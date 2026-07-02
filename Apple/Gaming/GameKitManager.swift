// GameKitManager.swift
// MTRX — Gaming
//
// Game Center (GameKit) for the mini-games: real GKLocalPlayer authentication,
// real leaderboard submission of genuine in-game scores, and achievements for
// real accomplishments. Scores are NEVER fabricated — they come straight from
// the engines. Best scores are persisted locally so they survive offline and
// when Game Center isn't signed in; submission happens only when authenticated.
//
// Honest states: not authenticated → an explicit "Sign in to Game Center"
// affordance (never fake leaderboard data); declined/unavailable → honest. The
// leaderboard / achievement IDs below must be configured in App Store Connect
// and the Game Center capability enabled on the App ID before scores actually
// post — until then submission fails soft and only the local best is kept.

import GameKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class GameKitManager {

    static let shared = GameKitManager()
    private init() {}

    enum AuthState { case unknown, authenticating, authenticated, unavailable }
    private(set) var authState: AuthState = .unknown
    private(set) var playerAlias: String?

    var isAuthenticated: Bool { authState == .authenticated }

    /// One leaderboard per game. Configure these EXACT IDs as Leaderboards in
    /// App Store Connect.
    enum GameID: String, CaseIterable {
        case solitaire, blocks, colorburst, merge2048, breakout, asteroids, arcade
        var leaderboardID: String { "mtrx.leaderboard.\(rawValue)" }
        var displayName: String {
            switch self {
            case .solitaire: return "Solitaire"
            case .blocks:    return BlockBrand.name   // user-facing brand; the leaderboard ID stays mtrx.leaderboard.blocks
            case .colorburst: return "Color Burst"
            case .merge2048: return "2048"
            case .breakout:  return "Brick Breaker"
            case .asteroids: return "Asteroid Storm"
            case .arcade:    return "Arcade"
            }
        }
    }

    /// Achievements for genuine accomplishments. Configure these IDs in ASC.
    enum Achievement: String {
        case firstPlay  = "mtrx.achievement.firstplay"
        case firstWin   = "mtrx.achievement.firstwin"
        case highRoller = "mtrx.achievement.highroller"   // a score ≥ 1000
    }

    // MARK: - Authentication

    /// Begin Game Center auth. GameKit calls the handler with a sign-in view
    /// controller when the user needs to sign in (we present it), authenticates
    /// silently if already signed in, or reports unavailable — all honest.
    func authenticate() {
        guard authState == .unknown || authState == .unavailable else { return }
        authState = .authenticating
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    Self.present(viewController)
                    return
                }
                if GKLocalPlayer.local.isAuthenticated {
                    self.authState = .authenticated
                    self.playerAlias = GKLocalPlayer.local.alias
                } else {
                    self.authState = .unavailable
                }
            }
        }
    }

    // MARK: - Scores (real, persisted locally + submitted when authenticated)

    func bestScore(_ game: GameID) -> Int {
        UserDefaults.standard.integer(forKey: "mtrx.best.\(game.rawValue)")
    }

    /// Record a finished game's REAL score: update the local best always, and
    /// submit to Game Center + report achievements only when authenticated.
    func recordGameOver(_ game: GameID, score: Int, won: Bool = false) {
        guard score > 0 else { return }
        let key = "mtrx.best.\(game.rawValue)"
        if score > UserDefaults.standard.integer(forKey: key) {
            UserDefaults.standard.set(score, forKey: key)
        }
        guard isAuthenticated else { return }
        Task {
            try? await GKLeaderboard.submitScore(score, context: 0,
                                                 player: GKLocalPlayer.local,
                                                 leaderboardIDs: [game.leaderboardID])
            await reportOnce(.firstPlay)
            if won { await reportOnce(.firstWin) }
            if score >= 1000 { await report(.highRoller) }
        }
    }

    /// One-time milestone: report (with banner) only the first time it's earned.
    private func reportOnce(_ achievement: Achievement) async {
        let flag = "mtrx.ach.\(achievement.rawValue)"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        await report(achievement)
    }

    private func report(_ achievement: Achievement, percent: Double = 100) async {
        let a = GKAchievement(identifier: achievement.rawValue)
        a.percentComplete = percent
        a.showsCompletionBanner = true
        try? await GKAchievement.report([a])
    }

    // MARK: - Game Center dashboard

    func showDashboard() {
        guard isAuthenticated else { return }
#if canImport(UIKit)
        let vc = GKGameCenterViewController(state: .leaderboards)
        vc.gameCenterDelegate = GameKitDashboardDelegate.shared
        Self.present(vc)
#endif
    }

#if canImport(UIKit)
    private static func present(_ vc: UIViewController) {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        top.present(vc, animated: true)
    }
#endif
}

#if canImport(UIKit)
/// Dismisses the Game Center dashboard when the user closes it.
final class GameKitDashboardDelegate: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameKitDashboardDelegate()
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
#endif
