// SharePlayManager.swift
// MTRX Apple Integration — Interaction
//
// SharePlay for multi-party contract review sessions via GroupActivities

import GroupActivities
import Foundation
import Combine

// MARK: - MTRX Group Activity

struct MTRXContractReviewActivity: GroupActivity {
    let contractId: String
    let contractTitle: String

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Review: \(contractTitle)"
        meta.subtitle = "MTRX Contract Review Session"
        meta.type = .generic
        return meta
    }
}

// MARK: - SharePlayManager

final class SharePlayManager: ObservableObject {

    static let shared = SharePlayManager()

    @Published private(set) var isSessionActive: Bool = false
    @Published private(set) var participants: Int = 0
    @Published private(set) var sessionId: String?

    private var groupSession: GroupSession<MTRXContractReviewActivity>?
    private var messenger: GroupSessionMessenger?
    private var cancellables = Set<AnyCancellable>()
    private var tasks = Set<Task<Void, Never>>()

    // MARK: - Start Session

    func startContractReview(contractId: String, title: String) async throws {
        let activity = MTRXContractReviewActivity(contractId: contractId, contractTitle: title)
        let activated = try await activity.activate()
        _ = activated

        for await session in MTRXContractReviewActivity.sessions() {
            configureSession(session)
            break
        }
    }

    // MARK: - Join Session

    func listenForSessions() {
        let task = Task {
            for await session in MTRXContractReviewActivity.sessions() {
                configureSession(session)
            }
        }
        tasks.insert(task)
    }

    // MARK: - Session Configuration

    private func configureSession(_ session: GroupSession<MTRXContractReviewActivity>) {
        groupSession = session
        messenger = GroupSessionMessenger(session: session)

        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .joined:
                    self?.isSessionActive = true
                    self?.sessionId = session.id.uuidString
                case .invalidated:
                    self?.isSessionActive = false
                    self?.sessionId = nil
                default:
                    break
                }
            }
            .store(in: &cancellables)

        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                self?.participants = participants.count
            }
            .store(in: &cancellables)

        session.join()
    }

    // MARK: - Messaging

    func sendContractAction(_ action: ContractReviewAction) async throws {
        guard let messenger = messenger else { return }
        try await messenger.send(action)
    }

    func receiveActions() -> AsyncStream<ContractReviewAction> {
        AsyncStream { continuation in
            guard let messenger = messenger else {
                continuation.finish()
                return
            }
            let task = Task {
                for await (action, _) in messenger.messages(of: ContractReviewAction.self) {
                    continuation.yield(action)
                }
            }
            tasks.insert(task)
        }
    }

    // MARK: - End Session

    func endSession() {
        groupSession?.end()
        groupSession = nil
        messenger = nil
        isSessionActive = false
        participants = 0
        sessionId = nil
        cancellables.removeAll()
    }
}

// MARK: - Contract Review Action

struct ContractReviewAction: Codable {
    let type: ActionType
    let contractId: String
    let senderName: String
    let payload: String?
    let timestamp: Date

    enum ActionType: String, Codable {
        case highlight, comment, approve, reject, suggest, scroll
    }
}
