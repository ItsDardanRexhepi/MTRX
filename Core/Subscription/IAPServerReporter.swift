// Core/Subscription/IAPServerReporter.swift
// MTRX — Phase 3 monetization server (client half)
//
// Ships the StoreKit-signed transaction JWS to the backend's
// POST /api/v1/iap/verify so the server holds an independently-verified
// record (subscriptions AND the solitaire do-over Consumable).
//
// Fire-and-forget by design: local StoreKit 2 verification remains the UX
// source of truth. A server ack never grants anything locally, and a server
// failure never blocks, retries into, or degrades the purchase the user
// already owns — it is logged honestly and that is all.

import Foundation

enum IAPServerReporter {

    private struct VerifyBody: Encodable {
        let signedTransaction: String
    }

    /// Report a verified transaction's JWS to the backend, if configured.
    /// Safe to call from any purchase/updates path; returns immediately.
    static func report(jws: String, context: String) {
        guard PendingCredentials.isBackendConfigured else { return }
        guard !jws.isEmpty else {
            print("IAPServerReporter[\(context)]: no jwsRepresentation to send")
            return
        }
        Task.detached(priority: .utility) {
            do {
                let response = try await MTRXAPIClient.shared.postRaw(
                    path: "/api/v1/iap/verify",
                    body: VerifyBody(signedTransaction: jws)
                )
                let replay = response["replay"]?.boolValue ?? false
                print("IAPServerReporter[\(context)]: recorded on server"
                      + (replay ? " (replay — already recorded)" : ""))
            } catch {
                // Honest log only — the purchase is already locally verified
                // and granted; the server record catches up via ASN/retry.
                print("IAPServerReporter[\(context)]: server verify failed — "
                      + "\(error.localizedDescription). Local entitlement unaffected.")
            }
        }
    }
}
