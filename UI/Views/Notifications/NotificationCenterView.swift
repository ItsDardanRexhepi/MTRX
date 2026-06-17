// NotificationCenterView.swift
// MTRX - Notification center: filtered list with swipe-to-delete, mark-all-read
// Copyright 2026 OPN MATRX. All rights reserved.

import SwiftUI

// MARK: - Notification Model

struct MtrxNotification: Identifiable {
    let id = UUID()
    let type: NotificationType
    let title: String
    let message: String
    let timestamp: Date
    var isRead: Bool

    enum NotificationType: String, CaseIterable {
        case info, warning, success, error, social, governance, defi

        var icon: String {
            switch self {
            case .info: return Symbols.alertInfo
            case .warning: return Symbols.alertWarning
            case .success: return Symbols.alertSuccess
            case .error: return Symbols.alertCritical
            case .social: return Symbols.comment
            case .governance: return Symbols.vote
            case .defi: return Symbols.chartLine
            }
        }

        var color: Color {
            switch self {
            case .info: return .statusInfo
            case .warning: return .statusWarning
            case .success: return .statusSuccess
            case .error: return .statusError
            case .social: return .accentSecondary
            case .governance: return .trinityPrimary
            case .defi: return .accentTertiary
            }
        }

        var filterCategory: NotificationFilter {
            switch self {
            case .info, .warning, .error: return .alerts
            case .success, .defi: return .activity
            case .social, .governance: return .social
            }
        }
    }

    static let sampleData: [MtrxNotification] = [
        MtrxNotification(
            type: .success,
            title: "Contract Deployed",
            message: "Your Escrow Agreement contract has been successfully deployed to Base mainnet.",
            timestamp: Date().addingTimeInterval(-600),
            isRead: false
        ),
        MtrxNotification(
            type: .success,
            title: "Payment Received",
            message: "You received 0.5 ETH from 0x1a2b...3c4d. Transaction confirmed.",
            timestamp: Date().addingTimeInterval(-1800),
            isRead: false
        ),
        MtrxNotification(
            type: .warning,
            title: "Price Alert Triggered",
            message: "ETH has dropped below your $3,200 alert threshold. Current price: $3,187.42.",
            timestamp: Date().addingTimeInterval(-3600),
            isRead: false
        ),
        MtrxNotification(
            type: .governance,
            title: "Governance Vote Open",
            message: "Proposal #47: Treasury Diversification is now open for voting. 3 days remaining.",
            timestamp: Date().addingTimeInterval(-7200),
            isRead: true
        ),
        MtrxNotification(
            type: .info,
            title: "Dispute Update",
            message: "Arbitrator has requested additional evidence for dispute case #1042. Please respond within 48 hours.",
            timestamp: Date().addingTimeInterval(-14400),
            isRead: true
        ),
        MtrxNotification(
            type: .error,
            title: "Liquidation Warning",
            message: "Your Aave V3 lending position health factor is 1.12. Consider adding collateral to avoid liquidation.",
            timestamp: Date().addingTimeInterval(-28800),
            isRead: false
        ),
        MtrxNotification(
            type: .defi,
            title: "NFT Sale Completed",
            message: "Genesis Pass #0042 sold for 1.2 ETH on the marketplace. Funds have been credited to your wallet.",
            timestamp: Date().addingTimeInterval(-43200),
            isRead: true
        ),
        MtrxNotification(
            type: .social,
            title: "Social Mention",
            message: "@vitalik.eth mentioned you in a post: \"Great analysis on the L2 scaling proposal by @you\"",
            timestamp: Date().addingTimeInterval(-86400),
            isRead: true
        ),
        MtrxNotification(
            type: .info,
            title: "Staking Reward",
            message: "You earned 125 MTRX from your 90-day staking position. Rewards auto-compounded.",
            timestamp: Date().addingTimeInterval(-129600),
            isRead: true
        ),
        MtrxNotification(
            type: .warning,
            title: "Approval Expiring",
            message: "Your USDC approval for Uniswap V3 will expire in 24 hours. Renew to continue trading.",
            timestamp: Date().addingTimeInterval(-172800),
            isRead: true
        ),
    ]
}

// MARK: - Filter

enum NotificationFilter: String, CaseIterable {
    case all = "All"
    case alerts = "Alerts"
    case activity = "Activity"
    case social = "Social"
}

// MARK: - View Model

@MainActor
final class NotificationCenterViewModel: ObservableObject {
    @Published var notifications: [MtrxNotification] = MtrxNotification.sampleData
    @Published var selectedFilter: NotificationFilter = .all

    var filteredNotifications: [MtrxNotification] {
        switch selectedFilter {
        case .all:
            return notifications
        case .alerts:
            return notifications.filter { $0.type.filterCategory == .alerts }
        case .activity:
            return notifications.filter { $0.type.filterCategory == .activity }
        case .social:
            return notifications.filter { $0.type.filterCategory == .social }
        }
    }

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var hasNotifications: Bool {
        !filteredNotifications.isEmpty
    }

    func markAllRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        MtrxHaptics.success()
    }

    func markRead(_ notification: MtrxNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
        }
    }

    func delete(_ notification: MtrxNotification) {
        notifications.removeAll { $0.id == notification.id }
        MtrxHaptics.impact(.light)
    }

    func deleteAtOffsets(_ offsets: IndexSet) {
        let filtered = filteredNotifications
        let idsToRemove = offsets.map { filtered[$0].id }
        notifications.removeAll { idsToRemove.contains($0.id) }
        MtrxHaptics.impact(.light)
    }
}

// MARK: - Notification Center View

struct NotificationCenterView: View {
    @StateObject private var viewModel = NotificationCenterViewModel()
    @State private var appeared = false

    var body: some View {
        ZStack {
            MtrxGradientBackground(style: .subtle)

            VStack(spacing: 0) {
                filterBar
                    .padding(.horizontal, Spacing.contentPadding)
                    .padding(.vertical, Spacing.sm)

                if viewModel.hasNotifications {
                    notificationList
                } else {
                    MtrxEmptyState(
                        icon: Symbols.notification,
                        title: "No Notifications",
                        message: emptyStateMessage
                    )
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.unreadCount > 0 {
                    Button("Mark All Read") {
                        viewModel.markAllRead()
                    }
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(Color.accentPrimary)
                }
            }
        }
        .onAppear {
            withAnimation(Motion.springDefault) {
                appeared = true
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(NotificationFilter.allCases, id: \.self) { filter in
                    MtrxChip(
                        label: filter.rawValue,
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        withAnimation(Motion.springSnappy) {
                            viewModel.selectedFilter = filter
                        }
                        MtrxHaptics.selection()
                    }
                }
            }
        }
    }

    // MARK: - Notification List

    private var notificationList: some View {
        List {
            ForEach(Array(viewModel.filteredNotifications.enumerated()), id: \.element.id) { index, notification in
                notificationRow(notification)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: Spacing.xs,
                        leading: Spacing.contentPadding,
                        bottom: Spacing.xs,
                        trailing: Spacing.contentPadding
                    ))
                    .mtrxStaggeredAppearance(index: index, isVisible: appeared)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.delete(notification)
                        } label: {
                            Label("Delete", systemImage: Symbols.delete)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !notification.isRead {
                            Button {
                                viewModel.markRead(notification)
                            } label: {
                                Label("Read", systemImage: "envelope.open")
                            }
                            .tint(Color.accentPrimary)
                        }
                    }
                    .onTapGesture {
                        viewModel.markRead(notification)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Notification Row

    private func notificationRow(_ notification: MtrxNotification) -> some View {
        HStack(alignment: .top, spacing: Spacing.ms) {
            // Type icon
            ZStack {
                Circle()
                    .fill(notification.type.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: notification.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(notification.type.color)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .top) {
                    Text(notification.title)
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)

                    Spacer()

                    // Unread indicator
                    if !notification.isRead {
                        Circle()
                            .fill(Color.accentPrimary)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(notification.message)
                    .font(.mtrxSubheadline)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(2)

                Text(relativeTimestamp(notification.timestamp))
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(Spacing.ms)
        .background(notification.isRead ? Color.surfaceCard.opacity(0.6) : Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var emptyStateMessage: String {
        switch viewModel.selectedFilter {
        case .all: return "You're all caught up. New notifications will appear here."
        case .alerts: return "No alerts right now. We'll notify you of important events."
        case .activity: return "No recent activity. Transactions and DeFi events will show here."
        case .social: return "No social updates. Mentions and governance activity will appear here."
        }
    }
}

// MARK: - Preview

#Preview("Notification Center") {
    NavigationStack {
        NotificationCenterView()
    }
}

#Preview("Empty State") {
    NavigationStack {
        NotificationCenterView()
    }
}
