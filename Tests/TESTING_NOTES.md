# MTRX — Testing Notes & Known Environment Issues

Notes for anyone running the MTRX test suite. These are **environment** gotchas,
not code bugs — the distinction matters because some of them *look* like test
failures but aren't.

> **Verified clean baseline (2026-06-23):** full bundle = **117 tests, 3 skipped,
> 0 failures** (`** TEST SUCCEEDED **`). The 3 skips are intentional —
> `InferenceRouterTests` integration tests gated behind `XCTSkipUnless` (live
> network). "Green" means the whole 117-bundle, not the WalletTests-44 subset.

---

## KNOWN-ENV-1 — `MicaPlayer` GameKit + MusicKit framework conflict (iOS 27 Simulator)

**Symptom.** A full-suite run prints `** TEST FAILED **` and
`Restarting after unexpected exit, crash, or test timeout; summary will include
totals from previous launches` — but with **zero `failed -` assertion lines** in
the log, and a **truncated / relaunched test count** (never a clean `Executed 117`).
The test that happened to be *in flight* when the host crashed (observed:
`MTRXAPIClientTests.test_500_retriesThenThrowsServerError`) gets listed under
`Failing tests:` even though it asserted nothing — it's a **crash victim, not a
real red.**

**Cause.** The simulator logs:

```
objc[…]: Class MicaPlayer is implemented in both
  …/GameCenterUI.framework/GameCenterUI and
  …/AppleMediaServicesUI.framework/AppleMediaServicesUI.
  This may cause spurious casting failures and mysterious crashes.
```

The app links **GameKit** (Game Center) and **MusicKit** (AppleMediaServicesUI),
so both frameworks load `MicaPlayer` in the test host and occasionally crash it.
**Simulator-only, intermittent, not a code bug, does not affect device.**

**Handling (category-3: environment/flaky).** Do **NOT** "fix" code for this.
1. Clear sim state: `xcrun simctl shutdown all`
2. Clear derived data, re-run the full suite.
3. A clean run produces `Executed 117 tests … 0 failures` / `** TEST SUCCEEDED **`.

**How to tell a real failure from this crash:**
| | Real failure | MicaPlayer crash |
|---|---|---|
| `failed -` assertion line | yes (names the test + expectation) | **none** |
| test count | clean `Executed 117` | truncated / "previous launches" |
| `Restarting after unexpected exit` | no | **yes** |

**Expect it to recur during the games workstream** — GameKit is exercised heavily
there (Game Center leaderboards/achievements across all 6 games). A sim crash
mid-games-build is this issue, not a regression, until proven otherwise by a
`failed -` assertion line.
