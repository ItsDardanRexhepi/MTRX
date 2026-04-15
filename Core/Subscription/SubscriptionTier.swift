// Core/Subscription/SubscriptionTier.swift
// MTRX — Subscription Tier Definitions
//
// Three-tier subscription system:
//   Free ($0)       — Default. Generous limits, on-device CoreML, local wallet, full privacy.
//   Pro             — Removes most limits, priority Trinity, advanced dashboard, custom skills.
//   Enterprise      — Unlimited everything, teams, white-label, API access, audit logs.
//
// All tiers still pay automatic on-chain platform fees (PAC, NFT 10%, DAO treasury, etc.)
// that route to NeoSafe.

import Foundation
import SwiftData

// MARK: - Subscription Tier

/// The three subscription tiers available in MTRX.
enum SubscriptionTier: String, Codable, CaseIterable, Comparable {
    case free       = "free"
    case pro        = "pro"
    case enterprise = "enterprise"

    /// StoreKit product identifiers configured in App Store Connect.
    var productId: String? {
        switch self {
        case .free:       return nil
        case .pro:        return "com.opnmatrx.mtrx.pro.monthly"
        case .enterprise: return "com.opnmatrx.mtrx.enterprise.monthly"
        }
    }

    /// Display name shown in the UI.
    var displayName: String {
        switch self {
        case .free:       return "Free"
        case .pro:        return "Pro"
        case .enterprise: return "Enterprise"
        }
    }

    /// Monthly price as displayed to the user.
    /// Actual pricing is managed in App Store Connect.
    var priceDisplay: String {
        switch self {
        case .free:       return "Free"
        case .pro:        return "Pro"
        case .enterprise: return "Enterprise"
        }
    }

    /// Short description for marketing/upgrade prompts.
    var tagline: String {
        switch self {
        case .free:
            return "Full access to all 50+ components with generous limits"
        case .pro:
            return "Remove limits, priority Trinity, advanced dashboard & custom skills"
        case .enterprise:
            return "Unlimited everything, teams, white-label, API access & audit logs"
        }
    }

    /// Numeric level for comparison (free=0, pro=1, enterprise=2).
    var level: Int {
        switch self {
        case .free:       return 0
        case .pro:        return 1
        case .enterprise: return 2
        }
    }

    /// Whether this tier is a paid tier (has a StoreKit product).
    var isPaid: Bool { self != .free }

    /// Whether this tier offers a 3-day free trial.
    var hasTrialOffer: Bool { isPaid }

    /// Trial duration in days (both paid tiers get 3 days).
    var trialDays: Int { isPaid ? 3 : 0 }

    // MARK: Comparable

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.level < rhs.level
    }
}

// MARK: - Feature Definitions

/// Every gated feature in the app.
enum Feature: String, CaseIterable {
    // --- Usage Limits (Free tier has caps) ---
    case contractConversions          // 5/month free, 100 pro, unlimited enterprise
    case contractDeployments          // 3/month free, 50 pro, unlimited enterprise
    case nftMints                     // 3/month free, 100 pro, unlimited enterprise
    case nftCollections               // 1/month free, 20 pro, unlimited enterprise
    case monthlyLoanVolume            // $5k free, $500k pro, unlimited enterprise
    case activeLoans                  // 3 free, 50 pro, unlimited enterprise
    case marketplaceListings          // 2/month free, 100 pro, unlimited enterprise
    case insurancePolicies            // 2/month free, 20 pro, unlimited enterprise
    case insuranceCoverage            // $50k free, $1M pro, unlimited enterprise
    case governanceVotes              // 10/month free, 500 pro, unlimited enterprise
    case governanceProposals          // 2/month free, 50 pro, unlimited enterprise
    case securitiesTrades             // 10/month free, 500 pro, unlimited enterprise
    case attestationsPerMonth         // 10 free, 500 pro, unlimited enterprise
    case agentsRegistered             // 2 free, 20 pro, unlimited enterprise
    case daosCreated                  // 1 free, 10 pro, unlimited enterprise
    case fundraisingCampaigns         // 1/month free, 10 pro, unlimited enterprise
    case rwaAssets                    // 2/month free, 25 pro, unlimited enterprise

    // --- Pro Features ---
    case priorityTrinity              // Priority Trinity responses
    case extendedContextMemory        // Longer conversation context
    case advancedDashboard            // Dashboard with exports
    case customAgentSkills            // Custom Trinity skills & saved workflows
    case earlyAccessComponents        // Early access to new components

    // --- Enterprise Features ---
    case teamAccounts                 // Multi-user team accounts
    case whiteLabelBranding           // Custom branding
    case advancedGovernanceTools      // Advanced governance tooling
    case enterpriseAnalytics          // Enterprise analytics & audit logs
    case apiAccess                    // Direct API access
    case prioritySupport              // Priority support channel
    case customComponentDev           // Custom component development

    /// Human-readable display name for UI.
    var displayName: String {
        switch self {
        case .contractConversions: return "Contract Conversions"
        case .contractDeployments: return "Contract Deployments"
        case .nftMints: return "NFT Mints"
        case .nftCollections: return "NFT Collections"
        case .monthlyLoanVolume: return "Monthly Loan Volume"
        case .activeLoans: return "Active Loans"
        case .marketplaceListings: return "Marketplace Listings"
        case .insurancePolicies: return "Insurance Policies"
        case .insuranceCoverage: return "Insurance Coverage"
        case .governanceVotes: return "Governance Votes"
        case .governanceProposals: return "Governance Proposals"
        case .securitiesTrades: return "Securities Trades"
        case .attestationsPerMonth: return "Attestations"
        case .agentsRegistered: return "Agents Registered"
        case .daosCreated: return "DAOs Created"
        case .fundraisingCampaigns: return "Fundraising Campaigns"
        case .rwaAssets: return "RWA Assets"
        case .priorityTrinity: return "Priority Trinity"
        case .extendedContextMemory: return "Extended Memory"
        case .advancedDashboard: return "Advanced Dashboard"
        case .customAgentSkills: return "Custom Skills"
        case .earlyAccessComponents: return "Early Access"
        case .teamAccounts: return "Team Accounts"
        case .whiteLabelBranding: return "White Label"
        case .advancedGovernanceTools: return "Governance Tools"
        case .enterpriseAnalytics: return "Enterprise Analytics"
        case .apiAccess: return "API Access"
        case .prioritySupport: return "Priority Support"
        case .customComponentDev: return "Custom Components"
        }
    }

    /// The minimum tier required to access this feature.
    var minimumTier: SubscriptionTier {
        switch self {
        // Usage limits exist at all tiers (just different caps)
        case .contractConversions, .contractDeployments,
             .nftMints, .nftCollections, .monthlyLoanVolume,
             .activeLoans, .marketplaceListings, .insurancePolicies,
             .insuranceCoverage, .governanceVotes, .governanceProposals,
             .securitiesTrades, .attestationsPerMonth, .agentsRegistered,
             .daosCreated, .fundraisingCampaigns, .rwaAssets:
            return .free

        // Pro-only features
        case .priorityTrinity, .extendedContextMemory,
             .advancedDashboard, .customAgentSkills,
             .earlyAccessComponents:
            return .pro

        // Enterprise-only features
        case .teamAccounts, .whiteLabelBranding,
             .advancedGovernanceTools, .enterpriseAnalytics,
             .apiAccess, .prioritySupport, .customComponentDev:
            return .enterprise
        }
    }

    /// Usage limit for each tier. nil = unlimited.
    func limit(for tier: SubscriptionTier) -> Int? {
        switch self {
        case .contractConversions:
            switch tier {
            case .free: return 5; case .pro: return 100; case .enterprise: return nil
            }
        case .contractDeployments:
            switch tier {
            case .free: return 3; case .pro: return 50; case .enterprise: return nil
            }
        case .nftMints:
            switch tier {
            case .free: return 3; case .pro: return 100; case .enterprise: return nil
            }
        case .nftCollections:
            switch tier {
            case .free: return 1; case .pro: return 20; case .enterprise: return nil
            }
        case .monthlyLoanVolume:
            switch tier {
            case .free: return 5_000; case .pro: return 500_000; case .enterprise: return nil
            }
        case .activeLoans:
            switch tier {
            case .free: return 3; case .pro: return 50; case .enterprise: return nil
            }
        case .marketplaceListings:
            switch tier {
            case .free: return 2; case .pro: return 100; case .enterprise: return nil
            }
        case .insurancePolicies:
            switch tier {
            case .free: return 2; case .pro: return 20; case .enterprise: return nil
            }
        case .insuranceCoverage:
            switch tier {
            case .free: return 50_000; case .pro: return 1_000_000; case .enterprise: return nil
            }
        case .governanceVotes:
            switch tier {
            case .free: return 10; case .pro: return 500; case .enterprise: return nil
            }
        case .governanceProposals:
            switch tier {
            case .free: return 2; case .pro: return 50; case .enterprise: return nil
            }
        case .securitiesTrades:
            switch tier {
            case .free: return 10; case .pro: return 500; case .enterprise: return nil
            }
        case .attestationsPerMonth:
            switch tier {
            case .free: return 10; case .pro: return 500; case .enterprise: return nil
            }
        case .agentsRegistered:
            switch tier {
            case .free: return 2; case .pro: return 20; case .enterprise: return nil
            }
        case .daosCreated:
            switch tier {
            case .free: return 1; case .pro: return 10; case .enterprise: return nil
            }
        case .fundraisingCampaigns:
            switch tier {
            case .free: return 1; case .pro: return 10; case .enterprise: return nil
            }
        case .rwaAssets:
            switch tier {
            case .free: return 2; case .pro: return 25; case .enterprise: return nil
            }
        default:
            return nil // Boolean features, no numeric limit
        }
    }
}

// MARK: - Persisted Subscription State (SwiftData)

/// On-device subscription state stored via SwiftData.
@Model
final class SubscriptionState {
    var tierRawValue: String
    var isTrialActive: Bool
    var trialStartDate: Date?
    var trialEndDate: Date?
    var subscriptionStartDate: Date?
    var lastVerifiedDate: Date
    var originalTransactionId: String?

    /// Monthly usage counters (reset on the 1st of each month).
    var usageCounters: [String: Int]
    var usageResetDate: Date

    init() {
        self.tierRawValue = SubscriptionTier.free.rawValue
        self.isTrialActive = false
        self.trialStartDate = nil
        self.trialEndDate = nil
        self.subscriptionStartDate = nil
        self.lastVerifiedDate = Date()
        self.originalTransactionId = nil
        self.usageCounters = [:]
        self.usageResetDate = SubscriptionState.nextResetDate()
    }

    var tier: SubscriptionTier {
        get { SubscriptionTier(rawValue: tierRawValue) ?? .free }
        set { tierRawValue = newValue.rawValue }
    }

    /// Effective tier — during trial, this is the paid tier; after trial expires, falls back to free.
    var effectiveTier: SubscriptionTier {
        if isTrialActive, let end = trialEndDate, Date() < end {
            return tier
        }
        if tier.isPaid && !isTrialActive {
            return tier
        }
        if isTrialActive, let end = trialEndDate, Date() >= end {
            // Trial expired — fall back to free
            return .free
        }
        return tier
    }

    /// Days remaining in trial (0 if not in trial).
    var trialDaysRemaining: Int {
        guard isTrialActive, let end = trialEndDate else { return 0 }
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        return max(0, remaining)
    }

    /// Increment a usage counter and return the new count.
    @discardableResult
    func incrementUsage(_ feature: Feature) -> Int {
        resetIfNeeded()
        let key = feature.rawValue
        let current = usageCounters[key] ?? 0
        usageCounters[key] = current + 1
        return current + 1
    }

    /// Get current usage count for a feature.
    func currentUsage(_ feature: Feature) -> Int {
        resetIfNeeded()
        return usageCounters[feature.rawValue] ?? 0
    }

    /// Reset counters if we've passed the reset date.
    private func resetIfNeeded() {
        if Date() >= usageResetDate {
            usageCounters = [:]
            usageResetDate = SubscriptionState.nextResetDate()
        }
    }

    /// Calculate the next 1st-of-month reset date.
    static func nextResetDate() -> Date {
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month], from: now)
        comps.month! += 1
        comps.day = 1
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? now.addingTimeInterval(30 * 24 * 3600)
    }
}
