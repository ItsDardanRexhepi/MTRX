import SwiftUI

/// App Clip teaser for a fundraiser. Shows only the campaign reference from the
/// invocation URL and routes to the full app. It does NOT fabricate amounts
/// raised, goals, progress, or contributor counts — an App Clip can't fetch
/// those without a backend, and inventing them would be fake.
struct AppClipFundraiser: View {
    let campaignId: String

    var body: some View {
        AppClipTeaser(
            icon: "heart.circle.fill",
            kind: "Fundraiser",
            reference: "Campaign \(campaignId)",
            message: "Open MTRX to see this campaign's live progress and contribute. 100% goes to the recipient — 0% platform fee.",
            actionTitle: "Get MTRX to Contribute"
        )
        .navigationTitle("Fundraiser")
    }
}
