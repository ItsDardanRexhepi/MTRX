// StreamingView.swift
// MTRX
//
// Token streaming — create, manage outgoing/incoming payment streams with real-time flow rates.

import SwiftUI

// MARK: - Streaming ViewModel

@MainActor
final class StreamingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var outgoingStreams: [PaymentStream] = []
    @Published var incomingStreams: [PaymentStream] = []
    @Published var selectedSegment: StreamSegment = .outgoing
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showCreateForm: Bool = false
    @Published var contentAppeared: Bool = false
    @Published var actionUnavailable: Bool = false

    // Create form
    @Published var recipient: String = ""
    @Published var tokenSymbol: String = "USDC"
    @Published var flowRateAmount: String = ""
    @Published var flowRateUnit: FlowRateUnit = .month
    @Published var durationMonths: String = ""
    @Published var isCreating: Bool = false

    // MARK: - Computed

    var canCreateStream: Bool {
        !recipient.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Double(flowRateAmount) ?? 0) > 0 &&
        (Double(durationMonths) ?? 0) > 0
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        try? await Task.sleep(nanoseconds: 800_000_000)

        outgoingStreams = PaymentStream.sampleOutgoing
        incomingStreams = PaymentStream.sampleIncoming
        isLoading = false

        withAnimation(Motion.springDefault) {
            contentAppeared = true
        }
    }

    func createStream() async {
        guard canCreateStream else { return }
        // Honest failure: no backend / on-chain path is wired to open a payment stream.
        isCreating = false
        actionUnavailable = true
    }

    func pauseStream(_ stream: PaymentStream) {
        updateStreamStatus(stream, to: .paused)
        MtrxHaptics.impact(.medium)
    }

    func resumeStream(_ stream: PaymentStream) {
        updateStreamStatus(stream, to: .active)
        MtrxHaptics.impact(.medium)
    }

    func cancelStream(_ stream: PaymentStream) {
        updateStreamStatus(stream, to: .cancelled)
        MtrxHaptics.warning()
    }

    func claimStream(_ stream: PaymentStream) {
        if let index = incomingStreams.firstIndex(where: { $0.id == stream.id }) {
            incomingStreams[index].claimedAmount = incomingStreams[index].streamedAmount
        }
        MtrxHaptics.success()
    }

    private func updateStreamStatus(_ stream: PaymentStream, to status: StreamStatus) {
        if let index = outgoingStreams.firstIndex(where: { $0.id == stream.id }) {
            outgoingStreams[index].status = status
        }
        if let index = incomingStreams.firstIndex(where: { $0.id == stream.id }) {
            incomingStreams[index].status = status
        }
    }

    private func resetForm() {
        recipient = ""
        flowRateAmount = ""
        durationMonths = ""
    }
}

// MARK: - Stream Segment

enum StreamSegment: String, CaseIterable {
    case outgoing = "Outgoing"
    case incoming = "Incoming"
}

// MARK: - Flow Rate Unit

enum FlowRateUnit: CaseIterable {
    case second, minute, hour, month

    var label: String {
        switch self {
        case .second: return "/ sec"
        case .minute: return "/ min"
        case .hour: return "/ hr"
        case .month: return "/ mo"
        }
    }

    var seconds: Double {
        switch self {
        case .second: return 1
        case .minute: return 60
        case .hour: return 3600
        case .month: return 2_592_000
        }
    }
}

// MARK: - Streaming View

struct StreamingView: View {
    @StateObject private var viewModel = StreamingViewModel()

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
                        case .outgoing:
                            outgoingView
                        case .incoming:
                            incomingView
                        }
                    }
                }
                .background(MtrxGradientBackground(style: .primary))

                // FAB
                Button {
                    viewModel.showCreateForm = true
                    MtrxHaptics.impact(.medium)
                } label: {
                    Image(systemName: Symbols.add)
                        .accessibilityLabel("Create payment stream")
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
            .navigationTitle("Streams")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $viewModel.showCreateForm) {
                createStreamSheet
            }
            .honestActionAlert($viewModel.actionUnavailable, message: "Creating a payment stream isn't available in this build yet. No stream was started.")
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        HStack(spacing: 0) {
            ForEach(StreamSegment.allCases, id: \.self) { segment in
                Button {
                    withAnimation(Motion.springSnappy) {
                        viewModel.selectedSegment = segment
                    }
                    MtrxHaptics.selection()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: segment == .outgoing ? Symbols.send : Symbols.receive)
                            .font(.system(size: 12, weight: .semibold))
                        Text(segment.rawValue)
                            .font(.mtrxCaptionBold)
                    }
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

    // MARK: - Outgoing View

    private var outgoingView: some View {
        Group {
            if viewModel.outgoingStreams.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.send,
                    title: "No Outgoing Streams",
                    message: "Create a payment stream to continuously send tokens to a recipient.",
                    actionLabel: "Create Stream"
                ) {
                    viewModel.showCreateForm = true
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(Array(viewModel.outgoingStreams.enumerated()), id: \.element.id) { index, stream in
                            outgoingStreamCard(stream)
                                .mtrxStaggeredAppearance(index: index, isVisible: viewModel.contentAppeared)
                        }
                        Spacer().frame(height: Spacing.xxxl)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.top, Spacing.sm)
                }
            }
        }
    }

    private func outgoingStreamCard(_ stream: PaymentStream) -> some View {
        MtrxCard(style: .standard, accentEdge: .leading) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    MtrxBadge(text: stream.status.label, style: stream.status.badgeStyle)
                    Spacer()
                    Text(stream.tokenSymbol)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(accent)
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Recipient")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(stream.counterparty)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Rate")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(String(format: "%.2f / mo", stream.flowRatePerSecond * 2_592_000))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                    }
                }

                // Progress bar
                VStack(spacing: Spacing.xs) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.surfaceOverlay)
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent)
                                .frame(width: geo.size.width * stream.progress, height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(String(format: "%.2f sent", stream.streamedAmount))
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(String(format: "%.2f total", stream.totalAmount))
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.labelTertiary)
                    }
                }

                MtrxDivider()

                HStack {
                    Text(stream.timeRemaining)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)

                    Spacer()

                    HStack(spacing: Spacing.sm) {
                        if stream.status == .active {
                            Button {
                                viewModel.pauseStream(stream)
                            } label: {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .accessibilityLabel("Pause stream")
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
                        }

                        if stream.status == .paused {
                            Button {
                                viewModel.resumeStream(stream)
                            } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .accessibilityLabel("Resume stream")
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .compact))
                        }

                        if stream.status != .cancelled && stream.status != .completed {
                            Button {
                                viewModel.cancelStream(stream)
                            } label: {
                                Image(systemName: Symbols.close)
                                    .font(.system(size: 12, weight: .bold))
                                    .accessibilityLabel("Cancel stream")
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .destructive, size: .compact))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Incoming View

    private var incomingView: some View {
        Group {
            if viewModel.incomingStreams.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.receive,
                    title: "No Incoming Streams",
                    message: "When someone streams tokens to you, they will appear here."
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(Array(viewModel.incomingStreams.enumerated()), id: \.element.id) { index, stream in
                            incomingStreamCard(stream)
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

    private func incomingStreamCard(_ stream: PaymentStream) -> some View {
        MtrxCard(style: .standard, accentEdge: .leading) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    MtrxBadge(text: stream.status.label, style: stream.status.badgeStyle)
                    Spacer()
                    Text(stream.tokenSymbol)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(accent)
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Sender")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(stream.counterparty)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Rate")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(String(format: "%.2f / mo", stream.flowRatePerSecond * 2_592_000))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelPrimary)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Total Received")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(String(format: "%.4f %@", stream.streamedAmount, stream.tokenSymbol))
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text("Claimable")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(String(format: "%.4f %@", stream.claimableBalance, stream.tokenSymbol))
                            .font(.mtrxMono)
                            .foregroundStyle(Color.statusSuccess)
                    }
                }

                if stream.claimableBalance > 0 {
                    Button {
                        viewModel.claimStream(stream)
                    } label: {
                        Label("Claim", systemImage: Symbols.receive)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
                }
            }
        }
    }

    // MARK: - Create Stream Sheet

    private var createStreamSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Create Stream", subtitle: "Set up a continuous token stream") {
                        viewModel.showCreateForm = false
                    }

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // Recipient
                        fieldLabel("Recipient Address", required: true)
                        MtrxTextField(
                            placeholder: "0x...",
                            text: $viewModel.recipient,
                            icon: "person.fill"
                        )

                        // Token
                        fieldLabel("Token")
                        Menu {
                            ForEach(["USDC", "DAI", "ETH", "WETH", "USDT"], id: \.self) { token in
                                Button(token) {
                                    viewModel.tokenSymbol = token
                                }
                            }
                        } label: {
                            HStack {
                                Text(viewModel.tokenSymbol)
                                    .font(.mtrxBody)
                                    .foregroundStyle(Color.labelPrimary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.labelTertiary)
                            }
                            .padding(.horizontal, Spacing.textFieldPadding)
                            .frame(height: Spacing.Size.textFieldHeight)
                            .background(Color.surfaceOverlay)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                        }

                        // Flow rate
                        fieldLabel("Flow Rate", required: true)
                        HStack(spacing: Spacing.sm) {
                            MtrxTextField(
                                placeholder: "100.00",
                                text: $viewModel.flowRateAmount,
                                keyboardType: .decimalPad
                            )

                            Menu {
                                ForEach(FlowRateUnit.allCases, id: \.self) { unit in
                                    Button(unit.label) {
                                        viewModel.flowRateUnit = unit
                                    }
                                }
                            } label: {
                                Text(viewModel.flowRateUnit.label)
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, Spacing.md)
                                    .frame(height: Spacing.Size.textFieldHeight)
                                    .background(Color.surfaceOverlay)
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                            }
                        }

                        // Duration
                        fieldLabel("Duration (months)", required: true)
                        MtrxTextField(
                            placeholder: "12",
                            text: $viewModel.durationMonths,
                            icon: Symbols.calendar,
                            keyboardType: .numberPad
                        )

                        // Summary
                        if let rate = Double(viewModel.flowRateAmount), rate > 0,
                           let months = Double(viewModel.durationMonths), months > 0 {
                            MtrxCard(style: .glass) {
                                VStack(spacing: Spacing.ms) {
                                    HStack {
                                        Text("Total Amount")
                                            .font(.mtrxCaption1)
                                            .foregroundStyle(Color.labelSecondary)
                                        Spacer()
                                        Text(String(format: "%.2f %@", rate * months, viewModel.tokenSymbol))
                                            .font(.mtrxMono)
                                            .foregroundStyle(Color.labelPrimary)
                                    }
                                    HStack {
                                        Text("Per Second")
                                            .font(.mtrxCaption1)
                                            .foregroundStyle(Color.labelSecondary)
                                        Spacer()
                                        Text(String(format: "%.8f %@", rate / viewModel.flowRateUnit.seconds, viewModel.tokenSymbol))
                                            .font(.mtrxMonoSmall)
                                            .foregroundStyle(Color.labelSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    Button {
                        MtrxHaptics.impact(.medium)
                        Task { await viewModel.createStream() }
                    } label: {
                        Label("Start Stream", systemImage: Symbols.send)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: viewModel.isCreating, fullWidth: true))
                    .disabled(!viewModel.canCreateStream || viewModel.isCreating)
                    .opacity(viewModel.canCreateStream ? 1 : 0.5)
                    .padding(.horizontal, Spacing.contentPadding)
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func fieldLabel(_ text: String, required: Bool = false) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(text)
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)
            if required {
                Text("*")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.statusError)
            }
        }
    }
}

// MARK: - Data Models

struct PaymentStream: Identifiable {
    let id = UUID()
    let counterparty: String
    let tokenSymbol: String
    let flowRatePerSecond: Double
    let totalAmount: Double
    var streamedAmount: Double
    var status: StreamStatus
    let startDate: Date
    let endDate: Date
    let direction: StreamDirection
    var claimedAmount: Double = 0

    var progress: Double {
        guard totalAmount > 0 else { return 0 }
        return min(streamedAmount / totalAmount, 1.0)
    }

    var claimableBalance: Double {
        max(streamedAmount - claimedAmount, 0)
    }

    var timeRemaining: String {
        let remaining = Calendar.current.dateComponents([.day, .hour], from: Date(), to: endDate)
        let days = remaining.day ?? 0
        let hours = remaining.hour ?? 0
        if days > 0 { return "\(days)d \(hours)h remaining" }
        if hours > 0 { return "\(hours)h remaining" }
        return "Completed"
    }

    static let sampleOutgoing: [PaymentStream] = [
        PaymentStream(counterparty: "0xabcd...ef01", tokenSymbol: "USDC", flowRatePerSecond: 0.0000385, totalAmount: 3000, streamedAmount: 1250, status: .active, startDate: Calendar.current.date(byAdding: .month, value: -5, to: Date())!, endDate: Calendar.current.date(byAdding: .month, value: 7, to: Date())!, direction: .outgoing),
        PaymentStream(counterparty: "0x5678...9abc", tokenSymbol: "DAI", flowRatePerSecond: 0.0000193, totalAmount: 1500, streamedAmount: 750, status: .paused, startDate: Calendar.current.date(byAdding: .month, value: -3, to: Date())!, endDate: Calendar.current.date(byAdding: .month, value: 9, to: Date())!, direction: .outgoing),
        PaymentStream(counterparty: "0x1234...5678", tokenSymbol: "USDC", flowRatePerSecond: 0.0000116, totalAmount: 900, streamedAmount: 900, status: .completed, startDate: Calendar.current.date(byAdding: .month, value: -12, to: Date())!, endDate: Calendar.current.date(byAdding: .month, value: -2, to: Date())!, direction: .outgoing),
    ]

    static let sampleIncoming: [PaymentStream] = [
        PaymentStream(counterparty: "0x9876...5432", tokenSymbol: "USDC", flowRatePerSecond: 0.0000578, totalAmount: 4500, streamedAmount: 2100, status: .active, startDate: Calendar.current.date(byAdding: .month, value: -4, to: Date())!, endDate: Calendar.current.date(byAdding: .month, value: 8, to: Date())!, direction: .incoming, claimedAmount: 1500),
        PaymentStream(counterparty: "0xfedc...ba98", tokenSymbol: "ETH", flowRatePerSecond: 0.00000019, totalAmount: 5.0, streamedAmount: 2.3, status: .active, startDate: Calendar.current.date(byAdding: .month, value: -6, to: Date())!, endDate: Calendar.current.date(byAdding: .month, value: 6, to: Date())!, direction: .incoming, claimedAmount: 1.0),
    ]
}

enum StreamStatus {
    case active, paused, cancelled, completed

    var label: String {
        switch self {
        case .active: return "Streaming"
        case .paused: return "Paused"
        case .cancelled: return "Cancelled"
        case .completed: return "Completed"
        }
    }

    var badgeStyle: MtrxBadge.BadgeStyle {
        switch self {
        case .active: return .success
        case .paused: return .warning
        case .cancelled: return .error
        case .completed: return .accent
        }
    }
}

enum StreamDirection {
    case incoming, outgoing
}

// MARK: - Preview

#Preview {
    StreamingView()
}
