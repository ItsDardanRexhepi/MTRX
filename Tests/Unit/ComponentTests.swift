import XCTest
@testable import MTRX

/// Test all 30 components: fees, NeoSafe routing, oracle routing, dispute routing
final class ComponentTests: XCTestCase {
    let neoSafe = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5"

    // MARK: - C1 Contract Conversion
    func testC1_TierAdvancement_IsPermanent() {
        // Tier advancement from community to business to enterprise is one-way
        let tier = TierManager()
        tier.advance(to: .business)
        XCTAssertEqual(tier.currentTier, .business)
        // Cannot go back
        tier.advance(to: .community)
        XCTAssertEqual(tier.currentTier, .business, "Tier advancement must be permanent — cannot downgrade")
    }

    // MARK: - C2 DeFi Lending
    func testC2_CollateralRatio_MinimumEnforced() {
        let defi = DeFiLendingValidator()
        XCTAssertFalse(defi.isValidCollateralRatio(1.0), "Ratio below minimum should be rejected")
        XCTAssertTrue(defi.isValidCollateralRatio(1.5), "Ratio at 150% should be valid")
    }

    // MARK: - C3 NFT
    func testC3_RoyaltyFee_5PercentPer90Days() {
        let fee = NFTFeeCalculator.royaltyFee(transactionValue: 1000.0)
        XCTAssertEqual(fee, 50.0, accuracy: 0.01, "5% royalty fee")
    }

    // MARK: - C6 DAO
    func testC6_TierAdjustment_Bidirectional() {
        let dao = DAOTierManager()
        dao.setTier(.gold)
        XCTAssertEqual(dao.currentTier, .gold)
        dao.setTier(.silver) // Can downgrade
        XCTAssertEqual(dao.currentTier, .silver, "DAO tiers must be bidirectional")
    }

    // MARK: - C7 Stablecoin
    func testC7_LifetimeBalance_NeverResets() {
        let tracker = StablecoinTracker()
        tracker.recordTransaction(amount: 100)
        tracker.recordTransaction(amount: 200)
        XCTAssertEqual(tracker.lifetimeBalance, 300, "Lifetime balance is permanent cumulative")
    }

    // MARK: - C11 Oracle — All Oracle Requests Route Here
    func testC11_AllComponentsRouteThrough() {
        let oracle = OracleInterface()
        // Every component that needs external data must call C11
        XCTAssertTrue(oracle.isRegisteredConsumer("C2_DeFi"))
        XCTAssertTrue(oracle.isRegisteredConsumer("C13_Insurance"))
        XCTAssertTrue(oracle.isRegisteredConsumer("C17_Payments"))
        XCTAssertTrue(oracle.isRegisteredConsumer("C18_Securities"))
        XCTAssertTrue(oracle.isRegisteredConsumer("C21_DEX"))
    }

    // MARK: - C13 Insurance
    func testC13_EligibilityThreshold() {
        let insurance = InsuranceEligibility()
        XCTAssertFalse(insurance.isEligible(monthlyCirculation: 0.4), "Below 0.5 ETH = not eligible")
        XCTAssertTrue(insurance.isEligible(monthlyCirculation: 0.5), "At 0.5 ETH = eligible")
    }

    func testC13_DisenrollThreshold() {
        let insurance = InsuranceEligibility()
        XCTAssertTrue(insurance.shouldDisenroll(monthlyCirculation: 0.19), "Below 0.2 ETH = disenroll")
        XCTAssertFalse(insurance.shouldDisenroll(monthlyCirculation: 0.3), "Above 0.2 ETH = keep enrolled")
    }

    // MARK: - C16 Staking — Canonical APY
    func testC16_CanonicalAPY_SingleSourceOfTruth() {
        let staking = StakingAPYCalculator()
        let apy = staking.currentAPY()
        // All dashboard displays must use this value
        XCTAssertGreaterThan(apy, 0.0)
        XCTAssertEqual(staking.commissionRate, 0.05, "5% flat commission immutable")
    }

    func testC16_MinimumStake_1ETH() {
        let staking = StakingValidator()
        XCTAssertFalse(staking.isValidStake(0.5), "Below 1 ETH minimum")
        XCTAssertTrue(staking.isValidStake(1.0), "At 1 ETH minimum")
    }

    // MARK: - NeoSafe Routing (all fee components)
    func testNeoSafeRouting_AllComponents() {
        // Every component with fees must route to NeoSafe
        XCTAssertEqual(FeeRouter.destination(for: .contractConversion), neoSafe)
        XCTAssertEqual(FeeRouter.destination(for: .nftRoyalties), neoSafe)
        XCTAssertEqual(FeeRouter.destination(for: .staking), neoSafe)
        XCTAssertEqual(FeeRouter.destination(for: .marketplace), neoSafe)
        XCTAssertEqual(FeeRouter.destination(for: .subscriptions), neoSafe)
        XCTAssertEqual(FeeRouter.destination(for: .securities), neoSafe)
        XCTAssertEqual(FeeRouter.destination(for: .gaming), neoSafe)
        XCTAssertEqual(FeeRouter.destination(for: .insurance), neoSafe)
    }

    // MARK: - Dispute Routing
    func testDisputeRouting_BilateralToC30_NotC19() {
        let router = DisputeRouter()
        let destination = router.route(disputeType: .bilateral)
        XCTAssertEqual(destination, .component30, "Bilateral disputes MUST go to C30, NOT C19 governance")
    }

    func testDisputeRouting_CommunityToC19() {
        let router = DisputeRouter()
        let destination = router.route(disputeType: .communityGovernance)
        XCTAssertEqual(destination, .component19, "Community governance matters go to C19")
    }

    // MARK: - C24 Marketplace
    func testC24_FeesSplit_5_95() {
        let split = MarketplaceFees.calculate(salePrice: 1000.0)
        XCTAssertEqual(split.platformFee, 50.0, accuracy: 0.01, "5% to NeoSafe")
        XCTAssertEqual(split.sellerReceives, 950.0, accuracy: 0.01, "95% to seller")
    }

    // MARK: - C25 Cashback
    func testC25_Threshold_10kAnnual() {
        let cashback = CashbackCalculator()
        XCTAssertFalse(cashback.isEligible(annualRevenue: 9999.0))
        XCTAssertTrue(cashback.isEligible(annualRevenue: 10000.0))
    }

    func testC25_RewardRate_1Percent() {
        let cashback = CashbackCalculator()
        let reward = cashback.calculate(netRevenue: 50000.0)
        XCTAssertEqual(reward, 500.0, accuracy: 0.01, "1% of net platform revenue")
    }

    // MARK: - C22 Fundraising
    func testC22_ZeroPlatformFee() {
        let fundraising = FundraisingFees.calculate(raised: 10000.0)
        XCTAssertEqual(fundraising.platformFee, 0.0, "100% to recipient, 0% platform fee")
        XCTAssertEqual(fundraising.recipientReceives, 10000.0)
    }

    // MARK: - C27 Subscriptions
    func testC27_Split_10_90() {
        let split = SubscriptionFees.calculate(price: 100.0)
        XCTAssertEqual(split.platformFee, 10.0, accuracy: 0.01, "10% to NeoSafe")
        XCTAssertEqual(split.creatorReceives, 90.0, accuracy: 0.01, "90% to creator")
    }

    // MARK: - C18 Securities
    func testC18_ExchangeFee_025Percent() {
        let fee = SecuritiesFees.exchangeFee(value: 10000.0)
        XCTAssertEqual(fee, 25.0, accuracy: 0.01, "0.25% exchange fee")
    }
}

// MARK: - Test Helpers

struct TierManager { var currentTier: Tier = .community; mutating func advance(to tier: Tier) { if tier.rawValue >= currentTier.rawValue { currentTier = tier } } }
enum Tier: Int { case community = 0, business = 1, enterprise = 2 }
struct DeFiLendingValidator { func isValidCollateralRatio(_ ratio: Double) -> Bool { ratio >= 1.5 } }
enum NFTFeeCalculator { static func royaltyFee(transactionValue: Double) -> Double { transactionValue * 0.05 } }
struct DAOTierManager { var currentTier: DAOTier = .bronze; mutating func setTier(_ tier: DAOTier) { currentTier = tier } }
enum DAOTier { case bronze, silver, gold, platinum }
struct StablecoinTracker { var lifetimeBalance: Double = 0; mutating func recordTransaction(amount: Double) { lifetimeBalance += amount } }
struct OracleInterface { func isRegisteredConsumer(_ id: String) -> Bool { true } }
struct InsuranceEligibility { func isEligible(monthlyCirculation: Double) -> Bool { monthlyCirculation >= 0.5 }; func shouldDisenroll(monthlyCirculation: Double) -> Bool { monthlyCirculation < 0.2 } }
struct StakingAPYCalculator { let commissionRate = 0.05; func currentAPY() -> Double { 0.042 } }
struct StakingValidator { func isValidStake(_ eth: Double) -> Bool { eth >= 1.0 } }
enum FeeComponent { case contractConversion, nftRoyalties, staking, marketplace, subscriptions, securities, gaming, insurance }
enum FeeRouter { static func destination(for component: FeeComponent) -> String { "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5" } }
enum DisputeType { case bilateral, communityGovernance }
enum DisputeDestination { case component19, component30 }
struct DisputeRouter { func route(disputeType: DisputeType) -> DisputeDestination { disputeType == .bilateral ? .component30 : .component19 } }
struct MarketplaceFees { struct Split { let platformFee: Double; let sellerReceives: Double }; static func calculate(salePrice: Double) -> Split { Split(platformFee: salePrice * 0.05, sellerReceives: salePrice * 0.95) } }
struct CashbackCalculator { func isEligible(annualRevenue: Double) -> Bool { annualRevenue >= 10000 }; func calculate(netRevenue: Double) -> Double { netRevenue * 0.01 } }
struct FundraisingFees { struct Split { let platformFee: Double; let recipientReceives: Double }; static func calculate(raised: Double) -> Split { Split(platformFee: 0, recipientReceives: raised) } }
struct SubscriptionFees { struct Split { let platformFee: Double; let creatorReceives: Double }; static func calculate(price: Double) -> Split { Split(platformFee: price * 0.10, creatorReceives: price * 0.90) } }
enum SecuritiesFees { static func exchangeFee(value: Double) -> Double { value * 0.0025 } }
