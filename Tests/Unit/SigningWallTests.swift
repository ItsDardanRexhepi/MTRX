import CryptoKit
import XCTest
@testable import MTRX

/// The testnet-only signing wall, proven to enforce INDEPENDENTLY of the Morpheus
/// advisor. This file references ZERO Core/Morpheus symbols — it imports nothing
/// from the advisor and reads no advisor state. Deleting all of Core/Morpheus (the
/// persona, the read-only `MorpheusSecurityState` layer, everything) leaves this
/// test passing unchanged: the wall lives in the signing primitive, not in any
/// agent. This is the first deterministic test of the headline wall (mainnet
/// signing refused, fail-closed, before any signature), per MORPHEUS_ADVISOR_SPEC §7.
final class SigningWallTests: XCTestCase {

    private func sampleOperation() -> UserOperation {
        UserOperation(
            sender: "0x000000000000000000000000000000000000dEaD",
            nonce: 0,
            initCode: Data(),
            callData: Data([0x01, 0x02, 0x03]),
            callGasLimit: 100_000,
            verificationGasLimit: 100_000,
            preVerificationGas: 21_000,
            maxFeePerGas: 1_000_000,
            maxPriorityFeePerGas: 1_000_000,
            paymasterAndData: Data(),
            signature: Data()
        )
    }

    /// Mainnet (chainId 8453) signing is REFUSED, fail-closed, even with a valid
    /// enclave key configured — the chain lock fires before the enclave is touched.
    func testMainnetSigning_isRefusedFailClosed_evenWithValidKey() throws {
        let tag = "test.wall.\(UUID().uuidString)"
        let mgr = SecureEnclaveManager.shared
        defer { mgr.deleteKey(tag: tag) }
        _ = try mgr.publicKeyData(tag: tag)   // create a real, usable signing key

        let url = URL(string: "https://unused.invalid")!
        // Base mainnet — the explicitly forbidden chain.
        let cfg = BaseNetworkConfig(rpcURL: url, chainId: BaseNetworkConfig.baseMainnetChainID, bundlerURL: url)
        XCTAssertEqual(cfg.chainId, 8_453)
        XCTAssertFalse(cfg.isSigningPermitted, "Mainnet must never be a permitted signing chain")

        let manager = ERC4337Manager(entryPointAddress: "", paymasterAddress: nil, bundlerURL: url, networkConfig: cfg)
        manager.configureSigningKey(tag: tag)

        let exp = expectation(description: "mainnet sign refused")
        var refusedChain: UInt64?
        manager.signOperation(sampleOperation()) { result in
            if case .failure(.signingChainNotPermitted(let id)) = result { refusedChain = id }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(refusedChain, 8_453,
                       "Mainnet signing must fail closed with signingChainNotPermitted — nothing signed")
    }

    /// Positive control: the SAME key + op on the permitted testnet chain is NOT
    /// blocked by the chain lock (it passes the lock and actually signs).
    func testTestnetSigning_passesTheChainLock() throws {
        let tag = "test.wall.\(UUID().uuidString)"
        let mgr = SecureEnclaveManager.shared
        defer { mgr.deleteKey(tag: tag) }
        _ = try mgr.publicKeyData(tag: tag)

        let url = URL(string: "https://unused.invalid")!
        let cfg = BaseNetworkConfig(rpcURL: url, chainId: BaseNetworkConfig.permittedSigningChainID, bundlerURL: url)
        let manager = ERC4337Manager(entryPointAddress: "", paymasterAddress: nil, bundlerURL: url, networkConfig: cfg)
        manager.configureSigningKey(tag: tag)

        let exp = expectation(description: "testnet sign")
        var chainBlocked = false
        var signed = false
        manager.signOperation(sampleOperation()) { result in
            switch result {
            case .failure(.signingChainNotPermitted): chainBlocked = true
            case .success: signed = true
            default: break
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertFalse(chainBlocked, "Permitted testnet chain must pass the signing chain lock")
        XCTAssertTrue(signed, "On the permitted chain with a configured key, signing proceeds")
    }
}
