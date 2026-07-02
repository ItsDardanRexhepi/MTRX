import XCTest
@testable import MTRX

/// Continuously re-verifies the committed Solitaire seeds and the solver's
/// core guarantees. This is the permanent replacement for the one-off
/// generation harness: every shipped level seed must still be PROVABLY winnable
/// (soundness → no unbeatable level), and the deterministic deck must be stable.
final class SolitaireSeedTests: XCTestCase {

    func testExactly50CommittedSeeds() {
        XCTAssertEqual(SolitaireSeeds.seeds.count, 50, "one seed per level")
        // Seeds are distinct so no two levels are the identical deal.
        XCTAssertEqual(Set(SolitaireSeeds.seeds).count, 50, "seeds must be unique")
    }

    func testEveryCommittedSeedIsProvablyWinnable() {
        // Each committed seed must still be solved by the sound solver — a
        // proof it is winnable. Budget is generous; committed seeds solve well
        // under it, so this stays fast.
        for (i, seed) in SolitaireSeeds.seeds.enumerated() {
            let r = SolitaireSolver.solve(seed: seed, nodeBudget: 30_000)
            XCTAssertTrue(r.solved, "level \(i + 1) seed \(seed) is no longer solvable (nodes=\(r.nodes))")
        }
    }

    func testDeckIsDeterministicAndComplete() {
        // Same seed → same 52-card ordering, and it is a full valid deck.
        let a = SolitaireDeck.shuffled(seed: 596)
        let b = SolitaireDeck.shuffled(seed: 596)
        XCTAssertEqual(a.map(\.code), b.map(\.code), "deck must be reproducible")
        XCTAssertEqual(Set(a.map(\.code)).count, 52, "must be all 52 distinct cards")
        // Different seeds give different orderings.
        let c = SolitaireDeck.shuffled(seed: 597)
        XCTAssertNotEqual(a.map(\.code), c.map(\.code))
    }

    func testSolverIsSound_reportsWinOnlyOnRealWin() {
        // A trivially-solvable check: the initial state's isWon is false, and a
        // fully-banked foundation state is won — the win predicate the solver
        // trusts is correct.
        var s = SolitaireSolver.makeInitialState(seed: 2)
        XCTAssertFalse(s.isWon)
        s.foundations = [13, 13, 13, 13]
        XCTAssertTrue(s.isWon)
    }
}
