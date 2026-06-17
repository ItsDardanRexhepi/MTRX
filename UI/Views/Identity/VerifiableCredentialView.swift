// VerifiableCredentialView.swift
// MTRX
//
// Credentials wallet — issue, verify, and share verifiable credentials.

import SwiftUI

// MARK: - View Model

final class VerifiableCredentialViewModel: ObservableObject {

    // MARK: - Published State

    @Published var credentials: [CredentialUIModel] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isDemo: Bool = false
    @Published var isEmpty: Bool = false

    // Issue Form
    @Published var issueRecipient: String = ""
    @Published var issueType: String = "Identity"
    @Published var issueClaims: [ClaimPair] = [ClaimPair()]
    @Published var issueExpiry: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @Published var isIssuing: Bool = false
    @Published var issueSuccess: Bool = false

    // Verify
    @Published var verifyInput: String = ""
    @Published var isVerifying: Bool = false
    @Published var verificationResult: CredentialVerification?

    // Share
    @Published var showShareSheet: Bool = false
    @Published var sharePayload: String = ""

    // MARK: - Credential Types

    let credentialTypes = ["Identity", "Education", "Employment", "Membership", "Certification", "Financial", "Health"]

    // MARK: - Load

    func loadCredentials() async {
        isLoading = true
        errorMessage = nil

        // Live credentials from VerifiableCredentialService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let live = try await VerifiableCredentialService.shared.getCredentials(address: address)
                credentials = live.map { c in
                    CredentialUIModel(
                        id: c.id, issuer: c.issuerDID, recipient: c.subjectDID, type: c.type,
                        claims: c.claims, issuedDate: c.issuanceDate,
                        expiryDate: c.expirationDate ?? c.issuanceDate,
                        status: CredentialUIModel.CredentialStatus(rawValue: c.status.capitalized) ?? .valid
                    )
                }
                isEmpty = credentials.isEmpty
                isDemo = false
                isLoading = false
                return
            } catch {
                // This screen renders an error view when errorMessage is set; fall
                // through to labeled demo data silently rather than blocking it.
            }
        }

        errorMessage = nil
        try? await Task.sleep(for: .milliseconds(800))
        credentials = CredentialUIModel.sampleData
        isEmpty = credentials.isEmpty
        isDemo = true
        isLoading = false
    }

    // MARK: - Issue

    func issueCredential() {
        guard !issueRecipient.isEmpty else {
            errorMessage = "Recipient address is required."
            return
        }
        isIssuing = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let newCred = CredentialUIModel(
                id: UUID().uuidString,
                issuer: "did:mtrx:self",
                recipient: self.issueRecipient,
                type: self.issueType,
                claims: Dictionary(uniqueKeysWithValues: self.issueClaims.filter { !$0.key.isEmpty }.map { ($0.key, $0.value) }),
                issuedDate: Date(),
                expiryDate: self.issueExpiry,
                status: .valid
            )
            self.credentials.insert(newCred, at: 0)
            self.isEmpty = false
            self.isIssuing = false
            self.issueSuccess = true
            self.resetIssueForm()
        }
    }

    // MARK: - Verify

    func verifyCredential() {
        guard !verifyInput.isEmpty else {
            errorMessage = "Paste a credential to verify."
            return
        }
        isVerifying = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.verificationResult = CredentialVerification(
                isValid: true,
                issuer: "did:mtrx:0x1a2b...9z",
                subject: "did:mtrx:0xfe32...7d",
                type: "Identity",
                claims: ["name": "Verified User", "country": "US"],
                issuedDate: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(),
                expiryDate: Calendar.current.date(byAdding: .month, value: 9, to: Date()) ?? Date()
            )
            self.isVerifying = false
        }
    }

    // MARK: - Share

    func shareCredential(_ credential: CredentialUIModel) {
        sharePayload = "mtrx://credential/\(credential.id)?issuer=\(credential.issuer)&type=\(credential.type)"
        showShareSheet = true
    }

    // MARK: - Helpers

    func addClaim() {
        issueClaims.append(ClaimPair())
    }

    func removeClaim(at index: Int) {
        guard issueClaims.count > 1 else { return }
        issueClaims.remove(at: index)
    }

    private func resetIssueForm() {
        issueRecipient = ""
        issueType = "Identity"
        issueClaims = [ClaimPair()]
        issueExpiry = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    }
}

// MARK: - Models

struct CredentialUIModel: Identifiable {
    let id: String
    let issuer: String
    let recipient: String
    let type: String
    let claims: [String: String]
    let issuedDate: Date
    let expiryDate: Date
    let status: CredentialStatus

    enum CredentialStatus: String {
        case valid = "Valid"
        case expired = "Expired"
        case revoked = "Revoked"

        var color: Color {
            switch self {
            case .valid: return .green
            case .expired: return .orange
            case .revoked: return .red
            }
        }

        var icon: String {
            switch self {
            case .valid: return "checkmark.seal.fill"
            case .expired: return "clock.badge.exclamationmark"
            case .revoked: return "xmark.seal.fill"
            }
        }
    }

    static var sampleData: [CredentialUIModel] {
        [
            CredentialUIModel(id: "vc-001", issuer: "did:mtrx:0x1a2b...9z", recipient: "did:mtrx:self", type: "Identity", claims: ["name": "User", "country": "US"], issuedDate: Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date(), status: .valid),
            CredentialUIModel(id: "vc-002", issuer: "did:mtrx:0xaa11...bb", recipient: "did:mtrx:self", type: "Education", claims: ["degree": "B.S. Computer Science", "institution": "MIT"], issuedDate: Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .year, value: 8, to: Date()) ?? Date(), status: .valid),
            CredentialUIModel(id: "vc-003", issuer: "did:mtrx:0xcc22...dd", recipient: "did:mtrx:self", type: "Membership", claims: ["org": "DeFi Alliance", "tier": "Gold"], issuedDate: Calendar.current.date(byAdding: .month, value: -14, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date(), status: .expired),
        ]
    }
}

struct ClaimPair: Identifiable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
}

struct CredentialVerification {
    let isValid: Bool
    let issuer: String
    let subject: String
    let type: String
    let claims: [String: String]
    let issuedDate: Date
    let expiryDate: Date
}

// MARK: - View

struct VerifiableCredentialView: View {
    @StateObject private var viewModel = VerifiableCredentialViewModel()
    @State private var selectedTab: CredentialTab = .wallet
    @State private var showQRScanner = false

    private let accentColor = Color(red: 0.0, green: 0.675, blue: 0.694)

    enum CredentialTab: String, CaseIterable {
        case wallet = "Wallet"
        case issue = "Issue"
        case verify = "Verify"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                tabContent
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Credentials")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.loadCredentials() }
            .alert("Success", isPresented: $viewModel.issueSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Credential issued successfully.")
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                ShareSheet(items: [viewModel.sharePayload])
            }
            .fullScreenCover(isPresented: $showQRScanner) {
                QRScannerSheet(title: "Scan Credential") { scanned in
                    viewModel.verifyInput = scanned
                    selectedTab = .verify
                }
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(CredentialTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .wallet:
            walletSection
        case .issue:
            issueSection
        case .verify:
            verifySection
        }
    }

    // MARK: - Wallet

    private var walletSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading credentials...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isEmpty {
                ContentUnavailableView("No Credentials", systemImage: "wallet.pass", description: Text("Your verifiable credentials will appear here."))
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                credentialsList
            }
        }
    }

    private var credentialsList: some View {
        List {
            ForEach(viewModel.credentials) { credential in
                credentialRow(credential)
                    .swipeActions(edge: .trailing) {
                        Button {
                            viewModel.shareCredential(credential)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(accentColor)
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func credentialRow(_ credential: CredentialUIModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: credential.status.icon)
                    .foregroundStyle(credential.status.color)
                    .font(.title3)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(credential.type)
                        .font(.mtrxHeadline)
                    Text("Issuer: \(credential.issuer)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(credential.status.rawValue)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(credential.status.color)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(credential.status.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            Divider()

            HStack {
                Label {
                    Text("Issued: \(credential.issuedDate, format: .dateTime.month().day().year())")
                        .font(.mtrxCaption1)
                } icon: {
                    Image(systemName: "calendar")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Spacer()

                Label {
                    Text("Expires: \(credential.expiryDate, format: .dateTime.month().day().year())")
                        .font(.mtrxCaption1)
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            if !credential.claims.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(Array(credential.claims.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key.capitalized)
                                .font(.mtrxCaption1)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(credential.claims[key] ?? "")
                                .font(.mtrxCaptionBold)
                        }
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Issue

    private var issueSection: some View {
        Form {
            Section("Recipient") {
                TextField("0x... or DID", text: $viewModel.issueRecipient)
                    .font(.mtrxMono)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section("Credential Type") {
                Picker("Type", selection: $viewModel.issueType) {
                    ForEach(viewModel.credentialTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
            }

            Section("Claims") {
                ForEach(Array(viewModel.issueClaims.enumerated()), id: \.element.id) { index, _ in
                    HStack(spacing: Spacing.sm) {
                        TextField("Key", text: $viewModel.issueClaims[index].key)
                            .font(.mtrxBody)
                        TextField("Value", text: $viewModel.issueClaims[index].value)
                            .font(.mtrxBody)
                        if viewModel.issueClaims.count > 1 {
                            Button {
                                viewModel.removeClaim(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    viewModel.addClaim()
                } label: {
                    Label("Add Claim", systemImage: "plus.circle")
                        .foregroundStyle(accentColor)
                }
            }

            Section("Expiry") {
                DatePicker("Expires", selection: $viewModel.issueExpiry, in: Date()..., displayedComponents: .date)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.mtrxFootnote)
                }
            }

            Section {
                Button {
                    viewModel.issueCredential()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isIssuing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Issue Credential")
                                .font(.mtrxHeadline)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                }
                .disabled(viewModel.isIssuing)
                .listRowInsets(EdgeInsets())
                .padding(Spacing.contentPadding)
            }
        }
    }

    // MARK: - Verify

    private var verifySection: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Paste Credential")
                        .font(.mtrxHeadline)

                    TextEditor(text: $viewModel.verifyInput)
                        .font(.mtrxMonoSmall)
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm)
                                .stroke(Color(.separator), lineWidth: 1)
                        )

                    HStack(spacing: Spacing.sm) {
                        Button {
                            viewModel.verifyCredential()
                        } label: {
                            HStack {
                                if viewModel.isVerifying {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                    Text("Verify")
                                }
                            }
                            .font(.mtrxHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.buttonVertical)
                            .background(accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                        .disabled(viewModel.isVerifying)

                        Button {
                            showQRScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .foregroundStyle(accentColor)
                                .frame(width: Spacing.Size.buttonHeight, height: Spacing.Size.buttonHeight)
                                .background(accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                    }
                }
                .mtrxCardStyle()

                if let result = viewModel.verificationResult {
                    verificationResultCard(result)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.mtrxFootnote)
                        .padding()
                }
            }
            .padding(Spacing.contentPadding)
        }
    }

    private func verificationResultCard(_ result: CredentialVerification) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: result.isValid ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(result.isValid ? .green : .red)
                Text(result.isValid ? "Valid Credential" : "Invalid Credential")
                    .font(.mtrxTitle3)
            }

            Divider()

            Group {
                infoRow(label: "Issuer", value: result.issuer)
                infoRow(label: "Subject", value: result.subject)
                infoRow(label: "Type", value: result.type)
                infoRow(label: "Issued", value: result.issuedDate.formatted(date: .abbreviated, time: .omitted))
                infoRow(label: "Expires", value: result.expiryDate.formatted(date: .abbreviated, time: .omitted))
            }

            if !result.claims.isEmpty {
                Divider()
                Text("Claims")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(.secondary)
                ForEach(Array(result.claims.keys.sorted()), id: \.self) { key in
                    infoRow(label: key.capitalized, value: result.claims[key] ?? "")
                }
            }
        }
        .mtrxCardStyle()
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mtrxCaption1)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.mtrxMono)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Preview

#Preview {
    VerifiableCredentialView()
}
