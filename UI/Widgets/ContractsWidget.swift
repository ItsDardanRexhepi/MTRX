// ContractsWidget.swift
// MTRX Widget
//
// Home screen widget showing active smart contracts and deadlines.

import WidgetKit
import SwiftUI

struct ContractsEntry: TimelineEntry {
    let date: Date
    let activeCount: Int
    let pendingCount: Int
    let nextDeadline: String?
    let recentActivity: String?
}

struct ContractsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContractsEntry {
        ContractsEntry(date: .now, activeCount: 0, pendingCount: 0, nextDeadline: nil, recentActivity: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContractsEntry) -> Void) {
        completion(currentEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContractsEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    /// Reflects the app's published contract activity; honest empty state when none exists.
    private var currentEntry: ContractsEntry {
        guard let s = WidgetSharedStore.contracts() else {
            return ContractsEntry(date: .now, activeCount: 0, pendingCount: 0, nextDeadline: nil, recentActivity: nil)
        }
        return ContractsEntry(
            date: s.updatedAt,
            activeCount: s.activeCount,
            pendingCount: s.pendingCount,
            nextDeadline: s.nextDeadline,
            recentActivity: s.recentActivity
        )
    }
}

struct ContractsWidgetView: View {
    let entry: ContractsEntry
    @Environment(\.widgetFamily) var family

    private let cyan = Color(red: 0, green: 0.675, blue: 0.694)
    private let amber = Color(red: 1.0, green: 0.7, blue: 0.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(cyan)
                    Text("Contracts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entry.activeCount)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            if family != .systemSmall {
                Divider().overlay(Color.white.opacity(0.1))
            }

            if entry.pendingCount > 0 {
                Label("\(entry.pendingCount) pending", systemImage: "clock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(amber)
            }

            if let deadline = entry.nextDeadline {
                Label(deadline, systemImage: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }

            if family == .systemMedium, let activity = entry.recentActivity {
                Spacer()
                Label(activity, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.2, green: 0.84, blue: 0.42))
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.black }
    }
}

struct ContractsWidget: Widget {
    let kind = "ContractsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContractsProvider()) { entry in
            ContractsWidgetView(entry: entry)
        }
        .configurationDisplayName("Contracts")
        .description("Active smart contracts and upcoming deadlines.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
