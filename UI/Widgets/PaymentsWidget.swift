import WidgetKit
import SwiftUI

struct PaymentsEntry: TimelineEntry {
    let date: Date
    let nextPayment: String?
    let nextPaymentDate: String?
    let subscriptionRenewals: Int
}

struct PaymentsProvider: TimelineProvider {
    func placeholder(in context: Context) -> PaymentsEntry { PaymentsEntry(date: .now, nextPayment: nil, nextPaymentDate: nil, subscriptionRenewals: 0) }
    func getSnapshot(in context: Context, completion: @escaping (PaymentsEntry) -> Void) {
        completion(PaymentsEntry(date: .now, nextPayment: "Rent - 0.5 ETH", nextPaymentDate: "Apr 1", subscriptionRenewals: 2))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PaymentsEntry>) -> Void) {
        let entry = PaymentsEntry(date: .now, nextPayment: nil, nextPaymentDate: nil, subscriptionRenewals: 0)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60))))
    }
}

struct PaymentsWidgetView: View {
    let entry: PaymentsEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Payments").font(.caption).foregroundColor(.secondary)
            if let payment = entry.nextPayment, let date = entry.nextPaymentDate {
                Text(payment).font(.caption).bold()
                Text("Due \(date)").font(.caption2).foregroundColor(.orange)
            } else {
                Text("No upcoming payments").font(.caption2).foregroundColor(.tertiary)
            }
            if entry.subscriptionRenewals > 0 {
                Text("\(entry.subscriptionRenewals) subscription renewals this month").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct PaymentsWidget: Widget {
    let kind = "PaymentsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PaymentsProvider()) { entry in PaymentsWidgetView(entry: entry) }
        .configurationDisplayName("Payments")
        .description("Next payment due and subscription renewals.")
        .supportedFamilies([.systemSmall])
    }
}
