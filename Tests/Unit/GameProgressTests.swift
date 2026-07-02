import XCTest
@testable import MTRX

/// Real tests for the shared mini-game level-progress store. Exercises the
/// actual GameProgress API against an in-memory key-value backend (no mocks of
/// success) so unlock gating, completion bitmask, persistence, and reset all
/// prove out deterministically.
@MainActor
final class GameProgressTests: XCTestCase {

    /// In-memory GameKVStore double — same contract the iCloud/UserDefaults
    /// backends satisfy.
    final class MemStore: GameKVStore {
        var dict: [String: Int64] = [:]
        func int64(forKey key: String) -> Int64 { dict[key] ?? 0 }
        func setInt64(_ value: Int64, forKey key: String) { dict[key] = value }
        func flush() {}
    }

    private func makeProgress() -> (GameProgress, MemStore) {
        let store = MemStore()
        return (GameProgress(store: store), store)
    }

    func testFreshGame_level1UnlockedRestLocked() {
        let (p, _) = makeProgress()
        XCTAssertEqual(p.totalLevels(for: .blocks), 50)
        XCTAssertEqual(p.unlockedLevel(for: .blocks), 1)
        XCTAssertTrue(p.isUnlocked(1, in: .blocks))
        XCTAssertFalse(p.isUnlocked(2, in: .blocks))
        XCTAssertFalse(p.isCompleted(1, in: .blocks))
        XCTAssertEqual(p.completedCount(for: .blocks), 0)
        XCTAssertEqual(p.highestCompletedLevel(for: .blocks), 0)
    }

    func testArcadeHasNoLevels() {
        let (p, _) = makeProgress()
        XCTAssertEqual(p.totalLevels(for: .arcade), 0)
        XCTAssertEqual(p.unlockedLevel(for: .arcade), 0)
        XCTAssertFalse(p.isUnlocked(1, in: .arcade))
        XCTAssertNil(p.recordCompletion(level: 1, in: .arcade))
    }

    func testCompletingLevelUnlocksNext() {
        let (p, _) = makeProgress()
        let unlocked = p.recordCompletion(level: 1, in: .solitaire)
        XCTAssertEqual(unlocked, 2)
        XCTAssertTrue(p.isCompleted(1, in: .solitaire))
        XCTAssertTrue(p.isUnlocked(2, in: .solitaire))
        XCTAssertFalse(p.isUnlocked(3, in: .solitaire))
        XCTAssertEqual(p.completedCount(for: .solitaire), 1)
        XCTAssertEqual(p.highestCompletedLevel(for: .solitaire), 1)
    }

    func testCompletingIsIdempotent() {
        let (p, _) = makeProgress()
        XCTAssertEqual(p.recordCompletion(level: 1, in: .breakout), 2)
        XCTAssertNil(p.recordCompletion(level: 1, in: .breakout))  // already done, no new unlock
        XCTAssertEqual(p.completedCount(for: .breakout), 1)
        XCTAssertEqual(p.unlockedLevel(for: .breakout), 2)
    }

    func testOutOfOrderCompletionDoesNotRegressUnlock() {
        let (p, _) = makeProgress()
        _ = p.recordCompletion(level: 1, in: .merge2048)
        _ = p.recordCompletion(level: 2, in: .merge2048)   // unlock -> 3
        XCTAssertEqual(p.unlockedLevel(for: .merge2048), 3)
        // Re-completing level 1 must NOT pull the unlock back down to 2.
        XCTAssertNil(p.recordCompletion(level: 1, in: .merge2048))
        XCTAssertEqual(p.unlockedLevel(for: .merge2048), 3)
    }

    func testFinalLevelCapsUnlock() {
        let (p, _) = makeProgress()
        let unlocked = p.recordCompletion(level: 50, in: .asteroids)
        // No level 51 to unlock — capped at total.
        XCTAssertNil(unlocked)
        XCTAssertTrue(p.isCompleted(50, in: .asteroids))
        XCTAssertEqual(p.highestCompletedLevel(for: .asteroids), 50)
    }

    func testRejectsOutOfRangeLevels() {
        let (p, _) = makeProgress()
        XCTAssertNil(p.recordCompletion(level: 0, in: .colorburst))
        XCTAssertNil(p.recordCompletion(level: 51, in: .colorburst))
        XCTAssertFalse(p.isCompleted(0, in: .colorburst))
        XCTAssertFalse(p.isCompleted(51, in: .colorburst))
    }

    func testProgressPersistsAcrossInstances() {
        let store = MemStore()
        let p1 = GameProgress(store: store)
        _ = p1.recordCompletion(level: 1, in: .blocks)
        _ = p1.recordCompletion(level: 2, in: .blocks)

        // A fresh store instance backed by the same KV data reads it back.
        let p2 = GameProgress(store: store)
        XCTAssertEqual(p2.unlockedLevel(for: .blocks), 3)
        XCTAssertTrue(p2.isCompleted(1, in: .blocks))
        XCTAssertTrue(p2.isCompleted(2, in: .blocks))
        XCTAssertEqual(p2.completedCount(for: .blocks), 2)
    }

    func testResetProgress() {
        let (p, _) = makeProgress()
        _ = p.recordCompletion(level: 1, in: .solitaire)
        _ = p.recordCompletion(level: 2, in: .solitaire)
        p.resetProgress(for: .solitaire)
        XCTAssertEqual(p.unlockedLevel(for: .solitaire), 1)
        XCTAssertEqual(p.completedCount(for: .solitaire), 0)
        XCTAssertFalse(p.isUnlocked(2, in: .solitaire))
    }

    func testPerGameIsolation() {
        let (p, _) = makeProgress()
        _ = p.recordCompletion(level: 1, in: .blocks)
        // Completing a level in one game must not touch another.
        XCTAssertEqual(p.completedCount(for: .solitaire), 0)
        XCTAssertEqual(p.unlockedLevel(for: .solitaire), 1)
    }

    func testRevisionBumpsOnMutation() {
        let (p, _) = makeProgress()
        let before = p.revision
        _ = p.recordCompletion(level: 1, in: .breakout)
        XCTAssertGreaterThan(p.revision, before)
    }
}
