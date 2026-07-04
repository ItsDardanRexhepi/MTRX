// Core/Networking/RealtimeClient.swift
// MTRX — Phase 6 realtime client
//
// Two live channels against the gateway, both derived from the single
// configured PendingCredentials.Backend.gatewayURL (no extra config slots):
//
//   • GatewayChatStream — WebSocket to /ws. Sends one chat frame, renders
//     {"type":"token"} frames incrementally, resolves on {"type":"done"}.
//     Any failure throws; the caller falls back to the REST path it uses
//     today. Nothing is ever fabricated mid-stream.
//
//   • FeedEventStream — SSE from /api/v1/events/stream (social.post events).
//     Long-lived with honest reconnect: exponential backoff, Last-Event-ID
//     replay on resume, and a published `isLive` that is true ONLY while a
//     healthy stream is attached — the UI never claims live when it isn't.
//
// Both are inert until PendingCredentials.isBackendConfigured.

import Foundation

// MARK: - URL derivation

enum GatewayRealtimeURL {
    /// wss://…/ws derived from the https gateway URL. Nil when unconfigured.
    static var chatSocket: URL? {
        guard PendingCredentials.isBackendConfigured else { return nil }
        var raw = PendingCredentials.effectiveGatewayURL
        if raw.hasSuffix("/") { raw.removeLast() }
        raw = raw.replacingOccurrences(of: "https://", with: "wss://")
        raw = raw.replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: raw + "/ws")
    }

    /// https://…/api/v1/events/stream filtered to the given event types.
    static func eventStream(types: [String]) -> URL? {
        guard PendingCredentials.isBackendConfigured else { return nil }
        var raw = PendingCredentials.effectiveGatewayURL
        if raw.hasSuffix("/") { raw.removeLast() }
        var components = URLComponents(string: raw + "/api/v1/events/stream")
        if !types.isEmpty {
            components?.queryItems = [URLQueryItem(name: "types",
                                                   value: types.joined(separator: ","))]
        }
        return components?.url
    }
}

// MARK: - Chat streaming (WebSocket)

enum GatewayChatStreamError: Error {
    case notConfigured
    case connectionFailed
    case serverError(String)
    case malformedFrame
    case timedOut
}

enum GatewayChatStream {

    /// Frames the gateway sends on /ws.
    private struct Frame: Decodable {
        let type: String
        let text: String?
        let error: String?
    }

    /// Stream one chat turn. `onToken` receives the ACCUMULATED text after
    /// each token frame (ready to assign to the live bubble). Returns the
    /// final full text on the done frame. Throws on any failure — the caller
    /// falls back to the REST path; no partial text is ever presented as a
    /// finished reply.
    @MainActor
    static func stream(
        message: String,
        agent: String,
        sessionId: String,
        context: String,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard let url = GatewayRealtimeURL.chatSocket else {
            throw GatewayChatStreamError.notConfigured
        }

        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let frame: [String: Any] = [
            "type": "chat",
            "message": message,
            "agent": agent,
            "session_id": sessionId,
            "context": context,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let json = String(data: data, encoding: .utf8) else {
            throw GatewayChatStreamError.malformedFrame
        }
        do {
            try await task.send(.string(json))
        } catch {
            throw GatewayChatStreamError.connectionFailed
        }

        var accumulated = ""
        let decoder = JSONDecoder()
        // A stalled socket must not hang the chat: 90s of silence → give up
        // and let the REST fallback answer. (Server heartbeats keep a healthy
        // socket well under this.)
        while true {
            let received = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message?.self) { group in
                group.addTask { try await task.receive() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 90 * 1_000_000_000)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let message = first else {
                    throw GatewayChatStreamError.timedOut
                }
                return message
            }

            guard case .string(let text) = received,
                  let parsed = try? decoder.decode(Frame.self, from: Data(text.utf8)) else {
                continue   // ignore non-JSON/ping frames, keep listening
            }
            switch parsed.type {
            case "token":
                accumulated += parsed.text ?? ""
                onToken(accumulated)
            case "done":
                return accumulated
            case "error":
                throw GatewayChatStreamError.serverError(parsed.error ?? "unknown")
            default:
                continue
            }
        }
    }
}

// MARK: - Feed events (SSE)

/// Long-lived SSE subscription with honest reconnect. `isLive` is true only
/// while a healthy stream is attached; on drop it flips false immediately and
/// the client backs off exponentially (1s → 60s cap), resuming with
/// Last-Event-ID so the broadcaster replays anything missed.
@MainActor
final class FeedEventStream: ObservableObject {

    @Published private(set) var isLive = false

    private var streamTask: Task<Void, Never>?
    private var lastEventId: String?
    private let types: [String]
    private let onEvent: @MainActor (String) -> Void

    /// `onEvent` receives the SSE event type each time a matching event
    /// arrives (the caller refetches its typed endpoint — event payloads are
    /// a refresh signal, never merged raw into UI state).
    init(types: [String], onEvent: @escaping @MainActor (String) -> Void) {
        self.types = types
        self.onEvent = onEvent
    }

    func start() {
        guard streamTask == nil, PendingCredentials.isBackendConfigured else { return }
        streamTask = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await self.attach()
                    attempt = 0   // healthy session ended (server restart) — quick retry
                } catch {
                    if Task.isCancelled { return }
                    print("FeedEventStream: stream dropped — \(error.localizedDescription); reconnecting")
                }
                self.isLive = false
                attempt += 1
                let backoff = min(60.0, pow(2.0, Double(min(attempt, 6))))
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isLive = false
    }

    private func attach() async throws {
        guard let url = GatewayRealtimeURL.eventStream(types: types) else {
            throw GatewayChatStreamError.notConfigured
        }
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let lastEventId {
            request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GatewayChatStreamError.connectionFailed
        }
        isLive = true

        var eventType = ""
        for try await line in bytes.lines {
            if Task.isCancelled { return }
            if line.hasPrefix("event:") {
                eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("id:") {
                lastEventId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.isEmpty {
                // Frame boundary — dispatch anything but the hello/keep-alive.
                if !eventType.isEmpty, eventType != "hello" {
                    onEvent(eventType)
                }
                eventType = ""
            }
            // data: lines are deliberately not merged into UI state — the
            // subscriber refetches its typed endpoint on dispatch.
        }
        // Stream ended without an error (server closed) — caller reconnects.
    }
}
