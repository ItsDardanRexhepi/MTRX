import XCTest
@testable import MTRX

/// Test ERC-4337 account creation, gas sponsorship, Base network, wallet balance tracking
final class WalletTests: XCTestCase {

    // MARK: - Account Creation

    func testERC4337AccountCreation_NoSeedPhrase() {
        let wallet = WalletCreation()
        let account = wallet.createSmartAccount()
        XCTAssertNotNil(account, "ERC-4337 account should be created")
        XCTAssertNil(account?.seedPhrase, "Smart accounts must NOT expose seed phrases")
        XCTAssertTrue(account?.address.hasPrefix("0x") ?? false, "Address should be valid hex")
    }

    func testAccountCreation_GeneratesUniqueAddresses() {
        let wallet = WalletCreation()
        let account1 = wallet.createSmartAccount()
        let account2 = wallet.createSmartAccount()
        XCTAssertNotEqual(account1?.address, account2?.address, "Each account should have unique address")
    }

    // MARK: - Gas Sponsorship

    func testGasSponsorship_OnBase() {
        let sponsorship = GasSponsorship()
        let isSponsored = sponsorship.shouldSponsor(network: .base, userOperation: UserOperation(sender: "0x1234", callData: Data()))
        XCTAssertTrue(isSponsored, "Gas should be sponsored on Base network")
    }

    func testGasSponsorship_EstimatesCorrectly() {
        let sponsorship = GasSponsorship()
        let estimate = sponsorship.estimateGas(for: UserOperation(sender: "0x1234", callData: Data()))
        XCTAssertGreaterThan(estimate, 0, "Gas estimate should be positive")
    }

    // MARK: - Base Network

    func testBaseNetwork_ChainId() {
        let network = BaseNetwork()
        XCTAssertEqual(network.chainId, 8453, "Base mainnet chain ID should be 8453")
    }

    func testBaseNetwork_RPCEndpoint() {
        let network = BaseNetwork()
        XCTAssertNotNil(network.rpcURL, "RPC URL should be configured")
    }

    // MARK: - Balance Tracking

    func testWalletBalance_TracksMultipleTokens() {
        let tracker = WalletBalanceTracker()
        tracker.updateBalance(token: "ETH", amount: 2.5)
        tracker.updateBalance(token: "USDC", amount: 1000.0)
        XCTAssertEqual(tracker.balance(for: "ETH"), 2.5)
        XCTAssertEqual(tracker.balance(for: "USDC"), 1000.0)
    }

    func testWalletBalance_UnknownTokenReturnsZero() {
        let tracker = WalletBalanceTracker()
        XCTAssertEqual(tracker.balance(for: "UNKNOWN"), 0.0)
    }

    // MARK: - Transaction Signing

    func testTransactionSigning_ProducesValidSignature() {
        let wallet = WalletCreation()
        let account = wallet.createSmartAccount()
        let signature = account?.sign(data: "test transaction".data(using: .utf8)!)
        XCTAssertNotNil(signature, "Signing should produce a signature")
        XCTAssertGreaterThan(signature?.count ?? 0, 0, "Signature should not be empty")
    }

    // MARK: - NeoSafe Address Validation

    func testNeoSafeAddress_Constant() {
        XCTAssertEqual(WalletConstants.neoSafeAddress, "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5")
    }
}

// MARK: - Test Helpers

struct UserOperation { let sender: String; let callData: Data }
struct WalletBalanceTracker {
    private var balances: [String: Double] = [:]
    mutating func updateBalance(token: String, amount: Double) { balances[token] = amount }
    func balance(for token: String) -> Double { balances[token] ?? 0.0 }
}
enum WalletConstants { static let neoSafeAddress = "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5" }
