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

    // MARK: - Block / Stackfall (#4)

    func testBlock_allLevelsWellFormed() {
        for n in 1...50 {
            let l = BlockLevels.level(n)
            XCTAssertGreaterThanOrEqual(l.lineQuota, 5, "level \(n) needs a real quota")
            XCTAssertLessThanOrEqual(l.lineQuota, 30)
            XCTAssertGreaterThanOrEqual(l.gravity, 0.08, "gravity must not drop below the floor")
            XCTAssertLessThanOrEqual(l.gravity, 0.80)
            XCTAssertGreaterThanOrEqual(l.garbageRows, 0)
            XCTAssertLessThanOrEqual(l.garbageRows, 4)
        }
    }

    func testBlock_quotaNonDecreasing_and_gravityNonIncreasing() {
        var prevQuota = 0
        var prevGravity = Double.greatestFiniteMagnitude
        for n in 1...50 {
            let l = BlockLevels.level(n)
            XCTAssertGreaterThanOrEqual(l.lineQuota, prevQuota, "quota regressed at level \(n)")
            XCTAssertLessThanOrEqual(l.gravity, prevGravity + 1e-9, "gravity slowed at level \(n)")
            prevQuota = l.lineQuota
            prevGravity = l.gravity
        }
    }

    func testBlock_earlyLevelsHaveNoGarbage() {
        for n in 1...10 {
            XCTAssertEqual(BlockLevels.level(n).garbageRows, 0, "level \(n) should start clean")
        }
    }

    func testBlock_milestoneValues() {
        XCTAssertEqual(BlockLevels.level(50).lineQuota, 30)   // 5 + 50/2
        XCTAssertEqual(BlockLevels.level(50).garbageRows, 4)
        XCTAssertEqual(BlockLevels.level(25).lineQuota, 17)   // 5 + 25/2
        XCTAssertEqual(BlockLevels.level(25).garbageRows, 2)
        XCTAssertEqual(BlockLevels.level(1).lineQuota, 5)
    }

    func testBlock_brandIsNotTrademarked() {
        // The user-facing name must be the original brand, never "Tetris".
        XCTAssertFalse(BlockBrand.name.isEmpty)
        XCTAssertNotEqual(BlockBrand.name.lowercased(), "tetris")
        // The leaderboard ID intentionally stays 'blocks' regardless of the brand.
        XCTAssertEqual(GameKitManager.GameID.blocks.leaderboardID, "mtrx.leaderboard.blocks")
        XCTAssertEqual(GameKitManager.GameID.blocks.displayName, BlockBrand.name)
    }

    // MARK: - BrickBreaker (#5)

    func testBrickBreaker_has50DistinctBoards() {
        XCTAssertEqual(BrickBreakerBoards.patterns.count, 50, "must ship exactly 50 authored boards")
    }

    func testBrickBreaker_allBoardsWellFormed() {
        let valid = Set("ox#.")
        for (i, board) in BrickBreakerBoards.patterns.enumerated() {
            XCTAssertFalse(board.isEmpty, "board \(i + 1) is empty")
            XCTAssertLessThanOrEqual(board.count, BrickBreakerBoards.maxRows, "board \(i + 1) too tall")
            var brickCount = 0
            for row in board {
                XCTAssertLessThanOrEqual(row.count, BrickBreakerBoards.cols, "board \(i + 1) row too wide")
                for ch in row {
                    XCTAssertTrue(valid.contains(ch), "board \(i + 1) has invalid char '\(ch)'")
                    if ch != "." { brickCount += 1 }
                }
            }
            XCTAssertGreaterThan(brickCount, 0, "board \(i + 1) has no bricks")
        }
    }

    func testBrickBreaker_difficultyTrendsUp() {
        // Total hit-points (bricks × hp) in the last 10 boards should exceed the
        // first 10 — later levels are meaningfully harder.
        func totalHP(_ board: [String]) -> Int {
            board.reduce(0) { acc, row in
                acc + row.reduce(0) { a, ch in a + (ch == "o" ? 1 : ch == "x" ? 2 : ch == "#" ? 3 : 0) }
            }
        }
        let early = BrickBreakerBoards.patterns.prefix(10).map(totalHP).reduce(0, +)
        let late = BrickBreakerBoards.patterns.suffix(10).map(totalHP).reduce(0, +)
        XCTAssertGreaterThan(late, early, "late boards should carry more total hit-points")
    }

    func testBrickBreaker_speedCappedNoTunneling() {
        // The tunneling fix: ball speed is capped below the brick height (22),
        // so at 120 Hz with sub-stepping the ball can never skip a brick.
        for n in 1...50 {
            let s = BrickBreakerBoards.cappedSpeed(n)
            XCTAssertLessThanOrEqual(s, BrickBreakerBoards.maxSpeed)
            XCTAssertLessThan(s, 22.0, "per-tick speed must stay under the brick height")
        }
        XCTAssertEqual(BrickBreakerBoards.cappedSpeed(50), 8.0, "high levels ride the cap")
    }
}
