// AlertsView.swift
// MTRX
//
// Price alerts — active alerts list, create alert sheet with token/condition/price inputs, preview text.

import SwiftUI

// MARK: - Data Models

struct AlertItem: Identifiable {
    let id = UUID()
    let token: String
    let condition: String
    let targetPrice: String
    let createdAt: String
    let triggered: Bool
}

// MARK: - View Model

@MainActor
class AlertsViewModel: ObservableObject {
    @Published var alerts: [AlertItem] = []
    @Published var newToken: String = ""
    @Published var newCondition: String = "above"
    @Published var newPrice: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showCreateAlert: Bool = false
    @Published var isDemo: Bool = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM dd, yyyy"; return f
    }()

    let conditions = ["above", "below"]

    var previewText: String {
        let tokenName = newToken.isEmpty ? "[token]" : newToken.uppercased()
        let priceValue = newPrice.isEmpty ? "[price]" : "$\(newPrice)"
        return "Notify me when \(tokenName) goes \(newCondition) \(priceValue)"
    }

    var canCreateAlert: Bool {
        !newToken.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newPrice.trimmingCharacters(in: .whitespaces).isEmpty &&
        Double(newPrice) != nil
    }

    var activeAlerts: [AlertItem] {
        alerts.filter { !$0.triggered }
    }

    var triggeredAlerts: [AlertItem] {
        alerts.filter { $0.triggered }
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // Live from AlertsService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let live = try await AlertsService.shared.getAlerts(address: address)
                alerts = live.map { a in
                    AlertItem(
                        token: a.token,
                        condition: a.condition.rawValue,
                        targetPrice: String(format: "$%.2f", a.targetPrice),
                        createdAt: Self.dateFormatter.string(from: a.createdAt),
                        triggered: a.triggeredAt != nil
                    )
                }
                isDemo = false
                isLoading = false
                return
            } catch {
                errorMessage = "Live alerts unavailable — showing demo."
            }
        }

        alerts = AlertsViewModel.sampleAlerts
        isDemo = true
        isLoading = false
    }

    func createAlert() async {
        guard canCreateAlert else { return }

        let alert = AlertItem(
            token: newToken.uppercased(),
            condition: newCondition,
            targetPrice: "$\(newPrice)",
            createdAt: "Just now",
            triggered: false
        )

        alerts.insert(alert, at: 0)
        newToken = ""
        newCondition = "above"
        newPrice = ""
        showCreateAlert = false
    }

    func deleteAlert(_ alert: AlertItem) {
        alerts.removeAll { $0.id == alert.id }
    }

    static let sampleAlerts: [AlertItem] = [
        AlertItem(token: "ETH", condition: "above", targetPrice: "$4,000.00", createdAt: "Apr 12, 2026", triggered: false),
        AlertItem(token: "BTC", condition: "below", targetPrice: "$60,000.00", createdAt: "Apr 10, 2026", triggered: false),
        AlertItem(token: "SOL", condition: "above", targetPrice: "$200.00", createdAt: "Apr 8, 2026", triggered: false),
        AlertItem(token: "LINK", condition: "above", targetPrice: "$15.00", createdAt: "Apr 5, 2026", triggered: true),
        AlertItem(token: "ETH", condition: "below", targetPrice: "$3,000.00", createdAt: "Apr 1, 2026", triggered: true)
    ]
}

// MARK: - Alerts View

struct AlertsView: View {
    @StateObject private var viewModel = AlertsViewModel()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.alerts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.alerts.isEmpty {
                    errorState(message: error)
                } else {
                    alertsContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showCreateAlert = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                    }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $viewModel.showCreateAlert) {
                createAlertSheet
            }
        }
    }

    // MARK: - Content

    private var alertsContent: some View {
        ScrollView {
            VStack(spacing: Spacing.sectionGap) {
                if viewModel.alerts.isEmpty {
                    emptyState
                } else {
                    if !viewModel.activeAlerts.isEmpty {
                        activeAlertsSection
                    }
                    if !viewModel.triggeredAlerts.isEmpty {
                        triggeredAlertsSection
                    }
                }
            }
            .padding(.vertical, Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: - Active Alerts

    private var activeAlertsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Active Alerts")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.activeAlerts) { alert in
                alertRow(alert, isTriggered: false)
            }
        }
    }

    // MARK: - Triggered Alerts

    private var triggeredAlertsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Triggered")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelSecondary)
                .padding(.horizontal, Spacing.contentPadding)

            ForEach(viewModel.triggeredAlerts) { alert in
                alertRow(alert, isTriggered: true)
            }
        }
    }

    private func alertRow(_ alert: AlertItem, isTriggered: Bool) -> some View {
        MtrxCard(style: isTriggered ? .outlined : .standard) {
            HStack(spacing: Spacing.ms) {
                ZStack {
                    Circle()
                        .fill(isTriggered ? Color.statusSuccess.opacity(0.12) : Color(red: 0.0, green: 0.675, blue: 0.694).opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: isTriggered ? "bell.badge.fill" : (alert.condition == "above" ? "arrow.up.circle.fill" : "arrow.down.circle.fill"))
                        .font(.system(size: 18))
                        .foregroundStyle(isTriggered ? Color.statusSuccess : Color(red: 0.0, green: 0.675, blue: 0.694))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(alert.token) \(alert.condition) \(alert.targetPrice)")
                        .font(.mtrxBodyBold)
                        .foregroundStyle(isTriggered ? Color.labelSecondary : Color.labelPrimary)
                    Text(alert.createdAt)
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }

                Spacer()

                if !isTriggered {
                    Button {
                        viewModel.deleteAlert(alert)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.statusError.opacity(0.7))
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.statusSuccess)
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Create Alert Sheet

    private var createAlertSheet: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Token Input
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Token")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        HStack {
                            TextField("ETH, BTC, SOL...", text: $viewModel.newToken)
                                .font(.mtrxBody)
                                .textInputAutocapitalization(.characters)
                        }
                        .padding(Spacing.ms)
                        .background(Color.surfaceOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    // Condition Picker
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Condition")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        Picker("Condition", selection: $viewModel.newCondition) {
                            ForEach(viewModel.conditions, id: \.self) { condition in
                                Text(condition.capitalized).tag(condition)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Price Input
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Target Price")
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(Color.labelSecondary)

                        HStack {
                            Text("$")
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelTertiary)
                            TextField("0.00", text: $viewModel.newPrice)
                                .font(.mtrxMono)
                                .keyboardType(.decimalPad)
                        }
                        .padding(Spacing.ms)
                        .background(Color.surfaceOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                // Preview
                MtrxCard(style: .glass) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(red: 0.0, green: 0.675, blue: 0.694))
                        Text(viewModel.previewText)
                            .font(.mtrxBody)
                            .foregroundStyle(Color.labelPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.contentPadding)

                Spacer()

                Button {
                    Task { await viewModel.createAlert() }
                } label: {
                    Text("Create Alert")
                        .font(.mtrxBodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.ms)
                        .background(viewModel.canCreateAlert ? Color(red: 0.0, green: 0.675, blue: 0.694) : Color.labelTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .disabled(!viewModel.canCreateAlert)
                .padding(.horizontal, Spacing.contentPadding)
                .padding(.bottom, Spacing.lg)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("New Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        viewModel.showCreateAlert = false
                    }
                    .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.labelTertiary)
            Text("No alerts set")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
            Text("Create price alerts to get notified when tokens hit your target price.")
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button {
                viewModel.showCreateAlert = true
            } label: {
                Text("Create Alert")
                    .font(.mtrxBodyBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.ms)
                    .background(Color(red: 0.0, green: 0.675, blue: 0.694))
                    .clipShape(Capsule())
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error State

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.statusWarning)
            Text(message)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.0, green: 0.675, blue: 0.694))
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    AlertsView()
        .preferredColorScheme(.dark)
}
