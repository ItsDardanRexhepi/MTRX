// BridgeView.swift
// MTRX
//
// Cross-chain bridge — source/destination chain pickers, token/amount, fees, estimated time, status tracker.

import SwiftUI

// MARK: - Data Models

enum BridgeChain: String, CaseIterable, Identifiable {
    case ethereum = "Ethereum"
    case base = "Base"
    case optimism = "Optimism"
    case arbitrum = "Arbitrum"
    case polygon = "Polygon"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ethereum: return "diamond.fill"
        case .base: return "b.circle.fill"
        case .optimism: return "o.circle.fill"
        case .arbitrum: return "a.circle.fill"
        case .polygon: return "p.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ethereum: return .blue
        case .base: return Color(red: 0.0, green: 0.5, blue: 1.0)
        case .optimism: return .red
        case .arbitrum: return Color(red: 0.16, green: 0.47, blue: 0.88)
        case .polygon: return .purple
        }
    }

    var estimatedMinutes: Int {
        switch self {
        case .ethereum: return 15
        case .base: return 2
        case .optimism: return 2
        case .arbitrum: return 3
        case .polygon: return 5
        }
    }
}

enum BridgeStatus: String {
    case idle
    case sent = "Sent"
    case confirming = "Confirming"
    case arrived = "Arrived"
}

// MARK: - View Model

@MainActor
class BridgeViewModel: ObservableObject {
    @Published var sourceChain: BridgeChain = .ethereum
    @Published var destinationChain: BridgeChain = .base
    @Published var token: String = "ETH"
    @Published var amount: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isBridging: Bool = false
    @Published var bridgeStatus: BridgeStatus = .idle
    @Published var showSourcePicker: Bool = false
    @Published var showDestPicker: Bool = false
    /// A real route quote from BridgeService, fetched when a backend is configured.
    @Published var liveRoute: BridgeRoute?
    /// True while the fee/time shown are local illustrative estimates (no live route).
    @Published var isDemo: Bool = true

    let availableTokens = ["ETH", "USDC", "USDT", "WBTC", "DAI"]

    var estimatedTime: String {
        if let r = liveRoute { return "Arrives in ~\(r.estimatedTime)" }
        let minutes = max(sourceChain.estimatedMinutes, destinationChain.estimatedMinutes)
        if minutes == 1 {
            return "Arrives in ~1 minute"
        }
        return "Arrives in ~\(minutes) minutes"
    }

    var bridgeFeeUSD: String {
        if let r = liveRoute { return r.fee.formatted(.currency(code: "USD")) }
        return "$1.85"
    }

    /// Fetch a real bridge route whenever the inputs change and a backend is configured;
    /// otherwise clear it and fall back to the local illustrative estimate.
    func refreshQuote() async {
        guard PendingCredentials.isBackendConfigured, canBridge else {
            liveRoute = nil
            isDemo = true
            return
        }
        if let routes = try? await BridgeGatewayService.shared.getBridgeRoutes(
            fromChain: sourceChain.rawValue, toChain: destinationChain.rawValue,
            token: token, amount: amount), let best = routes.first {
            liveRoute = best
            isDemo = false
        } else {
            liveRoute = nil
            isDemo = true
        }
    }

    var canBridge: Bool {
        !amount.isEmpty &&
        (Double(amount) ?? 0) > 0 &&
        sourceChain != destinationChain
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(400))
            isLoading = false
        } catch {
            errorMessage = "Unable to load bridge data."
            isLoading = false
        }
    }

    func swapChains() {
        let temp = sourceChain
        sourceChain = destinationChain
        destinationChain = temp
    }

    func bridge() async {
        guard canBridge else { return }
        // Honest failure: no real bridge path is wired. Do NOT advance the status to
        // .confirming/.arrived or fire a success — that would imply funds moved across
        // chains. Nothing was bridged.
        isBridging = false
        bridgeStatus = .idle
        errorMessage = "Bridging isn't available in this build yet. Nothing was bridged."
    }

    func reset() {
        bridgeStatus = .idle
        amount = ""
        isBridging = false
    }
}

// MARK: - Bridge View

struct BridgeView: View {
    @StateObject private var viewModel = BridgeViewModel()

    // MARK: - Body

    var body: some View { _regulatedBody.mvpGated() }

    @ViewBuilder private var _regulatedBody: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.bridgeStatus == .idle {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    bridgeContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Bridge")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge(label: "Estimated fee") }
                }
            }
            .task { await viewModel.load() }
            .task(id: "\(viewModel.sourceChain.rawValue)|\(viewModel.destinationChain.rawValue)|\(viewModel.token)|\(viewModel.amount)") {
                await viewModel.refreshQuote()
            }
        }
    }

    // MARK: - Content

    private var bridgeContent: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if viewModel.bridgeStatus != .idle {
                    statusTracker
                } else {
                    bridgeForm
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
    }

    // MARK: - Bridge Form

    private var bridgeForm: some View {
        VStack(spacing: Spacing.lg) {
            chainSelectors
            tokenAmountSection
            feeEstimateSection
            submitButton
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Chain Selectors

    private var chainSelectors: some View {
        VStack(spacing: Spacing.sm) {
            // Source chain
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("From")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)

                chainPickerButton(
                    chain: viewModel.sourceChain,
                    showPicker: $viewModel.showSourcePicker
                )

                if viewModel.showSourcePicker {
                    chainPickerList(
                        excluding: viewModel.destinationChain,
                        selection: Binding(
                            get: { viewModel.sourceChain },
                            set: { viewModel.sourceChain = $0 }
                        ),
                        showPicker: $viewModel.showSourcePicker
                    )
                    .transition(.mtrxScale)
                }
            }

            // Swap button
            HStack {
                Spacer()
                Button {
                    MtrxHaptics.impact(.medium)
                    withAnimation(Motion.springBouncy) {
                        viewModel.swapChains()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.surfaceCard)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color.accentPrimary.opacity(0.3), lineWidth: 1)
                            )
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.accentPrimary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.vertical, -Spacing.xs)

            // Destination chain
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("To")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)

                chainPickerButton(
                    chain: viewModel.destinationChain,
                    showPicker: $viewModel.showDestPicker
                )

                if viewModel.showDestPicker {
                    chainPickerList(
                        excluding: viewModel.sourceChain,
                        selection: Binding(
                            get: { viewModel.destinationChain },
                            set: { viewModel.destinationChain = $0 }
                        ),
                        showPicker: $viewModel.showDestPicker
                    )
                    .transition(.mtrxScale)
                }
            }
        }
    }

    private func chainPickerButton(chain: BridgeChain, showPicker: Binding<Bool>) -> some View {
        Button {
            MtrxHaptics.selection()
            withAnimation(Motion.springSnappy) {
                showPicker.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Spacing.ms) {
                Image(systemName: chain.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(chain.color)
                Text(chain.rawValue)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.labelTertiary)
            }
            .padding(Spacing.md)
            .background(Color.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chainPickerList(excluding: BridgeChain, selection: Binding<BridgeChain>, showPicker: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            ForEach(BridgeChain.allCases) { chain in
                if chain != excluding {
                    Button {
                        MtrxHaptics.selection()
                        withAnimation(Motion.springSnappy) {
                            selection.wrappedValue = chain
                            showPicker.wrappedValue = false
                        }
                    } label: {
                        HStack(spacing: Spacing.ms) {
                            Image(systemName: chain.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(chain.color)
                            Text(chain.rawValue)
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelPrimary)
                            Spacer()
                            if chain == selection.wrappedValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.accentPrimary)
                            }
                        }
                        .padding(.vertical, Spacing.ms)
                        .padding(.horizontal, Spacing.md)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }

    // MARK: - Token & Amount

    private var tokenAmountSection: some View {
        VStack(spacing: Spacing.md) {
            // Token selector
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Token")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(viewModel.availableTokens, id: \.self) { token in
                            MtrxChip(
                                label: token,
                                isSelected: viewModel.token == token
                            ) {
                                MtrxHaptics.selection()
                                viewModel.token = token
                            }
                        }
                    }
                }
            }

            // Amount input
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Amount")
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.labelSecondary)
                MtrxTextField(
                    placeholder: "0.00 \(viewModel.token)",
                    text: $viewModel.amount,
                    keyboardType: .decimalPad
                )
            }
        }
    }

    // MARK: - Fee & Estimate

    private var feeEstimateSection: some View {
        MtrxCard(style: .standard) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    Text("Estimated Time")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text(viewModel.estimatedTime)
                        .font(.mtrxCallout)
                        .foregroundStyle(Color.labelPrimary)
                }
                MtrxDivider()
                HStack {
                    Text("Bridge Fee")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    Text(viewModel.bridgeFeeUSD)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                }
                MtrxDivider()
                HStack {
                    Text("Route")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Spacer()
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.bridge)
                            .font(.system(size: 11))
                        Text("\(viewModel.sourceChain.rawValue) \(Image(systemName: "arrow.right")) \(viewModel.destinationChain.rawValue)")
                            .font(.mtrxCaption1)
                    }
                    .foregroundStyle(Color.accentPrimary)
                }

                if viewModel.sourceChain == viewModel.destinationChain {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.alertWarning)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.statusWarning)
                        Text("Source and destination chains must be different.")
                            .font(.mtrxCaption2)
                            .foregroundStyle(Color.statusWarning)
                    }
                }
            }
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button {
            Task { await viewModel.bridge() }
        } label: {
            Text(viewModel.isBridging ? "Bridging..." : "Bridge \(viewModel.token)")
        }
        .buttonStyle(MtrxButtonStyle(
            variant: .primary,
            size: .large,
            isLoading: viewModel.isBridging,
            fullWidth: true
        ))
        .disabled(!viewModel.canBridge || viewModel.isBridging)
        .opacity(viewModel.canBridge ? 1 : 0.5)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Status Tracker

    private var statusTracker: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer(minLength: Spacing.xl)

            // Status steps
            HStack(spacing: 0) {
                statusStep(label: "Sent", status: .sent)
                statusLine(isActive: viewModel.bridgeStatus == .confirming || viewModel.bridgeStatus == .arrived)
                statusStep(label: "Confirming", status: .confirming)
                statusLine(isActive: viewModel.bridgeStatus == .arrived)
                statusStep(label: "Arrived", status: .arrived)
            }
            .padding(.horizontal, Spacing.xl)

            // Details
            MtrxCard(style: .glass) {
                VStack(spacing: Spacing.ms) {
                    HStack {
                        Text("Amount")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text("\(viewModel.amount) \(viewModel.token)")
                            .font(.mtrxMono)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    MtrxDivider()
                    HStack {
                        Text("From")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(viewModel.sourceChain.rawValue)
                            .font(.mtrxCallout)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    MtrxDivider()
                    HStack {
                        Text("To")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        Text(viewModel.destinationChain.rawValue)
                            .font(.mtrxCallout)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    MtrxDivider()
                    HStack {
                        Text("Status")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)
                        Spacer()
                        MtrxBadge(
                            text: viewModel.bridgeStatus.rawValue,
                            style: viewModel.bridgeStatus == .arrived ? .success : .accent
                        )
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)

            if viewModel.bridgeStatus == .arrived {
                Button {
                    MtrxHaptics.success()
                    withAnimation(Motion.springDefault) {
                        viewModel.reset()
                    }
                } label: {
                    Text("Done")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
                .padding(.horizontal, Spacing.contentPadding)
            }

            Spacer()
        }
        .mtrxFadeInFromBottom(isVisible: true)
    }

    private func statusStep(label: String, status: BridgeStatus) -> some View {
        let isReached = statusOrder(viewModel.bridgeStatus) >= statusOrder(status)
        let isCurrent = viewModel.bridgeStatus == status

        return VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(isReached ? Color.accentPrimary : Color.surfaceOverlay)
                    .frame(width: 32, height: 32)

                if isReached {
                    if status == .arrived && viewModel.bridgeStatus == .arrived {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .mtrxPulse(isActive: isCurrent && status != .arrived)

            Text(label)
                .font(.mtrxCaptionBold)
                .foregroundStyle(isReached ? Color.labelPrimary : Color.labelTertiary)
        }
    }

    private func statusLine(isActive: Bool) -> some View {
        Rectangle()
            .fill(isActive ? Color.accentPrimary : Color.surfaceOverlay)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)
    }

    private func statusOrder(_ status: BridgeStatus) -> Int {
        switch status {
        case .idle: return 0
        case .sent: return 1
        case .confirming: return 2
        case .arrived: return 3
        }
    }
}

// MARK: - Preview

#Preview {
    BridgeView()
        .preferredColorScheme(.dark)
}
