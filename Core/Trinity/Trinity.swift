//
//  Trinity.swift
//  MTRX — Trinity
//
//  Primary intelligence layer. Main conversation interface for MTRX.
//

import Foundation
import Combine

// MARK: - Trinity

/// Primary intelligence layer that serves as the main user-facing interface.
/// Coordinates context assembly, memory, inference, and voice to deliver responses.
@MainActor
final class Trinity: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var lastResponse: TrinityResponse?
    @Published private(set) var conversationHistory: [ConversationTurn] = []
    @Published private(set) var currentState: TrinityState = .idle

    // MARK: - Dependencies

    private let context: TrinityContext
    private let memory: TrinityMemoryStore
    private let inference: TrinityInference
    private let voice: TrinityVoice
    private let scoringEngine: RexhepiEngine
    private let decisionLog: DecisionLog

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Intent Classification Patterns

    private static let actionKeywords: Set<String> = [
        "send", "transfer", "swap", "bridge", "deploy", "create", "mint",
        "stake", "unstake", "delegate", "vote", "propose", "buy", "sell",
        "list", "auction", "claim", "withdraw", "deposit", "borrow", "lend",
        "repay", "liquidate", "approve", "revoke", "sign", "execute",
        "launch", "fund", "donate", "insure", "cancel", "remove"
    ]

    private static let queryKeywords: Set<String> = [
        "what", "how", "why", "when", "where", "who", "which", "explain",
        "show", "tell", "describe", "check", "look up", "find", "search",
        "compare", "analyze", "status", "info", "details", "history",
        "is it", "can i", "should i", "price", "rate", "fee", "cost",
        "estimate", "calculate", "forecast", "predict"
    ]

    private static let portfolioKeywords: Set<String> = [
        "balance", "portfolio", "holdings", "performance", "allocation",
        "profit", "loss", "pnl", "p&l", "net worth", "assets", "positions",
        "returns", "yield", "apy", "apr", "rewards", "earnings", "value",
        "total", "summary", "overview", "breakdown"
    ]

    private static let settingsKeywords: Set<String> = [
        "settings", "configure", "preferences", "change language", "theme",
        "notifications", "alerts", "security", "password", "biometric",
        "two-factor", "2fa", "backup", "export", "import", "reset",
        "default", "customize", "toggle", "enable", "disable", "turn on",
        "turn off", "update profile", "account"
    ]

    private static let alertResponseKeywords: Set<String> = [
        "approve it", "reject it", "accept", "decline", "confirm",
        "yes do it", "no don't", "go ahead", "cancel that", "stop",
        "proceed", "abort", "dismiss", "acknowledge", "got it", "ok do it"
    ]

    private static let moneyActionKeywords: Set<String> = [
        "send", "transfer", "swap", "bridge", "deploy", "stake", "unstake",
        "buy", "sell", "borrow", "lend", "repay", "liquidate", "withdraw",
        "deposit", "mint", "donate", "fund", "auction", "sign", "execute",
        "approve", "claim"
    ]

    private static let urgencyKeywords: Set<String> = [
        "urgent", "now", "asap", "immediately", "right now", "hurry",
        "quickly", "fast", "emergency", "critical", "time sensitive"
    ]

    // MARK: - Entity Extraction Patterns

    /// Matches dollar amounts like "$100", "$1,500.50", "$0.01"
    private static let dollarAmountPattern = try! NSRegularExpression(
        pattern: #"\$[\d,]+(?:\.\d{1,2})?"#, options: []
    )

    /// Matches crypto amounts like "0.5 ETH", "100 USDC", "1.25 BTC"
    private static let cryptoAmountPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(ETH|BTC|USDC|USDT|SOL|MATIC|AVAX|DAI|WETH|WBTC|ARB|OP|LINK|UNI|AAVE|MKR|SNX|CRV|COMP|MTRX|APE|DOGE|SHIB|ADA|DOT|XRP|BNB|ATOM)"#,
        options: .caseInsensitive
    )

    /// Matches wallet addresses (0x... format)
    private static let walletAddressPattern = try! NSRegularExpression(
        pattern: #"0x[a-fA-F0-9]{40}"#, options: []
    )

    /// Matches ENS names like "vitalik.eth"
    private static let ensPattern = try! NSRegularExpression(
        pattern: #"[\w-]+\.eth"#, options: .caseInsensitive
    )

    /// Matches percentage values like "50%", "7.5%"
    private static let percentagePattern = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*%"#, options: []
    )

    // MARK: - State

    enum TrinityState: Sendable {
        case idle
        case listening
        case thinking
        case responding
        case error(String)
    }

    // MARK: - Initialization

    init(
        context: TrinityContext = TrinityContext(),
        memory: TrinityMemoryStore = TrinityMemoryStore(),
        inference: TrinityInference = TrinityInference(),
        voice: TrinityVoice = TrinityVoice(),
        scoringEngine: RexhepiEngine = RexhepiEngine(),
        decisionLog: DecisionLog = DecisionLog()
    ) {
        self.context = context
        self.memory = memory
        self.inference = inference
        self.voice = voice
        self.scoringEngine = scoringEngine
        self.decisionLog = decisionLog
    }

    // MARK: - Primary Interface

    /// Respond to a user message. This is the main entry point for conversation.
    /// - Parameter message: The user's input message.
    /// - Returns: Trinity's response.
    func respond(to message: String) async throws -> TrinityResponse {
        currentState = .thinking
        isProcessing = true
        defer {
            isProcessing = false
            currentState = .idle
        }

        // 1. Assemble full context
        let userContext = await context.assembleContext()

        // 2. Query memory for relevant history
        let relevantMemory = await memory.queryRelevant(for: message)

        // 3. Process the intent
        let intent = try await processIntent(message: message, context: userContext, memory: relevantMemory)

        // 4. Run through scoring engine if the intent involves a decision
        var outcome: Outcome?
        if intent.requiresDecision {
            let request = DecisionRequest(
                description: intent.description,
                context: intent.decisionContext,
                timeSensitivity: intent.timeSensitivity
            )
            outcome = try await scoringEngine.runPipeline(request)
        }

        // 5. Generate response via inference
        let response = try await think(
            intent: intent,
            context: userContext,
            memory: relevantMemory,
            outcome: outcome
        )

        // 6. Store in memory
        await memory.store(TrinityMemoryEntry(
            content: message,
            response: response.text,
            intent: intent.description,
            timestamp: Date()
        ))

        // 7. Record conversation turn
        let turn = ConversationTurn(
            userMessage: message,
            response: response,
            intent: intent,
            timestamp: Date()
        )
        conversationHistory.append(turn)

        lastResponse = response
        return response
    }

    // MARK: - Intent Processing

    /// Process the user's message to determine intent.
    /// Uses keyword matching, pattern detection, and entity extraction to classify
    /// the user's intent and pull out actionable information.
    /// - Parameters:
    ///   - message: The raw user message.
    ///   - context: The assembled user context.
    ///   - memory: Relevant memory entries.
    /// - Returns: The processed intent.
    func processIntent(
        message: String,
        context: UserContext,
        memory: [TrinityMemoryEntry]
    ) async throws -> TrinityIntent {
        let lower = message.lowercased()
        let words = Set(lower.split(separator: " ").map { String($0) })
        let nsMessage = message as NSString
        let fullRange = NSRange(location: 0, length: nsMessage.length)

        // --- Entity extraction ---

        var entities: [String: String] = [:]

        // Extract dollar amounts
        let dollarMatches = Self.dollarAmountPattern.matches(in: message, options: [], range: fullRange)
        if let first = dollarMatches.first {
            let amount = nsMessage.substring(with: first.range)
            entities["amount"] = amount
            entities["currency"] = "USD"
        }

        // Extract crypto amounts
        let cryptoMatches = Self.cryptoAmountPattern.matches(in: message, options: [], range: fullRange)
        if let first = cryptoMatches.first, first.numberOfRanges >= 3 {
            let amount = nsMessage.substring(with: first.range(at: 1))
            let symbol = nsMessage.substring(with: first.range(at: 2)).uppercased()
            entities["amount"] = amount
            entities["asset"] = symbol
            entities["currency"] = symbol
        }

        // Extract wallet addresses
        let walletMatches = Self.walletAddressPattern.matches(in: message, options: [], range: fullRange)
        if let first = walletMatches.first {
            entities["walletAddress"] = nsMessage.substring(with: first.range)
        }

        // Extract ENS names
        let ensMatches = Self.ensPattern.matches(in: message, options: [], range: fullRange)
        if let first = ensMatches.first {
            entities["ensName"] = nsMessage.substring(with: first.range)
        }

        // Extract percentage values
        let percentMatches = Self.percentagePattern.matches(in: message, options: [], range: fullRange)
        if let first = percentMatches.first, first.numberOfRanges >= 2 {
            entities["percentage"] = nsMessage.substring(with: first.range(at: 1))
        }

        // Extract asset names mentioned without amounts
        let knownAssets = ["bitcoin", "ethereum", "solana", "polygon", "avalanche", "arbitrum",
                          "optimism", "chainlink", "uniswap", "aave", "maker", "compound"]
        for asset in knownAssets where lower.contains(asset) {
            if entities["asset"] == nil {
                entities["asset"] = asset.capitalized
            }
        }

        // --- Intent classification ---

        var category: IntentCategory = .conversation
        var confidence: Double = 0.5
        var matchCount = 0

        // Check alert response first (highest priority when user is responding to a prompt)
        let alertResponseScore = Self.alertResponseKeywords.filter { lower.contains($0) }.count
        if alertResponseScore > 0 {
            category = .alertResponse
            confidence = min(0.7 + Double(alertResponseScore) * 0.1, 0.95)
            matchCount = alertResponseScore
        }

        // Portfolio queries
        let portfolioScore = Self.portfolioKeywords.filter { lower.contains($0) }.count
        if portfolioScore > matchCount {
            category = .portfolio
            confidence = min(0.6 + Double(portfolioScore) * 0.1, 0.95)
            matchCount = portfolioScore
        }

        // Settings
        let settingsScore = Self.settingsKeywords.filter { lower.contains($0) }.count
        if settingsScore > matchCount {
            category = .settings
            confidence = min(0.6 + Double(settingsScore) * 0.1, 0.95)
            matchCount = settingsScore
        }

        // Action vs query — check actions first since they are more specific
        let actionScore = Self.actionKeywords.filter { words.contains($0) || lower.contains($0) }.count
        let queryScore = Self.queryKeywords.filter { lower.contains($0) }.count

        if actionScore > 0 && actionScore >= queryScore && actionScore > matchCount {
            category = .action
            confidence = min(0.6 + Double(actionScore) * 0.1, 0.95)
            matchCount = actionScore
        } else if queryScore > matchCount {
            category = .query
            confidence = min(0.5 + Double(queryScore) * 0.1, 0.90)
            matchCount = queryScore
        }

        // If entities were extracted but no strong category match, boost confidence
        if !entities.isEmpty && confidence < 0.6 {
            confidence = 0.65
        }

        // Boost confidence if memory contains similar previous interactions
        if !memory.isEmpty {
            let memoryBoost = min(Double(memory.prefix(5).count) * 0.02, 0.1)
            confidence = min(confidence + memoryBoost, 0.98)
        }

        // --- Requires decision? ---
        // Actions involving money, contracts, or deployments require decision pipeline
        let requiresDecision: Bool
        if category == .action {
            let hasMoneyAction = Self.moneyActionKeywords.contains { lower.contains($0) }
            let hasAmount = entities["amount"] != nil
            let hasContract = lower.contains("contract") || lower.contains("deploy")
            requiresDecision = hasMoneyAction && (hasAmount || hasContract)
        } else {
            requiresDecision = false
        }

        // --- Time sensitivity ---
        let timeSensitivity: TimeSensitivity
        let urgencyScore = Self.urgencyKeywords.filter { lower.contains($0) }.count
        if urgencyScore >= 2 {
            timeSensitivity = .high
        } else if urgencyScore == 1 {
            timeSensitivity = .high
        } else if lower.contains("soon") || lower.contains("today") || lower.contains("tonight") {
            timeSensitivity = .medium
        } else {
            timeSensitivity = category == .alertResponse ? .high : .medium
        }

        // --- Build decision context ---
        var decisionContext: [String: Any] = [:]
        if requiresDecision {
            decisionContext["category"] = category.rawValue
            decisionContext["entities"] = entities
            decisionContext["originalMessage"] = message
            if let portfolioState = context.portfolioState {
                decisionContext["portfolioValue"] = portfolioState.totalValue
            }
        }

        let intent = TrinityIntent(
            description: message,
            category: category,
            entities: entities,
            requiresDecision: requiresDecision,
            timeSensitivity: timeSensitivity,
            decisionContext: decisionContext,
            confidence: confidence
        )

        return intent
    }

    // MARK: - Thinking / Response Generation

    /// Generate a response by combining intent, context, memory, and optional outcome.
    /// Attempts to call the backend API first, falling back to local response generation.
    /// - Parameters:
    ///   - intent: The processed user intent.
    ///   - context: The current user context.
    ///   - memory: Relevant memory entries.
    ///   - outcome: Optional scoring engine outcome.
    /// - Returns: The generated response.
    func think(
        intent: TrinityIntent,
        context: UserContext,
        memory: [TrinityMemoryEntry],
        outcome: Outcome?
    ) async throws -> TrinityResponse {
        currentState = .thinking

        // Build the prompt from intent + context + memory
        let prompt = buildPrompt(intent: intent, context: context, memory: memory, outcome: outcome)

        // Attempt API call to backend
        var responseText: String
        var fromAPI = false

        do {
            let apiResponse = try await MTRXAPIClient.shared.sendAgentMessage(
                agent: "trinity",
                message: intent.description,
                context: prompt,
                conversationHistory: memory.map { ["role": "user", "content": $0.content, "response": $0.response] }
            )
            responseText = apiResponse.text
            fromAPI = true
        } catch {
            // Fall back to local response generation
            responseText = generateLocalResponse(intent: intent, context: context, outcome: outcome)
        }

        // Build suggested actions based on intent category
        let suggestedActions = buildSuggestedActions(for: intent, outcome: outcome)

        // Include outcome context if present
        if let outcome = outcome {
            responseText = incorporateOutcome(outcome, into: responseText)
        }

        var metadata: [String: String] = [
            "source": fromAPI ? "api" : "local",
            "intentCategory": intent.category.rawValue,
            "confidence": String(format: "%.2f", intent.confidence)
        ]
        if let asset = intent.entities["asset"] {
            metadata["asset"] = asset
        }
        if let amount = intent.entities["amount"] {
            metadata["amount"] = amount
        }

        let response = TrinityResponse(
            text: responseText,
            confidence: intent.confidence,
            suggestedActions: suggestedActions,
            outcome: outcome,
            metadata: metadata
        )

        currentState = .responding
        return response
    }

    // MARK: - Prompt Construction

    /// Build a structured prompt from intent, context, memory, and outcome.
    private func buildPrompt(
        intent: TrinityIntent,
        context: UserContext,
        memory: [TrinityMemoryEntry],
        outcome: Outcome?
    ) -> String {
        var parts: [String] = []

        // System context
        parts.append("You are Trinity, the primary AI assistant for MTRX — a decentralized super-app.")
        parts.append("Respond naturally, helpfully, and with awareness of the user's full context.")

        // Time context
        let timeCtx = context.timeContext
        parts.append("Current time: \(timeCtx.currentTime), Market: \(timeCtx.marketStatus.rawValue), Business hours: \(timeCtx.isBusinessHours)")

        // Portfolio context
        if let portfolio = context.portfolioState {
            parts.append("Portfolio: $\(String(format: "%.2f", portfolio.totalValue)) total, \(String(format: "%+.2f%%", portfolio.dailyChangePercent)) today")
            if !portfolio.alerts.isEmpty {
                parts.append("Active alerts: \(portfolio.alerts.map { $0.message }.joined(separator: "; "))")
            }
        }

        // Intent
        parts.append("User intent: [\(intent.category.rawValue)] \"\(intent.description)\"")
        if !intent.entities.isEmpty {
            let entityStr = intent.entities.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            parts.append("Extracted entities: \(entityStr)")
        }

        // Relevant memory (last 5 interactions)
        if !memory.isEmpty {
            parts.append("Recent relevant interactions:")
            for entry in memory.prefix(5) {
                parts.append("  - User: \(entry.content) -> Response: \(entry.response)")
            }
        }

        // Outcome from scoring engine
        if let outcome = outcome {
            switch outcome {
            case .execute(let ctx):
                parts.append("Scoring engine: EXECUTE approved. \(ctx.summary)")
            case .probe(let questions):
                parts.append("Scoring engine: PROBE needed. Questions: \(questions.map { $0.text }.joined(separator: "; "))")
            case .ask(let prompt, let options):
                parts.append("Scoring engine: ASK user. Prompt: \(prompt), Options: \(options.joined(separator: ", "))")
            case .defer_(let reason, _):
                parts.append("Scoring engine: DEFER. Reason: \(reason)")
            case .abort(let reason, let violations):
                parts.append("Scoring engine: ABORT. Reason: \(reason). Violations: \(violations.joined(separator: ", "))")
            }
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Local Response Generation

    /// Generate a response locally when the API is unavailable.
    private func generateLocalResponse(
        intent: TrinityIntent,
        context: UserContext,
        outcome: Outcome?
    ) -> String {
        let lower = intent.description.lowercased()

        switch intent.category {
        case .action:
            return generateActionResponse(lower: lower, entities: intent.entities)
        case .query:
            return generateQueryResponse(lower: lower, entities: intent.entities, context: context)
        case .portfolio:
            return generatePortfolioResponse(lower: lower, context: context)
        case .settings:
            return generateSettingsResponse(lower: lower)
        case .alertResponse:
            return "Understood. I've processed your response and will take the appropriate action. You'll receive a confirmation once complete."
        case .conversation:
            return generateConversationResponse(lower: lower)
        }
    }

    // MARK: - 30-Component Conversational Flows

    /// Every action the user can take on MTRX maps to one of these 30 runtime
    /// components. The keyword lists below are deliberately written in plain
    /// English so that non-technical users can trigger the right wizard by
    /// saying "I want to sell my cat picture", "get me some insurance for
    /// this trip", "set up a recurring payment to my brother", etc.
    ///
    /// The detector walks the list in priority order and returns the first
    /// component whose keywords match the user's message. Money-action verbs
    /// like "buy", "send" are intentionally low-priority so that a phrase
    /// like "buy an NFT" is classified as NFT (3) instead of generic
    /// payments (17).
    private static let componentKeywords: [(id: Int, keywords: [String])] = [
        // Concept-first components (highest priority — these override verb matches)
        (3,  ["nft", "nfts", "collectible", "collectable", "erc721", "erc-721", "jpeg", "art piece", "digital art"]),
        (4,  ["rwa", "real world asset", "real-world asset", "tokenize property", "tokenise property", "real estate", "tokenize a house", "tokenise a house", "commodity token", "gold bar", "treasury bill"]),
        (5,  ["decentralized identity", "decentralised identity", "did", "self sovereign", "self-sovereign", "kyc", "verify myself", "prove who i am"]),
        (8,  ["attestation", "attest", "eas", "sign a statement", "verifiable credential", "vc"]),
        (9,  ["agent identity", "ai agent", "my agent", "autonomous agent", "robot identity"]),
        (10, ["agentic payment", "agent payment", "agent-to-agent", "autonomous payment", "ai pays", "agent pays"]),
        (11, ["oracle", "price feed", "data feed", "chainlink feed", "weather data", "sports data", "off-chain data"]),
        (12, ["supply chain", "provenance", "track shipment", "track my shipment", "track product", "where is my package", "batch number"]),
        (13, ["insurance", "insure", "coverage", "cover my", "policy", "file a claim", "travel insurance", "renter", "flight delay"]),
        (14, ["gaming", "tournament", "play to earn", "play-to-earn", "in-game", "video game", "leaderboard", "game asset"]),
        (15, ["intellectual property", "ip rights", "trademark", "copyright", "patent", "license my work", "protect my art", "register my song"]),
        (18, ["security token", "tokenized stock", "tokenised stock", "equity token", "bond token", "ipo", "regulation d", "reg d"]),
        (22, ["fundraiser", "fundraising", "crowdfund", "campaign", "milestone release", "donation drive", "raise money", "kickstart"]),
        (23, ["loyalty", "loyalty points", "points program", "tier", "silver tier", "gold tier", "platinum tier"]),
        (25, ["cashback", "rebate", "cash back", "cash-back"]),
        (26, ["brand reward", "partner reward", "merchant reward", "coffee shop reward", "store reward"]),
        (27, ["subscription", "subscribe", "recurring", "monthly plan", "yearly plan", "renewal", "cancel subscription"]),
        (28, ["social", "post something", "social feed", "follow someone", "message someone", "encrypted chat", "social graph"]),
        (29, ["privacy", "private transfer", "private send", "zero knowledge", "zero-knowledge", "zk", "hide the amount", "anonymous"]),
        (30, ["dispute", "arbitration", "resolve a dispute", "counterparty", "refund request", "they didn't deliver"]),
        (20, ["dashboard", "overview", "give me a summary", "my numbers", "kpi", "metric", "stats"]),
        (6,  ["dao", "join a dao", "create a dao", "dao proposal"]),
        (19, ["governance", "vote on proposal", "proposal", "delegate my vote", "cast a vote"]),
        (16, ["stake", "staking", "validator", "unstake", "staking reward"]),
        (7,  ["stablecoin", "mint stablecoin", "usdc", "usdt", "dai", "pegged", "peg"]),
        (2,  ["lending", "defi loan", "borrow against", "supply to aave", "supply to compound", "yield farm", "earn yield"]),
        (21, ["swap", "dex", "trade tokens", "exchange tokens", "liquidity pool", "amm"]),
        (24, ["marketplace", "list for sale", "auction", "sell it", "list it", "bid on"]),
        (17, ["send money", "send payment", "pay", "wire", "remittance"]),
        (1,  ["smart contract", "deploy contract", "contract template", "escrow contract", "multisig"]),
    ]

    /// Map a component ID back to a short plain-English label Trinity uses in
    /// response text ("your NFT", "your stablecoin", etc.).
    private static func componentLabel(_ id: Int) -> String {
        switch id {
        case 1: return "smart contract"
        case 2: return "DeFi position"
        case 3: return "NFT"
        case 4: return "real-world asset"
        case 5: return "digital identity"
        case 6: return "DAO"
        case 7: return "stablecoin"
        case 8: return "attestation"
        case 9: return "AI agent identity"
        case 10: return "agentic payment"
        case 11: return "oracle feed"
        case 12: return "supply-chain record"
        case 13: return "insurance policy"
        case 14: return "gaming asset"
        case 15: return "IP rights entry"
        case 16: return "staking position"
        case 17: return "payment"
        case 18: return "security token"
        case 19: return "governance vote"
        case 20: return "dashboard"
        case 21: return "swap"
        case 22: return "fundraising campaign"
        case 23: return "loyalty rewards"
        case 24: return "marketplace listing"
        case 25: return "cashback claim"
        case 26: return "brand reward"
        case 27: return "subscription"
        case 28: return "social post"
        case 29: return "private transfer"
        case 30: return "dispute"
        default: return "action"
        }
    }

    /// Detect which of the 30 components the user's message refers to, if any.
    /// The detector uses `componentKeywords` in priority order, so the first
    /// match wins. Returns nil if no component is recognised — the caller
    /// falls back to a generic "tell me more" prompt so Trinity never just
    /// stares silently at the user.
    private func detectComponent(lower: String) -> Int? {
        for (id, keywords) in Self.componentKeywords {
            for kw in keywords where lower.contains(kw) {
                return id
            }
        }
        return nil
    }

    /// Plain-English guided wizard for each of the 30 components. These are
    /// deliberately chatty and use everyday language rather than protocol
    /// jargon so that first-time users can follow along without reading a
    /// DeFi glossary. Each wizard:
    ///
    /// * names the action in one sentence
    /// * lists what Trinity needs from the user
    /// * explains the consequences in plain English
    /// * ends with a yes/no confirmation prompt
    ///
    /// The wizards substitute extracted entities (amount, asset, recipient)
    /// when available so the user sees their own numbers echoed back instead
    /// of boilerplate placeholders.
    private func componentFlow(component: Int, lower: String, entities: [String: String]) -> String {
        let amount = entities["amount"]
        let asset = entities["asset"]
        let recipient = entities["ensName"] ?? entities["walletAddress"]
        let amountPhrase = amount.map { "\($0)" } ?? "the amount you choose"
        let assetPhrase = asset.map { "of \($0)" } ?? ""

        switch component {
        case 1: // Smart Contracts
            return """
            I can deploy a smart contract for you. This is a permanent on-chain action, so let's do it carefully.

            Here's what I need from you:
              1. What should the contract do? (hold money in escrow, release funds on a date, require multiple signatures, something custom)
              2. Which network? (Base is cheapest and fastest, Ethereum mainnet is the most established)
              3. Do you want to start from one of our pre-audited templates, or do you have your own code?

            I'll run a safety check on the code and show you the full deployment cost before anything goes live. Ready to begin — which of the three questions above can you answer first?
            """

        case 2: // DeFi Lending
            if lower.contains("borrow") {
                return """
                You want to borrow against what you already own — that's a loan where your crypto stays as collateral. Here's the deal in plain English:

                  • You lock up some of your holdings (like ETH)
                  • You receive a loan in a stablecoin (like USDC) up to about 50–75% of the locked value
                  • You pay interest over time, and you can repay whenever you want
                  • If the market drops hard, your collateral can be sold to cover the loan — that's called liquidation

                To get you the best rate, tell me: what do you want to borrow, how much, and what can you put up as collateral?
                """
            }
            return """
            You'd like to earn yield on your crypto by lending it out \(assetPhrase). Here's what happens in plain English:

              • Your tokens sit in a lending pool
              • Other people borrow from that pool and pay interest
              • You earn a share of that interest automatically, usually between 2% and 8% APY
              • You can pull your money out whenever you want

            I'll scan the top lending protocols (Aave, Compound, Morpho) for the safest rate and show you the numbers side by side. Which asset do you want to lend?
            """

        case 3: // NFT
            if lower.contains("mint") || lower.contains("create") {
                return """
                Minting an NFT means registering a piece of digital content — an image, video, song, or 3D model — on the blockchain as something you uniquely own.

                To mint yours, I just need:
                  1. The file itself (you can attach it here)
                  2. A name and a sentence or two describing it
                  3. Whether it's a one-of-a-kind piece or a small edition (say, 10 copies)
                  4. The resale royalty you want — that's a cut you get every time it's sold later. Most artists pick between 5% and 10%

                I'll show you the gas fee before we hit the button, and once minted you can list it for sale in the marketplace. Ready to upload?
                """
            }
            if lower.contains("buy") {
                return """
                Happy to help you buy an NFT. Do you already have the listing link or the contract + token ID, or would you like me to browse trending collections with you first? I'll show the asking price, the price history, and whether the collection has been verified before you commit anything.
                """
            }
            if lower.contains("sell") || lower.contains("list") {
                return """
                To list your NFT for sale, tell me:
                  • Which NFT (you can pick from your wallet or paste the link)
                  • Fixed price or auction?
                  • What price (or starting bid)
                  • How long the listing should run

                I'll handle the on-chain listing and ping you the moment someone makes an offer.
                """
            }
            return "I can help with NFTs — do you want to mint a new one, buy one, or list one of yours for sale?"

        case 4: // RWA
            return """
            Tokenising a real-world asset turns something physical — a piece of real estate, a gold bar, an invoice, a car — into digital shares you can own, trade, or use as collateral.

            Before I start, I'll need:
              1. What's the asset? (address for property, serial number for gold, contract number for an invoice)
              2. Proof of ownership (title deed, receipt, certificate)
              3. Who's authorised to verify it? (your lawyer, an appraiser, a notary)
              4. How many tokens you want to split it into

            This is a regulated area, so I'll walk you through the legal paperwork step by step. Is the asset you're tokenising property, a commodity, or something else?
            """

        case 5: // Identity
            return """
            A decentralised identity (DID) is a secure digital ID that belongs only to you — no company can delete it or lock you out. You can use it to prove things about yourself (age, citizenship, license) without handing over a photo of your passport every time.

            I can:
              • Create a new DID for you (takes about 30 seconds)
              • Add verifiable credentials (driver's licence, university degree, etc.)
              • Show you which apps are asking to read it

            Would you like me to create a DID now, or add a credential to an existing one?
            """

        case 6: // DAO
            return """
            A DAO is a group that makes decisions together on-chain — think of it as a club, a co-op, or even a mini company where every member has a vote.

            Tell me which you'd like to do:
              • Join a DAO (I'll look up membership requirements)
              • Create a new DAO (I'll walk you through naming it, setting voting rules, and inviting members)
              • See what DAOs you're already a member of and their active proposals

            Which sounds right?
            """

        case 7: // Stablecoin
            return """
            You'd like to mint a stablecoin — that means locking up collateral (like ETH) and receiving a stable-value token (like USDC-style) against it.

            Here's how it works in plain English:
              • You deposit, say, $150 worth of ETH
              • You can mint up to $100 of stablecoin (the extra buffer is a safety cushion)
              • You pay a small interest rate on the amount you mint
              • If ETH drops too much, some of your collateral gets sold to keep things safe

            How much stablecoin do you want to mint, and what will you use as collateral?
            """

        case 8: // Attestation
            return """
            An attestation is a signed statement — you (or someone you trust) asserting that something is true: "Alice is over 18", "this wallet belongs to my company", "Bob finished the course".

            I just need to know:
              1. What's the statement?
              2. Who is it about? (a wallet address or your own)
              3. Should anyone be able to see it, or only people you share it with?

            It takes a few seconds and a tiny gas fee. Want to write one now?
            """

        case 9: // Agent Identity
            return """
            I can set up an identity for an AI agent — useful if you want an automated program to act on your behalf (for example, to rebalance your portfolio while you sleep).

            To register one I need:
              • A name for the agent
              • What it's allowed to do (spending limit, asset whitelist, time window)
              • Your confirmation, because this agent will be able to sign transactions under those limits

            Every action the agent takes stays in your decision log and can be revoked instantly. Shall we start by naming it?
            """

        case 10: // Agentic Payments
            return """
            An agentic payment is a transaction an AI agent executes on your behalf — for example, paying a subscription, tipping a content creator, or settling with another agent.

            For this one I need:
              • Which agent should send it (yours, or one you've authorised)
              • How much, and to whom
              • What it's for (so it shows up clearly in your history)

            I'll double-check the spending stays inside the limits you set for that agent before it goes through.
            """

        case 11: // Oracle
            return """
            Oracles are how a smart contract learns about the outside world — stock prices, weather, sports scores, whatever you need.

            Tell me what data you want and I'll:
              • Find the right feed (Chainlink, Pyth, RedStone, or a custom source)
              • Pull the latest value right now
              • Optionally wire it into one of your contracts so it updates automatically

            What data do you need a feed for?
            """

        case 12: // Supply Chain
            return """
            I can record a supply-chain event on-chain — a permanent, tamper-proof log of where a product is, who handled it, and when.

            To log an event I need:
              1. The product ID or batch number
              2. What happened (shipped, received, inspected, stored)
              3. Where it happened (address or GPS)
              4. Optionally, a photo for evidence

            It's especially useful for food, pharma, and luxury goods where provenance matters. What product are we logging?
            """

        case 13: // Insurance
            return """
            MTRX has several insurance products — tell me which one fits:

              • **Smart-contract cover** — pays out if a protocol you use gets hacked
              • **DeFi position cover** — protects against liquidation or impermanent loss
              • **Travel cover** — flight delays, lost baggage, trip cancellation
              • **Rental cover** — for short-term stays
              • **Parametric cover** — pays automatically based on weather data (useful for farmers and events)

            If you've already got a policy and want to file a claim, just say "file a claim" and tell me what happened — I'll handle the paperwork.
            """

        case 14: // Gaming
            return """
            The MTRX gaming layer lets you:
              • Play games where in-game items (skins, weapons, land) are actual NFTs you own
              • Join tournaments with prize pools paid out on-chain
              • Move items between compatible games
              • Track your stats and achievements across titles

            What would you like to do — browse games, enter a tournament, or check the value of an in-game item you already own?
            """

        case 15: // IP Rights
            return """
            I can register your intellectual property on-chain so you've got a permanent, timestamped record of authorship — useful for art, music, writing, photography, designs, even inventions.

            Just tell me:
              1. What's the work? (attach or describe it)
              2. What rights are you claiming? (full copyright, Creative Commons, patent application, trademark)
              3. Do you want to make it licensable — i.e. let others pay you to use it?

            Once registered you can license, transfer, or enforce it through the dispute system if someone copies it.
            """

        case 16: // Staking
            if lower.contains("unstake") {
                return """
                Got it — you want to unstake \(amountPhrase) \(assetPhrase). A few things to know before we do this:

                  • There's an unbonding period (usually a few days) during which your tokens are frozen and don't earn rewards
                  • You'll still see the tokens in your wallet once unbonding finishes
                  • You can cancel while the request is in flight if you change your mind

                Want me to check the exact unbonding time for your validator and proceed?
                """
            }
            return """
            Staking means locking up your tokens to help secure a network — in return, the network pays you rewards, usually 3% to 10% a year.

            A few things to know:
              • Your tokens are locked for an unbonding period (a few days to a few weeks depending on the network)
              • Rewards get paid out automatically, you don't have to claim them manually
              • If a validator misbehaves, a small percentage can be slashed — I'll only recommend validators with a spotless history

            Want me to show you the top-performing validators for \(asset ?? "your asset")?
            """

        case 17: // Payments
            let who = recipient ?? "the recipient"
            return """
            Let's set up a payment. Here's what I have so far:

              • Amount: \(amountPhrase) \(assetPhrase)
              • To: \(who)
              • Fee: I'll calculate this at current network rates before you confirm

            Before I send it I'll show you the exact total including fees. Can you confirm the recipient's address (or ENS name) is correct? That's the one thing I can't undo if it's wrong.
            """

        case 18: // Securities
            return """
            Security tokens are digital versions of regulated investments — shares in a company, bonds, or fund units. Because they're regulated, there are rules about who can buy them, what disclosures you need, and where they can be traded.

            If you want to issue one, I need to know:
              1. What does the token represent? (equity, debt, fund unit)
              2. Which jurisdiction's rules apply?
              3. Who's allowed to hold it? (accredited investors only, or open)
              4. How many tokens and what's each worth?

            If you want to buy one, tell me which offering and I'll verify you meet the eligibility requirements first.
            """

        case 19: // Governance
            if lower.contains("delegate") {
                return """
                Delegating means handing your voting power to someone you trust who will vote on your behalf — great if you care about a protocol but don't want to track every proposal yourself.

                Tell me which token's voting power you want to delegate, and I'll show you the top delegates, their voting history, and how aligned they are with what you usually support.
                """
            }
            return """
            I'll help you vote on a governance proposal. I can:
              • Show you the active proposals for any protocol you hold tokens in
              • Translate each proposal into plain English so you actually know what you're voting on
              • Show you how whales and delegates are voting
              • Cast your vote on-chain

            Which protocol's proposals do you want to look at?
            """

        case 20: // Dashboard
            return """
            I'll pull up your dashboard — a single view of your portfolio, recent activity, active positions, pending transactions, upcoming subscription renewals, governance votes you haven't cast yet, and any alerts. Give me a second to assemble it.
            """

        case 21: // DEX / Swap
            return """
            Swapping means trading one token for another without going through a centralised exchange. Here's what I'll do for you:

              • Compare rates across every major DEX (Uniswap, Curve, Balancer, 1inch)
              • Show you the exact amount you'll receive after fees and slippage
              • Split the swap across multiple pools if that gets you more output
              • Protect you from sandwich attacks with a safe slippage setting

            What are you swapping, and how much?
            """

        case 22: // Fundraising
            if lower.contains("donate") {
                return """
                Happy to help you donate. Do you have a specific campaign in mind, or would you like me to show you trending campaigns by cause (disaster relief, open-source, climate, animals)? Every donation is tracked on-chain and the recipient can only pull funds as they hit verified milestones.
                """
            }
            return """
            Let's set up a fundraiser. Here's what I need:

              1. A title and a short story — why are you raising money?
              2. The goal amount
              3. Milestones — break the goal into 2–5 chunks, each with a condition. Donors love this because their money only releases as you hit real progress
              4. A deadline

            All funds sit in an on-chain escrow until each milestone is verified. Ready to tell me the title?
            """

        case 23: // Loyalty
            return """
            Loyalty programs on MTRX track your points on-chain, so they can't be revoked or expire secretly. I can:
              • Show your current points balance across every program you're enrolled in
              • Redeem points for rewards
              • Move points between compatible programs
              • Check what tier you're in and how close you are to the next one

            Which of those would you like to do?
            """

        case 24: // Marketplace
            return """
            The marketplace is where you can buy, sell, or auction anything — NFTs, tokens, real-world asset shares, physical items with on-chain provenance.

            If you're listing, tell me:
              • What's the item?
              • Fixed price or auction?
              • Price (or starting bid and reserve)
              • How long should it run?

            If you're buying, just paste the listing link or tell me what you're hunting for — I'll search.
            """

        case 25: // Cashback
            return """
            I can pull up your cashback wallet — every qualifying purchase you've made through MTRX generates cashback that accrues here. I can:
              • Show your pending and claimable balance
              • Redeem it into any asset you like (stablecoins are most common)
              • Set up auto-redeem so cashback converts to USDC on the 1st of every month

            What would you like to do?
            """

        case 26: // Brand Rewards
            return """
            Brand rewards are merchant-specific points you earn from partner brands. Tell me which brand and I'll:
              • Show your balance and the rewards catalogue
              • Redeem points for a specific reward
              • Link a new brand to your account so future purchases count

            Which brand are we working with?
            """

        case 27: // Subscriptions
            if lower.contains("cancel") {
                return """
                I can cancel a subscription for you. Which one — I'll pull up your active subscriptions so you can pick. Cancellation is instant on-chain; you'll keep access until the end of the current billing period.
                """
            }
            return """
            Let's set up a subscription. I need:
              1. What you're subscribing to (a service, a creator, a DAO membership)
              2. Which plan (monthly, annual)
              3. Which asset you want to pay with (USDC is the most common for recurring payments because its price doesn't swing)
              4. Whether to auto-renew

            You can cancel any time with one tap. Which service is this for?
            """

        case 28: // Social
            if lower.contains("post") {
                return """
                What do you want to post? I can:
                  • Post plain text to your on-chain social feed
                  • Attach an image, video, or audio clip
                  • Tag other users (they'll get a notification)
                  • Gate the post so only your followers, or token holders, can see it

                Once posted it lives on-chain and can't be quietly edited or deleted by anyone but you.
                """
            }
            if lower.contains("message") {
                return """
                Messages on MTRX are end-to-end encrypted — only you and the recipient can read them. Who do you want to message? You can use a wallet address, an ENS name, or their username.
                """
            }
            return "I can help with social — do you want to post something, message someone, follow an account, or manage your followers?"

        case 29: // Privacy
            return """
            A private transfer hides the amount and the recipient from public view on the blockchain. It still settles on-chain, but observers only see that *some* transaction happened, not the details.

            A few things to know in plain English:
              • The money goes into a privacy pool and comes out on the other side, untraceable
              • The fees are a bit higher than a regular transfer
              • You can still prove the transfer happened to anyone you want (for taxes, for compliance) using a zero-knowledge receipt

            How much do you want to send privately, and to whom?
            """

        case 30: // Disputes
            return """
            Sorry you're dealing with a dispute — I can help. The MTRX dispute system uses neutral arbitrators who review the evidence on-chain and issue a binding decision.

            To open a dispute I need:
              1. The other party's wallet address
              2. A short description of what went wrong
              3. Evidence — screenshots, transaction hashes, messages, anything that backs your story

            Once filed, the other side has 7 days to respond. If they don't, the dispute is decided in your favour by default. Want to start filing?
            """

        default:
            return "I'll help you with that. Could you give me a little more detail so I can pick the right wizard?"
        }
    }

    /// Generate an action response. Routes through `detectComponent` so every
    /// message that mentions one of the 30 runtime components gets the
    /// matching plain-English wizard; falls back to a generic-but-still-
    /// friendly prompt otherwise.
    private func generateActionResponse(lower: String, entities: [String: String]) -> String {
        if let component = detectComponent(lower: lower) {
            return componentFlow(component: component, lower: lower, entities: entities)
        }

        // No specific component detected — generic action acknowledgment
        // that still asks a useful clarifying question instead of stalling.
        let amount = entities["amount"] ?? "the amount"
        let asset = entities["asset"] ?? "your asset"
        if lower.contains("send") || lower.contains("transfer") || lower.contains("pay") {
            return componentFlow(component: 17, lower: lower, entities: entities)
        }
        if lower.contains("buy") || lower.contains("sell") {
            return componentFlow(component: 24, lower: lower, entities: entities)
        }
        return """
        I can help you with that. To make sure I take the safest path, tell me:

          • Which asset? (for example \(asset))
          • How much? (for example \(amount))
          • And a little bit about what you're trying to achieve

        Once I know that, I'll walk you through it step by step and confirm before anything touches the blockchain.
        """
    }

    private func generateQueryResponse(lower: String, entities: [String: String], context: UserContext) -> String {
        if lower.contains("price") || lower.contains("rate") {
            let asset = entities["asset"] ?? "that asset"
            return "Let me fetch the current price data for \(asset). I'll include the 24h change, trading volume, market cap, and price chart. One moment."
        }
        if lower.contains("gas") || lower.contains("fee") {
            return "Current network gas fees:\n\n- Ethereum: checking current gwei levels\n- Base/Optimism/Arbitrum: typically 10-100x cheaper than L1\n- Solana: approximately $0.00025 per transaction\n\nI can recommend the optimal time to transact based on historical gas patterns if you'd like to wait for lower fees."
        }
        if lower.contains("explain") || lower.contains("what is") || lower.contains("what are") {
            return "Great question. Let me break that down for you in clear terms, covering what it is, how it works, the risks involved, and how it fits into the MTRX ecosystem. What specific aspect would you like me to focus on?"
        }
        if lower.contains("compare") || lower.contains("vs") || lower.contains("versus") {
            return "I'll run a detailed comparison for you, covering fees, performance, security audits, TVL, user reviews, and any relevant metrics. Give me a moment to compile the data."
        }
        if lower.contains("history") || lower.contains("transaction") {
            return "I'll pull up your transaction history. I can filter by:\n\n- Time period (today, this week, this month, custom range)\n- Transaction type (sends, receives, swaps, contract interactions)\n- Asset or network\n\nWhat range would you like to see?"
        }
        if lower.contains("contract") || lower.contains("smart contract") {
            return "I can help you understand smart contracts. I can:\n\n- Explain what a specific contract does in plain language\n- Check if a contract has been audited\n- Show the contract's interaction history\n- Analyze potential risks before you interact\n\nPaste a contract address or tell me what you'd like to know."
        }
        if lower.contains("nft") {
            return "I can help with NFTs. I can show you:\n\n- Floor prices and recent sales for collections\n- Rarity analysis for specific tokens\n- Your NFT portfolio value and history\n- Trending collections and minting opportunities\n\nWhat would you like to explore?"
        }
        if lower.contains("defi") || lower.contains("yield") || lower.contains("apy") {
            return "I'll scan DeFi protocols for the best opportunities. I track:\n\n- Lending/borrowing rates across major protocols\n- Liquidity pool APYs with impermanent loss estimates\n- Yield farming opportunities sorted by risk-adjusted returns\n- Protocol safety scores based on audit status and TVL\n\nWant me to find the best yields for a specific asset?"
        }
        if lower.contains("identity") || lower.contains("did") || lower.contains("credential") {
            return "MTRX uses decentralized identity (DID) for secure, self-sovereign verification. You can:\n\n- Create and manage verifiable credentials\n- Prove identity attributes without revealing personal data\n- Connect credentials across platforms\n- Revoke or update credentials at any time\n\nWould you like to set up or manage your identity?"
        }
        if lower.contains("privacy") || lower.contains("zero-knowledge") || lower.contains("zk") {
            return "MTRX leverages zero-knowledge proofs for privacy-preserving transactions. You can:\n\n- Send private transactions that hide amounts\n- Prove asset ownership without revealing balances\n- Generate compliance proofs without exposing data\n- Use commitment schemes for sealed-bid auctions\n\nWhat privacy feature are you interested in?"
        }
        if lower.contains("gaming") || lower.contains("play") || lower.contains("game") {
            return "The MTRX gaming ecosystem includes:\n\n- Play-to-earn games with real asset rewards\n- Tournaments with prize pools\n- In-game asset ownership as NFTs\n- Cross-game asset interoperability\n- Leaderboards and achievement systems\n\nWould you like to browse available games or check your gaming stats?"
        }
        if lower.contains("marketplace") || lower.contains("rwa") || lower.contains("real world") {
            return "The MTRX marketplace supports:\n\n- Digital assets (NFTs, tokens, digital collectibles)\n- Real World Assets (tokenized property, commodities, securities)\n- Peer-to-peer trading with escrow protection\n- Auction mechanisms (English, Dutch, sealed-bid)\n\nWould you like to browse listings or learn about listing your own assets?"
        }
        if lower.contains("social") || lower.contains("message") || lower.contains("post") {
            return "MTRX social features include:\n\n- Encrypted peer-to-peer messaging\n- Community posts with on-chain verification\n- Token-gated groups and channels\n- Social trading and portfolio sharing\n- Content monetization with direct tipping\n\nWhat would you like to do?"
        }

        // Component-aware fallback for questions: if the user is asking about
        // one of the 30 components but didn't hit an explicit keyword above,
        // re-use the same plain-English wizard we show for actions. The
        // wizards are written to double as explainers so a user asking "what
        // is staking" gets the same clear answer as one saying "I want to
        // stake".
        if let component = detectComponent(lower: lower) {
            return componentFlow(component: component, lower: lower, entities: entities)
        }

        return "Let me look into that for you. I'll gather the relevant information and present it clearly. One moment."
    }

    private func generatePortfolioResponse(lower: String, context: UserContext) -> String {
        if let portfolio = context.portfolioState {
            let value = String(format: "$%.2f", portfolio.totalValue)
            let change = String(format: "%+.2f%%", portfolio.dailyChangePercent)

            if lower.contains("performance") || lower.contains("return") {
                return "Your portfolio performance:\n\n- Total Value: \(value)\n- Today's Change: \(change)\n- Top holdings are performing as follows:\n\(portfolio.topHoldings.prefix(5).map { "  - \($0.symbol): \(String(format: "%+.2f%%", $0.changePercent)) (\(String(format: "%.1f%%", $0.allocation * 100)) allocation)" }.joined(separator: "\n"))\n\nWould you like a deeper analysis or rebalancing suggestions?"
            }
            if lower.contains("allocation") || lower.contains("breakdown") {
                return "Your portfolio allocation breakdown:\n\n\(portfolio.topHoldings.map { "- \($0.name) (\($0.symbol)): \(String(format: "%.1f%%", $0.allocation * 100)) — \(String(format: "$%.2f", $0.value))" }.joined(separator: "\n"))\n\nTotal: \(value). Would you like rebalancing recommendations based on your risk profile?"
            }

            return "Here's your portfolio overview:\n\n- Total Value: \(value)\n- 24h Change: \(change)\n- Holdings: \(portfolio.topHoldings.count) assets\n\nYour top positions:\n\(portfolio.topHoldings.prefix(3).map { "  - \($0.symbol): \(String(format: "$%.2f", $0.value)) (\(String(format: "%+.2f%%", $0.changePercent)))" }.joined(separator: "\n"))\n\nWould you like more details on any position?"
        }

        return "I'll pull up your portfolio data now. This includes your current balances, asset allocation, recent changes, and any active positions across all connected wallets and protocols."
    }

    private func generateSettingsResponse(lower: String) -> String {
        if lower.contains("notification") || lower.contains("alert") {
            return "I can adjust your notification preferences. Available options:\n\n- Price alerts (set thresholds for any asset)\n- Transaction confirmations\n- Portfolio change alerts (daily summaries or threshold-based)\n- Security alerts (always on, cannot be disabled)\n- Governance voting reminders\n\nWhat would you like to change?"
        }
        if lower.contains("security") || lower.contains("2fa") || lower.contains("biometric") {
            return "Security settings:\n\n- Biometric authentication: currently checking status\n- Two-factor authentication: I can help you enable or update this\n- Transaction signing: set approval thresholds\n- Active sessions: view and revoke connected devices\n- Recovery options: backup your wallet and identity\n\nWhat would you like to configure?"
        }
        return "I can help you adjust your settings. Available categories:\n\n- Notifications and alerts\n- Security and authentication\n- Display preferences (theme, language, currency)\n- Privacy settings\n- Connected wallets and accounts\n- Data export and backup\n\nWhich area would you like to configure?"
    }

    private func generateConversationResponse(lower: String) -> String {
        if lower.contains("hello") || lower.contains("hi") || lower.contains("hey") {
            return "Hello! I'm Trinity, your AI assistant for everything on MTRX. I can help you manage your portfolio, execute transactions, explore DeFi opportunities, handle NFTs, participate in governance, and much more. What would you like to do today?"
        }
        if lower.contains("thank") {
            return "You're welcome! I'm always here whenever you need help with anything on MTRX. Just ask."
        }
        if lower.contains("help") || lower.contains("what can you do") {
            return "I can help you with a wide range of activities across MTRX:\n\n- Portfolio: Check balances, track performance, rebalance\n- Payments: Send, receive, swap, and bridge assets\n- DeFi: Lending, borrowing, yield farming, liquidity provision\n- NFTs: Mint, buy, sell, and manage collections\n- Smart Contracts: Create, deploy, and interact with contracts\n- Insurance: Get coverage for contracts, travel, property\n- Gaming: Play, compete in tournaments, manage game assets\n- Marketplace: Buy, sell, and auction digital and real-world assets\n- Governance: Vote on proposals, delegate, create DAOs\n- Social: Messaging, posts, community engagement\n- Identity: Manage DIDs and verifiable credentials\n- Privacy: Zero-knowledge transactions and proofs\n\nJust tell me what you need!"
        }
        return "I'm here whenever you need me. Whether it's checking your portfolio, making a transaction, exploring DeFi, or anything else on MTRX — just let me know how I can help."
    }

    // MARK: - Suggested Actions

    /// Build suggested follow-up actions based on intent category.
    private func buildSuggestedActions(for intent: TrinityIntent, outcome: Outcome?) -> [SuggestedAction] {
        var actions: [SuggestedAction] = []

        // Outcome-driven suggestions
        if let outcome = outcome {
            switch outcome {
            case .ask(let prompt, let options):
                for option in options {
                    actions.append(SuggestedAction(
                        title: option,
                        description: prompt,
                        action: "respond:\(option)"
                    ))
                }
                return actions
            case .probe(let questions):
                for question in questions.prefix(3) {
                    actions.append(SuggestedAction(
                        title: "Answer",
                        description: question.text,
                        action: "probe:\(question.id)"
                    ))
                }
                return actions
            default:
                break
            }
        }

        // Category-driven suggestions
        switch intent.category {
        case .action:
            actions.append(SuggestedAction(title: "Confirm", description: "Proceed with this action", action: "confirm"))
            actions.append(SuggestedAction(title: "Modify", description: "Change the details", action: "modify"))
            actions.append(SuggestedAction(title: "Cancel", description: "Cancel this action", action: "cancel"))

        case .query:
            actions.append(SuggestedAction(title: "More Details", description: "Get a deeper analysis", action: "details"))
            actions.append(SuggestedAction(title: "Compare", description: "Compare with alternatives", action: "compare"))

        case .portfolio:
            actions.append(SuggestedAction(title: "Full Report", description: "Detailed portfolio analysis", action: "portfolio:report"))
            actions.append(SuggestedAction(title: "Rebalance", description: "Get rebalancing suggestions", action: "portfolio:rebalance"))
            actions.append(SuggestedAction(title: "Alerts", description: "Set up price alerts", action: "portfolio:alerts"))

        case .settings:
            actions.append(SuggestedAction(title: "Apply Changes", description: "Save these settings", action: "settings:apply"))
            actions.append(SuggestedAction(title: "Reset", description: "Reset to defaults", action: "settings:reset"))

        case .alertResponse:
            actions.append(SuggestedAction(title: "View Details", description: "See the full alert context", action: "alert:details"))

        case .conversation:
            actions.append(SuggestedAction(title: "Portfolio", description: "Check your portfolio", action: "nav:portfolio"))
            actions.append(SuggestedAction(title: "Send", description: "Send assets", action: "nav:send"))
            actions.append(SuggestedAction(title: "Explore", description: "Explore DeFi & NFTs", action: "nav:explore"))
        }

        return actions
    }

    // MARK: - Outcome Integration

    /// Incorporate scoring engine outcome context into the response text.
    private func incorporateOutcome(_ outcome: Outcome, into text: String) -> String {
        switch outcome {
        case .execute:
            return text
        case .probe(let questions):
            let probeText = questions.map { "- \($0.text)" }.joined(separator: "\n")
            return "\(text)\n\nBefore I proceed, I need a few more details:\n\(probeText)"
        case .ask(let prompt, let options):
            let optionsText = options.map { "- \($0)" }.joined(separator: "\n")
            return "\(text)\n\n\(prompt)\n\(optionsText)"
        case .defer_(let reason, let reassessAt):
            var deferText = "\(text)\n\nI've deferred this action: \(reason)"
            if let date = reassessAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                deferText += "\nI'll reassess at \(formatter.string(from: date))."
            }
            return deferText
        case .abort(let reason, let violations):
            let violationsText = violations.map { "- \($0)" }.joined(separator: "\n")
            return "I cannot proceed with this action.\n\nReason: \(reason)\n\nIssues identified:\n\(violationsText)\n\nPlease address these concerns before retrying."
        }
    }

    // MARK: - Voice Output

    /// Speak the response using Trinity's voice.
    /// - Parameter response: The response to speak.
    func speak(_ response: TrinityResponse) async {
        await voice.speak(response.text)
    }
}

// The authoritative ``MTRXAPIClient`` lives in
// ``Core/Networking/MTRXAPIClient.swift``. Trinity calls
// ``MTRXAPIClient.shared.sendAgentMessage`` which is declared there and
// returns an ``AgentChatResponse`` whose ``text`` property is what the
// ``think(...)`` method reads. This file used to carry a duplicate stub
// of the same class; that stub has been removed to avoid a redeclaration
// conflict now that the real client has shipped.

// MARK: - Trinity Response

/// A response generated by Trinity.
struct TrinityResponse: Sendable {
    let text: String
    let confidence: Double
    let suggestedActions: [SuggestedAction]
    let outcome: Outcome?
    let metadata: [String: String]
}

// MARK: - Suggested Action

struct SuggestedAction: Identifiable, Sendable {
    let id: UUID
    let title: String
    let description: String
    let action: String

    init(id: UUID = UUID(), title: String, description: String, action: String) {
        self.id = id
        self.title = title
        self.description = description
        self.action = action
    }
}

// MARK: - Trinity Intent

/// Represents the processed intent from a user message.
struct TrinityIntent: Sendable {
    let description: String
    let category: IntentCategory
    let entities: [String: String]
    let requiresDecision: Bool
    let timeSensitivity: TimeSensitivity
    let decisionContext: [String: Any]
    let confidence: Double
}

// MARK: - Intent Category

enum IntentCategory: String, Sendable, CaseIterable {
    case query          // User is asking for information
    case action         // User wants to perform an action
    case conversation   // General conversation
    case alertResponse  // User responding to a Morpheus alert
    case portfolio      // Portfolio-related query or action
    case settings       // Settings or configuration change
}

// MARK: - Conversation Turn

/// A single turn in the conversation history.
struct ConversationTurn: Identifiable, Sendable {
    let id: UUID = UUID()
    let userMessage: String
    let response: TrinityResponse
    let intent: TrinityIntent
    let timestamp: Date
}
