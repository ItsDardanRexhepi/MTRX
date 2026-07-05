// HeartbeatWatchdog.swift
// MTRX
//
// A LOCAL, user-controlled canary timer (a "dead-man's switch" the user
// owns). The user periodically checks in to reset a 72-hour countdown.
// If the countdown lapses, the app surfaces that its safeguard window
// has elapsed and elevates the Rexhepi Risk gate so sensitive actions
// require fresh biometric confirmation.
//
// Privacy / scope note (deliberate): this build does NOT poll external
// legal/regulatory databases and does NOT auto-contact any third party.
// Automated outbound messaging to entities derived from public filings
// is intentionally omitted. The watchdog is a local status surface only;
// the on-chain "publish keys → open-source on expiry" behavior is a
// concept owned by a real contract outside this app, not wired here.

import Foundation
import Combine

@MainActor
final class HeartbeatWatchdog: ObservableObject {

    static let shared = HeartbeatWatchdog()

    /// 72-hour window, matching the contract's immutable countdown.
    static let window: TimeInterval = 72 * 60 * 60

    @Published private(set) var lastHeartbeat: Date
    @Published private(set) var now: Date = Date()

    private let storeKey = "com.mtrx.watchdog.lastHeartbeat"
    private var ticker: Timer?

    private init() {
        let stored = UserDefaults.standard.double(forKey: storeKey)
        lastHeartbeat = stored > 0 ? Date(timeIntervalSince1970: stored) : Date()
        if stored == 0 { persist() }
        // Light minute-resolution ticker for the countdown UI.
        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    /// Seconds left before the window lapses (clamped at 0).
    var remaining: TimeInterval { max(0, Self.window - now.timeIntervalSince(lastHeartbeat)) }
    var progress: Double { min(1, max(0, remaining / Self.window)) }
    var hasLapsed: Bool { remaining <= 0 }

    /// "Push the heartbeat" — resets the countdown. In production this is
    /// the secure on-chain transaction that resets the contract timer.
    func pushHeartbeat() {
        lastHeartbeat = Date()
        persist()
        refresh()
        RexhepiGate.shared.elevatedRisk = false
        MtrxHaptics.success()
    }

    private func refresh() {
        now = Date()
        if hasLapsed {
            // Window elapsed — harden the device locally.
            RexhepiGate.shared.elevatedRisk = true
        }
    }

    private func persist() {
        UserDefaults.standard.set(lastHeartbeat.timeIntervalSince1970, forKey: storeKey)
    }

    /// Human-readable countdown, e.g. "71h 24m".
    var countdownText: String {
        let total = Int(remaining)
        let h = total / 3600
        let m = (total % 3600) / 60
        return hasLapsed ? "Lapsed" : "\(h)h \(m)m"
    }
}
