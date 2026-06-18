// EventKitManager.swift
// MTRX Apple Integration — Interaction
//
// Native Calendar + Reminders via EventKit, scoped to MTRX's OWN dedicated
// "MTRX" calendar and "MTRX" reminder list. The app only ever reads and writes
// those two — it never enumerates or displays the user's personal calendars.
//
// Privacy note: EventKit grants access per data-type, not per-calendar, so even
// showing MTRX's own items requires Calendar / Reminders authorization. We keep
// the footprint minimal by touching only the dedicated MTRX containers. Calendar
// and Reminders are SEPARATE authorizations on current iOS and are requested
// independently. No data is ever fabricated — empty means honestly empty.

import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class EventKitManager {

    static let shared = EventKitManager()

    private(set) var calendarStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var reminderStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    var isWorking = false

    private let eventStore = EKEventStore()
    private let mtrxTitle = "MTRX"
    private let eventCalKey = "mtrx.eventCalendarID"
    private let reminderListKey = "mtrx.reminderListID"

    private let personalSyncKey = "mtrx.personalSync"

    /// Personal-calendar sync — the USER's explicit, opt-in choice. When ON,
    /// MTRX also READS the user's personal calendars/reminders and lets events be
    /// created in them. Default OFF: MTRX touches ONLY its own dedicated
    /// containers and never reads personal data. Persisted.
    var personalSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(personalSyncEnabled, forKey: personalSyncKey) }
    }

    private init() {
        personalSyncEnabled = UserDefaults.standard.bool(forKey: personalSyncKey)   // default false
        refreshStatus()
    }

    // MARK: - Authorization (honest states)

    func refreshStatus() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    var calendarGranted: Bool { calendarStatus == .fullAccess }
    var calendarDenied: Bool { calendarStatus == .denied || calendarStatus == .restricted }
    /// "Add Only" access: can write but not read, so we can't show the schedule.
    var calendarWriteOnly: Bool { calendarStatus == .writeOnly }
    var reminderGranted: Bool { reminderStatus == .fullAccess }
    var reminderDenied: Bool { reminderStatus == .denied || reminderStatus == .restricted }

    func requestCalendarAccess() async {
        isWorking = true; defer { isWorking = false }
        _ = try? await eventStore.requestFullAccessToEvents()
        refreshStatus()
    }

    func requestReminderAccess() async {
        isWorking = true; defer { isWorking = false }
        _ = try? await eventStore.requestFullAccessToReminders()
        refreshStatus()
    }

    // MARK: - Dedicated MTRX containers

    /// The MTRX-only event calendar (found by saved id, then by title, else
    /// created). All MTRX events live here — never the user's default calendar.
    private func mtrxEventCalendar() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: eventCalKey),
           let cal = eventStore.calendar(withIdentifier: id) { return cal }
        // Create our OWN calendar. We deliberately do NOT adopt an existing
        // calendar that merely shares the "MTRX" title — that could be one the
        // user created, and reading/writing it would touch their personal data.
        // A lost saved id (rare) just creates a fresh container.
        let cal = EKCalendar(for: .event, eventStore: eventStore)
        cal.title = mtrxTitle
        guard let source = eventStore.defaultCalendarForNewEvents?.source
                ?? eventStore.sources.first(where: { $0.sourceType == .local })
                ?? eventStore.sources.first else {
            throw EventKitError.noSource
        }
        cal.source = source
        try eventStore.saveCalendar(cal, commit: true)
        UserDefaults.standard.set(cal.calendarIdentifier, forKey: eventCalKey)
        return cal
    }

    /// The MTRX-only reminder list (found by saved id, then by title, else created).
    private func mtrxReminderList() throws -> EKCalendar {
        if let id = UserDefaults.standard.string(forKey: reminderListKey),
           let cal = eventStore.calendar(withIdentifier: id) { return cal }
        // Create our OWN list — never adopt a user list that happens to be
        // titled "MTRX" (that would touch their personal reminders).
        let cal = EKCalendar(for: .reminder, eventStore: eventStore)
        cal.title = mtrxTitle
        guard let source = eventStore.defaultCalendarForNewReminders()?.source
                ?? eventStore.sources.first(where: { $0.sourceType == .local })
                ?? eventStore.sources.first else {
            throw EventKitError.noSource
        }
        cal.source = source
        try eventStore.saveCalendar(cal, commit: true)
        UserDefaults.standard.set(cal.calendarIdentifier, forKey: reminderListKey)
        return cal
    }

    // MARK: - Reads (scoped to the MTRX containers only)

    /// Upcoming MTRX events from the dedicated calendar only.
    func upcomingMTRXEvents(days: Int = 30) -> [EKEvent] {
        guard calendarGranted, let cal = try? mtrxEventCalendar() else { return [] }
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: [cal])
        return eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    /// MTRX reminders (the checklist) from the dedicated list only.
    func fetchMTRXReminders() async -> [EKReminder] {
        guard reminderGranted, let list = try? mtrxReminderList() else { return [] }
        let predicate = eventStore.predicateForReminders(in: [list])
        return await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
    }

    // MARK: - Writes (MTRX containers only)

    /// Add a user-created reminder to the MTRX checklist.
    @discardableResult
    func addReminder(title: String, due: Date? = nil, notes: String? = nil) throws -> String {
        guard reminderGranted else { throw EventKitError.notAuthorized }
        let list = try mtrxReminderList()
        let r = EKReminder(eventStore: eventStore)
        r.title = title
        r.notes = notes
        r.calendar = list
        if let due {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        try eventStore.save(r, commit: true)
        return r.calendarItemIdentifier
    }

    func setReminderCompleted(_ reminder: EKReminder, completed: Bool) throws {
        reminder.isCompleted = completed
        try eventStore.save(reminder, commit: true)
    }

    /// Log a completed MTRX activity item (real in-app action → checklist entry).
    /// Best-effort; silently no-ops if reminders aren't authorized.
    func logActivity(title: String, notes: String? = nil) {
        guard reminderGranted, let list = try? mtrxReminderList() else { return }
        let r = EKReminder(eventStore: eventStore)
        r.title = title
        r.notes = notes
        r.calendar = list
        r.isCompleted = true
        r.completionDate = Date()
        try? eventStore.save(r, commit: true)
    }

    /// Schedule an upcoming MTRX event (e.g. a contract deadline) in the MTRX
    /// calendar, with reminders. Used by app activity, not personal calendar.
    @discardableResult
    func addUpcomingEvent(title: String, at date: Date, notes: String? = nil) throws -> String {
        guard calendarGranted else { throw EventKitError.notAuthorized }
        let event = EKEvent(eventStore: eventStore)
        event.title = "MTRX: \(title)"
        event.startDate = date
        event.endDate = date.addingTimeInterval(3600)
        event.notes = notes
        event.calendar = try mtrxEventCalendar()
        event.addAlarm(EKAlarm(relativeOffset: -3600))
        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    func removeEvent(identifier: String) throws {
        guard let event = eventStore.event(withIdentifier: identifier) else {
            throw EventKitError.eventNotFound
        }
        try eventStore.remove(event, span: .thisEvent)
    }

    // MARK: - Interactive calendar: scoped reads
    //
    // The read scope is MTRX-only unless the user has explicitly opted into
    // personal sync. On failure to resolve the MTRX container while sync is OFF
    // we read NOTHING (never silently fall back to all calendars).

    private enum ReadScope { case all, only([EKCalendar]), none }

    private func eventReadScope() -> ReadScope {
        if personalSyncEnabled { return .all }
        guard let cal = try? mtrxEventCalendar() else { return .none }
        return .only([cal])
    }

    private func reminderReadScope() -> ReadScope {
        if personalSyncEnabled { return .all }
        guard let list = try? mtrxReminderList() else { return .none }
        return .only([list])
    }

    /// Events on a specific day.
    func events(on day: Date) -> [EKEvent] {
        guard calendarGranted else { return [] }
        let calendars: [EKCalendar]?
        switch eventReadScope() {
        case .all: calendars = nil
        case .only(let c): calendars = c
        case .none: return []
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    /// Start-of-day dates in the given month that have at least one event (for
    /// the grid's day markers).
    func eventDays(inMonthOf date: Date) -> Set<Date> {
        guard calendarGranted else { return [] }
        let calendars: [EKCalendar]?
        switch eventReadScope() {
        case .all: calendars = nil
        case .only(let c): calendars = c
        case .none: return []
        }
        let cal = Calendar.current
        guard let month = cal.dateInterval(of: .month, for: date) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: month.start, end: month.end, calendars: calendars)
        var days = Set<Date>()
        for e in eventStore.events(matching: predicate) {
            // Mark every day a (possibly multi-day) event spans, clamped to the
            // visible month, so the dot matches what events(on:) returns per day.
            var d = max(cal.startOfDay(for: e.startDate), month.start)
            let last = min(cal.startOfDay(for: e.endDate), month.end)
            while d <= last {
                days.insert(d)
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
        return days
    }

    /// Reminders due on a specific day.
    func reminders(on day: Date) async -> [EKReminder] {
        guard reminderGranted else { return [] }
        let lists: [EKCalendar]?
        switch reminderReadScope() {
        case .all: lists = nil
        case .only(let c): lists = c
        case .none: return []
        }
        let predicate = eventStore.predicateForReminders(in: lists)
        let all = await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        let cal = Calendar.current
        return all.filter { r in
            guard let comps = r.dueDateComponents, let due = cal.date(from: comps) else { return false }
            return cal.isDate(due, inSameDayAs: day)
        }
    }

    // MARK: - Interactive calendar: event + reminder CRUD

    /// Writable calendars offered in the event editor's picker: MTRX first, plus
    /// the user's other writable calendars only when personal sync is opted in.
    func writableEventCalendars() -> [EKCalendar] {
        guard calendarGranted, let mtrx = try? mtrxEventCalendar() else { return [] }
        guard personalSyncEnabled else { return [mtrx] }
        let others = eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications && $0.calendarIdentifier != mtrx.calendarIdentifier }
            .sorted { $0.title < $1.title }
        return [mtrx] + others
    }

    func mtrxCalendarID() -> String? { try? mtrxEventCalendar().calendarIdentifier }

    @discardableResult
    func createEvent(title: String, start: Date, end: Date, notes: String?, in calendar: EKCalendar? = nil) throws -> String {
        guard calendarGranted else { throw EventKitError.notAuthorized }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = max(end, start)
        event.notes = notes
        event.calendar = try (calendar ?? mtrxEventCalendar())
        event.addAlarm(EKAlarm(relativeOffset: -3600))
        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    func updateEvent(_ event: EKEvent, title: String, start: Date, end: Date, notes: String?, calendar: EKCalendar?) throws {
        event.title = title
        event.startDate = start
        event.endDate = max(end, start)
        event.notes = notes
        if let calendar { event.calendar = calendar }
        try eventStore.save(event, span: .thisEvent)
    }

    func deleteEvent(_ event: EKEvent) throws {
        try eventStore.remove(event, span: .thisEvent)
    }

    func updateReminder(_ reminder: EKReminder, title: String, due: Date?, notes: String?) throws {
        reminder.title = title
        reminder.notes = notes
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        } else {
            reminder.dueDateComponents = nil
        }
        try eventStore.save(reminder, commit: true)
    }

    func deleteReminder(_ reminder: EKReminder) throws {
        try eventStore.remove(reminder, commit: true)
    }

    /// Reminders with NO due date (the general checklist), scoped exactly like
    /// the dated reads. Surfaced so an undated reminder is never silently hidden.
    func undatedReminders() async -> [EKReminder] {
        guard reminderGranted else { return [] }
        let lists: [EKCalendar]?
        switch reminderReadScope() {
        case .all: lists = nil
        case .only(let c): lists = c
        case .none: return []
        }
        let predicate = eventStore.predicateForReminders(in: lists)
        let all = await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        return all.filter { $0.dueDateComponents == nil }
    }
}

// MARK: - EventKitError

enum EventKitError: LocalizedError {
    case notAuthorized
    case eventNotFound
    case noSource
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Calendar access not authorized."
        case .eventNotFound: return "Calendar event not found."
        case .noSource:      return "No calendar account available to create the MTRX calendar."
        case .saveFailed(let r): return "Failed to save: \(r)"
        }
    }
}
