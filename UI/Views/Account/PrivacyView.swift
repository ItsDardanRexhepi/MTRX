// PrivacyView.swift
// MTRX - Component 29 privacy controls: zero-knowledge commitments, credential visibility,
//        social profile, wallet linking, data sharing, commitment history
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Models

enum ProfileVisibility: String, CaseIterable {
    case public_ = "Public"
    case connections = "Connections Only"
    case private_ = "Private"
}

enum PrivacyLevel: String, CaseIterable {
    case standard = "Standard"
    case enhanced = "Enhanced"
    case maximum = "Maximum"

    var description: String {
        switch self {
        case .standard: return "Basic on-chain privacy. Transactions and balances are visible on the explorer."
        case .enhanced: return "Zero-knowledge proofs for transaction amounts. Addresses remain visible."
        case .maximum: return "Full ZK shielding. Transactions, amounts, and addresses are privacy-protected."
        }
    }

    var icon: String {
        switch self {
        case .standard: return Symbols.shield
        case .enhanced: return Symbols.zeroKnowledge
        case .maximum: return Symbols.encrypted
        }
    }

    var color: Color {
        switch self {
        case .standard: return .statusInfo
        case .enhanced: return .statusWarning
        case .maximum: return .statusSuccess
        }
    }
}

struct CredentialEntry: Identifiable, Equatable {
    let id: String
    let name: String
    var isVisible: Bool
    let issuer: String
    let issuedAt: String

    init(id: String = UUID().uuidString, name: String, isVisible: Bool, issuer: String = "", issuedAt: String = "") {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.issuer = issuer
        self.issuedAt = issuedAt
    }
}

struct ZKCommitment: Identifiable, Equatable {
    let id: String
    let type: String
    let description: String
    let timestamp: String
    let status: String
    let proofHash: String
}

struct DataSharingPreference: Identifiable {
    let id: String
    let category: String
    var isShared: Bool
    let description: String
}

// MARK: - ViewModel

@MainActor
final class PrivacyViewModel: ObservableObject {
    @Published var credentials: [CredentialEntry] = []
    @Published var profileVisibility: ProfileVisibility = .connections
    @Published var showLinkedWallets = false
    @Published var storeTrinityHistory = true
    @Published var showDeletionAlert = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var privacyLevel: PrivacyLevel = .standard
    @Published var commitments: [ZKCommitment] = []
    @Published var dataSharingPreferences: [DataSharingPreference] = []
    @Published var isGeneratingProof = false
    @Published var isSaving = false

    private let api = MTRXAPIClient.shared

    func loadPrivacySettings() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: [String: AnyCodableValue] = try await api.getPrivacySettings()
            parseSettings(response)
        } catch {
            errorMessage = "Failed to load privacy settings: \(error.localizedDescription)"
        }
    }

    func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let settings: [String: AnyCodableValue] = [
                "profile_visibility": .string(profileVisibility.rawValue),
                "show_linked_wallets": .bool(showLinkedWallets),
                "store_trinity_history": .bool(storeTrinityHistory),
                "privacy_level": .string(privacyLevel.rawValue),
            ]
            let _: [String: AnyCodableValue] = try await api.updatePrivacySettings(settings: settings)
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    func setCredentialVisibility(_ id: String, visible: Bool) {
        if let idx = credentials.firstIndex(where: { $0.id == id }) {
            credentials[idx] = CredentialEntry(
                id: id,
                name: credentials[idx].name,
                isVisible: visible,
                issuer: credentials[idx].issuer,
                issuedAt: credentials[idx].issuedAt
            )
        }
        Task { await saveSettings() }
    }

    func generateZKProof(type: String, claims: [String: String]) async {
        isGeneratingProof = true
        defer { isGeneratingProof = false }

        do {
            var claimsDict: [String: AnyCodableValue] = [:]
            for (k, v) in claims { claimsDict[k] = .string(v) }
            let request = PrivacyProofRequest(proofType: type, claims: claimsDict)
            let _: [String: AnyCodableValue] = try await api.generatePrivacyProof(request)
            await loadCommitments()
        } catch {
            errorMessage = "Failed to generate proof: \(error.localizedDescription)"
        }
    }

    func loadCommitments() async {
        do {
            let response: [String: AnyCodableValue] = try await api.get(path: "/api/v1/privacy/commitments")
            commitments = parseCommitments(response)
        } catch {
            // Non-fatal
        }
    }

    func clearHistory() {
        Task {
            do {
                let _: [String: AnyCodableValue] = try await api.postRaw(
                    path: "/api/v1/privacy/clear-history",
                    body: ["type": "trinity_conversations"]
                )
            } catch {
                errorMessage = "Failed to clear history: \(error.localizedDescription)"
            }
        }
    }

    func deleteOffChainData() {
        Task {
            do {
                let _: [String: AnyCodableValue] = try await api.postRaw(
                    path: "/api/v1/privacy/delete-data",
                    body: ["scope": "off_chain"]
                )
            } catch {
                errorMessage = "Failed to delete data: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Parsing

    private func parseSettings(_ response: [String: AnyCodableValue]) {
        if case .dictionary(let d) = response["settings"] ?? response["data"] ?? .dictionary(response) {
            if let vis = d["profile_visibility"]?.stringValue,
               let pv = ProfileVisibility.allCases.first(where: { $0.rawValue == vis }) {
                profileVisibility = pv
            }
            showLinkedWallets = d["show_linked_wallets"]?.boolValue ?? false
            storeTrinityHistory = d["store_trinity_history"]?.boolValue ?? true

            if let level = d["privacy_level"]?.stringValue,
               let pl = PrivacyLevel.allCases.first(where: { $0.rawValue == level }) {
                privacyLevel = pl
            }

            if case .array(let credList) = d["credentials"] {
                credentials = credList.compactMap { item -> CredentialEntry? in
                    guard case .dictionary(let c) = item else { return nil }
                    return CredentialEntry(
                        id: c["id"]?.stringValue ?? UUID().uuidString,
                        name: c["name"]?.stringValue ?? "",
                        isVisible: c["is_visible"]?.boolValue ?? true,
                        issuer: c["issuer"]?.stringValue ?? "",
                        issuedAt: c["issued_at"]?.stringValue ?? ""
                    )
                }
            }

            if case .array(let sharingList) = d["data_sharing"] {
                dataSharingPreferences = sharingList.compactMap { item -> DataSharingPreference? in
                    guard case .dictionary(let s) = item else { return nil }
                    return DataSharingPreference(
                        id: s["id"]?.stringValue ?? UUID().uuidString,
                        category: s["category"]?.stringValue ?? "",
                        isShared: s["is_shared"]?.boolValue ?? false,
                        description: s["description"]?.stringValue ?? ""
                    )
                }
            }
        }
    }

    private func parseCommitments(_ response: [String: AnyCodableValue]) -> [ZKCommitment] {
        guard case .array(let items) = response["commitments"] ?? response["data"] ?? .null else {
            return []
        }
        return items.compactMap { item -> ZKCommitment? in
            guard case .dictionary(let d) = item else { return nil }
            return ZKCommitment(
                id: d["id"]?.stringValue ?? UUID().uuidString,
                type: d["type"]?.stringValue ?? "",
                description: d["description"]?.stringValue ?? "",
                timestamp: d["timestamp"]?.stringValue ?? "",
                status: d["status"]?.stringValue ?? "verified",
                proofHash: d["proof_hash"]?.stringValue ?? ""
            )
        }
    }
}

// MARK: - Main View

struct PrivacyView: View {
    @StateObject private var viewModel = PrivacyViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading privacy settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.credentials.isEmpty && viewModel.dataSharingPreferences.isEmpty {
                errorView(error)
            } else {
                settingsForm
            }
        }
        .navigationTitle("Privacy")
        .alert("Delete Off-Chain Data?", isPresented: $viewModel.showDeletionAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { viewModel.deleteOffChainData() }
        } message: {
            Text("This removes all locally stored preferences, Trinity memory, and cloud backups. On-chain records remain permanently.")
        }
        .task {
            await viewModel.loadPrivacySettings()
            await viewModel.loadCommitments()
        }
    }

    // MARK: - Settings Form

    private var settingsForm: some View {
        Form {
            privacyLevelSection
            credentialVisibilitySection
            dataSharingSection
            socialProfileSection
            walletLinkingSection
            agentSection
            zkCommitmentsSection
            dataDeletionSection
        }
        .refreshable {
            await viewModel.loadPrivacySettings()
        }
    }

    // MARK: - Privacy Level

    private var privacyLevelSection: some View {
        Section("Privacy Level") {
            ForEach(PrivacyLevel.allCases, id: \.self) { level in
                Button {
                    viewModel.privacyLevel = level
                    Task { await viewModel.saveSettings() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: level.icon)
                            .foregroundStyle(level.color)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(level.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if viewModel.privacyLevel == level {
                            Image(systemName: Symbols.complete)
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Credential Visibility

    private var credentialVisibilitySection: some View {
        Section("Credential Visibility") {
            if viewModel.credentials.isEmpty {
                Text("No credentials found")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.credentials) { cred in
                    Toggle(isOn: Binding(
                        get: { cred.isVisible },
                        set: { viewModel.setCredentialVisibility(cred.id, visible: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cred.name)
                            if !cred.issuer.isEmpty {
                                Text("Issued by \(cred.issuer)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Sharing

    private var dataSharingSection: some View {
        Section("Data Sharing Preferences") {
            if viewModel.dataSharingPreferences.isEmpty {
                Text("No configurable data sharing options")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($viewModel.dataSharingPreferences) { $pref in
                    Toggle(isOn: $pref.isShared) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pref.category)
                            Text(pref.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: pref.isShared) { _, _ in
                        Task { await viewModel.saveSettings() }
                    }
                }
            }
        }
    }

    // MARK: - Social Profile

    private var socialProfileSection: some View {
        Section("Social Profile") {
            Picker("Profile Visibility", selection: $viewModel.profileVisibility) {
                ForEach(ProfileVisibility.allCases, id: \.self) { vis in
                    Text(vis.rawValue).tag(vis)
                }
            }
            .onChange(of: viewModel.profileVisibility) { _, _ in
                Task { await viewModel.saveSettings() }
            }
        }
    }

    // MARK: - Wallet Linking

    private var walletLinkingSection: some View {
        Section("Wallet Address Linking") {
            Toggle("Show linked wallets on profile", isOn: $viewModel.showLinkedWallets)
                .onChange(of: viewModel.showLinkedWallets) { _, _ in
                    Task { await viewModel.saveSettings() }
                }
            Text("Others can see which wallets belong to you")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Agent Conversations

    private var agentSection: some View {
        Section("Agent Conversations") {
            Toggle("Store Trinity conversation history", isOn: $viewModel.storeTrinityHistory)
                .onChange(of: viewModel.storeTrinityHistory) { _, _ in
                    Task { await viewModel.saveSettings() }
                }
            if viewModel.storeTrinityHistory {
                Button("Clear Conversation History") { viewModel.clearHistory() }
            }
        }
    }

    // MARK: - ZK Commitments

    private var zkCommitmentsSection: some View {
        Section("Zero-Knowledge Commitments") {
            if viewModel.commitments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: Symbols.zeroKnowledge)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No commitments yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("ZK commitments allow you to prove facts about your data without revealing the data itself.")
                        .font(.caption)
                        .foregroundStyle(.labelTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(viewModel.commitments) { commitment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(commitment.type)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(commitment.status)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(commitment.status == "verified" ? Color.statusSuccess.opacity(0.12) : Color.statusWarning.opacity(0.12))
                                .foregroundStyle(commitment.status == "verified" ? .statusSuccess : .statusWarning)
                                .cornerRadius(4)
                        }
                        Text(commitment.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(commitment.timestamp)
                                .font(.caption2)
                                .foregroundStyle(.labelTertiary)
                            Spacer()
                            if !commitment.proofHash.isEmpty {
                                Text(String(commitment.proofHash.prefix(12)) + "...")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.labelTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                Task {
                    await viewModel.generateZKProof(
                        type: "identity_verification",
                        claims: ["claim": "identity_holder"]
                    )
                }
            } label: {
                if viewModel.isGeneratingProof {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Generate New ZK Proof", systemImage: Symbols.zeroKnowledge)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(viewModel.isGeneratingProof)
        }
    }

    // MARK: - Data Deletion

    private var dataDeletionSection: some View {
        Section("Data Deletion") {
            Button(role: .destructive) {
                viewModel.showDeletionAlert = true
            } label: {
                Label("Delete Off-Chain Data", systemImage: Symbols.delete)
            }
            Text("On-chain records (transactions, attestations, contracts) are permanent and cannot be deleted. This deletes only local and cloud-stored data.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Could Not Load Settings")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadPrivacySettings() }
            } label: {
                Label("Retry", systemImage: Symbols.refresh)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Privacy") {
    NavigationStack {
        PrivacyView()
    }
}
