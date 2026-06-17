// PortfolioWidget.swift
// MTRX Widget
//
// Home screen widget showing portfolio value with real-time updates.

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct PortfolioEntry: TimelineEntry {
    let date: Date
    let totalValue: String
    let change24h: String
    let changePercent: String
    let isPositive: Bool
    let topTokens: [(symbol: String, value: String, change: String, isUp: Bool)]
}

// MARK: - Provider

struct PortfolioProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortfolioEntry { .empty }

    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        completion(currentEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let timeline = Timeline(entries: [currentEntry], policy: .after(Date().addingTimeInterval(15 * 60)))
        completion(timeline)
    }

    /// Reflects the app's published portfolio; honest empty state when none exists.
    private var currentEntry: PortfolioEntry {
        guard let s = WidgetSharedStore.portfolio() else { return .empty }
        return PortfolioEntry(
            date: s.updatedAt,
            totalValue: s.totalValue,
            change24h: s.change24h,
            changePercent: s.changePercent,
            isPositive: s.isPositive,
            topTokens: s.tokens.map { ($0.symbol, $0.value, $0.change, $0.isUp) }
        )
    }
}

extension PortfolioEntry {
    /// Honest placeholder shown before the app has published any data.
    static var empty: PortfolioEntry {
        PortfolioEntry(date: .now, totalValue: "$\u{2014}", change24h: "\u{2014}", changePercent: "\u{2014}", isPositive: true, topTokens: [])
    }
}

// MARK: - Widget View

struct PortfolioWidgetView: View {
    let entry: PortfolioEntry
    @Environment(\.widgetFamily) var family

    // Widget-local color constants (can't use main app design system in extensions)
    private let cyan = Color(red: 0, green: 0.675, blue: 0.694)
    private let gainGreen = Color(red: 0.2, green: 0.84, blue: 0.42)
    private let lossRed = Color(red: 1.0, green: 0.27, blue: 0.27)

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallWidget
            case .systemMedium:
                mediumWidget
            default:
                largeWidget
            }
        }
        .containerBackground(for: .widget) {
            Color.black
        }
    }

    // MARK: - Small

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("M")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(cyan)
                Text("Portfolio")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.totalValue)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)

            HStack(spacing: 3) {
                Image(systemName: entry.isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text(entry.changePercent)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(entry.isPositive ? gainGreen : lossRed)
        }
        .padding(14)
    }

    // MARK: - Medium

    private var mediumWidget: some View {
        HStack(spacing: 16) {
            // Left: value
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("M")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(cyan)
                    Text("Portfolio")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(entry.totalValue)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 4) {
                    Image(systemName: entry.isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(entry.change24h) (\(entry.changePercent))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(entry.isPositive ? gainGreen : lossRed)
            }

            // Right: top tokens
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.topTokens.prefix(3), id: \.symbol) { token in
                    HStack {
                        Text(token.symbol)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 40, alignment: .leading)
                        Spacer()
                        Text(token.value)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(token.change)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(token.isUp ? gainGreen : lossRed)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
    }

    // MARK: - Large

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 4) {
                    Text("M")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(cyan)
                    Text("MTRX Portfolio")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(entry.totalValue)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                Image(systemName: entry.isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                Text("\(entry.change24h) (\(entry.changePercent)) today")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(entry.isPositive ? gainGreen : lossRed)

            Divider().overlay(Color.white.opacity(0.1))

            Text("Holdings")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(entry.topTokens, id: \.symbol) { token in
                HStack {
                    Circle()
                        .fill(cyan.opacity(0.15))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(String(token.symbol.prefix(1)))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(cyan)
                        )

                    Text(token.symbol)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)

                    Spacer()

                    Text(token.value)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))

                    Text(token.change)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(token.isUp ? gainGreen : lossRed)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            Spacer()
        }
        .padding(16)
    }
}

// MARK: - Widget Configuration

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

#Preview(as: .systemSmall) {
    PortfolioWidget()
} timeline: {
    PortfolioEntry(date: .now, totalValue: "$12,450.23", change24h: "+$340.50", changePercent: "+2.81%", isPositive: true, topTokens: [("ETH", "$7,960", "+3.1%", true), ("USDC", "$1,250", "+0.0%", true), ("MTRX", "$1,170", "+12.4%", true)])
}
