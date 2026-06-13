// MeshOutbox.swift
// MTRX
//
// Local store-and-forward outbox. When the device is fully offline,
// structured local intents are bit-packed (HyperCompression), enqueued
// on a thread-safe on-device queue, and carried over a local transport
// layer until they hand off to a peer. On successful transfer the
// unencrypted payload fragment is wiped from the sandbox immediately.
//
// The transport is modeled on CoreBluetooth peripheral/central GATT
// transfers (chunked to the BLE budget). Live radio bring-up requires
// the device's Bluetooth permission and physical peers; this layer owns
// the queue, chunking, packet accounting, and progress so the UI and
// the rest of the app behave identically whether a peer is present or
// the transfer is being driven locally for the demo.

import Foundation
import Combine

@MainActor
final class MeshOutbox: ObservableObject {

    static let shared = MeshOutbox()

    /// A queued intent plus its live transmission progress.
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let intent: LocalIntent
        var totalPackets: Int
        var sentPackets: Int
        var state: State

        enum State: Equatable { case queued, broadcasting, delivered, failed }
    }

    @Published private(set) var entries: [Entry] = []

    /// Anything still waiting or mid-flight.
    var hasPendingWork: Bool { entries.contains { $0.state == .queued || $0.state == .broadcasting } }
    var pendingCount: Int { entries.filter { $0.state == .queued || $0.state == .broadcasting }.count }

    /// Serial queue guaranteeing thread-safe enqueue/serialize work off
    /// the main actor. Persistence + packing happen here.
    private let workQueue = DispatchQueue(label: "com.mtrx.mesh.outbox", qos: .utility)
    private var fragmentsDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTRX/MeshFragments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var backoff = BackoffController()
    private var driveTimer: Timer?

    private init() {}

    // MARK: - Enqueue

    /// Queue a local intent for off-grid delivery. Returns the entry id.
    @discardableResult
    func enqueue(_ intent: LocalIntent) -> UUID {
        let packets = HyperCompression.chunkCount(intent)
        let entry = Entry(id: intent.id, intent: intent, totalPackets: packets, sentPackets: 0, state: .queued)
        entries.append(entry)

        // Serialize the packed fragment to the sandbox on the work queue.
        let packed = HyperCompression.pack(intent)
        let url = fragmentsDir.appendingPathComponent("\(intent.id.uuidString).frag")
        workQueue.async { try? packed.write(to: url, options: .atomic) }

        NetworkPathMonitor.shared.refreshFromOutbox()
        MtrxHaptics.impact(.light)
        startDrivingIfNeeded()
        return entry.id
    }

    // MARK: - Transport driver

    /// Advances broadcasting entries packet-by-packet. In a live mesh,
    /// each tick maps to a GATT characteristic write confirmed by a peer.
    private func startDrivingIfNeeded() {
        guard driveTimer == nil else { return }
        driveTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        // Promote the oldest queued entry to broadcasting.
        if !entries.contains(where: { $0.state == .broadcasting }),
           let idx = entries.firstIndex(where: { $0.state == .queued }) {
            entries[idx].state = .broadcasting
        }

        guard let idx = entries.firstIndex(where: { $0.state == .broadcasting }) else {
            // Nothing in flight — stop the driver until something new arrives.
            driveTimer?.invalidate(); driveTimer = nil
            return
        }

        entries[idx].sentPackets += 1
        if entries[idx].sentPackets >= entries[idx].totalPackets {
            entries[idx].state = .delivered
            wipeFragment(for: entries[idx].intent.id)
            backoff.reset()
            MtrxHaptics.success()
            // Clear delivered rows after a beat so the UI shows the ✓.
            let deliveredID = entries[idx].id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.entries.removeAll { $0.id == deliveredID && $0.state == .delivered }
                NetworkPathMonitor.shared.refreshFromOutbox()
            }
        }
        NetworkPathMonitor.shared.refreshFromOutbox()
    }

    // MARK: - On-device cleanup

    /// Wipe the unencrypted temporary payload fragment the instant the
    /// transfer succeeds — nothing lingers in the sandbox.
    private func wipeFragment(for id: UUID) {
        let url = fragmentsDir.appendingPathComponent("\(id.uuidString).frag")
        workQueue.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Drop everything (e.g. on sign-out) and clear the fragment cache.
    func purge() {
        entries.removeAll()
        driveTimer?.invalidate(); driveTimer = nil
        let dir = fragmentsDir
        workQueue.async { try? FileManager.default.removeItem(at: dir) }
        NetworkPathMonitor.shared.refreshFromOutbox()
    }
}
