// SolitaireSeeds.swift
// MTRX — Core/Gaming
//
// The 50 committed Solitaire level seeds — the OUTPUT of SolitaireSolver.
// Every seed here was PROVEN winnable by the sound solver (it found a complete
// win line), so no level can ever be unbeatable. They are ordered easiest →
// hardest by the solver's node count, giving a natural difficulty ramp across
// the 50 levels. Regenerate with SolitaireSolverGenTests; each seed is
// continuously re-verified by SolitaireSeedTests.

enum SolitaireSeeds {
    /// Level N uses `seeds[N-1]`. Deals via SolitaireDeck.shuffled(seed:).
    static let seeds: [UInt64] = [
        596, 36, 588, 226, 405, 456, 282, 314, 387, 506,
        80, 379, 329, 121, 479, 211, 91, 364, 104, 572,
        463, 267, 416, 399, 212, 18, 2, 82, 202, 551,
        168, 548, 598, 316, 131, 183, 190, 45, 69, 273,
        605, 610, 581, 276, 571, 501, 485, 299, 511, 227,
    ]

    static func seed(forLevel level: Int) -> UInt64 {
        let i = max(1, min(seeds.count, level)) - 1
        return seeds[i]
    }
}
