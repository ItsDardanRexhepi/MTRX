import SwiftUI

/// Portfolio — token balances, NFTs, DeFi positions, staking rewards, transaction history
struct WalletView: View {
    @StateObject private var viewModel = WalletViewModel()
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Total Value Header
            VStack(spacing: 4) {
                Text(viewModel.totalValue)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                HStack(spacing: 4) {
                    Image(systemName: viewModel.isPositive ? "arrow.up.right" : "arrow.down.right")
                    Text(viewModel.change24h)
                }
                .font(.subheadline)
                .foregroundColor(viewModel.isPositive ? .green : .red)
            }
            .padding()

            // Tab Selector
            Picker("", selection: $selectedTab) {
                Text("Tokens").tag(0)
                Text("NFTs").tag(1)
                Text("DeFi").tag(2)
                Text("History").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Content
            ScrollView {
                switch selectedTab {
                case 0: tokenList
                case 1: nftGallery
                case 2: defiPositions
                case 3: transactionHistory
                default: EmptyView()
                }
            }
        }
        .navigationTitle("Wallet")
    }

    private var tokenList: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.tokens, id: \.symbol) { token in
                HStack {
                    VStack(alignment: .leading) {
                        Text(token.symbol).bold()
                        Text(token.name).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(token.value)
                        Text(token.balance).font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .padding()
    }

    private var nftGallery: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
            ForEach(viewModel.nfts, id: \.tokenId) { nft in
                VStack {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(height: 150)
                    Text(nft.name).font(.caption).lineLimit(1)
                }
            }
        }
        .padding()
    }

    private var defiPositions: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.defiPositions, id: \.protocol_) { pos in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(pos.protocol_).bold()
                        Spacer()
                        Text(pos.value)
                    }
                    HStack {
                        Text("Collateral: \(pos.collateralRatio)")
                            .foregroundColor(pos.healthColor)
                        Spacer()
                        Text(pos.type).font(.caption).foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
            }
        }
        .padding()
    }

    private var transactionHistory: some View {
        LazyVStack(spacing: 4) {
            ForEach(viewModel.transactions, id: \.hash) { tx in
                HStack {
                    Image(systemName: tx.isIncoming ? "arrow.down.left" : "arrow.up.right")
                        .foregroundColor(tx.isIncoming ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text(tx.description_).lineLimit(1)
                        Text(tx.date).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(tx.amount)
                }
                .padding(.vertical, 6)
                .padding(.horizontal)
            }
        }
    }
}

struct TokenInfo { let symbol: String; let name: String; let value: String; let balance: String }
struct NFTInfo { let tokenId: String; let name: String; let collection: String }
struct DeFiPosition { let protocol_: String; let type: String; let value: String; let collateralRatio: String; let healthColor: Color }
struct TransactionInfo { let hash: String; let description_: String; let amount: String; let date: String; let isIncoming: Bool }

@MainActor final class WalletViewModel: ObservableObject {
    @Published var totalValue = "$0.00"
    @Published var change24h = "+$0.00"
    @Published var isPositive = true
    @Published var tokens: [TokenInfo] = []
    @Published var nfts: [NFTInfo] = []
    @Published var defiPositions: [DeFiPosition] = []
    @Published var transactions: [TransactionInfo] = []
}
