import ManagedSettings
import FamilyControls
import DeviceActivity

/// Respect Screen Time limits — shield MTRX during restricted periods
@MainActor
final class ScreenTimeManager: ObservableObject {
    @Published var isRestricted = false
    private let center = AuthorizationCenter.shared
    private let store = ManagedSettingsStore()

    func checkAuthorization() async {
        do {
            try await center.requestAuthorization(for: .individual)
        } catch {
            isRestricted = true
        }
    }

    /// Check if the app is currently within a restricted Screen Time period
    func isWithinRestrictedPeriod() -> Bool { isRestricted }

    /// Defer non-urgent operations during restricted periods
    func shouldDeferOperation(_ urgency: OperationUrgency) -> Bool {
        guard isRestricted else { return false }
        switch urgency {
        case .critical: return false // liquidation warnings always go through
        case .high: return false // dispute deadlines always go through
        case .normal, .low: return true // defer during Screen Time
        }
    }

    enum OperationUrgency { case critical, high, normal, low }
}
