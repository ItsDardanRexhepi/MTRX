// HomeView.swift
// MTRX — Home tab.
//
// The welcome screen: greets the user, puts their agents one tap away,
// and surfaces the most-used actions immediately. Chats open full-screen
// over the dashboard and slide back down to it.

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var walletManager: WalletManager
    @ObservedObject private var chatStore = ConversationStore.shared

    @State private var presentedChat: ChatLaunch?
    @State private var appeared = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""

    /// What to open the chat with: an agent and an optional prefill.
    struct ChatLaunch: Identifiable {
        let id = UUID()
        let agent: AgentAccessControl.ActiveAgent
        var prompt: String?
    }

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .trinityGlow)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    greetingHeader
                        .mtrxStaggeredAppearance(index: 0, isVisible: appeared)

                    agentSection
                        .mtrxStaggeredAppearance(index: 1, isVisible: appeared)

                    quickActionsSection
                        .mtrxStaggeredAppearance(index: 2, isVisible: appeared)

                    portfolioSnapshot
                        .mtrxStaggeredAppearance(index: 3, isVisible: appeared)
                }
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .onAppear {
            withAnimation(Motion.springDefault.delay(0.1)) {
                appeared = true
            }
        }
        .fullScreenCover(item: $presentedChat) { launch in
            AgentConversationView(
                userID: appState.currentUserID,
                initialAgent: launch.agent,
                initialPrompt: launch.prompt,
                isModal: true
            )
            .environmentObject(appState)
            .environmentObject(walletManager)
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(timeGreeting)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.trinityPrimary.opacity(0.85))
                .textCase(.uppercase)
                .kerning(1.6)

            HStack(spacing: Spacing.sm) {
                Text(firstName)
                    .font(.mtrxLargeTitle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.labelPrimary, Color.trinityPrimary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Button {
                    nameDraft = appState.displayName
                    showNameEditor = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.labelTertiary)
                }
                .buttonStyle(.plain)
            }
            .alert("Your Name", isPresented: $showNameEditor) {
                TextField("Name", text: $nameDraft)
                Button("Save") { appState.updateDisplayName(nameDraft) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Shown in your greeting and on your posts.")
            }

            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelTertiary)
        }
        .padding(.top, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Soft signature glow rising behind the greeting.
            Circle()
                .fill(Color.trinityPrimary.opacity(0.13))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -60, y: -70),
            alignment: .topLeading
        )
    }

    private var timeGreeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome back"
        }
    }

    private var firstName: String {
        let name = appState.displayName
        if let first = name.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        return name.isEmpty ? "Welcome" : name
    }

    // MARK: - Agents

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            sectionTitle("Your Agents")

            agentCard(
                agent: .trinity,
                name: "Trinity",
                tagline: "Your assistant — money, markets, answers",
                colors: [.trinityPrimary, .trinitySecondary]
            )

            agentCard(
                agent: .morpheus,
                name: "Morpheus",
                tagline: "The guardian — security and judgment",
                colors: [.statusError, .statusError.opacity(0.7)]
            )

            // Neo answers only to the owner.
            if AgentAccessControl.shared.userType(for: appState.currentUserID) == .owner {
                agentCard(
                    agent: .neo,
                    name: "Neo",
                    tagline: "The coordinator — full platform command",
                    colors: [.statusSuccess, .accentPrimary]
                )
            }
        }
    }

    private func agentCard(
        agent: AgentAccessControl.ActiveAgent,
        name: String,
        tagline: String,
        colors: [Color]
    ) -> some View {
        Button {
            MtrxHaptics.impact(.medium)
            presentedChat = ChatLaunch(agent: agent)
        } label: {
            HStack(spacing: Spacing.ms) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                    Text(String(name.prefix(1)))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .mtrxGlow(color: colors.first ?? .accentPrimary, radius: 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)

                    Text(lastMessagePreview(for: agent) ?? tagline)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle((colors.first ?? .accentPrimary).opacity(0.8))
            }
            .padding(Spacing.md)
            .background(.ultraThinMaterial)
            .background((colors.first ?? .clear).opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                (colors.first ?? .clear).opacity(0.45),
                                (colors.first ?? .clear).opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: (colors.first ?? .clear).opacity(0.10), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func lastMessagePreview(for agent: AgentAccessControl.ActiveAgent) -> String? {
        guard let last = chatStore.mostRecent(agent: agent)?.messages.last else { return nil }
        let prefix = last.role == .user ? "You: " : ""
        let flattened = last.text.replacingOccurrences(of: "\n", with: " ")
        return prefix + flattened
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            sectionTitle("Quick Actions")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.ms) {
                quickAction("Send Money", icon: "arrow.up.circle.fill", color: .accentPrimary, prompt: "Send $")
                quickAction("Swap", icon: "arrow.triangle.2.circlepath.circle.fill", color: .trinityPrimary, prompt: "Swap 1 ETH to USDC")
                quickAction("Stake", icon: "lock.circle.fill", color: .statusSuccess, prompt: "Stake 0.5 ETH")
                quickAction("Deploy Contract", icon: "doc.badge.gearshape.fill", color: .accentTertiary, prompt: "Deploy a smart contract called ")
                quickAction("Check Balance", icon: "chart.pie.fill", color: .statusInfo, prompt: "What's my balance?")
                quickAction("Market Check", icon: "chart.line.uptrend.xyaxis.circle.fill", color: .trinitySecondary, prompt: "What's bitcoin at right now?")
            }
        }
    }

    private func quickAction(_ title: String, icon: String, color: Color, prompt: String) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            presentedChat = ChatLaunch(agent: .trinity, prompt: prompt)
        } label: {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }
            .padding(Spacing.ms)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(.ultraThinMaterial)
            .background(color.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Portfolio Snapshot

    private var portfolioSnapshot: some View {
        VStack(alignment: .leading, spacing: Spacing.ms) {
            sectionTitle("Portfolio")

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        walletManager.totalPortfolioValue,
                        format: .currency(code: "USD").precision(.fractionLength(2))
                    )
                    .font(.mtrxTitle1)
                    .foregroundStyle(Color.labelPrimary)

                    Spacer()

                    HStack(spacing: 3) {
                        Image(systemName: walletManager.portfolioChange24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(format: "%.2f%%", abs(walletManager.portfolioChange24h)))
                            .font(.mtrxCaptionBold)
                    }
                    .foregroundStyle(walletManager.portfolioChange24h >= 0 ? Color.statusSuccess : Color.statusError)
                }

                Divider().overlay(Color.labelQuaternary.opacity(0.3))

                HStack(spacing: Spacing.md) {
                    ForEach(walletManager.tokens.prefix(3), id: \.symbol) { token in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.symbol)
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                            Text(String(format: "%.3f", token.balance))
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelPrimary)
                        }
                        if token.symbol != walletManager.tokens.prefix(3).last?.symbol {
                            Spacer()
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .background(.ultraThinMaterial)
            .background(Color.trinityPrimary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.trinityPrimary.opacity(0.35), Color.trinityPrimary.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.trinityPrimary.opacity(0.08), radius: 14, y: 6)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.mtrxCaptionBold)
            .foregroundStyle(Color.labelSecondary)
            .textCase(.uppercase)
            .kerning(1.1)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(WalletManager())
}
