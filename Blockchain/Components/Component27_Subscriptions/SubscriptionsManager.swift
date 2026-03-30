// SubscriptionsManager.swift
// MTRX Blockchain - Components - Subscriptions
//
// On-chain subscriptions: recurring payments, plan management, usage metering

import Foundation
import Combine

// MARK: - Data Models

struct SubscriptionPlan: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let providerAddress: String
    let price: Double
    let token: String
    let interval: SubscriptionInterval
    let features: [String]
    var isActive: Bool
    let trialDays: Int
    let contractAddress: String?
}

enum SubscriptionInterval: String, Codable {
    case weekly, monthly, quarterly, annually

    var seconds: TimeInterval {
        switch self {
        case .weekly: return 7 * 86400
        case .monthly: return 30 * 86400
        case .quarterly: return 90 * 86400
        case .annually: return 365 * 86400
        }
    }
}

struct Subscription: Identifiable, Codable {
    let id: String
    let planId: String
    let subscriberAddress: String
    let startDate: Date
    var currentPeriodStart: Date
    var currentPeriodEnd: Date
    var status: SubscriptionStatus
    var cancelledAt: Date?
    let trialEndsAt: Date?
    var paymentHistory: [SubscriptionPayment]
}

enum SubscriptionStatus: String, Codable {
    case trialing, active, pastDue, cancelled, expired
}

struct SubscriptionPayment: Identifiable, Codable {
    let id: String
    let subscriptionId: String
    let amount: Double
    let token: String
    let periodStart: Date
    let periodEnd: Date
    let paidAt: Date
    let transactionHash: String?
    let status: PaymentResultStatus
}

enum PaymentResultStatus: String, Codable {
    case succeeded, failed, pending, refunded
}

enum SubscriptionError: Error, LocalizedError {
    case planNotFound(String)
    case subscriptionNotFound(String)
    case alreadySubscribed
    case paymentFailed(String)
    case alreadyCancelled
    case planInactive

    var errorDescription: String? {
        switch self {
        case .planNotFound(let id): return "Plan not found: \(id)"
        case .subscriptionNotFound(let id): return "Subscription not found: \(id)"
        case .alreadySubscribed: return "Already subscribed to this plan."
        case .paymentFailed(let r): return "Payment failed: \(r)"
        case .alreadyCancelled: return "Subscription already cancelled."
        case .planInactive: return "Subscription plan is not active."
        }
    }
}

// MARK: - SubscriptionsManager

final class SubscriptionsManager: ObservableObject {

    static let shared = SubscriptionsManager()

    @Published private(set) var plans: [SubscriptionPlan] = []
    @Published private(set) var activeSubscriptions: [Subscription] = []

    private var planStore: [String: SubscriptionPlan] = [:]
    private var subscriptionStore: [String: Subscription] = [:]

    // MARK: - Plan Management

    func createPlan(name: String, description: String, provider: String, price: Double, token: String, interval: SubscriptionInterval, features: [String], trialDays: Int = 0) async throws -> SubscriptionPlan {
        let plan = SubscriptionPlan(
            id: UUID().uuidString, name: name, description: description,
            providerAddress: provider, price: price, token: token,
            interval: interval, features: features, isActive: true,
            trialDays: trialDays, contractAddress: nil
        )
        planStore[plan.id] = plan
        await MainActor.run { plans.append(plan) }
        return plan
    }

    // MARK: - Subscription Lifecycle

    func subscribe(planId: String, subscriber: String) async throws -> Subscription {
        guard let plan = planStore[planId], plan.isActive else {
            throw SubscriptionError.planNotFound(planId)
        }

        let existing = subscriptionStore.values.first {
            $0.planId == planId && $0.subscriberAddress == subscriber && $0.status != .cancelled && $0.status != .expired
        }
        guard existing == nil else { throw SubscriptionError.alreadySubscribed }

        let now = Date()
        let trialEnd = plan.trialDays > 0 ? now.addingTimeInterval(TimeInterval(plan.trialDays * 86400)) : nil
        let periodStart = trialEnd ?? now
        let periodEnd = periodStart.addingTimeInterval(plan.interval.seconds)

        let subscription = Subscription(
            id: UUID().uuidString, planId: planId, subscriberAddress: subscriber,
            startDate: now, currentPeriodStart: periodStart, currentPeriodEnd: periodEnd,
            status: trialEnd != nil ? .trialing : .active,
            cancelledAt: nil, trialEndsAt: trialEnd, paymentHistory: []
        )

        subscriptionStore[subscription.id] = subscription
        await MainActor.run { activeSubscriptions.append(subscription) }
        return subscription
    }

    func cancelSubscription(subscriptionId: String) async throws {
        guard var sub = subscriptionStore[subscriptionId] else {
            throw SubscriptionError.subscriptionNotFound(subscriptionId)
        }
        guard sub.status != .cancelled else { throw SubscriptionError.alreadyCancelled }

        sub.status = .cancelled
        sub.cancelledAt = Date()
        subscriptionStore[subscriptionId] = sub

        await MainActor.run {
            if let idx = activeSubscriptions.firstIndex(where: { $0.id == subscriptionId }) {
                activeSubscriptions[idx] = sub
            }
        }
    }

    // MARK: - Renewals

    func processRenewal(subscriptionId: String) async throws -> SubscriptionPayment {
        guard var sub = subscriptionStore[subscriptionId] else {
            throw SubscriptionError.subscriptionNotFound(subscriptionId)
        }
        guard let plan = planStore[sub.planId] else {
            throw SubscriptionError.planNotFound(sub.planId)
        }

        let payment = SubscriptionPayment(
            id: UUID().uuidString, subscriptionId: subscriptionId,
            amount: plan.price, token: plan.token,
            periodStart: sub.currentPeriodEnd,
            periodEnd: sub.currentPeriodEnd.addingTimeInterval(plan.interval.seconds),
            paidAt: Date(), transactionHash: nil, status: .succeeded
        )

        sub.currentPeriodStart = payment.periodStart
        sub.currentPeriodEnd = payment.periodEnd
        sub.status = .active
        sub.paymentHistory.append(payment)
        subscriptionStore[subscriptionId] = sub

        return payment
    }

    // MARK: - Queries

    func getSubscriptions(for user: String) -> [Subscription] {
        subscriptionStore.values.filter { $0.subscriberAddress == user && $0.status != .expired }
    }

    func isSubscribed(user: String, planId: String) -> Bool {
        subscriptionStore.values.contains {
            $0.subscriberAddress == user && $0.planId == planId && ($0.status == .active || $0.status == .trialing)
        }
    }

    func getNextPaymentDate(subscriptionId: String) -> Date? {
        subscriptionStore[subscriptionId]?.currentPeriodEnd
    }
}
