# Morpheus Security Advisor — Specification (M-SPEC)

Status: **DRAFT for review.** No code. Read-only analysis. Hold for approval before M-STATE.
Posture: Flags OFF, OBSERVE, testnet. The walls do not move.
Revision: v2 (hardened after an adversarial self-critique — see §9 for what changed and why).

---

## 0. The inviolable invariant

**Morpheus is an ADVISOR, never an enforcer.** He watches, warns, explains, surfaces security
state, and recommends. His output is **never** the thing that decides whether money moves or a key
signs.

The deterministic walls — testnet chain lock, biometric Secure-Enclave gate, fail-closed money
paths, gated-key enforcement — stay exactly as they are and remain the **only** things that
enforce.

**The test for every piece of this workstream:** if Morpheus were deleted entirely, the actual
security must be byte-for-byte identical. If we ever find ourselves writing
`if morpheusApproves { sign() }` — or anything where Morpheus's judgment gates a real action — we
STOP. Morpheus informs the human (and a deterministic rule enforces); Morpheus never decides.

This already holds in the codebase today and we keep it that way (see §6).

### Naming (read this before anything else)

The word **"Morpheus" already names two different things in this codebase**, and the firewall in
this spec must not rest on the name:

- **The client advisor** — the on-device agent in `Core/Morpheus/` this workstream builds. This is
  what "Morpheus" means everywhere in this document.
- **A pre-existing server-side gate** — the server security preflight
  (`MTRXAPIClient.securityPreflightAllowsSend`, `:2413`), whose deny boolean is **load-bearing**:
  it aborts a real send (`SendView.swift:114`). Code comments already call it "Morpheus"
  (`MTRXAPIClient.swift:2426`, `AgentAccessControl.swift:8`). **It is not the client advisor.**

**Throughout this spec, "Morpheus" = the client advisor only.** The server gate is referred to as
the **"server security preflight."** The client advisor must never become, call, feed, or read the
preflight's boolean (see §6 danger zone). This naming collision is the single most likely place the
line could be crossed by accident.

---

## 1. The advisor / enforcer line (where it sits)

```
        ADVISOR LANE (Morpheus)                 ENFORCEMENT LANE (the walls)
   ─────────────────────────────────       ────────────────────────────────────────
   reads deterministic state  ───read──▶   testnet chain lock   (ERC4337Manager.signOperation
   narrates / warns / recommends            :754  guard isSigningPermitted)
        │                                   biometric Secure-Enclave gate (SecureEnclaveManager
        │ (text + voice only)               .sign(...context:)  .biometryCurrentSet)
        ▼                                   fail-closed send path (SendView.sendNative + bridge)
   the HUMAN reads it and decides           gated-key enforcement (signForValue / isGated / restore
        │                                   re-validation / reset re-probe)
        ▼                                   server security preflight (separate, server-side)
   the human taps (or doesn't)   ───────▶   ...all run regardless of anything Morpheus said
```

- The advisor lane **only reads**. It never returns a value consumed by a signing or money-moving
  decision.
- The enforcement lane decides. It does not call into Morpheus, does not read his output, and does
  not depend on him existing.
- The two lanes meet **only at the human**: Morpheus speaks; the person decides; a deterministic
  wall then enforces independent of both.

### The deterministic walls Morpheus observes (the things that actually enforce)

| Wall | Where it enforces | Fails… |
|---|---|---|
| Testnet-only signing lock | `ERC4337Manager.signOperation` `Blockchain/Wallet/ERC4337Manager.swift:754` (`guard networkConfig.isSigningPermitted`, == chainId `84532`); defense-in-depth `BlockchainBridge.assertTestnetSigning()` `Core/Blockchain/BlockchainBridge.swift:347`; connect-time chain-id check `BaseNetwork.connect` `:252` (check at `:264`) | closed (throws before any hash/signature) |
| Biometric Secure-Enclave gate | `SecureEnclaveManager.sign(_:tag:context:)` enclave key under `.privateKeyUsage + .biometryCurrentSet`; declined Face ID → `KeyError.authenticationRequired`, no signature | closed |
| Gated-key value enforcement | `SecureEnclaveManager.signForValue` `:192` + `isGated(tag:)` `:211` (probes the **real** access control, non-spoofable); `enforceGatedOwnerKeyForValue` `:26` (OBSERVE today, REFUSE at go-live); restore re-validation `WalletCreation.restoreActiveWallet :301`; reset re-probe `:359` | closed (at go-live); OBSERVE-logged today |
| Fail-closed send path | `SendView.sendNative` `UI/Views/Wallet/SendView.swift:102` biometric gate → **server security preflight consult** `:112` (a *separate* server gate; aborts on explicit deny, **fail-OPEN when the backend is absent**, `MTRXAPIClient.swift:2415`) → bridge guards → success **only** on a valid `0x` hash `:127` | closed on biometric/chain/hash; preflight is best-effort |

The send path has **three** decision points (biometric → server preflight → valid-hash), named in
full here so no one mistakes the client advisor for the "missing" preflight — the server preflight
already exists at `SendView.swift:112-117`. None of these is the client advisor.

These walls are unchanged by this workstream and are not touched by any Morpheus code.

---

## 2. What Morpheus is today (starting point)

Morpheus already exists as a client-side advisory persona. Nothing about him is load-bearing on
money or keys — confirmed:

- Agent identity: `AgentAccessControl.ActiveAgent.morpheus` (`Core/Security/AgentAccessControl.swift`). Routing only; the file header already says it is **UX-only, not the security boundary**.
- Persona prompt: `FoundationModelsEngine.morpheusInstructions` (`Core/Trinity/InferenceRouter.swift:76`) — "guardian agent… protection is your domain; execution is Trinity's." **No** money tools wired to him.
- Detection/intervention machinery: `Core/Morpheus/Morpheus.swift`, `MorpheusInterventions.swift`, `MorpheusTriggers.swift`, `MorpheusThreshold.swift`, `MorpheusVoice.swift` (deeper/slower voice + severity chimes).
- His warnings are pure UX: `MorpheusInterventions.confirmAction()`'s return value is **discarded** by enforcement (`AgentConversationView.swift:1042` calls it as `_ =`); `TradingView.morpheusWarning` is display text with no lever to block a trade.

---

## 3. The read-only security-state layer (what M-STATE will expose)

The foundation both surfaces need: a single read-only façade that lets Morpheus *observe* the
deterministic state below. **It reads; it cannot touch.** Every read is captured into an
**immutable value snapshot** (plain `Bool`/`Int`/`String`/`Double`) — the façade never holds or
returns a reference to a live mutable singleton, and never exposes a setter (see §6). Exact
signatures get pinned when M-STATE is implemented; sources below are verified.

### 3a. Global posture (always available)

| State | Reads | Source |
|---|---|---|
| On testnet vs mainnet | configured chain id vs the only permitted signing chain | `PendingCredentials.Network.chainID` (`Config/PendingCredentials.swift:113`, default `84532`); `BaseNetworkConfig.permittedSigningChainID` (`ERC4337Manager.swift:1042` = `84532`), `baseMainnetChainID` (`:1044` = `8453`) |
| Testnet signing lock is in force | the wall's own predicate | `BaseNetworkConfig.isSigningPermitted` (`ERC4337Manager.swift:1047`) |
| Chain configured (live vs demo) | `isChainConfigured` | `PendingCredentials.swift:40` |
| Backend / gateway configured | `isBackendConfigured` | `:58` |
| Gas sponsorship configured | `isGasSponsorshipConfigured` | `:49` |
| App Attest enabled / enforced | `isAppAttestEnabled` / `isAppAttestEnforced` | `:225` / `:228` (both OFF today) |
| Gated-key enforcement armed | snapshot the **value** of `SecureEnclaveManager.enforceGatedOwnerKeyForValue` | `Core/Wallet/SecureEnclaveManager.swift:26` — **⚠ this is a writable `static var`, not a constant** (it gates REFUSE vs OBSERVE in `signForValue` `:198`). The façade copies its value into an immutable field and **must never assign it**. (See §6.) |
| Regulated features hidden (MVP) | `FeatureFlags.mvpMode` / `regulatedFeaturesEnabled` | `Config/FeatureFlags.swift:20` / `:23` |

### 3b. Wallet / key security (per-wallet)

| State | Reads | Source |
|---|---|---|
| Secure Enclave available on device | `isSecureEnclaveAvailable` | `SecureEnclaveManager.swift:47` |
| **This owner key is biometric-gated** | `isGated(tag:)` — probes real access control, non-spoofable | `:211` |
| Face ID / Touch ID available + which | `BiometricAuth.canUseBiometrics` / `.biometryType` | `Core/Wallet/BiometricAuth.swift:35` / `:27` |
| `requireBiometricForSigning` (user pref) | snapshot the **value** — a settable `var`; gates the **off-chain identity-proof** signer (`WalletCore.sign :85`), **not** the on-chain money path | `Core/Security/SecurityPreferences.swift:48` (see §6 danger zone) |
| Wallet restore / readiness | `WalletCreation.restoreActiveWallet()` → `.restored / .needsReset(reason) / .identityOnly / .noWallet` | `Blockchain/Wallet/WalletCreation.swift:301` |
| Recovery guardians present (count) | `getGuardians()` (non-secret addresses+names) | `WalletCreation.swift:474` |
| Cloud backup registered | **needs a new read-only getter** — `cloudBackupID` is `private` (`WalletCreation.swift:203`); M-STATE must expose a small `hasCloudBackup` probe (e.g. over the recovery iCloud-keychain entry) rather than read the private field | `WalletCreation.swift:203` / iCloud-keychain presence |
| App Attest readiness | `AppAttestManager.readiness` / `.hasKey` / `.isSupported` | `Apple/Security/AppAttestManager.swift:67` / `:65` / `:64` |

### 3c. Per-action context (only when an action is being composed)

| State | Reads | Source | Groundable? |
|---|---|---|---|
| **This send requires Face ID** | the **native-send** flow always biometric-gates before signing **and** the signer key is gated | `SendView.sendNative:102` (unconditional) + `isGated(tag:)` | **Yes for native sends.** NOT a generic "any action requires Face ID" — the off-chain identity-proof signer is conditional on `requireBiometricForSigning` (`WalletCore.sign:85`). Scope the warning to the path actually running. |
| **Recipient is not in your contacts** | no matching wallet address in the contact book | `ContactsManager.mtrxContacts` (`Apple/Interaction/ContactsManager.swift:16`) — a real membership check (not the `suggestRecipients` prefix matcher) | **Yes** — deterministic local read |
| ~~Recipient is new (no prior send)~~ | *(deferred — see §5)* native sends currently persist **no** `TransactionRecord` (only the ERC-20 log indexer writes them, `TransactionIndexer.swift:83`), so "have I sent here before?" is blind to native sends | — | **No, not yet** |
| **Amount crosses one of your thresholds** | compares a **USD amount** to the user's own limits (and today's running total for the daily one) | `SecurityPreferences.shared` extraConfirm ($1k) / coolingOff ($10k) / dailySoft ($25k) (`Core/Security/SecurityPreferences.swift:25-28,75-90`), snapshotted to values | **Yes vs the user's settings — BUT** the USD amount itself is `amount × priceUSD` from a **live price feed** (`SendView.swift:44`; CoinGecko / gateway, demo fallback). Treat as **price-feed-dependent**, not pure local state; phrasing must reflect that (§5). |
| **No verification record for this contract** | whether MTRX has a verified record / ABI for the target | `ContractRecord.isVerified` (`Data/Models/ContractModel.swift:178`) / `ContractService.getContractABI` | **Partial** — server-asserted; narrate as "no verification record," never as "audited" or "unsafe" (§5) |
| **Action is a contract interaction / irreversible** | the **live action-kind** being initiated (send / swap / deploy / NFT) | the action being composed | **Yes** (do **not** ground this on `TransactionRecord.direction == .contractInteraction` — that enum case is never assigned in production, `TransactionModel.swift:54`) |

`TransactionRecord` field anchors for any later history read: `to` at `Data/Models/TransactionModel.swift:66`, `direction` at `:82` (enum `:50-55`).

---

## 4. What Morpheus watches (the two destination surfaces)

Built later, one at a time, **after** M-STATE is verified. Listed here only so the foundation
covers what they need.

1. **Pre-transaction guardian.** Before a risky money action reaches the hard gate, Morpheus
   surfaces what he *observes* from §3c (recipient not in contacts, a threshold crossed, no
   contract record, irreversible kind, this send requires Face ID), warns, and recommends. The user
   decides. The deterministic gate then enforces, exactly as it does with Morpheus absent.

2. **Whole-app security narrator.** Morpheus surfaces posture from §3a/§3b so the user always
   understands what is protecting them ("you're on testnet — nothing moves real funds," "your
   signing key is Face-ID-gated," "no recovery guardians yet"). Pure explanation of true state.

Neither surface introduces a code path where Morpheus's judgment gates an action.

---

## 5. Warnings catalogue — every warning and its grounding

Rule: **a warning ships only if it derives from real, observable deterministic state.** No vibes,
no guesses, no unprovable claims. Where state is price-feed-dependent or server-asserted, the
phrasing says so.

### In-scope (grounded) — eligible for the later surfaces

| Warning | Grounded in (real state) | Honest phrasing | Gates? |
|---|---|---|---|
| "You're on testnet — this won't move real funds" | chainID == 84532 / `isSigningPermitted` | factual | No |
| "This send will require Face ID" *(native send only)* | unconditional send-flow gate + `isGated(tag:)` | factual, scoped to the send | No (the gate enforces) |
| "Your signing key is Face-ID protected" | `isGated(tag:) == true` | factual | No |
| "Your key isn't biometric-gated" *(edge/legacy)* | `isGated(tag:) == false` | factual; recommend reset | No |
| "This address isn't in your contacts" | not in `ContactsManager.mtrxContacts` | factual (contacts only) | No |
| "This looks above your $X confirmation threshold" | priced amount vs `extraConfirmThresholdUSD` | factual **with a price caveat** ("at the current price") | No |
| "This would trigger your 1-hour cooling-off delay" | priced amount vs `coolingOffThresholdUSD` + `coolingOffEnabled` | factual, references the user's own setting | No |
| "This looks above your daily soft limit ($25k)" | today's priced outgoing total + amount vs `dailySoftThresholdUSD` | factual **with a price caveat** | No |
| "We have no verification record for this contract" | `ContractRecord.isVerified == false`/absent | factual about **our records**, not the contract's safety | No |
| "This is a contract interaction / irreversible" | live action-kind | factual | No |
| "Backend security service isn't connected" | `isBackendConfigured == false` | factual posture | No |
| "No recovery guardians set up" | `getGuardians().isEmpty` | factual | No |

### Deferred — not groundable today (would require new observable state first)

Explicitly **out of scope** until backing state exists; grounding them now would be guessing:

- **"You haven't sent to this address before"** — native sends persist **no** `TransactionRecord`,
  so a send-history lookup is blind. Deferred until native sends are persisted (a separate code
  change) or grounded contacts-only. (Contacts membership ships now; send-history does not.)
- "This is unusually large *for you* / 5× your average" — **no spending baseline/percentile state.**
- "This contract is unaudited / unsafe" — **no local audited-contract registry**; only a
  server-asserted `isVerified`. We may only say "no verification record," never assert safety.
- "This address is risky / flagged / scammy" — **no per-address reputation state.**
- "Device may be compromised" — no ongoing device-integrity signal beyond one-time App Attest.

### Forbidden — never specified

- Any warning whose truth Morpheus cannot observe from deterministic state.
- Any warning wired such that dismissing/heeding it changes whether the action proceeds.
- Any warning that asserts a price-dependent or server-asserted fact as if it were certain local
  truth (must carry the caveat).

---

## 6. Where the line sits — explicit rules & danger zone

**Rules for all Morpheus code in this workstream:**

1. Morpheus code is **read-only** w.r.t. every wall. The façade exposes value getters only — **no**
   setter, no toggle, no "approve," no veto — and copies mutable globals into immutable snapshots
   (it never returns a reference to a live mutable singleton).
2. No enforcement path may **read** a Morpheus value to decide. Signing, chain lock, biometric
   gate, gated-key refusal, the send success/abort, and the server preflight all stay computed from
   deterministic state alone.
3. Morpheus may **narrate** an enforcer's outcome ("the security service declined this," "the key
   isn't gated") **only by reading state already computed by the action's own flow** — never by
   invoking the enforcer himself.
4. Every warning maps to a row in §5's in-scope table or it doesn't ship.
5. "Morpheus" denotes the **client advisor** only (see §0 Naming).

**Danger zone — the specific places the line could be crossed and must not be:**

- **The server security preflight.** Morpheus/M-STATE code must **never** import, call, or feed
  `securityPreflightAllowsSend` (`MTRXAPIClient.swift:2413`),
  `postFundMovingAttested(path:"/api/v1/security/preflight")`, or the `securityBlocked` /
  `isSecurityBlock` error (`:18`,`:76`). Narrating "the security service declined this" must read
  the send's **already-computed** failure state, never produce or influence that boolean.
- **`SecureEnclaveManager.enforceGatedOwnerKeyForValue`** is a writable `static var` (`:26`) that
  arms the go-live gated-key wall. Advisor code may capture its **value**; it must **never** assign
  it. *(Recommended hardening: make it `private(set)` / function-gated so it cannot be flipped from
  advisor code — see §8.)*
- **`SecurityPreferences.shared`** is a live `@Observable` singleton whose thresholds **and**
  `requireBiometricForSigning` are public settable `var`s; `requireBiometricForSigning` feeds a real
  signing decision (`WalletCore.sign:85`). M-STATE reads these into an immutable snapshot and
  **never** writes them (no auto-tightening/loosening).
- **`MorpheusInterventions.confirmAction()`** return value is discarded today; it must **stay**
  discarded by enforcement.
- **`SecureEnclaveManager` / `BiometricAuth`** gain **no** Morpheus parameter, no Morpheus check, no
  advisor-aware branch.

**Remove-Morpheus test:** deleting `Core/Morpheus/` and the new state layer leaves the chain lock,
enclave gate, gated-key refusal, fail-closed send, and server preflight behaving identically. This
is true today **by inspection**, and M-STATE adds the first deterministic test that proves it (§7).

---

## 7. Sequencing (this workstream)

1. **M-SPEC (this document)** — read-only analysis + spec. → **HOLD for your read.**
2. **M-STATE (next, only on your approval)** — the read-only security-state layer from §3: a single
   façade (e.g. `MorpheusSecurityState`) returning **immutable value snapshots** of the
   deterministic state, wrapping the §3 reads behind read-only getters. **No** warning flows, **no**
   surfacing UI. Includes:
   - the façade + snapshot value types for §3a/§3b (and the §3c reads the guardian needs);
   - the small new `hasCloudBackup` read-only probe (since `cloudBackupID` is private);
   - tests asserting the façade only reads (no setter/reference escape), **plus the first
     deterministic wall test** — signing against mainnet `8453` throws `signingChainNotPermitted`,
     and a build with `Core/Morpheus/` + the façade removed still enforces it.
   Verified against the full Swift test suite (currently **117 executed, 3 skipped**), packaged,
   held for read.
3. *(Later, one at a time, each held)* — Pre-transaction guardian surface; then whole-app security
   narrator. Not part of M-SPEC or M-STATE.

**M-STATE will NOT include:** any warning logic, any UI, any change to a wall, any new write
surface. Out of scope and untouched, as before: the ~14 unbadged demo views, games, M1b, M2.

---

## 8. Open decisions for you

1. **Façade shape** — one immutable `MorpheusSecurityState` snapshot struct (read once) vs an
   `@Observable` live reader. *(Recommendation: immutable snapshot per query — it makes "read-only,
   no reference escape" provable, and an advisor narrates a moment in time.)*
2. **Price-dependent thresholds** — the amount/threshold warnings depend on a live price feed. Ship
   them now **with an explicit price caveat** ("at the current price"), or restrict to a
   native-denominated threshold, or defer them until pricing is more robust? *(Recommendation: ship
   with the caveat; it's honest and still useful.)*
3. **Recipient send-history** — ships **contacts-only** now ("not in your contacts"). The stronger
   "you haven't sent here before" needs native sends to persist a `TransactionRecord` (a small
   separate code change). Want that change folded into the guardian phase, or left out?
4. **Harden `enforceGatedOwnerKeyForValue`** — make it `private(set)` / function-gated so advisor
   code (or anything) can't flip the go-live wall. Worth doing as a tiny standalone change?
5. **"No verification record" wording** — confirm you're comfortable with the strictly-honest
   framing (we never assert a contract is audited/safe, only that we do/don't have a record).

---

## 9. What changed in v2 (from the adversarial self-critique)

A multi-lens critique (line-integrity / grounding / completeness, each finding adversarially
verified) found and this revision fixed: the **"Morpheus" naming collision** with the load-bearing
server preflight (§0, §6); `enforceGatedOwnerKeyForValue` and `SecurityPreferences` being **writable
surfaces** the façade must snapshot, not reference (§3, §6); the **price-feed dependency** of the
USD thresholds (§3c, §5); two warnings grounded on **dead/empty state** — native sends write no
`TransactionRecord`, and `.contractInteraction` is never assigned — now corrected/deferred (§3c,
§5); the **server preflight** named as a real send-path decision point (§1); the **off-chain
identity-proof** Face-ID nuance (§3b, §5); a missing **cooling-off** in-scope warning (§5);
`requireBiometricForSigning` added to the state catalogue (§3b); the walls-intact claim re-scoped to
**"true by inspection; M-STATE adds the first test"** (§6, §7); and corrected source line anchors
throughout §1/§3.
