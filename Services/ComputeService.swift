import Foundation

// MARK: - Models

struct ComputeProvider: Codable, Identifiable {
    var id: String { providerId }
    let providerId: String
    let name: String
    let gpuType: String
    let pricePerHour: Double
    let availability: String
    let rating: Double
}

struct ComputeJob: Codable, Identifiable {
    var id: String { jobId }
    let jobId: String
    let type: String
    let status: String
    let provider: String
    let cost: Double
    let submittedAt: Date
    let completedAt: Date?
    let resultCID: String?
}

// MARK: - Service

@MainActor
final class ComputeService {

    static let shared = ComputeService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getComputeProviders() async throws -> [ComputeProvider] {
        try await api.get("/compute/providers")
    }

    func submitJob(type: String, inputs: Data, providerId: String, budget: String) async throws -> ComputeJob {
        struct SubmitBody: Codable {
            let type: String
            let inputsBase64: String
            let providerId: String
            let budget: String
        }
        let body = SubmitBody(
            type: type,
            inputsBase64: inputs.base64EncodedString(),
            providerId: providerId,
            budget: budget
        )
        return try await api.post("/compute/jobs", body: body)
    }

    func getUserJobs(address: String) async throws -> [ComputeJob] {
        try await api.get("/compute/jobs", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getJobStatus(jobId: String) async throws -> ComputeJob {
        try await api.get("/compute/jobs/\(jobId)")
    }

    func downloadResult(jobId: String) async throws -> Data {
        let result: [String: String] = try await api.get("/compute/jobs/\(jobId)/result")
        guard let base64 = result["data"],
              let data = Data(base64Encoded: base64) else {
            throw MTRXAPIError.decodingFailed("Failed to decode compute result data")
        }
        return data
    }
}
