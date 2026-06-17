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

    // MARK: - Network (JSON-RPC + realtime)

    enum Network {

        /// HTTPS JSON-RPC endpoint for the chain.
        /// Format: `https://...` (e.g. an Alchemy/Infura/QuickNode Base URL).
        /// Where: your RPC provider dashboard (Base mainnet or Base Sepolia).
        static let rpcURL = ""

        /// WebSocket JSON-RPC endpoint for live subscriptions
        /// (`eth_subscribe` newHeads / logs). Optional — when empty, the
        /// network layer falls back to HTTP polling.
        /// Format: `wss://...`
        /// Where: same RPC provider, "WebSocket" endpoint.
        static let webSocketURL = ""

        /// EVM chain id.
        /// Format: integer. Base mainnet = 8453, Base Sepolia = 84532.
        /// Where: chainlist.org / your provider. Leave 0 until decided.
        static let chainID = 0
    }

    // MARK: - Account Abstraction (ERC-4337)

    enum AccountAbstraction {

        /// ERC-4337 bundler RPC URL (accepts `eth_sendUserOperation`,
        /// `eth_estimateUserOperationGas`, etc.).
        /// Format: `https://...`
        /// Where: your bundler provider (Pimlico/Alchemy/Stackup/Biconomy).
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

        /// CloudKit container identifier used for the encrypted wallet
        /// backup (recovery blob is encrypted on-device; only ciphertext
        /// is stored in the user's private CloudKit DB).
        /// Format: `iCloud.com.opnmatrx.mtrx` (must match an entitlement).
        /// Where: Apple Developer → Identifiers → iCloud Containers, and add
        /// it to the app's iCloud entitlement.
        static let iCloudContainerID = ""
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
        /// 21 — DEX router (REGULATED: display + self-custody only).
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
