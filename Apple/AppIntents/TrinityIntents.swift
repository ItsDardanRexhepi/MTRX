// TrinityIntents.swift
// MTRX Apple Integration — AppIntents
// All Trinity actions exposed as AppIntents for Shortcuts and Spotlight

import AppIntents

// MARK: - Ask Trinity Intent

struct AskTrinityIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Trinity"
    static var description = IntentDescription("Ask Trinity any question about your portfolio, DeFi, or blockchain")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question")
    var question: String

    @Parameter(title: "Persona", default: .trinity)
    var persona: TrinityPersona

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let response = try await TrinityQueryEngine.shared.ask(
            question: question,
            persona: persona
        )
        return .result(value: response)
    }
}

// MARK: - Send Payment Intent

struct SendPaymentAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Crypto Payment"
    static var description = IntentDescription("Send ETH or tokens to a recipient")

    @Parameter(title: "Recipient")
    var recipient: String

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Token", default: "ETH")
    var token: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$amount) \(\.$token) to \(\.$recipient)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let txHash = try await TrinityPaymentService.shared.send(
            amount: Decimal(amount),
            token: token,
            to: recipient
        )
        return .result(value: "Sent \(amount) \(token) to \(recipient). TX: \(txHash)")
    }
}

// MARK: - Check Gas Price Intent

struct CheckGasPriceIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Gas Price"
    static var description = IntentDescription("Get current Ethereum gas price estimate")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Network", default: .ethereum)
    var network: BlockchainNetwork

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let gasPrice = try await TrinityGasService.shared.currentPrice(network: network)
        return .result(value: "Current gas: \(gasPrice) gwei on \(network.rawValue)")
    }
}

// MARK: - Swap Tokens Intent

struct SwapTokensIntent: AppIntent {
    static var title: LocalizedStringResource = "Swap Tokens"
    static var description = IntentDescription("Execute a token swap on DEX")

    @Parameter(title: "From Token")
    var fromToken: String

    @Parameter(title: "To Token")
    var toToken: String

    @Parameter(title: "Amount")
    var amount: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Swap \(\.$amount) \(\.$fromToken) to \(\.$toToken)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try await TrinitySwapService.shared.swap(
            from: fromToken,
            to: toToken,
            amount: Decimal(amount)
        )
        return .result(value: result)
    }
}

// MARK: - Stake Tokens Intent

struct StakeTokensIntent: AppIntent {
    static var title: LocalizedStringResource = "Stake Tokens"
    static var description = IntentDescription("Stake tokens for yield")

    @Parameter(title: "Token")
    var token: String

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Protocol")
    var stakingProtocol: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try await TrinityStakingService.shared.stake(
            token: token,
            amount: Decimal(amount),
            protocol: stakingProtocol
        )
        return .result(value: result)
    }
}

// MARK: - Trinity Persona Enum

enum TrinityPersona: String, AppEnum {
    case trinity = "Trinity"
    case morpheus = "Morpheus"
    case oracle = "Oracle"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Persona"
    static var caseDisplayRepresentations: [TrinityPersona: DisplayRepresentation] = [
        .trinity: "Trinity",
        .morpheus: "Morpheus",
        .oracle: "Oracle"
    ]
}

// MARK: - Blockchain Network Enum

enum BlockchainNetwork: String, AppEnum {
    case ethereum = "Ethereum"
    case polygon = "Polygon"
    case arbitrum = "Arbitrum"
    case optimism = "Optimism"
    case base = "Base"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Network"
    static var caseDisplayRepresentations: [BlockchainNetwork: DisplayRepresentation] = [
        .ethereum: "Ethereum",
        .polygon: "Polygon",
        .arbitrum: "Arbitrum",
        .optimism: "Optimism",
        .base: "Base"
    ]
}

// MARK: - Service Stubs

final class TrinityQueryEngine {
    static let shared = TrinityQueryEngine()
    func ask(question: String, persona: TrinityPersona) async throws -> String {
        let online = await TrinitySiriSession.isOnline()
        return await TrinitySiriSession.shared.answer(question, online: online)
    }
}

final class TrinityPaymentService {
    static let shared = TrinityPaymentService()
    func send(amount: Decimal, token: String, to recipient: String) async throws -> String {
        return "0x" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

final class TrinityGasService {
    static let shared = TrinityGasService()
    func currentPrice(network: BlockchainNetwork) async throws -> Double {
        return 25.0
    }
}

final class TrinitySwapService {
    static let shared = TrinitySwapService()
    func swap(from: String, to: String, amount: Decimal) async throws -> String {
        return "Swap executed"
    }
}

final class TrinityStakingService {
    static let shared = TrinityStakingService()
    func stake(token: String, amount: Decimal, protocol: String) async throws -> String {
        return "Staking initiated"
    }
}
