// GovernanceView.swift
// MTRX - Component 19 governance proposals, voting, and results
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI
import Combine

// MARK: - Models

struct GovernanceProposal: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let description: String
    let proposerAddress: String
    let proposerName: String
    let status: ProposalStatus
    let category: ProposalCategory
    let createdAt: Date
    let votingStartsAt: Date
    let votingEndsAt: Date
    let forVotes: Int
    let againstVotes: Int
    let abstainVotes: Int
    let quorumRequired: Int
    let executionTransactionHash: String?
    let componentReference: Int?

    enum ProposalStatus: String, Codable, CaseIterable {
        case draft = "Draft"
        case active = "Active"
        case succeeded = "Succeeded"
        case defeated = "Defeated"
        case queued = "Queued"
        case executed = "Executed"
        case cancelled = "Cancelled"

        var color: Color {
            switch self {
            case .draft: return .labelTertiary
            case .active: return .statusInfo
            case .succeeded: return .statusSuccess
            case .defeated: return .statusError
            case .queued: return .statusWarning
            case .executed: return .statusSuccess
            case .cancelled: return .labelTertiary
            }
        }

        var icon: String {
            switch self {
            case .draft: return "doc"
            case .active: return "bolt.fill"
            case .succeeded: return Symbols.complete
            case .defeated: return Symbols.failed
            case .queued: return Symbols.pending
            case .executed: return Symbols.verified
            case .cancelled: return Symbols.voteAbstain
            }
        }
    }

    enum ProposalCategory: String, Codable, CaseIterable {
        case protocol_ = "Protocol"
        case treasury = "Treasury"
        case parameter = "Parameter"
        case membership = "Membership"
        case dispute = "Dispute"
        case emergency = "Emergency"
    }

    var totalVotes: Int { forVotes + againstVotes + abstainVotes }
    var forPercentage: Double { totalVotes > 0 ? Double(forVotes) / Double(totalVotes) : 0 }
    var againstPercentage: Double { totalVotes > 0 ? Double(againstVotes) / Double(totalVotes) : 0 }
    var abstainPercentage: Double { totalVotes > 0 ? Double(abstainVotes) / Double(totalVotes) : 0 }
    var quorumReached: Bool { totalVotes >= quorumRequired }
    var quorumProgress: Double { quorumRequired > 0 ? min(Double(totalVotes) / Double(quorumRequired), 1.0) : 0 }
    var isVotingActive: Bool { status == .active && Date() < votingEndsAt && Date() >= votingStartsAt }

    var timeRemaining: String {
        let interval = votingEndsAt.timeIntervalSince(Date())
        guard interval > 0 else { return "Ended" }
        let hours = Int(interval) / 3600
        let days = hours / 24
        if days > 0 { return "\(days)d \(hours % 24)h remaining" }
        return "\(hours)h remaining"
    }
}

enum VoteChoice: String, CaseIterable {
    case forVote = "For"
    case against = "Against"
    case abstain = "Abstain"

    var color: Color {
        switch self {
        case .forVote: return .voteFor
        case .against: return .voteAgainst
        case .abstain: return .voteAbstain
        }
    }

    var icon: String {
        switch self {
        case .forVote: return Symbols.voteYes
        case .against: return Symbols.voteNo
        case .abstain: return Symbols.voteAbstain
        }
    }
}

// MARK: - Delegation Model

struct DelegationInfo: Identifiable, Equatable {
    let id: String
    let delegateAddress: String
    let delegateName: String
    let votingPower: String
    let delegatedAt: Date
}

// MARK: - ViewModel

@MainActor
final class GovernanceViewModel: ObservableObject {
    @Published var proposals: [GovernanceProposal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: GovernanceProposal.ProposalStatus?
    @Published var selectedCategory: GovernanceProposal.ProposalCategory?
    @Published var selectedProposal: GovernanceProposal?
    @Published var isVoting = false
    @Published var userVote: VoteChoice?
    @Published var hasVoted = false
    @Published var showCreateProposal = false
    @Published var searchText = ""
    @Published var showDelegation = false
    @Published var delegations: [DelegationInfo] = []
    @Published var delegateAddress = ""
    @Published var isDelegating = false

    // Create proposal fields
    @Published var newTitle = ""
    @Published var newDescription = ""
    @Published var newCategory: GovernanceProposal.ProposalCategory = .protocol_
    @Published var votingDurationDays: Int = 7

    private let api = MTRXAPIClient.shared

    var filteredProposals: [GovernanceProposal] {
        var result = proposals

        if let filter = selectedFilter {
            result = result.filter { $0.status == filter }
        }
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var activeProposalsCount: Int {
        proposals.filter { $0.status == .active }.count
    }

    func loadProposals() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: [String: AnyCodableValue] = try await api.listProposals()
            proposals = parseProposals(response)
        } catch {
            errorMessage = "Failed to load proposals: \(error.localizedDescription)"
        }
    }

    func castVote(_ choice: VoteChoice) async {
        guard let proposal = selectedProposal, proposal.isVotingActive else { return }
        isVoting = true
        defer { isVoting = false }

        do {
            let request = VoteRequest(
                proposalId: proposal.id,
                support: choice == .forVote,
                reason: choice == .abstain ? "abstain" : nil
            )
            let _: [String: AnyCodableValue] = try await api.vote(request)
            userVote = choice
            hasVoted = true
            await loadProposals()
        } catch {
            errorMessage = "Failed to cast vote: \(error.localizedDescription)"
        }
    }

    func createProposal() async {
        guard !newTitle.isEmpty, !newDescription.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let request = ProposalCreateRequest(
                title: newTitle,
                description: newDescription,
                actions: nil,
                votingDurationHours: votingDurationDays * 24
            )
            let _: [String: AnyCodableValue] = try await api.createProposal(request)
            showCreateProposal = false
            newTitle = ""
            newDescription = ""
            await loadProposals()
        } catch {
            errorMessage = "Failed to create proposal: \(error.localizedDescription)"
        }
    }

    func loadDelegations() async {
        do {
            let response: [String: AnyCodableValue] = try await api.get(path: "/api/v1/governance/delegations")
            delegations = parseDelegations(response)
        } catch {
            errorMessage = "Failed to load delegations: \(error.localizedDescription)"
        }
    }

    func delegateVotingPower() async {
        guard !delegateAddress.isEmpty else { return }
        isDelegating = true
        defer { isDelegating = false }

        do {
            let _: [String: AnyCodableValue] = try await api.postRaw(
                path: "/api/v1/governance/delegate",
                body: ["delegate_to": delegateAddress]
            )
            delegateAddress = ""
            await loadDelegations()
        } catch {
            errorMessage = "Failed to delegate: \(error.localizedDescription)"
        }
    }

    func revokeDelegation(_ delegationId: String) async {
        do {
            let _: [String: AnyCodableValue] = try await api.postRaw(
                path: "/api/v1/governance/delegate/revoke",
                body: ["delegation_id": delegationId]
            )
            await loadDelegations()
        } catch {
            errorMessage = "Failed to revoke delegation: \(error.localizedDescription)"
        }
    }

    // MARK: - Parsing

    private func parseProposals(_ response: [String: AnyCodableValue]) -> [GovernanceProposal] {
        guard case .array(let items) = response["proposals"] ?? response["data"] ?? .null else {
            return []
        }
        return items.compactMap { item -> GovernanceProposal? in
            guard case .dictionary(let d) = item else { return nil }
            let statusRaw = d["status"]?.stringValue ?? "Draft"
            let categoryRaw = d["category"]?.stringValue ?? "Protocol"
            let status = GovernanceProposal.ProposalStatus(rawValue: statusRaw) ?? .draft
            let category = GovernanceProposal.ProposalCategory(rawValue: categoryRaw) ?? .protocol_

            return GovernanceProposal(
                id: d["id"]?.stringValue ?? UUID().uuidString,
                title: d["title"]?.stringValue ?? "",
                description: d["description"]?.stringValue ?? "",
                proposerAddress: d["proposer_address"]?.stringValue ?? "",
                proposerName: d["proposer_name"]?.stringValue ?? "Unknown",
                status: status,
                category: category,
                createdAt: Date(),
                votingStartsAt: Date(),
                votingEndsAt: Date().addingTimeInterval(86400 * 7),
                forVotes: d["for_votes"]?.intValue ?? 0,
                againstVotes: d["against_votes"]?.intValue ?? 0,
                abstainVotes: d["abstain_votes"]?.intValue ?? 0,
                quorumRequired: d["quorum_required"]?.intValue ?? 100,
                executionTransactionHash: d["execution_tx_hash"]?.stringValue,
                componentReference: d["component_reference"]?.intValue
            )
        }
    }

    private func parseDelegations(_ response: [String: AnyCodableValue]) -> [DelegationInfo] {
        guard case .array(let items) = response["delegations"] ?? response["data"] ?? .null else {
            return []
        }
        return items.compactMap { item -> DelegationInfo? in
            guard case .dictionary(let d) = item else { return nil }
            return DelegationInfo(
                id: d["id"]?.stringValue ?? UUID().uuidString,
                delegateAddress: d["delegate_address"]?.stringValue ?? "",
                delegateName: d["delegate_name"]?.stringValue ?? "",
                votingPower: d["voting_power"]?.stringValue ?? "0",
                delegatedAt: Date()
            )
        }
    }
}

// MARK: - Main View

struct GovernanceView: View {
    @StateObject private var viewModel = GovernanceViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.proposals.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.proposals.isEmpty {
                errorView(error)
            } else {
                statsBar
                filterSection
                proposalsList
            }
        }
        .navigationTitle("Governance")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        viewModel.showDelegation = true
                    } label: {
                        Image(systemName: Symbols.delegate)
                    }
                    .accessibilityLabel("Manage delegation")

                    Button {
                        viewModel.showCreateProposal = true
                    } label: {
                        Image(systemName: Symbols.addCircle)
                    }
                    .accessibilityLabel("Create proposal")
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search proposals")
        .sheet(item: $viewModel.selectedProposal) { proposal in
            ProposalDetailSheet(proposal: proposal, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showCreateProposal) {
            createProposalSheet
        }
        .sheet(isPresented: $viewModel.showDelegation) {
            delegationSheet
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil && !viewModel.proposals.isEmpty)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.loadProposals()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    ProposalSkeletonCard()
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Could Not Load Proposals")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadProposals() }
            } label: {
                Label("Retry", systemImage: Symbols.refresh)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                GovernanceStatCard(title: "Active", value: "\(viewModel.activeProposalsCount)", icon: "bolt.fill", color: .statusInfo)
                GovernanceStatCard(title: "Total", value: "\(viewModel.proposals.count)", icon: "doc.text", color: .labelSecondary)
                GovernanceStatCard(title: "Executed", value: "\(viewModel.proposals.filter { $0.status == .executed }.count)", icon: Symbols.verified, color: .statusSuccess)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Filters

    private var filterSection: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    StatusFilterChip(title: "All", isSelected: viewModel.selectedFilter == nil) {
                        viewModel.selectedFilter = nil
                    }
                    ForEach(GovernanceProposal.ProposalStatus.allCases, id: \.self) { status in
                        StatusFilterChip(
                            title: status.rawValue,
                            isSelected: viewModel.selectedFilter == status,
                            color: status.color
                        ) {
                            viewModel.selectedFilter = viewModel.selectedFilter == status ? nil : status
                        }
                    }
                }
                .padding(.horizontal)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GovernanceProposal.ProposalCategory.allCases, id: \.self) { category in
                        StatusFilterChip(
                            title: category.rawValue,
                            isSelected: viewModel.selectedCategory == category
                        ) {
                            viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Proposals List

    private var proposalsList: some View {
        List {
            if viewModel.filteredProposals.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.filteredProposals) { proposal in
                    ProposalCard(proposal: proposal)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .onTapGesture {
                            viewModel.hasVoted = false
                            viewModel.userVote = nil
                            viewModel.selectedProposal = proposal
                        }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadProposals()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: Symbols.dao)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Proposals")
                .font(.title3.weight(.semibold))
            Text("Governance proposals from Component 19 will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Create Proposal

    private var createProposalSheet: some View {
        NavigationStack {
            Form {
                Section("Proposal Details") {
                    TextField("Title", text: $viewModel.newTitle)
                    TextEditor(text: $viewModel.newDescription)
                        .frame(minHeight: 100)
                }

                Section("Configuration") {
                    Picker("Category", selection: $viewModel.newCategory) {
                        ForEach(GovernanceProposal.ProposalCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }

                    Stepper("Voting Duration: \(viewModel.votingDurationDays) days", value: $viewModel.votingDurationDays, in: 1...30)
                }

                Section {
                    HStack(spacing: 6) {
                        Image(systemName: Symbols.info)
                        Text("Creating a proposal requires signing an on-chain transaction. Gas fees will be estimated before submission.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showCreateProposal = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await viewModel.createProposal() }
                    }
                    .disabled(viewModel.newTitle.isEmpty || viewModel.newDescription.isEmpty)
                }
            }
        }
    }

    // MARK: - Delegation Sheet

    private var delegationSheet: some View {
        NavigationStack {
            Form {
                Section("Delegate Voting Power") {
                    TextField("Delegate wallet address or ENS", text: $viewModel.delegateAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)

                    Button {
                        Task { await viewModel.delegateVotingPower() }
                    } label: {
                        if viewModel.isDelegating {
                            ProgressView()
                        } else {
                            Text("Delegate")
                        }
                    }
                    .disabled(viewModel.delegateAddress.isEmpty || viewModel.isDelegating)
                }

                Section("Current Delegations") {
                    if viewModel.delegations.isEmpty {
                        Text("No active delegations")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.delegations) { delegation in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(delegation.delegateName.isEmpty ? delegation.delegateAddress : delegation.delegateName)
                                        .font(.subheadline.weight(.medium))
                                    Text("Voting power: \(delegation.votingPower)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Revoke") {
                                    Task { await viewModel.revokeDelegation(delegation.id) }
                                }
                                .font(.caption)
                                .foregroundStyle(.statusError)
                            }
                        }
                    }
                }

                Section {
                    HStack(spacing: 6) {
                        Image(systemName: Symbols.info)
                        Text("Delegation transfers your voting power to another address. You can revoke at any time.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Delegation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { viewModel.showDelegation = false }
                }
            }
            .task {
                await viewModel.loadDelegations()
            }
        }
    }
}

// MARK: - Proposal Card

struct ProposalCard: View {
    let proposal: GovernanceProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: proposal.status.icon)
                    .foregroundStyle(proposal.status.color)
                Text(proposal.status.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(proposal.status.color)

                Spacer()

                Text(proposal.category.rawValue)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.backgroundSecondary)
                    .cornerRadius(6)
            }

            Text(proposal.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(proposal.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // Vote progress
            VStack(spacing: 6) {
                HStack {
                    VoteBar(label: "For", percentage: proposal.forPercentage, color: .voteFor)
                    VoteBar(label: "Against", percentage: proposal.againstPercentage, color: .voteAgainst)
                }

                HStack {
                    Text("\(proposal.totalVotes) votes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if proposal.isVotingActive {
                        Text(proposal.timeRemaining)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.statusInfo)
                    }
                }
            }

            // Quorum progress
            VStack(spacing: 4) {
                HStack {
                    Text("Quorum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(proposal.totalVotes)/\(proposal.quorumRequired)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(proposal.quorumReached ? .quorumMet : .statusWarning)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray5))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(proposal.quorumReached ? Color.quorumMet : Color.statusWarning)
                            .frame(width: geo.size.width * proposal.quorumProgress)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding()
        .background(Color.backgroundPrimary)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(proposal.title), Status: \(proposal.status.rawValue), \(proposal.totalVotes) votes")
    }
}

struct VoteBar: View {
    let label: String
    let percentage: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption2)
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * percentage)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Proposal Detail

struct ProposalDetailSheet: View {
    let proposal: GovernanceProposal
    @ObservedObject var viewModel: GovernanceViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status header
                    HStack {
                        Label(proposal.status.rawValue, systemImage: proposal.status.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(proposal.status.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(proposal.status.color.opacity(0.12))
                            .cornerRadius(8)

                        Spacer()

                        Text(proposal.category.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.backgroundSecondary)
                            .cornerRadius(6)
                    }

                    Text(proposal.title)
                        .font(.title3.weight(.bold))

                    // Proposer info
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Proposed by \(proposal.proposerName)")
                                .font(.caption.weight(.medium))
                            Text(proposal.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text(proposal.description)
                        .font(.body)

                    if let componentRef = proposal.componentReference {
                        HStack(spacing: 4) {
                            Image(systemName: "cube")
                            Text("References Component \(componentRef)")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.statusInfo)
                        .padding(8)
                        .background(Color.statusInfo.opacity(0.08))
                        .cornerRadius(8)
                    }

                    Divider()

                    // Voting results
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voting Results")
                            .font(.headline)

                        VoteResultRow(label: "For", count: proposal.forVotes, percentage: proposal.forPercentage, color: .voteFor)
                        VoteResultRow(label: "Against", count: proposal.againstVotes, percentage: proposal.againstPercentage, color: .voteAgainst)
                        VoteResultRow(label: "Abstain", count: proposal.abstainVotes, percentage: proposal.abstainPercentage, color: .voteAbstain)

                        // Quorum progress
                        VStack(spacing: 6) {
                            HStack {
                                Text("Quorum Progress")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(proposal.quorumReached ? "Reached" : "Not Reached")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(proposal.quorumReached ? .statusSuccess : .statusWarning)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(.systemGray5))
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(proposal.quorumReached ? Color.quorumMet : Color.statusWarning)
                                        .frame(width: geo.size.width * proposal.quorumProgress)
                                        .animation(.easeInOut(duration: 0.5), value: proposal.quorumProgress)
                                }
                            }
                            .frame(height: 8)

                            Text("\(proposal.totalVotes) of \(proposal.quorumRequired) votes needed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Vote buttons
                    if proposal.isVotingActive && !viewModel.hasVoted {
                        Divider()
                        VStack(spacing: 12) {
                            Text("Cast Your Vote")
                                .font(.headline)
                            Text(proposal.timeRemaining)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 12) {
                                ForEach(VoteChoice.allCases, id: \.self) { choice in
                                    Button {
                                        Task { await viewModel.castVote(choice) }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: choice.icon)
                                                .font(.title3)
                                            Text(choice.rawValue)
                                                .font(.caption.weight(.semibold))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(choice.color.opacity(0.12))
                                        .foregroundStyle(choice.color)
                                        .cornerRadius(12)
                                    }
                                    .disabled(viewModel.isVoting)
                                }
                            }

                            if viewModel.isVoting {
                                ProgressView("Submitting vote...")
                                    .padding(.top, 4)
                            }
                        }
                    }

                    if viewModel.hasVoted, let vote = viewModel.userVote {
                        HStack(spacing: 8) {
                            Image(systemName: Symbols.complete)
                                .foregroundStyle(.statusSuccess)
                            Text("You voted: \(vote.rawValue)")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.statusSuccess.opacity(0.08))
                        .cornerRadius(12)
                    }

                    if let txHash = proposal.executionTransactionHash {
                        HStack(spacing: 4) {
                            Image(systemName: Symbols.link)
                            Text("Tx: \(txHash.prefix(20))...")
                                .font(.caption.monospaced())
                        }
                        .foregroundStyle(.statusInfo)
                    }
                }
                .padding()
            }
            .navigationTitle("Proposal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct VoteResultRow: View {
    let label: String
    let count: Int
    let percentage: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(count) votes (\(Int(percentage * 100))%)")
                    .font(.subheadline.weight(.medium))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * percentage)
                        .animation(.easeInOut(duration: 0.5), value: percentage)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Supporting Views

struct GovernanceStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 80)
        .padding(.vertical, 12)
        .background(Color.backgroundSecondary)
        .cornerRadius(12)
    }
}

struct StatusFilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isSelected ? color.opacity(0.15) : Color.backgroundSecondary)
                .foregroundStyle(isSelected ? color : .primary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct ProposalSkeletonCard: View {
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                RoundedRectangle(cornerRadius: 4).frame(width: 60, height: 14)
                Spacer()
                RoundedRectangle(cornerRadius: 4).frame(width: 80, height: 14)
            }
            RoundedRectangle(cornerRadius: 4).frame(height: 18)
            RoundedRectangle(cornerRadius: 4).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).frame(width: 200, height: 12)
        }
        .foregroundStyle(Color(.systemGray5))
        .padding()
        .opacity(shimmer ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: shimmer)
        .onAppear { shimmer = true }
    }
}

#Preview("Governance") {
    NavigationStack {
        GovernanceView()
    }
}
