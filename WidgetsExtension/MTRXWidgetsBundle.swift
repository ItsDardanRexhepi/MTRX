// WidgetsExtension/MTRXWidgetsBundle.swift
// MTRX Widgets — the extension's entry point.
//
// The four Home Screen widgets read their data from the App Group snapshot
// (group.com.opnmatrx.mtrx) that the app writes on foreground/wallet updates;
// with no snapshot they render their honest empty states. The Live Activity
// renders transaction progress started by the app's ActivityKitManager.

import SwiftUI
import WidgetKit

@main
struct MTRXWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PortfolioWidget()
        PositionsWidget()
        ContractsWidget()
        PaymentsWidget()
        MTRXLiveActivityWidget()
    }
}
