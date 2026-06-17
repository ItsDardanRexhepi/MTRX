import CryptoKit
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

    // MARK: - ERC-4337 signs with the enclave key (not a throwaway)

    /// Proves signOperation signs with the user's Secure Enclave key: the
    /// returned signature verifies against THAT tag's public key. A throwaway
    /// key (the old behavior) would not verify against this public key.
    func testSignOperation_usesEnclaveKey_notThrowaway() throws {
        let tag = "test.erc4337.\(UUID().uuidString)"
        let mgr = SecureEnclaveManager.shared
        defer { mgr.deleteKey(tag: tag) }
        let pubRaw = try mgr.publicKeyData(tag: tag)

        let url = URL(string: "https://unused.invalid")!
        let cfg = BaseNetworkConfig(rpcURL: url, chainId: 8453, bundlerURL: url)
        let manager = ERC4337Manager(entryPointAddress: "", paymasterAddress: nil, bundlerURL: url, networkConfig: cfg)
        manager.configureSigningKey(tag: tag)

        let op = sampleOperation()
        let exp = expectation(description: "sign")
        var signed: UserOperation?
        manager.signOperation(op) { result in
            if case .success(let s) = result { signed = s }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        let sig = try XCTUnwrap(signed?.signature, "signOperation must succeed with a configured enclave key")
        XCTAssertGreaterThan(sig.count, 0)

        // Reconstruct the exact message the manager signs (opHash ++ entryPoint ++
        // chainId, keccak256'd) and verify the signature against the enclave key.
        var message = Data()
        message.append(Self.hexToData(op.hash))
        message.append(ABIEncoder.encodeAddress(""))
        message.append(ABIEncoder.encodeUInt256(UInt64(8453)))
        let messageHash = Keccak256.hash(data: message)

        let pub = try P256.Signing.PublicKey(rawRepresentation: pubRaw)
        let ecdsa = try P256.Signing.ECDSASignature(derRepresentation: sig)
        XCTAssertTrue(pub.isValidSignature(ecdsa, for: messageHash),
                      "Signature must verify against the configured ENCLAVE key, not a throwaway")
    }

    /// Without a configured enclave key, signing must FAIL — never a throwaway.
    func testSignOperation_refusesWithoutConfiguredKey() {
        let url = URL(string: "https://unused.invalid")!
        let cfg = BaseNetworkConfig(rpcURL: url, chainId: 8453, bundlerURL: url)
        let manager = ERC4337Manager(entryPointAddress: "", paymasterAddress: nil, bundlerURL: url, networkConfig: cfg)
        let exp = expectation(description: "refuse")
        var didFail = false
        manager.signOperation(sampleOperation()) { result in
            if case .failure = result { didFail = true }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertTrue(didFail, "No enclave key configured → must refuse to sign (no throwaway key)")
    }

    static func hexToData(_ hex: String) -> Data {
        var s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        if s.count % 2 != 0 { s = "0" + s }
        var d = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let n = s.index(i, offsetBy: 2)
            if let b = UInt8(s[i..<n], radix: 16) { d.append(b) }
            i = n
        }
        return d
    }

    // MARK: - Submit pipeline (end-to-end via MockURLProtocol)

    /// Drives the whole WalletTransactionService pipeline against a mocked
    /// transport: it must build the op, fetch sponsorship from the (mock)
    /// paymaster SERVER, sign with the user's ENCLAVE key, and submit to the
    /// (mock) bundler. The signature is verified against the enclave key's
    /// public key — so the test FAILS if signing were bypassed, faked
    /// (zero bytes), or done with a throwaway key, and FAILS if it didn't submit.
    @MainActor
    func testSubmitPipeline_buildsSignsWithEnclave_andSubmits() async throws {
        let mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: mockConfig)
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let entryPoint = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
        let pmData = "0x" + String(repeating: "ab", count: 97) // addr(20)+window(12)+sig(65)
        let expectedHash = "0x1234567890abcdef00000000000000000000000000000000000000000000abcd"

        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            let json = request.httpBody.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            if url.contains("paymaster.test") {
                return try MockURLProtocol.json(["paymasterAndData": pmData])
            }
            if (json?["method"] as? String) == "eth_sendUserOperation" {
                return try MockURLProtocol.json(["jsonrpc": "2.0", "id": 1, "result": expectedHash])
            }
            return try MockURLProtocol.json(["jsonrpc": "2.0", "id": 1, "result": [:]])
        }

        // Real enclave key the pipeline must sign with.
        let tag = "test.pipeline.\(UUID().uuidString)"
        let enclave = SecureEnclaveManager.shared
        defer { enclave.deleteKey(tag: tag) }
        let pubRaw = try enclave.publicKeyData(tag: tag)

        let cfg = WalletTransactionService.Config(
            rpcURL: URL(string: "https://rpc.test")!,
            bundlerURL: URL(string: "https://bundler.test")!,
            chainID: 8453,
            entryPoint: entryPoint,
            paymasterAddress: "0x1111111111111111111111111111111111111111",
            paymasterSignatureEndpoint: "https://paymaster.test/sign",
            platformBudgetWei: 1_000_000_000_000_000_000
        )
        let service = try XCTUnwrap(WalletTransactionService(config: cfg, session: session))

        let submission = try await service.submitCall(
            to: "0x2222222222222222222222222222222222222222",
            value: 0,
            data: Data([0xde, 0xad, 0xbe, 0xef]),
            sender: "0x3333333333333333333333333333333333333333",
            signingKeyTag: tag
        )

        // Submitted and returned the BUNDLER's hash (not a hardcoded success).
        XCTAssertEqual(submission.userOpHash, expectedHash)

        // The bundler actually received eth_sendUserOperation.
        let sawBundler = MockURLProtocol.seenRequests.contains { req in
            guard req.url?.absoluteString.contains("bundler.test") == true,
                  let b = req.httpBody,
                  let j = (try? JSONSerialization.jsonObject(with: b)) as? [String: Any] else { return false }
            return (j["method"] as? String) == "eth_sendUserOperation"
        }
        XCTAssertTrue(sawBundler, "Pipeline must submit via the bundler (eth_sendUserOperation)")

        // The paymaster SERVER was actually called for sponsorship.
        XCTAssertTrue(MockURLProtocol.seenRequests.contains { $0.url?.absoluteString.contains("paymaster.test") == true },
                      "Pipeline must fetch sponsorship from the paymaster server")
        XCTAssertFalse(submission.signedOperation.paymasterAndData.isEmpty,
                       "paymasterAndData must be set from the server response")

        // CRITICAL: the op is signed by the ENCLAVE key — verify the signature
        // against the tag's public key. Fails if bypassed / faked / throwaway.
        let sig = submission.signedOperation.signature
        XCTAssertGreaterThan(sig.count, 0)
        XCTAssertFalse(sig.allSatisfy { $0 == 0 })
        var message = Data()
        message.append(Self.hexToData(submission.signedOperation.hash))
        message.append(ABIEncoder.encodeAddress(entryPoint))
        message.append(ABIEncoder.encodeUInt256(UInt64(8453)))
        let messageHash = Keccak256.hash(data: message)
        let pub = try P256.Signing.PublicKey(rawRepresentation: pubRaw)
        let ecdsa = try P256.Signing.ECDSASignature(derRepresentation: sig)
        XCTAssertTrue(pub.isValidSignature(ecdsa, for: messageHash),
                      "UserOp must be signed by the configured ENCLAVE key — not faked, not a throwaway")
    }

    // MARK: - Guardian recovery rotation submits through the pipeline

    /// Proves the Phase-4 guardian-recovery loop is closed onto the pipeline:
    /// the owner-rotation actually SUBMITS through the bundler (proof-of-submit),
    /// not a clean-failure stub.
    @MainActor
    func testGuardianRotation_submitsThroughPipeline() async throws {
        let mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: mockConfig)
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let expectedHash = "0xRECABC000000000000000000000000000000000000000000000000000000ce00"
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            let json = request.httpBody.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            if url.contains("paymaster.test") {
                return try MockURLProtocol.json(["paymasterAndData": "0x" + String(repeating: "cd", count: 97)])
            }
            if (json?["method"] as? String) == "eth_sendUserOperation" {
                return try MockURLProtocol.json(["jsonrpc": "2.0", "id": 1, "result": expectedHash])
            }
            return try MockURLProtocol.json(["jsonrpc": "2.0", "id": 1, "result": [:]])
        }

        let tag = "test.rotation.\(UUID().uuidString)"
        let enclave = SecureEnclaveManager.shared
        defer { enclave.deleteKey(tag: tag) }
        let newPub = try enclave.publicKeyData(tag: tag)

        let cfg = WalletTransactionService.Config(
            rpcURL: URL(string: "https://rpc.test")!,
            bundlerURL: URL(string: "https://bundler.test")!,
            chainID: 8453,
            entryPoint: "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789",
            paymasterAddress: "0x1111111111111111111111111111111111111111",
            paymasterSignatureEndpoint: "https://paymaster.test/sign",
            platformBudgetWei: 1_000_000_000_000_000_000
        )
        let service = try XCTUnwrap(WalletTransactionService(config: cfg, session: session))

        let wallet = WalletCreation()
        let hash = try await wallet.submitGuardianRotation(
            newOwnerPublicKey: newPub,
            moduleAddress: "0x4444444444444444444444444444444444444444",
            accountAddress: "0x5555555555555555555555555555555555555555",
            signingKeyTag: tag,
            service: service
        )

        XCTAssertEqual(hash, expectedHash, "Rotation must return the bundler's submit hash (not a stub)")
        let didSubmit = MockURLProtocol.seenRequests.contains { req in
            guard req.url?.absoluteString.contains("bundler.test") == true,
                  let b = req.httpBody,
                  let j = (try? JSONSerialization.jsonObject(with: b)) as? [String: Any] else { return false }
            return (j["method"] as? String) == "eth_sendUserOperation"
        }
        XCTAssertTrue(didSubmit, "Guardian rotation must actually submit through the bundler")
    }

    // MARK: - Config keystone

    func testPendingCredentials_blankReturnsNil() {
        XCTAssertNil(PendingCredentials.filled(""))
        XCTAssertNil(PendingCredentials.filled("   "))
        XCTAssertEqual(PendingCredentials.filled("  0xabc  "), "0xabc")
    }

    // MARK: - Component money-path harness

    /// Shared harness for every component's on-chain money path. Sets up a mocked
    /// transport (paymaster SERVER + bundler), a real enclave key, and a test
    /// config, then runs `call` (the component's pipeline method) and asserts it
    /// (1) returned the bundler's hash, (2) actually submitted eth_sendUserOperation,
    /// and (3) signed with the ENCLAVE key — the signature verifies against the
    /// tag's public key, so the test FAILS if signing were bypassed, faked
    /// (zero bytes), or done with a throwaway key.
    @MainActor
    func assertComponentMoneyPath(
        expectedHash: String = "0xC0FFEE0000000000000000000000000000000000000000000000000000000abc",
        contract: String = "0x9999999999999999999999999999999999999999",
        _ call: (_ service: WalletTransactionService, _ signingKeyTag: String, _ contract: String) async throws -> WalletTransactionService.Submission
    ) async throws {
        let mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: mockConfig)
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let entryPoint = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
        MockURLProtocol.handler = { request in
            let url = request.url?.absoluteString ?? ""
            let json = request.httpBody.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            if url.contains("paymaster.test") {
                return try MockURLProtocol.json(["paymasterAndData": "0x" + String(repeating: "ab", count: 97)])
            }
            if (json?["method"] as? String) == "eth_sendUserOperation" {
                return try MockURLProtocol.json(["jsonrpc": "2.0", "id": 1, "result": expectedHash])
            }
            return try MockURLProtocol.json(["jsonrpc": "2.0", "id": 1, "result": [:]])
        }

        let tag = "test.comp.\(UUID().uuidString)"
        let enclave = SecureEnclaveManager.shared
        defer { enclave.deleteKey(tag: tag) }
        let pubRaw = try enclave.publicKeyData(tag: tag)

        let cfg = WalletTransactionService.Config(
            rpcURL: URL(string: "https://rpc.test")!,
            bundlerURL: URL(string: "https://bundler.test")!,
            chainID: 8453,
            entryPoint: entryPoint,
            paymasterAddress: "0x1111111111111111111111111111111111111111",
            paymasterSignatureEndpoint: "https://paymaster.test/sign",
            platformBudgetWei: 1_000_000_000_000_000_000
        )
        let service = try XCTUnwrap(WalletTransactionService(config: cfg, session: session))

        let submission = try await call(service, tag, contract)

        // Returned the BUNDLER's hash — not a hardcoded success.
        XCTAssertEqual(submission.userOpHash, expectedHash, "must return the bundler's submit hash")

        // Actually submitted via the bundler.
        let sawBundler = MockURLProtocol.seenRequests.contains { req in
            guard req.url?.absoluteString.contains("bundler.test") == true,
                  let b = req.httpBody,
                  let j = (try? JSONSerialization.jsonObject(with: b)) as? [String: Any] else { return false }
            return (j["method"] as? String) == "eth_sendUserOperation"
        }
        XCTAssertTrue(sawBundler, "must submit via the bundler (eth_sendUserOperation)")

        // CRITICAL: signed by the ENCLAVE key — verify against the tag's pubkey.
        let sig = submission.signedOperation.signature
        XCTAssertGreaterThan(sig.count, 0)
        XCTAssertFalse(sig.allSatisfy { $0 == 0 }, "signature must not be all-zero")
        var message = Data()
        message.append(Self.hexToData(submission.signedOperation.hash))
        message.append(ABIEncoder.encodeAddress(entryPoint))
        message.append(ABIEncoder.encodeUInt256(UInt64(8453)))
        let pub = try P256.Signing.PublicKey(rawRepresentation: pubRaw)
        let ecdsa = try P256.Signing.ECDSASignature(derRepresentation: sig)
        XCTAssertTrue(pub.isValidSignature(ecdsa, for: Keccak256.hash(data: message)),
                      "money path must be signed by the ENCLAVE key — not faked, not a throwaway")
    }

    /// A throwaway ERC4337Manager for constructing component managers in tests.
    /// Component on-chain methods route through the injected WalletTransactionService,
    /// not this manager, so its endpoints are irrelevant.
    @MainActor
    static func dummyERC4337() -> ERC4337Manager {
        let url = URL(string: "https://unused.invalid")!
        return ERC4337Manager(entryPointAddress: "", paymasterAddress: nil, bundlerURL: url,
                              networkConfig: BaseNetworkConfig(rpcURL: url, chainId: 8453, bundlerURL: url))
    }

    // MARK: - Component: NFT (Component 03)

    @MainActor
    func testNFTMint_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await NFTManager(erc4337Manager: Self.dummyERC4337()).mintOnChain(
                to: "0x2222222222222222222222222222222222222222",
                amount: 1,
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }

    // MARK: - Component: SupplyChain (Component 12)

    @MainActor
    func testSupplyChainCheckpoint_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await SupplyChainManager.shared.recordCheckpointOnChain(
                shipmentHash: Data(repeating: 0x1A, count: 32),
                dataHash: Data(repeating: 0x2B, count: 32),
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }

    // MARK: - Component: AgenticPayments (Component 10)

    @MainActor
    func testAgenticPaymentsExecute_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await AgenticPayments.executePaymentOnChain(
                recipient: "0x2222222222222222222222222222222222222222",
                token: "0x4444444444444444444444444444444444444444",
                amount: 5_000,
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }

    // MARK: - Component: AgentIdentity (Component 09)

    @MainActor
    func testAgentIdentityRegister_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await AgentIdentity.registerAgentOnChain(
                owner: "0x2222222222222222222222222222222222222222",
                agentType: .semiAutonomous,
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }

    // MARK: - Component: Stablecoin (Component 07)

    @MainActor
    func testStablecoinTransfer_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await StablecoinManager(erc4337Manager: Self.dummyERC4337()).transferOnChain(
                token: contract,
                to: "0x2222222222222222222222222222222222222222",
                amount: 1_000_000, // 1 USDC (6 decimals)
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service
            )
        }
    }

    // MARK: - Component: RWA (Component 04, securities-adjacent / self-custody)

    @MainActor
    func testRWAPurchaseShares_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await RWATokenization.purchaseSharesOnChain(
                assetId: 7,
                shares: 10,
                paymentWei: 0,
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }

    // MARK: - Component: Identity (Component 05)

    @MainActor
    func testIdentityRegisterDID_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await IdentityManager.registerDIDOnChain(
                controller: "0x2222222222222222222222222222222222222222",
                publicKey: Data(repeating: 0x04, count: 64), // P-256 pubkey shape
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }

    // MARK: - Component: ContractConversion (Component 01)

    @MainActor
    func testContractConversionDeploy_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await ContractConversion(erc4337Manager: Self.dummyERC4337()).deployOnChain(
                salt: Data(repeating: 0x01, count: 32),
                bytecode: Data([0x60, 0x80, 0x60, 0x40]), // sample creation code
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }

    // MARK: - Component: DAO (Component 06)

    @MainActor
    func testDAOCastVote_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await DAOManager(erc4337Manager: Self.dummyERC4337()).castVoteOnChain(
                proposalId: 42,
                support: .forProposal,
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }

    // MARK: - Component: Attestation (Component 08)

    @MainActor
    func testAttestation_submitsThroughPipeline() async throws {
        try await assertComponentMoneyPath { service, tag, contract in
            try await AttestationComponent.createAttestationOnChain(
                schemaUID: Data(repeating: 0xAB, count: 32),
                recipient: "0x2222222222222222222222222222222222222222",
                data: Data("claim:verified".utf8),
                sender: "0x3333333333333333333333333333333333333333",
                signingKeyTag: tag,
                service: service,
                contract: contract
            )
        }
    }
}
