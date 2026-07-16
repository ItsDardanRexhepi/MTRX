// RealEstatePurchaseFlow.swift
// MTRX — property detail, the one-tap purchase, buyer verification, escrow
// status, and "my properties". Honest-failure law is absolute here: readiness
// is re-verified server-side at purchase time (never a cached green), every
// state maps to a real backend response, and nothing fabricates a purchase.

import SwiftUI

// MARK: - Local purchase ledger (honest "my properties")
//
// The backend exposes no "escrows for buyer" or "deeds owned by wallet" query,
// so we do NOT invent one. Instead the app remembers the escrow ids it itself
// created (per wallet, on device) and renders each from a REAL getEscrow() —
// so "My Properties" shows only genuine escrows the user actually started here.
// (Deeds acquired outside the app would need an on-chain balanceOf read or a
// new backend endpoint — flagged, not faked.)

enum RealEstateLedger {
    private static func key(_ wallet: String) -> String {
        "com.mtrx.realestate.escrows.\(wallet.lowercased())"
    }
    static func record(escrowId: String, wallet: String) {
        guard !wallet.isEmpty, !escrowId.isEmpty else { return }
        var ids = escrowIds(wallet: wallet)
        if !ids.contains(escrowId) { ids.insert(escrowId, at: 0) }
        UserDefaults.standard.set(ids, forKey: key(wallet))
    }
    static func escrowIds(wallet: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(wallet)) ?? []
    }
}

private func hexToData(_ hex: String) -> Data? {
    var s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
    guard s.count % 2 == 0 else { return nil }
    var out = Data(); out.reserveCapacity(s.count / 2)
    while s.count >= 2 {
        let pair = String(s.prefix(2)); s = String(s.dropFirst(2))
        guard let b = UInt8(pair, radix: 16) else { return nil }
        out.append(b)
    }
    return out
}

// MARK: - Property detail

struct RealEstatePropertyDetailView: View {
    let property: REProperty
    @StateObject private var vm = PropertyDetailViewModel()
    @State private var showPurchase = false
    @State private var showVerify = false

    private var buyer: String { MtrxSession.walletAddress ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                heroCard
                readinessCard
                documentsCard
                verificationRow
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.md)
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle(property.address.line1 ?? "Property")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(property: property, buyer: buyer) }
        .sheet(isPresented: $showPurchase, onDismiss: { Task { await vm.load(property: property, buyer: buyer) } }) {
            RealEstatePurchaseSheet(property: property)
        }
        .sheet(isPresented: $showVerify, onDismiss: { Task { await vm.load(property: property, buyer: buyer) } }) {
            BuyerVerificationView(requiredPriceWei: property.priceWei)
        }
    }

    private var heroCard: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ZStack {
                    LinearGradient(colors: [Color.accentPrimary.opacity(0.35),
                                            Color.accentSecondary.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: Symbols.property)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Color.labelPrimary.opacity(0.55))
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md))

                Text(property.address.display)
                    .font(.mtrxBodyBold).foregroundStyle(Color.labelPrimary)
                Text(RE.ethString(property.priceWei))
                    .font(.mtrxTitle3).foregroundStyle(Color.accentPrimary)
                HStack(spacing: Spacing.sm) {
                    Label(RE.label(property.status),
                          systemImage: "circle.fill")
                        .font(.mtrxCaption1)
                        .foregroundStyle(RE.propertyStatusColor(property.status))
                    Spacer()
                    Text("Seller \(property.sellerWallet.prefix(6))…\(property.sellerWallet.suffix(4))")
                        .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                }
            }
        }
    }

    // Readiness — the honest heart. ready → purchase CTA; not ready → blockers.
    @ViewBuilder private var readinessCard: some View {
        MtrxCard(style: .elevated) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Transaction readiness")
                    .font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)

                if vm.loadingReadiness {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let r = vm.readiness {
                    if r.ready {
                        Label("Transaction-ready", systemImage: "checkmark.seal.fill")
                            .font(.mtrxBodyBold).foregroundStyle(Color.statusSuccess)
                        Text(PendingCredentials.isGasSponsorshipConfigured
                             ? "Every document is verified and current, and your funds are confirmed. You can buy this home in one tap — and you pay no gas."
                             : "Every document is verified and current, and your funds are confirmed. You can buy this home in one tap.")
                            .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                        Button {
                            MtrxHaptics.impact(.medium); showPurchase = true
                        } label: {
                            Label("Buy in one tap", systemImage: "key.fill")
                        }
                        .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
                        .padding(.top, Spacing.xs)
                    } else {
                        Label("Not yet ready", systemImage: "exclamationmark.triangle.fill")
                            .font(.mtrxBodyBold).foregroundStyle(Color.statusWarning)
                        Text("This property can't transact yet. Exactly what's outstanding:")
                            .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                        ForEach(r.blockers) { blocker in
                            blockerRow(blocker)
                        }
                    }
                } else if buyer.isEmpty {
                    Text("Connect a wallet to check your readiness to purchase.")
                        .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                } else {
                    Text("Readiness is unavailable right now.")
                        .font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
                }
            }
        }
    }

    private func blockerRow(_ b: REBlocker) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "circle.fill").font(.system(size: 6))
                .foregroundStyle(Color.statusWarning).padding(.top, 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(RE.label(b.item)).font(.mtrxCaption1).foregroundStyle(Color.labelPrimary)
                Text(blockerReason(b)).font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
            }
            Spacer()
        }
    }

    private func blockerReason(_ b: REBlocker) -> String {
        switch b.reason {
        case "missing": return "Missing — not yet uploaded"
        case "stale": return "Stale — \(b.daysStale ?? 0) day\(b.daysStale == 1 ? "" : "s") overdue; needs re-upload"
        case "unverified": return "Not verified on-chain yet"
        case "insufficient": return b.detail ?? "Proof of funds doesn't cover the price"
        default: return b.detail ?? b.reason
        }
    }

    private var documentsCard: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Closing documents")
                    .font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
                if vm.documents.isEmpty {
                    Text("No documents uploaded for this property yet.")
                        .font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
                } else {
                    ForEach(vm.sortedDocTypes, id: \.self) { type in
                        if let doc = vm.documents[type] {
                            documentRow(type: type, doc: doc)
                            if type != vm.sortedDocTypes.last { MtrxDivider() }
                        }
                    }
                }
            }
        }
    }

    private func documentRow(type: String, doc: RETimestampedDoc) -> some View {
        let f = DocFreshness.of(doc)
        return HStack(spacing: Spacing.sm) {
            Image(systemName: f.icon).foregroundStyle(f.color)
                .font(.system(size: 16)).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(RE.label(type)).font(.mtrxCaption1).foregroundStyle(Color.labelPrimary)
                Text("Expires \(RE.date(doc.expiresAt))")
                    .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
            }
            Spacer()
            Text(f.text).font(.mtrxCaption2).foregroundStyle(f.color)
        }
        .padding(.vertical, 2)
    }

    private var verificationRow: some View {
        Button { showVerify = true } label: {
            MtrxCard(style: .glass) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(vm.buyerVerified ? Color.statusSuccess : Color.accentPrimary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.buyerVerified ? "Funds verified" : "Verify your funds")
                            .font(.mtrxCaption1).foregroundStyle(Color.labelPrimary)
                        Text(vm.buyerVerified
                             ? "Your proof-of-funds is current."
                             : "Confirm you can cover the price to become purchase-ready.")
                            .font(.mtrxCaption2).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Image(systemName: Symbols.forward).font(.system(size: 12))
                        .foregroundStyle(Color.labelTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class PropertyDetailViewModel: ObservableObject {
    @Published var readiness: REReadiness?
    @Published var documents: [String: RETimestampedDoc] = [:]
    @Published var buyerVerified = false
    @Published var loadingReadiness = false

    /// Documents in the canonical closing order.
    private let order = ["title_report", "inspection", "pest_roof_inspection",
                         "appraisal", "seller_disclosures", "hoa_documents",
                         "insurance_binder"]
    var sortedDocTypes: [String] {
        let known = order.filter { documents[$0] != nil }
        let extra = documents.keys.filter { !order.contains($0) }.sorted()
        return known + extra
    }

    func load(property: REProperty, buyer: String) async {
        guard PendingCredentials.isBackendConfigured else { return }
        loadingReadiness = true
        defer { loadingReadiness = false }
        if let docs = try? await RealEstateService.shared.getDocuments(propertyId: property.id) {
            documents = docs.current
        }
        if !buyer.isEmpty {
            readiness = try? await RealEstateService.shared.getReadiness(propertyId: property.id, buyer: buyer)
            if let v = try? await RealEstateService.shared.getBuyerVerification(wallet: buyer) {
                buyerVerified = v.isVerified
            }
        }
    }
}

// MARK: - The one-tap purchase sheet (the signature moment)

struct RealEstatePurchaseSheet: View {
    let property: REProperty
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = PurchaseViewModel()

    private var buyer: String { MtrxSession.walletAddress ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    summaryCard
                    stageCard
                    if let escrowId = vm.escrowId {
                        NavigationLink {
                            RealEstateEscrowView(escrowId: escrowId)
                        } label: {
                            Label("View escrow status", systemImage: Symbols.escrow)
                                .font(.mtrxCaption1)
                        }
                    }
                    Spacer(minLength: Spacing.lg)
                    actionButton
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Confirm purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private var summaryCard: some View {
        MtrxCard(style: .elevated) {
            VStack(spacing: Spacing.sm) {
                reviewRow("Property", property.address.line1 ?? "—")
                MtrxDivider()
                reviewRow("Location", property.address.shortCity)
                MtrxDivider()
                reviewRow("Price", RE.ethString(property.priceWei))
                MtrxDivider()
                HStack {
                    Text("Gas").font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                    Spacer()
                    // Honest: "$0" is claimed ONLY when the paymaster path is
                    // genuinely configured — otherwise the buyer pays network fees.
                    if PendingCredentials.isGasSponsorshipConfigured {
                        Label("Sponsored — you pay $0", systemImage: "fuelpump.slash.fill")
                            .font(.mtrxCaptionBold).foregroundStyle(Color.statusSuccess)
                    } else {
                        Text("Network fee applies")
                            .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                    }
                }
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
            Spacer()
            Text(value).font(.mtrxCaption1).foregroundStyle(Color.labelPrimary)
        }
    }

    private var stageCard: some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.sm) {
                switch vm.stage {
                case .idle:
                    Image(systemName: "key.fill").foregroundStyle(Color.accentPrimary)
                    Text("One tap becomes a home. Face ID confirms; funds lock and settle atomically against the deed.")
                        .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                case .working(let msg):
                    ProgressView()
                    Text(msg).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                case .settled(let note):
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.statusSuccess)
                    Text(note).font(.mtrxCaption1).foregroundStyle(Color.labelPrimary)
                case .refused(let msg):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.statusWarning)
                    Text(msg).font(.mtrxCaption1).foregroundStyle(Color.labelPrimary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var actionButton: some View {
        if case .settled = vm.stage {
            Button("Done") { dismiss() }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large, fullWidth: true))
        } else {
            Button {
                Task { await vm.purchase(property: property, buyer: buyer) }
            } label: {
                Label("Buy in one tap", systemImage: "faceid")
            }
            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .large,
                                         isLoading: vm.isBusy, fullWidth: true))
            .disabled(vm.isBusy)
        }
    }
}

@MainActor
final class PurchaseViewModel: ObservableObject {
    enum Stage: Equatable {
        case idle
        case working(String)
        case settled(String)
        case refused(String)
    }
    @Published var stage: Stage = .idle
    @Published var escrowId: String?
    var isBusy: Bool { if case .working = stage { return true }; return false }

    func purchase(property: REProperty, buyer: String) async {
        guard !buyer.isEmpty else { stage = .refused("Connect a wallet first."); return }

        // 1. Face ID BEFORE anything is prepared or signed. Cancel aborts.
        do {
            let ok = try await BiometricAuth.shared.authenticate(
                reason: "Confirm buying \(property.address.line1 ?? "this property")")
            guard ok else { return }
        } catch {
            stage = .refused("Face ID wasn't confirmed. Nothing happened.")
            return
        }

        // 2. Server re-verifies readiness at execution — never a cached green.
        stage = .working("Verifying readiness…")
        let prep: REPurchaseResponse
        do {
            prep = try await RealEstateService.shared.executePurchase(buyer: buyer, propertyId: property.id)
        } catch let e as MTRXAPIError where e.isSecurityBlock {
            stage = .refused("Purchasing isn't available yet."); return
        } catch {
            stage = .refused("Couldn't reach the purchase service. Nothing happened."); return
        }

        switch prep.status {
        case "not_ready":
            let names = (prep.readiness?.blockers ?? []).map { RE.label($0.item) }.joined(separator: ", ")
            stage = .refused("Not ready to purchase — outstanding: \(names.isEmpty ? "see property detail" : names).")
            return
        case "not_deployed":
            stage = .refused("One-tap purchasing isn't live yet — the escrow contracts are being deployed. Your funds were not touched.")
            return
        case "prepared":
            break
        default:
            stage = .refused("Unexpected response (\(prep.status)). Nothing happened.")
            return
        }

        guard let settlement = prep.settlement, let escrow = prep.escrow else {
            stage = .refused("The settlement wasn't prepared. Nothing happened."); return
        }
        escrowId = escrow.id
        RealEstateLedger.record(escrowId: escrow.id, wallet: buyer)

        // 3. Submit the atomic settlement from the buyer's own account
        //    (gas-sponsored). Honest failures never claim success.
        guard BlockchainBridge.shared.isWalletConnected else {
            stage = .refused("Your on-chain wallet isn't connected for settlement yet. The escrow is recorded; complete it once your wallet is set up.")
            return
        }
        guard let value = UInt64(settlement.valueWei) else {
            stage = .refused("This property's price exceeds the current one-tap signing limit. Flagged — no funds moved.")
            return
        }
        guard let data = hexToData(settlement.data) else {
            stage = .refused("The settlement data couldn't be prepared. Nothing happened."); return
        }

        stage = .working("Locking funds & settling…")
        let hash: String
        do {
            let result = try await BlockchainBridge.shared.sendTransaction(
                to: settlement.to, amount: value, data: data)
            hash = result.transactionHash
            guard hash.hasPrefix("0x"), hash.count > 2 else {
                stage = .refused("The network didn't return a valid transaction. Check your wallet before retrying."); return
            }
        } catch {
            stage = .refused((error as? LocalizedError)?.errorDescription ?? "Settlement couldn't be submitted. Nothing was finalized.")
            return
        }

        // 4. Confirm the settlement on-chain (server verifies the receipt really
        //    settled THIS escrow — an unrelated tx can't fake it).
        stage = .working("Confirming settlement…")
        do {
            let confirm = try await RealEstateService.shared.confirmSettlement(escrowId: escrow.id, txHash: hash)
            switch confirm.status {
            case "settled":
                MtrxHaptics.success()
                stage = .settled(confirm.honestNote ?? "Settled on-chain. County recording is pending — tracked, not instant.")
            case "pending":
                stage = .working("Transaction submitted — awaiting confirmation. Track it in escrow status.")
            default:
                stage = .refused(confirm.message ?? "Settlement not confirmed on-chain.")
            }
        } catch {
            stage = .refused("Submitted, but confirmation failed. Check escrow status before retrying.")
        }
    }
}

// MARK: - Buyer verification (proof of funds)

struct BuyerVerificationView: View {
    let requiredPriceWei: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = VerificationViewModel()

    private var buyer: String { MtrxSession.walletAddress ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    statusCard
                    walletMethodCard
                    bankMethodCard
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Proof of funds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() } } }
            .task { await vm.loadCurrent(buyer: buyer) }
        }
        .presentationDetents([.large])
    }

    private var statusCard: some View {
        MtrxCard(style: .elevated) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Required: \(RE.ethString(requiredPriceWei))")
                    .font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
                if let s = vm.statusText {
                    Text(s).font(.mtrxCaption1).foregroundStyle(vm.statusColor)
                }
            }
        }
    }

    private var walletMethodCard: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Wallet balance", systemImage: "wallet.pass.fill")
                    .font(.mtrxBodyBold).foregroundStyle(Color.labelPrimary)
                Text("Prove your on-chain balance covers the price. Real, automatic, private — read directly from the chain.")
                    .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                Button {
                    Task { await vm.verifyWallet(buyer: buyer, priceWei: requiredPriceWei) }
                } label: {
                    Label("Verify my funds", systemImage: "checkmark.shield")
                }
                .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular,
                                             isLoading: vm.isBusy, fullWidth: true))
                .disabled(vm.isBusy)
            }
        }
    }

    private var bankMethodCard: some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "building.columns.fill").foregroundStyle(Color.labelTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bank verification").font(.mtrxCaption1).foregroundStyle(Color.labelPrimary)
                    Text("Coming soon — external bank proof-of-funds isn't available yet.")
                        .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                }
                Spacer()
                Text("Soon").font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                    .padding(.horizontal, Spacing.sm).padding(.vertical, 2)
                    .background(Color.labelTertiary.opacity(0.12)).clipShape(Capsule())
            }
        }
    }
}

@MainActor
final class VerificationViewModel: ObservableObject {
    @Published var statusText: String?
    @Published var statusColor: Color = .labelSecondary
    @Published var isBusy = false

    func loadCurrent(buyer: String) async {
        guard !buyer.isEmpty, PendingCredentials.isBackendConfigured else {
            statusText = "Connect a wallet to verify funds."; return
        }
        if let v = try? await RealEstateService.shared.getBuyerVerification(wallet: buyer) {
            apply(v)
        }
    }

    func verifyWallet(buyer: String, priceWei: String) async {
        guard !buyer.isEmpty else { statusText = "Connect a wallet first."; return }
        isBusy = true; defer { isBusy = false }
        do {
            let v = try await RealEstateService.shared.verifyBuyer(buyer: buyer, thresholdWei: priceWei)
            apply(v)
        } catch let e as MTRXAPIError where e.isSecurityBlock {
            statusText = "Verification isn't available yet."; statusColor = .labelTertiary
        } catch {
            statusText = "Couldn't verify right now. Nothing was recorded."; statusColor = .statusWarning
        }
    }

    private func apply(_ v: REVerification) {
        switch v.status {
        case "verified":
            statusText = "Verified — your funds cover the price."; statusColor = .statusSuccess
        case "insufficient_funds":
            statusText = "Your on-chain balance doesn't cover the price yet."; statusColor = .statusWarning
        case "not_deployed":
            statusText = "Verification needs a live network connection — try again shortly."; statusColor = .labelTertiary
        case "none":
            statusText = "No verification on file yet."; statusColor = .labelSecondary
        default:
            statusText = v.message ?? "Verification status: \(v.status ?? "unknown")."; statusColor = .labelSecondary
        }
    }
}

// MARK: - Escrow status (the state machine, surfaced truthfully)

struct RealEstateEscrowView: View {
    let escrowId: String
    @StateObject private var vm = EscrowViewModel()

    private static let stages: [(String, String)] = [
        ("initiated", "Purchase initiated"),
        ("funds_locked", "Funds locked in escrow"),
        ("settled", "Settled on-chain — deed transferred"),
        ("offchain_recording_pending", "County recording pending"),
        ("complete", "Recording complete"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if let e = vm.escrow {
                    if e.state == "refunded" {
                        refundedCard
                    } else {
                        timelineCard(current: e.state)
                    }
                    honestNoteCard(state: e.state)
                } else if vm.loading {
                    ProgressView().padding(.top, Spacing.xl)
                } else {
                    MtrxEmptyState(icon: Symbols.escrow, title: "Escrow unavailable",
                                   message: "Couldn't load this escrow right now.")
                }
            }
            .padding(Spacing.contentPadding)
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle("Escrow status")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(escrowId: escrowId) }
        .refreshable { await vm.load(escrowId: escrowId) }
    }

    private func timelineCard(current: String) -> some View {
        let idx = Self.stages.firstIndex { $0.0 == current } ?? 0
        return MtrxCard(style: .elevated) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(Array(Self.stages.enumerated()), id: \.offset) { i, stage in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: i < idx ? "checkmark.circle.fill"
                              : (i == idx ? "circle.circle.fill" : "circle"))
                            .foregroundStyle(i <= idx ? Color.statusSuccess : Color.labelTertiary)
                        Text(stage.1)
                            .font(i == idx ? .mtrxBodyBold : .mtrxCaption1)
                            .foregroundStyle(i <= idx ? Color.labelPrimary : Color.labelTertiary)
                        Spacer()
                    }
                }
            }
        }
    }

    private var refundedCard: some View {
        MtrxCard(style: .elevated) {
            Label("Refunded — funds returned to you", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.mtrxBodyBold).foregroundStyle(Color.statusWarning)
        }
    }

    private func honestNoteCard(state: String) -> some View {
        MtrxCard(style: .glass) {
            Text(honestNote(state))
                .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
        }
    }

    private func honestNote(_ state: String) -> String {
        switch state {
        case "offchain_recording_pending":
            return "The on-chain settlement is complete — funds settled, deed token transferred, trail attested. County recording and notarization are real-world steps still in progress; we track them honestly and never mark them done early."
        case "complete":
            return "County recording is complete. This purchase is fully finalized."
        case "settled":
            return "Settled on-chain. Legal recording will be tracked next."
        default:
            return "This purchase is in progress. Every step shown here is real on-chain/record state."
        }
    }
}

@MainActor
final class EscrowViewModel: ObservableObject {
    @Published var escrow: REEscrow?
    @Published var loading = false
    func load(escrowId: String) async {
        guard PendingCredentials.isBackendConfigured else { return }
        loading = true; defer { loading = false }
        escrow = try? await RealEstateService.shared.getEscrow(id: escrowId)
    }
}

// MARK: - My properties (honest client ledger)

struct MyPropertiesView: View {
    @StateObject private var vm = MyPropertiesViewModel()
    private var buyer: String { MtrxSession.walletAddress ?? "" }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if vm.escrows.isEmpty {
                    MtrxEmptyState(icon: "key.horizontal",
                                   title: "No purchases yet",
                                   message: "Homes you buy in the app appear here with their live escrow status.")
                        .padding(.top, Spacing.xl)
                } else {
                    ForEach(vm.escrows) { escrow in
                        NavigationLink {
                            RealEstateEscrowView(escrowId: escrow.id)
                        } label: {
                            escrowRow(escrow)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Spacing.contentPadding)
        }
        .background(MtrxGradientBackground(style: .primary))
        .navigationTitle("My properties")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load(buyer: buyer) }
        .refreshable { await vm.load(buyer: buyer) }
    }

    private func escrowRow(_ e: REEscrow) -> some View {
        MtrxCard(style: .standard) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: e.state == "complete" ? "key.fill" : Symbols.escrow)
                    .foregroundStyle(e.state == "complete" ? Color.statusSuccess : Color.accentPrimary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(RE.ethString(e.amountWei)).font(.mtrxBodyBold).foregroundStyle(Color.labelPrimary)
                    Text(RE.label(e.state)).font(.mtrxCaption2).foregroundStyle(Color.labelSecondary)
                }
                Spacer()
                Image(systemName: Symbols.forward).font(.system(size: 12))
                    .foregroundStyle(Color.labelTertiary)
            }
        }
    }
}

@MainActor
final class MyPropertiesViewModel: ObservableObject {
    @Published var escrows: [REEscrow] = []
    func load(buyer: String) async {
        guard !buyer.isEmpty, PendingCredentials.isBackendConfigured else { escrows = []; return }
        var loaded: [REEscrow] = []
        for id in RealEstateLedger.escrowIds(wallet: buyer) {
            if let e = try? await RealEstateService.shared.getEscrow(id: id) { loaded.append(e) }
        }
        escrows = loaded
    }
}
