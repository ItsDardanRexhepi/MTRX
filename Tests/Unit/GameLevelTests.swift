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
}
