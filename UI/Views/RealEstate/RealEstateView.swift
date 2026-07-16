// RealEstateView.swift
// MTRX — Real-Estate Escrow Engine front-end (browse + detail + readiness).
//
// Honest-failure law applied to the buy button: readiness is NEVER faked. A
// property shows "transaction-ready" with a clear purchase path ONLY when the
// backend readiness engine returns ready=true; otherwise the named blockers are
// shown to the user exactly as returned. Server-disabled (403) and
// not-connected states present honestly as "coming soon", never fake data.

import SwiftUI

// MARK: - Feature state (honest)

enum RealEstateFeatureState: Equatable {
    case loading
    case comingSoon          // services.real_estate.enabled=false (HTTP 403)
    case notConnected        // no backend gateway configured
    case live                // enabled + reachable
    case error(String)
}

// MARK: - Formatting helpers

enum RE {
    /// wei (decimal string) → a short ETH string, e.g. "1.25 ETH". Uses Decimal
    /// (never Int64) so large prices don't overflow. Honest "—" if unparseable.
    static func ethString(_ wei: String?) -> String {
        guard let wei, let d = Decimal(string: wei) else { return "—" }
        let eth = d / Decimal(sign: .plus, exponent: 18, significand: 1)
        var rounded = Decimal()
        var input = eth
        NSDecimalRound(&rounded, &input, 4, .plain)
        let ns = rounded as NSDecimalNumber
        let s = ns.stringValue
        return "\(s) ETH"
    }

    static func date(_ epoch: Double?) -> String {
        guard let epoch, epoch > 0 else { return "—" }
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }

    /// Human label for a document/blocker key: title_report → "Title report".
    static func label(_ key: String) -> String {
        key.split(separator: "_").enumerated().map { i, part in
            i == 0 ? part.capitalized : String(part)
        }.joined(separator: " ")
    }

    static func propertyStatusColor(_ status: String) -> Color {
        switch status {
        case "listed": return .statusSuccess
        case "under_escrow": return .statusWarning
        case "sold": return .labelTertiary
        default: return .labelSecondary
        }
    }
}

// MARK: - Document freshness (computed on read, honestly)

enum DocFreshness {
    case verifiedFresh          // attested + comfortably in-window
    case expiringSoon(Int)      // attested but within N days of expiry
    case stale(Int)             // past expiry (days stale)
    case unverified             // attestation not confirmed

    static let soonWindowDays = 14

    static func of(_ doc: RETimestampedDoc, now: Double = Date().timeIntervalSince1970) -> DocFreshness {
        let expires = doc.expiresAt ?? 0
        if now >= expires {
            let days = max(1, Int(((now - expires) / 86400).rounded(.up)))
            return .stale(days)
        }
        if doc.attestationStatus != "attested" { return .unverified }
        let daysLeft = Int(((expires - now) / 86400).rounded(.down))
        if daysLeft <= soonWindowDays { return .expiringSoon(daysLeft) }
        return .verifiedFresh
    }

    var color: Color {
        switch self {
        case .verifiedFresh: return .statusSuccess
        case .expiringSoon: return .statusWarning
        case .stale, .unverified: return .statusError
        }
    }
    var icon: String {
        switch self {
        case .verifiedFresh: return "checkmark.seal.fill"
        case .expiringSoon: return "clock.badge.exclamationmark"
        case .stale: return "exclamationmark.triangle.fill"
        case .unverified: return "questionmark.diamond.fill"
        }
    }
    var text: String {
        switch self {
        case .verifiedFresh: return "Verified · fresh"
        case .expiringSoon(let d): return d <= 0 ? "Expires today" : "Expiring in \(d)d"
        case .stale(let d): return "Stale · \(d)d overdue"
        case .unverified: return "Not yet verified"
        }
    }
}

// MARK: - Hub view (opened from Discover ▸ Real World Assets)

struct RealEstateView: View {
    @StateObject private var viewModel = RealEstateViewModel()

    var body: some View { _content.mvpGated() }

    @ViewBuilder private var _content: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .comingSoon:
                    RealEstateComingSoon(
                        reason: "Property purchasing is being prepared. Soon you'll "
                              + "buy a home in one tap — every document verified, "
                              + "settled in seconds.")
                case .notConnected:
                    RealEstateComingSoon(
                        reason: "Connect a gateway in Settings → Trinity AI to browse "
                              + "live properties. Nothing here is simulated.")
                case .error(let m):
                    RealEstateComingSoon(reason: m, systemImage: "wifi.exclamationmark")
                case .live:
                    liveContent
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Real World Assets")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        MyPropertiesView()
                    } label: {
                        Image(systemName: "key.horizontal.fill")
                    }
                    .accessibilityLabel("My properties")
                }
            }
            .task { await viewModel.load() }
        }
    }

    private var liveContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                headerCard
                if viewModel.properties.isEmpty {
                    MtrxEmptyState(
                        icon: "building.2",
                        title: "No properties listed yet",
                        message: "Listed properties will appear here as they come to market.")
                        .padding(.top, Spacing.xl)
                } else {
                    ForEach(viewModel.properties) { property in
                        NavigationLink {
                            RealEstatePropertyDetailView(property: property)
                        } label: {
                            RealEstatePropertyCard(property: property)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.md)
        }
        .refreshable { await viewModel.load() }
    }

    private var headerCard: some View {
        MtrxCard(style: .glass) {
            HStack(spacing: Spacing.md) {
                Image(systemName: Symbols.property)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.accentPrimary.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homeownership at a tap")
                        .font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
                    // "no gas" is claimed only when sponsorship is truly configured.
                    Text(PendingCredentials.isGasSponsorshipConfigured
                         ? "Every closing document pre-verified · settle in seconds · you pay no gas"
                         : "Every closing document pre-verified · settle in seconds")
                        .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Property card (row)

struct RealEstatePropertyCard: View {
    let property: REProperty

    var body: some View {
        MtrxCard(style: .standard) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // imagery placeholder — honest, no fabricated photos
                ZStack {
                    LinearGradient(colors: [Color.accentPrimary.opacity(0.35),
                                            Color.accentSecondary.opacity(0.25)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: Symbols.property)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.labelPrimary.opacity(0.55))
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(property.address.line1 ?? "Property")
                            .font(.mtrxBodyBold).foregroundStyle(Color.labelPrimary)
                            .lineLimit(1)
                        Text(property.address.shortCity)
                            .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    statusBadge
                }
                Text(RE.ethString(property.priceWei))
                    .font(.mtrxHeadlineTabular).foregroundStyle(Color.labelPrimary)
            }
        }
    }

    private var statusBadge: some View {
        Text(RE.label(property.status))
            .font(.mtrxCaption2)
            .foregroundStyle(RE.propertyStatusColor(property.status))
            .padding(.horizontal, Spacing.sm).padding(.vertical, 3)
            .background(RE.propertyStatusColor(property.status).opacity(0.14))
            .clipShape(Capsule())
    }
}

// MARK: - Coming-soon (server-disabled / not-connected honest state)

struct RealEstateComingSoon: View {
    let reason: String
    var systemImage: String = "clock.badge.checkmark"

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentPrimary.opacity(0.8))
            Text("Coming Soon")
                .font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
            Text(reason)
                .font(.mtrxBody).foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hub view-model

@MainActor
final class RealEstateViewModel: ObservableObject {
    @Published var state: RealEstateFeatureState = .loading
    @Published var properties: [REProperty] = []

    func load() async {
        guard PendingCredentials.isBackendConfigured else {
            state = .notConnected; return
        }
        if properties.isEmpty { state = .loading }
        do {
            let list = try await RealEstateService.shared.listProperties(status: "listed")
            properties = list
            state = .live
        } catch let err as MTRXAPIError where err.isSecurityBlock {
            // The whole feature 403s while services.real_estate.enabled=false.
            state = .comingSoon
        } catch {
            state = properties.isEmpty ? .error("Couldn't reach the property service right now.") : .live
        }
    }
}
