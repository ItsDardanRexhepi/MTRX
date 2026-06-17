import SwiftUI

/// App Clip teaser for a tokenized property. Shows only the token reference
/// from the invocation URL and routes to the full app. It does NOT fabricate an
/// ownership timeline, inspections, or transfers — an App Clip can't fetch the
/// on-chain history without a backend, and inventing it would be fake.
struct AppClipProperty: View {
    let tokenId: String

    var body: some View {
        AppClipTeaser(
            icon: "house.circle.fill",
            kind: "Property",
            reference: "Token \(tokenId)",
            message: "Open MTRX to view this property's full on-chain ownership history, inspections, and title status.",
            actionTitle: "Get MTRX for Full History"
        )
        .navigationTitle("Property")
    }
}
