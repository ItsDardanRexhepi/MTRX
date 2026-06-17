// KYCView.swift
// MTRX
//
// KYC verification — privacy-preserving identity proofs with zero-knowledge sharing.

import SwiftUI

// MARK: - View Model

final class KYCViewModel: ObservableObject {

    // MARK: - Published State

    @Published var badges: [KYCBadge] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isEmpty: Bool = false

    // Verification Flow
    @Published var selectedVerificationType: VerificationType = .ageVerification
    @Published var isCapturing: Bool = false
    @Published var captureStep: CaptureStep = .instructions

    // ZK Proof
    @Published var isGeneratingProof: Bool = false
    @Published var generatedProofID: String?
    @Published var proofProgress: Double = 0.0

    // Sharing
    @Published var sharedServices: [ServiceShare] = []

    enum CaptureStep {
        case instructions
        case capturing
        case processing
        case complete
    }

    // MARK: - Types

    let verificationTypes: [VerificationType] = VerificationType.allCases

    // MARK: - Load

    func loadBadges() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.badges = KYCBadge.sampleData
            self.sharedServices = ServiceShare.sampleData
            self.isEmpty = self.badges.isEmpty
            self.isLoading = false
        }
    }

    // MARK: - Initiate Verification

    func startVerification() {
        isCapturing = true
        captureStep = .instructions
    }

    func captureDocument() {
        captureStep = .capturing

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            self.captureStep = .processing

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.captureStep = .complete

                let newBadge = KYCBadge(
                    type: self.selectedVerificationType,
                    status: .verified,
                    verifiedDate: Date(),
                    expiryDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
                )
                self.badges.insert(newBadge, at: 0)
                self.isEmpty = false
            }
        }
    }

    func dismissCapture() {
        isCapturing = false
        captureStep = .instructions
    }

    // MARK: - ZK Proof

    func generateZKProof() {
        isGeneratingProof = true
        proofProgress = 0.0
        generatedProofID = nil

        simulateProofProgress()
    }

    private func simulateProofProgress() {
        guard proofProgress < 1.0 else {
            isGeneratingProof = false
            // Clearly-labelled demo id (no real prover on-device — see PrivacyManager).
            generatedProofID = "zk-demo-" + String(DemoArtifacts.hash(seed: "kyc-proof").dropFirst(2).prefix(10))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            self.proofProgress = min(self.proofProgress + Double.random(in: 0.05...0.15), 1.0)
            self.simulateProofProgress()
        }
    }

    // MARK: - Share Toggle

    func toggleServiceShare(serviceID: String) {
        if let index = sharedServices.firstIndex(where: { $0.id == serviceID }) {
            sharedServices[index].isShared.toggle()
        }
    }

    // MARK: - Revoke

    func revokeAccess(for serviceID: String) {
        if let index = sharedServices.firstIndex(where: { $0.id == serviceID }) {
            sharedServices[index].isShared = false
        }
    }

    func revokeAllAccess() {
        for index in sharedServices.indices {
            sharedServices[index].isShared = false
        }
    }
}

// MARK: - Models

enum VerificationType: String, CaseIterable, Identifiable {
    case ageVerification = "Age Verification"
    case accreditedInvestor = "Accredited Investor"
    case identityProof = "Identity Proof"
    case residency = "Residency"
    case sanctionsCheck = "Sanctions Check"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ageVerification: return "person.badge.shield.checkmark"
        case .accreditedInvestor: return "chart.bar.doc.horizontal"
        case .identityProof: return "person.text.rectangle"
        case .residency: return "house.and.flag"
        case .sanctionsCheck: return "shield.checkered"
        }
    }

    var instructions: String {
        switch self {
        case .ageVerification: return "Position your government-issued ID within the frame. Ensure all text is clearly visible."
        case .accreditedInvestor: return "Upload financial documentation proving accredited investor status."
        case .identityProof: return "Take a selfie matching your government ID photo. Good lighting recommended."
        case .residency: return "Provide a utility bill or bank statement showing your current address."
        case .sanctionsCheck: return "Provide your full legal name for automated sanctions screening."
        }
    }
}

struct KYCBadge: Identifiable {
    let id = UUID()
    let type: VerificationType
    let status: BadgeStatus
    let verifiedDate: Date
    let expiryDate: Date

    enum BadgeStatus: String {
        case verified = "Verified"
        case pending = "Pending"
        case expired = "Expired"
        case rejected = "Rejected"

        var color: Color {
            switch self {
            case .verified: return .green
            case .pending: return .orange
            case .expired: return .gray
            case .rejected: return .red
            }
        }

        var icon: String {
            switch self {
            case .verified: return "checkmark.seal.fill"
            case .pending: return "clock.fill"
            case .expired: return "calendar.badge.exclamationmark"
            case .rejected: return "xmark.seal.fill"
            }
        }
    }

    static var sampleData: [KYCBadge] {
        [
            KYCBadge(type: .ageVerification, status: .verified, verifiedDate: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .month, value: 9, to: Date()) ?? Date()),
            KYCBadge(type: .accreditedInvestor, status: .verified, verifiedDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .month, value: 11, to: Date()) ?? Date()),
            KYCBadge(type: .sanctionsCheck, status: .pending, verifiedDate: Date(), expiryDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()),
        ]
    }
}

struct ServiceShare: Identifiable {
    let id: String
    let name: String
    let icon: String
    var isShared: Bool
    let sharedSince: Date?

    static var sampleData: [ServiceShare] {
        [
            ServiceShare(id: "svc-1", name: "Uniswap", icon: "arrow.triangle.swap", isShared: true, sharedSince: Calendar.current.date(byAdding: .month, value: -2, to: Date())),
            ServiceShare(id: "svc-2", name: "Aave", icon: "building.columns", isShared: true, sharedSince: Calendar.current.date(byAdding: .month, value: -1, to: Date())),
            ServiceShare(id: "svc-3", name: "Compound", icon: "chart.line.uptrend.xyaxis", isShared: false, sharedSince: nil),
            ServiceShare(id: "svc-4", name: "MakerDAO", icon: "dollarsign.circle", isShared: false, sharedSince: nil),
        ]
    }
}

// MARK: - View

struct KYCView: View {
    @StateObject private var viewModel = KYCViewModel()

    private let accentColor = Color(red: 0.0, green: 0.675, blue: 0.694)

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading verification status...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    mainContent
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("KYC Verification")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { viewModel.loadBadges() }
            .sheet(isPresented: $viewModel.isCapturing) {
                captureFlowSheet
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                badgesSection
                verificationSection
                zkProofSection
                sharingSection
            }
            .padding(Spacing.contentPadding)
        }
    }

    // MARK: - Badges

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Status Badges")
                .font(.mtrxTitle3)

            if viewModel.isEmpty {
                HStack {
                    Image(systemName: "shield.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No verifications yet. Start your first verification below.")
                        .font(.mtrxSubheadline)
                        .foregroundStyle(.secondary)
                }
                .mtrxCardStyle()
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                    ForEach(viewModel.badges) { badge in
                        badgeCard(badge)
                    }
                }
            }
        }
    }

    private func badgeCard(_ badge: KYCBadge) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: badge.status.icon)
                .font(.title)
                .foregroundStyle(badge.status.color)

            Text(badge.type.rawValue)
                .font(.mtrxCaptionBold)
                .multilineTextAlignment(.center)

            Text(badge.status.rawValue)
                .font(.mtrxCaption2)
                .foregroundStyle(badge.status.color)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
                .background(badge.status.color.opacity(0.12))
                .clipShape(Capsule())

            Text("Exp: \(badge.expiryDate, format: .dateTime.month().year())")
                .font(.mtrxCaption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.md)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }

    // MARK: - Initiate Verification

    private var verificationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Initiate Verification")
                .font(.mtrxTitle3)

            Picker("Verification Type", selection: $viewModel.selectedVerificationType) {
                ForEach(viewModel.verificationTypes) { type in
                    Label(type.rawValue, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.menu)
            .mtrxCardStyle()

            Button {
                viewModel.startVerification()
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Start \(viewModel.selectedVerificationType.rawValue)")
                }
                .font(.mtrxHeadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.buttonVertical)
                .background(accentColor)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
            }
        }
    }

    // MARK: - Capture Flow Sheet

    private var captureFlowSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                Spacer()

                switch viewModel.captureStep {
                case .instructions:
                    VStack(spacing: Spacing.lg) {
                        Image(systemName: viewModel.selectedVerificationType.icon)
                            .font(.system(size: 60))
                            .foregroundStyle(accentColor)

                        Text(viewModel.selectedVerificationType.rawValue)
                            .font(.mtrxTitle2)

                        Text(viewModel.selectedVerificationType.instructions)
                            .font(.mtrxBody)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)

                        Button {
                            viewModel.captureDocument()
                        } label: {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Begin Capture")
                            }
                            .font(.mtrxHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.buttonVertical)
                            .background(accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                        .padding(.horizontal, Spacing.xl)
                    }

                case .capturing:
                    VStack(spacing: Spacing.lg) {
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg)
                            .strokeBorder(accentColor, lineWidth: 3)
                            .frame(width: 280, height: 180)
                            .overlay(
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 50))
                                    .foregroundStyle(accentColor)
                            )

                        Text("Scanning document...")
                            .font(.mtrxHeadline)

                        ProgressView()
                            .tint(accentColor)
                    }

                case .processing:
                    VStack(spacing: Spacing.lg) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(accentColor)
                        Text("Processing verification...")
                            .font(.mtrxHeadline)
                        Text("This may take a moment.")
                            .font(.mtrxSubheadline)
                            .foregroundStyle(.secondary)
                    }

                case .complete:
                    VStack(spacing: Spacing.lg) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        Text("Verification Complete")
                            .font(.mtrxTitle2)
                        Text("\(viewModel.selectedVerificationType.rawValue) has been verified successfully.")
                            .font(.mtrxBody)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Done") {
                            viewModel.dismissCapture()
                        }
                        .font(.mtrxHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.buttonVertical)
                        .background(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        .padding(.horizontal, Spacing.xl)
                    }
                }

                Spacer()
            }
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.dismissCapture() }
                }
            }
        }
    }

    // MARK: - ZK Proof

    private var zkProofSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Zero-Knowledge Proof")
                .font(.mtrxTitle3)

            VStack(spacing: Spacing.md) {
                if viewModel.isGeneratingProof {
                    VStack(spacing: Spacing.sm) {
                        ProgressView(value: viewModel.proofProgress)
                            .tint(accentColor)
                        Text("Generating your privacy proof...")
                            .font(.mtrxSubheadline)
                            .foregroundStyle(.secondary)
                        Text("\(Int(viewModel.proofProgress * 100))%")
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(accentColor)
                    }
                } else if let proofID = viewModel.generatedProofID {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text("Proof Generated")
                                .font(.mtrxCaptionBold)
                            Text(proofID)
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = proofID
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(accentColor)
                        }
                    }
                } else {
                    Text("Generate a ZK proof to share your verification status without revealing personal data.")
                        .font(.mtrxSubheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.generateZKProof()
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("Generate ZK Proof")
                    }
                    .font(.mtrxHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.buttonVertical)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                }
                .disabled(viewModel.isGeneratingProof || viewModel.badges.filter { $0.status == .verified }.isEmpty)
            }
            .mtrxCardStyle()
        }
    }

    // MARK: - Sharing

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Share Proof")
                    .font(.mtrxTitle3)
                Spacer()
                Button("Revoke All") {
                    viewModel.revokeAllAccess()
                }
                .font(.mtrxCaptionBold)
                .foregroundStyle(.red)
            }

            VStack(spacing: 0) {
                ForEach(viewModel.sharedServices) { service in
                    HStack {
                        Image(systemName: service.icon)
                            .font(.title3)
                            .frame(width: 32)
                            .foregroundStyle(accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name)
                                .font(.mtrxHeadline)
                            if let since = service.sharedSince, service.isShared {
                                Text("Shared since \(since, format: .dateTime.month().year())")
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { service.isShared },
                            set: { _ in viewModel.toggleServiceShare(serviceID: service.id) }
                        ))
                        .tint(accentColor)
                        .labelsHidden()
                    }
                    .padding(.vertical, Spacing.sm)

                    if service.id != viewModel.sharedServices.last?.id {
                        Divider()
                    }
                }
            }
            .mtrxCardStyle()
        }
    }
}

// MARK: - Preview

#Preview {
    KYCView()
}
