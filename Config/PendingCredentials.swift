// PendingCredentials.swift
// MTRX — Config
//
// ┌──────────────────────────────────────────────────────────────────────┐
// │  THE SINGLE PLACE TO FILL IN EXTERNAL VALUES.                          │
// │                                                                        │
// │  Every external endpoint, address, and identifier the app needs lives  │
// │  here as one clearly-labelled constant. Nothing is hardcoded anywhere  │
// │  else; no value is invented or pasted inline elsewhere in the code.    │
// │                                                                        │
// │  Each constant is EMPTY by default. While empty, the feature that      │
// │  uses it degrades to a safe no-op / demo path (it never crashes and    │
// │  never fakes a result). Fill a value in and that feature goes live on  │
// │  the next launch — no other code change required.                      │
// │                                                                        │
// │  NEVER put a private key in this file (or anywhere in the app). The    │
// │  paymaster/deployer signing key lives ONLY on a server; the app asks   │
// │  that server for signatures (see AccountAbstraction.paymasterSignature │
// │  Endpoint). If you are ever tempted to paste a 64-hex private key      │
// │  here, stop — that is the one thing this design forbids.               │
// └──────────────────────────────────────────────────────────────────────┘

import Foundation

enum PendingCredentials {

    // MARK: - Helpers

    /// `nil` when a value hasn't been filled in yet, so callers can branch
    /// to their safe no-op/demo path instead of using an empty string.
    @inline(__always)
    static func filled(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True once the on-chain core (RPC + chain id + EntryPoint + factory)
    /// is configured. The wallet shows real balances and can deploy only
    /// when this is true.
    static var isChainConfigured: Bool {
        filled(Network.rpcURL) != nil
            && Network.chainID != 0
            && filled(AccountAbstraction.entryPointAddress) != nil
            && filled(AccountAbstraction.accountFactoryAddress) != nil
    }

    /// True once gas sponsorship can be requested (bundler + paymaster +
    /// the server signature endpoint are all set).
    static var isGasSponsorshipConfigured: Bool {
        filled(AccountAbstraction.bundlerURL) != nil
            && filled(AccountAbstraction.paymasterAddress) != nil
            && filled(AccountAbstraction.paymasterSignatureEndpoint) != nil
    }

    /// True once the off-chain backend gateway is configured. Feature screens
    /// show honest, clearly-labelled DEMO data until this is true; the moment it
    /// is filled they flip to live service data automatically — no code change.
    static var isBackendConfigured: Bool {
        filled(effectiveGatewayURL) != nil
    }

    // MARK: - Runtime gateway override (developer / owner on-device testing)
    //
    // Lets the owner point Trinity's cloud brain at a locally-run 0pnMatrx
    // gateway from the device (Settings → Trinity AI, DEBUG builds) without a
    // rebuild — so REAL Anthropic reasoning can be exercised on a physical phone
    // before the gateway is deployed. The Anthropic key NEVER ships in the app;
    // it stays server-side in the gateway. Empty by default → honest until set.
    private static let runtimeGatewayKey = "mtrx.debug.gatewayURL"
    private static let forceCloudKey = "mtrx.debug.forceCloudReasoning"

    /// A gateway base URL set at runtime on the device (overrides Backend.gatewayURL).
    static var runtimeGatewayURL: String {
        get { UserDefaults.standard.string(forKey: runtimeGatewayKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: runtimeGatewayKey) }
    }

    /// The gateway URL actually used: the runtime override when set, else the
    /// compiled `Backend.gatewayURL`.
    static var effectiveGatewayURL: String {
        filled(runtimeGatewayURL) ?? Backend.gatewayURL
    }

    /// When true, Trinity routes free-form reasoning through the cloud gateway
    /// (Anthropic) even when the on-device model is available — lets the owner
    /// verify the cloud path on an Apple-Intelligence device. Off by default.
    static var forceCloudReasoning: Bool {
        get { UserDefaults.standard.bool(forKey: forceCloudKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceCloudKey) }
    }

    /// True once Apple Pay can take a REAL charge: a registered merchant id and
    /// a server-side processor endpoint that decrypts the payment token and
    /// charges the card. While false, the Apple Pay button stays hidden — the
    /// app never reports a successful charge it didn't make.
    static var isApplePayConfigured: Bool {
        filled(Payments.applePayMerchantID) != nil
            && filled(Payments.applePayProcessorChargeURL) != nil
    }

    // MARK: - Payments (Apple Pay)

    enum Payments {

        /// Apple Pay merchant identifier, registered in the Apple Developer
        /// portal and enabled on the app's Apple Pay capability.
        /// Format: `merchant.com.yourcompany.app`.
        static let applePayMerchantID = ""

        /// HTTPS endpoint on YOUR server that receives the encrypted Apple Pay
        /// payment token, submits it to your payment processor (Stripe /
        /// Braintree / Adyen / …) to charge the card, and returns HTTP 200 only
        /// on a confirmed charge. The app POSTs the token here and reports
        /// success ONLY when this endpoint confirms — never optimistically.
        static let applePayProcessorChargeURL = ""

        /// ISO country + currency for the Apple Pay sheet.
        static let countryCode = "US"
        static let currencyCode = "USD"
    }

    // MARK: - Network (JSON-RPC + realtime)

    enum Network {

        /// HTTPS JSON-RPC endpoint for the chain. TESTNET-ONLY phase: this must be a
        /// Base **Sepolia** endpoint (e.g. an Alchemy/Infura/QuickNode Base Sepolia
        /// URL). Format: `https://...`. Empty = unconfigured (no real network; sends
        /// honest-fail — nothing is faked). Do NOT point this at Base mainnet.
        static let rpcURL = ""

        /// WebSocket JSON-RPC endpoint for live subscriptions
        /// (`eth_subscribe` newHeads / logs). Optional — when empty, the
        /// network layer falls back to HTTP polling.
        /// Format: `wss://...`
        /// Where: same RPC provider, "WebSocket" endpoint.
        static let webSocketURL = ""

        /// EVM chain id. TESTNET-ONLY phase: Base **Sepolia** (84532). Base mainnet
        /// (8453) is intentionally NOT used — BlockchainBridge reads this value and
        /// fails CLOSED (signs nothing) against any non-testnet chain. Change this
        /// away from 84532 only after the human-review + go-live gate.
        static let chainID = 84_532
    }

    // MARK: - Account Abstraction (ERC-4337)

    enum AccountAbstraction {

        /// ERC-4337 bundler RPC URL (accepts `eth_sendUserOperation`,
        /// `eth_estimateUserOperationGas`, etc.). TESTNET-ONLY phase: a Base **Sepolia**
        /// bundler endpoint (Pimlico/Alchemy/Stackup/Biconomy, Base Sepolia network).
        /// Format: `https://...`. Empty = unconfigured (sends honest-fail).
        static let bundlerURL = ""

        /// The canonical EntryPoint contract address for the bundler's
        /// supported version.
        /// Format: 0x + 40 hex (checksummed).
        /// Where: ERC-4337 spec / your bundler's docs (e.g. v0.6
        /// 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789 — confirm with bundler).
        static let entryPointAddress = ""

        /// The smart-account factory that CREATE2-deploys user wallets and
        /// is also used to compute the counterfactual address before deploy.
        /// Format: 0x + 40 hex.
        /// Where: the address you deployed your account factory to.
        static let accountFactoryAddress = ""

        /// The verifying-paymaster contract address that sponsors gas.
        /// Format: 0x + 40 hex.
        /// Where: the address you deployed your paymaster to.
        static let paymasterAddress = ""

        /// HTTPS endpoint of YOUR paymaster signing service. The app POSTs a
        /// UserOperation + validity window and the server returns the
        /// paymaster signature. THE SIGNING KEY LIVES ONLY ON THIS SERVER —
        /// never in the app.
        /// Format: `https://.../paymaster/sign`
        /// Where: your backend (the service that holds the paymaster signer).
        static let paymasterSignatureEndpoint = ""
    }

    // MARK: - Recovery

    enum Recovery {

        /// Social-recovery module / guardian-registry contract address.
        /// Format: 0x + 40 hex.
        /// Where: the address you deployed your recovery module to.
        static let socialRecoveryModuleAddress = ""
    }

    // MARK: - Attestation (EAS)

    enum Attestation {

        /// EAS schema UID the client attests against (M6/D4 post-deploy
        /// wiring unit). Format: 0x + 64 hex — a chain-specific keccak256
        /// SchemaRegistry hash, NOT an easscan display number like "348".
        /// Where: register with 0pnMatrx scripts/register_eas_schemas.py and
        /// paste the SAME UID the server carries in blockchain.schemas.primary
        /// — client and server must attest against the same schema. Empty
        /// fails closed (no attestation against a placeholder).
        static let schemaUID = ""
    }

    // MARK: - Pricing

    enum Pricing {

        /// Source for the ETH/USD spot price used to convert gas estimates
        /// to fiat. Either an on-chain Chainlink ETH/USD aggregator address
        /// (0x + 40 hex, read via `latestRoundData`) OR an HTTPS price API
        /// returning `{ "usd": <number> }`. The pricing layer auto-detects
        /// which by the `0x` prefix.
        /// Where: Chainlink data feeds (Base) for the on-chain option, or a
        /// price API (CoinGecko/your gateway) for the HTTP option.
        static let ethUsdSource = ""
    }

    // MARK: - Backend gateway (off-chain feature APIs)

    enum Backend {

        /// HTTPS base URL of the 0pnMatrx runtime gateway that backs the feature
        /// services (events, social, storage, lending data, etc.). When empty,
        /// every feature view runs on its bundled DEMO data (clearly labelled);
        /// when filled, the views flip to live service data automatically.
        /// Format: `https://...` (e.g. https://api.openmatrix-ai.com). Also
        /// overridable at runtime via the MTRX_RUNTIME_URL environment variable.
        static let gatewayURL = ""
    }

    // MARK: - Security (App Attest + biometric owner factor)
    //
    // Client half of two server-side layers in Morpheus-Security-System:
    //   • App Attest (server Package D / AppAttestVerifier) — proves a request comes
    //     from a genuine, unmodified MTRX build on a real Apple device.
    //   • Biometric Secure-Enclave owner factor (server Package E / owner.py) — the
    //     owner third factor is a Face/Touch-ID-gated App Attest assertion.
    //
    // BOTH FLAGS DEFAULT OFF. With both off the whole client layer is INERT: no
    // challenge fetch, no biometric prompt, no assertion attached — privileged
    // requests go out byte-for-byte unchanged. The feature does nothing live until
    // the security server is deployed AND the flags are deliberately flipped, in
    // lockstep with the server, per SECURITY_REVIEW_CHECKLIST §14.4. Never enable
    // `appAttestEnforced` before the server's OPNMATRX_APPATTEST_ENFORCE is on.

    enum Security {

        /// Master switch: whether the client ATTEMPTS App Attest at all (fetch a
        /// challenge, biometric-gate, attach the assertion to fund-moving requests).
        /// DEFAULT OFF → the layer is inert and requests are unchanged. Flip ON only
        /// once the security server is deployed; this alone is observe-compatible —
        /// the server records `would_block` but does not deny while its own
        /// OPNMATRX_APPATTEST_ENFORCE is off.
        static let appAttestEnabled = false

        /// Mirror of the SERVER flag OPNMATRX_APPATTEST_ENFORCE. DEFAULT OFF.
        /// OFF (observe): a privileged request that can't produce a valid assertion is
        /// NOT blocked locally — it is sent without one (the server observes).
        /// ON (enforce): such a request HARD-FAILS on the client — the app never sends
        /// an unattested request dressed up as attested. Flip ON only in lockstep with
        /// the server flag. Has no effect unless `appAttestEnabled` is also on.
        static let appAttestEnforced = false
    }

    /// True once the client App Attest layer is active (master switch on).
    static var isAppAttestEnabled: Bool { Security.appAttestEnabled }

    /// True once the client enforces App Attest locally (both switches on).
    static var isAppAttestEnforced: Bool { Security.appAttestEnabled && Security.appAttestEnforced }

    // MARK: - Legal

    enum Legal {

        /// HTTPS URL to the hosted Terms of Service. When set, the in-app legal
        /// screen loads it in a web view; when empty, the app falls back to the
        /// bundled Terms.md (and finally to inline text), so the screen is never
        /// blank. Format: `https://...`
        static let termsURL = ""

        /// HTTPS URL to the hosted Privacy Policy (same fallback behaviour).
        /// Format: `https://...`
        static let privacyURL = ""

        /// HTTPS URL to the hosted Open-Source Licenses page (same fallback).
        /// Format: `https://...`
        static let licensesURL = ""
    }

    // MARK: - Deployed component contracts
    //
    // One address per on-chain component. Empty → that component runs in
    // display-only / demo mode (no real call is attempted). Regulated
    // components (DeFiLending, Staking, Insurance, Securities, DEX,
    // Fundraising) are *intentionally* display + user-signed self-custody
    // only even once filled — see the final report.

    enum Components {

        /// 01 — Contract conversion / escrow factory. Format: 0x+40 hex.
        static let contractConversion = ""
        /// 02 — DeFi lending pool (REGULATED: display + self-custody only).
        static let deFiLending = ""
        /// 03 — NFT collection / minter. Format: 0x+40 hex.
        static let nft = ""
        /// 04 — Real-world-asset registry (REGULATED). Format: 0x+40 hex.
        static let rwa = ""
        /// 05 — Identity / DID registry. Format: 0x+40 hex.
        static let identity = ""
        /// 06 — DAO / governor. Format: 0x+40 hex.
        static let dao = ""
        /// 07 — Stablecoin token (ERC-20). Format: 0x+40 hex.
        static let stablecoin = ""
        /// 08 — Attestation registry. Format: 0x+40 hex.
        static let attestation = ""
        /// 09 — Agent identity registry. Format: 0x+40 hex.
        static let agentIdentity = ""
        /// 10 — Agentic payments / session keys. Format: 0x+40 hex.
        static let agenticPayments = ""
        /// 11 — Oracle aggregator. Format: 0x+40 hex.
        static let oracle = ""
        /// 12 — Supply-chain registry. Format: 0x+40 hex.
        static let supplyChain = ""
        /// 13 — Insurance pool (REGULATED: display + self-custody only).
        static let insurance = ""
        /// 14 — Gaming assets. Format: 0x+40 hex.
        static let gaming = ""
        /// 15 — IP registry. Format: 0x+40 hex.
        static let ip = ""
        /// 16 — Staking (REGULATED: display + self-custody only).
        static let staking = ""
        /// 17 — Payments router. Format: 0x+40 hex.
        static let payments = ""
        /// 18 — Securities token (REGULATED: display + self-custody only).
        static let securities = ""
        /// 19 — Governance. Format: 0x+40 hex.
        static let governance = ""
        /// 20 — Dashboard / analytics reader. Format: 0x+40 hex.
        static let dashboard = ""
        /// 21 — DEX router / swap-aggregator address (Base Sepolia, testnet). Format: 0x+40 hex.
        /// PLACEHOLDER slot for the swap path. Filling it enables nothing on its own:
        /// on-chain swap EXECUTION (S2–S4) is BLOCKED on a legal/licensing decision
        /// (App Store 3.1.5(b) + money-transmission/exchange law), not a technical gap.
        /// REGULATED — leave empty for the App Store MVP build (display + self-custody only).
        static let dex = ""
        /// 22 — Fundraising / ICO (REGULATED: display + self-custody only).
        static let fundraising = ""
        /// 23 — Loyalty points. Format: 0x+40 hex.
        static let loyalty = ""
        /// 24 — Marketplace. Format: 0x+40 hex.
        static let marketplace = ""
        /// 25 — Cashback. Format: 0x+40 hex.
        static let cashback = ""
        /// 26 — Brand rewards. Format: 0x+40 hex.
        static let brandRewards = ""
        /// 27 — Subscriptions. Format: 0x+40 hex.
        static let subscriptions = ""
        /// 28 — Social graph. Format: 0x+40 hex.
        static let social = ""
        /// 29 — Privacy / shielded pool. Format: 0x+40 hex.
        static let privacy = ""
        /// 30 — Dispute resolution. Format: 0x+40 hex.
        static let disputeResolution = ""
    }
}
