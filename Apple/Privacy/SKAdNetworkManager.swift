import StoreKit

/// Privacy-preserving install attribution — no user-level tracking ever
final class SKAdNetworkManager {
    /// Register app install attribution without exposing user identity
    func registerAttribution() {
        SKAdNetwork.registerAppForAdNetworkAttribution()
    }

    /// Update postback conversion value for aggregated reporting only
    func updateConversionValue(_ value: Int) async throws {
        if #available(iOS 16.1, *) {
            // Fine + coarse conversion values, no user-level data
            try await SKAdNetwork.updatePostbackConversionValue(value, coarseValue: coarseValue(from: value))
        } else {
            try await SKAdNetwork.updatePostbackConversionValue(value)
        }
    }

    private func coarseValue(from fine: Int) -> SKAdNetwork.CoarseConversionValue {
        switch fine {
        case 0..<20: return .low
        case 20..<50: return .medium
        default: return .high
        }
    }
}
