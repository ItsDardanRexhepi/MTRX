# App-Side Status — App Attest (D) + Biometric Secure-Enclave Owner Factor (E)

This is the **client (iOS / Swift) half** of two security layers whose server half
already lives in `Matrix-Security-System`. It was built against the real server
contract (`matrix_security/attest/app_attest.py` + `attest/CLIENT_INTEGRATION.md`),
behind flags that **default OFF**.

> **"Done" here means: the client code is written, it compiles, and it matches the
> server contract.** It does **NOT** mean the attestation/biometric round-trip has
> been verified working — that is impossible in this environment (see
> [§5 Unverifiable](#5-what-cannot-be-verified-here)). Build verified:
> `xcodebuild -scheme MTRX -configuration Debug -destination 'generic/platform=iOS
> Simulator' build` → **BUILD SUCCEEDED**.

---

## 1. What was built

All changes are in **already-compiled files** (the project uses classic
`project.pbxproj` membership, not synchronized groups, so no new Swift files were
added — zero pbxproj risk). No new build artifacts; the only new file is this doc.

| File | Change |
|---|---|
| `Apple/Security/AppAttestManager.swift` | Rewritten into the real Package D + E client (was a stub). |
| `Core/Networking/MTRXAPIClient.swift` | Added the App Attest server endpoints + the attach mechanism; routed `sendPayment` through it. |
| `Config/PendingCredentials.swift` | Added `Security` flags, **default OFF**. |
| `APP_SIDE_STATUS.md` | This document. |

### Package D — App Attest client (`AppAttestManager`)

- **Key generation** via `DCAppAttestService.generateKey()`; the resulting `keyId` is
  stored in the **Keychain** (not UserDefaults), **device-only and not iCloud-synced**
  (the key is bound to this device's Secure Enclave — a synced copy would be useless).
- **One-time attestation** (`registerIfNeeded(identity:)`): fetch a server challenge →
  `attestKey` over `SHA256(utf8(challenge))` (the exact transform the server
  reconstructs) → POST the attestation object to the server → **persist the keyId only
  after the server accepts**.
- **Per-request assertion** (`makeAssertion` / `fundMovingAssertion` /
  `ownerDeviceAssertion`): fetch a fresh challenge → biometric gate (see E) →
  `clientDataHash = SHA256(utf8(challenge) + canonicalRequestBytes)` →
  `generateAssertion` → return the envelope in the **exact server shape**
  `{ key_id, assertion_b64, client_data_hash, challenge }` (snake_case — the keys the
  gate reads from `context["app_attest"]`).
- **Honest failure modes** — typed `AppAttestError`, never a crash, never a fake
  success:
  - device unsupported (older hardware / Simulator) → `.notSupported`, `Readiness.unsupported`;
  - no key yet → `.keyNotRegistered`;
  - **key lost** (restore / reinstall — Apple rejects the keyId) → caught at
    `generateAssertion`, the local keyId is cleared and `.keyLost` is thrown so the
    caller can re-register;
  - network failure fetching a challenge → `.challengeUnavailable`.
  An unattested request is **never** sent dressed up as attested.
- **Flag-gated**: the manager is only ever reached when the client flag is on
  (see §3).

### Package E — biometric Secure-Enclave owner factor

- **Local biometric gate first.** For owner-gated / high-value actions the user must
  pass `LocalAuthentication` Face/Touch ID (passcode fallback) **before** the device
  assertion is produced — a stolen, already-unlocked phone still can't silently
  authorize. Implemented in `makeAssertion(requireBiometrics: true)` via the existing
  `BiometricAuth` wrapper.
- **Secure Enclave / private key never leaves the device.** The owner device factor is
  a Face/Touch-ID-gated **App Attest assertion** — and App Attest keys are themselves
  Secure-Enclave-backed by Apple. (See the contract note in §4: the server's owner
  third factor, `owner.py._verify_device_assertion`, verifies an **App Attest
  assertion**, so that is what the client produces. The separate
  `kSecAttrTokenIDSecureEnclave` P-256 key in `SecureEnclaveManager` remains the
  wallet-signing key.)
- **Keychain ACL.** Sensitive values use `KeychainManager`'s biometric ACL
  (`SecAccessControlCreateWithFlags(..., .biometryCurrentSet, ...)`). The keyId itself
  is not secret, so it is stored without that ACL to avoid a double Face ID prompt on
  every send.
- **SMS-OTP fallback intact, never silent.** The existing OTP path
  (`MTRXAPIClient.requestPhoneOTP` / `verifyPhoneOTP`, server purpose `owner_verify`)
  is **unchanged**. `ownerDeviceAssertion` **throws** on biometric failure / unsupported
  hardware / lost key — it does **not** auto-downgrade. The caller surfaces the failure
  and the user must **explicitly** choose the OTP fallback, matching the server's
  "biometric preferred, OTP fallback" logic.

### Networking (`MTRXAPIClient`)

- `fetchAttestChallenge(identity:)` → `GET /security/appattest/challenge`.
- `verifyAttestation(keyId:attestationObjectB64:challenge:)` → `POST /security/appattest/attest`.
- `postFundMovingAttested(path:body:)` — attaches the assertion to a fund-moving body
  via `AttestedBody` (adds `app_attest` at the same JSON level the gate reads),
  governed by the flags (§3). `sendPayment` now routes through it; **inert** until the
  flag is on.

---

## 2. Apple-side prerequisites (manual, in the Apple Developer account)

None of these are done by this change — they require portal access and a real App ID.

1. **App Attest capability** on the App ID `com.opnmatrx.mtrx`
   (Team `Z8T732UGMV`): Apple Developer → Identifiers → App IDs → enable
   **App Attest** (under DeviceCheck).
2. **Entitlement** in `Config/Entitlements.entitlements` — add:
   ```xml
   <key>com.apple.developer.devicecheck.appattest-environment</key>
   <string>production</string>   <!-- or "development" for a dev build -->
   ```
   > Deliberately **NOT added in this change**: adding it before the App ID carries the
   > capability can fail code-signing/provisioning and break the build. Add it together
   > with step 1, on a provisioning profile that includes the capability.
3. **Provisioning profile** regenerated to include the App Attest entitlement
   (automatic signing will do this once step 1 is set).
4. **Server config** (operator, on the deployed gateway):
   - `config['attest']['app_id'] = "Z8T732UGMV.com.opnmatrx.mtrx"`
     (or `OPNMATRX_APPATTEST_APP_ID`) — for the RP-ID hash check;
   - Apple's App Attest **root certificate** PEM via
     `config['attest']['apple_root_pem']` / `OPNMATRX_APPATTEST_ROOT`;
   - the gateway HTTP routes for `new_challenge` / `verify_attestation` exposed at the
     paths this client uses (see §4).

---

## 3. The flags (default OFF — nothing is live)

`PendingCredentials.Security`:

| Flag | Default | Meaning |
|---|---|---|
| `appAttestEnabled` | **false** | Master switch. OFF → the whole layer is **inert**: no challenge fetch, no biometric prompt, no assertion attached; fund-moving requests are byte-for-byte unchanged. |
| `appAttestEnforced` | **false** | Mirror of server `OPNMATRX_APPATTEST_ENFORCE`. OFF (observe) → a request that can't produce an assertion is sent **without** one. ON (enforce) → it **hard-fails** on the client. No effect unless `appAttestEnabled` is also on. |

With both OFF (the shipping default) this feature **does nothing live**.

---

## 4. Contract reconciliation (read this before enabling)

- **Doc vs. server code agree** on the crypto flow (challenge transform, assertion
  hash, envelope keys, replay counter). No disagreement was found.
- **Owner factor = App Attest assertion.** `owner.py._verify_device_assertion` calls
  `AppAttestVerifier.verify_assertion`, so the owner "device assertion" is an App
  Attest assertion (Secure-Enclave-backed), **not** a raw `SecureEnclaveManager` P-256
  signature. The client builds it that way. The P-256 SE key remains the wallet signer.
- **HTTP route paths are an assumption to confirm.** The server module defines the
  verifier *methods*; the *gateway HTTP routes* are the server team's. This client uses
  `/security/appattest/challenge` and `/security/appattest/attest` (following the
  existing `/security/phone/*` OTP convention). **Confirm these against the deployed
  gateway** — if they differ, update the two paths in the `MTRXAPIClient` App Attest
  extension. The per-request assertion is attached in the body as `app_attest` (the
  shape the gate consumes); that needs no extra route.
- **Keychain access group.** `KeychainManager` uses access group
  `group.com.mtrx.shared`; the keyId is stored device-only/non-synced. If that access
  group isn't in the app's entitlements at runtime, keychain writes fail — a runtime
  prerequisite, not a compile one.

---

## 5. What cannot be verified here

App Attest and Secure-Enclave biometrics **cannot run in the Simulator or CI**.
Runtime verification of the full round-trip requires **all three**:

- **(a) a physical iPhone** (App Attest + Face/Touch ID hardware);
- **(b) the App Attest entitlement** enabled on the real App ID (§2);
- **(c) the deployed security server** with the App ID + Apple root cert configured (§2).

Until all three exist, this is **compiled, contract-matching client code** — not a
verified working attestation. That is the honest status.

---

## 6. Exact steps to turn it on later (lockstep with the server)

Per `Matrix-Security-System/SECURITY_REVIEW_CHECKLIST.md` §14.4:

1. Apple side: enable App Attest on the App ID, add the entitlement, regenerate the
   profile (§2 steps 1–3).
2. Server side: deploy the security server; set `app_id` + the Apple root cert; expose
   the App Attest routes; keep `OPNMATRX_APPATTEST_ENFORCE` **OFF**.
3. Client: flip `PendingCredentials.Security.appAttestEnabled = true`, ship to a
   **physical device**. This is **observe mode** — assertions are produced and sent,
   the server records `would_block` but denies nothing.
4. On-device, confirm the round-trip: a registered key, a fund-moving request carrying
   a valid `app_attest` envelope, the server verifying it. Inspect the server's
   `would_block` metrics for false negatives across real devices (old OS, restored,
   reinstalled).
5. Only after a clean observe burn-in, and only **in lockstep**, flip BOTH
   `OPNMATRX_APPATTEST_ENFORCE` (server) and
   `PendingCredentials.Security.appAttestEnforced = true` (client) — signed off per
   §14.4. From then on, a privileged request without a valid assertion is denied
   server-side and hard-failed client-side.

Owner factor (E): once the above is live, owner-gated actions prefer the biometric
device assertion; the SMS-OTP path stays as the explicit, user-chosen fallback.
