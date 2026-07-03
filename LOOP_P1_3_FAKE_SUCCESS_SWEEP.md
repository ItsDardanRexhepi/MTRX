# P1-3 — Exhaustive fake-success re-sweep (MTRX view layer)

Swept every `Task.sleep` / `asyncAfter` / `DispatchQueue…after` in `UI/`,
`Services/`, `ViewModels/` (102 occurrences across 62 files) with a deterministic
analyzer, then hand-verified every non-loader hit. Classification rule (R10):

- **Demo-data loader** — populates sample data + sets `isDemo` on screen load →
  **LEAVE** (the screens are intentionally explorable demo per the owner's request).
- **Demo interactivity** — a delay→list-mutation that carries **no** money / on-chain /
  regulated semantics (e.g. following a profile, posting to a demo group feed) →
  **LEAVE** (part of the explorable demo; claims no consequential outcome).
- **Consequential fake action** — a delay→success for something that, wired, would
  move money, submit an on-chain tx, or create/verify a regulated record → **CONVERT**
  to honest failure via `.honestActionAlert` (`actionUnavailable = true`, change no state).

## CONVERTED to honest failure (18 functions, 13 files)

| # | File | Function | Why consequential |
|---|---|---|---|
| 1 | ContentPublishingView | `sendTip` | value transfer (tip) |
| 2 | CreatorView | `launchToken` | launches a financial token |
| 3 | DelegationView | `delegate` | delegates token/voting power (chain) |
| 4 | DelegationView | `undelegate` | revokes delegation (chain) |
| 5 | AttestationView | `createAttestation` | on-chain EAS attestation |
| 6 | VerifiableCredentialView | `issueCredential` | issues a regulated credential |
| 7 | VerifiableCredentialView | `verifyCredential` | fabricated "Valid" verification |
| 8 | AccessControlView | `submitGrant` | grants a contract role (access control) |
| 9 | StreamingView | `createStream` | starts a money-flow payment stream |
| 10 | MultiSigView | `createWallet` | deploys a multi-sig wallet |
| 11 | MultiSigView | `proposeTransaction` | proposes a value transaction |
| 12 | MusicView | `uploadTrack` | configures royalty economics / on-chain |
| 13 | MusicView | `claimEarnings` | claims (zeros) earnings — money |
| 14 | DomainView | `register` (+ `Renew` button) | ENS registration/renewal — money/chain. `Renew` was an adjacent non-sleep fake ("extended on-chain" alert) caught during conversion and gated too. |
| 15 | AgentIdentityView | `registerCapability` | mutates agent DID record |
| 16 | AgentIdentityView | `revokeAgent` | revokes an agent DID |
| 17 | KYCView | `captureDocument` | fabricated "verified" KYC badge |
| 18 | TreasuryView | `submitProposal` | treasury/governance proposal |

## LEFT deliberately (with reason)

| File | Function | Classification |
|---|---|---|
| GovernanceView | `confirmVote` | already honest — `hasVoted` drives an honest "not available yet" message, no success claim |
| HomeView | `confirm` | honest demo wallet — uses `walletManager.demoSend/Swap/Stake` against a real demo-balance ledger; fails on insufficient balance |
| AgentConversationViewModel | `executePendingAction` | honest demo wallet — every reply is explicitly "(demo) … Simulated — not broadcast on-chain", real balance checks |
| WalletView | `connect` | already honest — links a demo account with a masked detail and ZERO balance, explicitly commented |
| AttestationView | `verifyAttestation` | local lookup over already-loaded demo attestations; changes no state |
| KYCView | `simulateProofProgress` | labelled `zk-demo-` progress animation (no on-device prover) |
| MusicView | `simulatePlayback` | playback progress-bar animation |
| GroupsView | `createGroup`, `postToGroup` | demo social interactivity (no money/chain/regulated record) |
| SocialGraphView | `toggleFollow` | demo social interactivity |
| Games (Block/ColorBurst/2048/Runner/Solitaire) | move/swap/clear/tap/collect | game mechanics; not actions |
| Search (MusicHub/MusicLibrary/Domain/Social) | `runSearch`/`search` | read/lookup, not a state-changing action |
| Various | `load`/`loadX`/`refresh`/`loadAll` | demo-data loaders (set `isDemo`) — the explorable demo surface |
| LaunchView `openPortal`, SocialPlatform `startProgress`, SocialView `showFeedback`, StorageView `copyCID`, ConversationStore `persist`, Agent `navigate` | — | UI animation / feedback / persistence, no fabricated action success |

## Known follow-up (not a honesty defect)
Several converted actions are triggered from inside a `.sheet` (register,
createWallet, proposeTransaction, submitProposal, createStream, launchToken,
issueCredential, createAttestation, submitGrant, uploadTrack). The
`.honestActionAlert` is attached to the view's root, so while the sheet is up the
alert may not present over it — the button simply changes no state (no fabricated
success). Making the honest message visible over the sheet (inline error or
dismiss-then-alert) is UX polish, tracked separately. The R10 requirement — no
fake success, no state change — is fully met.

## Postcondition
Zero consequential fake-action patterns remain. `SigningWallTests` + Morpheus
tests unaffected (no signing/security code touched). MTRX builds green.
