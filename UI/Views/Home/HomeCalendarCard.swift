// HomeCalendarCard.swift
// MTRX — Home
//
// The MTRX calendar + integrated Reminders (EventKit), scoped to MTRX's OWN
// dedicated calendar + reminder list (never the user's personal calendars).
// Reached from the tappable date in the Home greeting (not a standalone card).
// Every state is honest: not-authorized → Connect; denied → Settings;
// granted+empty → honest empty; granted → real items. Never fabricated.

import SwiftUI
import EventKit

private func mtrxEventDateText(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
}

// MARK: - Detail (full upcoming + checklist)

struct MTRXCalendarView: View {
    @State private var ek = EventKitManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var events: [EKEvent] = []
    @State private var reminders: [EKReminder] = []
    @State private var newReminder = ""

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        upcomingSection
                        checklistSection
                    }
                    .padding(Spacing.md)
                }
            }
            .navigationTitle("MTRX Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.labelPrimary).accessibilityLabel("Close")
                    }
                }
            }
            .task { reloadAll() }
        }
    }

    // Upcoming events (Calendar)

    @ViewBuilder
    private var upcomingSection: some View {
        sectionHeader("Upcoming")
        if !ek.calendarGranted {
            authRow(
                denied: ek.calendarDenied || ek.calendarWriteOnly,
                grantTitle: "Connect Calendar",
                deniedText: ek.calendarWriteOnly
                    ? "MTRX has add-only access. Enable full access in Settings to show your MTRX schedule."
                    : "Calendar access is off. Enable it in Settings to see and add MTRX events.",
                action: { Task { await ek.requestCalendarAccess(); reloadAll() } })
        } else if events.isEmpty {
            emptyText("No upcoming MTRX events. They'll appear here as you schedule app activity.")
        } else {
            ForEach(events, id: \.eventIdentifier) { event in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "calendar").foregroundStyle(Color.trinityPrimary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clean(event.title)).font(.mtrxCallout).foregroundStyle(Color.labelPrimary)
                        Text(mtrxEventDateText(event.startDate)).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, Spacing.xs)
            }
        }
    }

    // Checklist (Reminders)

    @ViewBuilder
    private var checklistSection: some View {
        sectionHeader("Checklist")
        if !ek.reminderGranted {
            authRow(
                denied: ek.reminderDenied,
                grantTitle: "Connect Reminders",
                deniedText: "Reminders access is off. Enable it in Settings for your MTRX checklist.",
                action: { Task { await ek.requestReminderAccess(); reloadAll() } })
        } else {
            HStack(spacing: Spacing.sm) {
                TextField("Add a reminder…", text: $newReminder)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                    .background(Color.surfaceOverlay, in: Capsule())
                    .foregroundStyle(Color.labelPrimary)
                    .submitLabel(.done)
                    .onSubmit(addReminder)
                Button(action: addReminder) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 24)).foregroundStyle(Color.trinityPrimary)
                }
                .buttonStyle(.plain)
                .disabled(newReminder.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if reminders.isEmpty {
                emptyText("No reminders yet. Add one above, or MTRX will log activity here.")
            } else {
                ForEach(reminders, id: \.calendarItemIdentifier) { reminder in
                    Button { toggle(reminder) } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(reminder.isCompleted ? Color.statusSuccess : Color.labelTertiary)
                            Text(reminder.title ?? "Untitled")
                                .font(.mtrxCallout)
                                .foregroundStyle(reminder.isCompleted ? Color.labelTertiary : Color.labelPrimary)
                                .strikethrough(reminder.isCompleted)
                            Spacer()
                        }
                        .padding(.vertical, Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ t: String) -> some View {
        Text(t).font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
    }

    private func emptyText(_ t: String) -> some View {
        Text(t).font(.mtrxCallout).foregroundStyle(Color.labelTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func authRow(denied: Bool, grantTitle: String, deniedText: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if denied {
                Text(deniedText).font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: { Text("Open Settings") }
                    .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
            } else {
                Button(action: action) {
                    HStack {
                        if ek.isWorking { ProgressView().tint(.white) }
                        Text(grantTitle)
                    }
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                .disabled(ek.isWorking)
            }
        }
    }

    private func addReminder() {
        let title = newReminder.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        try? ek.addReminder(title: title)
        newReminder = ""
        reloadReminders()
    }

    private func toggle(_ reminder: EKReminder) {
        try? ek.setReminderCompleted(reminder, completed: !reminder.isCompleted)
        reloadReminders()
    }

    private func reloadAll() {
        ek.refreshStatus()
        events = ek.upcomingMTRXEvents(days: 30)
        reloadReminders()
    }

    private func reloadReminders() {
        Task {
            let r = await ek.fetchMTRXReminders()
            reminders = r.sorted { (!$0.isCompleted ? 0 : 1, $0.title ?? "") < (!$1.isCompleted ? 0 : 1, $1.title ?? "") }
        }
    }

    private func clean(_ t: String) -> String {
        t.hasPrefix("MTRX: ") ? String(t.dropFirst(6)) : t
    }
}
