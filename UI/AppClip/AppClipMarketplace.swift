import SwiftUI

/// App Clip preview for marketplace listings — item details, seller reputation, price
struct AppClipMarketplace: View {
    let listingId: String
    @State private var listing: AppClipMarketplaceListing?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let listing {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary).frame(height: 250)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(listing.title).font(.title2).bold()
                        Text(listing.description_).foregroundColor(.secondary)
                        HStack {
                            Text(listing.price).font(.title3).bold()
                            Spacer()
                            Label("\(listing.sellerRating)/5", systemImage: "star.fill").foregroundColor(.yellow)
                        }
                        Text("5% platform fee • 95% to seller").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Button(action: {}) {
                        Text("Get Full App to Purchase")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                } else {
                    ProgressView("Loading listing...")
                }
            }
        }
        .navigationTitle("Marketplace")
        .task { listing = AppClipMarketplaceListing(title: "Digital Art #\(listingId)", description_: "Verified NFT listing", price: "0.5 ETH", sellerRating: 4.8) }
    }
}

struct AppClipMarketplaceListing { let title: String; let description_: String; let price: String; let sellerRating: Double }
