# Games Workstream — scope & build plan

> **STATUS: QUEUED.** Build is deferred until **Phase 5 closes and merges to main**.
> Built carefully, sequenced, one piece at a time, each verified against the full
> 117-suite and held for read — **not** fanned out in parallel. ~2–3 weeks. Option B:
> everything ships in one TestFlight update (all 300 levels + Game Center + Solitaire
> redos/IAP).

## Build order (dependency-correct)

### 1. Game Center fix (tiny, sequenced)
Root cause: the app is **not entitled** for Game Center — no `com.apple.developer.game-center`
key in `Config/Entitlements.entitlements`. Code is correct + fully wired (honest soft-fail
to `.unavailable`). 
- **USER-ACTION FIRST:** ① enable Game Center capability on the MTRX App ID (Apple Developer
  portal) + refresh provisioning; ② create **7 leaderboards** with exact IDs
  `mtrx.leaderboard.{solitaire,blocks,colorburst,merge2048,breakout,asteroids,arcade}`;
  ③ create **3 achievements** `mtrx.achievement.{firstplay,firstwin,highroller}`.
- **THEN CODE (me):** add `<key>com.apple.developer.game-center</key><true/>` (2 lines).
  Adding the entitlement *before* the capability is enabled breaks provisioning — order matters.

### 2. Shared progress / unlock / level-select layer — BUILT ONCE
The foundation all 6 games plug into (level progress, unlock gating, level-select, persistence).
**None of the 6 games persist level progress today** (all start at level 1 each launch).
Build it **once and reuse** — do NOT build it six times.

### 3. The 300 levels — ONE GAME AT A TIME
For each: 50-level system + difficulty curve + level-complete/win UI, plug into the shared
layer, verify full-117, package, hold. Order = easiest → content-heavy:

| Order | Game | Today | Level = | Content/code | Size |
|---|---|---|---|---|---|
| 1 | **AsteroidStorm** | wave-based (endless) | a wave; cap at 50 + victory | generated (formula + ~6 milestone overrides) | **S** (M if UFO hazard tier) |
| 2 | **ColorBurst** | none (endless match-3) | target score within move budget | hybrid (formula + sparse overrides) | M |
| 3 | **2048** | none (endless) | target tile + move budget + blockers | authored 50-row table | M · **product call: zen→gauntlet** |
| 4 | **Block** | derived `lines/10+1`, gravity caps L11 | clear a line-quota under a profile | hybrid (formula + ~5-row table) | M · **product call: "Block"/Tetris naming** |
| 5 | **BrickBreaker** | shell only (boards identical, speed tunnels) | one distinct board | authored (50 hand-designed boards) | M |
| 6 | **Solitaire** | none (single fixed Klondike) | deal-difficulty tier, advance by winning | hybrid (formula rules + 50 solver-verified seeds) | M |

**Flag the two product decisions BEFORE building #3 and #4:** 2048 going zen→gauntlet (confirm
the feel change), and "Block" labeled "Tetris" (confirm naming, given trademark exposure).
**Perf:** late-level difficulty must come from speed/hazards, not raw object count
(AsteroidStorm/BrickBreaker run discrete collision on a 120 Hz loop; BrickBreaker's current
uncapped speed already tunnels).

### 4. Solitaire redos: 3a → 3b
- **3a (non-money, S):** the 3-free-redo take-back. Solitaire is forward-only today (no undo/
  redo/history); use a **snapshot-before-mutate** stack (inverse-replay is unsafe — moves have
  auto-flip +5 side effects). `redosLeft = 3` reset per game, no cross-launch persistence.
- **3b (REAL MONEY — full money-seam adversarial pass):** a $0.99 **Consumable** IAP
  (`com.opnmatrx.mtrx.solitaire.redos5`). Must NOT enter `tierForProductId`/`productIds`
  (would grant Pro for $0.99). Grant order = purchase → verify → **grantRedos → finish**
  (finish-before-grant = lost money). **Idempotent on `transaction.id`** (delivered twice:
  purchase return + the `Transaction.updates` listener). Balance in a dedicated key, NOT in
  `SubscriptionState.usageCounters` (resets monthly). Fail-closed: zero redos on
  cancel/pending/unverified/error, honest copy. **3a must ship before 3b** — can't sell redos
  that can't be used. User creates the Consumable in ASC (exact id) → App Review.

## Open / deferred items (don't lose these)
- **Tournament cards render mock data** (`GamingViewModel` → `entryFee` / `players` / `status`).
  Phase 5 step 2 made the **Register** button honest ("Not Available Yet"), but the tournament
  *content* is fabricated. When Game Center + real competition wiring land, the cards either get
  **real data** or honest **"no live tournaments"** states. It's a fake-content question (belongs
  here), not a dead-end question (Phase 5). — flagged 2026-06-23.

## Environment note
The **MicaPlayer** GameKit+MusicKit sim-crash (see `Tests/TESTING_NOTES.md`) will likely recur
during this workstream (GameKit-heavy). A sim crash mid-build with **no `failed -` assertion
line** is that env issue, not a regression — clear sim + re-run, don't "fix" code for it.
