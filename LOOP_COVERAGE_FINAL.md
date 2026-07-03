# LOOP_COVERAGE_FINAL — module × 13-step traversal

Final coverage of the universal 13-step loop after the Phases 1–7 build-out.
The loop is a **single universal path**: every feature module's action funnels
through the same gateway `_call → gate_action` seam, so steps 5–6 and 10–13 are
structurally identical for all modules. Steps 7–9 (paymaster / phone-sign /
bundler) apply to on-chain-write modules and are **deploy-gated** — real code,
dormant until the Phase-6 deploy-wall addresses land (see
`POST_DEPLOY_WIRING_UNIT.md`).

Legend: **✓** real & exercised now · **⛓** real, deploy-gated (dormant until
contract addresses) · **·** not applicable to this module.

### The 13 steps
1 Tap · 2 local walls · 3 Face ID / Morpheus advisory · 4 preflight (App Attest)
· 5 gateway `/api/v1/*` · 6 Morpheus seam `_call→gate_action` · 7 paymaster/sign
· 8 phone signs · 9 bundler / EntryPoint · 10 EXECUTES · 11 real-result-first ·
12 feed publishes · 13 ripple out

| Module | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Send / Swap / Stake (wallet) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ⛓ | ⛓ | ⛓ | ⛓ | ✓ | ✓ | ✓ |
| NFT mint (P3) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ⛓ | ⛓ | ⛓ | ✓ | ✓ | ✓ | ✓ |
| IP register / license (P3) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | · | · | · | ✓ | ✓ | ✓ | ✓ |
| Governance vote (P5-1) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | · | · | · | ✓ | ✓ | ✓ | ✓ |
| Groups / community (P2 WIRE) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | · | · | · | ✓ | ✓ | ✓ | ✓ |
| Messaging reads (P2 WIRE) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | · | · | · | ✓ | ✓ | · | · |
| Social post | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | · | · | · | ✓ | ✓ | ✓ | ✓ |
| Oracle / Compute / Storage | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | · | · | · | ⛓ | ✓ | ✓ | ✓ |
| Events / Indexer / Licensing-list | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | · | · | · | ✵ | ✓ | · | · |
| DeFi / RWA / Insurance / Securities | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ⛓ | ⛓ | ⛓ | ⛓ | ✓ | ✓ | ✓ |
| Privacy (transfer / stealth / vote) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ⛓ | ⛓ | ⛓ | ⛓ | ✓ | ✗ | ✗ |

`✵` = route registered as honest **501** (no backing service yet — P2). `✗` on
steps 12–13 for Privacy is **intentional**: privacy actions must NEVER ripple.

## Per-step proof
- **5 gateway** — 196 routes registered; `docs/ROUTES.md` regenerated, doctor
  `route table = READY`, staleness guard green.
- **6 Morpheus seam** — every service-backed route runs through `_call()`, which
  calls `gate_action()` first (OBSERVE/testnet, inert-allow when the private
  package isn't installed). P2 WIRE routes verified through the seam.
- **7 paymaster/sign** — `sendTransaction` requests `paymasterAndData` and folds
  it in **before** signing (P5-2); non-custodial (server signs only the gas
  digest with a platform key). Dormant until `isGasSponsorshipConfigured`.
- **8–9 sign/bundle** — `ERC4337Manager.signOperation` / `submitOperation`;
  testnet-only fail-closed guard (`SigningWallTests` green).
- **10 EXECUTES** — real service method via `_call`; honest 501 where no backing.
- **11 real-result-first** — P3 actions flip success only on the real server
  result; P1-3 killed 18 fake-success actions; honest failure changes no state.
- **12–13 feed/ripple** — P4: an executed non-privacy action emits `feed.ripple`
  through the seam; privacy/reads/failures never ripple.

## Verification (2026-07-03)
0pnMatrx pytest **665** · Morpheus **183** · MTRX **185** (SigningWall green) ·
doctor consistent (no HALF) · verify_abis + route-table guard green · five
adversarial passes (P1–P5) — zero surviving honesty/security/custody violations.
