// AccessControlView.swift
// MTRX
//
// Role-based access control — manage contract roles, grants, revocations, and audit logs.

import SwiftUI

// MARK: - View Model

final class AccessControlViewModel: ObservableObject {

    // MARK: - Published State

    @Published var roles: [ContractRole] = []
    @Published var roleDefinitions: [RoleDefinition] = []
    @Published var auditLog: [AuditEntry] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isEmpty: Bool = false

    // Grant Form
    @Published var grantContract: String = ""
    @Published var grantAddress: String = ""
    @Published var grantRole: String = "Operator"
    @Published var grantExpiry: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @Published var isGranting: Bool = false
    @Published var grantSuccess: Bool = false

    // Revoke
    @Published var showRevokeConfirm: Bool = false
    @Published var roleToRevoke: ContractRole?

    let availableRoles = ["Admin", "Operator", "Minter", "Pauser", "Upgrader"]

    // MARK: - Load

    func loadAccessControl() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            self.roles = ContractRole.sampleData
            self.roleDefinitions = RoleDefinition.sampleData
            self.auditLog = AuditEntry.sampleData
            self.isEmpty = self.roles.isEmpty
            self.isLoading = false
        }
    }

    // MARK: - Grant

    func submitGrant() {
        guard !grantContract.isEmpty, !grantAddress.isEmpty else {
            errorMessage = "Contract and address are required."
            return
        }
        isGranting = true
        errorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            let newRole = ContractRole(
                contractName: self.grantContract,
                contractAddress: "0x\(UUID().uuidString.prefix(8))...",
                role: self.grantRole,
                grantedBy: "You",
                grantedDate: Date(),
                expiryDate: self.grantExpiry
            )
            self.roles.insert(newRole, at: 0)
            self.isEmpty = false
            self.isGranting = false
            self.grantSuccess = true
            self.resetGrantForm()
        }
    }

    // MARK: - Revoke

    func confirmRevoke(_ role: ContractRole) {
        roleToRevoke = role
        showRevokeConfirm = true
    }

    func executeRevoke() {
        guard let target = roleToRevoke else { return }
        roles.removeAll { $0.id == target.id }
        isEmpty = roles.isEmpty
        roleToRevoke = nil

        let entry = AuditEntry(
            action: "Revoke",
            role: target.role,
            contractName: target.contractName,
            performedBy: "You",
            timestamp: Date()
        )
        auditLog.insert(entry, at: 0)
    }

    private func resetGrantForm() {
        grantContract = ""
        grantAddress = ""
        grantRole = "Operator"
        grantExpiry = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    }
}

// MARK: - Models

struct ContractRole: Identifiable {
    let id = UUID()
    let contractName: String
    let contractAddress: String
    let role: String
    let grantedBy: String
    let grantedDate: Date
    let expiryDate: Date

    var roleColor: Color {
        switch role {
        case "Admin": return .red
        case "Operator": return .blue
        case "Minter": return .purple
        case "Pauser": return .orange
        case "Upgrader": return .green
        default: return .gray
        }
    }

    static var sampleData: [ContractRole] {
        [
            ContractRole(contractName: "MTRX Token", contractAddress: "0x1a2b...3c4d", role: "Admin", grantedBy: "Deployer", grantedDate: Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()),
            ContractRole(contractName: "Staking Pool", contractAddress: "0x5e6f...7g8h", role: "Operator", grantedBy: "DAO Multisig", grantedDate: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .month, value: 10, to: Date()) ?? Date()),
            ContractRole(contractName: "NFT Collection", contractAddress: "0x9i0j...1k2l", role: "Minter", grantedBy: "0xABCD...EF01", grantedDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(), expiryDate: Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()),
        ]
    }
}

struct RoleDefinition: Identifiable {
    let id = UUID()
    let name: String
    let permissions: [String]
    let icon: String

    static var sampleData: [RoleDefinition] {
        [
            RoleDefinition(name: "Admin", permissions: ["Grant roles", "Revoke roles", "Upgrade contract", "Pause/unpause", "Mint tokens"], icon: "shield.fill"),
            RoleDefinition(name: "Operator", permissions: ["Execute transactions", "Update parameters", "Manage whitelist"], icon: "gearshape.fill"),
            RoleDefinition(name: "Minter", permissions: ["Mint new tokens", "Set token metadata"], icon: "plus.circle.fill"),
            RoleDefinition(name: "Pauser", permissions: ["Pause contract", "Unpause contract"], icon: "pause.circle.fill"),
            RoleDefinition(name: "Upgrader", permissions: ["Deploy new implementation", "Initialize upgrades"], icon: "arrow.up.circle.fill"),
        ]
    }
}

struct AuditEntry: Identifiable {
    let id = UUID()
    let action: String
    let role: String
    let contractName: String
    let performedBy: String
    let timestamp: Date

    var actionColor: Color {
        switch action {
        case "Grant": return .green
        case "Revoke": return .red
        case "Transfer": return .blue
        default: return .gray
        }
    }

    static var sampleData: [AuditEntry] {
        [
            AuditEntry(action: "Grant", role: "Minter", contractName: "NFT Collection", performedBy: "0xABCD...EF01", timestamp: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()),
            AuditEntry(action: "Grant", role: "Operator", contractName: "Staking Pool", performedBy: "DAO Multisig", timestamp: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()),
            AuditEntry(action: "Revoke", role: "Pauser", contractName: "MTRX Token", performedBy: "Admin", timestamp: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()),
            AuditEntry(action: "Grant", role: "Admin", contractName: "MTRX Token", performedBy: "Deployer", timestamp: Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()),
            AuditEntry(action: "Transfer", role: "Admin", contractName: "Governance", performedBy: "0x1234...5678", timestamp: Calendar.current.date(byAdding: .month, value: -8, to: Date()) ?? Date()),
        ]
    }
}

// MARK: - View

struct AccessControlView: View {
    @StateObject private var viewModel = AccessControlViewModel()
    @State private var selectedTab: ACTab = .myRoles

    private let accentColor = Color(red: 0.0, green: 0.675, blue: 0.694)

    enum ACTab: String, CaseIterable {
        case myRoles = "My Roles"
        case grant = "Grant"
        case definitions = "Definitions"
        case audit = "Audit Log"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                tabContent
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Access Control")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { viewModel.loadAccessControl() }
            .alert("Role Granted", isPresented: $viewModel.grantSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Role has been granted successfully.")
            }
            .alert("Revoke Role", isPresented: $viewModel.showRevokeConfirm) {
                Button("Revoke", role: .destructive) { viewModel.executeRevoke() }
                Button("Cancel", role: .cancel) { }
            } message: {
                if let role = viewModel.roleToRevoke {
                    Text("Are you sure you want to revoke \(role.role) on \(role.contractName)?")
                }
            }
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(ACTab.allCases, id: \.self) { tab in
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
        case .myRoles:
            myRolesSection
        case .grant:
            grantSection
        case .definitions:
            definitionsSection
        case .audit:
            auditSection
        }
    }

    // MARK: - My Roles

    private var myRolesSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading roles...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isEmpty {
                ContentUnavailableView("No Roles", systemImage: "lock.open.display", description: Text("You have no active roles on any contracts."))
            } else {
                List {
                    ForEach(viewModel.roles) { role in
                        roleRow(role)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.confirmRevoke(role)
                                } label: {
                                    Label("Revoke", systemImage: "xmark.circle")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func roleRow(_ role: ContractRole) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(role.contractName)
                    .font(.mtrxHeadline)

                Spacer()

                Text(role.role)
                    .font(.mtrxCaptionBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(role.roleColor)
                    .clipShape(Capsule())
            }

            Text(role.contractAddress)
                .font(.mtrxMonoSmall)
                .foregroundStyle(.secondary)

            HStack {
                Label("By: \(role.grantedBy)", systemImage: "person")
                    .font(.mtrxCaption1)
                    .foregroundStyle(.secondary)

                Spacer()

                Label("Exp: \(role.expiryDate, format: .dateTime.month().day().year())", systemImage: "calendar")
                    .font(.mtrxCaption1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Grant

    private var grantSection: some View {
        Form {
            Section("Contract") {
                TextField("Contract name or address", text: $viewModel.grantContract)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section("Grantee") {
                TextField("0x... address", text: $viewModel.grantAddress)
                    .font(.mtrxMono)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section("Role") {
                Picker("Role", selection: $viewModel.grantRole) {
                    ForEach(viewModel.availableRoles, id: \.self) { role in
                        Text(role).tag(role)
                    }
                }
            }

            Section("Expiry") {
                DatePicker("Expires", selection: $viewModel.grantExpiry, in: Date()..., displayedComponents: .date)
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
                    viewModel.submitGrant()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isGranting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Grant Role")
                                .font(.mtrxHeadline)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                }
                .disabled(viewModel.isGranting)
                .listRowInsets(EdgeInsets())
                .padding(Spacing.contentPadding)
            }
        }
    }

    // MARK: - Definitions

    private var definitionsSection: some View {
        List {
            ForEach(viewModel.roleDefinitions) { definition in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: definition.icon)
                            .foregroundStyle(accentColor)
                            .font(.title3)
                        Text(definition.name)
                            .font(.mtrxHeadline)
                    }

                    ForEach(definition.permissions, id: \.self) { permission in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(permission)
                                .font(.mtrxSubheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Audit Log

    private var auditSection: some View {
        List {
            ForEach(viewModel.auditLog) { entry in
                HStack(alignment: .top, spacing: Spacing.ms) {
                    Circle()
                        .fill(entry.actionColor)
                        .frame(width: 10, height: 10)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text(entry.action)
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(entry.actionColor)
                            Text(entry.role)
                                .font(.mtrxCaptionBold)
                            Text("on")
                                .font(.mtrxCaption1)
                                .foregroundStyle(.secondary)
                            Text(entry.contractName)
                                .font(.mtrxCaptionBold)
                        }

                        HStack {
                            Text("By: \(entry.performedBy)")
                                .font(.mtrxCaption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.timestamp, format: .dateTime.month().day().year())
                                .font(.mtrxCaption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Preview

#Preview {
    AccessControlView()
}
