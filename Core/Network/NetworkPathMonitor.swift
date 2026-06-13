// NetworkPathMonitor.swift
// MTRX
//
// Live transport-state engine built on the public Network framework.
// Drives the global topology indicator and the app's failover behavior:
// when the link goes ultra-constrained (carrier direct-to-cell / heavily
// throttled), non-essential transfers are restricted and payloads are
// hyper-compressed. Fully local — the monitor never reports anywhere.

import Foundation
import Network
import Combine

/// What the link can currently do, mapped to the three UI states.
enum TransportState: Equatable {
    case unconstrained        // Wi-Fi / strong cellular — full app behavior
    case mesh                 // no internet, local BLE outbox is carrying traffic
    case constrained          // ultra-constrained / satellite — hyper-compression on

    var title: String {
        switch self {
        case .unconstrained: return "Online"
        case .mesh: return "Mesh"
        case .constrained: return "Constrained"
        }
    }
}

@MainActor
final class NetworkPathMonitor: ObservableObject {

    static let shared = NetworkPathMonitor()

    /// Published topology state — read by the indicator and failover code.
    @Published private(set) var state: TransportState = .unconstrained
    /// True only when the OS reports an ultra-constrained path.
    @Published private(set) var isUltraConstrained = false
    /// True when there is no usable internet path at all.
    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mtrx.network.path", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Compute everything off the main thread; publish on main.
            let satisfied = path.status == .satisfied
            let constrained = path.isConstrained          // Low Data Mode
            var ultra = false
            if #available(iOS 26.0, *) {
                ultra = path.isUltraConstrained            // carrier ultra-constrained
            }
            Task { @MainActor [weak self] in
                self?.apply(satisfied: satisfied, constrained: constrained, ultra: ultra)
            }
        }
        monitor.start(queue: queue)
    }

    private func apply(satisfied: Bool, constrained: Bool, ultra: Bool) {
        isUltraConstrained = ultra
        isOffline = !satisfied

        // Mesh wins when there is no internet but the local outbox is active.
        if !satisfied, MeshOutbox.shared.hasPendingWork {
            state = .mesh
        } else if ultra || (constrained && satisfied) {
            state = .constrained
        } else if !satisfied {
            // No internet and nothing queued yet — surface as mesh-ready so
            // the user understands the app has switched to local transport.
            state = .mesh
        } else {
            state = .unconstrained
        }
    }

    /// Called by the outbox when its queue changes so the indicator can
    /// flip to/from mesh mode without waiting for a path update.
    func refreshFromOutbox() {
        apply(satisfied: !isOffline, constrained: false, ultra: isUltraConstrained)
    }

    /// Should the app restrict non-essential data transfers right now?
    var shouldRestrictNonEssential: Bool { isUltraConstrained || isOffline }
}
