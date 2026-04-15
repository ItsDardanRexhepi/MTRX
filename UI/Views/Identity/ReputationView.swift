// ReputationView.swift
// MTRX
//
// On-chain reputation score display with breakdown, leaderboard, and improvement actions.

import SwiftUI

// MARK: - View Model

final class ReputationViewModel: ObservableObject {

    // MARK: - Published State

    @Published var score: Int = 0
    @Published var breakdown: [ScoreComponent] = []
    @Published var leaderboard: [LeaderboardEntry] = []
    @Published var improvementActions: [ImprovementAction] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isEmpty: Bool = false

    // MARK: - Computed

    var tierLabel: String {
        switch score {
        case 800...: return "Trusted"
        case 600..<800: return "Established"
        case 400..<600: return "Building"
        case 200..<400: return "New"
        default: return "Unranked"
        }
    }

    var tierColor: Color {
        switch score {
        case 800...: return .green
        case 600..<800: return Color(red: 0.0, green: 0.675, blue: 0.694)
        case 400..<600: return .orange
        case 200..<400: return .yellow
        default: return .gray
        }
    }

    // MARK: - Load

    func loadReputation() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.score = 742
            self.breakdown = ScoreComponent.sampleData
            self.leaderboard = LeaderboardEntry.sampleData
            self.improvementActions = ImprovementAction.sampleData
            self.isEmpty = false
            self.isLoading = false
        }
    }
}

// MARK: - Models

struct ScoreComponent: Identifiable {
    let id = UUID()
    let name: String
    let score: Int
    let maxScore: Int
    let icon: String

    var percentage: Double {
        guard maxScore > 0 else { return 0 }
        return Double(score) / Double(maxScore)
    }

    static var sampleData: [ScoreComponent] {
        [
            ScoreComponent(name: "Transaction History", score: 210, maxScore: 250, icon: "arrow.left.arrow.right"),
            ScoreComponent(name: "Governance", score: 180, maxScore: 250, icon: "person.3.fill"),
            ScoreComponent(name: "Attestations", score: 192, maxScore: 250, icon: "checkmark.seal.fill"),
            ScoreComponent(name: "Longevity", score: 160, maxScore: 250, icon: "clock.fill"),
        ]
    }
}

struct LeaderboardEntry: Identifiable {
    let id = UUID()
    let rank: Int
    let address: String
    let score: Int
    let tier: String

    static var sampleData: [LeaderboardEntry] {
        [
            LeaderboardEntry(rank: 1, address: "0xA1b2...C3d4", score: 980, tier: "Trusted"),
            LeaderboardEntry(rank: 2, address: "0xE5f6...G7h8", score: 955, tier: "Trusted"),
            LeaderboardEntry(rank: 3, address: "0xI9j0...K1l2", score: 941, tier: "Trusted"),
            LeaderboardEntry(rank: 4, address: "0xM3n4...O5p6", score: 912, tier: "Trusted"),
            LeaderboardEntry(rank: 5, address: "0xQ7r8...S9t0", score: 898, tier: "Trusted"),
            LeaderboardEntry(rank: 6, address: "0xU1v2...W3x4", score: 871, tier: "Trusted"),
            LeaderboardEntry(rank: 7, address: "0xY5z6...A7b8", score: 855, tier: "Trusted"),
            LeaderboardEntry(rank: 8, address: "0xC9d0...E1f2", score: 830, tier: "Trusted"),
            LeaderboardEntry(rank: 9, address: "0xG3h4...I5j6", score: 808, tier: "Trusted"),
            LeaderboardEntry(rank: 10, address: "0xK7l8...M9n0", score: 791, tier: "Established"),
        ]
    }
}

struct ImprovementAction: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let points: Int
    let icon: String
    let difficulty: Difficulty

    enum Difficulty: String {
        case easy = "Easy"
        case medium = "Medium"
        case hard = "Hard"

        var color: Color {
            switch self {
            case .easy: return .green
            case .medium: return .orange
            case .hard: return .red
            }
        }
    }

    static var sampleData: [ImprovementAction] {
        [
            ImprovementAction(title: "Complete KYC Verification", description: "Verify your identity to earn attestation points.", points: 50, icon: "person.badge.shield.checkmark", difficulty: .easy),
            ImprovementAction(title: "Vote in 3 Governance Proposals", description: "Participate in DAO governance to build your score.", points: 30, icon: "hand.raised.fill", difficulty: .easy),
            ImprovementAction(title: "Execute 10 Transactions", description: "Build transaction history with consistent on-chain activity.", points: 25, icon: "arrow.left.arrow.right", difficulty: .medium),
            ImprovementAction(title: "Maintain Wallet 6+ Months", description: "Longevity accrues over time with continuous activity.", points: 40, icon: "clock.fill", difficulty: .medium),
            ImprovementAction(title: "Receive 5 Attestations", description: "Get attested by other verified users or institutions.", points: 60, icon: "checkmark.seal.fill", difficulty: .hard),
        ]
    }
}

// MARK: - View

struct ReputationView: View {
    @StateObject private var viewModel = ReputationViewModel()

    private let accentColor = Color(red: 0.0, green: 0.675, blue: 0.694)

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading reputation...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    mainContent
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reputation")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { viewModel.loadReputation() }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                scoreDisplay
                breakdownSection
                leaderboardSection
                improvementSection
            }
            .padding(Spacing.contentPadding)
        }
    }

    // MARK: - Score Display

    private var scoreDisplay: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 12)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.score) / 1000.0)
                    .stroke(viewModel.tierColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: Spacing.xs) {
                    Text("\(viewModel.score)")
                        .font(.mtrxMonoLarge)
                        .foregroundStyle(viewModel.tierColor)

                    Text("/ 1000")
                        .font(.mtrxCaption1)
                        .foregroundStyle(.secondary)
                }
            }

            Text(viewModel.tierLabel)
                .font(.mtrxTitle2)
                .foregroundStyle(viewModel.tierColor)

            Text("Your on-chain reputation score")
                .font(.mtrxSubheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Score Breakdown")
                .font(.mtrxTitle3)

            VStack(spacing: Spacing.ms) {
                ForEach(viewModel.breakdown) { component in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Image(systemName: component.icon)
                                .font(.subheadline)
                                .foregroundStyle(accentColor)
                                .frame(width: 24)

                            Text(component.name)
                                .font(.mtrxSubheadline)

                            Spacer()

                            Text("\(component.score)/\(component.maxScore)")
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(.secondary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(accentColor)
                                    .frame(width: geo.size.width * component.percentage, height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
            .mtrxCardStyle()
        }
    }

    // MARK: - Leaderboard

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Leaderboard")
                .font(.mtrxTitle3)

            VStack(spacing: 0) {
                ForEach(viewModel.leaderboard) { entry in
                    HStack {
                        Text("#\(entry.rank)")
                            .font(.mtrxHeadlineTabular)
                            .foregroundStyle(entry.rank <= 3 ? Color.orange : .secondary)
                            .frame(width: 36, alignment: .leading)

                        Text(entry.address)
                            .font(.mtrxMono)
                            .lineLimit(1)

                        Spacer()

                        Text("\(entry.score)")
                            .font(.mtrxHeadlineTabular)

                        Text(entry.tier)
                            .font(.mtrxCaption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.vertical, Spacing.sm)

                    if entry.rank != viewModel.leaderboard.last?.rank {
                        Divider()
                    }
                }
            }
            .mtrxCardStyle()
        }
    }

    // MARK: - Improvement Actions

    private var improvementSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Improve Your Score")
                .font(.mtrxTitle3)

            ForEach(viewModel.improvementActions) { action in
                HStack(alignment: .top, spacing: Spacing.ms) {
                    Image(systemName: action.icon)
                        .font(.title3)
                        .foregroundStyle(accentColor)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(action.title)
                            .font(.mtrxHeadline)

                        Text(action.description)
                            .font(.mtrxCaption1)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(action.difficulty.rawValue)
                                .font(.mtrxCaption2)
                                .foregroundStyle(action.difficulty.color)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 2)
                                .background(action.difficulty.color.opacity(0.12))
                                .clipShape(Capsule())

                            Spacer()

                            Text("+\(action.points) pts")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(accentColor)
                        }
                    }
                }
                .mtrxCardStyle()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ReputationView()
}
