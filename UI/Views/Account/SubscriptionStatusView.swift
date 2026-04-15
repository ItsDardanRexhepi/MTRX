// UI/Views/Account/SubscriptionStatusView.swift
// MTRX — Subscription Status

import SwiftUI

/// Shows the user's current subscription status and usage.
struct SubscriptionStatusView: View {
    @State private var gate = FeatureGate.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Current plan
                Section("Current Plan") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(gate.currentTier.displayName)
                                .font(.headline)
                            Text(gate.currentTier.priceDisplay)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Active")
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentPrimary, in: Capsule())
                    }
                }

                // Usage this month
                Section("Usage This Month") {
                    ForEach(countBasedFeatures, id: \.self) { feature in
                        usageRow(feature)
                    }
                }

                // Feature access
                Section("Feature Access") {
                    ForEach(booleanFeatures, id: \.self) { feature in
                        HStack {
                            Text(feature.displayName)
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: gate.isEnabled(feature)
                                  ? "checkmark.circle.fill"
                                  : "xmark.circle")
                                .foregroundStyle(gate.isEnabled(feature)
                                                 ? Color.accentPrimary : .secondary)
                        }
                    }
                }

                // Manage
                Section {
                    Button("Manage Subscription") {
                        Task {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                await UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var countBasedFeatures: [Feature] {
        [.contractConversions, .nftMints, .marketplaceListings, .governanceVotes]
    }

    private var booleanFeatures: [Feature] {
        [.advancedDashboard, .customAgentSkills, .teamAccounts, .whiteLabelBranding,
         .enterpriseAnalytics, .apiAccess, .prioritySupport, .earlyAccessComponents]
    }

    private func usageRow(_ feature: Feature) -> some View {
        let limit = feature.limit(for: gate.currentTier)
        let used = 0 // Replace with actual usage from gateway
        let total = limit ?? 0
        let progress = total > 0 ? Double(used) / Double(total) : 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(feature.displayName)
                    .font(.subheadline)
                Spacer()
                if let limit = limit {
                    Text("\(used) / \(limit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(used) / \u{221E}")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if limit != nil {
                ProgressView(value: progress)
                    .tint(progress > 0.8 ? .red : Color.accentPrimary)
            }
        }
    }
}
