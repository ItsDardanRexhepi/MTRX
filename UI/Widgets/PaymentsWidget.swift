// PaymentsWidget.swift
// MTRX Widget
//
// Home screen widget showing upcoming payments and subscription renewals.

import WidgetKit
import SwiftUI

struct PaymentsEntry: TimelineEntry {
    let date: Date
    let nextPayment: String?
    let nextPaymentAmount: String?
    let nextPaymentDate: String?
    let subscriptionRenewals: Int
}

struct PaymentsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaymentsEntry {
        PaymentsEntry(date: .now, nextPayment: nil, nextPaymentAmount: nil, nextPaymentDate: nil, subscriptionRenewals: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (PaymentsEntry) -> Void) {
        completion(PaymentsEntry(date: .now, nextPayment: "Rent Agreement", nextPaymentAmount: "0.5 ETH", nextPaymentDate: "Apr 15", subscriptionRenewals: 2))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PaymentsEntry>) -> Void) {
        let entry = PaymentsEntry(date: .now, nextPayment: "Rent Agreement", nextPaymentAmount: "0.5 ETH", nextPaymentDate: "Apr 15", subscriptionRenewals: 2)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60))))
    }
}

struct PaymentsWidgetView: View {
    let entry: PaymentsEntry

    private let cyan = Color(red: 0, green: 0.675, blue: 0.694)
    private let amber = Color(red: 1.0, green: 0.7, blue: 0.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(cyan)
                Text("Payments")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let payment = entry.nextPayment, let amount = entry.nextPaymentAmount, let date = entry.nextPaymentDate {
                VStack(alignment: .leading, spacing: 3) {
                    Text(payment)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(amount)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Label("Due \(date)", systemImage: "clock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(amber)
                }
            } else {
                Text("No upcoming payments")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if entry.subscriptionRenewals > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                    Text("\(entry.subscriptionRenewals) renewals this month")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color.black }
    }
}

struct PaymentsWidget: Widget {
    let kind = "PaymentsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaymentsProvider()) { entry in
            PaymentsWidgetView(entry: entry)
        }
        .configurationDisplayName("Payments")
        .description("Next payment due and subscription renewals.")
        .supportedFamilies([.systemSmall])
    }
}
