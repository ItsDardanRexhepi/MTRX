// GameProgress.swift
// MTRX — Core/Gaming
//
// The single, shared level-progress / unlock layer for all six mini-games.
// Built ONCE and reused — no game re-implements persistence. Tracks, per game,
// which levels are unlocked and which are completed, and persists via iCloud
// Key-Value Store when available (falling back to UserDefaults) so progress
// follows the player across devices — the same house pattern as WalletSync.
//
// The store is objective-agnostic: it records "level N of game G is
// completed / unlocked" and nothing about WHAT a level means. Each game
// defines its own objective (target score, wave, board, deal difficulty).

import Foundation
import Combine

/// Minimal key-value backend so the store can be driven by iCloud KVS,
/// UserDefaults, or an in-memory double in tests. Values are Int64 because a
/// 50-level completion bitmask needs up to 50 bits.
protocol GameKVStore: AnyObject {
    func int64(forKey key: String) -> Int64
    func setInt64(_ value: Int64, forKey key: String)
    func flush()
}

final class UserDefaultsGameStore: GameKVStore {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func int64(forKey key: String) -> Int64 { Int64(defaults.integer(forKey: key)) }
    func setInt64(_ value: Int64, forKey key: String) { defaults.set(Int(value), forKey: key) }
    func flush() {}
}

final class CloudGameStore: GameKVStore {
    private let store = NSUbiquitousKeyValueStore.default
    func int64(forKey key: String) -> Int64 { store.longLong(forKey: key) }
    func setInt64(_ value: Int64, forKey key: String) { store.set(value, forKey: key) }
    func flush() { store.synchronize() }
}

@MainActor
final class GameProgress: ObservableObject {

    static let shared = GameProgress()

    /// All six mini-games ship with 50 levels. The three built-in arcade
    /// mechanics stay endless (no level progression), so they report 0.
    static let levelsPerGame = 50

    /// Bumped on every mutation so SwiftUI views re-render.
    @Published private(set) var revision = 0

    private let store: GameKVStore
    private var cache: [String: State] = [:]

    private struct State {
        var unlockedLevel: Int      // highest level the player may start (>=1)
        var completedMask: Int64    // bit (L-1) set == level L completed
    }

    /// Cloud when available (entitlement + signed-in account), else local —
    /// matching WalletSync. Tests inject an in-memory double.
    init(store: GameKVStore? = nil) {
        if let store {
            self.store = store
        } else if FileManager.default.ubiquityIdentityToken != nil {
            self.store = CloudGameStore()
        } else {
            self.store = UserDefaultsGameStore()
        }
    }

    // MARK: - Queries

    func totalLevels(for game: GameKitManager.GameID) -> Int {
        game == .arcade ? 0 : Self.levelsPerGame
    }

    /// Highest level the player is allowed to start (1-based). Level 1 is
    /// always unlocked for a levelled game.
    func unlockedLevel(for game: GameKitManager.GameID) -> Int {
        guard totalLevels(for: game) > 0 else { return 0 }
        return max(1, state(for: game).unlockedLevel)
    }

    func isUnlocked(_ level: Int, in game: GameKitManager.GameID) -> Bool {
        level >= 1 && level <= unlockedLevel(for: game)
    }

    func isCompleted(_ level: Int, in game: GameKitManager.GameID) -> Bool {
        guard level >= 1, level <= totalLevels(for: game) else { return false }
        return state(for: game).completedMask & (Int64(1) << (level - 1)) != 0
    }

    func completedCount(for game: GameKitManager.GameID) -> Int {
        state(for: game).completedMask.nonzeroBitCount
    }

    /// Highest completed level, or 0 if none.
    func highestCompletedLevel(for game: GameKitManager.GameID) -> Int {
        let mask = state(for: game).completedMask
        return mask == 0 ? 0 : (64 - mask.leadingZeroBitCount)
    }

    // MARK: - Mutation

    /// Record a level as beaten. Marks it completed and unlocks the next level
    /// (capped at the game's total). Idempotent — completing a level twice is a
    /// no-op beyond the first. Returns the newly-unlocked level, if any.
    @discardableResult
    func recordCompletion(level: Int, in game: GameKitManager.GameID) -> Int? {
        let total = totalLevels(for: game)
        guard total > 0, (1...total).contains(level) else { return nil }

        var s = state(for: game)
        let alreadyDone = s.completedMask & (Int64(1) << (level - 1)) != 0
        s.completedMask |= (Int64(1) << (level - 1))

        // Completing level L unlocks L+1. There is nothing beyond the last
        // level, so beating the final level unlocks nothing new (returns nil).
        let nextLevel = level + 1
        let unlockedSomething = nextLevel <= total && nextLevel > s.unlockedLevel
        if unlockedSomething { s.unlockedLevel = nextLevel }

        guard !alreadyDone || unlockedSomething else { return nil }
        write(game, s)
        return unlockedSomething ? nextLevel : nil
    }

    func resetProgress(for game: GameKitManager.GameID) {
        write(game, State(unlockedLevel: 1, completedMask: 0))
    }

    func resetAll() {
        for game in GameKitManager.GameID.allCases where totalLevels(for: game) > 0 {
            resetProgress(for: game)
        }
    }

    // MARK: - Persistence

    private func state(for game: GameKitManager.GameID) -> State {
        if let cached = cache[game.rawValue] { return cached }
        let loaded = State(
            unlockedLevel: Int(store.int64(forKey: unlockedKey(game))),
            completedMask: store.int64(forKey: completedKey(game))
        )
        // A fresh game (never persisted) reports unlockedLevel 0 → normalize to 1.
        let normalized = State(unlockedLevel: max(1, loaded.unlockedLevel),
                               completedMask: loaded.completedMask)
        cache[game.rawValue] = normalized
        return normalized
    }

    private func write(_ game: GameKitManager.GameID, _ s: State) {
        cache[game.rawValue] = s
        store.setInt64(Int64(s.unlockedLevel), forKey: unlockedKey(game))
        store.setInt64(s.completedMask, forKey: completedKey(game))
        store.flush()
        revision &+= 1
    }

    private func unlockedKey(_ game: GameKitManager.GameID) -> String {
        "com.mtrx.gameProgress.\(game.rawValue).unlocked"
    }
    private func completedKey(_ game: GameKitManager.GameID) -> String {
        "com.mtrx.gameProgress.\(game.rawValue).completedMask"
    }
}
