import WidgetKit
import SwiftUI

struct PositionData: Identifiable { let id = UUID(); let name: String; let ratio: Double; let value: String }

struct PositionsEntry: TimelineEntry {
    let date: Date
    let positions: [PositionData]
}

struct PositionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PositionsEntry { PositionsEntry(date: .now, positions: []) }
    func getSnapshot(in context: Context, completion: @escaping (PositionsEntry) -> Void) {
        completion(PositionsEntry(date: .now, positions: [
            PositionData(name: "ETH/USDC LP", ratio: 1.85, value: "$4,200"),
            PositionData(name: "DeFi Loan", ratio: 1.42, value: "$2,100")
        ]))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PositionsEntry>) -> Void) {
        let entry = PositionsEntry(date: .now, positions: [])
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct PositionsWidgetView: View {
    let entry: PositionsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open Positions").font(.caption).foregroundColor(.secondary)
            if entry.positions.isEmpty {
                Text("No active positions").font(.caption2).foregroundColor(.tertiary)
            } else {
                ForEach(entry.positions) { pos in
                    HStack {
                        Circle().fill(healthColor(pos.ratio)).frame(width: 8, height: 8)
                        Text(pos.name).font(.caption2)
                        Spacer()
                        Text(pos.value).font(.caption2).bold()
                    }
                }
            }
        }
        .padding()
    }

    func healthColor(_ ratio: Double) -> Color { ratio > 1.5 ? .green : ratio > 1.2 ? .yellow : .red }
}

struct PositionsWidget: Widget {
    let kind = "PositionsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PositionsProvider()) { entry in
            PositionsWidgetView(entry: entry)
        }
        .configurationDisplayName("Positions")
        .description("Your open DeFi and staking positions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
