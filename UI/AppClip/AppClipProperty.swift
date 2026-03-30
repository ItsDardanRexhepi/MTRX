import SwiftUI

/// App Clip preview for property on-chain history — ownership timeline, inspections, title status
struct AppClipProperty: View {
    let tokenId: String
    @State private var history: [OwnershipRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Property History").font(.title2).bold()
                Text("Token: \(tokenId)").font(.caption).monospaced().foregroundColor(.secondary)

                ForEach(history, id: \.date) { record in
                    HStack(alignment: .top) {
                        Circle().fill(record.type == .transfer ? .blue : .green).frame(width: 10, height: 10).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.event).bold()
                            Text(record.date).font(.caption).foregroundColor(.secondary)
                            if let detail = record.detail { Text(detail).font(.caption2).foregroundColor(.tertiary) }
                        }
                    }
                }

                Button("Get Full App for Complete History") {}
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.accentColor).foregroundColor(.white).cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Property")
        .task { loadHistory() }
    }

    func loadHistory() {
        history = [
            OwnershipRecord(event: "Title Registered", date: "Jan 15, 2025", detail: "Original tokenization", type: .registration),
            OwnershipRecord(event: "Inspection Passed", date: "Mar 1, 2025", detail: "Annual inspection — all clear", type: .inspection),
            OwnershipRecord(event: "Ownership Transfer", date: "Jun 20, 2025", detail: "0x1234...→0x5678...", type: .transfer),
        ]
    }
}

struct OwnershipRecord { let event: String; let date: String; let detail: String?; let type: RecordType; enum RecordType { case registration, inspection, transfer } }
