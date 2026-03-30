import XCTest

/// XCUITest: Trinity conversation flows, onboarding, plain language command processing
final class TrinityFlowTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testTrinityGreeting_AppearsOnLaunch() {
        let trinityMessage = app.staticTexts["trinityGreeting"]
        XCTAssertTrue(trinityMessage.waitForExistence(timeout: 5), "Trinity greeting should appear on launch")
    }

    func testTrinityInput_AcceptsText() {
        let inputField = app.textFields["trinityInput"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5))
        inputField.tap()
        inputField.typeText("check my portfolio")
        app.buttons["sendButton"].tap()
        let response = app.staticTexts["trinityResponse"]
        XCTAssertTrue(response.waitForExistence(timeout: 10), "Trinity should respond to portfolio query")
    }

    func testTrinityCommand_SendETH_ShowsConfirmation() {
        let inputField = app.textFields["trinityInput"]
        XCTAssertTrue(inputField.waitForExistence(timeout: 5))
        inputField.tap()
        inputField.typeText("send 0.5 ETH to alice.eth")
        app.buttons["sendButton"].tap()

        // Should show confirmation screen with fee breakdown
        let confirmationView = app.otherElements["transactionConfirmation"]
        XCTAssertTrue(confirmationView.waitForExistence(timeout: 10), "Confirmation screen should appear")

        // Verify fee breakdown is visible
        let feeBreakdown = app.staticTexts["feeBreakdown"]
        XCTAssertTrue(feeBreakdown.exists, "Fee breakdown should be displayed")
    }

    func testTrinityCommand_StakeETH_ShowsStakingView() {
        let inputField = app.textFields["trinityInput"]
        inputField.tap()
        inputField.typeText("stake 2 ETH")
        app.buttons["sendButton"].tap()

        let stakingView = app.otherElements["stakingConfirmation"]
        XCTAssertTrue(stakingView.waitForExistence(timeout: 10))
    }

    func testTrinityCommand_CreateContract_NavigatesToBuild() {
        let inputField = app.textFields["trinityInput"]
        inputField.tap()
        inputField.typeText("create a rental agreement")
        app.buttons["sendButton"].tap()

        let buildView = app.otherElements["contractBuilder"]
        XCTAssertTrue(buildView.waitForExistence(timeout: 10))
    }

    func testTrinityVoice_MicButton_Exists() {
        let micButton = app.buttons["voiceInputButton"]
        XCTAssertTrue(micButton.waitForExistence(timeout: 5), "Voice input button should exist")
    }
}
