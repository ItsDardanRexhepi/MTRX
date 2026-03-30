import GameKit

/// GameKit integration for Component 14 gaming — leaderboards, achievements, multiplayer
@MainActor
final class GameKitManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var localPlayer: GKLocalPlayer?

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if GKLocalPlayer.local.isAuthenticated {
                self?.isAuthenticated = true
                self?.localPlayer = GKLocalPlayer.local
            }
        }
    }

    // MARK: - Leaderboards
    func submitScore(_ score: Int, leaderboardID: String) async throws {
        try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                             leaderboardIDs: [leaderboardID])
    }

    func loadLeaderboard(id: String, scope: GKLeaderboard.PlayerScope = .global, range: NSRange = NSRange(1...25)) async throws -> [GKLeaderboard.Entry] {
        let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [id])
        guard let leaderboard = leaderboards.first else { return [] }
        let (_, entries, _) = try await leaderboard.loadEntries(for: scope, timeScope: .allTime, range: range)
        return entries
    }

    // MARK: - Achievements
    func reportAchievement(id: String, percentComplete: Double = 100.0) async throws {
        let achievement = GKAchievement(identifier: id)
        achievement.percentComplete = percentComplete
        achievement.showsCompletionBanner = true
        try await GKAchievement.report([achievement])
    }

    // MARK: - Multiplayer
    func findMatch(minPlayers: Int = 2, maxPlayers: Int = 4) async throws -> GKMatch {
        let request = GKMatchRequest()
        request.minPlayers = minPlayers
        request.maxPlayers = maxPlayers
        return try await GKMatchmaker.shared().findMatch(for: request)
    }
}
