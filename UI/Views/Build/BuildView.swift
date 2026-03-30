// BuildView.swift
// MTRX
//
// Smart contracts listings and subscription management hub.

import SwiftUI

// MARK: - Build View

struct BuildView: View {
    @State private var selectedSection: BuildSection = .contracts
    @State private var activeContracts: [ContractListItem] = ContractListItem.sampleData
    @State private var subscriptions: [SubscriptionItem] = SubscriptionItem.sampleData
    @State private var showCreateContract: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionPicker

                Group {
                    switch selectedSection {
                    case .contracts:
                        contractsSection
                    case .subscriptions:
                        subscriptionsSection
                    case .templates:
                        templatesSection
                    }
                }
            }
            .navigationTitle("Build")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateContract = true
                    } label: {
                        Image(systemName: Symbols.addCircle)
                    }
                }
            }
            .sheet(isPresented: $showCreateContract) {
                NavigationStack {
                    ContractView()
                }
            }
        }
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        Picker("Section", selection: $selectedSection) {
            ForEach(BuildSection.allCases, id: \.self) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Contracts Section

    private var contractsSection: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                // Summary stats
                HStack(spacing: Spacing.md) {
                    BuildStatCard(title: "Active", value: "\(activeContracts.count)", color: .statusSuccess)
                    BuildStatCard(title: "Pending", value: "2", color: .statusWarning)
                    BuildStatCard(title: "Completed", value: "15", color: .accentPrimary)
                }
                .padding(.bottom, Spacing.sm)

                ForEach(activeContracts) { contract in
                    NavigationLink {
                        ContractDetailView(contract: contract)
                    } label: {
                        ContractListRow(contract: contract)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.contentPadding)
        }
    }

    // MARK: - Subscriptions Section

    private var subscriptionsSection: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(subscriptions) { subscription in
                    SubscriptionRow(subscription: subscription)
                }
            }
            .padding(Spacing.contentPadding)
        }
    }

    // MARK: - Templates Section

    private var templatesSection: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                ForEach(ContractTemplate.sampleData) { template in
                    NavigationLink {
                        ContractView()
                    } label: {
                        TemplateCard(template: template)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.contentPadding)
        }
    }
}

// MARK: - Build Section

enum BuildSection: String, CaseIterable {
    case contracts = "Contracts"
    case subscriptions = "Subscriptions"
    case templates = "Templates"
}

// MARK: - Contract List Row

struct ContractListRow: View {
    let contract: ContractListItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: contract.typeIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: Spacing.Size.avatarMedium, height: Spacing.Size.avatarMedium)
                .background(Color.accentPrimary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(contract.title)
                    .font(.mtrxBodyBold)
                    .foregroundStyle(Color.labelPrimary)

                Text(contract.counterparty)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(contract.value)
                    .font(.mtrxBodyTabular)
                    .foregroundStyle(Color.labelPrimary)

                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(contract.statusColor)
                        .frame(width: 8, height: 8)
                    Text(contract.status)
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                }
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Contract Detail View

struct ContractDetailView: View {
    let contract: ContractListItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                // Status header
                HStack {
                    VStack(alignment: .leading) {
                        Text(contract.title)
                            .font(.mtrxTitle2)
                        Text(contract.counterparty)
                            .font(.mtrxSubheadline)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text(contract.status)
                        .font(.mtrxCaptionBold)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(contract.statusColor.opacity(0.15))
                        .foregroundStyle(contract.statusColor)
                        .clipShape(Capsule())
                }

                // Value
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Contract Value")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                    Text(contract.value)
                        .font(.mtrxMonoMedium)
                }

                Divider()

                // Milestones placeholder
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Milestones")
                        .font(.mtrxTitle3)

                    ForEach(0..<3, id: \.self) { i in
                        HStack {
                            Image(systemName: i == 0 ? Symbols.complete : Symbols.pending)
                                .foregroundStyle(i == 0 ? Color.statusSuccess : Color.labelTertiary)
                            Text("Milestone \(i + 1)")
                                .font(.mtrxBody)
                            Spacer()
                            Text("$\((i + 1) * 1000)")
                                .font(.mtrxBodyTabular)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                }

                // Actions
                VStack(spacing: Spacing.sm) {
                    Button { } label: {
                        Label("View on Chain", systemImage: Symbols.externalLink)
                            .font(.mtrxHeadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: Spacing.Size.buttonHeight)
                            .background(Color.accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    Button { } label: {
                        Label("Raise Dispute", systemImage: Symbols.dispute)
                            .font(.mtrxHeadline)
                            .foregroundStyle(Color.statusError)
                            .frame(maxWidth: .infinity)
                            .frame(height: Spacing.Size.buttonHeight)
                            .background(Color.statusError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
            }
            .padding(Spacing.contentPadding)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Subscription Row

struct SubscriptionRow: View {
    let subscription: SubscriptionItem

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: Symbols.processing)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: Spacing.Size.avatarSmall, height: Spacing.Size.avatarSmall)
                .background(Color.accentPrimary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(subscription.name)
                    .font(.mtrxBodyBold)
                Text(subscription.frequency)
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(subscription.amount)
                    .font(.mtrxBodyTabular)
                Text("Next: \(subscription.nextDate)")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: ContractTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: template.icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.accentPrimary)

            Text(template.name)
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)

            Text(template.description_)
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(2)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
    }
}

// MARK: - Build Stat Card

struct BuildStatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.mtrxTitle2)
                .foregroundStyle(color)
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

// MARK: - Models

struct ContractListItem: Identifiable {
    let id = UUID()
    let title: String
    let counterparty: String
    let value: String
    let status: String
    let statusColor: Color
    let typeIcon: String

    static let sampleData: [ContractListItem] = [
        ContractListItem(title: "Freelance Development", counterparty: "0x1a2b...3c4d", value: "$5,000", status: "Active", statusColor: .statusSuccess, typeIcon: Symbols.contract),
        ContractListItem(title: "Property Lease", counterparty: "PropertyDAO", value: "$2,400/mo", status: "Active", statusColor: .statusSuccess, typeIcon: Symbols.property),
        ContractListItem(title: "Insurance Policy", counterparty: "InsureDAO", value: "$500", status: "Pending", statusColor: .statusWarning, typeIcon: Symbols.insurance),
    ]
}

struct SubscriptionItem: Identifiable {
    let id = UUID()
    let name: String
    let frequency: String
    let amount: String
    let nextDate: String

    static let sampleData: [SubscriptionItem] = [
        SubscriptionItem(name: "DeFi Yield Optimizer", frequency: "Monthly", amount: "$29/mo", nextDate: "Apr 1"),
        SubscriptionItem(name: "Data Oracle Feed", frequency: "Weekly", amount: "$5/wk", nextDate: "Mar 31"),
    ]
}

struct ContractTemplate: Identifiable {
    let id = UUID()
    let name: String
    let description_: String
    let icon: String

    static let sampleData: [ContractTemplate] = [
        ContractTemplate(name: "Escrow", description_: "Milestone-based escrow contract", icon: Symbols.escrow),
        ContractTemplate(name: "Subscription", description_: "Recurring payment stream", icon: Symbols.processing),
        ContractTemplate(name: "DAO Treasury", description_: "Multi-sig treasury management", icon: Symbols.treasury),
        ContractTemplate(name: "Insurance", description_: "Parametric insurance policy", icon: Symbols.insurance),
    ]
}

// MARK: - Preview

#Preview {
    BuildView()
}
