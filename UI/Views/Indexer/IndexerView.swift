// IndexerView.swift
// MTRX
//
// On-chain indexer — query builder, saved queries, GraphQL translation, subgraph browser.

import SwiftUI

// MARK: - Data Models

struct QueryItem: Identifiable {
    let id = UUID()
    let name: String
    let lastRunAt: String?
}

struct SubgraphItem: Identifiable {
    let id = UUID()
    let name: String
    let protocol_: String
    let description: String
}

// MARK: - View Model

@MainActor
class IndexerViewModel: ObservableObject {
    @Published var queries: [QueryItem] = []
    @Published var queryInput: String = ""
    @Published var queryResult: String?
    @Published var subgraphs: [SubgraphItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isTranslating: Bool = false
    @Published var isRunning: Bool = false
    @Published var isDemo: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live subgraphs (global) + saved queries (per-wallet) from IndexerService; else demo.
        if PendingCredentials.isBackendConfigured {
            do {
                let liveSubgraphs = try await IndexerService.shared.getSubgraphs()
                subgraphs = liveSubgraphs.map { s in
                    SubgraphItem(name: s.name, protocol_: s.protocol_ ?? "", description: s.description)
                }
                if let address = MtrxSession.walletAddress {
                    let liveQueries = try await IndexerService.shared.getUserQueries(address: address)
                    queries = liveQueries.map { q in
                        QueryItem(name: q.name, lastRunAt: q.lastRunAt.map { Self.dateFormatter.string(from: $0) })
                    }
                } else {
                    queries = []
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live indexer data unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
            queries = IndexerViewModel.sampleQueries
            subgraphs = IndexerViewModel.sampleSubgraphs
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load indexer data."
            isLoading = false
        }
    }

    func translateToGraphQL() async {
        guard !queryInput.isEmpty else { return }
        isTranslating = true
        do {
            try await Task.sleep(for: .seconds(1))
            queryResult = """
            {
              swaps(
                first: 10,
                orderBy: timestamp,
                orderDirection: desc,
                where: { amountUSD_gt: "10000" }
              ) {
                id
                timestamp
                amountUSD
                token0 { symbol }
                token1 { symbol }
              }
            }
            """
            isTranslating = false
        } catch {
            isTranslating = false
        }
    }

    func runQuery() async {
        guard queryResult != nil else { return }
        isRunning = true
        do {
            try await Task.sleep(for: .seconds(1.5))
            queryResult = """
            {
              "data": {
                "swaps": [
                  {
                    "id": "0xabc...123",
                    "timestamp": "1718400000",
                    "amountUSD": "42150.00",
                    "token0": { "symbol": "WETH" },
                    "token1": { "symbol": "USDC" }
                  },
                  {
                    "id": "0xdef...456",
                    "timestamp": "1718399500",
                    "amountUSD": "18720.00",
                    "token0": { "symbol": "WBTC" },
                    "token1": { "symbol": "DAI" }
                  }
                ]
              }
            }
            """
            isRunning = false
        } catch {
            isRunning = false
        }
    }

    func loadSavedQuery(_ query: QueryItem) {
        queryInput = query.name
        queryResult = nil
    }

    static let sampleQueries: [QueryItem] = [
        QueryItem(name: "Top swaps by volume today", lastRunAt: "2h ago"),
        QueryItem(name: "All lending positions above $50k", lastRunAt: "1d ago"),
        QueryItem(name: "Recent governance proposals", lastRunAt: "3d ago"),
        QueryItem(name: "LP positions with impermanent loss", lastRunAt: nil)
    ]

    static let sampleSubgraphs: [SubgraphItem] = [
        SubgraphItem(name: "Uniswap V3", protocol_: "Uniswap", description: "DEX swaps, pools, and liquidity positions"),
        SubgraphItem(name: "Aave V3", protocol_: "Aave", description: "Lending markets, borrows, and liquidations"),
        SubgraphItem(name: "ENS", protocol_: "ENS", description: "Domain registrations, transfers, and renewals"),
        SubgraphItem(name: "Lido", protocol_: "Lido", description: "Staking deposits, withdrawals, and rewards"),
        SubgraphItem(name: "OpenSea", protocol_: "OpenSea", description: "NFT sales, listings, and transfers")
    ]
}

// MARK: - Indexer View

struct IndexerView: View {
    @StateObject private var viewModel = IndexerViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.queries.isEmpty {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.queries.isEmpty {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    indexerContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Indexer")
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

    private var indexerContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                savedQueriesSection
                queryBuilderSection
                if viewModel.queryResult != nil {
                    resultsSection
                }
                subgraphBrowserSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Saved Queries

    private var savedQueriesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Saved Queries")
                .padding(.horizontal, Spacing.contentPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(viewModel.queries) { query in
                        Button {
                            viewModel.loadSavedQuery(query)
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(query.name)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.labelPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                if let lastRun = query.lastRunAt {
                                    HStack(spacing: Spacing.xs) {
                                        Image(systemName: Symbols.clock)
                                            .font(.system(size: 10))
                                        Text(lastRun)
                                            .font(.mtrxCaption2)
                                    }
                                    .foregroundStyle(Color.labelTertiary)
                                } else {
                                    Text("Never run")
                                        .font(.mtrxCaption2)
                                        .foregroundStyle(Color.labelTertiary)
                                }
                            }
                            .frame(width: 160, alignment: .leading)
                            .padding(Spacing.ms)
                            .background(Color.surfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Query Builder

    private var queryBuilderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Query Builder")
                .padding(.horizontal, Spacing.contentPadding)

            MtrxCard(style: .glass, accentEdge: .leading) {
                VStack(spacing: Spacing.md) {
                    TextEditor(text: $viewModel.queryInput)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.labelPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, maxHeight: 160)
                        .padding(Spacing.sm)
                        .background(Color.surfaceOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                        .overlay(
                            Group {
                                if viewModel.queryInput.isEmpty {
                                    Text("Describe your query in natural language...")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(Color.labelPlaceholder)
                                        .padding(.horizontal, Spacing.sm + 5)
                                        .padding(.vertical, Spacing.sm + 8)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )

                    HStack(spacing: Spacing.sm) {
                        Button {
                            Task { await viewModel.translateToGraphQL() }
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: Symbols.wand)
                                    .font(.system(size: 14))
                                Text(viewModel.isTranslating ? "Translating..." : "Translate to GraphQL")
                            }
                        }
                        .buttonStyle(MtrxButtonStyle(
                            variant: .primary,
                            size: .compact,
                            isLoading: viewModel.isTranslating,
                            fullWidth: true
                        ))
                        .disabled(viewModel.queryInput.isEmpty || viewModel.isTranslating)
                        .opacity(viewModel.queryInput.isEmpty ? 0.5 : 1)

                        if viewModel.queryResult != nil {
                            Button {
                                Task { await viewModel.runQuery() }
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 12))
                                    Text(viewModel.isRunning ? "Running..." : "Run")
                                }
                            }
                            .buttonStyle(MtrxButtonStyle(
                                variant: .secondary,
                                size: .compact,
                                isLoading: viewModel.isRunning
                            ))
                            .disabled(viewModel.isRunning)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Results")
                .padding(.horizontal, Spacing.contentPadding)

            MtrxCard(style: .standard) {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(viewModel.queryResult ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.accentPrimary)
                        .padding(Spacing.sm)
                }
                .frame(maxHeight: 200)
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Subgraph Browser

    private var subgraphBrowserSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Subgraph Browser")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.subgraphs) { subgraph in
                MtrxCard(style: .standard) {
                    HStack(spacing: Spacing.ms) {
                        MtrxAvatar(
                            text: String(subgraph.protocol_.prefix(2)),
                            color: .accentPrimary,
                            size: 40
                        )

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                Text(subgraph.name)
                                    .font(.mtrxBodyBold)
                                    .foregroundStyle(Color.labelPrimary)
                                MtrxBadge(text: subgraph.protocol_, style: .accent)
                            }
                            Text(subgraph.description)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: Symbols.forward)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    IndexerView()
        .preferredColorScheme(.dark)
}
