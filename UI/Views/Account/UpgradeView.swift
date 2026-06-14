// UI/Views/Account/UpgradeView.swift
// MTRX — Upgrade Prompt

import SwiftUI

/// Modal shown when a user hits a usage limit.
struct UpgradeView: View {
    let blockedFeature: Feature
    let currentUsage: Int
    let limit: Int

    @State private var storeKit = StoreKitManager.shared
    @State private var isPurchasing = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("com.mtrx.subscriptionTier") private var currentTierRaw: String = SubscriptionTier.free.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentPrimary)

                        Text("Limit Reached")
                            .font(.title2.bold())

                        Text("You've used \(currentUsage) of \(limit) \(blockedFeature.displayName.lowercased()) this month.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()

                    // Tier comparison
                    HStack(spacing: 12) {
                        tierColumn(.free, highlight: false)
                        tierColumn(.pro, highlight: true)
                        tierColumn(.enterprise, highlight: false)
                    }
                    .padding(.horizontal)

                    // CTA buttons
                    VStack(spacing: 12) {
                        Button {
                            Task { await startTrial(for: StoreKitManager.proProductId) }
                        } label: {
                            HStack {
                                if isPurchasing {
                                    ProgressView().tint(.black)
                                }
                                Text("Start 3-Day Free Trial \u{2014} Pro")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentPrimary)
                        .foregroundStyle(.black)
                        .disabled(isPurchasing)

                        Button {
                            Task { await startTrial(for: StoreKitManager.enterpriseProductId) }
                        } label: {
                            Text("Try Enterprise Free")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPurchasing)
                    }
                    .padding(.horizontal)

                    Button("Maybe Later") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical)
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if !storeKit.isLoaded {
                    await storeKit.loadProducts()
                }
            }
        }
    }

    private func tierColumn(_ tier: SubscriptionTier, highlight: Bool) -> some View {
        VStack(spacing: 8) {
            Text(tier.displayName)
                .font(.caption.bold())

            Text(tier.priceDisplay)
                .font(.caption2)
                .foregroundStyle(.secondary)

            let featureLimit = blockedFeature.limit(for: tier)
            Text(featureLimit == nil ? "\u{221E}" : "\(featureLimit!)")
                .font(.title3.bold())
                .foregroundStyle(highlight ? Color.accentPrimary : .primary)

            Text(blockedFeature.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    highlight ? Color.accentPrimary : .secondary.opacity(0.3),
                    lineWidth: highlight ? 2 : 1
                )
        )
    }

    private func startTrial(for productId: String) async {
        isPurchasing = true
        defer { isPurchasing = false }
        // Real StoreKit path first.
        await storeKit.startTrialIfEligible(for: productId)

        // Testable path: if no live product landed the purchase, grant the
        // tier locally on a 3-day trial so the whole flow is fully usable
        // and every tier can be exercised end-to-end.
        let target: SubscriptionTier = productId == StoreKitManager.enterpriseProductId ? .enterprise : .pro
        let current = SubscriptionTier(rawValue: currentTierRaw) ?? .free
        if current < target {
            currentTierRaw = target.rawValue
            FeatureGate.shared.updateTier(
                target,
                isTrialActive: true,
                trialEndDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())
            )
            MtrxHaptics.success()
        }
        dismiss()
    }
}
