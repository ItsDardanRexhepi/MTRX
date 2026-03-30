import SwiftUI
import WidgetKit

/// Portfolio glance on Apple Watch with total value and top positions
struct WatchPortfolioView: View {
    @StateObject private var viewModel = WatchPortfolioViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Portfolio")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text(viewModel.totalValue)
                    .font(.system(.title2, design: .rounded, weight: .bold))

                HStack(spacing: 4) {
                    Image(systemName: viewModel.changePositive ? "arrow.up.right" : "arrow.down.right")
                    Text(viewModel.change24h)
                }
                .font(.caption)
                .foregroundColor(viewModel.changePositive ? .green : .red)

                Divider()

                ForEach(viewModel.topPositions) { position in
                    HStack {
                        Text(position.symbol).font(.caption2).bold()
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(position.value).font(.caption2)
                            Text(position.change).font(.system(.caption2))
                                .foregroundColor(position.changePositive ? .green : .red)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear { viewModel.refresh() }
    }
}

struct WatchPosition: Identifiable {
    let id = UUID()
    let symbol: String
    let value: String
    let change: String
    let changePositive: Bool
}

@MainActor
final class WatchPortfolioViewModel: ObservableObject {
    @Published var totalValue = "$0.00"
    @Published var change24h = "+$0.00 (0%)"
    @Published var changePositive = true
    @Published var topPositions: [WatchPosition] = []

    func refresh() {
        NotificationCenter.default.addObserver(forName: .watchDataReceived, object: nil, queue: .main) { [weak self] notification in
            guard let data = notification.object as? [String: Any] else { return }
            self?.updateFrom(data)
        }
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "portfolio"], replyHandler: { [weak self] reply in
            Task { @MainActor in self?.updateFrom(reply) }
        }, errorHandler: nil)
    }

    private func updateFrom(_ data: [String: Any]) {
        if let total = data["totalValue"] as? String { totalValue = total }
        if let change = data["change24h"] as? String { change24h = change }
        if let positive = data["changePositive"] as? Bool { changePositive = positive }
        if let positions = data["topPositions"] as? [[String: Any]] {
            topPositions = positions.prefix(5).map { pos in
                WatchPosition(
                    symbol: pos["symbol"] as? String ?? "",
                    value: pos["value"] as? String ?? "",
                    change: pos["change"] as? String ?? "",
                    changePositive: pos["changePositive"] as? Bool ?? true
                )
            }
        }
    }
}

import WatchConnectivity
extension WCSession: @unchecked @retroactive Sendable {}
