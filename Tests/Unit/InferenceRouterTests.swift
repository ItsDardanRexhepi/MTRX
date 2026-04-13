//
//  InferenceRouterTests.swift
//  MTRX — Tests
//
//  Tests for the two-layer inference router: complexity classification,
//  source selection, privacy mode, connectivity, and fallback behavior.
//

import XCTest
@testable import MTRX

final class InferenceRouterTests: XCTestCase {

    var router: InferenceRouter!

    override func setUp() {
        super.setUp()
        router = InferenceRouter()
        // Reset privacy mode between tests
        UserDefaults.standard.removeObject(forKey: "mtrx_privacy_mode")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "mtrx_privacy_mode")
        router = nil
        super.tearDown()
    }

    // MARK: - Complexity Classification

    func testConversationIntentIsSimple() {
        let intent = makeIntent(category: .conversation)
        XCTAssertEqual(router.classifyComplexity(intent: intent), .simple)
    }

    func testSettingsIntentIsSimple() {
        let intent = makeIntent(category: .settings)
        XCTAssertEqual(router.classifyComplexity(intent: intent), .simple)
    }

    func testAlertResponseWithoutDecisionIsSimple() {
        let intent = makeIntent(category: .alertResponse, requiresDecision: false)
        XCTAssertEqual(router.classifyComplexity(intent: intent), .simple)
    }

    func testAlertResponseWithDecisionIsComplex() {
        let intent = makeIntent(category: .alertResponse, requiresDecision: true)
        XCTAssertEqual(router.classifyComplexity(intent: intent), .complex)
    }

    func testQueryWithoutEntitiesIsSimple() {
        let intent = makeIntent(category: .query, entities: [:])
        XCTAssertEqual(router.classifyComplexity(intent: intent), .simple)
    }

    func testQueryWithEntitiesIsModerate() {
        let intent = makeIntent(category: .query, entities: ["asset": "ETH"])
        XCTAssertEqual(router.classifyComplexity(intent: intent), .moderate)
    }

    func testPortfolioIntentIsModerate() {
        let intent = makeIntent(category: .portfolio)
        XCTAssertEqual(router.classifyComplexity(intent: intent), .moderate)
    }

    func testActionWithoutDecisionIsModerate() {
        let intent = makeIntent(category: .action, requiresDecision: false)
        XCTAssertEqual(router.classifyComplexity(intent: intent), .moderate)
    }

    func testActionWithDecisionIsComplex() {
        let intent = makeIntent(category: .action, requiresDecision: true)
        XCTAssertEqual(router.classifyComplexity(intent: intent), .complex)
    }

    // MARK: - Complexity Ordering

    func testComplexityOrdering() {
        XCTAssertTrue(TaskComplexity.simple < TaskComplexity.moderate)
        XCTAssertTrue(TaskComplexity.moderate < TaskComplexity.complex)
        XCTAssertFalse(TaskComplexity.complex < TaskComplexity.simple)
    }

    // MARK: - Privacy Mode

    func testPrivacyModeDefaultOff() {
        XCTAssertFalse(router.isPrivacyModeEnabled)
    }

    func testPrivacyModeToggle() {
        router.isPrivacyModeEnabled = true
        XCTAssertTrue(router.isPrivacyModeEnabled)

        router.isPrivacyModeEnabled = false
        XCTAssertFalse(router.isPrivacyModeEnabled)
    }

    func testPrivacyModePersists() {
        router.isPrivacyModeEnabled = true

        // Create a new router — privacy mode should still be on
        let newRouter = InferenceRouter()
        XCTAssertTrue(newRouter.isPrivacyModeEnabled)
    }

    // MARK: - Source Selection

    func testActiveSourceWithoutFoundationModels() {
        // On test hardware without iOS 26, Foundation Models won't be available
        if !router.isOnDeviceAvailable {
            XCTAssertEqual(router.activeSource, .gateway)
        }
    }

    func testPrivacyModeFallsBackToLocalWithoutOnDevice() {
        router.isPrivacyModeEnabled = true
        if !router.isOnDeviceAvailable {
            XCTAssertEqual(router.activeSource, .localFallback)
        }
    }

    func testActiveSourceReflectsOnDeviceWhenAvailable() {
        // If Foundation Models is available (iOS 26 device), it should be preferred
        if router.isOnDeviceAvailable {
            XCTAssertEqual(router.activeSource, .foundationModels)
        }
    }

    // MARK: - Connectivity

    func testOfflineDefaultFalse() {
        XCTAssertFalse(router.isOffline)
    }

    func testUpdateConnectivityOffline() {
        router.updateConnectivity(isConnected: false)
        XCTAssertTrue(router.isOffline)
    }

    func testUpdateConnectivityOnline() {
        router.updateConnectivity(isConnected: false)
        XCTAssertTrue(router.isOffline)

        router.updateConnectivity(isConnected: true)
        XCTAssertFalse(router.isOffline)
    }

    // MARK: - Inference Result Structure

    func testInferenceResultMetadata() {
        let result = InferenceResult(
            text: "Hello",
            source: .foundationModels,
            confidence: 0.85,
            latencyMs: 42.0,
            metadata: ["engine": "apple_foundation_models", "on_device": "true"]
        )

        XCTAssertEqual(result.text, "Hello")
        XCTAssertEqual(result.source, .foundationModels)
        XCTAssertEqual(result.confidence, 0.85)
        XCTAssertEqual(result.latencyMs, 42.0)
        XCTAssertEqual(result.metadata["on_device"], "true")
    }

    func testInferenceSourceRawValues() {
        XCTAssertEqual(InferenceSource.foundationModels.rawValue, "on_device")
        XCTAssertEqual(InferenceSource.coreML.rawValue, "coreml")
        XCTAssertEqual(InferenceSource.gateway.rawValue, "gateway")
        XCTAssertEqual(InferenceSource.localFallback.rawValue, "local")
    }

    // MARK: - Generation Fallback

    func testSimpleGenerationReturnsResult() async {
        let result = await router.generate(
            prompt: "Hello Trinity",
            complexity: .simple
        )
        // Without Foundation Models on test hardware, this will hit gateway or local fallback
        XCTAssertTrue(
            result.source == .foundationModels ||
            result.source == .gateway ||
            result.source == .localFallback
        )
        XCTAssertGreaterThanOrEqual(result.latencyMs, 0)
    }

    func testComplexGenerationReturnsResult() async {
        let result = await router.generate(
            prompt: "Deploy an ERC-20 token called TestCoin",
            complexity: .complex
        )
        // Complex tasks prefer gateway; will fall back if unavailable
        XCTAssertTrue(
            result.source == .gateway ||
            result.source == .foundationModels ||
            result.source == .localFallback
        )
    }

    func testPrivacyModeBlocksGateway() async {
        router.isPrivacyModeEnabled = true
        let result = await router.generate(
            prompt: "What is my portfolio worth?",
            complexity: .moderate
        )
        // In privacy mode, source should never be gateway
        XCTAssertNotEqual(result.source, .gateway)
    }

    // MARK: - Session Management

    func testResetSessionDoesNotCrash() {
        // Should complete without error regardless of Foundation Models availability
        router.resetSession()
    }

    // MARK: - Helpers

    private func makeIntent(
        category: IntentCategory,
        entities: [String: String] = [:],
        requiresDecision: Bool = false
    ) -> TrinityIntent {
        TrinityIntent(
            description: "test message",
            category: category,
            entities: entities,
            requiresDecision: requiresDecision,
            timeSensitivity: .medium,
            decisionContext: [:],
            confidence: 0.8
        )
    }
}
