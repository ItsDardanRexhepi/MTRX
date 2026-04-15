import Foundation

// MARK: - Models

struct DecentralizedFile: Codable, Identifiable {
    var id: String { cid }
    let cid: String
    let filename: String
    let mimeType: String
    let size: Int64
    let uploadedAt: Date
    let layer: String
    let isPinned: Bool
    let pinnedUntil: Date?
    let url: String?
}

// MARK: - Service

@MainActor
final class StorageService {

    static let shared = StorageService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getUserFiles(address: String) async throws -> [DecentralizedFile] {
        try await api.get("/storage/files", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func uploadFile(data: Data, filename: String, mimeType: String, layer: String, pinDays: Int?) async throws -> DecentralizedFile {
        struct UploadBody: Codable {
            let dataBase64: String
            let filename: String
            let mimeType: String
            let layer: String
            let pinDays: Int?
        }
        let body = UploadBody(
            dataBase64: data.base64EncodedString(),
            filename: filename,
            mimeType: mimeType,
            layer: layer,
            pinDays: pinDays
        )
        return try await api.post("/storage/files", body: body)
    }

    func getFile(cid: String) async throws -> DecentralizedFile {
        try await api.get("/storage/files/\(cid)")
    }

    func pinFile(cid: String, days: Int) async throws -> TransactionResult {
        try await api.post("/storage/files/\(cid)/pin", body: ["days": String(days)])
    }

    func unpinFile(cid: String) async throws -> TransactionResult {
        try await api.post("/storage/files/\(cid)/unpin", body: nil as String?)
    }
}
