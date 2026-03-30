// HomeView.swift
// MTRX
//
// Trinity conversation space — main home screen with AI chat, quick actions, portfolio summary.

import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var trinityEngine: TrinityEngine
    @EnvironmentObject var walletManager: WalletManager

    @State private var trinityInput: String = ""
    @State private var messages: [TrinityMessage] = []
    @State private var showQuickActions: Bool = true
    @State private var isListening: Bool = false
    @State private var scrollProxy: ScrollViewProxy?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                portfolioHeader
                trinityConversation
                quickActionsBar
                trinityInputBar
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("MTRX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    notificationButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    scanButton
                }
            }
        }
    }

    // MARK: - Portfolio Header

    private var portfolioHeader: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Total Portfolio")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)

                    Text(formattedPortfolioValue)
                        .font(.mtrxMonoLarge)
                        .foregroundStyle(Color.labelPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("24h Change")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.trendUp)
                        Text("+2.34%")
                    }
                    .font(.mtrxHeadlineTabular)
                    .foregroundStyle(Color.priceUp)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.backgroundSecondary)
    }

    // MARK: - Trinity Conversation

    private var trinityConversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    if messages.isEmpty {
                        trinityWelcome
                    } else {
                        ForEach(messages) { message in
                            TrinityMessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if trinityEngine.isProcessing {
                        TrinityTypingIndicator()
                            .id("typing")
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    // MARK: - Trinity Welcome

    private var trinityWelcome: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: Spacing.xxl)

            Image(systemName: Symbols.trinityActive)
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient.mtrxTrinity)
                .mtrxPulse(isActive: true)

            VStack(spacing: Spacing.sm) {
                Text("Trinity")
                    .font(.mtrxTitle1)
                    .foregroundStyle(Color.labelPrimary)

                Text("Your intelligent DeFi assistant. Ask me anything about your portfolio, contracts, or the market.")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: Spacing.xxl)
        }
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: - Quick Actions Bar

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                QuickActionChip(icon: Symbols.send, label: "Send") { }
                QuickActionChip(icon: Symbols.receive, label: "Receive") { }
                QuickActionChip(icon: Symbols.swap, label: "Swap") { }
                QuickActionChip(icon: Symbols.stake, label: "Stake") { }
                QuickActionChip(icon: Symbols.contractCreate, label: "Contract") { }
                QuickActionChip(icon: Symbols.marketplace, label: "Browse") { }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.backgroundSecondary)
        .opacity(showQuickActions ? 1 : 0)
        .frame(height: showQuickActions ? nil : 0)
    }

    // MARK: - Trinity Input Bar

    private var trinityInputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask Trinity...", text: $trinityInput)
                .font(.mtrxBody)
                .padding(.horizontal, Spacing.textFieldPadding)
                .padding(.vertical, Spacing.sm)
                .background(Color.surfaceOverlay)
                .clipShape(Capsule())

            Button {
                isListening.toggle()
            } label: {
                Image(systemName: isListening ? Symbols.microphoneSlash : Symbols.microphone)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isListening ? Color.statusError : Color.accentPrimary)
                    .mtrxMinTouchTarget()
            }

            Button {
                sendMessage()
            } label: {
                Image(systemName: Symbols.send)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(trinityInput.isEmpty ? Color.labelTertiary : Color.accentPrimary)
                    .mtrxMinTouchTarget()
            }
            .disabled(trinityInput.isEmpty)
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Toolbar Items

    private var notificationButton: some View {
        Button {
            // Navigate to notifications
        } label: {
            Image(systemName: Symbols.notificationBadge)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var scanButton: some View {
        Button {
            // Open QR scanner
        } label: {
            Image(systemName: Symbols.qrScanner)
        }
    }

    // MARK: - Helpers

    private var formattedPortfolioValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: walletManager.balance as NSDecimalNumber) ?? "$0.00"
    }

    private func sendMessage() {
        guard !trinityInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let userMessage = TrinityMessage(role: .user, content: trinityInput)
        messages.append(userMessage)
        trinityInput = ""
        showQuickActions = false

        // Scroll to bottom
        withAnimation(Motion.springDefault) {
            scrollProxy?.scrollTo(userMessage.id, anchor: .bottom)
        }
    }
}

// MARK: - Supporting Types

struct TrinityMessage: Identifiable {
    let id = UUID()
    let role: TrinityRole
    let content: String
    let timestamp = Date()

    enum TrinityRole {
        case user
        case trinity
        case system
    }
}

// MARK: - Message Bubble

struct TrinityMessageBubble: View {
    let message: TrinityMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: Spacing.xxl) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xs) {
                Text(message.content)
                    .font(.mtrxBody)
                    .foregroundStyle(message.role == .user ? .white : Color.labelPrimary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(Color.accentPrimary)
                            : AnyShapeStyle(Color.surfaceCard)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))

                Text(message.timestamp, style: .time)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelTertiary)
            }

            if message.role == .trinity { Spacer(minLength: Spacing.xxl) }
        }
    }
}

// MARK: - Typing Indicator

struct TrinityTypingIndicator: View {
    @State private var dotScale: [CGFloat] = [1, 1, 1]

    var body: some View {
        HStack {
            HStack(spacing: Spacing.xs) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.trinityPrimary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotScale[index])
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.surfaceCard)
            .clipShape(Capsule())

            Spacer()
        }
        .onAppear { animateDots() }
    }

    private func animateDots() {
        for index in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.15)
            ) {
                dotScale[index] = 1.4
            }
        }
    }
}

// MARK: - Quick Action Chip

struct QuickActionChip: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.mtrxCaptionBold)
            }
            .padding(.horizontal, Spacing.chipHorizontal)
            .padding(.vertical, Spacing.chipVertical)
            .background(Color.surfaceOverlay)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(WalletManager())
        .environmentObject(TrinityEngine())
}
