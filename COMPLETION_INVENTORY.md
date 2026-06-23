# COMPLETION_INVENTORY.md — Phase 0, CERTIFIED FULL PASS

Where MTRX (and the public 0pnMatrx runtime) **reports success without doing the
work**, plus a WIRED / SHELL / PARTIAL / GATED classification of every action flow.
Read-only — no code was changed to produce this.

**The inviolable rule:** nothing reports success it didn't earn. Every 🚩 and ⚠️ below
currently violates it.

## Coverage (this is the certified pass)

- **Method:** comprehensive grep across **all 360 Swift files** + the **0pnMatrx
  runtime** (incl. the 181-file `runtime/blockchain/services` dir the agent-fleet
  finder died on) for the precise signatures — success-shaped returns
  (`completion(.success)`, `return .success(true/[])`, `isValid/verified/allow: true`,
  success UI state) and the **TODO/stub-then-success adjacency** — then a **targeted
  read of every candidate function** to confirm fake vs. real, trace callers, and judge
  user-reachability. Every funds/action UI flow individually classified.
- **Why direct instead of the agent fleet:** the parallel sweep hit a usage cap; you
  approved completing it on the main loop. Same goal, delivered now.
- **Result:** the launch-critical surface from the draft is confirmed and **3 new items
  found** (M5 governance vote, M6 batch-attestation, M7 dispute submit). The 0pnMatrx
  services layer and MTRX `Services/` are **clean** of the pattern (0 TODO→success).

---

## 🚩 DANGEROUS — fake success on funds / recovery / attestation, user-reachable

| # | File:line | Shows / returns | Actually does | Reachable |
|---|---|---|---|---|
| **D1** | `UI/Views/Wallet/SendView.swift:82` | `.alert("Transaction Sent")` "Successfully sent {amt}" | **Nothing** — 0 execution calls in the file; the button toggles the alert. No sign, no broadcast. | **Yes** (Wallet → Send) |
| **D2** | `UI/Views/Wallet/SwapView.swift:501,574` | `showConfirmation=true` + success haptic | **Nothing** — fetches a quote (PARTIAL), executes no swap. 0 exec calls. | **Yes** (Wallet → Swap) |
| **D3** | `Blockchain/Wallet/WalletCreation.swift:486` | `setupRecovery` (guardians) → `.success(())` | `// TODO: Deploy social recovery module` then reports success — nothing deployed. (Recovery *execution* `performGuardianRecovery` IS honest — fails if no module — so setup lies while recovery would fail.) | **Yes** (recovery setup) |
| **D4** | `Blockchain/Attestation/EASManager.swift:310` | `verifyWithResolver` → `.success(true)` | `// TODO: Call resolver` — returns valid without checking it. **Latent:** currently shielded because the upstream `verifyAttestation:288` is a TODO that returns `.failure` first; becomes a live fail-open the moment `verifyAttestation` is implemented. | Via attestation verify (shielded today) |

---

## ⚠️ MISLEADING — fake success off the funds path, or dead code that would be dangerous if wired

| # | File:line | Issue | Reachable |
|---|---|---|---|
| **M1** | `UI/Views/NFT/MintNFTView.swift:77,460` | `mint()` shows `mintSuccessView` "NFT Minted" with 0 execution calls | **Yes** (NFT → Mint) |
| **M2** | `0pnMatrx runtime/blockchain/agent_identity.py:81` | `_verify` sets `verified` from whether the *shared* platform wallet has any tx — never checks the agent's attestation; any agent name → `verified:true` | **Yes** — live `agent_identity` tool |
| **M3** | `0pnMatrx runtime/blockchain/wallet_abstraction/account_manager.py:197` | `sponsor_gas` → `{"sponsored":True,"user_pays":0.0}` sponsoring nothing | **No** — `AccountManager` is dead/test-only |
| **M4** | `0pnMatrx …/account_manager.py:57` | `get_or_create_session_wallet` returns a **keyless** `0x`+sha256 slice as a wallet | **No** — dead/test-only |
| **M5** | `UI/Views/Social/GovernanceView.swift:144` | vote sets `hasVoted = true` with **no** on-chain/service submission | **Yes** (Governance) — NOT mvpGated |
| **M6** | `Blockchain/Attestation/EASManager.swift:269` | `createBatchAttestations` → `// TODO: ABI-encode multiAttest` then `.success([])` — reports batch created, creates nothing (empty UID list) | callable on the attestation path |
| **M7** | `UI/Views/Dispute/DisputeView.swift:~105` | `submitDispute`/`vote` simulate with `Task.sleep(2s)` (+ `isDemo`) then succeed — no real submission | **Yes** (Dispute) — NOT mvpGated |
| **M8** | `UI/Views/Bridge/BridgeView.swift` | `bridge()` runs a `Task.sleep` 0.4s/2s/3s animation to a `"Sent"` status — no real bridge tx (fetches real routes = PARTIAL) | **Gated** — `mvpGated` (unreachable in MVP); ⚠️ only if ungated |

---

## Action-flow classification (every confirm/execute)

| Flow | File | Class |
|---|---|---|
| Send | `UI/Views/Wallet/SendView.swift` | 🚩 **SHELL** (D1) |
| Swap | `UI/Views/Wallet/SwapView.swift` | 🚩 **SHELL** + PARTIAL quote (D2) |
| NFT Mint | `UI/Views/NFT/MintNFTView.swift` | ⚠️ **SHELL** (M1) |
| Governance vote | `UI/Views/Social/GovernanceView.swift` | ⚠️ **SHELL**, reachable (M5) |
| Dispute submit/vote | `UI/Views/Dispute/DisputeView.swift` | ⚠️ **SHELL** (simulated), reachable (M7) |
| Bridge | `UI/Views/Bridge/BridgeView.swift` | ⚠️ **SHELL** (simulated) but **GATED** (M8) |
| Stake / Lend / Borrow / Liquidity / Yield | `UI/Views/DeFi/*`, `UI/Views/Wallet/StakingView.swift` | ☑️ **GATED** (`mvpGated` → unreachable; PARTIAL data only) |
| Receive | `UI/Views/Wallet/ReceiveView.swift` | ☑️ display-only ("success" = copy confirmation) |
| **Real signed transfer** | `UI/Views/Wallet/CryptoPaymentSheet.swift` | ✅ **WIRED (exists, unused)** — Face-ID-gated real signed transfer; the Phase 2 target for the shells |

---

## ☑️ BENIGN / honest / already-fixed (no action)

- **Already fixed this engagement:** `AppAttestManager.submitAssertion` (fake `isValid:true`
  removed), `gate_action` + `pre_action` (now fail-closed by action type).
- **Honest failure (no fake success):** `EASManager.verifyAttestation:288` (TODO →
  `.failure(.attestationNotFound)`); `performGuardianRecovery` (fails closed if no
  module/chain; real UserOp on success); `eas_client._is_configured` (fails closed).
- **Real logic (mis-greped):** `Component05_Identity:370` (real P256 `isValidSignature`),
  `Component07_Stablecoin:356` (real peg deviation), `Component09_AgentIdentity:371`
  (real capability/limit check), `ProofGenerator` (real proof + failure paths; only
  *peripheral* TODOs — QR image, short-code, ABI-decode), `BlockchainBridge:1812`
  (`return true` only after a real bridge request), `WalletView` "Sent" (tx-filter label).
- **Config-gated honest:** Apple Pay (`PassKitManager` — "never optimistically reports
  'paid'"); the Python placeholder helpers (`validation._is_placeholder`,
  `web3_manager.is_placeholder_value`, `telegram._placeholder`).
- **Swept clean of the pattern:** `0pnMatrx runtime/blockchain/services` (181 files,
  0 TODO→success), MTRX `Services/` (46 files, 0).
- **Benign total: ~130+** — display features returning empty, dead code with no callers,
  gated flows, and obvious placeholders.

---

## Phase 1 plan per item (reference — NOT done; the fix is honest failure, never wiring)

- **D1 / D2 / M1 / M5 / M7:** disable the confirm and show a clear "not available yet"
  state, or surface a real error — **stop showing "Transaction Sent" / "Minted" /
  "Voted" / "Submitted."** (Wiring to `CryptoPaymentSheet`/services is **Phase 2**, not
  Phase 1.)
- **D3:** `setupRecovery` guardians branch → return `.failure` / "recovery not set up,"
  not `.success(())`.
- **D4 / M6:** `verifyWithResolver` and `createBatchAttestations` → return `.failure`
  (or remove) instead of `.success(true)` / `.success([])`.
- **M2:** `_verify` reports honestly ("unverified") instead of asserting verified off an
  unrelated condition.
- **M3 / M4 / M8:** confirm dead/gated; if kept, make them fail honestly. No fix makes a
  fake more convincing.

**Stopping here per Phase 0. Read-only — nothing changed, nothing pushed. Awaiting your
review of this certified inventory before any Phase 1 fixing begins.**
