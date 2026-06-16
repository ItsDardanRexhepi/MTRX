// OraclesView.swift
// MTRX
//
// Oracle data feeds — price feeds, subscriptions, alert creation, real-time data monitoring.

import SwiftUI

// MARK: - Data Models

struct FeedItem: Identifiable {
    let id = UUID()
    let name: String
    let pair: String
    let currentValue: String
    let lastUpdated: String
    var isSubscribed: Bool
}

// MARK: - View Model

@MainActor
class OraclesViewModel: ObservableObject {
    @Published var feeds: [FeedItem] = []
    @Published var subscribedFeeds: [FeedItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live feeds from the gateway; fall back to samples if it isn't up.
        if let live = try? await MTRXAPIClient.shared.oracleFeeds(), !live.feeds.isEmpty {
            feeds = live.feeds.map {
                FeedItem(name: $0.name, pair: $0.pair, currentValue: $0.currentValue,
                         lastUpdated: $0.lastUpdated, isSubscribed: $0.isSubscribed ?? false)
            }
            subscribedFeeds = feeds.filter(\.isSubscribed)
            isLoading = false
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
            feeds = OraclesViewModel.sampleFeeds
            subscribedFeeds = feeds.filter(\.isSubscribed)
            isLoading = false
        } catch {
            errorMessage = "Unable to load oracle feeds."
            isLoading = false
        }
    }

    func toggleSubscription(for feed: FeedItem) async {
        do {
            try await Task.sleep(for: .milliseconds(400))
            if let idx = feeds.firstIndex(where: { $0.id == feed.id }) {
                let updated = FeedItem(
                    name: feed.name,
                    pair: feed.pair,
                    currentValue: feed.currentValue,
                    lastUpdated: feed.lastUpdated,
                    isSubscribed: !feed.isSubscribed
                )
                feeds[idx] = updated
                subscribedFeeds = feeds.filter(\.isSubscribed)
            }
        } catch { }
    }

    static let sampleFeeds: [FeedItem] = [
        FeedItem(name: "Chainlink ETH/USD", pair: "ETH/USD", currentValue: "$3,842.15", lastUpdated: "2s ago", isSubscribed: true),
        FeedItem(name: "Chainlink BTC/USD", pair: "BTC/USD", currentValue: "$97,231.40", lastUpdated: "3s ago", isSubscribed: true),
        FeedItem(name: "Pyth SOL/USD", pair: "SOL/USD", currentValue: "$182.67", lastUpdated: "1s ago", isSubscribed: false),
        FeedItem(name: "Chainlink LINK/USD", pair: "LINK/USD", currentValue: "$18.42", lastUpdated: "5s ago", isSubscribed: false),
        FeedItem(name: "Pyth AVAX/USD", pair: "AVAX/USD", currentValue: "$41.83", lastUpdated: "2s ago", isSubscribed: true),
        FeedItem(name: "UMA ETH/BTC", pair: "ETH/BTC", currentValue: "0.0395", lastUpdated: "8s ago", isSubscribed: false),
        FeedItem(name: "Chainlink MATIC/USD", pair: "MATIC/USD", currentValue: "$0.89", lastUpdated: "4s ago", isSubscribed: false),
        FeedItem(name: "API3 DAI/USD", pair: "DAI/USD", currentValue: "$1.0001", lastUpdated: "6s ago", isSubscribed: false)
    ]
}

// MARK: - Oracles View

struct OraclesView: View {
    @StateObject private var viewModel = OraclesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.feeds.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.feeds.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    oracleContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Oracles")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
        }
    }

    // MARK: - Content

    private var oracleContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                if !viewModel.subscribedFeeds.isEmpty {
                    subscribedSection
                }
                allFeedsSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Subscribed Feeds

    private var subscribedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Subscribed Feeds", subtitle: "\(viewModel.subscribedFeeds.count) active")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.subscribedFeeds) { feed in
                feedCard(feed, isSubscribedSection: true)
            }
        }
    }

    // MARK: - All Feeds

    private var allFeedsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "All Feeds")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.feeds) { feed in
                feedCard(feed, isSubscribedSection: false)
            }
        }
    }

    // MARK: - Feed Card

    private func feedCard(_ feed: FeedItem, isSubscribedSection: Bool) -> some View {
        MtrxCard(style: isSubscribedSection ? .glass : .standard, accentEdge: isSubscribedSection ? .leading : nil) {
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.ms) {
                    MtrxAvatar(
                        text: String(feed.pair.prefix(3)),
                        color: .accentPrimary,
                        size: 40
                    )

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(feed.name)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        HStack(spacing: Spacing.xs) {
                            Text(feed.pair)
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.accentPrimary)
                            Text("\u{2022}")
                                .foregroundStyle(Color.labelTertiary)
                            Text(feed.lastUpdated)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelTertiary)
                        }
                    }

                    Spacer()

                    Text(feed.currentValue)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }

                HStack(spacing: Spacing.sm) {
                    Button {
                        // Create alert shortcut
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: Symbols.notification)
                                .font(.system(size: 12))
                            Text("Create Alert")
                                .font(.mtrxCaptionBold)
                        }
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))

                    Spacer()

                    Button {
                        Task { await viewModel.toggleSubscription(for: feed) }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: feed.isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 14))
                            Text(feed.isSubscribed ? "Subscribed" : "Subscribe")
                                .font(.mtrxCaptionBold)
                        }
                    }
                    .buttonStyle(MtrxButtonStyle(
                        variant: feed.isSubscribed ? .primary : .secondary,
                        size: .compact
                    ))
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }
}

// MARK: - Preview

#Preview {
    OraclesView()
        .preferredColorScheme(.dark)
}
