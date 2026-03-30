import WidgetKit
import SwiftUI

struct PortfolioEntry: TimelineEntry {
    let date: Date
    let totalValue: String
    let change24h: String
    let isPositive: Bool
}

struct PortfolioProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: .now, totalValue: "$--,---", change24h: "+$0.00", isPositive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        completion(PortfolioEntry(date: .now, totalValue: "$12,450.00", change24h: "+$340.50 (2.8%)", isPositive: true))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let entry = PortfolioEntry(date: .now, totalValue: "$12,450.00", change24h: "+$340.50 (2.8%)", isPositive: true)
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
        completion(timeline)
    }
}

struct PortfolioWidgetView: View {
    let entry: PortfolioEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Portfolio").font(.caption).foregroundColor(.secondary)
            Text(entry.totalValue).font(family == .systemSmall ? .title3 : .title2).bold()
            HStack(spacing: 2) {
                Image(systemName: entry.isPositive ? "arrow.up.right" : "arrow.down.right")
                Text(entry.change24h)
            }
            .font(.caption)
            .foregroundColor(entry.isPositive ? .green : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

struct PortfolioWidget: Widget {
    let kind = "PortfolioWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            PortfolioWidgetView(entry: entry)
        }
        .configurationDisplayName("Portfolio")
        .description("Your total portfolio value at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
