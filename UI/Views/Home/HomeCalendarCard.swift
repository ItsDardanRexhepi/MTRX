// HomeCalendarCard.swift
// MTRX — Home
//
// The MTRX interactive calendar + integrated Reminders (EventKit). Reached from
// the tappable date in the Home greeting. A real month grid you navigate; tap a
// day to see its events AND reminders together; create / edit / delete events
// and reminders; check reminders off inline (real EventKit completion).
//
// Privacy: writes go ONLY to MTRX's dedicated calendar + reminder list by
// default, and reads are scoped to them — UNLESS the user explicitly opts into
// personal-calendar sync (default OFF). Every state is honest; nothing is faked.

import SwiftUI
import EventKit

private func mtrxEventDateText(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}
private func mtrxTimeText(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

/// Identifiable wrapper so EKEvent/EKReminder (not Identifiable) can drive
/// `.sheet(item:)`.
private struct Editing<Item>: Identifiable { let id = UUID(); let item: Item }

private extension View {
    /// The app's Liquid Glass card — real system glass on iOS 26 plus the
    /// trinity rim + soft shadow, matching the Portfolio / music cards.
    func mtrxCalGlassCard() -> some View {
        self
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.trinityPrimary.opacity(0.035))
            .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [Color.trinityPrimary.opacity(0.35), Color.trinityPrimary.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: Color.trinityPrimary.opacity(0.08), radius: 14, y: 6)
    }
}

// MARK: - Interactive calendar

struct MTRXCalendarView: View {
    @State private var ek = EventKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var monthAnchor = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var eventDays: Set<Date> = []
    @State private var dayEvents: [EKEvent] = []
    @State private var dayReminders: [EKReminder] = []
    @State private var undatedReminders: [EKReminder] = []
    @State private var dayError: String?

    @State private var editingEvent: Editing<EKEvent>?
    @State private var newEvent = false
    @State private var editingReminder: Editing<EKReminder>?
    @State private var newReminder = false

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        monthGrid.mtrxCalGlassCard()
                        VStack(alignment: .leading, spacing: Spacing.sm) { daySection }.mtrxCalGlassCard()
                        personalSyncRow.mtrxCalGlassCard()
                    }
                    .padding(Spacing.md)
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary).accessibilityLabel("Close")
                    }
                }
            }
            .task { refreshAll() }
            .onChange(of: monthAnchor) { _, _ in reloadMonth() }
            .onChange(of: selectedDay) { _, _ in reloadDay() }
            .sheet(isPresented: $newEvent, onDismiss: refreshAll) {
                EventEditorView(existing: nil, defaultDay: selectedDay)
            }
            .sheet(item: $editingEvent, onDismiss: refreshAll) { ev in
                EventEditorView(existing: ev.item, defaultDay: selectedDay)
            }
            .sheet(isPresented: $newReminder, onDismiss: refreshAll) {
                ReminderEditorView(existing: nil, defaultDay: selectedDay)
            }
            .sheet(item: $editingReminder, onDismiss: refreshAll) { r in
                ReminderEditorView(existing: r.item, defaultDay: selectedDay)
            }
        }
    }

    // MARK: Month grid

    private var monthGrid: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Text(monthAnchor.formatted(.dateTime.month(.wide).year()))
                    .font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
                Spacer()
                Button("Today") { withAnimation { monthAnchor = Date(); selectedDay = cal.startOfDay(for: Date()) } }
                    .font(.mtrxCaptionBold).foregroundStyle(Color.trinityPrimary)
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .foregroundStyle(Color.labelSecondary).padding(.leading, Spacing.sm)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    .foregroundStyle(Color.labelSecondary)
            }

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s).font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(monthCells().enumerated()), id: \.offset) { _, date in
                    dayCell(date)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in if v.translation.width < -40 { shiftMonth(1) } else if v.translation.width > 40 { shiftMonth(-1) } }
        )
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let isToday = cal.isDateInToday(date)
            let isSelected = cal.isDate(date, inSameDayAs: selectedDay)
            let hasEvents = eventDays.contains(cal.startOfDay(for: date))
            Button { MtrxHaptics.selection(); selectedDay = cal.startOfDay(for: date) } label: {
                VStack(spacing: 2) {
                    Text("\(cal.component(.day, from: date))")
                        .font(.mtrxCallout)
                        .foregroundStyle(isSelected ? .white : (isToday ? Color.trinityPrimary : Color.labelPrimary))
                        .frame(width: 34, height: 34)
                        .background {
                            if isSelected { Circle().fill(Color.trinityPrimary) }
                            else if isToday { Circle().strokeBorder(Color.trinityPrimary.opacity(0.7), lineWidth: 1) }
                        }
                    Circle().fill(hasEvents ? Color.trinityPrimary : .clear).frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 41)
        }
    }

    // MARK: Selected-day section

    @ViewBuilder
    private var daySection: some View {
        HStack {
            Text(selectedDay.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
            Spacer()
        }

        // Events
        if !ek.calendarGranted {
            authRow(denied: ek.calendarDenied || ek.calendarWriteOnly,
                    grant: "Connect Calendar",
                    deniedText: ek.calendarWriteOnly
                        ? "MTRX has add-only access. Enable full access in Settings to show your schedule."
                        : "Calendar access is off. Enable it in Settings to see and add events.",
                    action: { Task { await ek.requestCalendarAccess(); refreshAll() } })
        } else {
            sub("Events", add: { newEvent = true })
            if dayEvents.isEmpty {
                emptyText("No events. Tap + to add one.")
            } else {
                ForEach(dayEvents, id: \.eventIdentifier) { event in
                    Button { editingEvent = Editing(item: event) } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "calendar").foregroundStyle(Color.trinityPrimary).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(clean(event.title)).font(.mtrxCallout).foregroundStyle(Color.labelPrimary).lineLimit(1)
                                Text(event.isAllDay ? "All day" : mtrxTimeText(event.startDate))
                                    .font(.mtrxCaption2).foregroundStyle(Color.labelSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.labelTertiary)
                        }
                        .padding(.vertical, Spacing.xs).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // Reminders
        if !ek.reminderGranted {
            authRow(denied: ek.reminderDenied,
                    grant: "Connect Reminders",
                    deniedText: "Reminders access is off. Enable it in Settings for your checklist.",
                    action: { Task { await ek.requestReminderAccess(); refreshAll() } })
        } else {
            sub("Reminders", add: { newReminder = true })
            if let dayError {
                Text(dayError).font(.mtrxCaption1).foregroundStyle(Color.statusError)
            }
            if dayReminders.isEmpty {
                emptyText("No reminders due. Tap + to add one.")
            } else {
                ForEach(dayReminders, id: \.calendarItemIdentifier) { reminderRow($0) }
            }
            // Undated reminders (Due-date toggled off) — shown so a saved
            // reminder is never silently hidden from the calendar.
            if !undatedReminders.isEmpty {
                Text("No date").font(.mtrxCaption2).foregroundStyle(Color.labelTertiary).padding(.top, Spacing.xs)
                ForEach(undatedReminders, id: \.calendarItemIdentifier) { reminderRow($0) }
            }
        }
    }

    private func reminderRow(_ reminder: EKReminder) -> some View {
        HStack(spacing: Spacing.sm) {
            Button { toggle(reminder) } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(reminder.isCompleted ? Color.statusSuccess : Color.labelTertiary)
            }
            .buttonStyle(.plain)
            Button { editingReminder = Editing(item: reminder) } label: {
                HStack {
                    Text(reminder.title ?? "Untitled")
                        .font(.mtrxCallout)
                        .foregroundStyle(reminder.isCompleted ? Color.labelTertiary : Color.labelPrimary)
                        .strikethrough(reminder.isCompleted)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.labelTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Spacing.xs)
    }

    private var personalSyncRow: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: Binding(get: { ek.personalSyncEnabled }, set: { setPersonalSync($0) })) {
                Text("Show my personal calendar").font(.mtrxCallout).foregroundStyle(Color.labelPrimary)
            }
            .tint(Color.trinityPrimary)
            Text(ek.personalSyncEnabled
                 ? "On — MTRX can read your personal calendars/reminders and add events to them."
                 : "Off — MTRX uses only its own MTRX calendar & reminders. Turn on to also see and use your personal calendar.")
                .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
        }
        .padding(.top, Spacing.sm)
    }

    // MARK: Helpers

    private func sub(_ title: String, add: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.mtrxCalloutBold).foregroundStyle(Color.labelSecondary)
            Spacer()
            Button(action: add) {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Color.trinityPrimary)
            }
            .buttonStyle(.plain).accessibilityLabel("Add \(title.lowercased())")
        }
        .padding(.top, Spacing.xs)
    }

    private func emptyText(_ t: String) -> some View {
        Text(t).font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Spacing.xs)
    }

    private func authRow(denied: Bool, grant: String, deniedText: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if denied {
                Text(deniedText).font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: { Text("Open Settings") }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
            } else {
                Button(action: action) {
                    HStack { if ek.isWorking { ProgressView().tint(.white) }; Text(grant) }
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact)).disabled(ek.isWorking)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func monthCells() -> [Date?] {
        guard let month = cal.dateInterval(of: .month, for: monthAnchor) else { return [] }
        let monthStart = month.start
        let daysInMonth = cal.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
        let weekdayOfFirst = cal.component(.weekday, from: monthStart)
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<daysInMonth { cells.append(cal.date(byAdding: .day, value: d, to: monthStart)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func shiftMonth(_ by: Int) {
        if let d = cal.date(byAdding: .month, value: by, to: monthAnchor) {
            withAnimation(.easeInOut(duration: 0.2)) { monthAnchor = d }
        }
    }

    private func toggle(_ reminder: EKReminder) {
        MtrxHaptics.impact(.light)
        do {
            try ek.setReminderCompleted(reminder, completed: !reminder.isCompleted)
            dayError = nil
        } catch {
            dayError = "Couldn't update the reminder. Try again."
        }
        reloadDay()
    }

    private func setPersonalSync(_ on: Bool) {
        ek.personalSyncEnabled = on
        if on {
            Task {
                if !ek.calendarGranted { await ek.requestCalendarAccess() }
                if !ek.reminderGranted { await ek.requestReminderAccess() }
                refreshAll()
            }
        } else {
            refreshAll()
        }
    }

    private func refreshAll() { ek.refreshStatus(); reloadMonth(); reloadDay() }
    private func reloadMonth() { eventDays = ek.eventDays(inMonthOf: monthAnchor) }
    private func reloadDay() {
        let day = selectedDay
        dayEvents = ek.events(on: day)
        Task {
            let r = await ek.reminders(on: day)
            let u = await ek.undatedReminders()
            // A newer day may have been selected while these fetches were in flight;
            // drop stale results so we never show one day's reminders under another's header.
            guard day == selectedDay else { return }
            dayReminders = sortReminders(r)
            undatedReminders = sortReminders(u)
        }
    }

    private func sortReminders(_ r: [EKReminder]) -> [EKReminder] {
        r.sorted { (!$0.isCompleted ? 0 : 1, $0.title ?? "") < (!$1.isCompleted ? 0 : 1, $1.title ?? "") }
    }

    private func clean(_ t: String) -> String { t.hasPrefix("MTRX: ") ? String(t.dropFirst(6)) : t }
}

// MARK: - Event editor

struct EventEditorView: View {
    let existing: EKEvent?
    let defaultDay: Date
    @State private var ek = EventKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var notes = ""
    @State private var calendarID = ""
    @State private var showDelete = false
    @State private var error: String?

    private var calendars: [EKCalendar] { ek.writableEventCalendars() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $start)
                    DatePicker("Ends", selection: $end)
                }
                if calendars.count > 1 {
                    Section("Calendar") {
                        Picker("Calendar", selection: $calendarID) {
                            ForEach(calendars, id: \.calendarIdentifier) { c in
                                Text(c.title).tag(c.calendarIdentifier)
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                if let error {
                    Text(error).font(.mtrxCaption1).foregroundStyle(Color.statusError)
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) { showDelete = true } label: { Text("Delete Event") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
            .navigationTitle(existing == nil ? "New Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.trinityPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this event?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteEvent() }
            }
        }
    }

    private func load() {
        calendarID = ek.mtrxCalendarID() ?? calendars.first?.calendarIdentifier ?? ""
        if let e = existing {
            title = e.title ?? ""
            start = e.startDate
            end = e.endDate
            notes = e.notes ?? ""
            calendarID = e.calendar?.calendarIdentifier ?? calendarID
        } else {
            let base = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDay) ?? defaultDay
            start = base
            end = base.addingTimeInterval(3600)
        }
    }

    private func save() {
        let chosen = calendars.first { $0.calendarIdentifier == calendarID }
        do {
            if let e = existing {
                try ek.updateEvent(e, title: title, start: start, end: end, notes: notes.isEmpty ? nil : notes, calendar: chosen)
            } else {
                try ek.createEvent(title: title, start: start, end: end, notes: notes.isEmpty ? nil : notes, in: chosen)
            }
            dismiss()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't save the event." }
    }

    private func deleteEvent() {
        guard let e = existing else { return }
        do { try ek.deleteEvent(e); dismiss() }
        catch { self.error = "Couldn't delete the event." }
    }
}

// MARK: - Reminder editor

struct ReminderEditorView: View {
    let existing: EKReminder?
    let defaultDay: Date
    @State private var ek = EventKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var hasDue = true
    @State private var due = Date()
    @State private var notes = ""
    @State private var showDelete = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Toggle("Due date", isOn: $hasDue).tint(Color.trinityPrimary)
                    if hasDue { DatePicker("Due", selection: $due) }
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                if let error {
                    Text(error).font(.mtrxCaption1).foregroundStyle(Color.statusError)
                }
                if existing != nil {
                    Section {
                        Button(role: .destructive) { showDelete = true } label: { Text("Delete Reminder") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MtrxGradientBackground(style: .primary).ignoresSafeArea())
            .navigationTitle(existing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.trinityPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("Delete this reminder?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteReminder() }
            }
        }
    }

    private func load() {
        if let r = existing {
            title = r.title ?? ""
            notes = r.notes ?? ""
            if let comps = r.dueDateComponents, let d = Calendar.current.date(from: comps) {
                hasDue = true; due = d
            } else { hasDue = false }
        } else {
            due = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDay) ?? defaultDay
        }
    }

    private func save() {
        let dueDate = hasDue ? due : nil
        do {
            if let r = existing {
                try ek.updateReminder(r, title: title, due: dueDate, notes: notes.isEmpty ? nil : notes)
            } else {
                try ek.addReminder(title: title, due: dueDate, notes: notes.isEmpty ? nil : notes)
            }
            dismiss()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Couldn't save the reminder." }
    }

    private func deleteReminder() {
        guard let r = existing else { return }
        do { try ek.deleteReminder(r); dismiss() }
        catch { self.error = "Couldn't delete the reminder." }
    }
}
