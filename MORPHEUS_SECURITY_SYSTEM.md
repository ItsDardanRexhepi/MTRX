# Morpheus Security System

The named security system inside MTRX. Posture: Flags OFF, OBSERVE, testnet. The walls don't move.

Morpheus is the app's security identity — a **guardian that watches, warns, explains, and recommends.**
This document is the identity of record: what Morpheus is, what he is *not*, the two layers he spans,
and the one line that must never be crossed.

---

## The inviolable principle

**Morpheus advises; he never enforces.** His output is never the thing that decides whether money moves
or a key signs. The deterministic walls — the testnet chain lock, the biometric Secure-Enclave gate, the
fail-closed money paths, the gated-key refusal — are the only things that enforce, and they enforce
whether Morpheus is right, wrong, silent, or absent.

**The test for every part of Morpheus:** if the entire `Core/Morpheus/` layer were deleted, the actual
security would be byte-for-byte identical. That is true today and is proven by a deterministic test
(`SigningWallTests`) that exercises the chain-lock wall while referencing zero Morpheus symbols.

---

## Two layers, one name

"Morpheus Security System" spans two layers with very different authority. Keeping them distinct is the
whole game:

| Layer | What it is | Authority |
|---|---|---|
| **Client advisor** (`Core/Morpheus/`, the MTRX app) | The on-device guardian persona + the read-only security state, the pre-transaction guardian, and the whole-app narrator. | **None over money.** Read-only and advisory. It observes the walls and narrates/warns; it returns only display data, never a decision a wall consumes. |
| **Server core** (`0pnMatrx runtime/security/morpheus.py`) | The authoritative, server-side security gate (the "preflight"), plus the on-chain/DB ban authority. | **Load-bearing on the server.** An explicit server deny aborts a send. It is fail-OPEN when absent (an undeployed gate must not block a self-custody send on testnet). |

**The firewall:** the *client advisor* must never become — or feed, or be confused with — the
*server-side decision*. The advisor reads state and speaks; the human decides; a deterministic wall (or
the server gate) enforces. They meet only at the human. An implementer must never wire the client
advisor's output into the server preflight boolean, the signing path, or any other enforcement decision.
(In code comments, the server-side gate is sometimes referred to as "Morpheus" because the server module
is named `morpheus.py`; that is the *server core*, not the client advisor. Same name, different layer,
different authority — never collapse them.)

---

## The deterministic walls Morpheus observes (and never controls)

| Wall | Where it enforces |
|---|---|
| Testnet-only signing lock | `ERC4337Manager.signOperation` — fails closed before any signature if the chain isn't the one permitted chain (Base Sepolia) |
| Biometric Secure-Enclave gate | `SecureEnclaveManager.sign(...)` — a declined Face ID produces no signature |
| Gated-key value enforcement | `SecureEnclaveManager.signForValue` / `isGated` — refuses a non-biometric-gated owner key (armed at go-live; the arming flag is `private(set)` so no code can disarm it) |
| Fail-closed send path | `SendView.sendNative` — biometric → server preflight → broadcast → success only on a valid `0x` hash |

None of these reference Morpheus. He reads them through a read-only façade; he cannot touch them.

---

## What the client advisor is made of

1. **The read-only security-state façade** (`MorpheusSecurityState`) — a stateless namespace of pure reads
   returning immutable value snapshots (on testnet?, is the signing key biometric-gated?, recovery
   readiness, is this recipient in contacts?, does this amount cross the user's own thresholds?). No
   setter, no toggle, no veto; mutable globals are copied by value so no live reference escapes. It never
   calls or feeds the server preflight.
2. **The pre-transaction guardian** (`MorpheusGuardian`) — maps those facts into advisory *observations*
   shown on the send review screen before the hard gate. It returns only a list of observations — no
   boolean, no allow/deny. The user reads them, then proceeds; the existing gates run unchanged. Every
   observation is grounded in real state; nothing is a guess (no "you've never sent here" without send
   history, no "unsafe contract" — only "no verification record").
3. **The whole-app security narrator** (`MorpheusNarrator` + the "What's protecting you" section in
   Account → Security) — plain-language statements about what is protecting the user, each grounded in a
   real read. No blanket "you're secure"; an identity-only restore is narrated as "recovery needed,"
   never "ungated"; a non-testnet configuration is narrated as "signing locked — sends refused," never as
   "funds move."

Both surfaces are advisory/display-only. Each was built on the verified façade and adversarially checked
to confirm its output cannot gate an action and the walls hold if Morpheus is wrong or injected.

---

## Persona

The user-facing agent is **Morpheus** — the guardian: calm, deliberate, protective. His domain is
protection, not execution (execution is Trinity's). He does not move funds and does not pretend a wall's
decision is his.

---

## Status

The client advisor (state layer + both surfaces) is built and on `main`, on testnet, OBSERVE, advisory.
The server core and the go-live arming of the deterministic flags are owned elsewhere and are not flipped
by this work. The walls don't move.
