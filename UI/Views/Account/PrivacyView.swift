import SwiftUI

/// Component 29 privacy controls — credential visibility, social profile, wallet linking, data deletion
struct PrivacyView: View {
    @StateObject private var viewModel = PrivacyViewModel()

    var body: some View {
        Form {
            Section("Credential Visibility") {
                ForEach(viewModel.credentials, id: \.id) { cred in
                    Toggle(cred.name, isOn: Binding(
                        get: { cred.isVisible },
                        set: { viewModel.setCredentialVisibility(cred.id, visible: $0) }
                    ))
                }
            }

            Section("Social Profile") {
                Picker("Profile Visibility", selection: $viewModel.profileVisibility) {
                    Text("Public").tag(ProfileVisibility.public_)
                    Text("Connections Only").tag(ProfileVisibility.connections)
                    Text("Private").tag(ProfileVisibility.private_)
                }
            }

            Section("Wallet Address Linking") {
                Toggle("Show linked wallets on profile", isOn: $viewModel.showLinkedWallets)
                Text("Others can see which wallets belong to you")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("Agent Conversations") {
                Toggle("Store Trinity conversation history", isOn: $viewModel.storeTrinityHistory)
                if viewModel.storeTrinityHistory {
                    Button("Clear Conversation History") { viewModel.clearHistory() }
                }
            }

            Section("Data Deletion") {
                Button(role: .destructive) { viewModel.showDeletionAlert = true } label: {
                    Label("Delete Off-Chain Data", systemImage: "trash")
                }
                Text("On-chain records (transactions, attestations, contracts) are permanent and cannot be deleted. This deletes only local and cloud-stored data.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("Privacy")
        .alert("Delete Off-Chain Data?", isPresented: $viewModel.showDeletionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { viewModel.deleteOffChainData() }
        } message: {
            Text("This removes all locally stored preferences, Trinity memory, and cloud backups. On-chain records remain permanently.")
        }
    }
}

enum ProfileVisibility: String { case public_, connections, private_ }

struct CredentialEntry: Identifiable { let id: String; let name: String; var isVisible: Bool }

@MainActor
final class PrivacyViewModel: ObservableObject {
    @Published var credentials: [CredentialEntry] = []
    @Published var profileVisibility: ProfileVisibility = .connections
    @Published var showLinkedWallets = false
    @Published var storeTrinityHistory = true
    @Published var showDeletionAlert = false

    func setCredentialVisibility(_ id: String, visible: Bool) {
        if let idx = credentials.firstIndex(where: { $0.id == id }) {
            credentials[idx] = CredentialEntry(id: id, name: credentials[idx].name, isVisible: visible)
        }
    }

    func clearHistory() { /* Clear Trinity conversation data from local storage */ }
    func deleteOffChainData() { /* Delete all off-chain data — local + CloudKit */ }
}
