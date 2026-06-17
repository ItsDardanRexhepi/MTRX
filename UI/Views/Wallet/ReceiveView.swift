// ReceiveView.swift
// MTRX
//
// Receive flow — QR code display, address copy, network selector, share.

import SwiftUI

// MARK: - Receive View

struct ReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNetwork: ReceiveNetwork = .base
    @State private var showCopied: Bool = false
    @State private var isVisible: Bool = false

    private let walletAddress = DemoDataProvider.walletAddress
    private let ensName = DemoDataProvider.ensName

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                MtrxSheetHeader(title: "Receive", subtitle: "Deposit tokens to your wallet") {
                    dismiss()
                }

                Spacer()

                qrCodeSection
                addressSection
                networkSelector
                warningText

                Spacer()

                shareButton
            }
            .padding(.bottom, Spacing.xl)
            .background(MtrxGradientBackground(style: .primary))
            .onAppear {
                withAnimation(Motion.springDefault) {
                    isVisible = true
                }
            }
            .overlay(copiedToast)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - QR Code Section

    private var qrCodeSection: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 200, height: 200)

                // QR code placeholder — grid pattern
                VStack(spacing: 3) {
                    ForEach(0..<9, id: \.self) { row in
                        HStack(spacing: 3) {
                            ForEach(0..<9, id: \.self) { col in
                                let filled = qrModuleFilled(row: row, col: col)
                                Rectangle()
                                    .fill(filled ? Color.black : Color.white)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))

                // Center logo overlay
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 36, height: 36)
                    Text("M")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.black)
                }
            }
            .mtrxGlow(color: .accentPrimary, radius: 12)
            .mtrxScaleIn(isVisible: isVisible)
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    /// Deterministic fill pattern for the QR placeholder
    private func qrModuleFilled(row: Int, col: Int) -> Bool {
        // Finder patterns in corners
        if (row < 3 && col < 3) || (row < 3 && col > 5) || (row > 5 && col < 3) {
            let r = row < 3 ? row : row - 6
            let c = col < 3 ? col : col - 6
            if r == 1 && c == 1 { return false }
            return true
        }
        // Pseudo-random data fill
        return (row * 7 + col * 13 + row * col) % 3 != 0
    }

    // MARK: - Address Section

    private var addressSection: some View {
        VStack(spacing: Spacing.sm) {
            Text(ensName)
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)

            Text("Your \(selectedNetwork.name) Address")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)

            Button {
                MtrxHaptics.success()
                UIPasteboard.general.string = walletAddress
                withAnimation(Motion.springSnappy) {
                    showCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(Motion.springSnappy) {
                        showCopied = false
                    }
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text(walletAddress)
                        .font(.mtrxMonoSmall)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.middle)

                    Image(systemName: Symbols.copy)
                        .accessibilityLabel("Copy address")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentPrimary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.ms)
                .background(Color.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                .mtrxAccentBorder(cornerRadius: Spacing.CornerRadius.sm)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.contentPadding)
        .mtrxFadeInFromBottom(isVisible: isVisible, delay: 0.1)
    }

    // MARK: - Network Selector

    private var networkSelector: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Network")
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.labelSecondary)
                .padding(.horizontal, Spacing.contentPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(ReceiveNetwork.allCases, id: \.self) { network in
                        MtrxChip(
                            label: network.name,
                            icon: network.icon,
                            isSelected: selectedNetwork == network
                        ) {
                            MtrxHaptics.selection()
                            withAnimation(Motion.springSnappy) {
                                selectedNetwork = network
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
        .mtrxFadeInFromBottom(isVisible: isVisible, delay: 0.15)
    }

    // MARK: - Warning

    private var warningText: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 14))
                .foregroundStyle(Color.statusWarning)

            Text("Only send supported tokens on \(selectedNetwork.name) to this address")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
        }
        .padding(.horizontal, Spacing.lg)
        .multilineTextAlignment(.center)
        .mtrxFadeInFromBottom(isVisible: isVisible, delay: 0.2)
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Button {
            MtrxHaptics.impact(.medium)
            shareAddress()
        } label: {
            Label("Share Address", systemImage: Symbols.share)
        }
        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
        .padding(.horizontal, Spacing.contentPadding)
        .mtrxFadeInFromBottom(isVisible: isVisible, delay: 0.25)
    }

    // MARK: - Copied Toast

    @ViewBuilder
    private var copiedToast: some View {
        if showCopied {
            VStack {
                MtrxToast(message: "Address copied", icon: Symbols.complete, style: .success)
                    .transition(.mtrxSlideUp)
                Spacer()
            }
            .padding(.top, Spacing.lg)
        }
    }

    // MARK: - Share

    private func shareAddress() {
        let activityVC = UIActivityViewController(
            activityItems: [walletAddress],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Receive Network

enum ReceiveNetwork: String, CaseIterable {
    case base, ethereum, arbitrum, optimism, polygon

    var name: String {
        switch self {
        case .base: return "Base"
        case .ethereum: return "Ethereum"
        case .arbitrum: return "Arbitrum"
        case .optimism: return "Optimism"
        case .polygon: return "Polygon"
        }
    }

    var icon: String {
        switch self {
        case .base: return "b.circle.fill"
        case .ethereum: return "diamond.fill"
        case .arbitrum: return "a.circle.fill"
        case .optimism: return "o.circle.fill"
        case .polygon: return "p.circle.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    ReceiveView()
        .preferredColorScheme(.dark)
}
