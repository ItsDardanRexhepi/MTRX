import Foundation

// MARK: - Models

struct SvcMultiSigWallet: Codable, Identifiable {
    var id: String { walletId }
    let walletId: String
    let name: String
    let address: String
    let threshold: Int
    let signers: [String]
    let balance: Double
}

private struct CreateMultiSigBody: Codable {
    let name: String
    let signers: [String]
    let threshold: Int
}

struct MultiSigTransaction: Codable, Identifiable {
    var id: String { txId }
    let txId: String
    let to: String
    let value: Double
    let data: String?
    let signatures: [String]
    let status: String
    let proposedAt: Date
}

// MARK: - Service

@MainActor
final class MultiSigService {

    static let shared = MultiSigService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getUserMultiSigs(address: String) async throws -> [SvcMultiSigWallet] {
        try await api.get(path: "/multisig/wallets", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getPendingTransactions(multiSigId: String) async throws -> [MultiSigTransaction] {
        try await api.get(path: "/multisig/wallets/\(multiSigId)/transactions", queryItems: [
            URLQueryItem(name: "status", value: "pending")
        ])
    }

    func approveTransaction(multiSigId: String, txId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/multisig/wallets/\(multiSigId)/transactions/\(txId)/approve", body: nil as String?)
    }

    func rejectTransaction(multiSigId: String, txId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/multisig/wallets/\(multiSigId)/transactions/\(txId)/reject", body: nil as String?)
    }

    func createMultiSig(name: String, signers: [String], threshold: Int) async throws -> SvcMultiSigWallet {
        let body = CreateMultiSigBody(name: name, signers: signers, threshold: threshold)
        return try await api.post(path: "/multisig/wallets", body: body)
    }

    func proposeTransaction(multiSigId: String, to: String, amount: String, data: String?) async throws -> MultiSigTransaction {
        var body: [String: String] = [
            "to": to,
            "amount": amount
        ]
        if let data { body["data"] = data }
        return try await api.post(path: "/multisig/wallets/\(multiSigId)/transactions", body: body)
    }
}
