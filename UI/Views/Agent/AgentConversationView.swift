// AgentConversationView.swift
// MTRX
//
// Home tab — Trinity AI conversation interface.
// Handles Trinity, Morpheus, and Neo interactions with full design system.

import SwiftUI

// MARK: - Agent Conversation View

struct AgentConversationView: View {
    @StateObject private var viewModel = AgentConversationViewModel()
    @ObservedObject private var accessControl = AgentAccessControl.shared
    @ObservedObject private var morpheus = MorpheusInterventions.shared
    @EnvironmentObject private var walletManager: WalletManager
    @FocusState private var isInputFocused: Bool

    let userID: String

    /// Open straight into this agent's chat (Home screen agent cards).
    var initialAgent: AgentAccessControl.ActiveAgent?
    /// Pre-fill the input bar (Home screen quick actions).
    var initialPrompt: String?
    /// Presented modally → show a dismiss chevron in the header.
    var isModal: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var isListening = false
    @State private var appeared = false
    @State private var showAgentIdentity = false
    @State private var showSearch = false
    @State private var showChats = false
    @State private var dismissDrag: CGFloat = 0

    var body: some View {
        ZStack {
            // Background
            MtrxGradientBackground(style: .trinityGlow)

            // The room takes on its agent's signature color — a faint
            // aurora that shifts cyan/red/green with who's listening.
            Circle()
                .fill(agentAccent.opacity(0.11))
                .frame(width: 400, height: 400)
                .blur(radius: 95)
                .offset(y: -270)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.7), value: viewModel.activeAgent)

            VStack(spacing: 0) {
                // The agent space wears its own header; the tab-style
                // header remains for any non-modal embedding.
                if isModal {
                    agentSpaceHeader
                } else {
                    agentHeader
                }

                // Offline indicator
                if viewModel.isOffline {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .medium))
                        Text("Running locally")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                }

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Spacing.ms) {
                            // First boot card
                            if viewModel.showFirstBoot {
                                firstBootMessage
                                    .padding(.top, Spacing.xl)
                                    .padding(.bottom, Spacing.md)
                                    .transition(.mtrxSlideUp)
                            }

                            ForEach(viewModel.messages) { message in
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    MessageBubble(message: message)

                                    // Actionable suggestion chips — only on the
                                    // most recent agent message, so stale
                                    // confirmations can't be tapped.
                                    if message.id == viewModel.messages.last?.id,
                                       message.role == .agent,
                                       !message.suggestedActions.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: Spacing.sm) {
                                                ForEach(message.suggestedActions) { action in
                                                    Button {
                                                        MtrxHaptics.impact(.medium)
                                                        viewModel.handleSuggestedAction(action.action)
                                                    } label: {
                                                        Text(action.title)
                                                            .font(.mtrxCaptionBold)
                                                            .foregroundStyle(
                                                                action.action == "demo_cancel"
                                                                    ? Color.labelSecondary
                                                                    : Color.accentPrimary
                                                            )
                                                            .padding(.horizontal, Spacing.md)
                                                            .padding(.vertical, Spacing.sm)
                                                            .background(
                                                                Capsule().fill(
                                                                    action.action == "demo_cancel"
                                                                        ? Color.backgroundTertiary
                                                                        : Color.accentPrimary.opacity(0.12)
                                                                )
                                                            )
                                                            .overlay(
                                                                Capsule().stroke(
                                                                    action.action == "demo_cancel"
                                                                        ? Color.clear
                                                                        : Color.accentPrimary.opacity(0.35),
                                                                    lineWidth: 1
                                                                )
                                                            )
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.leading, Spacing.xl)
                                        }
                                        .transition(.mtrxSlideUp)
                                    }
                                }
                                .id(message.id)
                            }

                            if viewModel.isTyping {
                                TypingIndicator(agent: viewModel.activeAgent)
                                    .id("typingIndicator")
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages.count) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.isTyping) {
                        if viewModel.isTyping {
                            scrollToBottom(proxy: proxy, anchor: .bottom)
                        }
                    }
                }

                // Quick action chips
                quickActionChips

                // Input bar
                inputBar
            }

            // The agent space's living edge light.
            if isModal {
                edgeGlow
            }

            // Morpheus overlay
            if morpheus.isPresenting, let intervention = morpheus.activeIntervention {
                MorpheusOverlay(intervention: intervention)
                    .transition(.opacity.animation(Motion.springDefault))
            }

            // Scenario 2 ban overlay
            if let ban = accessControl.banEvent {
                BanOverlay(event: ban)
                    .transition(.opacity.animation(Motion.springDefault))
            }

            // Scenario 2 community alert
            if let alert = accessControl.scenarioTwoAlert {
                CommunityAlertOverlay(alert: alert)
                    .transition(.mtrxSlideUp)
            }
        }
        .offset(y: isModal ? dismissDrag : 0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    // Only from the header zone, only downward — never
                    // fights the message scroll or the keyboard.
                    guard isModal, value.startLocation.y < 190,
                          value.translation.height > 0 else { return }
                    dismissDrag = value.translation.height
                }
                .onEnded { value in
                    guard isModal else { return }
                    if value.startLocation.y < 190, value.translation.height > 130 {
                        dismiss()
                    } else {
                        withAnimation(Motion.springSnappy) { dismissDrag = 0 }
                    }
                }
        )
        .onAppear {
            viewModel.setup(userID: userID, walletManager: walletManager)
            if let initialAgent {
                viewModel.openAgentChat(initialAgent)
            }
            if let initialPrompt, viewModel.inputText.isEmpty {
                viewModel.inputText = initialPrompt
                isInputFocused = true
            }
            withAnimation(Motion.springDefault.delay(0.2)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showAgentIdentity) {
            AgentIdentityView()
        }
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
        .sheet(isPresented: $showChats) {
            ChatHistorySheet(
                currentID: viewModel.conversationID,
                allowNeo: AgentAccessControl.shared.userType(for: userID) == .owner,
                onSelect: { viewModel.openConversation($0) },
                onNew: { viewModel.startNewConversation(agent: $0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Agent Space Header
    //
    // One floating glass capsule is the entire identity AND switcher:
    // the active agent shows as an expanded orb with its name; the
    // others wait as quiet orbs one tap away. The highlight slides
    // between agents with a shared-element morph.

    @Namespace private var agentSegmentNS

    private var availableAgents: [AgentAccessControl.ActiveAgent] {
        AgentAccessControl.shared.userType(for: userID) == .owner
            ? [.trinity, .morpheus, .neo]
            : [.trinity, .morpheus]
    }

    private var agentSpaceHeader: some View {
        HStack(spacing: Spacing.sm) {
            chromeButton("chevron.down") { dismiss() }

            Spacer(minLength: 0)

            switcherCapsule

            Spacer(minLength: 0)

            chromeButton("square.and.pencil") { showChats = true }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private func chromeButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.labelSecondary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.07), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var switcherCapsule: some View {
        HStack(spacing: 3) {
            ForEach(availableAgents, id: \.self) { agent in
                agentSegment(agent)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func agentSegment(_ agent: AgentAccessControl.ActiveAgent) -> some View {
        let isActive = viewModel.activeAgent == agent
        let colors = orbPalette(agent)

        return Button {
            guard !isActive else { return }
            MtrxHaptics.impact(.medium)
            withAnimation(Motion.springSnappy) {
                viewModel.openAgentChat(agent)
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.85), colors.0, colors.1],
                            center: .init(x: 0.35, y: 0.28),
                            startRadius: 1,
                            endRadius: isActive ? 16 : 13
                        )
                    )
                    .frame(width: isActive ? 24 : 20, height: isActive ? 24 : 20)
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.8))
                    .shadow(color: colors.0.opacity(isActive ? 0.5 : 0.0), radius: 5)

                if isActive {
                    Text(AgentConversationViewModel.displayName(of: agent))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                        .fixedSize()

                    Circle()
                        .fill(Color.statusSuccess)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, isActive ? 12 : 7)
            .padding(.vertical, 6)
            .background {
                if isActive {
                    Capsule()
                        .fill(colors.0.opacity(0.15))
                        .overlay(Capsule().stroke(colors.0.opacity(0.32), lineWidth: 1))
                        .matchedGeometryEffect(id: "activeAgentSegment", in: agentSegmentNS)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Orb color pairs — Morpheus wears rose-crimson here, warmer and
    /// calmer than alert red.
    private func orbPalette(_ agent: AgentAccessControl.ActiveAgent) -> (Color, Color) {
        switch agent {
        case .trinity: return (.trinityPrimary, .trinitySecondary)
        case .morpheus: return (Color(red: 0.95, green: 0.36, blue: 0.42), Color(red: 0.58, green: 0.10, blue: 0.24))
        case .neo: return (.statusSuccess, .accentPrimary)
        }
    }

    /// The agent space wears a living edge light — the screen border
    /// glows in the active agent's colors, so the whole surface reads
    /// as its own layer over the app.
    private var edgeGlow: some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    colors: [agentAccent, .purple.opacity(0.6), agentAccent.opacity(0.2), agentAccent],
                    center: .center
                ),
                lineWidth: 2
            )
            .blur(radius: 7)
            .opacity(0.32)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: - Scroll Helper

    private func scrollToBottom(proxy: ScrollViewProxy, anchor: UnitPoint = .bottom) {
        if let last = viewModel.messages.last {
            withAnimation(Motion.springSnappy) {
                proxy.scrollTo(viewModel.isTyping ? AnyHashable("typingIndicator") : AnyHashable(last.id), anchor: anchor)
            }
        }
    }

    // MARK: - Agent Header

    private var agentHeader: some View {
        HStack(spacing: Spacing.ms) {
            // Dismiss chevron when presented from the Home screen.
            if isModal {
                Button {
                    MtrxHaptics.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.labelSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }

            // Agent avatar — gradient circle with initial.
            // Long-press opens the AgentIdentityView sheet.
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: agentGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)

                Text(agentInitial)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .mtrxGlow(color: agentGradientColors.first ?? .accentPrimary, radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(agentName)
                    .font(.mtrxHeadline)
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(viewModel.isTyping ? Color.accentTertiary : Color.statusSuccess)
                        .frame(width: 6, height: 6)

                    Text(agentStatus)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            Spacer()

            // Chats button — saved history + new chats per agent
            Button {
                MtrxHaptics.impact(.light)
                showChats = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // Search button — opens SearchView sheet
            Button {
                MtrxHaptics.impact(.light)
                showSearch = true
            } label: {
                Image(systemName: Symbols.search)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // Crypto markets never close.
            MtrxBadge(text: "Markets Live", style: .success)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.ms)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5) {
            MtrxHaptics.impact(.medium)
            showAgentIdentity = true
        }
    }

    private var agentGradientColors: [Color] {
        switch viewModel.activeAgent {
        case .trinity: return [.trinityPrimary, .trinitySecondary]
        case .morpheus: return [.statusError, .statusError.opacity(0.7)]
        case .neo: return [.statusSuccess, .accentPrimary]
        }
    }

    /// The active agent's signature color — used for focus rings and
    /// the send button so the whole bar quietly matches who's listening.
    private var agentAccent: Color {
        agentGradientColors.first ?? .accentPrimary
    }

    private var agentInitial: String {
        switch viewModel.activeAgent {
        case .trinity: return "T"
        case .morpheus: return "M"
        case .neo: return "N"
        }
    }

    private var agentName: String {
        switch viewModel.activeAgent {
        case .trinity: return "Trinity"
        case .morpheus: return "Morpheus"
        case .neo: return "Neo"
        }
    }

    private var agentStatus: String {
        if viewModel.isTyping { return "typing..." }
        return "online"
    }

    private func agentDotColor(for name: String?) -> Color {
        switch name {
        case "Morpheus": return .statusError
        case "Neo": return .statusSuccess
        default: return .trinityPrimary
        }
    }

    // MARK: - First Boot Message

    private var firstBootMessage: some View {
        MtrxCard(style: .glass) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: Symbols.trinityActive)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.trinityPrimary)

                    Spacer()
                }

                Text("Hi, my name is Trinity")
                    .font(.mtrxTitle2)
                    .foregroundStyle(Color.labelPrimary)

                Text("Welcome to the world of MTRX, I'll be by your side the entire time if you need me")
                    .font(.mtrxBody)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.lg)
    }

    // MARK: - Quick Action Chips

    private var quickActionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                MtrxChip(label: "Check balance", icon: Symbols.wallet) {
                    insertQuickAction("Check my balance")
                }

                MtrxChip(label: "Send", icon: Symbols.send) {
                    insertQuickAction("Send")
                }

                MtrxChip(label: "Swap", icon: Symbols.swap) {
                    insertQuickAction("Swap tokens")
                }

                MtrxChip(label: "Deploy contract", icon: Symbols.contractCreate) {
                    insertQuickAction("Deploy a smart contract")
                }

                MtrxChip(label: "Marketplace", icon: Symbols.marketplace) {
                    insertQuickAction("Browse the marketplace")
                }

                MtrxChip(label: "Portfolio", icon: Symbols.portfolio) {
                    insertQuickAction("View my portfolio")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.surfaceCard.opacity(0.4))
    }

    private func insertQuickAction(_ text: String) {
        MtrxHaptics.impact(.light)
        viewModel.inputText = text
        viewModel.sendMessage()
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            // Microphone button
            Button {
                MtrxHaptics.impact(.light)
                isListening.toggle()
            } label: {
                Image(systemName: isListening ? Symbols.microphoneSlash : Symbols.microphone)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isListening ? Color.statusError : Color.labelTertiary)
                    .frame(width: 36, height: 36)
            }

            // Text field — addressed to whoever is in the room.
            TextField("Ask \(agentName)...", text: $viewModel.inputText, axis: .vertical)
                .font(.mtrxBody)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, Spacing.ms)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                        .fill(Color.surfaceOverlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.CornerRadius.xl, style: .continuous)
                        .stroke(
                            isInputFocused ? agentAccent.opacity(0.45) : Color.clear,
                            lineWidth: 1
                        )
                        .animation(.easeOut(duration: 0.18), value: isInputFocused)
                )

            // Send button
            Button {
                MtrxHaptics.impact(.light)
                viewModel.sendMessage()
            } label: {
                Image(systemName: Symbols.send)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.labelTertiary
                            : agentAccent
                    )
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: AgentMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 56) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.xs) {
                // Agent name label with colored dot
                if !isUser {
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(agentDotColor)
                            .frame(width: 8, height: 8)

                        Text(message.agentName ?? "Trinity")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(agentDotColor)
                    }
                    .padding(.leading, Spacing.xs)
                }

                // Bubble
                Text(message.text)
                    .font(.mtrxBody)
                    .foregroundStyle(isUser ? .white : Color.labelPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .clipShape(bubbleShape)
                    .overlay(
                        bubbleShape.stroke(
                            isUser ? Color.clear : agentDotColor.opacity(0.16),
                            lineWidth: 1
                        )
                    )

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelQuaternary)
                    .padding(.horizontal, Spacing.xs)
            }

            if !isUser { Spacer(minLength: 56) }
        }
    }

    private var bubbleBackground: some View {
        Group {
            if isUser {
                LinearGradient(
                    colors: [Color.accentPrimary, Color.accentPrimary.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.surfaceCard.overlay(agentDotColor.opacity(0.045))
            }
        }
    }

    private var bubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    private var agentDotColor: Color {
        switch message.agentName {
        case "Morpheus": return .statusError
        case "Neo": return .statusSuccess
        default: return .trinityPrimary
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    let agent: AgentAccessControl.ActiveAgent

    @State private var dotPhases: [Bool] = [false, false, false]

    private var dotColor: Color {
        switch agent {
        case .trinity: return .trinityPrimary
        case .morpheus: return .statusError
        case .neo: return .statusSuccess
        }
    }

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotPhases[i] ? 1.0 : 0.5)
                        .opacity(dotPhases[i] ? 1.0 : 0.35)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()
        }
        .onAppear {
            startPulse()
        }
    }

    private func startPulse() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                dotPhases[i] = true
            }
        }
    }
}

// MARK: - Morpheus Overlay

struct MorpheusOverlay: View {
    let intervention: MorpheusIntervention
    @ObservedObject private var morpheus = MorpheusInterventions.shared
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    if !intervention.requiresConfirmation && !intervention.autoDismiss {
                        morpheus.dismiss()
                    }
                }

            VStack(spacing: Spacing.lg) {
                // Morpheus avatar
                ZStack {
                    Circle()
                        .fill(Color.statusError.opacity(0.15))
                        .frame(width: 64, height: 64)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.statusError, Color.statusError.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)

                    Text("M")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .mtrxGlow(color: .statusError, radius: 10)

                Text("Morpheus")
                    .font(.mtrxTitle3)
                    .foregroundStyle(.white)

                Text(intervention.message)
                    .font(.mtrxBody)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.md)

                if intervention.requiresConfirmation {
                    HStack(spacing: Spacing.md) {
                        Button("Cancel") {
                            MtrxHaptics.impact(.light)
                            morpheus.dismiss()
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .ghost))

                        Button("I understand. Proceed.") {
                            MtrxHaptics.warning()
                            _ = morpheus.confirmAction()
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .destructive))
                    }
                    .padding(.top, Spacing.sm)
                } else if !intervention.autoDismiss {
                    Button("Continue") {
                        MtrxHaptics.impact(.light)
                        morpheus.dismiss()
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary))
                    .padding(.top, Spacing.sm)
                }
            }
            .padding(Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.xxl, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.CornerRadius.xxl, style: .continuous)
                            .stroke(Color.statusError.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(Spacing.lg)
            .mtrxScaleIn(isVisible: appeared)
        }
        .onAppear {
            withAnimation(Motion.springDefault) {
                appeared = true
            }
        }
    }
}

// MARK: - Ban Overlay (Scenario 2)

struct BanOverlay: View {
    let event: BanEvent
    @State private var remainingSeconds: Int = 10
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.statusError)
                    .mtrxGlow(color: .statusError, radius: 12)

                Text("Access Permanently Revoked")
                    .font(.mtrxTitle2)
                    .foregroundStyle(.white)

                Text("Your access to MTRX has been permanently revoked due to unauthorized activity.")
                    .font(.mtrxBody)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)

                Text("This message will disappear in \(remainingSeconds) seconds.")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
                    .padding(.top, Spacing.sm)
            }
            .mtrxScaleIn(isVisible: appeared)
        }
        .onAppear {
            withAnimation(Motion.springDefault) {
                appeared = true
            }
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                remainingSeconds -= 1
                if remainingSeconds <= 0 { timer.invalidate() }
            }
        }
    }
}

// MARK: - Community Alert Overlay (Scenario 2 broadcast)

struct CommunityAlertOverlay: View {
    let alert: ScenarioTwoAlert
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: Spacing.ms) {
                ZStack {
                    Circle()
                        .fill(Color.statusError)
                        .frame(width: 28, height: 28)

                    Text("M")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Text("A user has been permanently removed from MTRX.")
                    .font(.mtrxSubheadline)
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .fill(Color.statusError.opacity(0.9))
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 100)
            .mtrxFadeInFromBottom(isVisible: appeared)
        }
        .onAppear {
            withAnimation(Motion.springDefault) {
                appeared = true
            }
        }
    }
}
