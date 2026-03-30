// MultipeerManager.swift
// MTRX — Connectivity
//
// MultipeerConnectivity MCSession for peer-to-peer asset transfer without internet

import MultipeerConnectivity
import Foundation
import Combine
import CryptoKit

// MARK: - Peer Transfer Models

struct PeerTransferPayload: Codable {
    let id: UUID
    let type: TransferType
    let data: Data
    let timestamp: Date
    let senderWallet: String
    let signature: Data

    enum TransferType: String, Codable {
        case signedTransaction
        case contractProposal
        case contactExchange
        case portfolioShare
    }
}

enum MultipeerError: Error, LocalizedError {
    case notConnected
    case sessionUnavailable
    case encodingFailed
    case peerNotFound
    case transferFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "No peers connected"
        case .sessionUnavailable: return "Multipeer session unavailable"
        case .encodingFailed: return "Failed to encode transfer payload"
        case .peerNotFound: return "Specified peer not found"
        case .transferFailed(let err): return "Transfer failed: \(err.localizedDescription)"
        }
    }
}

// MARK: - MultipeerManager

final class MultipeerManager: NSObject, ObservableObject {

    static let shared = MultipeerManager()

    // MARK: - Published State

    @Published private(set) var connectedPeers: [MCPeerID] = []
    @Published private(set) var discoveredPeers: [DiscoveredPeer] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    @Published private(set) var lastReceivedPayload: PeerTransferPayload?

    struct DiscoveredPeer: Identifiable {
        let id: String
        let peerId: MCPeerID
        let walletPrefix: String?
        let discoveredAt: Date
    }

    // MARK: - Combine Subjects

    let dataReceivedSubject = PassthroughSubject<(PeerTransferPayload, MCPeerID), Never>()
    let connectionStateSubject = PassthroughSubject<(MCPeerID, MCSessionState), Never>()
    let errorSubject = PassthroughSubject<MultipeerError, Never>()

    // MARK: - Private Properties

    private let serviceType = "mtrx-p2p"
    private let myPeerId: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var invitationHandlers: [MCPeerID: (Bool, MCSession?) -> Void] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private override init() {
        myPeerId = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        setupSession()
    }

    private func setupSession() {
        let session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
    }

    // MARK: - Advertising

    func startAdvertising(walletAddress: String) {
        guard !isAdvertising else { return }
        let info: [String: String] = [
            "wallet": String(walletAddress.prefix(8)),
            "version": "2",
        ]
        let adv = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: info, serviceType: serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv
        isAdvertising = true
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
    }

    // MARK: - Browsing

    func startBrowsing() {
        guard !isBrowsing else { return }
        let br = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        br.delegate = self
        br.startBrowsingForPeers()
        browser = br
        isBrowsing = true
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        discoveredPeers.removeAll()
        isBrowsing = false
    }

    // MARK: - Connection

    func invitePeer(_ peer: MCPeerID, timeout: TimeInterval = 30) {
        guard let session = session else { return }
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: timeout)
    }

    func acceptInvitation(from peer: MCPeerID) {
        if let handler = invitationHandlers.removeValue(forKey: peer) {
            handler(true, session)
        }
    }

    func declineInvitation(from peer: MCPeerID) {
        if let handler = invitationHandlers.removeValue(forKey: peer) {
            handler(false, nil)
        }
    }

    // MARK: - Sending Data

    func send(_ payload: PeerTransferPayload, to peer: MCPeerID) throws {
        guard let session = session else { throw MultipeerError.sessionUnavailable }
        guard session.connectedPeers.contains(peer) else { throw MultipeerError.peerNotFound }
        let data = try encoder.encode(payload)
        try session.send(data, toPeers: [peer], with: .reliable)
    }

    func broadcast(_ payload: PeerTransferPayload) throws {
        guard let session = session, !session.connectedPeers.isEmpty else {
            throw MultipeerError.notConnected
        }
        let data = try encoder.encode(payload)
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    func sendRawData(_ data: Data, to peer: MCPeerID, reliable: Bool = true) throws {
        guard let session = session else { throw MultipeerError.sessionUnavailable }
        try session.send(data, toPeers: [peer], with: reliable ? .reliable : .unreliable)
    }

    func sendResource(at url: URL, named name: String, to peer: MCPeerID) -> Progress? {
        guard let session = session else { return nil }
        return session.sendResource(at: url, withName: name, toPeer: peer, withCompletionHandler: nil)
    }

    // MARK: - Disconnect

    func disconnect() {
        session?.disconnect()
        stopAdvertising()
        stopBrowsing()
        connectedPeers.removeAll()
    }

    deinit {
        disconnect()
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            connectedPeers = session.connectedPeers
            connectionStateSubject.send((peerID, state))
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? decoder.decode(PeerTransferPayload.self, from: data) else { return }
        Task { @MainActor in
            lastReceivedPayload = payload
            dataReceivedSubject.send((payload, peerID))
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandlers[peerID] = invitationHandler
        // Auto-accept for MTRX peers; in production use UI confirmation
        acceptInvitation(from: peerID)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            isAdvertising = false
            errorSubject.send(.transferFailed(underlying: error))
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard !discoveredPeers.contains(where: { $0.peerId == peerID }) else { return }
            let peer = DiscoveredPeer(
                id: peerID.displayName,
                peerId: peerID,
                walletPrefix: info?["wallet"],
                discoveredAt: Date()
            )
            discoveredPeers.append(peer)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            discoveredPeers.removeAll { $0.peerId == peerID }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            isBrowsing = false
            errorSubject.send(.transferFailed(underlying: error))
        }
    }
}
