import Foundation

// MARK: - Models

struct OnChainEvent: Codable, Identifiable {
    var id: String { eventId }
    let eventId: String
    let title: String
    let description: String
    let organizer: String
    let date: Date
    let location: String
    let ticketPrice: Double
    let totalSupply: Int
    let remaining: Int
    let artworkURL: String?
}

struct EventTicket: Codable, Identifiable {
    var id: String { ticketId }
    let ticketId: String
    let eventId: String
    let eventTitle: String
    let eventDate: Date
    let holderAddress: String
    let qrCodeData: String?
    let used: Bool
}

struct EventParams: Codable {
    let title: String
    let description: String
    let date: Date
    let location: String
    let ticketPrice: Double
    let totalSupply: Int
}

struct TicketVerificationResult: Codable {
    let isValid: Bool
    let eventTitle: String?
    let holderAddress: String?
    let used: Bool
}

// MARK: - Service

@MainActor
final class EventsService {

    static let shared = EventsService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getEvents() async throws -> [OnChainEvent] {
        try await api.get("/events")
    }

    func getUserTickets(address: String) async throws -> [EventTicket] {
        try await api.get("/events/tickets", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func createEvent(params: EventParams) async throws -> OnChainEvent {
        try await api.post("/events", body: params)
    }

    func purchaseTicket(eventId: String) async throws -> EventTicket {
        try await api.post("/events/\(eventId)/purchase", body: nil as String?)
    }

    func verifyTicket(ticketId: String) async throws -> TicketVerificationResult {
        try await api.get("/events/tickets/\(ticketId)/verify")
    }
}
