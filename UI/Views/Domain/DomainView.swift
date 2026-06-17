// DomainView.swift
// MTRX
//
// ENS domain management — search, register, manage user domains, set primary name.

import SwiftUI

// MARK: - Domain ViewModel

@MainActor
final class DomainViewModel: ObservableObject {

    // MARK: - Published State

    @Published var searchText: String = ""
    @Published var searchResult: DomainSearchResult?
    @Published var isSearching: Bool = false
    @Published var userDomains: [ENSDomain] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedDuration: RegistrationDuration = .oneYear
    @Published var showRegisterSheet: Bool = false
    @Published var isRegistering: Bool = false
    @Published var registrationComplete: Bool = false
    @Published var contentAppeared: Bool = false
    @Published var isDemo: Bool = false

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // Live domains from ENSService (per-wallet) when configured; else demo.
        if PendingCredentials.isBackendConfigured, let address = MtrxSession.walletAddress {
            do {
                let live = try await ENSService.shared.getUserDomains(address: address)
                userDomains = live.map { d in
                    ENSDomain(name: d.name, expiryDate: d.expiresAt,
                              isPrimary: d.isPrimary, resolvedAddress: d.owner)
                }
                isDemo = false
                isLoading = false
                withAnimation(Motion.springDefault) { contentAppeared = true }
                return
            } catch {
                errorMessage = "Live domains unavailable — showing demo."
            }
        }

        try? await Task.sleep(nanoseconds: 800_000_000)

        userDomains = ENSDomain.sampleData
        isDemo = true
        isLoading = false

        withAnimation(Motion.springDefault) {
            contentAppeared = true
        }
    }

    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true

        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let normalized = query.lowercased().hasSuffix(".eth") ? query.lowercased() : "\(query.lowercased()).eth"
        let isAvailable = !["vitalik.eth", "ethereum.eth", "wallet.eth"].contains(normalized)

        searchResult = DomainSearchResult(
            name: normalized,
            isAvailable: isAvailable,
            annualCostUSD: normalized.count <= 7 ? 15.0 : 5.0,
            annualCostETH: normalized.count <= 7 ? 0.005 : 0.0017
        )
        isSearching = false
    }

    func register() async {
        isRegistering = true
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        if let result = searchResult {
            let newDomain = ENSDomain(
                name: result.name,
                expiryDate: Calendar.current.date(byAdding: .year, value: selectedDuration.years, to: Date()) ?? Date(),
                isPrimary: userDomains.isEmpty,
                resolvedAddress: DemoArtifacts.address(seed: "ens|\(result.name)")
            )
            userDomains.insert(newDomain, at: 0)
        }

        isRegistering = false
        registrationComplete = true
        MtrxHaptics.success()
    }

    func setPrimary(_ domain: ENSDomain) {
        for i in userDomains.indices {
            userDomains[i].isPrimary = (userDomains[i].id == domain.id)
        }
        MtrxHaptics.success()
    }
}

// MARK: - Registration Duration

enum RegistrationDuration: CaseIterable {
    case oneYear, twoYears, fiveYears

    var years: Int {
        switch self {
        case .oneYear: return 1
        case .twoYears: return 2
        case .fiveYears: return 5
        }
    }

    var label: String {
        switch self {
        case .oneYear: return "1 Year"
        case .twoYears: return "2 Years"
        case .fiveYears: return "5 Years"
        }
    }
}

// MARK: - Domain View

struct DomainView: View {
    @State private var renewedDomain: String?
    @StateObject private var viewModel = DomainViewModel()

    private let accent = Color(red: 0.0, green: 0.675, blue: 0.694)

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary)

                if viewModel.isLoading && viewModel.userDomains.isEmpty {
                    MtrxLoadingView(rows: 6)
                } else if let error = viewModel.errorMessage {
                    MtrxErrorView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else {
                    domainContent
                }
            }
            .alert("Renewed", isPresented: .init(
            get: { renewedDomain != nil },
            set: { if !$0 { renewedDomain = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(renewedDomain ?? "") is extended for another year on-chain.")
        }
        .navigationTitle("ENS Domains")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if viewModel.isDemo { DemoBadge() }
                }
            }
            .sheet(isPresented: $viewModel.showRegisterSheet) {
                registerSheet
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - Content

    private var domainContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Spacing.sectionGap) {
                // Search section
                searchSection
                    .mtrxStaggeredAppearance(index: 0, isVisible: viewModel.contentAppeared)

                // Search result
                if let result = viewModel.searchResult {
                    searchResultCard(result)
                        .transition(.mtrxScale)
                }

                // User domains
                userDomainsSection
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
    }

    // MARK: - Search Section

    private var searchSection: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                MtrxSearchBar(text: $viewModel.searchText, placeholder: "Search ENS names...")

                Button {
                    MtrxHaptics.impact(.light)
                    Task { await viewModel.search() }
                } label: {
                    if viewModel.isSearching {
                        ProgressView()
                            .tint(accent)
                            .frame(width: 40, height: 40)
                    } else {
                        Image(systemName: Symbols.search)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(accent)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }
                }
                .disabled(viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSearching)
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - Search Result Card

    private func searchResultCard(_ result: DomainSearchResult) -> some View {
        MtrxCard(style: .elevated) {
            VStack(spacing: Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(result.name)
                            .font(.mtrxTitle3)
                            .foregroundStyle(Color.labelPrimary)

                        MtrxBadge(
                            text: result.isAvailable ? "Available" : "Taken",
                            style: result.isAvailable ? .success : .error
                        )
                    }
                    Spacer()
                    Image(systemName: result.isAvailable ? Symbols.complete : Symbols.failed)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(result.isAvailable ? Color.statusSuccess : Color.statusError)
                }

                if result.isAvailable {
                    MtrxDivider()

                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Registration Cost")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            HStack(spacing: Spacing.xs) {
                                Text(String(format: "%.4f ETH", result.annualCostETH))
                                    .font(.mtrxMono)
                                    .foregroundStyle(Color.labelPrimary)
                                Text("/ year")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(Color.labelTertiary)
                            }
                        }
                        Spacer()
                        Text(String(format: "$%.2f", result.annualCostUSD))
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                    }

                    Button {
                        viewModel.showRegisterSheet = true
                        viewModel.registrationComplete = false
                        MtrxHaptics.impact(.medium)
                    } label: {
                        Label("Register", systemImage: Symbols.cart)
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))
                }
            }
        }
        .padding(.horizontal, Spacing.contentPadding)
    }

    // MARK: - User Domains Section

    private var userDomainsSection: some View {
        VStack(spacing: Spacing.md) {
            MtrxSectionHeader(title: "Your Domains", subtitle: "\(viewModel.userDomains.count) domains")
                .padding(.horizontal, Spacing.contentPadding)

            if viewModel.userDomains.isEmpty {
                MtrxEmptyState(
                    icon: Symbols.globe,
                    title: "No Domains Yet",
                    message: "Search for an ENS name above to register your on-chain identity."
                )
                .frame(height: 200)
            } else {
                LazyVStack(spacing: Spacing.md) {
                    ForEach(Array(viewModel.userDomains.enumerated()), id: \.element.id) { index, domain in
                        domainRow(domain)
                            .mtrxStaggeredAppearance(index: index + 1, isVisible: viewModel.contentAppeared)
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    private func domainRow(_ domain: ENSDomain) -> some View {
        MtrxCard(style: .standard, accentEdge: domain.isPrimary ? .leading : nil) {
            VStack(spacing: Spacing.ms) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            Text(domain.name)
                                .font(.mtrxHeadline)
                                .foregroundStyle(Color.labelPrimary)
                            if domain.isPrimary {
                                MtrxBadge(text: "Primary", style: .accent)
                            }
                        }
                        Text(domain.resolvedAddress)
                            .font(.mtrxMonoSmall)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }

                MtrxDivider()

                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Expires")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelTertiary)
                        Text(domain.expiryDate, style: .date)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(domain.isExpiringSoon ? Color.statusWarning : Color.labelSecondary)
                    }

                    Spacer()

                    HStack(spacing: Spacing.sm) {
                        if !domain.isPrimary {
                            Button {
                                viewModel.setPrimary(domain)
                            } label: {
                                Text("Set Primary")
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .ghost, size: .compact))
                        }

                        Button {
                            MtrxHaptics.success()
                            renewedDomain = domain.name
                        } label: {
                            Text("Renew")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .compact))
                    }
                }
            }
        }
    }

    // MARK: - Register Sheet

    private var registerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    MtrxSheetHeader(title: "Register Domain") {
                        viewModel.showRegisterSheet = false
                    }

                    if viewModel.registrationComplete {
                        registrationSuccessView
                    } else {
                        registrationFormView
                    }
                }
                .padding(.bottom, Spacing.xxl)
            }
            .background(MtrxGradientBackground(style: .primary))
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var registrationFormView: some View {
        VStack(spacing: Spacing.lg) {
            if let result = viewModel.searchResult {
                // Domain name
                MtrxCard(style: .glass) {
                    VStack(spacing: Spacing.sm) {
                        Text(result.name)
                            .font(.mtrxTitle2)
                            .foregroundStyle(accent)
                        MtrxBadge(text: "Available", style: .success)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Spacing.contentPadding)

                // Duration picker
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Registration Duration")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(Color.labelSecondary)
                        .padding(.horizontal, Spacing.contentPadding)

                    HStack(spacing: Spacing.sm) {
                        ForEach(RegistrationDuration.allCases, id: \.self) { duration in
                            Button {
                                withAnimation(Motion.springSnappy) {
                                    viewModel.selectedDuration = duration
                                }
                                MtrxHaptics.selection()
                            } label: {
                                VStack(spacing: Spacing.xs) {
                                    Text(duration.label)
                                        .font(.mtrxCaptionBold)
                                    Text(String(format: "%.4f ETH", result.annualCostETH * Double(duration.years)))
                                        .font(.mtrxMonoSmall)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.ms)
                                .foregroundStyle(
                                    viewModel.selectedDuration == duration ? .white : Color.labelPrimary
                                )
                                .background(
                                    viewModel.selectedDuration == duration
                                        ? accent
                                        : Color.surfaceOverlay
                                )
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }

                // Cost summary
                MtrxCard(style: .standard) {
                    VStack(spacing: Spacing.ms) {
                        HStack {
                            Text("Total Cost")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            Spacer()
                            Text(String(format: "%.4f ETH", result.annualCostETH * Double(viewModel.selectedDuration.years)))
                                .font(.mtrxMono)
                                .foregroundStyle(Color.labelPrimary)
                        }
                        HStack {
                            Text("USD Equivalent")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                            Spacer()
                            Text(String(format: "$%.2f", result.annualCostUSD * Double(viewModel.selectedDuration.years)))
                                .font(.mtrxMonoSmall)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                }
                .padding(.horizontal, Spacing.contentPadding)

                // Register button
                Button {
                    MtrxHaptics.impact(.medium)
                    Task { await viewModel.register() }
                } label: {
                    Label("Confirm Registration", systemImage: Symbols.complete)
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, isLoading: viewModel.isRegistering, fullWidth: true))
                .disabled(viewModel.isRegistering)
                .padding(.horizontal, Spacing.contentPadding)
            }
        }
    }

    private var registrationSuccessView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: Symbols.complete)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.statusSuccess)
                .mtrxGlow(color: .statusSuccess)

            VStack(spacing: Spacing.sm) {
                Text("Registration Successful")
                    .font(.mtrxTitle3)
                    .foregroundStyle(Color.labelPrimary)
                if let result = viewModel.searchResult {
                    Text("\(result.name) is now yours!")
                        .font(.mtrxBody)
                        .foregroundStyle(Color.labelSecondary)
                }
            }

            Button {
                viewModel.showRegisterSheet = false
                viewModel.searchResult = nil
                viewModel.searchText = ""
            } label: {
                Text("Done")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular))
        }
        .mtrxFadeInFromBottom(isVisible: true)
        .padding(.horizontal, Spacing.contentPadding)
    }
}

// MARK: - Data Models

struct DomainSearchResult {
    let name: String
    let isAvailable: Bool
    let annualCostUSD: Double
    let annualCostETH: Double
}

struct ENSDomain: Identifiable {
    let id = UUID()
    let name: String
    let expiryDate: Date
    var isPrimary: Bool
    let resolvedAddress: String

    var isExpiringSoon: Bool {
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        return daysUntilExpiry < 90
    }

    static let sampleData: [ENSDomain] = [
        ENSDomain(
            name: "neomatic.eth",
            expiryDate: Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date(),
            isPrimary: true,
            resolvedAddress: DemoArtifacts.address(seed: "ens|neomatic.eth")
        ),
        ENSDomain(
            name: "mtrx-dev.eth",
            expiryDate: Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date(),
            isPrimary: false,
            resolvedAddress: DemoArtifacts.address(seed: "ens|mtrx-dev.eth")
        ),
        ENSDomain(
            name: "trinity-ai.eth",
            expiryDate: Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date(),
            isPrimary: false,
            resolvedAddress: DemoArtifacts.address(seed: "ens|trinity-ai.eth")
        ),
    ]
}

// MARK: - Preview

#Preview {
    DomainView()
}
