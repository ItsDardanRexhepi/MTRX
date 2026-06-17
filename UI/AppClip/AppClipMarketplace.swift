import SwiftUI

/// App Clip teaser for a marketplace listing. Shows only the listing reference
/// from the invocation URL and routes to the full app. It does NOT fabricate a
/// title, price, image, or seller rating — an App Clip can't fetch those
/// without a backend, and inventing them would be fake.
struct AppClipMarketplace: View {
    let listingId: String

    var body: some View {
        AppClipTeaser(
            icon: "bag.circle.fill",
            kind: "Marketplace Listing",
            reference: "Listing \(listingId)",
            message: "Open MTRX to view this listing's details, verified seller, and price, and to purchase securely.",
            actionTitle: "Get MTRX to Purchase"
        )
        .navigationTitle("Marketplace")
    }
}
