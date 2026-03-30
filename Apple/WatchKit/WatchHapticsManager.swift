import WatchKit

/// Custom haptic feedback patterns on Apple Watch per event type
final class WatchHapticsManager {
    static let shared = WatchHapticsManager()
    private let device = WKInterfaceDevice.current()

    /// Gentle tap for transaction confirmations
    func confirmation() { device.play(.success) }

    /// Strong alert for liquidation warnings
    func liquidationWarning() {
        device.play(.failure)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.device.play(.failure) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.device.play(.retry) }
    }

    /// Rhythmic pulse for staking rewards received
    func stakingReward() {
        device.play(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.device.play(.directionUp) }
    }

    /// Subtle notification for incoming messages
    func messageReceived() { device.play(.notification) }

    /// Urgent repeated pulse for dispute deadlines
    func disputeDeadline() {
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.4) { self.device.play(.retry) }
        }
    }

    /// Click feedback for UI navigation
    func click() { device.play(.click) }

    /// Direction up for portfolio gains
    func portfolioUp() { device.play(.directionUp) }

    /// Direction down for portfolio losses
    func portfolioDown() { device.play(.directionDown) }
}
