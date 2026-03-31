import SwiftUI

/// The primary conversation interface that handles Trinity, Morpheus, and Neo interactions.
/// Public users see Trinity by default. Morpheus appears at pivotal moments.
/// Neo is never visible to public users.
struct AgentConversationView: View {
    @StateObject private var viewModel = AgentConversationViewModel()
    @ObservedObject private var accessControl = AgentAccessControl.shared
    @ObservedObject private var morpheus = MorpheusInterventions.shared
    @FocusState private var isInputFocused: Bool

    let userID: String

    var body: some View {
        ZStack {
            // Background
            Color.mtrxBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Agent header
                agentHeader

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // First boot message (Trinity only, once per user)
                            if viewModel.showFirstBoot {
                                firstBootMessage
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isTyping {
                                TypingIndicator(agent: viewModel.activeAgent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: viewModel.messages.count) {
                        if let last = viewModel.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
                inputBar
            }

            // Morpheus overlay
            if morpheus.isPresenting, let intervention = morpheus.activeIntervention {
                MorpheusOverlay(intervention: intervention)
            }

            // Scenario 2 ban overlay
            if let ban = accessControl.banEvent {
                BanOverlay(event: ban)
            }

            // Scenario 2 community alert
            if let alert = accessControl.scenarioTwoAlert {
                CommunityAlertOverlay(alert: alert)
            }
        }
        .onAppear {
            viewModel.setup(userID: userID)
        }
    }

    // MARK: - Agent Header

    private var agentHeader: some View {
        HStack(spacing: 12) {
            // Agent avatar
            Circle()
                .fill(agentColor)
                .frame(width: 36, height: 36)
                .overlay(
                    Text(agentInitial)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(agentName)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(agentStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Temporal context indicator
            Text(TemporalContext.shared.currentData().isMarketOpen ? "Markets Open" : "Markets Closed")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(TemporalContext.shared.currentData().isMarketOpen
                              ? Color.green.opacity(0.2)
                              : Color.gray.opacity(0.2))
                )
                .foregroundColor(TemporalContext.shared.currentData().isMarketOpen ? .green : .gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var agentColor: Color {
        switch viewModel.activeAgent {
        case .trinity: return .blue
        case .morpheus: return .red
        case .neo: return .green
        }
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

    // MARK: - First Boot Message

    private var firstBootMessage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hi, my name is Trinity")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Text("Welcome to the world of MTRX, I'll be by your side the entire time if you need me")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.blue.opacity(0.08))
        )
        .padding(.top, 40)
        .padding(.bottom, 20)
        .transition(.opacity)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemGray6))
                )

            Button {
                viewModel.sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(viewModel.inputText.isEmpty ? .gray : .blue)
            }
            .disabled(viewModel.inputText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role != .user {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(agentColor)
                            .frame(width: 16, height: 16)
                        Text(message.agentName ?? "Trinity")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(agentColor)
                    }
                }

                Text(message.text)
                    .font(.body)
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(message.role == .user
                                  ? Color.blue
                                  : Color(.systemGray6))
                    )
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }

    private var agentColor: Color {
        switch message.agentName {
        case "Morpheus": return .red
        case "Neo": return .green
        default: return .blue
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    let agent: AgentAccessControl.ActiveAgent
    @State private var dotIndex = 0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.gray.opacity(dotIndex == i ? 1.0 : 0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemGray6))
            )

            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotIndex = (dotIndex + 1) % 3
            }
        }
    }
}

// MARK: - Morpheus Overlay

struct MorpheusOverlay: View {
    let intervention: MorpheusIntervention
    @ObservedObject private var morpheus = MorpheusInterventions.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Morpheus indicator
                Circle()
                    .fill(Color.red)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text("M")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    )

                Text("Morpheus")
                    .font(.title3.bold())
                    .foregroundColor(.white)

                Text(intervention.message)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if intervention.requiresConfirmation {
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            morpheus.dismiss()
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)

                        Button("I understand. Proceed.") {
                            _ = morpheus.confirmAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                } else if !intervention.autoDismiss {
                    Button("Continue") {
                        morpheus.dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground).opacity(0.15))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            )
            .padding(24)
        }
        .transition(.opacity)
    }
}

// MARK: - Ban Overlay (Scenario 2)

struct BanOverlay: View {
    let event: BanEvent
    @State private var remainingSeconds: Int = 10

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "xmark.shield.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.red)

                Text("Access Permanently Revoked")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("This message will disappear in \(remainingSeconds) seconds.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
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

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 24, height: 24)
                    .overlay(Text("M").font(.caption.bold()).foregroundColor(.white))

                Text("A user has been permanently removed from MTRX.")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.9))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Extensions

extension Color {
    static let mtrxBackground = Color(UIColor.systemBackground)
}
