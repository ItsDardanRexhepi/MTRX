// AgentIdentityView.swift
// MTRX
//
// Agent identity — profile card, capabilities, interaction history, emergency revoke.

import SwiftUI

// MARK: - Data Models

struct AgentProfileItem: Identifiable {
    let id = UUID()
    let name: String
    var capabilities: [String]
    let trustLevel: String
    let interactionCount: Int
}

struct InteractionItem: Identifiable {
    let id = UUID()
    let action: String
    let target: String
    let timestamp: String
    let outcome: String
}

// MARK: - View Model

@MainActor
class AgentIdentityViewModel: ObservableObject {
    @Published var agent: AgentProfileItem?
    @Published var interactions: [InteractionItem] = []
    @Published var newCapability: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showRevokeConfirmation: Bool = false
    @Published var isRegistering: Bool = false
    @Published var isRevoking: Bool = false
    @Published var isDemo: Bool = false
    @Published var actionUnavailable: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live agent identity from AgentIdentityService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let profile = try await AgentIdentityService.shared.getAgentIdentity(address: address)
                agent = AgentProfileItem(
                    name: profile.name, capabilities: profile.capabilities,
                    trustLevel: profile.trustLevel, interactionCount: profile.interactionCount
                )
                let history = try await AgentIdentityService.shared.getInteractionHistory(agentId: profile.agentId)
                interactions = history.map { i in
                    InteractionItem(
                        action: i.action, target: i.target,
                        timestamp: Self.dateFormatter.string(from: i.timestamp),
                        outcome: i.outcome
                    )
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live agent identity unavailable — showing demo."
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(700))
            agent = AgentIdentityViewModel.sampleAgent
            interactions = AgentIdentityViewModel.sampleInteractions
            isDemo = true
            isLoading = false
        } catch {
            errorMessage = "Unable to load agent identity."
            isLoading = false
        }
    }

    func registerCapability() async {
        guard !newCapability.isEmpty else { return }
        // Honest failure: no agent-identity registry / on-chain path is wired.
        // Do not append the capability as if it were registered.
        isRegistering = false
        actionUnavailable = true
    }

    func revokeAgent() async {
        // Honest failure: no agent-identity registry path is wired to revoke.
        // Do not clear the agent as if a revocation succeeded.
        isRevoking = false
        showRevokeConfirmation = false
        actionUnavailable = true
    }

    static let sampleAgent = AgentProfileItem(
        name: "Trinity Agent v2.1",
        capabilities: ["DeFi Swaps", "Portfolio Rebalance", "Governance Voting", "Alert Management"],
        trustLevel: "Verified",
        interactionCount: 1_247
    )

    static let sampleInteractions: [InteractionItem] = [
        InteractionItem(action: "Swap", target: "Uniswap V3", timestamp: "5m ago", outcome: "Success"),
        InteractionItem(action: "Vote", target: "Aave Proposal #142", timestamp: "2h ago", outcome: "Success"),
        InteractionItem(action: "Rebalance", target: "Portfolio", timestamp: "6h ago", outcome: "Success"),
        InteractionItem(action: "Alert", target: "ETH Price Drop", timestamp: "1d ago", outcome: "Triggered"),
        InteractionItem(action: "Swap", target: "Curve Finance", timestamp: "2d ago", outcome: "Failed"),
        InteractionItem(action: "Delegate", target: "ENS DAO", timestamp: "3d ago", outcome: "Success")
    ]
}

// MARK: - Agent Identity View

struct AgentIdentityView: View {
    @StateObject private var viewModel = AgentIdentityViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.agent == nil {
                    MtrxLoadingView()
                } else if let error = viewModel.errorMessage, viewModel.agent == nil {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else if viewModel.agent == nil {
                    MtrxEmptyState(
                        icon: "person.badge.shield.checkmark.fill",
                        title: "No Agent Registered",
                        message: "Register an AI agent identity to enable autonomous on-chain actions."
                    )
                } else {
                    agentContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Agent Identity")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .task { await viewModel.load() }
            .honestActionAlert($viewModel.actionUnavailable, message: "Editing agent identity isn't available in this build yet. Nothing was changed.")
            .alert("Revoke Agent Identity", isPresented: $viewModel.showRevokeConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Revoke", role: .destructive) {
                    Task { await viewModel.revokeAgent() }
                }
            } message: {
                Text("This will permanently revoke all agent capabilities and permissions. This action cannot be undone.")
            }
        }
    }

    // MARK: - Content

    private var agentContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                if let agent = viewModel.agent {
                    profileCard(agent)
                    capabilitiesSection(agent)
                    registerCapabilitySection
                }
                if !viewModel.interactions.isEmpty {
                    interactionHistorySection
                }
                emergencySection
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Profile Card

    private func profileCard(_ agent: AgentProfileItem) -> some View {
        MtrxCard(style: .glass, accentEdge: .leading) {
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.ms) {
                    MtrxAvatar(
                        symbol: "cpu.fill",
                        color: .accentPrimary,
                        size: 56
                    )

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(agent.name)
                            .font(.mtrxTitle3)
                            .foregroundStyle(Color.labelPrimary)

                        HStack(spacing: Spacing.sm) {
                            MtrxBadge(text: agent.trustLevel, style: .success)
                            Text("\(agent.interactionCount) interactions")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }

                    Spacer()
                }

                MtrxDivider()

                HStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.xs) {
                        Text("\(agent.capabilities.count)")
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.labelPrimary)
                        Text("Capabilities")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }

                    VStack(spacing: Spacing.xs) {
                        Text("\(agent.interactionCount)")
                            .font(.mtrxMonoMedium)
                            .foregroundStyle(Color.labelPrimary)
                        Text("Interactions")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }

                    VStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.shieldCheck)
                            .font(.system(size: 18))
                            .foregroundStyle(Color.statusSuccess)
                        Text("Trust")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Capabilities

    private func capabilitiesSection(_ agent: AgentProfileItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Capabilities")
                .padding(.horizontal, Spacing.contentPadding)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.sm) {
                ForEach(agent.capabilities, id: \.self) { capability in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.complete)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.statusSuccess)
                        Text(capability)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.ms)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Register Capability

    private var registerCapabilitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Register Capability")
                .padding(.horizontal, Spacing.contentPadding)

            MtrxCard(style: .standard) {
                HStack(spacing: Spacing.sm) {
                    MtrxTextField(
                        placeholder: "e.g. NFT Trading",
                        text: $viewModel.newCapability
                    )

                    Button {
                        Task { await viewModel.registerCapability() }
                    } label: {
                        Text(viewModel.isRegistering ? "..." : "Add")
                    }
                    .buttonStyle(MtrxButtonStyle(
                        variant: .primary,
                        size: .compact,
                        isLoading: viewModel.isRegistering
                    ))
                    .disabled(viewModel.newCapability.isEmpty || viewModel.isRegistering)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
        }
    }

    // MARK: - Interaction History

    private var interactionHistorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MtrxSectionHeader(title: "Interaction History")
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.interactions) { interaction in
                MtrxCard(style: .standard) {
                    HStack(spacing: Spacing.ms) {
                        MtrxAvatar(
                            symbol: interactionIcon(for: interaction.action),
                            color: outcomeColor(for: interaction.outcome),
                            size: 36
                        )

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                Text(interaction.action)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.labelPrimary)
                                Text(interaction.target)
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                            }
                            Text(interaction.timestamp)
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                        }

                        Spacer()

                        MtrxBadge(
                            text: interaction.outcome,
                            style: outcomeBadgeStyle(for: interaction.outcome)
                        )
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    // MARK: - Emergency Section

    private var emergencySection: some View {
        VStack(spacing: Spacing.sm) {
            MtrxDivider()
                .padding(.horizontal, Spacing.contentPadding)

            Button {
                viewModel.showRevokeConfirmation = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: Symbols.alertCritical)
                        .font(.system(size: 14))
                    Text("Emergency Revoke")
                }
            }
            .buttonStyle(MtrxButtonStyle(
                variant: .destructive,
                size: .large,
                isLoading: viewModel.isRevoking,
                fullWidth: true
            ))
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Helpers

    private func interactionIcon(for action: String) -> String {
        switch action {
        case "Swap": return Symbols.swap
        case "Vote": return Symbols.vote
        case "Rebalance": return Symbols.processing
        case "Alert": return Symbols.notification
        case "Delegate": return Symbols.delegate
        default: return Symbols.transaction
        }
    }

    private func outcomeColor(for outcome: String) -> Color {
        switch outcome {
        case "Success": return .statusSuccess
        case "Failed": return .statusError
        case "Triggered": return .statusInfo
        default: return .labelSecondary
        }
    }

    private func outcomeBadgeStyle(for outcome: String) -> MtrxBadge.BadgeStyle {
        switch outcome {
        case "Success": return .success
        case "Failed": return .error
        case "Triggered": return .info
        default: return .neutral
        }
    }
}

// MARK: - Preview

#Preview {
    AgentIdentityView()
        .preferredColorScheme(.dark)
}
