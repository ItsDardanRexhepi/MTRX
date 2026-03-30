import XCTest

/// XCUITest: Complete transaction paths — send ETH, swap tokens, stake, create contract
final class TransactionFlowTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testSendETH_FullFlow() {
        // Navigate to wallet
        app.tabBars.buttons["Account"].tap()
        app.buttons["sendButton"].tap()

        // Fill in recipient
        let recipientField = app.textFields["recipientAddress"]
        XCTAssertTrue(recipientField.waitForExistence(timeout: 5))
        recipientField.tap()
        recipientField.typeText("0x1234567890abcdef1234567890abcdef12345678")

        // Fill in amount
        let amountField = app.textFields["sendAmount"]
        amountField.tap()
        amountField.typeText("0.1")

        // Confirm
        app.buttons["reviewTransaction"].tap()

        // Verify confirmation screen
        let confirmScreen = app.otherElements["transactionConfirmation"]
        XCTAssertTrue(confirmScreen.waitForExistence(timeout: 5))

        // Verify gas is sponsored
        XCTAssertTrue(app.staticTexts["gasSponsoredLabel"].exists, "Gas should be sponsored on Base")

        // Confirm and send
        app.buttons["confirmSend"].tap()

        // Verify success with EAS attestation
        let successView = app.otherElements["transactionSuccess"]
        XCTAssertTrue(successView.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["attestationLink"].exists, "EAS attestation should be created")
    }

    func testSwapTokens_FullFlow() {
        app.tabBars.buttons["Home"].tap()
        app.buttons["swapButton"].tap()

        let fromField = app.textFields["swapFromAmount"]
        XCTAssertTrue(fromField.waitForExistence(timeout: 5))
        fromField.tap()
        fromField.typeText("1.0")

        // Select token pair
        app.buttons["selectToToken"].tap()
        app.staticTexts["USDC"].tap()

        // Review swap
        app.buttons["reviewSwap"].tap()
        let priceImpact = app.staticTexts["priceImpact"]
        XCTAssertTrue(priceImpact.exists, "Price impact should be displayed")

        // Confirm
        app.buttons["confirmSwap"].tap()
        let success = app.otherElements["transactionSuccess"]
        XCTAssertTrue(success.waitForExistence(timeout: 15))
    }

    func testStakeETH_FullFlow() {
        app.tabBars.buttons["Home"].tap()
        app.buttons["stakeButton"].tap()

        let amountField = app.textFields["stakeAmount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.tap()
        amountField.typeText("1.0")

        // Verify minimum stake displayed
        XCTAssertTrue(app.staticTexts["minimumStake"].exists, "1 ETH minimum should be shown")

        // Verify APY displayed (from C16 canonical calculator)
        XCTAssertTrue(app.staticTexts["apyDisplay"].exists, "APY from C16 should be displayed")

        // Verify 5% commission disclosed
        XCTAssertTrue(app.staticTexts["commissionRate"].exists, "5% commission should be disclosed")

        app.buttons["confirmStake"].tap()
        let success = app.otherElements["transactionSuccess"]
        XCTAssertTrue(success.waitForExistence(timeout: 15))
    }

    func testCreateContract_FullFlow() {
        app.tabBars.buttons["Build"].tap()
        app.buttons["newContract"].tap()

        // Select template
        app.staticTexts["Rental Agreement"].tap()

        // Fill basic terms
        let monthlyRent = app.textFields["monthlyRent"]
        XCTAssertTrue(monthlyRent.waitForExistence(timeout: 5))
        monthlyRent.tap()
        monthlyRent.typeText("0.5")

        // Review
        app.buttons["reviewContract"].tap()
        XCTAssertTrue(app.staticTexts["contractPreview"].exists)

        // Deploy
        app.buttons["deployContract"].tap()
        let success = app.otherElements["deploymentSuccess"]
        XCTAssertTrue(success.waitForExistence(timeout: 20))
    }
}
