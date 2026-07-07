# Apple Dashboard Identifiers — type these EXACTLY as written

Source-attributed to code; these strings must match App Store Connect and the
Developer portal character-for-character.

**Anchors:** app `com.opnmatrx.mtrx` · widget `com.opnmatrx.mtrx.widgets` ·
Team `Z8T732UGMV` · ASC app id `6762253379`

## 1. In-App Purchases (3)

| Product ID | Type | Price |
|---|---|---|
| `com.opnmatrx.mtrx.pro.monthly` | Auto-renewable subscription | $9.99/mo, 3-day free trial (`MTRX.storekit:61`) |
| `com.opnmatrx.mtrx.enterprise.monthly` | Auto-renewable subscription | $39.99/mo, 3-day free trial (`MTRX.storekit:90`) |
| `com.opnmatrx.mtrx.solitaire.redos5` | **Consumable** | $0.99 (`Core/Gaming/SolitaireRedoStore.swift:26`) |

- Subscription group name: **`MTRX Membership`** (both subscriptions in it).
  The `20653` group id in MTRX.storekit is StoreKit-local; ASC assigns the real one.
- ⚠️ The consumable is NOT in MTRX.storekit — create it manually in ASC.

## 2. Game Center

Leaderboards (7) — `Apple/Gaming/GameKitManager.swift:37-39`:
`mtrx.leaderboard.solitaire` · `mtrx.leaderboard.blocks` ·
`mtrx.leaderboard.colorburst` · `mtrx.leaderboard.merge2048` ·
`mtrx.leaderboard.breakout` · `mtrx.leaderboard.asteroids` ·
`mtrx.leaderboard.arcade`

Achievements (3) — `GameKitManager.swift:54-58`:
`mtrx.achievement.firstplay` · `mtrx.achievement.firstwin` ·
`mtrx.achievement.highroller`

## 3. App Groups (create BOTH in the portal)

| Identifier | Used for | Targets |
|---|---|---|
| `group.com.opnmatrx.mtrx` | app↔widget shared store + SwiftData container | app + widget |
| `group.com.mtrx.shared` | shared Keychain access group | app only |

## 4. Capabilities on the App ID

| Capability | State | Note |
|---|---|---|
| App Attest | ✅ enable | entitlement `appattest-environment` = `production` |
| Push Notifications | ✅ enable | ⚠️ entitlement is `aps-environment` = `development` — flip to `production` before App Store submission |
| Sign in with Apple | ✅ enable | `com.apple.developer.applesignin` |
| **MusicKit** | ✅ enable on the App ID | no entitlement key by design — App-Service checkbox in the portal |
| Game Center, iCloud (KVS), WeatherKit, App Groups | ✅ enable | all declared + used |

Not used (leave off): CloudKit containers, HealthKit, Associated Domains, App Clips.

## 5. App Store Server Notifications (ASN V2)

Webhook URL: `https://<your-gateway-host>/api/v1/iap/asn`
(with the hosted gateway: `https://gateway.openmatrix-ai.com/api/v1/iap/asn`).
Route registered at `0pnMatrx/gateway/server.py:2056`; requires server config
`iap.bundle_id` = `com.opnmatrx.mtrx` or IAP verify/ASN fail closed with 503.
Client verify endpoint (not typed into ASC): `/api/v1/iap/verify`.
