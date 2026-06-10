// HomeView.swift
// MTRX — Home tab: Trinity conversation space.
//
// The default tab. Hosts the Trinity conversation as the centerpiece
// of the app; the personal dashboard lives alongside in DashboardView
// (reachable via ExploreToggle).

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        AgentConversationView(userID: appState.currentUserID)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(WalletManager())
}
