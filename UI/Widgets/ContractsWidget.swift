import WidgetKit
import SwiftUI

struct ContractsEntry: TimelineEntry {
    let date: Date
    let activeCount: Int
    let nextDeadline: String?
    let recentActivity: String?
}

struct ContractsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContractsEntry { ContractsEntry(date: .now, activeCount: 0, nextDeadline: nil, recentActivity: nil) }
    func getSnapshot(in context: Context, completion: @escaping (ContractsEntry) -> Void) {
        completion(ContractsEntry(date: .now, activeCount: 3, nextDeadline: "Payment due Apr 5", recentActivity: "Rental agreement signed"))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ContractsEntry>) -> Void) {
        let entry = ContractsEntry(date: .now, activeCount: 0, nextDeadline: nil, recentActivity: nil)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct ContractsWidgetView: View {
    let entry: ContractsEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Contracts").font(.caption).foregroundColor(.secondary); Spacer(); Text("\(entry.activeCount)").font(.title3).bold() }
            if let deadline = entry.nextDeadline { Label(deadline, systemImage: "clock").font(.caption2) }
            if let activity = entry.recentActivity { Label(activity, systemImage: "doc.text").font(.caption2).foregroundColor(.secondary) }
        }
        .padding()
    }
}

struct ContractsWidget: Widget {
    let kind = "ContractsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContractsProvider()) { entry in ContractsWidgetView(entry: entry) }
        .configurationDisplayName("Contracts")
        .description("Active smart contracts and upcoming deadlines.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
