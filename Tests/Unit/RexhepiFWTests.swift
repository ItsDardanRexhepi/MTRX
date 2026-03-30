import XCTest
@testable import MTRX

/// Test all 6 gates, all outcomes, HardRules validation, DecisionLog, and TimeSensitivity
final class RexhepiFWTests: XCTestCase {

    // MARK: - Gate Evaluation Tests

    func testClarityGate_ClearAction_ScoresHigh() {
        let context = ExecutionContext(action: "deploy contract", description: "Deploy rental agreement to Base mainnet for user at 0x1234")
        let score = RexhepiEngine.evaluateGate(.clarity, context: context)
        XCTAssertGreaterThan(score, 0.5, "Clear, specific actions should score high on clarity")
    }

    func testClarityGate_VagueAction_ScoresLow() {
        let context = ExecutionContext(action: "do something", description: "")
        let score = RexhepiEngine.evaluateGate(.clarity, context: context)
        XCTAssertLessThan(score, 0.5, "Vague actions should score low on clarity")
    }

    func testFeasibilityGate_ValidAction_Passes() {
        let context = ExecutionContext(action: "stake ETH", description: "Stake 2 ETH via Component 16 staking")
        let score = RexhepiEngine.evaluateGate(.feasibility, context: context)
        XCTAssertGreaterThan(score, 0.0)
    }

    func testRiskGate_HighValueTransfer_FlagsRisk() {
        let context = ExecutionContext(action: "transfer", description: "Transfer 100 ETH to external wallet", valueETH: 100.0)
        let score = RexhepiEngine.evaluateGate(.risk, context: context)
        XCTAssertGreaterThan(score, 0.5, "Large transfers should flag high risk")
    }

    func testRiskGate_SmallTransfer_LowRisk() {
        let context = ExecutionContext(action: "transfer", description: "Send 0.01 ETH", valueETH: 0.01)
        let score = RexhepiEngine.evaluateGate(.risk, context: context)
        XCTAssertLessThan(score, 0.3, "Small transfers should have low risk")
    }

    func testUncertaintyGate_UnverifiedToken_HighUncertainty() {
        let context = ExecutionContext(action: "swap", description: "Swap ETH for unverified token SCAM123", isVerified: false)
        let score = RexhepiEngine.evaluateGate(.uncertainty, context: context)
        XCTAssertGreaterThan(score, 0.5)
    }

    func testValueGate_DAOCreation_HighValue() {
        let context = ExecutionContext(action: "create DAO", description: "Convert user's business to DAO structure")
        let score = RexhepiEngine.evaluateGate(.value, context: context)
        XCTAssertGreaterThan(score, 0.3, "DAO creation provides high user value")
    }

    func testLoopLimitGate_FirstAttempt_NoLoopDetected() {
        let context = ExecutionContext(action: "deploy", description: "First deployment attempt", attemptCount: 1)
        let score = RexhepiEngine.evaluateGate(.loopLimit, context: context)
        XCTAssertEqual(score, 0.0, "First attempt should have zero loop score")
    }

    func testLoopLimitGate_RepeatedAttempts_FlagsLoop() {
        let context = ExecutionContext(action: "deploy", description: "Repeated deploy failure", attemptCount: 5)
        let score = RexhepiEngine.evaluateGate(.loopLimit, context: context)
        XCTAssertGreaterThan(score, 0.5, "Repeated failures should flag loop")
    }

    // MARK: - Outcome Tests

    func testOutcome_AllGreen_Execute() {
        let scores = GateScores(clarity: 0.9, feasibility: 0.9, risk: 0.1, uncertainty: 0.1, value: 0.9, loopLimit: 0.0)
        XCTAssertEqual(Outcome.determine(from: scores), .execute)
    }

    func testOutcome_HighRisk_Abort() {
        let scores = GateScores(clarity: 0.9, feasibility: 0.9, risk: 0.95, uncertainty: 0.1, value: 0.9, loopLimit: 0.0)
        XCTAssertEqual(Outcome.determine(from: scores), .abort)
    }

    func testOutcome_LowClarity_Ask() {
        let scores = GateScores(clarity: 0.2, feasibility: 0.9, risk: 0.1, uncertainty: 0.1, value: 0.9, loopLimit: 0.0)
        XCTAssertEqual(Outcome.determine(from: scores), .ask)
    }

    func testOutcome_HighUncertainty_Probe() {
        let scores = GateScores(clarity: 0.9, feasibility: 0.9, risk: 0.1, uncertainty: 0.8, value: 0.9, loopLimit: 0.0)
        XCTAssertEqual(Outcome.determine(from: scores), .probe)
    }

    func testOutcome_LowFeasibility_Defer() {
        let scores = GateScores(clarity: 0.9, feasibility: 0.1, risk: 0.1, uncertainty: 0.1, value: 0.9, loopLimit: 0.0)
        XCTAssertEqual(Outcome.determine(from: scores), .defer_)
    }

    // MARK: - HardRules Tests

    func testHardRules_NoPublishWithoutApproval() {
        let result = HardRules.validate(action: .publish, isApproved: false)
        XCTAssertTrue(result.violations.contains(.noPublishWithoutApproval))
    }

    func testHardRules_ApprovedPublish_NoViolation() {
        let result = HardRules.validate(action: .publish, isApproved: true)
        XCTAssertFalse(result.violations.contains(.noPublishWithoutApproval))
    }

    func testHardRules_NeoSafeAddressImmutable() {
        XCTAssertEqual(HardRules.neoSafeAddress, "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5")
    }

    // MARK: - DecisionLog Tests

    func testDecisionLog_AppendOnly() {
        let log = DecisionLog()
        log.append(entry: DecisionEntry(action: "test", outcome: .execute, timestamp: Date()))
        log.append(entry: DecisionEntry(action: "test2", outcome: .abort, timestamp: Date()))
        XCTAssertEqual(log.count, 2)
    }

    func testDecisionLog_CannotDelete() {
        let log = DecisionLog()
        log.append(entry: DecisionEntry(action: "permanent", outcome: .execute, timestamp: Date()))
        // DecisionLog has no delete method — this is by design
        XCTAssertEqual(log.count, 1, "Entries cannot be removed from append-only log")
    }

    // MARK: - TimeSensitivity Tests

    func testHighTimeSensitivity_ReducesThresholds() {
        let modifier = TimeSensitivity.high.thresholdModifier
        XCTAssertLessThan(modifier, 1.0, "High time sensitivity should reduce gate thresholds")
    }

    func testLowTimeSensitivity_NoModification() {
        let modifier = TimeSensitivity.low.thresholdModifier
        XCTAssertEqual(modifier, 1.0, "Low time sensitivity should not modify thresholds")
    }

    func testCriticalTimeSensitivity_MaxReduction() {
        let modifier = TimeSensitivity.critical.thresholdModifier
        XCTAssertLessThanOrEqual(modifier, TimeSensitivity.high.thresholdModifier)
    }
}
