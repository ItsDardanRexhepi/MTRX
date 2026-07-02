// LicensingView.swift
// MTRX
//
// IP licensing — register intellectual property, issue licenses, and browse marketplace.

import SwiftUI

// MARK: - View Model

final class LicensingViewModel: ObservableObject {

    // MARK: - Published State

    @Published var myIP: [LicensingIPAsset] = []
    @Published var myLicenses: [License] = []
    @Published var marketplace: [LicensingIPAsset] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isEmpty: Bool = false
    @Published var isDemo: Bool = true

    // Register IP
    @Published var registerName: String = ""
    @Published var registerDescription: String = ""
    @Published var registerType: LicensingIPType = .patent
    @Published var registerFee: String = "0.1"
    @Published var isRegistering: Bool = false
    @Published var registerSuccess: Bool = false

    // Issue License
    @Published var licenseRecipient: String = ""
    @Published var licenseScope: LicenseScope = .commercial
    @Published var licenseDuration: Int = 12
    @Published var licensePrice: String = "0.05"
    @Published var selectedIPForLicense: LicensingIPAsset?
    @Published var showIssueLicenseSheet: Bool = false
    @Published var isIssuingLicense: Bool = false

    let ipTypes: [LicensingIPType] = LicensingIPType.allCases
    let licenseScopes: [LicenseScope] = LicenseScope.allCases

    // MARK: - Load

    func loadData() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.myIP = LicensingIPAsset.sampleMine
            self.myLicenses = License.sampleData
            self.marketplace = LicensingIPAsset.sampleMarketplace
            self.isEmpty = self.myIP.isEmpty && self.myLicenses.isEmpty
            self.isLoading = false
        }
    }

    // MARK: - Register

    func registerIP() {
        guard !registerName.isEmpty else {
            errorMessage = "IP name is required."
            return
        }
        isRegistering = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let asset = LicensingIPAsset(
                name: self.registerName,
                description: self.registerDescription,
                type: self.registerType,
                owner: "You",
                registeredDate: Date(),
                licenseCount: 0,
                registrationFee: Double(self.registerFee) ?? 0.1
            )
            self.myIP.insert(asset, at: 0)
            self.isEmpty = false
            self.isRegistering = false
            self.registerSuccess = true
            self.resetRegisterForm()
        }
    }

    // MARK: - Issue License

    func openIssueLicense(for ip: LicensingIPAsset) {
        selectedIPForLicense = ip
        showIssueLicenseSheet = true
    }

    func issueLicense() {
        guard !licenseRecipient.isEmpty, selectedIPForLicense != nil else {
            errorMessage = "Recipient is required."
            return
        }
        isIssuingLicense = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if let ip = self.selectedIPForLicense, let index = self.myIP.firstIndex(where: { $0.id == ip.id }) {
                self.myIP[index].licenseCount += 1
            }
            self.isIssuingLicense = false
            self.showIssueLicenseSheet = false
            self.resetLicenseForm()
        }
    }

    private func resetRegisterForm() {
        registerName = ""
        registerDescription = ""
        registerType = .patent
        registerFee = "0.1"
    }

    private func resetLicenseForm() {
        licenseRecipient = ""
        licenseScope = .commercial
        licenseDuration = 12
        licensePrice = "0.05"
        selectedIPForLicense = nil
    }
}

// MARK: - Models

enum LicensingIPType: String, CaseIterable {
    case patent = "Patent"
    case trademark = "Trademark"
    case copyright = "Copyright"
    case tradeSecret = "Trade Secret"
    case design = "Design"

    var icon: String {
        switch self {
        case .patent: return "doc.text.fill"
        case .trademark: return "t.square.fill"
        case .copyright: return "c.circle.fill"
        case .tradeSecret: return "lock.doc.fill"
        case .design: return "paintpalette.fill"
        }
    }
}

enum LicenseScope: String, CaseIterable {
    case personal = "Personal"
    case commercial = "Commercial"
    case exclusive = "Exclusive"
    case nonExclusive = "Non-Exclusive"

    var icon: String {
        switch self {
        case .personal: return "person"
        case .commercial: return "building.2"
        case .exclusive: return "star.fill"
        case .nonExclusive: return "person.3"
        }
    }
}

struct LicensingIPAsset: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let type: LicensingIPType
    let owner: String
    let registeredDate: Date
    var licenseCount: Int
    let registrationFee: Double

    static var sampleMine: [LicensingIPAsset] {
        [
            LicensingIPAsset(name: "MTRX Protocol Specification", description: "Core protocol specification for decentralized matrix operations.", type: .patent, owner: "You", registeredDate: Calendar.current.date(byAdding: .month, value: -4, to: Date()) ?? Date(), licenseCount: 3, registrationFee: 0.5),
            LicensingIPAsset(name: "MTRX Logo", description: "Registered trademark for the MTRX brand identity.", type: .trademark, owner: "You", registeredDate: Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date(), licenseCount: 1, registrationFee: 0.2),
        ]
    }

    static var sampleMarketplace: [LicensingIPAsset] {
        [
            LicensingIPAsset(name: "ZK Circuit Library", description: "Optimized zero-knowledge proof circuits for identity verification.", type: .patent, owner: "zkLabs.eth", registeredDate: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date(), licenseCount: 15, registrationFee: 1.0),
            LicensingIPAsset(name: "DeFi UI Kit", description: "Professional UI component library for DeFi applications.", type: .design, owner: "designDAO.eth", registeredDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(), licenseCount: 42, registrationFee: 0.3),
            LicensingIPAsset(name: "Oracle Algorithm v2", description: "Price oracle aggregation algorithm with MEV resistance.", type: .tradeSecret, owner: "oraclePro.eth", registeredDate: Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date()) ?? Date(), licenseCount: 8, registrationFee: 2.0),
        ]
    }
}

struct License: Identifiable {
    let id = UUID()
    let ipName: String
    let scope: LicenseScope
    let licensor: String
    let grantedDate: Date
    let expiryDate: Date

    static var sampleData: [License] {
        [
            License(ipName: "ZK Circuit Library", scope: .commercial, licensor: "zkLabs.eth", grantedDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .month, value: 11, to: Date()) ?? Date()),
            License(ipName: "DeFi UI Kit", scope: .nonExclusive, licensor: "designDAO.eth", grantedDate: Calendar.current.date(byAdding: .weekOfYear, value: -2, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .month, value: 10, to: Date()) ?? Date()),
        ]
    }
}

// MARK: - View

struct LicensingView: View {
    @StateObject private var viewModel = LicensingViewModel()
    @State private var selectedTab: LicenseTab = .myIP

    private let accentColor = Color(red: 0.0, green: 0.675, blue: 0.694)

    enum LicenseTab: String, CaseIterable {
        case myIP = "My IP"
        case register = "Register"
        case myLicenses = "Licenses"
        case marketplace = "Marketplace"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                tabContent
            }
            .demoBadge(viewModel.isDemo)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Licensing")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { viewModel.loadData() }
            .alert("IP Registered", isPresented: $viewModel.registerSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your intellectual property has been registered on-chain.")
            }
            .sheet(isPresented: $viewModel.showIssueLicenseSheet) {
                issueLicenseSheet
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(LicenseTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(Motion.springSnappy) { selectedTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.mtrxCaptionBold)
                            .padding(.horizontal, Spacing.chipHorizontal)
                            .padding(.vertical, Spacing.chipVertical)
                            .background(selectedTab == tab ? accentColor : Color(.systemGray5))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .myIP:
            myIPSection
        case .register:
            registerSection
        case .myLicenses:
            myLicensesSection
        case .marketplace:
            marketplaceSection
        }
    }

    // MARK: - My IP

    private var myIPSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.myIP.isEmpty {
                ContentUnavailableView("No IP Registered", systemImage: "doc.text", description: Text("Register your intellectual property to see it here."))
            } else {
                List {
                    ForEach(viewModel.myIP) { ip in
                        ipRow(ip, showLicenseButton: true)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func ipRow(_ ip: LicensingIPAsset, showLicenseButton: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: ip.type.icon)
                    .foregroundStyle(accentColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ip.name)
                        .font(.mtrxHeadline)
                    Text(ip.type.rawValue)
                        .font(.mtrxCaption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ip.licenseCount) licenses")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(accentColor)
                    Text(ip.registeredDate, format: .dateTime.month().day().year())
                        .font(.mtrxCaption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !ip.description.isEmpty {
                Text(ip.description)
                    .font(.mtrxCaption1)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if showLicenseButton {
                Button {
                    viewModel.openIssueLicense(for: ip)
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("Issue License")
                    }
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Register

    private var registerSection: some View {
        Form {
            Section("IP Details") {
                TextField("Name", text: $viewModel.registerName)
                TextEditor(text: $viewModel.registerDescription)
                    .frame(minHeight: 80)
                Picker("Type", selection: $viewModel.registerType) {
                    ForEach(viewModel.ipTypes, id: \.self) { type in
                        Label(type.rawValue, systemImage: type.icon).tag(type)
                    }
                }
            }

            Section("Evidence") {
                HStack {
                    Image(systemName: "paperclip")
                        .foregroundStyle(accentColor)
                    Text("Attach supporting evidence")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(accentColor)
                }
            }

            Section("Registration Fee") {
                HStack {
                    TextField("Fee (ETH)", text: $viewModel.registerFee)
                        .font(.mtrxMono)
                        .keyboardType(.decimalPad)
                    Text("ETH")
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.mtrxFootnote)
                }
            }

            Section {
                Button {
                    viewModel.registerIP()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isRegistering {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "doc.badge.plus")
                            Text("Register IP")
                                .font(.mtrxHeadline)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                }
                .disabled(viewModel.isRegistering)
                .listRowInsets(EdgeInsets())
                .padding(Spacing.contentPadding)
            }
        }
    }

    // MARK: - My Licenses

    private var myLicensesSection: some View {
        Group {
            if viewModel.myLicenses.isEmpty {
                ContentUnavailableView("No Licenses", systemImage: "doc.plaintext", description: Text("Licenses you hold will appear here."))
            } else {
                List {
                    ForEach(viewModel.myLicenses) { license in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text(license.ipName)
                                    .font(.mtrxHeadline)
                                Spacer()
                                Label(license.scope.rawValue, systemImage: license.scope.icon)
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(accentColor)
                            }

                            HStack {
                                Label("Licensor: \(license.licensor)", systemImage: "person")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Label("Exp: \(license.expiryDate, format: .dateTime.month().year())", systemImage: "calendar")
                                    .font(.mtrxCaption1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Marketplace

    private var marketplaceSection: some View {
        Group {
            if viewModel.marketplace.isEmpty {
                ContentUnavailableView("Empty Marketplace", systemImage: "storefront", description: Text("No IP available for licensing."))
            } else {
                List {
                    ForEach(viewModel.marketplace) { ip in
                        ipRow(ip, showLicenseButton: false)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Issue License Sheet

    private var issueLicenseSheet: some View {
        NavigationStack {
            Form {
                if let ip = viewModel.selectedIPForLicense {
                    Section("Licensing") {
                        HStack {
                            Text("IP")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(ip.name)
                                .font(.mtrxHeadline)
                        }
                    }
                }

                Section("Recipient") {
                    TextField("0x... address", text: $viewModel.licenseRecipient)
                        .font(.mtrxMono)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Scope") {
                    Picker("Scope", selection: $viewModel.licenseScope) {
                        ForEach(viewModel.licenseScopes, id: \.self) { scope in
                            Label(scope.rawValue, systemImage: scope.icon).tag(scope)
                        }
                    }
                }

                Section("Duration (Months)") {
                    Stepper("\(viewModel.licenseDuration) months", value: $viewModel.licenseDuration, in: 1...60)
                }

                Section("Price (ETH)") {
                    TextField("Price", text: $viewModel.licensePrice)
                        .font(.mtrxMono)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Button {
                        viewModel.issueLicense()
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isIssuingLicense {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Issue License")
                                    .font(.mtrxHeadline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, Spacing.sm)
                        .background(accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                    }
                    .disabled(viewModel.isIssuingLicense)
                    .listRowInsets(EdgeInsets())
                    .padding(Spacing.contentPadding)
                }
            }
            .navigationTitle("Issue License")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.showIssueLicenseSheet = false }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LicensingView()
}
