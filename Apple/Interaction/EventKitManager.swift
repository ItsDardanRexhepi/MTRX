// EventKitManager.swift
// MTRX Apple Integration — Interaction
//
// Native calendar integration for contract deadlines, governance votes, payments

import EventKit
import Foundation

// MARK: - EventKitManager

final class EventKitManager: ObservableObject {

    static let shared = EventKitManager()

    @Published private(set) var isAuthorized: Bool = false

    private let eventStore = EKEventStore()

    // MARK: - Authorization

    func requestAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToEvents()
        await MainActor.run { isAuthorized = granted }
        return granted
    }

    // MARK: - Contract Events

    func addContractDeadline(title: String, contractId: String, deadline: Date, notes: String? = nil) throws -> String {
        guard isAuthorized else { throw EventKitError.notAuthorized }

        let event = EKEvent(eventStore: eventStore)
        event.title = "MTRX: \(title)"
        event.startDate = deadline
        event.endDate = deadline.addingTimeInterval(3600)
        event.notes = notes ?? "Contract ID: \(contractId)"
        event.calendar = eventStore.defaultCalendarForNewEvents

        let alarm = EKAlarm(relativeOffset: -3600) // 1 hour before
        event.addAlarm(alarm)

        let dayBeforeAlarm = EKAlarm(relativeOffset: -86400) // 1 day before
        event.addAlarm(dayBeforeAlarm)

        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    // MARK: - Governance Events

    func addGovernanceVoteDeadline(proposalTitle: String, proposalId: String, deadline: Date) throws -> String {
        guard isAuthorized else { throw EventKitError.notAuthorized }

        let event = EKEvent(eventStore: eventStore)
        event.title = "MTRX Vote: \(proposalTitle)"
        event.startDate = deadline.addingTimeInterval(-7200) // 2 hours before deadline
        event.endDate = deadline
        event.notes = "Proposal ID: \(proposalId)\nVote before this deadline."
        event.calendar = eventStore.defaultCalendarForNewEvents

        let alarm = EKAlarm(relativeOffset: -3600)
        event.addAlarm(alarm)

        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    // MARK: - Payment Events

    func addPaymentReminder(description: String, amount: String, dueDate: Date) throws -> String {
        guard isAuthorized else { throw EventKitError.notAuthorized }

        let event = EKEvent(eventStore: eventStore)
        event.title = "MTRX Payment: \(amount)"
        event.startDate = dueDate
        event.endDate = dueDate.addingTimeInterval(1800)
        event.notes = description
        event.calendar = eventStore.defaultCalendarForNewEvents

        let alarm = EKAlarm(relativeOffset: -86400)
        event.addAlarm(alarm)

        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    // MARK: - Recurring Events

    func addRecurringPayment(title: String, amount: String, startDate: Date, interval: EKRecurrenceFrequency) throws -> String {
        guard isAuthorized else { throw EventKitError.notAuthorized }

        let event = EKEvent(eventStore: eventStore)
        event.title = "MTRX Recurring: \(title) - \(amount)"
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(1800)
        event.calendar = eventStore.defaultCalendarForNewEvents

        let rule = EKRecurrenceRule(recurrenceWith: interval, interval: 1, end: nil)
        event.addRecurrenceRule(rule)

        try eventStore.save(event, span: .futureEvents)
        return event.eventIdentifier
    }

    // MARK: - Remove

    func removeEvent(identifier: String) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw EventKitError.eventNotFound
        }
        try eventStore.remove(event, span: .thisEvent)
    }

    // MARK: - Query

    func getUpcomingMTRXEvents(days: Int = 30) -> [EKEvent] {
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)!
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate).filter { $0.title.hasPrefix("MTRX") }
    }
}

// MARK: - EventKitError

enum EventKitError: LocalizedError {
    case notAuthorized
    case eventNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Calendar access not authorized."
        case .eventNotFound: return "Calendar event not found."
        case .saveFailed(let r): return "Failed to save event: \(r)"
        }
    }
}
