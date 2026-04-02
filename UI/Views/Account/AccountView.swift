// AccountView.swift
// MTRX - DID identity hub, wallet addresses, activity, and settings navigation
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Models

struct WalletInfo: Identifiable, Equatable {
    let id: String
    let label: String
    let address: String
    let chainName: String
    let balance: String

    init(id: String = UUID().uuidString, label: String, address: String, chainName: String = "Base", balance: String = "") {
        self.id = id
        self.label = label
        self.address = address
        self.chainName = chainName
        self.balance = balance
    }
}

// MARK: - ViewModel

@MainActor
final class AccountViewModel: ObservableObject {
    @Published var displayName = ""
    @Published var didIdentifier: String?
    @Published var wallets: [WalletInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var avatarInitial = ""
    @Published var joinDate = ""
    @Published var showSignOutConfirm = false

    private let api = MTRXAPIClient.shared

    func loadAccount() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: [String: AnyCodableValue] = try await api.get(path: "/api/v1/account/profile")
            parseProfile(response)
        } catch {
            errorMessage = "Failed to load account: \(error.localizedDescription)"
        }
    }

    func signOut() {
        api.clearToken()
    }

    private func parseProfile(_ response: [String: AnyCodableValue]) {
        if case .dictionary(let d) = response["profile"] ?? response["data"] ?? .dictionary(response) {
            displayName = d["display_name"]?.stringValue ?? d["name"]?.stringValue ?? "MTRX User"
            didIdentifier = d["did"]?.stringValue ?? d["did_identifier"]?.stringValue
            joinDate = d["joined"]?.stringValue ?? ""
            avatarInitial = String(displayName.prefix(1)).uppercased()

            if case .array(let walletList) = d["wallets"] {
                wallets = walletList.compactMap { item -> WalletInfo? in
                    guard case .dictionary(let w) = item else { return nil }
                    return WalletInfo(
                        label: w["label"]?.stringValue ?? "Wallet",
                        address: w["address"]?.stringValue ?? "",
                        chainName: w["chain"]?.stringValue ?? "Base",
                        balance: w["balance"]?.stringValue ?? ""
                    )
                }
            } else if let addr = d["wallet_address"]?.stringValue {
                wallets = [WalletInfo(label: "Primary", address: addr)]
            }
        } else {
            displayName = "MTRX User"
            didIdentifier = nil
            wallets = []
        }
    }

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

// MARK: - Main View

struct AccountView: View {
    @StateObject private var viewModel = AccountViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading account...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.displayName.isEmpty {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .navigationTitle("Account")
            .task {
                await viewModel.loadAccount()
            }
            .refreshable {
                await viewModel.loadAccount()
            }
            .alert("Sign Out", isPresented: $viewModel.showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    viewModel.signOut()
                    appState.isAuthenticated = false
                }
            } message: {
                Text("Are you sure you want to sign out? You will need to re-authenticate to access your account.")
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                identityCard
                walletsSection
                navigationSection
                signOutSection
            }
            .padding()
        }
    }

    // MARK: - Identity Card

    private var identityCard: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(LinearGradient.mtrxPrimary)
                .frame(width: 72, height: 72)
                .overlay {
                    Text(viewModel.avatarInitial.isEmpty ? "M" : viewModel.avatarInitial)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                }

            Text(viewModel.displayName)
                .font(.title2).bold()

            if let did = viewModel.didIdentifier {
                HStack(spacing: 4) {
                    Image(systemName: Symbols.verified)
                        .foregroundStyle(.statusSuccess)
                        .font(.caption)
                    Text(did)
                        .font(.caption).monospaced()
                        .foregroundColor(.labelSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.statusSuccess.opacity(0.08))
                .cornerRadius(8)
            }

            if !viewModel.joinDate.isEmpty {
                Text("Joined \(viewModel.joinDate)")
                    .font(.caption)
                    .foregroundStyle(.labelTertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    // MARK: - Wallets

    private var walletsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Wallets", systemImage: Symbols.wallet)
                .font(.headline)

            if viewModel.wallets.isEmpty {
                Text("No wallets connected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.wallets) { wallet in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wallet.label)
                                .font(.subheadline.weight(.medium))
                            Text(wallet.chainName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(truncatedAddress(wallet.address))
                                .monospaced().font(.caption)
                            if !wallet.balance.isEmpty {
                                Text(wallet.balance)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            UIPasteboard.general.string = wallet.address
                        } label: {
                            Image(systemName: Symbols.copy)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                WalletView()
            } label: {
                accountRow(icon: Symbols.portfolio, title: "Wallet & Portfolio", color: .statusInfo)
            }

            Divider().padding(.leading, 44)

            NavigationLink {
                SettingsView()
            } label: {
                accountRow(icon: Symbols.settings, title: "Settings", color: .labelSecondary)
            }

            Divider().padding(.leading, 44)

            NavigationLink {
                PrivacyView()
            } label: {
                accountRow(icon: Symbols.privacy, title: "Privacy Controls", color: .statusWarning)
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    private func accountRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: Symbols.forward)
                .font(.caption)
                .foregroundStyle(.labelTertiary)
        }
        .padding()
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Button(role: .destructive) {
            viewModel.showSignOutConfirm = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Could Not Load Account")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadAccount() }
            } label: {
                Label("Retry", systemImage: Symbols.refresh)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func truncatedAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

#Preview("Account") {
    AccountView()
        .environmentObject(AppState())
}
