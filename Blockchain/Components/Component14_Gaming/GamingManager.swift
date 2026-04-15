// GamingManager.swift
// MTRX Blockchain - Components - Gaming (C14)
//
// Game registry, vetting pipeline, milestone-based funding,
// 80/20 revenue share (developer/platform), ERC-1155 game-asset management.

import Foundation
import Combine

// MARK: - Protocols

protocol GamingDelegate: AnyObject {
    func gaming(_ manager: GamingManager, gameRegistered game: GameRegistration)
    func gaming(_ manager: GamingManager, vettingAdvanced game: GameRegistration, stage: GamingVettingStage)
    func gaming(_ manager: GamingManager, milestoneFunded milestone: FundingMilestone)
    func gaming(_ manager: GamingManager, revenueDistributed share: RevenueShare)
    func gaming(_ manager: GamingManager, assetMinted asset: GameAssetERC1155)
}

// MARK: - Data Models

enum GameStatus: String, Codable, CaseIterable {
    case submitted, underReview, approved, rejected, live, suspended
}

enum GamingVettingStage: Int, Codable, CaseIterable {
    case technicalAudit = 0
    case contentReview = 1
    case complianceCheck = 2
    case communityFeedback = 3
    case finalApproval = 4

    var next: GamingVettingStage? {
        GamingVettingStage(rawValue: rawValue + 1)
    }
}

struct GameRegistration: Identifiable, Codable {
    let id: String
    let title: String
    let developerAddress: String
    let metadataURI: String
    let submissionTimestamp: Date
    var status: GameStatus
    var vettingStage: GamingVettingStage?
    var contractAddress: String?
}

struct FundingMilestone: Identifiable, Codable {
    let id: String
    let gameId: String
    let title: String
    let description: String
    let targetAmount: Double
    var fundedAmount: Double
    let deadline: Date
    var isCompleted: Bool
    var isVerified: Bool
    var proofURI: String?
}

struct RevenueShare: Identifiable, Codable {
    let id: String
    let gameId: String
    let totalRevenue: Double
    let developerShare: Double   // 80%
    let platformShare: Double    // 20%
    let periodStart: Date
    let periodEnd: Date
    var distributionTxHash: String?
}

struct GameAssetERC1155: Identifiable, Codable {
    let id: String
    let gameId: String
    let tokenId: String
    let name: String
    let metadataURI: String
    let totalSupply: UInt64
    var circulatingSupply: UInt64
    let isFungible: Bool
}

enum GamingError: Error, LocalizedError {
    case gameNotFound(String)
    case registrationFailed(String)
    case vettingNotInProgress
    case gameNotApproved
    case milestoneNotFound(String)
    case milestoneDeadlinePassed
    case insufficientFunding
    case assetMintFailed(String)
    case revenueDistributionFailed(String)
    case contractCallFailed(String)

    var errorDescription: String? {
        switch self {
        case .gameNotFound(let id): return "Game not found: \(id)"
        case .registrationFailed(let r): return "Registration failed: \(r)"
        case .vettingNotInProgress: return "Game is not currently in the vetting pipeline."
        case .gameNotApproved: return "Game has not been approved yet."
        case .milestoneNotFound(let id): return "Milestone not found: \(id)"
        case .milestoneDeadlinePassed: return "Milestone deadline has passed."
        case .insufficientFunding: return "Milestone target not yet reached."
        case .assetMintFailed(let r): return "Asset mint failed: \(r)"
        case .revenueDistributionFailed(let r): return "Revenue distribution failed: \(r)"
        case .contractCallFailed(let r): return "Contract call failed: \(r)"
        }
    }
}

// MARK: - GamingManager

final class GamingManager: ObservableObject {

    static let shared = GamingManager()

    // Revenue split constants
    static let developerSharePct: Double = 0.80
    static let platformSharePct: Double = 0.20
    static let erc1155InterfaceId = "0xd9b67a26"

    weak var delegate: GamingDelegate?

    @Published private(set) var games: [GameRegistration] = []
    @Published private(set) var milestones: [FundingMilestone] = []
    @Published private(set) var assets: [GameAssetERC1155] = []
    @Published private(set) var revenueHistory: [RevenueShare] = []
    @Published private(set) var isLoading = false

    private var gameStore: [String: GameRegistration] = [:]
    private var milestoneStore: [String: FundingMilestone] = [:]
    private var assetStore: [String: GameAssetERC1155] = [:]

    // MARK: - Game Registration

    func registerGame(title: String, developerAddress: String, metadataURI: String) async throws -> GameRegistration {
        let game = GameRegistration(
            id: UUID().uuidString,
            title: title,
            developerAddress: developerAddress,
            metadataURI: metadataURI,
            submissionTimestamp: Date(),
            status: .submitted,
            vettingStage: .technicalAudit,
            contractAddress: nil
        )

        gameStore[game.id] = game
        await MainActor.run {
            games.append(game)
        }
        delegate?.gaming(self, gameRegistered: game)
        return game
    }

    // MARK: - Vetting Pipeline

    /// Advance a game to the next vetting stage. When final approval is reached,
    /// status transitions to `.approved`.
    func advanceVetting(gameId: String) async throws -> GameRegistration {
        guard var game = gameStore[gameId] else {
            throw GamingError.gameNotFound(gameId)
        }
        guard let current = game.vettingStage else {
            throw GamingError.vettingNotInProgress
        }

        if let next = current.next {
            game.vettingStage = next
            game.status = .underReview
        } else {
            // Passed final approval
            game.vettingStage = nil
            game.status = .approved
        }

        gameStore[gameId] = game
        await updateGameInPublished(game)
        delegate?.gaming(self, vettingAdvanced: game, stage: current)
        return game
    }

    func rejectGame(gameId: String) async throws {
        guard var game = gameStore[gameId] else {
            throw GamingError.gameNotFound(gameId)
        }
        game.status = .rejected
        game.vettingStage = nil
        gameStore[gameId] = game
        await updateGameInPublished(game)
    }

    func setGameLive(gameId: String) async throws {
        guard var game = gameStore[gameId] else {
            throw GamingError.gameNotFound(gameId)
        }
        guard game.status == .approved else {
            throw GamingError.gameNotApproved
        }
        game.status = .live
        gameStore[gameId] = game
        await updateGameInPublished(game)
    }

    // MARK: - Milestone Funding

    func createMilestone(gameId: String, title: String, description: String, targetAmount: Double, deadline: Date) async throws -> FundingMilestone {
        guard gameStore[gameId] != nil else {
            throw GamingError.gameNotFound(gameId)
        }

        let milestone = FundingMilestone(
            id: UUID().uuidString,
            gameId: gameId,
            title: title,
            description: description,
            targetAmount: targetAmount,
            fundedAmount: 0,
            deadline: deadline,
            isCompleted: false,
            isVerified: false,
            proofURI: nil
        )

        milestoneStore[milestone.id] = milestone
        await MainActor.run { milestones.append(milestone) }
        return milestone
    }

    func fundMilestone(milestoneId: String, amount: Double) async throws -> FundingMilestone {
        guard var milestone = milestoneStore[milestoneId] else {
            throw GamingError.milestoneNotFound(milestoneId)
        }
        guard milestone.deadline > Date() else {
            throw GamingError.milestoneDeadlinePassed
        }

        milestone.fundedAmount += amount
        milestoneStore[milestoneId] = milestone
        await updateMilestoneInPublished(milestone)
        delegate?.gaming(self, milestoneFunded: milestone)
        return milestone
    }

    /// Verify milestone completion and release funds. Target must be met.
    func verifyAndReleaseMilestone(milestoneId: String, proofURI: String) async throws -> FundingMilestone {
        guard var milestone = milestoneStore[milestoneId] else {
            throw GamingError.milestoneNotFound(milestoneId)
        }
        guard milestone.fundedAmount >= milestone.targetAmount else {
            throw GamingError.insufficientFunding
        }

        milestone.isCompleted = true
        milestone.isVerified = true
        milestone.proofURI = proofURI
        milestoneStore[milestoneId] = milestone
        await updateMilestoneInPublished(milestone)
        return milestone
    }

    // MARK: - Revenue Share (80 / 20)

    /// Distribute revenue for a game: 80% to developer, 20% to platform.
    func distributeRevenue(gameId: String, totalRevenue: Double, periodStart: Date, periodEnd: Date) async throws -> RevenueShare {
        guard let game = gameStore[gameId], game.status == .live else {
            throw GamingError.gameNotFound(gameId)
        }

        let devShare = totalRevenue * Self.developerSharePct
        let platShare = totalRevenue * Self.platformSharePct

        let record = RevenueShare(
            id: UUID().uuidString,
            gameId: gameId,
            totalRevenue: totalRevenue,
            developerShare: devShare,
            platformShare: platShare,
            periodStart: periodStart,
            periodEnd: periodEnd,
            distributionTxHash: nil
        )

        await MainActor.run { revenueHistory.append(record) }
        delegate?.gaming(self, revenueDistributed: record)
        return record
    }

    // MARK: - ERC-1155 Game Asset Management

    func mintAsset(gameId: String, name: String, metadataURI: String, supply: UInt64, isFungible: Bool) async throws -> GameAssetERC1155 {
        guard gameStore[gameId] != nil else {
            throw GamingError.gameNotFound(gameId)
        }

        let asset = GameAssetERC1155(
            id: UUID().uuidString,
            gameId: gameId,
            tokenId: UUID().uuidString,
            name: name,
            metadataURI: metadataURI,
            totalSupply: supply,
            circulatingSupply: supply,
            isFungible: isFungible
        )

        assetStore[asset.id] = asset
        await MainActor.run { assets.append(asset) }
        delegate?.gaming(self, assetMinted: asset)
        return asset
    }

    func transferAsset(assetId: String, from: String, to: String, amount: UInt64) async throws {
        guard let asset = assetStore[assetId] else {
            throw GamingError.assetMintFailed("Asset not found: \(assetId)")
        }
        guard asset.circulatingSupply >= amount else {
            throw GamingError.assetMintFailed("Insufficient supply for transfer.")
        }
        // On-chain transfer would happen here via ERC-1155 safeTransferFrom
    }

    func burnAsset(assetId: String, amount: UInt64) async throws {
        guard var asset = assetStore[assetId] else {
            throw GamingError.assetMintFailed("Asset not found: \(assetId)")
        }
        guard asset.circulatingSupply >= amount else {
            throw GamingError.assetMintFailed("Burn amount exceeds supply.")
        }
        asset.circulatingSupply -= amount
        assetStore[assetId] = asset
        await updateAssetInPublished(asset)
    }

    func getAssetsForGame(gameId: String) -> [GameAssetERC1155] {
        assetStore.values.filter { $0.gameId == gameId }
    }

    // MARK: - Private Helpers

    @MainActor
    private func updateGameInPublished(_ game: GameRegistration) {
        if let idx = games.firstIndex(where: { $0.id == game.id }) {
            games[idx] = game
        }
    }

    @MainActor
    private func updateMilestoneInPublished(_ milestone: FundingMilestone) {
        if let idx = milestones.firstIndex(where: { $0.id == milestone.id }) {
            milestones[idx] = milestone
        }
    }

    @MainActor
    private func updateAssetInPublished(_ asset: GameAssetERC1155) {
        if let idx = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[idx] = asset
        }
    }
}
