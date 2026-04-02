// FundraiserView.swift
// MTRX
//
// Component 22 — Active fundraisers, progress bars, and contribution interface.

import SwiftUI

// MARK: - Fundraiser ViewModel

@MainActor
final class FundraiserViewModel: ObservableObject {
    @Published var fundraisers: [FundraiserDetail] = []
    @Published var selectedStatus: FundraiserStatus = .active
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var totalRaised: String = "$0"
    @Published var activeCount: Int = 0
    @Published var totalBackers: Int = 0

    private let api = MTRXAPIClient.shared

    // MARK: - Filtered

    var filteredFundraisers: [FundraiserDetail] {
        var result = fundraisers
        if selectedStatus != .all {
            result = result.filter { $0.status == selectedStatus }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    // MARK: - Load

    func loadFundraisers() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let raw: [String: AnyCodableValue] = try await api.listCampaigns()
            let items = parseCampaigns(raw)
            fundraisers = items

            // Compute stats
            activeCount = items.filter { $0.status == .active }.count
            totalBackers = items.reduce(0) { $0 + $1.backersCount }
            let totalAmount = items.reduce(0.0) { acc, item in
                let numStr = item.raised.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
                return acc + (Double(numStr) ?? 0)
            }
            if totalAmount >= 1_000_000 {
                totalRaised = "$\(String(format: "%.1f", totalAmount / 1_000_000))M"
            } else if totalAmount >= 1_000 {
                totalRaised = "$\(String(format: "%.1f", totalAmount / 1_000))K"
            } else {
                totalRaised = "$\(String(format: "%.0f", totalAmount))"
            }

            if fundraisers.isEmpty {
                fundraisers = FundraiserDetail.sampleData
                totalRaised = "$2.4M"
                activeCount = 23
                totalBackers = 1_200
            }
        } catch {
            if fundraisers.isEmpty {
                fundraisers = FundraiserDetail.sampleData
                totalRaised = "$2.4M"
                activeCount = 23
                totalBackers = 1_200
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Contribute

    func contribute(campaignId: String, amount: Double) async throws {
        let request = ContributeRequest(campaignId: campaignId, amount: amount)
        _ = try await api.contributeToCampaign(request)
        // Reload to reflect updated progress
        await loadFundraisers()
    }

    // MARK: - Parser

    private func parseCampaigns(_ raw: [String: AnyCodableValue]) -> [FundraiserDetail] {
        guard case .array(let items) = raw["data"] ?? raw["campaigns"] ?? .null else {
            return []
        }
        return items.compactMap { item -> FundraiserDetail? in
            guard case .dictionary(let dict) = item else { return nil }
            let title = dict["title"]?.stringValue ?? "Campaign"
            let organizer = dict["organizer"]?.stringValue ?? dict["creator"]?.stringValue ?? "Anonymous"
            let desc = dict["description"]?.stringValue ?? ""
            let goalAmount = dict["goal_amount"]?.doubleValue ?? 100_000
            let raisedAmount = dict["raised_amount"]?.doubleValue ?? dict["current_amount"]?.doubleValue ?? 0
            let progress = goalAmount > 0 ? min(raisedAmount / goalAmount, 1.0) : 0
            let backers = dict["backers_count"]?.intValue ?? dict["contributors"]?.intValue ?? 0
            let daysLeft = dict["days_remaining"]?.intValue ?? dict["duration_days"]?.intValue ?? 30
            let verified = dict["is_verified"]?.boolValue ?? false
            let statusStr = dict["status"]?.stringValue ?? "active"

            let status: FundraiserStatus = {
                switch statusStr.lowercased() {
                case "funded": return .funded
                case "closed": return .closed
                default: return .active
                }
            }()

            let tags = dict["tags"]?.stringValue?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []

            // Parse milestones
            var milestones: [FundraiserMilestone] = []
            if case .array(let ms) = dict["milestones"] {
                milestones = ms.compactMap { m -> FundraiserMilestone? in
                    guard case .dictionary(let md) = m else { return nil }
                    let msTitle = md["title"]?.stringValue ?? "Milestone"
                    let msAmount = md["amount"]?.doubleValue ?? 0
                    let isComplete = md["is_complete"]?.boolValue ?? md["completed"]?.boolValue ?? false
                    return FundraiserMilestone(title: msTitle, amount: "$\(String(format: "%,.0f", msAmount))", isComplete: isComplete)
                }
            }
            if milestones.isEmpty {
                milestones = [
                    FundraiserMilestone(title: "Phase 1", amount: "$\(String(format: "%,.0f", goalAmount * 0.3))", isComplete: progress >= 0.3),
                    FundraiserMilestone(title: "Phase 2", amount: "$\(String(format: "%,.0f", goalAmount * 0.6))", isComplete: progress >= 0.6),
                    FundraiserMilestone(title: "Complete", amount: "$\(String(format: "%,.0f", goalAmount))", isComplete: progress >= 1.0),
                ]
            }

            return FundraiserDetail(
                title: title,
                organizer: organizer,
                description_: desc,
                raised: "$\(String(format: "%,.0f", raisedAmount))",
                goal: "$\(String(format: "%,.0f", goalAmount))",
                progress: progress,
                backersCount: backers,
                daysRemaining: "\(daysLeft) days left",
                status: status,
                isVerified: verified,
                tags: tags,
                milestones: milestones
            )
        }
    }
}

// MARK: - Fundraiser View

struct FundraiserView: View {
    @StateObject private var viewModel = FundraiserViewModel()

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.fundraisers.isEmpty {
                loadingState
            } else if let error = viewModel.errorMessage, viewModel.fundraisers.isEmpty {
                errorState(error)
            } else {
                contentView
            }
        }
        .navigationTitle("Fundraisers")
        .searchable(text: $viewModel.searchText, prompt: "Search fundraisers...")
        .task {
            await viewModel.loadFundraisers()
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Loading fundraisers...")
                .font(.mtrxSubheadline)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: Symbols.alertWarning)
                .font(.system(size: 48))
                .foregroundStyle(Color.statusWarning)
            Text("Failed to load fundraisers")
                .font(.mtrxTitle3)
            Text(message)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.loadFundraisers() }
            } label: {
                Label("Retry", systemImage: Symbols.refresh)
                    .font(.mtrxHeadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .frame(height: Spacing.Size.buttonHeight)
                    .background(Color.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sectionGap) {
                statusFilter
                statsOverview

                ForEach(viewModel.filteredFundraisers) { fundraiser in
                    NavigationLink {
                        FundraiserDetailView(fundraiser: fundraiser, viewModel: viewModel)
                    } label: {
                        FundraiserListCard(fundraiser: fundraiser)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.contentPadding)
        }
        .refreshable {
            await viewModel.loadFundraisers()
        }
    }

    // MARK: - Status Filter

    private var statusFilter: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(FundraiserStatus.allCases, id: \.self) { status in
                Button {
                    withAnimation(Motion.springSnappy) {
                        viewModel.selectedStatus = status
                    }
                } label: {
                    Text(status.rawValue)
                        .font(.mtrxCaptionBold)
                        .padding(.horizontal, Spacing.chipHorizontal)
                        .padding(.vertical, Spacing.chipVertical)
                        .background(viewModel.selectedStatus == status ? Color.accentPrimary : Color.surfaceOverlay)
                        .foregroundStyle(viewModel.selectedStatus == status ? .white : Color.labelPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Stats Overview

    private var statsOverview: some View {
        HStack(spacing: Spacing.md) {
            FundraiserStatBox(title: "Total Raised", value: viewModel.totalRaised, icon: Symbols.trendUp)
            FundraiserStatBox(title: "Active", value: "\(viewModel.activeCount)", icon: Symbols.fundraiser)
            FundraiserStatBox(title: "Backers", value: viewModel.totalBackers >= 1000 ? "\(String(format: "%.1f", Double(viewModel.totalBackers) / 1000))K" : "\(viewModel.totalBackers)", icon: Symbols.backers)
        }
    }
}

// MARK: - Fundraiser List Card

struct FundraiserListCard: View {
    let fundraiser: FundraiserDetail

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Text(fundraiser.title)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.labelPrimary)

                        if fundraiser.isVerified {
                            Image(systemName: Symbols.verified)
                                .foregroundStyle(Color.accentPrimary)
                                .font(.system(size: 14))
                        }
                    }

                    Text(fundraiser.organizer)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                Text(fundraiser.status.rawValue)
                    .font(.mtrxCaptionBold)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(fundraiser.status.color.opacity(0.15))
                    .foregroundStyle(fundraiser.status.color)
                    .clipShape(Capsule())
            }

            Text(fundraiser.description_)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)

            // Progress bar
            VStack(spacing: Spacing.xs) {
                ProgressView(value: fundraiser.progress)
                    .tint(Color.accentPrimary)

                HStack {
                    Text(fundraiser.raised)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.accentPrimary)

                    Text("of \(fundraiser.goal)")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)

                    Spacer()

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: Symbols.backers)
                            .font(.system(size: 12))
                        Text("\(fundraiser.backersCount) backers")
                    }
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                }
            }

            HStack {
                Label(fundraiser.daysRemaining, systemImage: Symbols.clock)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)

                Spacer()

                HStack(spacing: Spacing.xs) {
                    ForEach(fundraiser.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.mtrxCaption2)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.surfaceOverlay)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .mtrxCardStyle()
    }
}

// MARK: - Fundraiser Detail View

struct FundraiserDetailView: View {
    let fundraiser: FundraiserDetail
    @ObservedObject var viewModel: FundraiserViewModel
    @State private var contributionAmount: String = ""
    @State private var showContributeSheet: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.sectionGap) {
                // Hero
                RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous)
                    .fill(LinearGradient.mtrxPrimary)
                    .frame(height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: Symbols.fundraiser)
                                .font(.system(size: 48))
                                .foregroundStyle(.white)
                            Text(fundraiser.title)
                                .font(.mtrxTitle2)
                                .foregroundStyle(.white)
                        }
                    )

                // Progress
                VStack(spacing: Spacing.sm) {
                    HStack {
                        Text(fundraiser.raised)
                            .font(.mtrxMonoMedium)
                        Text("of \(fundraiser.goal)")
                            .font(.mtrxSubheadline)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    ProgressView(value: fundraiser.progress)
                        .tint(Color.accentPrimary)
                        .scaleEffect(y: 2)

                    HStack {
                        Label("\(fundraiser.backersCount) backers", systemImage: Symbols.backers)
                        Spacer()
                        Label(fundraiser.daysRemaining, systemImage: Symbols.clock)
                    }
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
                }

                // Description
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("About")
                        .font(.mtrxTitle3)
                    Text(fundraiser.description_)
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                }

                // Milestones
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Milestones")
                        .font(.mtrxTitle3)

                    ForEach(fundraiser.milestones) { milestone in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: milestone.isComplete ? Symbols.complete : Symbols.pending)
                                .foregroundStyle(milestone.isComplete ? Color.statusSuccess : Color.labelTertiary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(milestone.title)
                                    .font(.mtrxBodyBold)
                                Text(milestone.amount)
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelSecondary)
                            }

                            Spacer()

                            if milestone.isComplete {
                                Text("Complete")
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.statusSuccess)
                            }
                        }
                        .padding(Spacing.sm)
                        .background(Color.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                    }
                }
            }
            .padding(Spacing.contentPadding)
        }
        .navigationTitle(fundraiser.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                showContributeSheet = true
            } label: {
                Text("Contribute")
                    .font(.mtrxHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Spacing.Size.buttonHeight)
                    .background(Color.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
            .padding(Spacing.contentPadding)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showContributeSheet) {
            ContributeSheet(fundraiser: fundraiser, viewModel: viewModel)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Contribute Sheet

struct ContributeSheet: View {
    let fundraiser: FundraiserDetail
    @ObservedObject var viewModel: FundraiserViewModel
    @State private var amount: String = ""
    @State private var selectedToken: String = "USDC"
    @State private var isContributing: Bool = false
    @State private var contributionError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Text("Contribute to \(fundraiser.title)")
                    .font(.mtrxTitle3)

                VStack(spacing: Spacing.sm) {
                    TextField("Amount", text: $amount)
                        .font(.mtrxMonoMedium)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.surfaceOverlay)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))

                    HStack {
                        ForEach(["10", "50", "100", "500"], id: \.self) { preset in
                            Button {
                                amount = preset
                            } label: {
                                Text("$\(preset)")
                                    .font(.mtrxCaptionBold)
                                    .padding(.horizontal, Spacing.chipHorizontal)
                                    .padding(.vertical, Spacing.chipVertical)
                                    .background(amount == preset ? Color.accentPrimary.opacity(0.2) : Color.surfaceOverlay)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error = contributionError {
                    Text(error)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.statusError)
                }

                Spacer()

                Button {
                    guard let amountValue = Double(amount), amountValue > 0 else { return }
                    isContributing = true
                    contributionError = nil
                    Task {
                        do {
                            try await viewModel.contribute(
                                campaignId: fundraiser.id.uuidString,
                                amount: amountValue
                            )
                            dismiss()
                        } catch {
                            contributionError = error.localizedDescription
                        }
                        isContributing = false
                    }
                } label: {
                    HStack {
                        if isContributing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Confirm Contribution")
                        }
                    }
                    .font(.mtrxHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Spacing.Size.buttonHeight)
                    .background(amount.isEmpty ? Color.labelTertiary : Color.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
                .disabled(amount.isEmpty || isContributing)
            }
            .padding(Spacing.contentPadding)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct FundraiserStatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentPrimary)
            Text(value)
                .font(.mtrxHeadline)
            Text(title)
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Enums & Models

enum FundraiserStatus: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case funded = "Funded"
    case closed = "Closed"

    var color: Color {
        switch self {
        case .all: return Color.labelPrimary
        case .active: return Color.statusSuccess
        case .funded: return Color.accentPrimary
        case .closed: return Color.labelTertiary
        }
    }
}

struct FundraiserDetail: Identifiable {
    let id = UUID()
    let title: String
    let organizer: String
    let description_: String
    let raised: String
    let goal: String
    let progress: Double
    let backersCount: Int
    let daysRemaining: String
    let status: FundraiserStatus
    let isVerified: Bool
    let tags: [String]
    let milestones: [FundraiserMilestone]

    static let sampleData: [FundraiserDetail] = [
        FundraiserDetail(
            title: "Community Solar", organizer: "SolarDAO",
            description_: "Solar panel installation for rural communities providing sustainable energy.",
            raised: "$72,000", goal: "$100,000", progress: 0.72, backersCount: 234,
            daysRemaining: "12 days left", status: .active, isVerified: true,
            tags: ["Energy", "RWA"],
            milestones: [
                FundraiserMilestone(title: "Equipment Purchase", amount: "$30,000", isComplete: true),
                FundraiserMilestone(title: "Installation Phase", amount: "$50,000", isComplete: true),
                FundraiserMilestone(title: "Grid Connection", amount: "$100,000", isComplete: false),
            ]
        ),
        FundraiserDetail(
            title: "Water Access DAO", organizer: "AquaDAO",
            description_: "Clean water infrastructure development in East Africa communities.",
            raised: "$45,000", goal: "$100,000", progress: 0.45, backersCount: 156,
            daysRemaining: "28 days left", status: .active, isVerified: true,
            tags: ["Infrastructure", "DAO"],
            milestones: [
                FundraiserMilestone(title: "Site Survey", amount: "$10,000", isComplete: true),
                FundraiserMilestone(title: "Equipment", amount: "$50,000", isComplete: false),
                FundraiserMilestone(title: "Construction", amount: "$100,000", isComplete: false),
            ]
        ),
    ]
}

struct FundraiserMilestone: Identifiable {
    let id = UUID()
    let title: String
    let amount: String
    let isComplete: Bool
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FundraiserView()
    }
}
