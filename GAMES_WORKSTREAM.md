# Games Workstream — BUILT (Phase 2, 2026-07-02)

> **STATUS: BUILT.** All 300 levels (6 games × 50) + the shared progress layer +
> Solitaire redos (3a free + 3b IAP) shipped in one update (Option B). Built one
> game at a time, each verified against the full suite. Product decisions and
> the money-seam adversarial pass are recorded below.

## Product decisions (locked by the user, 2026-07-02)
- **2048 → Gauntlet** (50 authored levels: target tile + move budget + blockers).
  The classic **Endless** mode is KEPT as a separate mode chosen at launch — not
  deleted.
- **"Block" → "Stackfall"** (original brand; NOT "Tetris" — trademark risk). All
  user-facing strings route through `BlockBrand.name` (one-line rename). Internal
  ids and the ASC leaderboard id `mtrx.leaderboard.blocks` are unchanged.

## What was built
1. **Game Center entitlement** — already present (`com.apple.developer.game-center`,
   from B188-3). Only the user's ASC leaderboard/achievement creation remains
   (human action; the code soft-fails to `.unavailable`).
2. **Shared progress layer (built once)** — `Core/Gaming/GameProgress.swift`
   (iCloud-KVS/UserDefaults persistence, per-GameID unlocked-level + completed
   bitmask) + reusable `GameLevelSelectView`. 11 tests.
3. **300 levels, one game at a time** — each plugs into the shared layer with a
   level-select entry, per-level completion persistence, retry, and a real
   victory at 50:
   | # | Game | Level = | Content |
   |---|---|---|---|
   | 1 | AsteroidStorm | a wave | formula (count + speed by level), cap 50 + victory |
   | 2 | ColorBurst | target score in a move budget | formula + milestone overrides |
   | 3 | 2048 · Gauntlet | reach a target tile in a move budget past blockers | authored tiers + blocker-aware slide |
   | 4 | Stackfall | clear a line quota under a gravity/garbage profile | monotonic formula + garbage tiers |
   | 5 | BrickBreaker | one distinct board | 50 hand-designed boards + **ball-speed cap + sub-stepping (tunneling fixed)** |
   | 6 | Solitaire | a solver-verified deal | 50 seeds PROVEN winnable by a committed sound solver |
4. **Solitaire redos**
   - **3a** — snapshot-based undo, 3 free do-overs per deal (already in the engine; preserved).
   - **3b** — `$0.99` **Consumable** `com.opnmatrx.mtrx.solitaire.redos5` (+5 do-overs).
     Money-seam law enforced: grant→verify→grant→finish (grant before finish),
     idempotent on `transaction.id` (both delivery paths), dedicated balance key
     (never `usageCounters`), excluded from `productIds`/`tierForProductId` (a
     $0.99 buy can never grant Pro), fail-closed with honest copy.
     **Adversarial pass (2026-07-02): all 3 lanes SAFE — double-grant,
     grant-before-verify, restore-path abuse all clean.**

## Phase-2 adversarial pass (games honesty, 2026-07-02)
Three lanes: **progress-integrity SAFE**, **solver-soundness SAFE** (deal
equivalence verified card-for-card for 450 seeds; all 50 committed seeds' win
lines replayed through a strict independent referee — zero rejections), and
**game-logic: one P1 found and FIXED** — BrickBreaker's sub-step delta was
computed once per tick, so a mid-tick bounce kept the old heading and a
multi-hit brick could lose 2 hp in one contact (easier-never-unbeatable, but it
halved authored difficulty on levels 13+ and inflated scores). Fix: recompute
the per-step delta from the CURRENT velocity each sub-step (step count stays
valid — reflections preserve speed). Also hardened from the pass's notes: the
solver's whole-pile King prune no longer skips productive moves off face-down
cards, and 2048 (re)starts bump a generation counter so a stale post-move
closure can't fire into a fresh board.

## Solver
`Core/Gaming/SolitaireSolver.swift` — deterministic seeded deck + a SOUND
best-first thoughtful solver (reports solvable only on a real win line ⇒ no
unbeatable level). Its OUTPUT (`SolitaireSeeds.swift`, 50 proven seeds, easiest→
hardest) is continuously re-verified by `SolitaireSeedTests`.

## GameKit audit
All 6 games submit to their correct leaderboard (`.asteroids/.colorburst/
.merge2048/.blocks/.breakout/.solitaire`) via `recordGameOver`, which also
reports the 3 achievements (firstPlay/firstWin/highRoller). Soft-fails to
`.unavailable` until the user's ASC setup lands.

## Owed by the user (ASC, non-blocking)
7 leaderboards `mtrx.leaderboard.{solitaire,blocks,colorburst,merge2048,breakout,
asteroids,arcade}` + 3 achievements `mtrx.achievement.{firstplay,firstwin,
highroller}` + the Consumable `com.opnmatrx.mtrx.solitaire.redos5` — all created
in App Store Connect. Until then Game Center soft-fails and the IAP shows an
honest "unavailable" state.

## Open / deferred
- **Tournament cards render mock data** (`GamingViewModel`). Still fabricated
  content — when real competition wiring lands they get real data or an honest
  "no live tournaments" state. Not addressed in this workstream.
