import Foundation

// MARK: - Models

struct PaymentStream: Codable, Identifiable {
    var id: String { streamId }
    let streamId: String
    let sender: String
    let recipient: String
    let token: String
    let flowRatePerSecond: Double
    let startTime: Date
    let endTime: Date?
    let claimableBalance: Double
    let status: String
}

// MARK: - Service

@MainActor
final class StreamingService {

    static let shared = StreamingService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func createStream(recipient: String, token: String, flowRate: String, duration: Int) async throws -> TransactionResult {
        try await api.post("/streaming/streams", body: [
            "recipient": recipient,
            "token": token,
            "flowRate": flowRate,
            "duration": String(duration)
        ])
    }

    func getOutgoingStreams(address: String) async throws -> [PaymentStream] {
        try await api.get("/streaming/streams/outgoing", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getIncomingStreams(address: String) async throws -> [PaymentStream] {
        try await api.get("/streaming/streams/incoming", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func claimStreamBalance(streamId: String) async throws -> TransactionResult {
        try await api.post("/streaming/streams/\(streamId)/claim", body: nil as String?)
    }

    func cancelStream(streamId: String) async throws -> TransactionResult {
        try await api.post("/streaming/streams/\(streamId)/cancel", body: nil as String?)
    }
}
