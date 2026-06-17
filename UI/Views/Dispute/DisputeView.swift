// DisputeView.swift
// MTRX
//
// DisputeCase resolution — create disputes, view active cases, jury voting, claim winnings.

import SwiftUI

// MARK: - DisputeCase ViewModel

@MainActor
final class DisputeViewModel: ObservableObject {

    // MARK: - Published State

    @Published var activeDisputes: [DisputeCase] = []
    @Published var juryCases: [DisputeCase] = []
    @Published var selectedSegment: DisputeSegment = .myDisputes
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showCreateForm: Bool = false
    @Published var contentAppeared: Bool = false
    @Published var isDemo: Bool = false

    // Create form
    @Published var counterpartyAddress: String = ""
    @Published var disputeDescription: String = ""
    @Published var evidenceText: String = ""
    @Published var stakeAmount: String = ""
    @Published var isSubmitting: Bool = false

    // MARK: - Computed

    var claimableWinnings: Double {
        activeDisputes
            .filter { $0.status == .resolved && $0.wonByUser }
            .reduce(0) { $0 + $1.stakeAmount }
    }

    var canSubmitDispute: Bool {
        !counterpartyAddress.trimmingCharacters(in: .whitespaces).isEmpty &&
        !disputeDescription.trimmingCharacters(in: .whitespaces).isEmpty &&
        !stakeAmount.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(stakeAmount) ?? 0) > 0
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Live from DisputeService when the gateway is configured; else demo.
        if PendingCredentials.isBackendConfigured {
            do {
                func toCase(_ d: SvcDisputeCase, isJury: Bool) -> DisputeCase {
                    let st: DisputeUIStatus = d.status.lowercased() == "pending" ? .pending
                        : d.status.lowercased() == "resolved" ? .resolved
                        : d.status.lowercased() == "rejected" ? .rejected : .active
                    return DisputeCase(
                        counterparty: d.respondent,
                        description_: d.description,
                        stakeAmount: d.stake,
                        status: st,
                        votesFor: d.votesFor,
                        votesAgainst: d.votesAgainst,
                        deadline: d.deadline,
                        wonByUser: false,
                        isJuryCase: isJury
                    )
                }
                // "My disputes" are per-wallet; open jury cases are global.
                var mine: [SvcDisputeCase] = []
                if let address = MtrxSession.walletAddress {
                    mine = (try? await DisputeService.shared.getDisputes(address: address)) ?? []
                }
                let jury = try await DisputeService.shared.getOpenJuryCases()
                activeDisputes = mine.map { toCase($0, isJury: false) }
                juryCases = jury.map { toCase($0, isJury: true) }
                isDemo = false
                isLoading = false
                withAnimation(Motion.springDefault) { contentAppeared = true }
                return
            } catch {
                errorMessage = "Live disputes unavailable — showing demo."
            }
        }

        try? await Task.sleep(nanoseconds: 800_000_000)

        activeDisputes = DisputeCase.sampleMyDisputes
        juryCases = DisputeCase.sampleJuryCases
        isDemo = true
        isLoading = false

        withAnimation(Motion.springDefault) {
            contentAppeared = true
        }
    }

    func submitDispute() async {
        guard canSubmitDispute else { return }
        isSubmitting = true

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let newDispute = DisputeCase(
            counterparty: counterpartyAddress,
            description_: disputeDescription,
            stakeAmount: Double(stakeAmount) ?? 0,
            status: .pending,
            votesFor: 0,
            votesAgainst: 0,
            deadline: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
            wonByUser: false,
            isJuryCase: false
        )
        activeDisputes.insert(newDispute, at: 0)
        isSubmitting = false
        showCreateForm = false
        resetForm()
        MtrxHaptics.success()
    }

    func vote(for dispute: DisputeCase, inFavor: Bool) {
        if let index = juryCases.firstIndex(where: { $0.id == dispute.id }) {
            if inFavor {
                juryCases[index].votesFor += 1
            } else {
                juryCases[index].votesAgainst += 1
            }
            juryCases[index].hasVoted = true
        }
        MtrxHaptics.impact(.medium)
    }

    func claimWinnings() {
        for i in activeDisputes.indices {
            if activeDisputes[i].status == .resolved && activeDisputes[i].wonByUser {
                activeDisputes[i].claimed = true
            }
        }
        MtrxHaptics.success()
    }

    private func resetForm() {
        counterpartyAddress = ""
        disputeDescription = ""
        evidenceText = ""
        stakeAmount = ""
    }
}

// MARK: - DisputeCase Segment

enum DisputeSegment: String, CaseIterable {
    case myDisputes = "My Disputes"
    case jury = "Jury Duty"
}

// MARK: - DisputeCase View

struct DisputeView: View {
    @StateObject private var viewModel = DisputeViewModel()

    private let accent = Color(red: 0.0, green: 0.675, blue: 0.694)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    segmentControl
                        .padding(.horizontal, Spacing.contentPadding)
                        .padding(.vertical, Spacing.ms)

                    if viewModel.isLoading {
                        MtrxLoadingView(rows: 6)
                    } else if let error = viewModel.errorMessage {
                        MtrxErrorView(message: error) {
                            Task { await viewModel.load() }
                        }
                    } else {
                        switch viewModel.selectedSegment {
                        case .myDisputes:
                            myDisputesView
                        case .jury:
                            juryView
                        }
                    }
                }
                .background(MtrxGradientBackground(style: .primary))

                // FAB
                if viewModel.selectedSegment == .myDisputes {
                    Button {
                        viewModel.showCreateForm = true
                        MtrxHaptics.impact(.medium)
                    } label: {
                        Image(systemName: Symbols.add)
                            .accessibilityLabel("Create dispute")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(accent)
                            .clipShape(Circle())
                            .shadow(color: accent.opacity(0.4), radius: 12, y: 4)
                    }
                    .padding(.trailing, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
            }
            .navigationTitle("Disputes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { if viewModel.isDemo { DemoBadge() } } }
            .sheet(isPresented: $viewModel.showCreateForm) {
                createDisputeSheet
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        HStack(spacing: 0) {
            ForEach(DisputeSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(Motion.springSnappy) {
                        viewModel.selectedSegment = segment
                    }
                    MtrxHaptics.selection()
                } label: {
                    Text(segment.rawValue)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(viewModel.selectedSegment == segment ? .white : Color.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            viewModel.selectedSegment == segment
                                ? Capsule().fill(accent)
                                : Capsule().fill(Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.surfaceOverlay)
        .clipShape(Capsule())
    }

    // MARK: - My Disputes

    private var myDisputesView: some View {
        Group {
            if viewModel.activeDisputes.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.dispute,
                    title: "No Disputes",
                    message: "You have no active disputes. Tap + to raise one if needed.",
                    actionLabel: "Create DisputeCase"
                ) {
                    viewModel.showCreateForm = true
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.md) {
                        // Claimable winnings
                        if viewModel.claimableWinnings > 0 {
                            claimableCard
                                .mtrxStaggeredAppearance(index: 0, isVisible: viewModel.contentAppeared)
                        }

                        ForEach(Array(viewModel.activeDisputes.enumerated()), id: \.element.id) { index, dispute in
                            disputeCard(dispute)
                                .mtrxStaggeredAppearance(index: index + 1, isVisible: viewModel.contentAppeared)
                        }

                        Spacer().frame(height: Spacing.xxxl)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                }
            }
        }
    }

    private var claimableCard: some View {
        MtrxCard(style: .glass) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Claimable Winnings")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)
                    Text(String(format: "%.4f ETH", viewModel.claimableWinnings))
                        .font(.mtrxMonoMedium)
                        .foregroundStyle(Color.statusSuccess)
                }
                Spacer()
                Button {
                    viewModel.claimWinnings()
                } label: {
                    Text("Claim")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
            }
        }
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
    }

    private func disputeCard(_ dispute: DisputeCase) -> some View {
        MtrxCard(style: .standard, accentEdge: .leading) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    MtrxBadge(text: dispute.status.label, style: dispute.status.badgeStyle)
                    Spacer()
                    Text(String(format: "%.4f ETH", dispute.stakeAmount))
                        .font(.mtrxMono)
                        .foregroundStyle(Color.labelPrimary)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(dispute.description_)
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(2)

                    Text("vs \(dispute.counterparty)")
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MtrxDivider()

                HStack {
                    Label {
                        Text("Deadline")
                            .font(.mtrxCaption1)
                    } icon: {
                        Image(systemName: Symbols.clock)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.labelTertiary)

                    Text(dispute.deadline, style: .relative)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(dispute.isUrgent ? Color.statusWarning : Color.labelSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.voteYes)
                            .foregroundStyle(Color.voteFor)
                        Text("\(dispute.votesFor)")
                            .font(.mtrxCaptionBold)

                        Image(systemName: Symbols.voteNo)
                            .foregroundStyle(Color.voteAgainst)
                        Text("\(dispute.votesAgainst)")
                            .font(.mtrxCaptionBold)
                    }
                }
            }
        }
    }

    // MARK: - Jury View

    private var juryView: some View {
        Group {
            if viewModel.juryCases.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.vote,
                    title: "No Jury Cases",
                    message: "You have no disputes assigned for jury review."
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.md) {
                        ForEach(Array(viewModel.juryCases.enumerated()), id: \.element.id) { index, dispute in
                            juryCaseCard(dispute)
                                .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                        }

                        Spacer().frame(height: Spacing.xxl)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                }
            }
        }
    }

    private func juryCaseCard(_ dispute: DisputeCase) -> some View {
        MtrxCard(style: .elevated) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    MtrxBadge(text: "Jury Review", style: .info)
                    Spacer()
                    Text(String(format: "%.4f ETH", dispute.stakeAmount))
                        .font(.mtrxMono)
                        .foregroundStyle(Color.labelPrimary)
                }

                Text(dispute.description_)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(dispute.counterparty)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.middle)
                    Spacer()
                }

                MtrxDivider()

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Voting Deadline")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(dispute.deadline, style: .relative)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Current Votes")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        HStack(spacing: Spacing.sm) {
                            HStack(spacing: 2) {
                                Image(systemName: Symbols.voteYes)
                                    .font(.system(size: 12))
                                Text("\(dispute.votesFor)")
                                    .font(.mtrxCaptionBold)
                            }
                            .foregroundStyle(Color.voteFor)

                            HStack(spacing: 2) {
                                Image(systemName: Symbols.voteNo)
                                    .font(.system(size: 12))
                                Text("\(dispute.votesAgainst)")
                                    .font(.mtrxCaptionBold)
                            }
                            .foregroundStyle(Color.voteAgainst)
                        }
                    }
                }

                if dispute.hasVoted {
                    MtrxBadge(text: "Vote Cast", style: .neutral)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    HStack(spacing: Spacing.md) {
                        Button {
                            viewModel.vote(for: dispute, inFavor: true)
                        } label: {
                            Label("Claimant", systemImage: Symbols.voteYes)
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))

                        Button {
                            viewModel.vote(for: dispute, inFavor: false)
                        } label: {
                            Label("Respondent", systemImage: Symbols.voteNo)
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .destructive, size: .compact))
                    }
                }
            }
        }
    }

    // MARK: - Create DisputeCase Sheet

    private var createDisputeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Create DisputeCase", subtitle: "Raise a formal on-chain dispute") {
                        viewModel.showCreateForm = false
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        fieldSection(title: "Counterparty Address", required: true) {
                            MtrxTextField(
                                placeholder: "0x...",
                                text: $viewModel.counterpartyAddress,
                                icon: "person.fill"
                            )
                        }

                        fieldSection(title: "Description", required: true) {
                            TextEditor(text: $viewModel.disputeDescription)
                                .font(.mtrxBody)
                                .frame(minHeight: 80)
                                .padding(Spacing.sm)
                                .background(Color.surfaceOverlay)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                        }

                        fieldSection(title: "Evidence") {
                            TextEditor(text: $viewModel.evidenceText)
                                .font(.mtrxBody)
                                .frame(minHeight: 60)
                                .padding(Spacing.sm)
                                .background(Color.surfaceOverlay)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                        }

                        fieldSection(title: "Stake Amount (ETH)", required: true) {
                            MtrxTextField(
                                placeholder: "0.1",
                                text: $viewModel.stakeAmount,
                                icon: Symbols.token,
                                keyboardType: .decimalPad
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    Button {
                        MtrxHaptics.impact(.medium)
                        Task { await viewModel.submitDispute() }
                    } label: {
                        Label("Submit DisputeCase", systemImage: Symbols.dispute)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: viewModel.isSubmitting, fullWidth: true))
                    .disabled(!viewModel.canSubmitDispute || viewModel.isSubmitting)
                    .opacity(viewModel.canSubmitDispute ? 1 : 0.5)
                    .padding(.horizontal, Spacing.contentPadding)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func fieldSection<Content: View>(title: String, required: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                if required {
                    Text("*")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.statusError)
                }
            }
            content()
        }
    }
}

// MARK: - Data Models

struct DisputeCase: Identifiable {
    let id = UUID()
    let counterparty: String
    let description_: String
    let stakeAmount: Double
    var status: DisputeUIStatus
    var votesFor: Int
    var votesAgainst: Int
    let deadline: Date
    var wonByUser: Bool
    var isJuryCase: Bool
    var hasVoted: Bool = false
    var claimed: Bool = false

    var isUrgent: Bool {
        let hours = Calendar.current.dateComponents([.hour], from: Date(), to: deadline).hour ?? 0
        return hours < 24
    }

    static let sampleMyDisputes: [DisputeCase] = [
        DisputeCase(counterparty: "0x5678...9abc", description_: "Vendor failed to deliver contracted services within the agreed timeline", stakeAmount: 0.5, status: .active, votesFor: 3, votesAgainst: 1, deadline: Calendar.current.date(byAdding: .day, value: 3, to: Date())!, wonByUser: false, isJuryCase: false),
        DisputeCase(counterparty: "0xabcd...ef01", description_: "Smart contract audit was incomplete and missed critical vulnerabilities", stakeAmount: 1.2, status: .pending, votesFor: 0, votesAgainst: 0, deadline: Calendar.current.date(byAdding: .day, value: 7, to: Date())!, wonByUser: false, isJuryCase: false),
        DisputeCase(counterparty: "0x1234...5678", description_: "Payment dispute for completed milestone deliverables", stakeAmount: 0.8, status: .resolved, votesFor: 5, votesAgainst: 2, deadline: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, wonByUser: true, isJuryCase: false),
    ]

    static let sampleJuryCases: [DisputeCase] = [
        DisputeCase(counterparty: "0xaaaa...bbbb vs 0xcccc...dddd", description_: "DisputeCase over NFT collection royalty payments not being distributed", stakeAmount: 2.0, status: .active, votesFor: 4, votesAgainst: 3, deadline: Calendar.current.date(byAdding: .day, value: 2, to: Date())!, wonByUser: false, isJuryCase: true),
        DisputeCase(counterparty: "0xeeee...ffff vs 0x1111...2222", description_: "DAO treasury mismanagement allegation", stakeAmount: 5.0, status: .active, votesFor: 1, votesAgainst: 0, deadline: Calendar.current.date(byAdding: .day, value: 5, to: Date())!, wonByUser: false, isJuryCase: true),
    ]
}

enum DisputeUIStatus {
    case pending, active, resolved, rejected

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .active: return "Active"
        case .resolved: return "Resolved"
        case .rejected: return "Rejected"
        }
    }

    var badgeStyle: MtrxBadge.BadgeStyle {
        switch self {
        case .pending: return .warning
        case .active: return .info
        case .resolved: return .success
        case .rejected: return .error
        }
    }
}

// MARK: - Preview

#Preview {
    DisputeView()
}
