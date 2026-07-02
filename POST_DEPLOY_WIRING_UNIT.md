# POST-DEPLOY WIRING UNIT

**Status: BLOCKED** — every item below depends on deployed Base Sepolia
addresses and/or a live gateway. Nothing here fakes success today; each entry
is honest-gated. When the deployed addresses are pasted, this unit wires and
proves them at the next slice boundary.

Items bundled: **D2** (real swap execution) · **D3** (real recovery tx) ·
**M5** (governance vote submission — client call is pre-written and live-capable
once the gateway is deployed) · **M6** (batch EAS attestation writes) ·
**M7** (dispute file/vote/claim) · **D4** (EAS resolver/read verification).

## Pre-written in this pass (2026-07-02)

| Piece | Where | State |
|---|---|---|
| Swap route/execute request builders on the real gateway contract (`token_in/token_out/amount`, `wallet/route_id`) | `Services/SwapService.swift` | done, envelope-decoded; execute unreachable from UI until this unit fires |
| Governance vote builder (`proposal_id, voter, support`) + server `support`→`choice` kwarg fix | `Services/GovernanceService.swift` + `DAOView.castVote`; 0pnMatrx `gateway/service_routes.py` | vote SUBMISSION correct; DAO proposals **live-read BLOCKED** on a shape-matching route (see below) |
| Adversarial-verify remediation: paymaster `ReentrancyGuard` + NaN-stake guard + appeal-clears-claims + juror party-exclusion + 4 client fake-success theaters killed | multiple | done, gated |
| Dispute file/vote/claim builders on the real contracts | `Services/DisputeService.swift` | done, envelope-decoded |
| Dispute **server** routes `POST /api/v1/dispute/vote` + `/claim` + service methods (juror-panel-enforced vote; idempotent post-resolution claim; platform holds no funds) | 0pnMatrx `gateway/service_routes.py`, `runtime/.../dispute_resolution/service.py` | done, 8 tests green |
| Dispute file handler kwarg fix (was a guaranteed TypeError 500) | 0pnMatrx `gateway/service_routes.py` | done |
| Client EAS schema-UID slot | `Config/PendingCredentials.swift` `Attestation.schemaUID` | done (empty, fails closed) |
| Server EAS example fixed to the Base predeploy + chain-specific warning | 0pnMatrx `openmatrix.config.json.example` | done |

## Remaining wiring work when the unit fires

1. **D2** — flip SwapView's Confirm from the honest notice to
   `SwapService.executeSwap(routeId:)` using the server-issued route id;
   remove the hardcoded fee/route rows (`SwapView.swift:567-569`).
   NOTE: on-chain DEX execution via `Components.dex` stays legally blocked —
   the gateway path is the only sanctioned route.
2. **D3** — replace `WalletCreation.setupRecovery`'s honest failure
   (`WalletCreation.swift:707-717`) with a real guardian-registration write via
   `WalletTransactionService.submitCall`; the rotation path
   (`performGuardianRecovery` → `rotateOwner(bytes)`) is already real and gated
   on `Recovery.socialRecoveryModuleAddress`. The deployed module's ABI must
   expose `rotateOwner(bytes)`.
3. **M6** — implement `encodeMultiAttestRequest` in `EASManager` (ABI:
   `multiAttest((bytes32,(address,uint64,bool,bytes32,bytes,uint256)[])[])`,
   selector `0x44adc90e`), mirroring the existing single-attest
   `encodeAttestRequest` + ERC-4337 submit; schema from
   `PendingCredentials.Attestation.schemaUID` (empty → honest failure stays).
4. **D4** — implement `getAttestation(bytes32)` / SchemaRegistry
   `getSchema(bytes32)` as read-only `eth_call`s via the existing BaseNetwork
   JSON-RPC layer (needs only `Network.rpcURL`); then the resolver branch of
   `verifyWithResolver` resolves instead of honest-failing. EAS addresses are
   the Base predeploys already hardcoded (`0x4200…0021` / `0x4200…0020`).
5. **M5/M7 UI** — flip `GovernanceView.confirmVote` and `DisputeView`
   submit/vote/claim from honest notices to the pre-written service calls
   (all gated on `isBackendConfigured`).
6. **Runtime shape verification** — the typed decodes (SwapQuote, feed,
   staking, portfolio) intentionally throw on mismatch; verify against the
   live gateway and adjust models. Until then mismatches remain honest
   demo-fallbacks.

## EXACT keys to populate (the unit's trigger)

**MTRX `Config/PendingCredentials.swift`:**

| Field | For | Format |
|---|---|---|
| `Network.rpcURL` | everything on-chain (D2-on-chain/D3/M6/D4) | https URL |
| `AccountAbstraction.bundlerURL` | 4337 submits (D3, M6) | https URL |
| `AccountAbstraction.entryPointAddress` | 4337 | `0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789` (v0.6 canonical) |
| `AccountAbstraction.accountFactoryAddress` | 4337 | deployed `OpenMatrixAccountFactory` |
| `AccountAbstraction.paymasterAddress` | sponsored gas | deployed `OpenMatrixVerifyingPaymaster` |
| `AccountAbstraction.paymasterSignatureEndpoint` | sponsored gas | gateway `/api/v1/paymaster/sign` URL |
| `Recovery.socialRecoveryModuleAddress` | D3 | deployed recovery module (must expose `rotateOwner(bytes)`) |
| `Attestation.schemaUID` | M6/D4 | 0x + 64 hex, same as server `schemas.primary` |
| `Backend.gatewayURL` | D2-gateway, M5, M7, all remapped reads | deployed 0pnMatrx gateway URL |
| `Components.dex` | D2 on-chain (LEGALLY BLOCKED — leave empty for MVP) | — |

**0pnMatrx `openmatrix.config.json` (server):**

| Key | For |
|---|---|
| `blockchain.rpc_url`, `blockchain.chain_id` (84532) | chain reads/writes |
| `blockchain.eas_contract` (Base predeploy `0x4200…0021`) + `blockchain.schemas.primary/identity/payments` | server EAS writes; **must match the client schemaUID** |
| `blockchain.paymaster.{address, signer_key, bundler_url, entry_point, account_factory, policy}` | `/api/v1/paymaster/sign` (503 until set) |
| `blockchain.price_feeds.eth_usd` | Chainlink-primary price route |

## Known-open items surfaced by adversarial verify (2026-07-02)

- **DAO proposals live-read (M5 read side) — BLOCKED.** The gateway has no
  proposals list route whose response shape matches the client's
  `DAOProposalsResponse` (which needs number/proposer/votesFor/votesAgainst/
  quorumRequired). `list_proposals` in the governance service returns a
  different summary shape. Owed: a `GET /api/v1/dao/proposals` (or governance
  proposals) route that emits the client shape, OR a client model change to the
  service's shape. Until then `daoProposals()` decode-fails and the DAO tab
  stays honest-demo. Vote *submission* is already correct.
- **`sponsoredCallWithValue` (contract) — design decision owed.** Any
  `onlyAuthorized` agent can send arbitrary ETH to an arbitrary target; the
  `onlyOwner` `withdraw` guard is moot against a compromised/malicious agent
  key. Not exploitable at rest (OBSERVE/testnet, no agents authorized) and now
  `nonReentrant`, but before mainnet this needs a per-agent daily cap and/or a
  target allowlist (mirror the server paymaster `policy.allowed_actions`). Left
  as a policy decision, not silently changed.

## Proof plan at wiring time
Byte-exact digest cross-test stays green; forge suites green; a testnet
UserOp per flow (D2 gateway swap, D3 rotation, M6 batch attest) each verified
by reading the resulting state/attestation back from chain — no
submit-and-assume.
