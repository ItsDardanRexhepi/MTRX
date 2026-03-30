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
