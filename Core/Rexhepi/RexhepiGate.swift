// RexhepiGate.swift
// MTRX
//
// Runtime integration of the Unified Rexhepi Framework. Every
// consequential local action is routed through six scored gates before
// it processes, modeling the trajectory-selection objective
//   t* = argmax_{t in T_feasible} E_{P(t)}[U(t)]
// as: among the feasible ways to run an action, take the one that
// maximizes expected user value under the current on-device conditions.
//
// All scoring is local — hardware/network/battery state read on-device,
// nothing leaves the device.

import Foundation
import LocalAuthentication
#if canImport(UIKit)
import UIKit
#endif

/// The six gates, each scored 0…3.
struct RexhepiScores {
    var clarity: Int       // C — are the action's rules/endpoints testable here?
    var feasibility: Int   // F — can the hardware actually carry it out?
    var risk: Int          // R — on-device security blast radius
    var uncertainty: Int   // U — network/topology reliability
    var value: Int         // V — priority vs. battery/connectivity cost
    var omniversal: Int    // O — alignment with local node sovereignty/efficiency
}

/// What the validator decided the trajectory should do.
enum RexhepiOutcome: Equatable {
    case execute                 // run it now
    case probe                   // run it, but with retry/confirmation buffers (U high)
    case ask(String)             // need user clarification first (C low)
    case requireBiometric        // pause for Face ID / Touch ID (R == 3)
    case route(RexhepiRoute)     // run it over an alternate transport (F low)
    case defer_(String)          // defer low-value work under constraint (V low)
    case abort(String)           // do not run
}

enum RexhepiRoute: Equatable { case meshOutbox, constrainedLink }

/// One consequential action presented to the validator.
struct RexhepiRequest {
    enum Category { case payment, message, contract, identity, insurance, lowValueAutomation }
    let category: Category
    /// Caller-supplied stakes hint (e.g. USD value) used for R and V.
    let magnitude: Double
    /// True when the action is testable/complete on its own here.
    let isSelfContained: Bool
}

@MainActor
final class RexhepiGate: ObservableObject {

    static let shared = RexhepiGate()

    /// Elevated externally (e.g. by the watchdog) — forces R high.
    @Published var elevatedRisk = false

    private init() {}

    // MARK: - Scoring

    func score(_ request: RexhepiRequest) -> RexhepiScores {
        let net = NetworkPathMonitor.shared
        let battery = batteryLevel()
        let lowBattery = battery >= 0 && battery < 0.2

        // C — clarity
        let clarity = request.isSelfContained ? 3 : 1

        // F — feasibility: can the chosen transport carry it?
        let feasibility: Int = net.isOffline ? 1 : (net.isUltraConstrained ? 2 : 3)

        // R — risk: stakes + any external elevation
        var risk = 0
        switch request.category {
        case .payment, .contract: risk = request.magnitude >= 1000 ? 3 : (request.magnitude >= 100 ? 2 : 1)
        case .identity:           risk = 2
        case .insurance:          risk = request.magnitude >= 1000 ? 3 : 2
        case .message:            risk = 1
        case .lowValueAutomation: risk = 0
        }
        if elevatedRisk { risk = 3 }

        // U — uncertainty from network topology
        let uncertainty: Int = net.isOffline ? 3 : (net.isUltraConstrained ? 2 : (net.state == .constrained ? 1 : 0))

        // V — value vs. cost
        var value = request.category == .lowValueAutomation ? 1 : 3
        if lowBattery && request.category == .lowValueAutomation { value = 0 }

        // O — omniversal alignment: prefer trajectories that keep the
        // user sovereign and the local node efficient (offline-capable,
        // low-cost). Higher when we can serve it locally.
        let omniversal = net.isOffline ? 3 : 2

        return RexhepiScores(clarity: clarity, feasibility: feasibility, risk: risk,
                             uncertainty: uncertainty, value: value, omniversal: omniversal)
    }

    /// Evaluate the six gates in their canonical order and pick the
    /// trajectory. Hard rules first (clarity, feasibility, risk), then
    /// the soft modulators (uncertainty, value, omniversal).
    func evaluate(_ request: RexhepiRequest) -> RexhepiOutcome {
        let s = score(request)

        // C: if unclear, ask before doing anything.
        if s.clarity < 2 {
            return .ask("I need one detail before I run this safely.")
        }
        // F: if the hardware can't carry it, route to the offline path.
        if s.feasibility < 2 {
            return .route(.meshOutbox)
        }
        // R: highest risk pauses for biometric confirmation.
        if s.risk == 3 {
            return .requireBiometric
        }
        // V: defer low-value automation under constraint.
        if s.value == 0 {
            return .defer_("Deferred to protect battery / constrained link.")
        }
        // F partial: constrained link → compress + route.
        if s.feasibility == 2 {
            return .route(.constrainedLink)
        }
        // U: unreliable topology → run with retry/confirmation buffers.
        if s.uncertainty >= 2 {
            return .probe
        }
        // O leads the remaining feasible set: execute.
        return .execute
    }

    // MARK: - Biometric gate (R == 3)

    /// Local Face ID / Touch ID confirmation for the highest-risk gate.
    func confirmBiometric(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return await withCheckedContinuation { cont in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }

    // MARK: - Local hardware reads

    private func batteryLevel() -> Float {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryLevel
        #else
        return -1
        #endif
    }
}
