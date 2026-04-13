// ProductionConfig.swift
// MTRX
//
// Production configuration constants.
// Update these before App Store submission.
//
// MANUAL TODO LIST — Things that require human action before launch:
// -----------------------------------------------------------------
// 1. App icon: Add mtrx_icon_1024.png to Assets.xcassets/AppIcon.appiconset/
// 2. Apple Developer account: developer.apple.com ($99/year)
// 3. App Store Connect: Create app record with bundle ID com.opnmatrx.mtrx
// 4. Backend domain: Register openmatrix.io, point to neo-l4 external IP
// 5. SSL certificate: Configure on neo-l4 for https://openmatrix.io
// 6. GCP firewall: Open port 18790 on neo-l4 for external traffic
// 7. Set productionGatewayURL below once domain is live
// 8. GitHub CI secrets: APPLE_TEAM_ID, APP_STORE_CONNECT_API_KEY_ID,
//    APP_STORE_CONNECT_API_ISSUER, APP_STORE_CONNECT_API_KEY
// 9. APNs certificate: Configure in App Store Connect for push notifications
// 10. Secrets.swift: Create from Secrets.example.swift with real values
// 11. Rotate Telegram bot tokens via @BotFather (exposed March 29)
// 12. Rotate NeoWrite private key (leaked in terminal)
// 13. Fund NeoWrite with 0.03 ETH for gas
// 14. App Store screenshots: 3+ per device size after UI is final
// 15. Privacy policy: Host at accessible URL before submission
// 16. TestFlight: Submit build and get 20+ beta testers before launch
//
// -----------------------------------------------------------------

import Foundation

enum ProductionConfig {

    // MARK: - Backend

    /// The production gateway URL for the 0pnMatrx runtime.
    /// Set this to "https://openmatrix.io" once the domain
    /// is configured and SSL is live on neo-l4.
    ///
    /// After setting this, rebuild and submit to TestFlight.
    /// Trinity will then use full gateway intelligence instead
    /// of falling back to local responses.
    static let productionGatewayURL: String? = nil

    /// Gateway port on neo-l4. The Matrix gateway runs on 18790.
    static let gatewayPort: Int = 18790

    // MARK: - Blockchain

    /// NeoSafe multisig address — platform treasury.
    static let neoSafeAddress = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

    /// Supported chains at launch.
    static let primaryChain = "base"
    static let supportedChains = ["base", "ethereum"]

    // MARK: - App Identity

    /// Bundle ID — must match App Store Connect exactly.
    static let bundleID = "com.opnmatrx.mtrx"

    /// StoreKit product IDs — must start with bundleID.
    static let proProductID = "com.opnmatrx.mtrx.pro.monthly"
    static let enterpriseProductID = "com.opnmatrx.mtrx.enterprise.monthly"

    // MARK: - Launch

    /// May 21, 2026 — Dardan's 33rd birthday.
    static let launchDate = "2026-05-21"
}
