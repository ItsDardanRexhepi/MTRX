// GroupActivitySession.swift
// MTRX Apple Integration — Interaction
//
// GroupActivities coordination for synchronized multi-user experiences

import GroupActivities
import Foundation
import Combine

// MARK: - Portfolio Watch Activity

struct MTRXPortfolioWatchActivity: GroupActivity {
    let portfolioId: String

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Watch Portfolio Together"
        meta.subtitle = "Shared MTRX portfolio view"
        meta.type = .generic
        return meta
    }
}

// MARK: - DAO Voting Activity

struct MTRXDAOVotingActivity: GroupActivity {
    let proposalId: String
    let proposalTitle: String

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "DAO Vote: \(proposalTitle)"
        meta.subtitle = "Collaborative governance session"
        meta.type = .generic
        return meta
    }
}

// MARK: - GroupActivitySession Coordinator

final class GroupActivitySessionCoordinator: ObservableObject {

    static let shared = GroupActivitySessionCoordinator()

    @Published private(set) var activeSessionType: SessionType?
    @Published private(set) var participantCount: Int = 0
    @Published private(set) var isEligibleForGroupSession: Bool = false

    enum SessionType: String {
        case contractReview, portfolioWatch, daoVoting
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Eligibility

    func checkEligibility() async {
        // Check if GroupActivities is available
        let eligible = GroupStateObserver().isEligibleForGroupSession
        await MainActor.run {
            isEligibleForGroupSession = eligible
        }
    }

    // MARK: - Portfolio Watch

    func startPortfolioWatch(portfolioId: String) async throws {
        let activity = MTRXPortfolioWatchActivity(portfolioId: portfolioId)
        _ = try await activity.activate()
        await MainActor.run { activeSessionType = .portfolioWatch }
    }

    // MARK: - DAO Voting

    func startDAOVoting(proposalId: String, title: String) async throws {
        let activity = MTRXDAOVotingActivity(proposalId: proposalId, proposalTitle: title)
        _ = try await activity.activate()
        await MainActor.run { activeSessionType = .daoVoting }
    }

    // MARK: - Session State

    func endCurrentSession() {
        activeSessionType = nil
        participantCount = 0
    }
}

// MARK: - Synchronized State

struct SynchronizedContractState: Codable {
    let contractId: String
    let scrollPosition: Double
    let highlightedClause: String?
    let lastUpdatedBy: String
    let timestamp: Date
}

struct SynchronizedVoteState: Codable {
    let proposalId: String
    let votesFor: Int
    let votesAgainst: Int
    let votesAbstain: Int
    let lastVoter: String
    let timestamp: Date
}
