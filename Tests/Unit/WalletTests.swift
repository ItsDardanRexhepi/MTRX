import XCTest
@testable import MTRX

/// Real tests for the wallet stack: Secure Enclave signing, address derivation,
/// the Base network config gate, and gas-sponsorship policy evaluation.
/// Everything here exercises the actual shipping APIs (no mock-success stubs);
/// on the Simulator the enclave falls back to a real software P-256 key.
final class WalletTests: XCTestCase {

    // MARK: - Secure Enclave (real CryptoKit)

    func testEnclave_signProducesRealNonEmptySignature() throws {
        let mgr = SecureEnclaveManager.shared
        let tag = "test.enclave.\(UUID().uuidString)"
        defer { mgr.deleteKey(tag: tag) }

        try mgr.ensureKey(tag: tag)
        XCTAssertTrue(mgr.hasKey(tag: tag), "Key should exist after ensureKey")

        let message = Data("hello mtrx".utf8)
        let sig = try mgr.sign(message, tag: tag)
        XCTAssertGreaterThan(sig.count, 0, "Signature must not be empty (no zero-byte fakes)")
        XCTAssertFalse(sig.allSatisfy { $0 == 0 }, "Signature must not be all zero bytes")
    }

    func testEnclave_deleteKeyRemovesIt() throws {
        let mgr = SecureEnclaveManager.shared
        let tag = "test.enclave.del.\(UUID().uuidString)"
        try mgr.ensureKey(tag: tag)
        XCTAssertTrue(mgr.hasKey(tag: tag))
        mgr.deleteKey(tag: tag)
        XCTAssertFalse(mgr.hasKey(tag: tag), "Key should be gone after deleteKey")
    }

    func testEnclave_publicKeyIsStablePerTag() throws {
        let mgr = SecureEnclaveManager.shared
        let tag = "test.enclave.pub.\(UUID().uuidString)"
        defer { mgr.deleteKey(tag: tag) }
        let a = try mgr.publicKeyData(tag: tag)
        let b = try mgr.publicKeyData(tag: tag)
        XCTAssertEqual(a, b, "Same tag must yield the same public key")
        XCTAssertGreaterThan(a.count, 0)
    }

    /// Load-bearing anti-fake guard: exercises the ACTUAL former-fake site
    /// (`DefaultSecureEnclaveProvider.sign`, which once returned `Data(count: 64)`).
    /// If that method were ever reverted to a zero-byte signature, the
    /// not-all-zero assertion below FAILS — which the SecureEnclaveManager-only
    /// tests above would not catch. (Proven: reverting the method makes this fail.)
    func testDefaultProvider_signIsRealNotZeroBytes() throws {
        let provider = DefaultSecureEnclaveProvider()
        let tag = "test.defaultprovider.\(UUID().uuidString)"
        defer { try? provider.deleteKey(tag: tag) }

        _ = try provider.generateKeyPair(tag: tag)
        let sig = try provider.sign(data: Data("intent envelope".utf8), withKeyTag: tag)

        XCTAssertGreaterThan(sig.count, 0, "Provider signature must not be empty")
        XCTAssertFalse(sig.allSatisfy { $0 == 0 },
                       "Provider signature must not be all-zero (guards the Data(count:64) fake)")
    }

    // MARK: - Address derivation

    @MainActor
    func testWalletCore_derivesValidHexAddress() {
        let pub = Data((0..<32).map { UInt8($0) })
        let addr = WalletCore.deriveAddress(fromPublicKey: pub)
        XCTAssertTrue(addr.hasPrefix("0x"), "Address should be 0x-prefixed")
        XCTAssertEqual(addr.count, 42, "EVM address is 0x + 40 hex chars")
    }

    // MARK: - Network config gate (no hardcoded endpoints)

    func testBaseNetwork_chainIdConstant() {
        XCTAssertEqual(BaseNetwork.chainId, 8453, "Base mainnet chain id")
    }

    func testBaseNetwork_activeEndpointNilUntilConfigured() {
        if PendingCredentials.filled(PendingCredentials.Network.rpcURL) == nil {
            XCTAssertNil(BaseNetwork.RPCEndpoints().activeHTTP,
                         "No RPC configured → no active endpoint (no hardcoded URL)")
        }
        let custom = URL(string: "https://example.test")!
        XCTAssertEqual(BaseNetwork.RPCEndpoints(custom: custom).activeHTTP, custom)
    }

    // MARK: - Gas sponsorship policy + estimation

    private func sampleOperation(callGas: UInt64 = 100_000) -> UserOperation {
        UserOperation(
            sender: "0x000000000000000000000000000000000000dEaD",
            nonce: 0,
            initCode: Data(),
            callData: Data([0x01, 0x02, 0x03]),
            callGasLimit: callGas,
            verificationGasLimit: 100_000,
            preVerificationGas: 21_000,
            maxFeePerGas: 1_000_000,
            maxPriorityFeePerGas: 1_000_000,
            paymasterAndData: Data(),
            signature: Data()
        )
    }

    func testGasSponsorship_evaluatesFreeTierPolicy() {
        let sponsorship = GasSponsorship(paymasterAddress: "", platformBudgetWei: 1_000_000_000_000)
        let result = sponsorship.evaluateSponsorship(
            operation: sampleOperation(),
            userAddress: "0xUser",
            userTier: .free
        )
        switch result {
        case .success(let policy):
            XCTAssertEqual(policy.userTier, .free)
        case .failure(let error):
            XCTFail("Free-tier op within limits should qualify, got \(error)")
        }
    }

    func testGasSponsorship_rejectsOverGasLimit() {
        let sponsorship = GasSponsorship(paymasterAddress: "", platformBudgetWei: 1_000_000_000_000)
        let result = sponsorship.evaluateSponsorship(
            operation: sampleOperation(callGas: 5_000_000),
            userAddress: "0xUser",
            userTier: .free
        )
        if case .success = result {
            XCTFail("Operation exceeding the per-op gas limit must be rejected")
        }
    }

    func testGasSponsorship_costIsZeroWhenPriceUnknown() {
        let sponsorship = GasSponsorship(paymasterAddress: "", platformBudgetWei: 1_000_000_000_000)
        let estimate = sponsorship.estimateGas(for: sampleOperation())
        XCTAssertGreaterThan(estimate.totalGasWei, 0, "L2 execution fee should be > 0")
        if PendingCredentials.filled(PendingCredentials.Pricing.ethUsdSource) == nil {
            XCTAssertEqual(estimate.estimatedCostUSD, 0, "USD cost is 0 when no price source is set")
        }
    }

    // MARK: - Config keystone

    func testPendingCredentials_blankReturnsNil() {
        XCTAssertNil(PendingCredentials.filled(""))
        XCTAssertNil(PendingCredentials.filled("   "))
        XCTAssertEqual(PendingCredentials.filled("  0xabc  "), "0xabc")
    }
}
