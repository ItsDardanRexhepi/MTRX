import Foundation

// MARK: - Models

struct MusicTrack: Codable, Identifiable {
    var id: String { trackId }
    let trackId: String
    let title: String
    let artist: String
    let artworkURL: String?
    let audioURL: String?
    let pricePerPlay: Double
    let splits: [RoyaltySplit]
    let totalPlays: Int
    let totalEarnings: Double
}

struct RoyaltySplit: Codable, Identifiable {
    let id: UUID
    let address: String
    let ens: String?
    let percent: Double
    let role: String
}

struct MusicMetadata: Codable {
    let title: String
    let description: String?
    let splits: [RoyaltySplit]
    let pricePerPlay: Double
}

struct PlaySession: Codable {
    let sessionId: String
    let trackId: String
    let cost: Double
}

// MARK: - Service

@MainActor
final class MusicService {

    static let shared = MusicService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getCatalog() async throws -> [MusicTrack] {
        try await api.get("/music/catalog")
    }

    func uploadTrack(audioData: Data, artwork: Data, metadata: MusicMetadata) async throws -> MusicTrack {
        struct UploadBody: Codable {
            let audioBase64: String
            let artworkBase64: String
            let metadata: MusicMetadata
        }
        let body = UploadBody(
            audioBase64: audioData.base64EncodedString(),
            artworkBase64: artwork.base64EncodedString(),
            metadata: metadata
        )
        return try await api.post("/music/tracks", body: body)
    }

    func playTrack(trackId: String) async throws -> PlaySession {
        try await api.post("/music/tracks/\(trackId)/play", body: nil as String?)
    }

    func getUserTracks(address: String) async throws -> [MusicTrack] {
        try await api.get("/music/tracks", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func claimEarnings(trackId: String) async throws -> TransactionResult {
        try await api.post("/music/tracks/\(trackId)/claim", body: nil as String?)
    }

    func getRoyaltySplits(trackId: String) async throws -> [RoyaltySplit] {
        try await api.get("/music/tracks/\(trackId)/splits")
    }
}
