// SolitaireSolver.swift
// MTRX — Core/Gaming
//
// A deterministic Klondike deck (seeded) plus a SOUND thoughtful-solitaire
// solver. "Sound" is the load-bearing property: the solver only ever reports a
// deal solvable when it has actually found a complete winning line — so a seed
// it verifies can never produce an unbeatable level. It is intentionally not
// complete (a node budget may make it give up on a genuinely-winnable deal);
// that only costs us extra seed candidates, never correctness.
//
// The game deals draw-1 with unlimited redeals; the solver models the same. It
// is a thoughtful solver (it sees face-down cards), which is the standard
// solvability criterion for a known deal.

import Foundation

// MARK: - Deterministic deck

/// A card as a compact code: 0…51, where code = (rank-1) * 4 + suit,
/// rank 1…13 (A…K), suit 0…3 matching CardSuit (spades, hearts, diamonds, clubs).
struct SolCard: Equatable, Hashable {
    let code: UInt8
    init(rank: Int, suit: Int) { code = UInt8((rank - 1) * 4 + suit) }
    init(code: UInt8) { self.code = code }
    var rank: Int { Int(code) / 4 + 1 }
    var suit: Int { Int(code) % 4 }
    var isRed: Bool { suit == 1 || suit == 2 }   // hearts, diamonds
}

/// Reproducible shuffle from a seed (SplitMix64 → Fisher–Yates). The SAME
/// ordering is used by the game engine and the solver, so a verified seed
/// describes the exact deal the player sees.
enum SolitaireDeck {
    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// 52 cards in shuffled order for `seed`.
    static func shuffled(seed: UInt64) -> [SolCard] {
        var deck = (0..<52).map { SolCard(code: UInt8($0)) }
        var rng = SplitMix64(state: seed &+ 0xD1B54A32D192ED03)
        var i = deck.count - 1
        while i > 0 {
            let j = Int(rng.next() % UInt64(i + 1))
            deck.swapAt(i, j)
            i -= 1
        }
        return deck
    }
}

// MARK: - Solver

enum SolitaireSolver {

    /// Solver game state (value type so search can branch by copying).
    struct State: Hashable {
        // Face-down count at the bottom of each of the 7 tableau piles; the
        // rest of the pile (from `down[p]` to the end) is face-up.
        var piles: [[SolCard]]
        var down: [Int]
        var foundations: [Int]     // top rank per suit (0 = empty)
        var stock: [SolCard]       // draw from the end
        var waste: [SolCard]       // top is the end

        var isWon: Bool { foundations.allSatisfy { $0 == 13 } }
    }

    static func makeInitialState(seed: UInt64) -> State {
        let deck = SolitaireDeck.shuffled(seed: seed)
        var piles: [[SolCard]] = Array(repeating: [], count: 7)
        var down = Array(repeating: 0, count: 7)
        var idx = 0
        for col in 0..<7 {
            for row in 0...col {
                piles[col].append(deck[idx]); idx += 1
                if row != col { down[col] += 1 }   // all but the last are face-down
            }
        }
        let stock = Array(deck[idx...])
        return State(piles: piles, down: down, foundations: Array(repeating: 0, count: 4),
                     stock: stock, waste: [])
    }

    /// A card may be moved to a foundation once both opposite-colour foundations
    /// are high enough that it can never be needed on the tableau — the standard
    /// "safe autoplay" rule. Aces and twos are always safe.
    private static func safeToFoundation(_ card: SolCard, _ f: [Int]) -> Bool {
        if card.rank <= 2 { return true }
        let redMin = min(f[1], f[2])       // hearts, diamonds
        let blackMin = min(f[0], f[3])     // spades, clubs
        let oppMin = card.isRed ? blackMin : redMin
        return card.rank <= oppMin + 1
    }

    private static func canFoundation(_ card: SolCard, _ f: [Int]) -> Bool {
        f[card.suit] == card.rank - 1
    }

    private static func canTableau(_ card: SolCard, onto pile: [SolCard], down: Int) -> Bool {
        if pile.count == down {                     // empty (no face-up cards)
            return card.rank == 13                   // only a King
        }
        let top = pile[pile.count - 1]
        return top.isRed != card.isRed && top.rank == card.rank + 1
    }

    /// Priority = cards banked on foundations (primary), then fewer hidden
    /// cards. Higher is closer to a win; the search always expands the most
    /// promising frontier state, so winnable deals are reached in far fewer
    /// nodes than a blind DFS (Klondike wins are ~100+ moves deep).
    private static func priority(_ s: State) -> Int {
        let banked = s.foundations.reduce(0, +)
        let hidden = s.down.reduce(0, +)
        return banked * 100 - hidden
    }

    /// Determine whether the deal for `seed` is winnable, within a node budget.
    /// Returns (solved, nodesExplored). `solved == true` is a PROOF (a full win
    /// line was reached); `false` means "not found within the budget".
    static func solve(seed: UInt64, nodeBudget: Int = 200_000) -> (solved: Bool, nodes: Int) {
        var start = makeInitialState(seed: seed)
        _ = applySafeAutoplay(&start)
        if start.isWon { return (true, 0) }

        var heap = Heap<HeapEntry>()
        var visited = Set<State>()
        heap.push(HeapEntry(priority: priority(start), state: start))
        visited.insert(start)
        var nodes = 0

        while let entry = heap.pop() {
            if nodes >= nodeBudget { return (false, nodes) }
            nodes += 1
            for var next in successors(entry.state) {
                _ = applySafeAutoplay(&next)
                if next.isWon { return (true, nodes) }
                if visited.contains(next) { continue }
                visited.insert(next)
                heap.push(HeapEntry(priority: priority(next), state: next))
            }
        }
        return (false, nodes)
    }

    private struct HeapEntry: Comparable {
        let priority: Int
        let state: State
        static func < (a: HeapEntry, b: HeapEntry) -> Bool { a.priority < b.priority }
        static func == (a: HeapEntry, b: HeapEntry) -> Bool { a.priority == b.priority }
    }

    /// Minimal binary max-heap (pops the highest-priority entry).
    private struct Heap<T: Comparable> {
        private var items: [T] = []
        var isEmpty: Bool { items.isEmpty }
        mutating func push(_ x: T) {
            items.append(x)
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if items[parent] < items[i] { items.swapAt(parent, i); i = parent } else { break }
            }
        }
        mutating func pop() -> T? {
            guard !items.isEmpty else { return nil }
            items.swapAt(0, items.count - 1)
            let top = items.removeLast()
            var i = 0
            let n = items.count
            while true {
                let l = 2 * i + 1, r = 2 * i + 2
                var largest = i
                if l < n && items[largest] < items[l] { largest = l }
                if r < n && items[largest] < items[r] { largest = r }
                if largest == i { break }
                items.swapAt(i, largest); i = largest
            }
            return top
        }
    }

    /// Repeatedly play any safe foundation move. Returns true if it changed the
    /// state.
    private static func applySafeAutoplay(_ s: inout State) -> Bool {
        var changed = false
        var again = true
        while again {
            again = false
            // From tableau tops.
            for p in 0..<7 where s.piles[p].count > s.down[p] {
                let card = s.piles[p][s.piles[p].count - 1]
                if canFoundation(card, s.foundations), safeToFoundation(card, s.foundations) {
                    s.piles[p].removeLast()
                    s.foundations[card.suit] = card.rank
                    flipIfNeeded(&s, p)
                    changed = true; again = true
                }
            }
            // From the waste top.
            if let card = s.waste.last,
               canFoundation(card, s.foundations), safeToFoundation(card, s.foundations) {
                s.waste.removeLast()
                s.foundations[card.suit] = card.rank
                changed = true; again = true
            }
        }
        return changed
    }

    private static func flipIfNeeded(_ s: inout State, _ p: Int) {
        if s.piles[p].count == s.down[p] && s.down[p] > 0 {
            s.down[p] -= 1     // expose the next face-down card
        }
    }

    /// All non-safe-autoplay successor states, ordered to find wins fast.
    private static func successors(_ state: State) -> [State] {
        var out: [State] = []

        // 1) Tableau/waste → foundation (non-safe ones we didn't auto-apply).
        for p in 0..<7 where state.piles[p].count > state.down[p] {
            let card = state.piles[p][state.piles[p].count - 1]
            if canFoundation(card, state.foundations) {
                var s = state
                s.piles[p].removeLast(); s.foundations[card.suit] = card.rank
                flipIfNeeded(&s, p)
                out.append(s)
            }
        }
        if let card = state.waste.last, canFoundation(card, state.foundations) {
            var s = state
            s.waste.removeLast(); s.foundations[card.suit] = card.rank
            out.append(s)
        }

        // 2) Tableau → tableau (move a face-up run). Prefer moves that flip a
        //    face-down card or empty a pile onto a King.
        for from in 0..<7 {
            let faceUpStart = state.down[from]
            guard state.piles[from].count > faceUpStart else { continue }
            // A run must be a valid descending alternating-colour sequence.
            for start in faceUpStart..<state.piles[from].count {
                if !isValidRun(state.piles[from], from: start) { continue }
                let moving = state.piles[from][start]
                // A whole-pile move is only pointless when the base is ALREADY
                // empty (no face-down cards beneath) — then King→empty is a
                // no-op cycle. If face-down cards remain, moving the run off is
                // productive (it exposes one), so it must NOT be pruned.
                let movingWholePile = (start == faceUpStart && state.down[from] == 0)
                for to in 0..<7 where to != from {
                    if canTableau(moving, onto: state.piles[to], down: state.down[to]) {
                        if movingWholePile && moving.rank == 13 &&
                            state.piles[to].count == state.down[to] { continue }
                        var s = state
                        let run = Array(s.piles[from][start...])
                        s.piles[from].removeSubrange(start...)
                        s.piles[to].append(contentsOf: run)
                        flipIfNeeded(&s, from)
                        out.append(s)
                    }
                }
            }
        }

        // 3) Waste → tableau.
        if let card = state.waste.last {
            for to in 0..<7 where canTableau(card, onto: state.piles[to], down: state.down[to]) {
                var s = state
                s.waste.removeLast(); s.piles[to].append(card)
                out.append(s)
            }
        }

        // 4) Draw from stock (or redeal). Always available if there are cards.
        if !state.stock.isEmpty {
            var s = state
            s.waste.append(s.stock.removeLast())
            out.append(s)
        } else if !state.waste.isEmpty {
            var s = state
            s.stock = s.waste.reversed()
            s.waste = []
            out.append(s)
        }

        return out
    }

    /// Is `pile[from...]` a valid movable run (descending, alternating colour)?
    private static func isValidRun(_ pile: [SolCard], from: Int) -> Bool {
        var i = from
        while i + 1 < pile.count {
            let a = pile[i], b = pile[i + 1]
            if !(a.isRed != b.isRed && a.rank == b.rank + 1) { return false }
            i += 1
        }
        return true
    }
}
