import Foundation

// MARK: - Models

struct SvcMusicTrack: Codable, Identifiable {
    var id: String { trackId }
    let trackId: String
    let title: String
    let artist: String
    let artworkURL: String?
    let audioURL: String?
    let pricePerPlay: Double
    let splits: [SvcRoyaltySplit]
    let totalPlays: Int
    let totalEarnings: Double
}

struct SvcRoyaltySplit: Codable, Identifiable {
    let id: UUID
    let address: String
    let ens: String?
    let percent: Double
    let role: String
}

struct MusicMetadata: Codable {
    let title: String
    let description: String?
    let splits: [SvcRoyaltySplit]
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

    func getCatalog() async throws -> [SvcMusicTrack] {
        try await api.get(path: "/music/catalog")
    }

    func uploadTrack(audioData: Data, artwork: Data, metadata: MusicMetadata) async throws -> SvcMusicTrack {
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
        return try await api.post(path: "/music/tracks", body: body)
    }

    func playTrack(trackId: String) async throws -> PlaySession {
        try await api.post(path: "/music/tracks/\(trackId)/play", body: nil as String?)
    }

    func getUserTracks(address: String) async throws -> [SvcMusicTrack] {
        try await api.get(path: "/music/tracks", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func claimEarnings(trackId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/music/tracks/\(trackId)/claim", body: nil as String?)
    }

    func getRoyaltySplits(trackId: String) async throws -> [SvcRoyaltySplit] {
        try await api.get(path: "/music/tracks/\(trackId)/splits")
    }
}
