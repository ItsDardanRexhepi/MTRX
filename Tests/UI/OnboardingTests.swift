import XCTest

/// XCUITest: First launch — wallet creation, Trinity welcome, permissions, first attestation
final class OnboardingTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--reset-onboarding"]
        app.launch()
    }

    func testFirstLaunch_TrinityWelcomeAppears() {
        let welcome = app.staticTexts["trinityWelcome"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 5), "Trinity welcome message should appear on first launch")
    }

    func testFirstLaunch_WalletCreation_OneTap() {
        // Trinity should prompt wallet creation
        let createButton = app.buttons["createWallet"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 10), "Create wallet button should appear")

        createButton.tap()

        // Wallet should be created instantly — no seed phrase
        let walletCreated = app.staticTexts["walletCreatedConfirmation"]
        XCTAssertTrue(walletCreated.waitForExistence(timeout: 10), "Wallet should be created in one tap")

        // Verify no seed phrase is shown
        XCTAssertFalse(app.staticTexts["seedPhrase"].exists, "Seed phrase must NEVER be displayed — ERC-4337 smart account")
    }

    func testFirstLaunch_PermissionRequests() {
        // Create wallet first
        app.buttons["createWallet"].tap()
        _ = app.staticTexts["walletCreatedConfirmation"].waitForExistence(timeout: 10)

        // Continue to permission requests
        app.buttons["continueSetup"].tap()

        // Notification permission
        let notifPermission = app.staticTexts["notificationPermission"]
        XCTAssertTrue(notifPermission.waitForExistence(timeout: 5))
    }

    func testFirstLaunch_FirstAttestation_Created() {
        // Complete onboarding
        app.buttons["createWallet"].tap()
        _ = app.staticTexts["walletCreatedConfirmation"].waitForExistence(timeout: 10)
        app.buttons["continueSetup"].tap()

        // Skip permissions for test
        if app.buttons["skipPermissions"].exists { app.buttons["skipPermissions"].tap() }

        // Verify first attestation (account creation) is recorded
        let attestation = app.staticTexts["firstAttestation"]
        XCTAssertTrue(attestation.waitForExistence(timeout: 15), "First EAS attestation should be created for account setup")
    }

    func testOnboarding_CompleteFlow_ReachesHome() {
        // Full onboarding path
        app.buttons["createWallet"].tap()
        _ = app.staticTexts["walletCreatedConfirmation"].waitForExistence(timeout: 10)
        app.buttons["continueSetup"].tap()

        // Handle permission prompts
        if app.buttons["allowNotifications"].waitForExistence(timeout: 3) { app.buttons["allowNotifications"].tap() }
        if app.buttons["continueToHome"].waitForExistence(timeout: 3) { app.buttons["continueToHome"].tap() }

        // Should reach home screen with Trinity
        let homeView = app.otherElements["homeView"]
        XCTAssertTrue(homeView.waitForExistence(timeout: 10), "Should reach home screen after onboarding")
    }
}
