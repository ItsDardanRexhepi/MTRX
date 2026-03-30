// FundraiserView.swift
// MTRX
//
// Component 22 — Active fundraisers, progress bars, and contribution interface.

import SwiftUI

// MARK: - Fundraiser View

struct FundraiserView: View {
    @State private var fundraisers: [FundraiserDetail] = FundraiserDetail.sampleData
    @State private var selectedStatus: FundraiserStatus = .active
    @State private var searchText: String = ""

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sectionGap) {
                statusFilter
                statsOverview

                ForEach(filteredFundraisers) { fundraiser in
                    NavigationLink {
                        FundraiserDetailView(fundraiser: fundraiser)
                    } label: {
                        FundraiserListCard(fundraiser: fundraiser)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.contentPadding)
        }
        .navigationTitle("Fundraisers")
        .searchable(text: $searchText, prompt: "Search fundraisers...")
    }

    // MARK: - Status Filter

    private var statusFilter: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(FundraiserStatus.allCases, id: \.self) { status in
                Button {
                    withAnimation(Motion.springSnappy) {
                        selectedStatus = status
                    }
                } label: {
                    Text(status.rawValue)
                        .font(.mtrxCaptionBold)
                        .padding(.horizontal, Spacing.chipHorizontal)
                        .padding(.vertical, Spacing.chipVertical)
                        .background(selectedStatus == status ? Color.accentPrimary : Color.surfaceOverlay)
                        .foregroundStyle(selectedStatus == status ? .white : Color.labelPrimary)
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
            FundraiserStatBox(title: "Total Raised", value: "$2.4M", icon: Symbols.trendUp)
            FundraiserStatBox(title: "Active", value: "23", icon: Symbols.fundraiser)
            FundraiserStatBox(title: "Backers", value: "1.2K", icon: Symbols.backers)
        }
    }

    // MARK: - Filtered

    private var filteredFundraisers: [FundraiserDetail] {
        var result = fundraisers
        if selectedStatus != .all {
            result = result.filter { $0.status == selectedStatus }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return result
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
                        }
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
            ContributeSheet(fundraiser: fundraiser)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Contribute Sheet

struct ContributeSheet: View {
    let fundraiser: FundraiserDetail
    @State private var amount: String = ""
    @State private var selectedToken: String = "USDC"
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
                                    .background(Color.surfaceOverlay)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Confirm Contribution")
                        .font(.mtrxHeadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: Spacing.Size.buttonHeight)
                        .background(amount.isEmpty ? Color.labelTertiary : Color.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
                .disabled(amount.isEmpty)
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
