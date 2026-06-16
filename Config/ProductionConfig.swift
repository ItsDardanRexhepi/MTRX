// ProductionConfig.swift
// MTRX
//
// Production configuration constants.
// Set `productionGatewayURL` below once DNS is pointed at the Railway
// (or other) backend. Until it is non-nil, Trinity falls back to local
// DemoDataProvider responses — the app still renders every screen.

import Foundation

enum ProductionConfig {

    // MARK: - Backend

    /// The production gateway URL for the 0pnMatrx runtime.
    /// Point DNS for `openmatrix-ai.com` at the deployed Railway (or
    /// other) host, confirm SSL is live, then set this to the full
    /// HTTPS origin. Trinity will switch from DemoDataProvider to the
    /// real backend automatically on next app launch.
    static let productionGatewayURL: String? = "https://api.openmatrix-ai.com"

    /// Default port for self-hosted installs. The hosted gateway at
    /// `openmatrix-ai.com` uses standard HTTPS (443) via reverse proxy.
    static let gatewayPort: Int = 18790

    // MARK: - Blockchain

    /// NeoSafe multisig address — platform treasury.
    static let neoSafeAddress = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

    /// Supported chains at launch.
    static let primaryChain = "base"
    static let supportedChains = ["base", "ethereum"]

    // MARK: - App Identity

    /// Bundle ID — must match App Store Connect exactly.
    /// Note: uses historical `opnmatrx` spelling (registered before the
    /// public domain was chosen); App Store Connect treats the bundle
    /// ID as an opaque identifier, so this stays stable.
    static let bundleID = "com.opnmatrx.mtrx"

    /// StoreKit product IDs — must start with bundleID.
    static let proProductID = "com.opnmatrx.mtrx.pro.monthly"
    static let enterpriseProductID = "com.opnmatrx.mtrx.enterprise.monthly"

    // MARK: - Launch

    /// May 21, 2026.
    static let launchDate = "2026-05-21"
}
