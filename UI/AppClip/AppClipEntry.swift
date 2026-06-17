import SwiftUI
import AppClip

/// App Clip entry point — instant MTRX from QR code scan
@main
struct MTRXAppClip: App {
    var body: some Scene {
        WindowGroup {
            AppClipEntryView()
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    AppClipRouter.shared.route(url: url)
                }
        }
    }
}

struct AppClipEntryView: View {
    @StateObject private var router = AppClipRouter.shared

    var body: some View {
        NavigationStack {
            switch router.destination {
            case .marketplace(let listingId):
                AppClipMarketplace(listingId: listingId)
            case .property(let tokenId):
                AppClipProperty(tokenId: tokenId)
            case .fundraiser(let campaignId):
                AppClipFundraiser(campaignId: campaignId)
            case .none:
                VStack(spacing: 16) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    Text("MTRX").font(.largeTitle).bold()
                    Text("Scan a QR code to get started")
                        .foregroundColor(.secondary)
                    Text("Get the full app for the complete experience.")
                        .font(.caption).foregroundColor(.tertiary)
                }
            }
        }
    }
}

@MainActor
final class AppClipRouter: ObservableObject {
    static let shared = AppClipRouter()
    @Published var destination: AppClipDestination?

    enum AppClipDestination {
        case marketplace(String)
        case property(String)
        case fundraiser(String)
    }

    func route(url: URL) {
        let path = url.pathComponents
        if path.contains("marketplace"), let id = path.last { destination = .marketplace(id) }
        else if path.contains("property"), let id = path.last { destination = .property(id) }
        else if path.contains("fundraiser"), let id = path.last { destination = .fundraiser(id) }
    }
}

/// Honest App Clip teaser. Shows only what's verifiable from the invocation URL
/// (the reference id) and routes to the full app. It deliberately does NOT show
/// amounts, prices, ratings, or history — an App Clip can't fetch those without
/// a backend, and inventing them would be fake. Wire a real per-id fetch here
/// once a public endpoint exists.
struct AppClipTeaser: View {
    let icon: String
    let kind: String
    let reference: String
    let message: String
    let actionTitle: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
            Text(kind).font(.title2).bold()
            Text(reference)
                .font(.caption).monospaced()
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            // Standard App Clip "get the full app" affordance. Present an
            // SKOverlay here once the published App Store id is known.
            Text(actionTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
}
