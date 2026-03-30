import NetworkExtension

/// Optional VPN privacy layer — user-initiated only
@MainActor
final class NetworkExtensionManager: ObservableObject {
    @Published var isConnected = false
    @Published var status: NEVPNStatus = .disconnected

    private var manager: NETunnelProviderManager?

    func loadConfiguration() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        manager = managers.first ?? NETunnelProviderManager()
        status = manager?.connection.status ?? .disconnected
        isConnected = status == .connected
        NotificationCenter.default.addObserver(self, selector: #selector(statusChanged), name: .NEVPNStatusDidChange, object: nil)
    }

    func connect() throws {
        guard let manager else { return }
        try manager.connection.startVPNTunnel()
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    @objc private func statusChanged() {
        status = manager?.connection.status ?? .disconnected
        isConnected = status == .connected
    }
}
