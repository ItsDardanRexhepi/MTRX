// OnChainSubscriptionsView.swift
// MTRX
//
// On-chain subscriptions — active subscriptions, service offerings, tier selection, subscribe/cancel flows.

import SwiftUI

// MARK: - Data Models

struct SubItem: Identifiable {
    let id = UUID()
    let service: String
    let tier: String
    let price: String
    let token: String
    let nextBillingDate: String
    let status: String
}

struct OfferingItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let tiers: [TierItem]
}

struct TierItem: Identifiable {
    let id = UUID()
    let name: String
    let price: String
    let features: [String]
}

// MARK: - View Model

@MainActor
class OnChainSubscriptionsViewModel: ObservableObject {
    @Published var subscriptions: [SubItem] = []
    @Published var offerings: [OfferingItem] = []
    @Published var selectedTab: String = "My Subscriptions"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isCancelling: Bool = false
    @Published var isSubscribing: Bool = false
    @Published var isDemo: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM dd, yyyy"; return f
    }()

    let tabs = ["My Subscriptions", "Browse"]

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live offerings (global) + subscriptions (per-wallet) from
        // OnChainSubscriptionService when configured; else demo.
        if PendingCredentials.isBackendConfigured {
            do {
                let liveOfferings = try await OnChainSubscriptionService.shared.getSubscriptionOfferings()
                offerings = liveOfferings.map { o in
                    OfferingItem(
                        name: o.name, description: o.description,
                        tiers: o.tiers.map { t in
                            TierItem(name: t.name, price: "\(t.price.formatted()) \(t.token)/mo", features: t.features)
                        }
                    )
                }
                if let address = MtrxSession.walletAddress {
                    let liveSubs = try await OnChainSubscriptionService.shared.getUserSubscriptions(address: address)
                    subscriptions = liveSubs.map { s in
                        SubItem(
                            service: s.service, tier: s.tier,
                            price: "\(s.price.formatted()) \(s.token)/mo", token: s.token,
                            nextBillingDate: Self.dateFormatter.string(from: s.nextBillingDate),
                            status: s.status
                        )
                    }
                } else {
                    subscriptions = []
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live subscription data unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
            subscriptions = OnChainSubscriptionsViewModel.sampleSubscriptions
            offerings = OnChainSubscriptionsViewModel.sampleOfferings
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load subscriptions."
            isLoading = false
        }
    }

    func cancel(subscription: SubItem) async {
        isCancelling = true
        do {
            try await Task.sleep(for: .seconds(1))
            subscriptions.removeAll { $0.id == subscription.id }
            isCancelling = false
        } catch {
            isCancelling = false
        }
    }

    func subscribe(to offering: OfferingItem, tier: TierItem) async {
        isSubscribing = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            let sub = SubItem(
                service: offering.name,
                tier: tier.name,
                price: tier.price,
                token: "USDC",
                nextBillingDate: "May 13, 2026",
                status: "Active"
            )
            subscriptions.append(sub)
            isSubscribing = false
            selectedTab = "My Subscriptions"
        } catch {
            isSubscribing = false
        }
    }

    static let sampleSubscriptions: [SubItem] = [
        SubItem(service: "Chainlink Data Feeds", tier: "Pro", price: "50 USDC/mo", token: "USDC", nextBillingDate: "May 01, 2026", status: "Active"),
        SubItem(service: "The Graph Indexing", tier: "Growth", price: "120 GRT/mo", token: "GRT", nextBillingDate: "May 05, 2026", status: "Active"),
        SubItem(service: "Alchemy RPC", tier: "Basic", price: "25 USDC/mo", token: "USDC", nextBillingDate: "Apr 28, 2026", status: "Expiring")
    ]

    static let sampleOfferings: [OfferingItem] = [
        OfferingItem(
            name: "Chainlink Data Feeds",
            description: "Real-time price feeds and verifiable random functions",
            tiers: [
                TierItem(name: "Basic", price: "20 USDC/mo", features: ["5 price feeds", "1K requests/day", "Community support"]),
                TierItem(name: "Pro", price: "50 USDC/mo", features: ["25 price feeds", "10K requests/day", "VRF access", "Priority support"]),
                TierItem(name: "Enterprise", price: "200 USDC/mo", features: ["Unlimited feeds", "Unlimited requests", "Custom oracles", "SLA guarantee"])
            ]
        ),
        OfferingItem(
            name: "Filecoin Storage",
            description: "Decentralized storage with verifiable proofs",
            tiers: [
                TierItem(name: "Starter", price: "10 FIL/mo", features: ["100 GB storage", "Basic retrieval", "90-day deals"]),
                TierItem(name: "Pro", price: "40 FIL/mo", features: ["1 TB storage", "Fast retrieval", "365-day deals", "Redundancy"]),
                TierItem(name: "Scale", price: "150 FIL/mo", features: ["10 TB storage", "Instant retrieval", "Custom deal terms", "Multi-miner"])
            ]
        ),
        OfferingItem(
            name: "Gelato Automation",
            description: "Automated smart contract execution and keeper network",
            tiers: [
                TierItem(name: "Free", price: "Free", features: ["100 executions/mo", "Basic scheduling", "Community support"]),
                TierItem(name: "Pro", price: "30 USDC/mo", features: ["5K executions/mo", "Advanced triggers", "Multi-chain", "Priority queue"])
            ]
        )
    ]
}

// MARK: - On-Chain Subscriptions View

struct OnChainSubscriptionsView: View {
    @StateObject private var viewModel = OnChainSubscriptionsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.subscriptions.isEmpty && viewModel.offerings.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.subscriptions.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    subscriptionContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Subscriptions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.load() }
        }
    }

    // MARK: - Content

    private var subscriptionContent: some View {
        VStack(spacing: 0) {
            tabPicker
            tabBody
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(viewModel.tabs, id: \.self) { tab in
                    MtrxChip(
                        label: tab,
                        isSelected: viewModel.selectedTab == tab
                    ) {
                        withAnimation(Motion.springDefault) {
                            viewModel.selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Tab Body

    @ViewBuilder
    private var tabBody: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                switch viewModel.selectedTab {
                case "My Subscriptions":
                    mySubscriptionsTab
                case "Browse":
                    browseTab
                default:
                    EmptyView()
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - My Subscriptions Tab

    @ViewBuilder
    private var mySubscriptionsTab: some View {
        if viewModel.subscriptions.isEmpty {
            MtrxEmptyState(
                icon: "creditcard.fill",
                title: "No Active Subscriptions",
                message: "Browse available services and subscribe to get started.",
                actionLabel: "Browse Services"
            ) {
                viewModel.selectedTab = "Browse"
            }
        } else {
            ForEach(viewModel.subscriptions) { sub in
                subscriptionCard(sub)
            }
        }
    }

    private func subscriptionCard(_ sub: SubItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(sub.service)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        HStack(spacing: Spacing.xs) {
                            MtrxBadge(text: sub.tier, style: .accent)
                            MtrxBadge(
                                text: sub.status,
                                style: sub.status == "Active" ? .success : .warning
                            )
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text(sub.price)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.accentPrimary)
                        Text(sub.token)
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                MtrxDivider()

                HStack {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.calendar)
                            .font(.system(size: 12))
                        Text("Next billing: \(sub.nextBillingDate)")
                            .font(.mtrxCaption1)
                    }
                    .foregroundStyle(Color.labelSecondary)

                    Spacer()

                    Button {
                        Task { await viewModel.cancel(subscription: sub) }
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .destructive, size: .compact))
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Browse Tab

    private var browseTab: some View {
        ForEach(viewModel.offerings) { offering in
            offeringCard(offering)
        }
    }

    private func offeringCard(_ offering: OfferingItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(offering.name)
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                Text(offering.description)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
            .padding(.horizontal, Spacing.contentPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(offering.tiers) { tier in
                        tierCard(tier, offering: offering)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    private func tierCard(_ tier: TierItem, offering: OfferingItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(tier.name)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Text(tier.price)
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.accentPrimary)
            }

            MtrxDivider()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(tier.features, id: \.self) { feature in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.complete)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.statusSuccess)
                        Text(feature)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
            }

            Button {
                Task { await viewModel.subscribe(to: offering, tier: tier) }
            } label: {
                Text(viewModel.isSubscribing ? "Subscribing..." : "Subscribe")
            }
            .buttonStyle(MtrxButtonStyle(
                variant: .primary,
                size: .compact,
                isLoading: viewModel.isSubscribing,
                fullWidth: true
            ))
        }
        .frame(width: 200)
        .padding(Spacing.cardPadding)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
    }
}

// MARK: - Preview

#Preview {
    OnChainSubscriptionsView()
        .preferredColorScheme(.dark)
}
