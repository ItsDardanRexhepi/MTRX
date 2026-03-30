// ActivityKitManager.swift
// MTRX Apple Integration — Presence
//
// Dynamic Island live activities for real-time transaction tracking

import ActivityKit
import Foundation

// MARK: - Activity Attributes

struct MTRXTransactionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let status: String
        let progressPercent: Double
        let currentStep: String
        let amount: String
        let token: String
        let counterparty: String
        let estimatedCompletion: Date?
    }

    let transactionId: String
    let transactionType: String
    let startedAt: Date
}

// MARK: - ActivityKitManager

final class ActivityKitManager: ObservableObject {

    static let shared = ActivityKitManager()

    @Published private(set) var activeActivities: [String: String] = [:] // transactionId -> activityId

    // MARK: - Start Activity

    func startTransactionActivity(transactionId: String, type: String, amount: String, token: String, counterparty: String) throws -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw ActivityKitError.activitiesNotEnabled
        }

        let attributes = MTRXTransactionAttributes(
            transactionId: transactionId,
            transactionType: type,
            startedAt: Date()
        )

        let initialState = MTRXTransactionAttributes.ContentState(
            status: "Processing",
            progressPercent: 0.1,
            currentStep: "Submitting transaction",
            amount: amount,
            token: token,
            counterparty: counterparty,
            estimatedCompletion: Date().addingTimeInterval(30)
        )

        let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(300))

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            activeActivities[transactionId] = activity.id
            return activity.id
        } catch {
            throw ActivityKitError.startFailed(error.localizedDescription)
        }
    }

    // MARK: - Update Activity

    func updateTransactionProgress(transactionId: String, status: String, progress: Double, step: String) async throws {
        guard let activityId = activeActivities[transactionId] else {
            throw ActivityKitError.activityNotFound
        }

        let activities = Activity<MTRXTransactionAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityId }) else {
            throw ActivityKitError.activityNotFound
        }

        let updatedState = MTRXTransactionAttributes.ContentState(
            status: status,
            progressPercent: progress,
            currentStep: step,
            amount: activity.content.state.amount,
            token: activity.content.state.token,
            counterparty: activity.content.state.counterparty,
            estimatedCompletion: activity.content.state.estimatedCompletion
        )

        let content = ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(300))
        await activity.update(content)
    }

    // MARK: - End Activity

    func endTransactionActivity(transactionId: String, finalStatus: String) async throws {
        guard let activityId = activeActivities[transactionId] else {
            throw ActivityKitError.activityNotFound
        }

        let activities = Activity<MTRXTransactionAttributes>.activities
        guard let activity = activities.first(where: { $0.id == activityId }) else {
            throw ActivityKitError.activityNotFound
        }

        let finalState = MTRXTransactionAttributes.ContentState(
            status: finalStatus,
            progressPercent: 1.0,
            currentStep: "Complete",
            amount: activity.content.state.amount,
            token: activity.content.state.token,
            counterparty: activity.content.state.counterparty,
            estimatedCompletion: nil
        )

        let content = ActivityContent(state: finalState, staleDate: nil)
        await activity.end(content, dismissalPolicy: .after(.now + 30))
        activeActivities.removeValue(forKey: transactionId)
    }

    // MARK: - Cleanup

    func endAllActivities() async {
        for activity in Activity<MTRXTransactionAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activeActivities.removeAll()
    }
}

// MARK: - Errors

enum ActivityKitError: LocalizedError {
    case activitiesNotEnabled
    case startFailed(String)
    case activityNotFound
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .activitiesNotEnabled: return "Live Activities are not enabled."
        case .startFailed(let r): return "Failed to start activity: \(r)"
        case .activityNotFound: return "Activity not found."
        case .updateFailed(let r): return "Failed to update activity: \(r)"
        }
    }
}
