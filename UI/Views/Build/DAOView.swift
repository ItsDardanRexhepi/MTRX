// DAOView.swift
// MTRX
//
// Component 6 — DAO dashboard with proposals, voting interface, and treasury.

import SwiftUI

// MARK: - DAO ViewModel

@MainActor
final class DAOViewModel: ObservableObject {
    @Published var proposals: [DAOProposal] = []
    @Published var treasuryBalance: String = "$0"
    @Published var memberCount: Int = 0
    @Published var votingPower: String = "0 MTRX"
    @Published var treasuryAssets: [TreasuryAsset] = []
    @Published var delegates: [DelegateItem] = []
    @Published var selectedTab: DAOTab = .proposals
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showCreateProposal: Bool = false

    private let api = MTRXAPIClient.shared

    // MARK: - Treasury Asset Model

    struct TreasuryAsset: Identifiable {
        let id = UUID()
        let token: String
        let amount: String
        let percentage: Int
    }

    // MARK: - Load All

    func loadAll() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let proposalsTask: () = loadProposals()
        async let daoTask: () = loadDAOInfo()
        async let delegatesTask: () = loadDelegates()

        _ = await (proposalsTask, daoTask, delegatesTask)
        isLoading = false
    }

    // MARK: - Load Proposals

    func loadProposals() async {
        do {
            let raw: [String: AnyCodableValue] = try await api.listProposals()
            proposals = parseProposals(raw)
            if proposals.isEmpty {
                proposals = DAOProposal.sampleData
            }
        } catch {
            if proposals.isEmpty {
                proposals = DAOProposal.sampleData
            }
        }
    }

    // MARK: - Load DAO Info

    func loadDAOInfo() async {
        do {
            let raw: [String: AnyCodableValue] = try await api.listDAOs()

            // Parse treasury and member info from the DAO data
            if case .array(let daos) = raw["data"] ?? raw["daos"] ?? .null,
               let first = daos.first,
               case .dictionary(let dao) = first {

                let treasury = dao["treasury_balance"]?.doubleValue ?? 0
                if treasury >= 1_000_000 {
                    treasuryBalance = "$\(String(format: "%,.0f", treasury))"
                } else {
                    treasuryBalance = "$\(String(format: "%,.0f", treasury))"
                }

                memberCount = dao["member_count"]?.intValue ?? dao["members"]?.intValue ?? 0
                let power = dao["voting_power"]?.doubleValue ?? dao["voting_power"]?.intValue.map { Double($0) } ?? 0
                votingPower = "\(String(format: "%,.0f", power)) MTRX"

                // Parse treasury assets
                if case .array(let assets) = dao["treasury_assets"] {
                    treasuryAssets = assets.compactMap { asset -> TreasuryAsset? in
                        guard case .dictionary(let a) = asset else { return nil }
                        let token = a["token"]?.stringValue ?? "Unknown"
                        let amount = a["amount"]?.doubleValue ?? 0
                        let pct = a["percentage"]?.intValue ?? 0
                        return TreasuryAsset(token: token, amount: "$\(String(format: "%,.0f", amount))", percentage: pct)
                    }
                }
            }

            if memberCount == 0 {
                treasuryBalance = "$1,245,670"
                memberCount = 2_456
                votingPower = "1,250 MTRX"
                treasuryAssets = [
                    TreasuryAsset(token: "USDC", amount: "$800,000", percentage: 64),
                    TreasuryAsset(token: "ETH", amount: "$345,670", percentage: 28),
                    TreasuryAsset(token: "MTRX", amount: "$100,000", percentage: 8),
                ]
            }
        } catch {
            if memberCount == 0 {
                treasuryBalance = "$1,245,670"
                memberCount = 2_456
                votingPower = "1,250 MTRX"
                treasuryAssets = [
                    TreasuryAsset(token: "USDC", amount: "$800,000", percentage: 64),
                    TreasuryAsset(token: "ETH", amount: "$345,670", percentage: 28),
                    TreasuryAsset(token: "MTRX", amount: "$100,000", percentage: 8),
                ]
            }
        }
    }

    // MARK: - Load Delegates

    func loadDelegates() async {
        // Static for now
        delegates = DelegateItem.sampleData
    }

    // MARK: - Vote

    func castVote(proposalId: String, support: Bool, reason: String? = nil) async throws {
        let request = VoteRequest(proposalId: proposalId, support: support, reason: reason)
        _ = try await api.vote(request)
        await loadProposals()
    }

    // MARK: - Create Proposal

    func createProposal(title: String, description: String, votingDuration: Int) async throws {
        let request = ProposalCreateRequest(
            title: title,
            description: description,
            actions: nil,
            votingDurationHours: votingDuration
        )
        _ = try await api.createProposal(request)
        await loadProposals()
    }

    // MARK: - Parser

    private func parseProposals(_ raw: [String: AnyCodableValue]) -> [DAOProposal] {
        guard case .array(let items) = raw["data"] ?? raw["proposals"] ?? .null else {
            return []
        }
        return items.compactMap { item -> DAOProposal? in
            guard case .dictionary(let dict) = item else { return nil }
            let number = dict["number"]?.intValue ?? dict["id"]?.intValue ?? 0
            let title = dict["title"]?.stringValue ?? "Proposal"
            let summary = dict["summary"]?.stringValue ?? dict["description"]?.stringValue ?? ""
            let proposer = dict["proposer"]?.stringValue ?? dict["author"]?.stringValue ?? "Unknown"
            let statusStr = dict["status"]?.stringValue ?? "active"
            let forPct = dict["for_percentage"]?.doubleValue ?? dict["votes_for"]?.doubleValue ?? 0
            let againstPct = dict["against_percentage"]?.doubleValue ?? dict["votes_against"]?.doubleValue ?? 0
            let deadline = dict["deadline"]?.stringValue ?? dict["ends_at"]?.stringValue ?? "N/A"

            let status: ProposalStatus = {
                switch statusStr.lowercased() {
                case "passed": return .passed
                case "defeated": return .defeated
                case "queued": return .queued
                case "executed": return .executed
                default: return .active
                }
            }()

            // Normalize percentages to 0-1 range
            let forVal = forPct > 1 ? forPct / 100 : forPct
            let againstVal = againstPct > 1 ? againstPct / 100 : againstPct

            return DAOProposal(
                number: number,
                title: title,
                summary: summary,
                proposer: proposer,
                status: status,
                forPercentage: forVal,
                againstPercentage: againstVal,
                deadline: deadline
            )
        }
    }
}

// MARK: - DAO View

struct DAOView: View {
    @StateObject private var viewModel = DAOViewModel()

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.proposals.isEmpty {
                loadingState
            } else if let error = viewModel.errorMessage, viewModel.proposals.isEmpty {
                errorState(error)
            } else {
                contentView
            }
        }
        .navigationTitle("DAO")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showCreateProposal = true
                } label: {
                    Image(systemName: Symbols.addCircle)
                }
            }
        }
        .sheet(isPresented: $viewModel.showCreateProposal) {
            CreateProposalSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .task {
            await viewModel.loadAll()
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Loading DAO...")
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 48))
                .foregroundStyle(Color.statusWarning)
            Text("Failed to load DAO")
                .font(.mtrxTitle3)
            Text(message)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
            Button {
                Task { await viewModel.loadAll() }
            } label: {
                Label("Retry", systemImage: Symbols.refresh)
                    .font(.mtrxHeadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: Spacing.Size.buttonHeight)
                    .background(Color.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sectionGap) {
                daoHeader
                statsBar
                tabSelector
                tabContent
            }
        }
        .refreshable {
            await viewModel.loadAll()
        }
    }

    // MARK: - DAO Header

    private var daoHeader: some View {
        VStack(spacing: Spacing.sm) {
            Circle()
                .fill(LinearGradient.mtrxPrimary)
                .frame(width: Spacing.Size.avatarXLarge, height: Spacing.Size.avatarXLarge)
                .overlay(
                    Image(systemName: Symbols.dao)
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                )

            Text("MTRX DAO")
                .font(.mtrxTitle2)

            Text("Decentralized governance for the MTRX ecosystem")
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.md) {
                Label(viewModel.votingPower, systemImage: Symbols.vote)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.accentPrimary)

                Label("Member", systemImage: Symbols.verified)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.statusSuccess)
            }
        }
        .padding(Spacing.contentPadding)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: Spacing.md) {
            DAOStatCell(title: "Treasury", value: viewModel.treasuryBalance, icon: Symbols.treasury)
            DAOStatCell(title: "Members", value: "\(viewModel.memberCount)", icon: Symbols.backers)
            DAOStatCell(title: "Proposals", value: "\(viewModel.proposals.count)", icon: Symbols.proposal)
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        Picker("Tab", selection: $viewModel.selectedTab) {
            ForEach(DAOTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .proposals:
            proposalsContent
        case .treasury:
            treasuryContent
        case .delegates:
            delegatesContent
        }
    }

    // MARK: - Proposals

    private var proposalsContent: some View {
        LazyVStack(spacing: Spacing.sm) {
            ForEach(viewModel.proposals) { proposal in
                NavigationLink {
                    ProposalDetailView(proposal: proposal, viewModel: viewModel)
                } label: {
                    ProposalCard(proposal: proposal)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Treasury

    private var treasuryContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Treasury Balance")
                .font(.mtrxTitle3)

            Text(viewModel.treasuryBalance)
                .font(.mtrxMonoLarge)
                .foregroundStyle(Color.accentPrimary)

            Divider()

            VStack(spacing: Spacing.sm) {
                ForEach(viewModel.treasuryAssets) { asset in
                    TreasuryAssetRow(token: asset.token, amount: asset.amount, percentage: asset.percentage)
                }
            }

            Divider()

            Text("Recent Treasury Activity")
                .font(.mtrxHeadline)

            ForEach(0..<3, id: \.self) { i in
                HStack {
                    Image(systemName: i % 2 == 0 ? Symbols.send : Symbols.receive)
                        .foregroundStyle(i % 2 == 0 ? Color.statusError : Color.statusSuccess)
                    VStack(alignment: .leading) {
                        Text(i % 2 == 0 ? "Grant Payment" : "Revenue")
                            .font(.mtrxBodyBold)
                        Text("Proposal #\(100 + i)")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text(i % 2 == 0 ? "-$25,000" : "+$12,500")
                        .font(.mtrxBodyTabular)
                        .foregroundStyle(i % 2 == 0 ? Color.statusError : Color.statusSuccess)
                }
            }
        }
        .padding(Spacing.contentPadding)
    }

    // MARK: - Delegates

    private var delegatesContent: some View {
        LazyVStack(spacing: Spacing.sm) {
            ForEach(viewModel.delegates) { delegate in
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Color.accentPrimary.opacity(0.2))
                        .frame(width: Spacing.Size.avatarMedium, height: Spacing.Size.avatarMedium)
                        .overlay(
                            Text(String(delegate.name.prefix(2)))
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.accentPrimary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(delegate.name)
                            .font(.mtrxBodyBold)
                        Text(delegate.address)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(delegate.votingPower)
                            .font(.mtrxBodyTabular)
                        Text("\(delegate.proposalsVoted) votes")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                    }
                }
                .padding(Spacing.sm)
                .background(Color.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }
}

// MARK: - Proposal Card

struct ProposalCard: View {
    let proposal: DAOProposal

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("#\(proposal.number)")
                    .font(.mtrxMonoSmall)
                    .foregroundStyle(Color.labelTertiary)

                Text(proposal.title)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)

                Spacer()

                Text(proposal.status.rawValue)
                    .font(.mtrxCaptionBold)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(proposal.status.color.opacity(0.15))
                    .foregroundStyle(proposal.status.color)
                    .clipShape(Capsule())
            }

            Text(proposal.summary)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)

            // Vote bars
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.voteFor)
                        .frame(width: geo.size.width * proposal.forPercentage)

                    Rectangle()
                        .fill(Color.voteAgainst)
                        .frame(width: geo.size.width * proposal.againstPercentage)

                    Rectangle()
                        .fill(Color.voteAbstain)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            HStack {
                HStack(spacing: Spacing.xs) {
                    Circle().fill(Color.voteFor).frame(width: 8, height: 8)
                    Text("\(Int(proposal.forPercentage * 100))% For")
                }

                HStack(spacing: Spacing.xs) {
                    Circle().fill(Color.voteAgainst).frame(width: 8, height: 8)
                    Text("\(Int(proposal.againstPercentage * 100))% Against")
                }

                Spacer()

                Text(proposal.deadline)
                    .foregroundStyle(Color.labelTertiary)
            }
            .font(.mtrxCaption2)
        }
        .padding(Spacing.cardPadding)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Proposal Detail View

struct ProposalDetailView: View {
    let proposal: DAOProposal
    @ObservedObject var viewModel: DAOViewModel
    @State private var selectedVote: VoteChoice?
    @State private var isVoting: Bool = false
    @State private var voteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("#\(proposal.number) \(proposal.title)")
                        .font(.mtrxTitle2)

                    Text("Proposed by \(proposal.proposer)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                Text(proposal.summary)
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)

                // Vote section
                if proposal.status == .active {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Cast Your Vote")
                            .font(.mtrxTitle3)

                        HStack(spacing: Spacing.sm) {
                            ForEach(VoteChoice.allCases, id: \.self) { choice in
                                Button {
                                    withAnimation(Motion.springSnappy) {
                                        selectedVote = choice
                                    }
                                } label: {
                                    VStack(spacing: Spacing.xs) {
                                        Image(systemName: choice.icon)
                                            .font(.system(size: 24))
                                        Text(choice.rawValue)
                                            .font(.mtrxCaptionBold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(Spacing.md)
                                    .background(
                                        selectedVote == choice
                                            ? choice.color.opacity(0.2)
                                            : Color.surfaceOverlay
                                    )
                                    .foregroundStyle(
                                        selectedVote == choice
                                            ? choice.color
                                            : Color.labelPrimary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm)
                                            .stroke(selectedVote == choice ? choice.color : .clear, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let error = voteError {
                            Text(error)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.statusError)
                        }

                        Button {
                            guard let vote = selectedVote else { return }
                            isVoting = true
                            voteError = nil
                            Task {
                                do {
                                    try await viewModel.castVote(
                                        proposalId: "\(proposal.number)",
                                        support: vote == .forVote
                                    )
                                } catch {
                                    voteError = error.localizedDescription
                                }
                                isVoting = false
                            }
                        } label: {
                            HStack {
                                if isVoting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Submit Vote")
                                }
                            }
                            .font(.mtrxHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: Spacing.Size.buttonHeight)
                            .background(selectedVote != nil ? Color.accentPrimary : Color.labelTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                        }
                        .disabled(selectedVote == nil || isVoting)
                    }
                }
            }
            .padding(Spacing.contentPadding)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Create Proposal Sheet

struct CreateProposalSheet: View {
    @ObservedObject var viewModel: DAOViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var votingDurationHours: Int = 72
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Proposal Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Voting Duration") {
                    Stepper("\(votingDurationHours) hours", value: $votingDurationHours, in: 24...720, step: 24)
                    Text("\(votingDurationHours / 24) days")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                if let error = submitError {
                    Section {
                        Text(error)
                            .foregroundStyle(Color.statusError)
                    }
                }

                Section {
                    Button {
                        isSubmitting = true
                        submitError = nil
                        Task {
                            do {
                                try await viewModel.createProposal(
                                    title: title,
                                    description: description,
                                    votingDuration: votingDurationHours
                                )
                                dismiss()
                            } catch {
                                submitError = error.localizedDescription
                            }
                            isSubmitting = false
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Submit Proposal")
                                    .font(.mtrxHeadline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(title.isEmpty || description.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("New Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct DAOStatCell: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentPrimary)
            Text(value)
                .font(.mtrxHeadline)
            Text(title)
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

struct TreasuryAssetRow: View {
    let token: String
    let amount: String
    let percentage: Int

    var body: some View {
        HStack {
            Text(token)
                .font(.mtrxBodyBold)
            Spacer()
            Text(amount)
                .font(.mtrxBodyTabular)
            Text("(\(percentage)%)")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
        }
    }
}

// MARK: - Enums & Models

enum DAOTab: String, CaseIterable {
    case proposals = "Proposals"
    case treasury = "Treasury"
    case delegates = "Delegates"
}

enum VoteChoice: String, CaseIterable {
    case forVote = "For"
    case against = "Against"
    case abstain = "Abstain"

    var icon: String {
        switch self {
        case .forVote: return Symbols.voteYes
        case .against: return Symbols.voteNo
        case .abstain: return Symbols.voteAbstain
        }
    }

    var color: Color {
        switch self {
        case .forVote: return .voteFor
        case .against: return .voteAgainst
        case .abstain: return .voteAbstain
        }
    }
}

enum ProposalStatus: String {
    case active = "Active"
    case passed = "Passed"
    case defeated = "Defeated"
    case queued = "Queued"
    case executed = "Executed"

    var color: Color {
        switch self {
        case .active: return .statusInfo
        case .passed: return .statusSuccess
        case .defeated: return .statusError
        case .queued: return .statusWarning
        case .executed: return .accentPrimary
        }
    }
}

struct DAOProposal: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let summary: String
    let proposer: String
    let status: ProposalStatus
    let forPercentage: Double
    let againstPercentage: Double
    let deadline: String

    static let sampleData: [DAOProposal] = [
        DAOProposal(number: 42, title: "Treasury Diversification", summary: "Diversify 20% of treasury into ETH and stablecoins for risk management.", proposer: "0xab12...ef34", status: .active, forPercentage: 0.68, againstPercentage: 0.22, deadline: "2d left"),
        DAOProposal(number: 41, title: "Developer Grant Program", summary: "Allocate $100K for quarterly developer grants.", proposer: "0x9876...5432", status: .passed, forPercentage: 0.82, againstPercentage: 0.12, deadline: "Ended"),
        DAOProposal(number: 40, title: "Protocol Fee Reduction", summary: "Reduce protocol fees from 0.3% to 0.25%.", proposer: "0xfedc...ba98", status: .active, forPercentage: 0.45, againstPercentage: 0.35, deadline: "5d left"),
    ]
}

struct DelegateItem: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let votingPower: String
    let proposalsVoted: Int

    static let sampleData: [DelegateItem] = [
        DelegateItem(name: "Alice.eth", address: "0xab12...ef34", votingPower: "125K", proposalsVoted: 38),
        DelegateItem(name: "Bob.eth", address: "0x9876...5432", votingPower: "89K", proposalsVoted: 25),
        DelegateItem(name: "Carol.eth", address: "0xfedc...ba98", votingPower: "67K", proposalsVoted: 42),
    ]
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DAOView()
    }
}
