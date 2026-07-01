# MTRX ↔ 0pnMatrx endpoint map (P2-10)

The client (`Core/Networking/MTRXAPIClient.swift`) was originally written against a
REST backend that was never built (the header even said "FastAPI"). The real
backend is the **0pnMatrx aiohttp gateway**: REST routes under `/api/v1/*`
(`gateway/service_routes.py`) + the mobile bridge under `/bridge/v1/*`
(`gateway/bridge.py`) + core routes in `gateway/server.py`.

`FeatureFlags.mvpMode = true` hides the regulated screens, so the **live blast
radius** is the non-gated surface. This pass (P2-10) aligned the visible,
low-risk surfaces and adds the server routes the visible Social/Bridge screens
needed; the large 1:1 REMAP/BRIDGE-ACTION rewrite of the ~135 regulated-surface
paths is **scoped to M2** (see "Deferred", below) per the audit's own
GATED-DEFER decision — those screens are hidden today and a blind rewrite would
churn call sites without a way to verify each shape.

## Done in this pass

| Screen / service | Client method | Old path | Action | New target |
|---|---|---|---|---|
| Onboarding | `authenticateWithApple` | `/api/v1/auth/apple` | MATCHES (server added, P1-8) | `POST /api/v1/auth/apple` |
| Account (delete) | `deleteAccount` | `/api/v1/auth/account` | MATCHES (server added, P1-8) | `DELETE /api/v1/auth/account` |
| Send | `securityPreflightAllowsSend` | `/api/v1/security/preflight` | MATCHES (server added, P1-5) | `POST /api/v1/security/preflight` |
| Push | `bridgeRegisterPush` | `/bridge/v1/push/register` | MATCHES (server added, P1-6) | `POST /bridge/v1/push/register` |
| App Attest | `fetchAttestChallenge` / `verifyAttestation` | `/security/appattest/*` | MATCHES (server added, P1-4) | `GET/POST /security/appattest/*` |
| Social graph | `SocialGraphService` follow/unfollow/followers/following | `/social/*` | SERVER-ADD (P2-10) | `POST /social/follow` · `POST /social/unfollow` · `GET /social/{a}/followers` · `GET /social/{a}/following` |
| Cross-chain bridge | `BridgeGatewayService.getBridgeRoutes/executeBridge` | `/bridge/routes` · `/bridge/execute` (colliding namespace) | REMAP | `POST /api/v1/defi/bridge/quote` · `POST /api/v1/defi/bridge/execute` |
| Cross-chain bridge | `BridgeGatewayService.getBridgeStatus` | `/bridge/status/{tx}` | REMAP (no bridge-status route; poll generic tx lookup, no fake status) | `GET /api/v1/portfolio/history/{tx}` |
| (whole client) | header comment | "MTRX Runtime FastAPI backend" | fixed | "0pnMatrx gateway (aiohttp)" |

Social `suggestions` returns an empty list for now (no ranking) — the client
tolerates an empty array.

## Deferred to M2 (GATED-DEFER — regulated screens hidden by `mvpMode`)

The bulk of `MTRXAPIClient`'s `/api/v1/*` methods target the 30-component /
221-capability REST surface used by regulated DeFi/securities/RWA/payments
screens that are **hidden while `mvpMode = true`**. Many of these operations do
exist server-side as **ServiceDispatcher actions** reachable via
`POST /bridge/v1/action {"action", "params"}`, so the M2 path is: for each
hidden screen, either REMAP to an existing `/api/v1/*` route or BRIDGE-ACTION
through `/bridge/v1/action` using the dispatcher action names in
`runtime/blockchain/services/service_dispatcher.py`. That rewrite is out of
scope for this audit pass (R8) because the screens are not user-reachable today
and each response shape must be verified against a real handler — tracked here as
the M2 work item.
