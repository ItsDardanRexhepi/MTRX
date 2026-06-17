//
//  DemoArtifacts.swift
//  MTRX
//
//  Honest stand-ins for demo/preview screens that have no live chain configured.
//
//  Instead of (a) hardcoding a REAL third-party contract address (e.g. the
//  Uniswap router) or (b) minting a random UUID dressed up as an address/hash,
//  these produce DETERMINISTIC, content-derived values via keccak256. They are:
//   • reproducible from their seed (same input → same output),
//   • provably NOT a real deployed contract or a confirmed transaction,
//   • clearly labelled at the call site as simulated/demo.
//  They exist only so demo flows render something coherent until PendingCredentials
//  is filled and the real on-chain pipeline runs.
//
import Foundation

/// The signed-in user's wallet address, as persisted by AppState.signIn under
/// `com.mtrx.walletAddress`. `nil` until a real sign-in writes one — so live
/// service calls that need an address fall back to demo data rather than
/// querying a placeholder.
enum MtrxSession {
    static var walletAddress: String? {
        let value = UserDefaults.standard.string(forKey: "com.mtrx.walletAddress")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}

enum DemoArtifacts {

    /// A deterministic, content-derived 20-byte address for a demo/preview screen.
    /// Derived from `seed` so it's reproducible and never a real third-party contract.
    static func address(seed: String) -> String {
        let digest = Keccak256.hash(data: Data(seed.utf8))
        return "0x" + digest.suffix(20).map { String(format: "%02x", $0) }.joined()
    }

    /// A deterministic, content-derived 32-byte hash for a demo/preview artifact
    /// (e.g. a simulated tx hash / content id). NOT a confirmed transaction.
    static func hash(seed: String) -> String {
        let digest = Keccak256.hash(data: Data(seed.utf8))
        return "0x" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
