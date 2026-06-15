// GamingView.swift
// MTRX
//
// Gaming hub — browse games with asset/player counts, view and register for tournaments, prize pools.

import SwiftUI

// MARK: - Data Models

struct GameItem: Identifiable {
    let id = UUID()
    let name: String
    let assetCount: Int
    let playerCount: Int
    var kind: GameKind = .targets
    var accent: Color = Color(red: 0.0, green: 0.675, blue: 0.694)
}

/// The three demo mechanics — each game card maps to one so they play
/// differently. All run fully on-device, no network.
enum GameKind {
    case targets    // tap the glowing nodes before they fade
    case reflex     // tap only when the ring turns teal
    case sequence   // repeat the growing pattern
    case solitaire  // full Klondike solitaire
    case blocks     // falling-block stacking puzzle
    case match3     // swap-to-match gem puzzle
}

struct TournamentItem: Identifiable {
    let id = UUID()
    let name: String
    let prizePool: String
    let entryFee: String
    let players: Int
    let status: String
}

// MARK: - View Model

@MainActor
class GamingViewModel: ObservableObject {
    @Published var games: [GameItem] = []
    @Published var tournaments: [TournamentItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(600))
            games = GamingViewModel.sampleGames
            tournaments = GamingViewModel.sampleTournaments
            isLoading = false
        } catch {
            errorMessage = "Unable to load gaming data."
            isLoading = false
        }
    }

    static let sampleGames: [GameItem] = [
        GameItem(name: "Solitaire", assetCount: 2_450, playerCount: 18_300, kind: .solitaire, accent: Color(red: 0.13, green: 0.83, blue: 0.93)),
        GameItem(name: "Tetris", assetCount: 8_120, playerCount: 42_600, kind: .blocks, accent: Color(red: 0.62, green: 0.40, blue: 0.96)),
        GameItem(name: "Color Burst", assetCount: 5_680, playerCount: 31_200, kind: .match3, accent: Color(red: 0.98, green: 0.37, blue: 0.45)),
        GameItem(name: "Chain Racers", assetCount: 1_890, playerCount: 12_400, kind: .reflex, accent: Color(red: 0.98, green: 0.65, blue: 0.15)),
        GameItem(name: "DeFi Dungeons", assetCount: 3_340, playerCount: 9_800, kind: .sequence, accent: Color(red: 0.97, green: 0.30, blue: 0.55)),
        GameItem(name: "Meta Tactics", assetCount: 4_100, playerCount: 22_700, kind: .reflex, accent: Color(red: 0.25, green: 0.55, blue: 0.98))
    ]

    static let sampleTournaments: [TournamentItem] = [
        TournamentItem(name: "Solitaire Championship", prizePool: "5,000 USDC", entryFee: "25 USDC", players: 128, status: "Open"),
        TournamentItem(name: "Tetris Season Finals", prizePool: "10,000 USDC", entryFee: "50 USDC", players: 256, status: "Open"),
        TournamentItem(name: "Color Burst Siege", prizePool: "2,500 USDC", entryFee: "10 USDC", players: 64, status: "In Progress"),
        TournamentItem(name: "Chain Racers Grand Prix", prizePool: "3,000 USDC", entryFee: "15 USDC", players: 32, status: "Upcoming")
    ]
}

// MARK: - Gaming View

struct GamingView: View {
    @StateObject private var viewModel = GamingViewModel()
    @State private var activeGame: GameItem?

    private let gridColumns = [
        GridItem(.flexible(), spacing: Spacing.sm),
        GridItem(.flexible(), spacing: Spacing.sm)
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.games.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.games.isEmpty {
                    errorState(message: error)
                } else if viewModel.games.isEmpty && viewModel.tournaments.isEmpty {
                    emptyState
                } else {
                    gamingContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Gaming")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.load() }
            .fullScreenCover(item: $activeGame) { game in
                GameRunnerView(game: game)
            }
        }
    }

    // MARK: - Content

    private var gamingContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                gamesGrid
                tournamentsSection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Games Grid

    private var gamesGrid: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Games")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            LazyVGrid(columns: gridColumns, spacing: Spacing.sm) {
                ForEach(viewModel.games) { game in
                    gameCard(game)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    private func gameCard(_ game: GameItem) -> some View {
        Button {
            MtrxHaptics.impact(.medium)
            activeGame = game
        } label: {
            MtrxCard(style: .standard) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [game.accent.opacity(0.25), game.accent.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(height: 60)

                        gameGlyph(game)

                        // A clear "playable" cue in the corner.
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(game.accent)
                                    .padding(6)
                            }
                            Spacer()
                        }
                    }

                    Text(game.name)
                        .font(.mtrxBodyBold)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.md) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "cube.fill")
                                .font(.system(size: 10))
                            Text(formatCount(game.assetCount))
                                .font(.mtrxCaption2)
                        }
                        .foregroundStyle(Color.labelSecondary)

                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                            Text(formatCount(game.playerCount))
                                .font(.mtrxCaption2)
                        }
                        .foregroundStyle(Color.labelSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tournaments Section

    private var tournamentsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tournaments")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.tournaments) { tournament in
                tournamentCard(tournament)
            }
        }
    }

    private func tournamentCard(_ tournament: TournamentItem) -> some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tournament.name)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(Color.labelPrimary)
                        Text(tournamentStatusLabel(tournament.status))
                            .font(.mtrxCaption2)
                            .foregroundStyle(tournamentStatusColor(tournament.status))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(tournament.prizePool)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.priceUp)
                        Text("Prize Pool")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                HStack {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 12))
                        Text("Entry: \(tournament.entryFee)")
                            .font(.mtrxCaption1)
                    }
                    .foregroundStyle(Color.labelSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12))
                        Text("\(tournament.players) players")
                            .font(.mtrxCaption1)
                    }
                    .foregroundStyle(Color.labelSecondary)
                }

                if tournament.status == "Open" {
                    Button {
                        // Register action
                    } label: {
                        Text("Register")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(Color(red: 0.0, green: 0.675, blue: 0.694))
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundStyle(Color.labelTertiary)
            Text("No games available")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
            Text("Games and tournaments will appear here once they are launched on the platform.")
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// The icon shown on each game tile — a playing card for the solitaire
    /// game, a block for the stacking puzzle, a controller for the rest.
    @ViewBuilder
    private func gameGlyph(_ game: GameItem) -> some View {
        switch game.kind {
        case .solitaire:
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 23, height: 31)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.black)
            }
        case .blocks:
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 24))
                .foregroundStyle(game.accent)
        case .match3:
            // A little cluster of candy gems.
            let gemColors: [Color] = [
                Color(red: 0.98, green: 0.37, blue: 0.45),
                Color(red: 0.37, green: 0.71, blue: 0.99),
                Color(red: 0.99, green: 0.84, blue: 0.39),
                Color(red: 0.41, green: 0.87, blue: 0.55)
            ]
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    gemDot(gemColors[0]); gemDot(gemColors[1])
                }
                HStack(spacing: 4) {
                    gemDot(gemColors[2]); gemDot(gemColors[3])
                }
            }
        default:
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 24))
                .foregroundStyle(game.accent)
        }
    }

    private func gemDot(_ color: Color) -> some View {
        Circle()
            .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 0.8))
            .frame(width: 13, height: 13)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func tournamentStatusColor(_ status: String) -> Color {
        switch status {
        case "Open": return .priceUp
        case "In Progress": return .statusWarning
        case "Upcoming": return .statusInfo
        default: return .labelTertiary
        }
    }

    private func tournamentStatusLabel(_ status: String) -> String {
        switch status {
        case "Open": return "Registration Open"
        case "In Progress": return "In Progress"
        case "Upcoming": return "Coming Soon"
        default: return status
        }
    }
}

// MARK: - Preview

#Preview {
    GamingView()
        .preferredColorScheme(.dark)
}
