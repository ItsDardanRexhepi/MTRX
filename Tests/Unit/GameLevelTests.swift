import XCTest
@testable import MTRX

/// Deterministic checks on the per-game level tables/formulas. Levels must be
/// well-formed (positive targets, sane budgets), difficulty must be
/// non-decreasing, and the pinned milestone overrides must hold. As each game
/// gains its 50-level system its assertions are appended here.
final class GameLevelTests: XCTestCase {

    // MARK: - ColorBurst (#2)

    func testColorBurst_allLevelsWellFormed() {
        for n in 1...50 {
            let l = ColorBurstLevels.level(n)
            XCTAssertGreaterThan(l.target, 0, "level \(n) target must be positive")
            XCTAssertGreaterThanOrEqual(l.moves, 16, "level \(n) must give a usable move budget")
            XCTAssertLessThanOrEqual(l.moves, 26)
        }
    }

    func testColorBurst_targetNonDecreasing() {
        // Ignoring the pinned boss overrides, the base target must never regress.
        var prev = 0
        for n in 1...50 where n != 25 && n != 50 {
            let t = ColorBurstLevels.level(n).target
            XCTAssertGreaterThanOrEqual(t, prev, "target regressed at level \(n)")
            prev = t
        }
    }

    func testColorBurst_moveBudgetNonIncreasing() {
        var prev = Int.max
        for n in 1...50 {
            let m = ColorBurstLevels.level(n).moves
            XCTAssertLessThanOrEqual(m, prev, "move budget went UP at level \(n)")
            prev = m
        }
    }

    func testColorBurst_milestoneOverrides() {
        XCTAssertEqual(ColorBurstLevels.level(25).target, 2600, "mid-boss override")
        XCTAssertEqual(ColorBurstLevels.level(50).target, 5200, "final-boss override")
    }

    func testColorBurst_clampsOutOfRange() {
        XCTAssertEqual(ColorBurstLevels.level(0).target, ColorBurstLevels.level(1).target)
        XCTAssertEqual(ColorBurstLevels.level(99).target, ColorBurstLevels.level(50).target)
    }

    // MARK: - 2048 Gauntlet (#3)

    func test2048_allLevelsWellFormed() {
        let validTargets: Set<Int> = [64, 128, 256, 512, 1024]
        for n in 1...50 {
            let l = Game2048Levels.level(n)
            XCTAssertTrue(validTargets.contains(l.targetTile), "level \(n) target \(l.targetTile) must be a supported tile")
            XCTAssertGreaterThanOrEqual(l.moves, 20, "level \(n) needs a usable move budget")
            XCTAssertLessThanOrEqual(l.blockers.count, 2, "level \(n) blockers capped for a 4x4 board")
            for (r, c) in l.blockers {
                XCTAssertTrue((0..<4).contains(r) && (0..<4).contains(c), "blocker off-board at level \(n)")
            }
            // Blockers must be distinct and not overlap each other.
            let keys = Set(l.blockers.map { $0.0 * 4 + $0.1 })
            XCTAssertEqual(keys.count, l.blockers.count, "duplicate blocker at level \(n)")
        }
    }

    func test2048_earlyLevelsHaveNoBlockers() {
        // Tiers 1–2 (levels 1–20) stay blocker-free so newcomers ramp gently.
        for n in 1...20 {
            XCTAssertTrue(Game2048Levels.level(n).blockers.isEmpty, "level \(n) should have no blockers")
        }
    }

    func test2048_targetTileNonDecreasingWithinBlockerFreeLevels() {
        // Ignoring blocker-eased levels, target must never regress.
        var prev = 0
        for n in 1...50 where Game2048Levels.level(n).blockers.isEmpty {
            let t = Game2048Levels.level(n).targetTile
            XCTAssertGreaterThanOrEqual(t, prev, "target regressed at level \(n)")
            prev = t
        }
    }

    func test2048_blockedLevelsEaseHighTargets() {
        // A blocked level in tiers 4–5 (would be 512/1024) is eased one tier
        // down so the cramped board stays winnable.
        for n in 31...50 where !Game2048Levels.level(n).blockers.isEmpty {
            let l = Game2048Levels.level(n)
            XCTAssertLessThanOrEqual(l.targetTile, 512, "blocked high level \(n) should be eased")
        }
    }

    func test2048_clampsOutOfRange() {
        XCTAssertEqual(Game2048Levels.level(0).targetTile, Game2048Levels.level(1).targetTile)
        XCTAssertEqual(Game2048Levels.level(99).targetTile, Game2048Levels.level(50).targetTile)
    }
}
