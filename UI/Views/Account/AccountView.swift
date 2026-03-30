import SwiftUI

/// Main account hub — DID identity card, wallet addresses, activity history, settings
struct AccountView: View {
    @StateObject private var viewModel = AccountViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Identity Card
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.accentColor)
                        Text(viewModel.displayName)
                            .font(.title2).bold()
                        if let did = viewModel.didIdentifier {
                            Text(did)
                                .font(.caption).monospaced()
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)

                    // Wallet Addresses
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wallets", systemImage: "wallet.pass")
                            .font(.headline)
                        ForEach(viewModel.wallets, id: \.address) { wallet in
                            HStack {
                                Text(wallet.label)
                                Spacer()
                                Text(String(wallet.address.prefix(6)) + "..." + String(wallet.address.suffix(4)))
                                    .monospaced().font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)

                    // Navigation
                    NavigationLink("Wallet & Portfolio", destination: WalletView())
                    NavigationLink("Settings", destination: SettingsView())
                    NavigationLink("Privacy Controls", destination: PrivacyView())
                }
                .padding()
            }
            .navigationTitle("Account")
        }
    }
}

struct WalletInfo { let label: String; let address: String }

@MainActor
final class AccountViewModel: ObservableObject {
    @Published var displayName = ""
    @Published var didIdentifier: String?
    @Published var wallets: [WalletInfo] = []

    init() { Task { await loadAccount() } }

    func loadAccount() async {
        displayName = "MTRX User"
        didIdentifier = "did:ethr:base:0x..."
        wallets = [WalletInfo(label: "Primary", address: "0x46fF491D7054A6F500026B3E81f358190f8d8Ec5")]
    }
}
