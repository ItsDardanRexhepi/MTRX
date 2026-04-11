// PositionsWidget.swift
// MTRX Widget
//
// Home screen widget showing open DeFi and staking positions.

import WidgetKit
import SwiftUI

struct PositionData: Identifiable {
    let id = UUID()
    let name: String
    let healthFactor: Double
    let value: String
    let apy: String
}

struct PositionsEntry: TimelineEntry {
    let date: Date
    let totalValue: String
    let positions: [PositionData]
}

struct PositionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PositionsEntry {
        PositionsEntry(date: .now, totalValue: "$0", positions: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (PositionsEntry) -> Void) {
        completion(PositionsEntry(
            date: .now,
            totalValue: "$5,470",
            positions: [
                PositionData(name: "Aave V3", healthFactor: 2.8, value: "$2,500", apy: "4.2%"),
                PositionData(name: "Uniswap V3", healthFactor: 0, value: "$1,800", apy: "12.5%"),
                PositionData(name: "MTRX Stake", healthFactor: 0, value: "$1,170", apy: "8.7%"),
            ]
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PositionsEntry>) -> Void) {
        let entry = PositionsEntry(
            date: .now,
            totalValue: "$5,470",
            positions: [
                PositionData(name: "Aave V3", healthFactor: 2.8, value: "$2,500", apy: "4.2%"),
                PositionData(name: "Uniswap V3", healthFactor: 0, value: "$1,800", apy: "12.5%"),
                PositionData(name: "MTRX Stake", healthFactor: 0, value: "$1,170", apy: "8.7%"),
            ]
        )
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct PositionsWidgetView: View {
    let entry: PositionsEntry

    private let cyan = Color(red: 0, green: 0.675, blue: 0.694)
    private let green = Color(red: 0.2, green: 0.84, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(cyan)
                    Text("Positions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.totalValue)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            if entry.positions.isEmpty {
                Spacer()
                Text("No active positions")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(entry.positions) { pos in
                    HStack(spacing: 6) {
                        healthDot(pos.healthFactor)

                        Text(pos.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)

                        Spacer()

                        Text(pos.apy)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(green)

                        Text(pos.value)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.black }
    }

    @ViewBuilder
    private func healthDot(_ factor: Double) -> some View {
        if factor > 0 {
            let color: Color = factor > 2 ? .green : factor > 1.5 ? .yellow : .red
            Circle().fill(color).frame(width: 6, height: 6)
        } else {
            Circle().fill(cyan.opacity(0.4)).frame(width: 6, height: 6)
        }
    }
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
