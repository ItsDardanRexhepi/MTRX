// WalletTransactionService.swift
// MTRX Blockchain - Wallet
//
// The submit pipeline keystone. Threads the real Phase 1-4 layers for a single
// account call:
//
//   ABI-encode execute(target,value,data)         (ERC4337Manager)
//     → fetch verifying-paymaster data from server (GasSponsorship — key on server)
//     → sign the UserOperation with the Secure Enclave key  (ERC4337Manager #54)
//     → submit to the bundler                       (ERC4337Manager)
//
// Every external value is read from PendingCredentials (or injected for tests);
// nothing is hardcoded, and no private key ever lives in the app — the wallet
// signature comes from the enclave, the paymaster signature from the server.

import Foundation

@MainActor
final class WalletTransactionService {

    /// Everything the pipeline needs. Defaults read from PendingCredentials;
    /// tests inject explicit values + a mocked URLSession.
    struct Config {
        let rpcURL: URL
        let bundlerURL: URL
        let chainID: Int
        let entryPoint: String
        let paymasterAddress: String
        let paymasterSignatureEndpoint: String
        let platformBudgetWei: UInt64

        /// Build from PendingCredentials; `nil` until the chain core is configured
        /// (rpc + chainID + entryPoint + factory) — callers then no-op safely.
        static func fromPendingCredentials() -> Config? {
            guard PendingCredentials.isChainConfigured,
                  let rpc = PendingCredentials.filled(PendingCredentials.Network.rpcURL).flatMap({ URL(string: $0) }),
                  let bundler = PendingCredentials.filled(PendingCredentials.AccountAbstraction.bundlerURL).flatMap({ URL(string: $0) })
            else { return nil }
            return Config(
                rpcURL: rpc,
                bundlerURL: bundler,
                chainID: PendingCredentials.Network.chainID,
                entryPoint: PendingCredentials.AccountAbstraction.entryPointAddress,
                paymasterAddress: PendingCredentials.AccountAbstraction.paymasterAddress,
                paymasterSignatureEndpoint: PendingCredentials.AccountAbstraction.paymasterSignatureEndpoint,
                platformBudgetWei: 1_000_000_000_000_000_000 // 1 ETH default platform budget
            )
        }
    }

    enum TxError: Error, LocalizedError {
        case notConfigured
        case buildFailed(String)
        case submitFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "On-chain config not set — fill PendingCredentials."
            case .buildFailed(let r): return "Failed to build operation: \(r)"
            case .submitFailed(let r): return "Bundler submit failed: \(r)"
            }
        }
    }

    /// Result of a submitted call: the bundler's userOp hash + the signed op.
    struct Submission {
        let userOpHash: String
        let signedOperation: UserOperation
    }

    private let config: Config
    private let session: URLSession

    /// Production: reads PendingCredentials (returns nil until configured).
    /// Tests: inject `config` + a MockURLProtocol `session`.
    init?(config: Config? = Config.fromPendingCredentials(), session: URLSession = .shared) {
        guard let config = config else { return nil }
        self.config = config
        self.session = session
    }

    /// Build → server-sponsor → enclave-sign → bundler-submit a single call to
    /// `target`. `signingKeyTag` is the user's Secure Enclave key tag (e.g.
    /// WalletCore's "wallet.<appleUserId>"). Returns the bundler's userOp hash.
    ///
    /// P-256/RIP-7212 CONSTRAINT: the on-chain account must verify P-256
    /// signatures — the enclave (and therefore this pipeline) signs P-256.
    @discardableResult
    func submitCall(
        to target: String,
        value: UInt64 = 0,
        data: Data,
        sender: String,
        signingKeyTag: String,
        userTier: UserTier = .free
    ) async throws -> Submission {
        let networkConfig = BaseNetworkConfig(
            rpcURL: config.rpcURL,
            chainId: UInt64(config.chainID),
            bundlerURL: config.bundlerURL
        )
        let manager = ERC4337Manager(
            entryPointAddress: config.entryPoint,
            paymasterAddress: config.paymasterAddress.isEmpty ? nil : config.paymasterAddress,
            bundlerURL: config.bundlerURL,
            networkConfig: networkConfig,
            session: session
        )
        manager.setAccountAddress(sender)
        manager.configureSigningKey(tag: signingKeyTag)

        let sponsorship = GasSponsorship(
            paymasterAddress: config.paymasterAddress,
            platformBudgetWei: config.platformBudgetWei,
            paymasterSignatureEndpoint: config.paymasterSignatureEndpoint,
            entryPoint: config.entryPoint,
            chainID: config.chainID,
            session: session
        )

        // 1. Build the unsigned op (real ABI-encoded execute calldata).
        let op: UserOperation
        switch manager.buildUserOperation(to: target, value: value, data: data) {
        case .success(let built): op = built
        case .failure(let error): throw TxError.buildFailed(error.localizedDescription)
        }

        // 2. Fetch verifying-paymaster data from the SERVER (key never in app).
        //    If the policy/budget declines or the server is unreachable, proceed
        //    UNSPONSORED — we never fabricate paymaster data.
        let sponsoredOp = (try? await sponsorship.sponsoredOperation(op, userAddress: sender, userTier: userTier)) ?? op

        // 3. Sign with the user's Secure Enclave key (over the hash that now
        //    includes paymasterAndData). NEVER a throwaway key (see #54).
        let signedOp = try await signed(manager, sponsoredOp)

        // 4. Submit the signed op to the bundler.
        let hash = try await submitted(manager, signedOp)
        return Submission(userOpHash: hash, signedOperation: signedOp)
    }

    // MARK: - Continuation bridges to the completion-based ERC4337Manager

    private func signed(_ manager: ERC4337Manager, _ op: UserOperation) async throws -> UserOperation {
        try await withCheckedThrowingContinuation { continuation in
            manager.signOperation(op) { result in
                switch result {
                case .success(let signed): continuation.resume(returning: signed)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    private func submitted(_ manager: ERC4337Manager, _ op: UserOperation) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            manager.submitOperation(op) { result in
                switch result {
                case .success(let hash): continuation.resume(returning: hash)
                case .failure(let error): continuation.resume(throwing: TxError.submitFailed(error.localizedDescription))
                }
            }
        }
    }
}
