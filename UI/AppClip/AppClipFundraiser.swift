import SwiftUI

/// App Clip preview for fundraiser — goal, progress, deadline, contribute button
struct AppClipFundraiser: View {
    let campaignId: String
    @State private var campaign: FundraiserCampaign?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let campaign {
                    VStack(spacing: 8) {
                        Text(campaign.title).font(.title2).bold()
                        Text(campaign.description_).foregroundColor(.secondary)
                    }

                    VStack(spacing: 8) {
                        ProgressView(value: campaign.progress)
                            .tint(campaign.progress >= 1.0 ? .green : .accentColor)
                        HStack {
                            Text("\(campaign.raised) raised").bold()
                            Spacer()
                            Text("of \(campaign.goal)").foregroundColor(.secondary)
                        }
                        .font(.subheadline)
                        HStack {
                            Label("\(campaign.contributors) contributors", systemImage: "person.2")
                            Spacer()
                            Label(campaign.deadline, systemImage: "clock")
                        }
                        .font(.caption).foregroundColor(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)

                    Text("100% goes to recipient • 0% platform fee")
                        .font(.caption).foregroundColor(.green)

                    Button("Get Full App to Contribute") {}
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.accentColor).foregroundColor(.white).cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("Fundraiser")
        .task { campaign = FundraiserCampaign(title: "Community Project #\(campaignId)", description_: "Building something meaningful", raised: "2.5 ETH", goal: "10 ETH", progress: 0.25, contributors: 42, deadline: "Apr 30, 2026") }
    }
}

struct FundraiserCampaign { let title: String; let description_: String; let raised: String; let goal: String; let progress: Double; let contributors: Int; let deadline: String }
