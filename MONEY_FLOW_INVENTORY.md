# MONEY_FLOW_INVENTORY.md

**Definitive inventory of every value-moving flow — MTRX app (358 files) + 0pnMatrx platform.**
Read-only audit. Nothing changed, nothing built. Flags OFF, OBSERVE, testnet.

Legend — **State:** `WIRED` (real signed path) · `SHELL-honest` (honest "not available", nothing moves) · `mvpGated` (hidden in MVP build, `mvpMode = true`) · `FAKE-SUCCESS` (shows success / silent no-op for work not done).
**Guarded** = routes through the single guarded sign primitive (`ERC4337Manager.signOperation` → chain-locked to testnet 84532).
**Bio** = biometric (Face ID) before the value-moving step.

> Guard chain confirmed: the only real-send primitive is `BlockchainBridge.sendTransaction` → `submitSignedOperation` → `ERC4337Manager.signOperation`, which carries the P2.0 testnet lock. `mvpMode = true` (`Config/FeatureFlags.swift:20`), so every `mvpGated` flow renders `MVPUnavailableView` and is **not reachable** in the shipping build.

---

## TIER 1 — REACHABLE TODAY (user can trigger in the MVP build)

| # | Flow | file:line | Moves | State | Guarded | Bio | Reachable | Flag |
|---|------|-----------|-------|-------|:------:|:---:|:--------:|------|
| 1 | **Send (native ETH)** | `UI/Views/Wallet/SendView.swift:124` → `sendNative()` | native ETH | **WIRED** ✅ | ✅ | ✅ | ✅ | — the proven template (P2.2): biometric → advisory gate → guarded sign → success only on validated `0x` hash |
| 2 | **Contract deploy (Build hub)** | `UI/Views/Build/ContractView.swift:86` `deploy()` | gas (deploy) | **FAKE-SUCCESS** | ❌ no sign | ❌ | ✅ (`BuildView.swift:234`) | 🚩 sets `deploySuccess = true` after a 2.5 s timer; no chain, no sign. Offline branch also fakes success via MeshOutbox. **Phase 1 did not cover this.** |
| 3 | **Contract deploy (Deploy sheet)** | `UI/Views/Contract/DeployContractView.swift:126` `deploy()` | gas (deploy) | **FAKE-SUCCESS** | ❌ no sign | ❌ | ✅ (`BuildView.swift:243`) | 🚩 `Task.sleep(3s)` → sets `deployedAddress` (demo) + success haptic. Honest code-comment, but the **UI shows success**. |
| 4 | **NFT transfer** | `UI/Views/NFT/NFTDetailView.swift:44` `transfer()` | NFT (ERC-721) | **FAKE-SUCCESS** (silent no-op) | ❌ | ❌ | ✅ (`NFTGalleryView.swift:303`) | ⚠️ `Task.sleep(1s)` → clears spinner, no transfer, **no honest failure** → reads as done. (`makeOffer()` at :53 is the same.) |
| 5 | **NFT mint** | `UI/Views/NFT/MintNFTView.swift:77` `mint()` | gas + mint | **SHELL-honest** ✅ | n/a | n/a | ✅ | "Minting isn't available… Nothing was minted." (Phase 1) |
| 6 | **Dispute vote / claim** | `UI/Views/Dispute/DisputeView.swift:113` `vote()`, `:121` `claimWinnings()` | jury vote / payout (stake form present) | **SHELL-honest** ✅ | n/a | n/a | ✅ | both honest ("No vote was recorded" / "Nothing was claimed") (Phase 1) |
| 7 | **Chat transfer (Morpheus)** | `UI/Views/Agent/AgentConversationViewModel.swift:~360, ~892` | (intended) crypto/fiat transfer | **DEMO** (not wired) | ❌ | ✅ | ✅ | ⚠️ biometric gate + Morpheus narration → `presentConfirmation`. **No `sendTransaction`/`submitSignedOperation` anywhere in the file** → never executes a real send. Verify the confirmation doesn't imply "sent" when wiring. |

---

## TIER 2 — GATED (`mvpGated`, `mvpMode = true` → renders `MVPUnavailableView`, NOT reachable)

> All simulated underneath (`Task.sleep`); each needs the full Send treatment **and** an un-gate/licensing decision before wiring. Regulated set.

| # | Flow | file:line | Moves | Underlying state | Flag |
|---|------|-----------|-------|------------------|------|
| 8 | **Swap** | `UI/Views/Wallet/SwapView.swift` (`_regulatedBody.mvpGated()`) → `BlockchainBridge.swift:989` `swap()` | token↔token | view SHELL-honest + **gated**; **bridge method = FAKE-SUCCESS** | 🚩 `swap()` returns the **server-echo** `txHash` then does the real submit with `_ = try? await submitSignedOperation(...)` — error swallowed. **Do not reuse as-is.** Server-mediated (`blockchain/dex/swap` endpoint + DEX router not built). |
| 9 | **DeFi — Staking** | `UI/Views/DeFi/StakingView.swift:131/143/155` `stakeETH`/`unstake`/`claimRewards` | ETH stake | mvpGated; SIMULATED (`Task.sleep` ×4) | — |
| 10 | **DeFi — Yield** | `UI/Views/DeFi/YieldView.swift:151` `deposit()` | token deposit/withdraw | mvpGated; SIMULATED (×2) | — |
| 11 | **DeFi — Lending** | `UI/Views/DeFi/LendingView.swift:140` `submitAction()` (borrow/lend/repay/supply via `beginAction`) | borrow/lend/repay | mvpGated; SIMULATED | — |
| 12 | **DeFi — Liquidity** | `UI/Views/DeFi/LiquidityView.swift:109/120` `addLiquidity`/`removeLiquidity` | LP add/remove | mvpGated; SIMULATED (×3) | — |
| 13 | **Bridge** | `UI/Views/Bridge/BridgeView.swift:464` `viewModel.bridge(` | cross-chain bridge | mvpGated; SIMULATED | — |

---

## TIER 3 — DEAD / UNWIRED (exists, no view presents it)

| # | Flow | file:line | State | Flag |
|---|------|-----------|-------|------|
| 14 | **Crypto payment sheet** | `UI/Views/Wallet/CryptoPaymentSheet.swift:171` `pay()` → `:196` `sendTransaction` | real-send path: **Bio ✅** but shows `.success` (`:198`) **without validating the returned hash** (no `guard hash.hasPrefix("0x")`) **and skips the advisory gate**. Unreferenced → **dead**. | ⚠️ If ever wired, it's a Send-class bug (fake-success on empty hash + no gate). Fix or delete. |

---

## TIER 4 — BACKEND EXECUTION LAYER (not directly user-reachable)

**`BlockchainBridge` value-moving methods** (`Core/Blockchain/BlockchainBridge.swift`) — most are **unwired** to any reachable UI; each must be classified/hardened when its UI is wired:
- `sendTransaction:409` — **real, guarded** (the one good path; used by Send).
- `swap:989` — 🚩 **FAKE-SUCCESS** (see #8).
- server-mediated `postToAPI` stubs, currently unwired to reachable UI: `deployContract:472`, `mintNFT:511`, `stake:549`, `sendPayment:950`, `claimReward:1039`, `unstake:1123`, `repayLoan:1160`, `mintStablecoin:1448`, `redeemCashback:1592`.

**30 Components** (`Blockchain/Components/Component01–30/`) — backend plumbing. **None referenced from any UI view** → not directly user-reachable. Only `NFTManager` (C03) + `DAOManager` (C06) call the guarded `signOperation`; both now covered by the `ERC4337Manager.signOperation` chain guard (P2.0).

**0pnMatrx platform** (`runtime/blockchain/*.py`) — reached only via the gateway, gated by `gate_action` (fail-closed, action-type-aware). Each component service exposes `execute()`; protocol routers: `defi_router.execute_swap:304` / `execute_yield_deposit:269`, `cross_chain_router.execute_bridge:158`, `intent_resolver.execute_plan:231`; service methods (gaming, rwa `transfer_ownership`/`claim_income`, restaking `withdraw_restake`, fundraising `claim_vested`, …).
- **`web3_manager.send_transaction:157` = the only server-side signer** — signs with the **paymaster key** + broadcasts (gas sponsorship). **Non-custodial invariant holds**: the server cannot sign **user** funds (user's device key signs UserOps); the paymaster key moves only its own gas ETH. Gated by `gate_action`.

---

## ⚠️ THE DANGEROUS LIST (fake-success / silent no-op — same class as the Send bug)

Ordered by reachability:

1. 🚩 **Build/ContractView.deploy:86** — reachable fake-success (no sign, no biometric).
2. 🚩 **Contract/DeployContractView.deploy:126** — reachable simulated success (no biometric).
3. ⚠️ **NFTDetailView.transfer:44** (+ `makeOffer:53`) — reachable silent no-op (reads as success).
4. ⚠️ **AgentConversationViewModel chat transfer** — reachable scripted demo; verify `presentConfirmation` doesn't fake "sent".
5. 🚩 **BlockchainBridge.swap:989** — fake-success (server txHash + `try?`-swallowed submit). Gated at the UI, but the method is poisoned.
6. ⚠️ **CryptoPaymentSheet.pay:196** — real send w/ biometric but no hash-validation + no gate. Dead/unwired.

**Good news:** no *reachable* path executes a **real** on-chain send without biometric. The only WIRED real send is **Send**, which has biometric + gate + hash validation. The reachable "dangerous" entries are fakes/demos/no-ops, not unguarded real sends.

---

## SUGGESTED WIRING SEQUENCE (reachable-first, one at a time, Send template)

1. **Contract deploy** (consolidate ContractView + DeployContractView → real `WalletTransactionService` deploy) — *reachable fake-success, highest priority.*
2. **NFT transfer** (NFTDetailView) — *reachable silent no-op.*
3. **NFT mint** (MintNFTView) — *reachable; honest today → wire to real mint.*
4. **Chat transfer** (Morpheus → `presentConfirmation`) — *reachable demo; route to the real Send path; verify no fake "sent".*
5. **Out-of-band fixes** (do regardless of gating): repair `BlockchainBridge.swap:989` fake-success; fix-or-delete `CryptoPaymentSheet`.
6. **Gated tier** (Swap, DeFi ×4, Bridge) — each needs the un-gate/licensing decision **and** its real path; Swap already scoped as the larger server-mediated build (S1–S5).

Every wiring step: biometric → advisory gate → guarded sign → success only on a real result → honest failure otherwise → adversarial self-verify → package for review → hold push.
