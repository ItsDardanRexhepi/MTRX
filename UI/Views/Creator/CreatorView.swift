// CreatorView.swift
// MTRX
//
// Creator dashboard — token management cards, launch new token sheet, revenue tracking section.

import SwiftUI

// MARK: - Data Models

struct CreatorTokenItem: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let currentPrice: String
    let holders: Int
    let volume24h: String
}

// MARK: - View Model

@MainActor
class CreatorViewModel: ObservableObject {
    @Published var tokens: [CreatorTokenItem] = []
    @Published var showLaunch: Bool = false
    @Published var launchName: String = ""
    @Published var launchSymbol: String = ""
    @Published var launchPrice: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isLaunching: Bool = false
    @Published var isDemo: Bool = false

    var totalRevenue: String {
        // CreatorService has no revenue endpoint; this figure is illustrative and
        // only shown in demo mode (the screen carries a DemoBadge then).
        isDemo ? "$4,832.50" : "—"
    }

    var totalHolders: Int {
        tokens.reduce(0) { $0 + $1.holders }
    }

    var canLaunch: Bool {
        !launchName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !launchSymbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        !launchPrice.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(launchPrice) != nil
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live creator tokens from CreatorService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let live = try await CreatorService.shared.getCreatorTokens(address: address)
                tokens = live.map { t in
                    CreatorTokenItem(
                        name: t.name, symbol: t.symbol,
                        currentPrice: "$" + t.currentPrice.formatted(.number.precision(.fractionLength(4))),
                        holders: t.holders,
                        volume24h: "$" + t.volume24h.formatted(.number.precision(.fractionLength(2)))
                    )
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live creator data unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(600))
            tokens = CreatorViewModel.sampleTokens
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load creator data."
            isLoading = false
        }
    }

    func launchToken() async {
        guard canLaunch else { return }
        isLaunching = true

        do {
            try await Task.sleep(for: .seconds(1.5))
            let newToken = CreatorTokenItem(
                name: launchName,
                symbol: launchSymbol.uppercased(),
                currentPrice: "$\(launchPrice)",
                holders: 0,
                volume24h: "$0.00"
            )
            tokens.insert(newToken, at: 0)
            launchName = ""
            launchSymbol = ""
            launchPrice = ""
            isLaunching = false
            showLaunch = false
        } catch {
            isLaunching = false
        }
    }

    static let sampleTokens: [CreatorTokenItem] = [
        CreatorTokenItem(name: "Neon Pass", symbol: "NEON", currentPrice: "$2.45", holders: 1_240, volume24h: "$18,350"),
        CreatorTokenItem(name: "Verse Token", symbol: "VERSE", currentPrice: "$0.85", holders: 3_820, volume24h: "$42,100"),
        CreatorTokenItem(name: "Pixel Gem", symbol: "PXG", currentPrice: "$0.12", holders: 680, volume24h: "$5,230")
    ]
}

// MARK: - Creator View

struct CreatorView: View {
    @StateObject private var viewModel = CreatorViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.tokens.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.tokens.isEmpty {
                    errorState(message: error)
                } else {
                    creatorContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Creator")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showLaunch = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                    }
                    .accessibilityLabel("Launch creator token")
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showLaunch) {
                launchTokenSheet
            }
        }
    }

    // MARK: - Content

    private var creatorContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                revenueSection
                tokenDashboard
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Revenue Section

    private var revenueSection: some View {
        MtrxCard(style: .glass, accentEdge: .top) {
            VStack(spacing: Spacing.md) {
                Text("Creator Revenue")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)

                Text(viewModel.totalRevenue)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.xs) {
                        Text("\(viewModel.tokens.count)")
                            .font(.mtrxHeadlineTabular)
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                        Text("Tokens")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }

                    Rectangle()
                        .fill(Color.separatorStandard)
                        .frame(width: 1, height: 30)

                    VStack(spacing: Spacing.xs) {
                        Text(formatCount(viewModel.totalHolders))
                            .font(.mtrxHeadlineTabular)
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                        Text("Holders")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Token Dashboard

    private var tokenDashboard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your Tokens")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            if viewModel.tokens.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.tokens) { token in
                    tokenCard(token)
                }
            }
        }
    }

    private func tokenCard(_ token: CreatorTokenItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.675, blue: 0.694).opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(token.symbol.prefix(2))
                                .font(.system(size: 15, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.name)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(token.symbol)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    Text(token.currentPrice)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Holders")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12))
                            Text(formatCount(token.holders))
                                .font(.mtrxCaptionBold)
                        }
                        .foregroundStyle(Color.labelPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("24h Volume")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(token.volume24h)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.priceUp)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Launch Token Sheet

    private var launchTokenSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Token Name
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Token Name")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        TextField("My Token", text: $viewModel.launchName)
                            .font(.mtrxBody)
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Token Symbol
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Symbol")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        TextField("TKN", text: $viewModel.launchSymbol)
                            .font(.mtrxBody)
                            .textInputAutocapitalization(.characters)
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Initial Price
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Initial Price (USD)")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        HStack {
                            Text("$")
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelTertiary)
                            TextField("0.00", text: $viewModel.launchPrice)
                                .font(.mtrxMono)
                                .keyboardType(.decimalPad)
                        }
                        .padding(Spacing.ms)
                        .background(Color.surfaceOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.launchToken() }
                } label: {
                    Text(viewModel.isLaunching ? "Launching..." : "Launch Token")
                        .font(.mtrxBodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.ms)
                        .background(viewModel.canLaunch ? Color(red: 0.0, green: 0.675, blue: 0.694) : Color.labelTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .disabled(!viewModel.canLaunch || viewModel.isLaunching)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Launch Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        viewModel.showLaunch = false
                    }
                    .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.labelTertiary)
            Text("No tokens created")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
            Text("Launch your first token to start building your creator economy.")
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.showLaunch = true
            } label: {
                Text("Launch Token")
                    .font(.mtrxBodyBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.ms)
                    .background(Color(red: 0.0, green: 0.675, blue: 0.694))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusWarning)
            Text(message)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.675, blue: 0.694))
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Preview

#Preview {
    CreatorView()
        .preferredColorScheme(.dark)
}
