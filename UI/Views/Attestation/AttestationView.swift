// AttestationView.swift
// MTRX
//
// On-chain attestations — received/issued tabs, attestation list, create form, verify by UID.

import SwiftUI

// MARK: - Data Models

struct AttestationItem: Identifiable {
    let id = UUID()
    let uid: String
    let schema: String
    let attester: String
    let recipient: String
    let timestamp: String
    let isRevoked: Bool
}

// MARK: - View Model

@MainActor
class AttestationViewModel: ObservableObject {
    @Published var received: [AttestationItem] = []
    @Published var issued: [AttestationItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showCreate: Bool = false
    @Published var selectedTab: Int = 0
    @Published var isDemo: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM dd, yyyy"; return f
    }()

    // Create form
    @Published var createSchema: String = ""
    @Published var createRecipient: String = ""
    @Published var createFieldKey: String = ""
    @Published var createFieldValue: String = ""
    @Published var isCreating: Bool = false

    // Verify
    @Published var verifyUID: String = ""
    @Published var verifyResult: String?

    var canCreate: Bool {
        !createSchema.trimmingCharacters(in: .whitespaces).isEmpty &&
        !createRecipient.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live from AttestationService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let live = try await AttestationService.shared.getAttestationsForAddress(address: address)
                let items = live.map { a in
                    AttestationItem(
                        uid: a.uid, schema: a.schema, attester: a.attester,
                        recipient: a.recipient,
                        timestamp: Self.dateFormatter.string(from: a.timestamp),
                        isRevoked: a.isRevoked
                    )
                }
                received = items.filter { $0.recipient.lowercased() == address.lowercased() }
                issued = items.filter { $0.attester.lowercased() == address.lowercased() }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live attestations unavailable — showing demo."
            }
        }

        received = AttestationViewModel.sampleReceived
        issued = AttestationViewModel.sampleIssued
        isDemo = true
        isLoading = false
    }

    func createAttestation() async {
        guard canCreate else { return }
        isCreating = true

        do {
            try await Task.sleep(for: .seconds(1))
            let newAttestation = AttestationItem(
                uid: String(DemoArtifacts.hash(seed: "attest|\(createSchema)|\(createRecipient)").prefix(18)),
                schema: createSchema,
                attester: "0x1234...abcd",
                recipient: createRecipient,
                timestamp: "Just now",
                isRevoked: false
            )
            issued.insert(newAttestation, at: 0)
            createSchema = ""
            createRecipient = ""
            createFieldKey = ""
            createFieldValue = ""
            isCreating = false
            showCreate = false
        } catch {
            isCreating = false
        }
    }

    func verifyAttestation() async {
        guard !verifyUID.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        do {
            try await Task.sleep(for: .milliseconds(800))
            let allAttestations = received + issued
            if let found = allAttestations.first(where: { $0.uid == verifyUID }) {
                verifyResult = found.isRevoked ? "Revoked" : "Valid"
            } else {
                verifyResult = "Not Found"
            }
        } catch {
            verifyResult = "Verification failed"
        }
    }

    static let sampleReceived: [AttestationItem] = [
        AttestationItem(uid: "0xa1b2c3d4e5f60001", schema: "KYC Verification", attester: "0x9876...fedc", recipient: "0x1234...abcd", timestamp: "Apr 11, 2026", isRevoked: false),
        AttestationItem(uid: "0xa1b2c3d4e5f60002", schema: "Credit Score", attester: "0x5555...aaaa", recipient: "0x1234...abcd", timestamp: "Mar 28, 2026", isRevoked: false),
        AttestationItem(uid: "0xa1b2c3d4e5f60003", schema: "Membership", attester: "0x7777...bbbb", recipient: "0x1234...abcd", timestamp: "Feb 15, 2026", isRevoked: true)
    ]

    static let sampleIssued: [AttestationItem] = [
        AttestationItem(uid: "0xf6e5d4c3b2a10001", schema: "Skill Badge", attester: "0x1234...abcd", recipient: "0xaaaa...1111", timestamp: "Apr 10, 2026", isRevoked: false),
        AttestationItem(uid: "0xf6e5d4c3b2a10002", schema: "Endorsement", attester: "0x1234...abcd", recipient: "0xbbbb...2222", timestamp: "Apr 5, 2026", isRevoked: false)
    ]
}

// MARK: - Attestation View

struct AttestationView: View {
    @StateObject private var viewModel = AttestationViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.received.isEmpty && viewModel.issued.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.received.isEmpty {
                    errorState(message: error)
                } else {
                    attestationContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Attestations")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showCreate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                    }
                    .accessibilityLabel("Create attestation")
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showCreate) {
                createAttestationSheet
            }
        }
    }

    // MARK: - Content

    private var attestationContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                // Segmented control
                Picker("Tab", selection: $viewModel.selectedTab) {
                    Text("Received").tag(0)
                    Text("Issued").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.contentPadding)

                // Attestation list
                if viewModel.selectedTab == 0 {
                    attestationList(viewModel.received, emptyLabel: "No attestations received yet")
                } else {
                    attestationList(viewModel.issued, emptyLabel: "No attestations issued yet")
                }

                // Verify section
                verifySection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Attestation List

    private func attestationList(_ items: [AttestationItem], emptyLabel: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if items.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.labelTertiary)
                    Text(emptyLabel)
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.xl)
            } else {
                ForEach(items) { attestation in
                    attestationRow(attestation)
                }
            }
        }
    }

    private func attestationRow(_ attestation: AttestationItem) -> some View {
        MtrxCard(style: attestation.isRevoked ? .outlined : .standard) {
            VStack(alignment: .leading, spacing: Spacing.ms) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attestation.schema)
                            .font(.mtrxBodyBold)
                            .foregroundStyle(attestation.isRevoked ? Color.labelTertiary : Color.labelPrimary)
                        Text(attestation.timestamp)
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }

                    Spacer()

                    if attestation.isRevoked {
                        Text("Revoked")
                            .font(.mtrxCaptionBold)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 3)
                            .background(Color.statusError.opacity(0.12))
                            .clipShape(Capsule())
                            .foregroundStyle(Color.statusError)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.statusSuccess)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.xs) {
                        Text("UID:")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(attestation.uid)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    HStack(spacing: Spacing.xs) {
                        Text("Attester:")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(attestation.attester)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.labelSecondary)
                    }

                    HStack(spacing: Spacing.xs) {
                        Text("Recipient:")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                        Text(attestation.recipient)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Verify Section

    private var verifySection: some View {
        MtrxCard(style: .glass, accentEdge: .leading) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Verify Attestation")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Attestation UID")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)

                    HStack {
                        TextField("0x...", text: $viewModel.verifyUID)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(Spacing.ms)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }

                Button {
                    Task { await viewModel.verifyAttestation() }
                } label: {
                    Text("Verify")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(viewModel.verifyUID.isEmpty ? Color.labelTertiary : Color(red: 0.0, green: 0.675, blue: 0.694))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
                .disabled(viewModel.verifyUID.isEmpty)

                if let result = viewModel.verifyResult {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: verifyResultIcon(result))
                            .font(.system(size: 16))
                            .foregroundStyle(verifyResultColor(result))
                        Text("Status: \(result)")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(verifyResultColor(result))
                    }
                    .padding(Spacing.sm)
                    .background(verifyResultColor(result).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Create Attestation Sheet

    private var createAttestationSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Schema
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Schema")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("KYC, Endorsement, Skill Badge...", text: $viewModel.createSchema)
                            .font(.mtrxBody)
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Recipient
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Recipient Address")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("0x...", text: $viewModel.createRecipient)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Custom Field Key
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Field Name (optional)")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("e.g. score, level, name", text: $viewModel.createFieldKey)
                            .font(.mtrxBody)
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Custom Field Value
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Field Value (optional)")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                        TextField("e.g. 95, Gold, Verified", text: $viewModel.createFieldValue)
                            .font(.mtrxBody)
                            .padding(Spacing.ms)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.createAttestation() }
                } label: {
                    Text(viewModel.isCreating ? "Creating..." : "Create Attestation")
                        .font(.mtrxBodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.ms)
                        .background(viewModel.canCreate ? Color(red: 0.0, green: 0.675, blue: 0.694) : Color.labelTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .disabled(!viewModel.canCreate || viewModel.isCreating)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("New Attestation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        viewModel.showCreate = false
                    }
                    .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusWarning)
            Text(message)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.675, blue: 0.694))
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func verifyResultIcon(_ result: String) -> String {
        switch result {
        case "Valid": return "checkmark.seal.fill"
        case "Revoked": return "xmark.seal.fill"
        case "Not Found": return "questionmark.circle.fill"
        default: return "exclamationmark.circle.fill"
        }
    }

    private func verifyResultColor(_ result: String) -> Color {
        switch result {
        case "Valid": return .statusSuccess
        case "Revoked": return .statusError
        case "Not Found": return .statusWarning
        default: return .statusError
        }
    }
}

// MARK: - Preview

#Preview {
    AttestationView()
        .preferredColorScheme(.dark)
}
