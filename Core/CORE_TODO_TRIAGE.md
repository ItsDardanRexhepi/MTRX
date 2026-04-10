# MTRX Core TODO Triage

**Status as of 2026-04-09.** 69 total TODOs across 19 files in `Core/`,
categorized for the May 21, 2026 TestFlight ship.

Two buckets:

- **BLOCKER** — must ship working before TestFlight or the app cannot
  pass App Review, cannot honor advertised features, or cannot persist
  state.
- **POST-TESTFLIGHT** — ship with a safe stub that returns a reasonable
  default; full implementation can land after 1.0.

Nothing here is thrown away. The post-TestFlight items are tracked and
queued for the 1.1 milestone.

---

## BLOCKERS (must ship)

These 14 items gate the TestFlight build. Everything else can slip.

### Trinity permissions (iOS system APIs)

`Core/Trinity/TrinityOnboarding.swift`

| Line | TODO | Why blocker |
|-----:|------|-------------|
| 220 | Implement actual permission requests using system APIs | User cannot complete onboarding without real prompts |
| 346 | `UNUserNotificationCenter.current().requestAuthorization` | Morpheus alerts unusable without notifications |
| 351 | `HKHealthStore().requestAuthorization` | Health context is an advertised capability |
| 356 | `CLLocationManager` | Location context is an advertised capability |
| 361 | `AVCaptureDevice.requestAccess(for: .video)` | Camera for KYC + agent vision |
| 366 | `AVCaptureDevice.requestAccess(for: .audio)` | Voice conversations with Trinity |
| 371 | `LAContext().canEvaluatePolicy` | Biometric unlock gates wallet signing |
| 376 | `INPreferences.requestSiriAuthorization` | Siri shortcut for "Ask Trinity" |

**Implementation plan:** wire each stub to its real system API using the
appropriate `async/await` wrapper. Each permission must persist its
status in `UserDefaults` under `trinity.permission.<name>` so onboarding
can resume correctly.

### Trinity voice & memory

`Core/Trinity/TrinityVoice.swift`

| Line | TODO | Why blocker |
|-----:|------|-------------|
| 66 | Configure `AVAudioSession` for speech playback | Voice output crackles on speaker/bluetooth without it |

`Core/Trinity/TrinityMemory.swift`

| Line | TODO | Why blocker |
|-----:|------|-------------|
| 112 | Configure SwiftData container with proper schema | Without this the memory store doesn't persist across launches |

### Morpheus voice alerts

`Core/Morpheus/MorpheusVoice.swift`

| Line | TODO | Why blocker |
|-----:|------|-------------|
| 114 | Play alert chime before critical voice | Required so users notice urgent Morpheus warnings |
| 200 | Implement alert chime playback using `AVAudioPlayer` | Same — the chime trigger has no implementation |

### Instrumentation

`Core/Trinity/TrinityInference.swift`

| Line | TODO | Why blocker |
|-----:|------|-------------|
| 123 | Measure actual latency | TestFlight analytics need real numbers; `latencyMs: 0` is a lie |

---

## POST-TESTFLIGHT (stub is OK for 1.0)

These 55 items can ship with a hard-coded or heuristic fallback. The
fallback is documented in-line so there's no mystery in production logs.

### Rexhepi Framework — gate evaluators *(7 TODOs)*

`Core/RexhepiFW/Engine.swift:106,186,207,213,219,225,231,237`

Every gate (clarity, feasibility, risk, uncertainty, value, loop limit)
currently returns a midpoint default. For TestFlight, tighten the
defaults per gate (e.g. `0.7` for clarity on well-formed prompts,
`0.3` for risk on read-only operations) and ship. Real learning-based
scoring lands in 1.1.

### Decision log persistence *(4 TODOs)*

`Core/Omniversal/DecisionLog.swift:73,205,215,226`

In-memory log with a best-effort snapshot to `UserDefaults` on backgrounding.
Real append-mode file handle + retry queue can ship in 1.1.

### Omniversal hard rules & time sensitivity *(2 TODOs)*

`Core/Omniversal/HardRules.swift:239` — Data freshness: use a fixed
5-minute TTL as the stub.
`Core/Omniversal/TimeSensitivity.swift:135` — Use message keyword
heuristics (`"now"`, `"urgent"`, `"before"`) as the stub.

### Oracle suite *(22 TODOs)*

`Core/Oracle/Oracle.swift:217` — Semantic relevance: keyword intersection
with Jaccard similarity.
`Core/Oracle/ThreatDetection.swift:184,193,209,227,243` — All five return
`.low` severity by default. Real pattern matching after 1.0.
`Core/Oracle/StrategicForesight.swift:214` — Return the three top-level
scenario templates baked in. No dynamic generation for 1.0.
`Core/Oracle/DardanAdvisory.swift:273,325,330` — Portfolio optimization
is a no-op passthrough; insights render via `String(describing:)`.
`Core/Oracle/PatternIntelligence.swift:167,184,243` — Pearson uses a
simplified windowed implementation; feed refresh is on a 60s timer;
anomaly detection uses fixed 3-sigma.
`Core/Oracle/ProbabilityArchitecture.swift:187,214` — Evidence fetching
returns empty; risk assessment uses a single-factor default.
`Core/Oracle/CoordinationIntelligence.swift:118,153,166,179,262,285` —
Deferred delivery, conflict resolution, insight merging, resource
rebalancing all default to pass-through. Safe but non-optimal.

### Trinity context providers *(10 TODOs)*

`Core/Trinity/TrinityContext.swift:27,41,144,225,231,237,243,249,285,295`

Context providers (HealthKit, CoreLocation, WeatherKit, portfolio,
transactions) all return `.unavailable` stubs for 1.0 **except** the
ones already covered in the BLOCKER section (HealthKit + CoreLocation
permission requests). The device info stub reads only values that are
always available without permission prompts.

### Morpheus triggers *(3 TODOs)*

`Core/Morpheus/MorpheusTriggers.swift:143,155,160`
`Core/Morpheus/Morpheus.swift:215,219,230`

For 1.0 the trigger evaluator only watches the two hand-tuned scenarios
Morpheus ships with (big portfolio drop, looming liquidation). General
trigger matching lands in 1.1.

### Trinity memory patterns *(2 TODOs)*

`Core/Trinity/TrinityMemory.swift:154,204`

Semantic similarity search falls back to substring match; pattern
detection returns an empty array. Still useful for a TestFlight demo.

### Trinity inference internals *(3 TODOs)*

`Core/Trinity/TrinityInference.swift:149,221,233`

Model-specific interpretation and feature-provider construction work
correctly for the single CoreML model shipped with 1.0 (Trinity base).
MLMultiArray/CVPixelBuffer handling lands when multi-model support does.

### Trinity relevance + integrations *(2 TODOs)*

`Core/Trinity/TrinityContext.swift:27,144` — Relevance scoring is a
time-weighted recency heuristic; data provider protocols are in place
as empty types ready for 1.1 implementations.

---

## Acceptance

A TestFlight build is ready when:

1. All 14 BLOCKER items are marked done and have tests.
2. All 55 POST-TESTFLIGHT items still compile and ship with the
   documented fallback (no crash, no `fatalError`, no empty
   `switch default` traps).
3. The `.github/workflows/ios.yml` pipeline is green on `main`.
4. `Tests/Unit/MTRXPackagerTests.swift`, `MTRXAPIClientTests.swift`,
   `BridgeSmokeTest.swift` all pass in CI.

When any BLOCKER lands, strike it through in this file and check it off.
