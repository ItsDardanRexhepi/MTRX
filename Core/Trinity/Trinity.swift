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

    private func generateActionResponse(lower: String, entities: [String: String]) -> String {
        let amount = entities["amount"] ?? "the specified amount"
        let asset = entities["asset"] ?? "your asset"

        if lower.contains("send") || lower.contains("transfer") {
            let recipient = entities["ensName"] ?? entities["walletAddress"] ?? "the recipient"
            return "I'll prepare a transfer of \(amount) to \(recipient). Before I execute this, please confirm the details:\n\n- Amount: \(amount)\n- To: \(recipient)\n- Network fees will be calculated at current rates\n\nShall I proceed with this transfer?"
        }
        if lower.contains("swap") {
            return "I'll set up a swap for \(amount) of \(asset). I'll find the best rate across available DEXs and show you the quote including slippage and fees before executing. One moment while I fetch current rates."
        }
        if lower.contains("bridge") {
            return "I can bridge \(amount) of \(asset) to your target chain. I'll compare bridge protocols for the best combination of speed, cost, and security. Which chain would you like to bridge to?"
        }
        if lower.contains("deploy") || lower.contains("create contract") {
            return "I'll help you deploy a smart contract. This is an irreversible on-chain action, so let me walk you through it carefully:\n\n1. What type of contract do you need? (token, NFT collection, escrow, multisig, custom)\n2. Which network should it be deployed on?\n3. Do you have the contract code ready, or would you like to use one of our audited templates?\n\nI'll run a security analysis before any deployment."
        }
        if lower.contains("stake") {
            return "I can help you stake \(amount) of \(asset). Here's what you should know:\n\n- Current APY varies by validator — I'll show you the top-performing ones\n- Staking locks your tokens for the unbonding period\n- Rewards are distributed automatically\n\nWould you like to see available validators and their performance history?"
        }
        if lower.contains("unstake") {
            return "I'll initiate an unstaking request for \(amount) of \(asset). Please note that unstaking involves an unbonding period during which your tokens will not earn rewards and cannot be transferred. I'll show you the exact timeline. Shall I proceed?"
        }
        if lower.contains("mint") {
            return "I'll help you mint a new NFT. Please provide:\n\n- The media file (image, video, audio, or 3D model)\n- Name and description for the NFT\n- Collection (existing or new)\n- Royalty percentage for secondary sales\n- Supply (1 for unique, or multiple for editions)\n\nI'll estimate gas fees before minting."
        }
        if lower.contains("borrow") || lower.contains("loan") {
            return "I can help you open a borrowing position. Here's the current landscape:\n\n- I'll scan available lending protocols for the best rates\n- Your collateral ratio and liquidation price will be clearly displayed\n- Health factor monitoring will be set up automatically\n\nWhat asset would you like to borrow, and what collateral will you provide?"
        }
        if lower.contains("lend") || lower.contains("supply") {
            return "I can help you supply \(amount) of \(asset) to a lending protocol. I'll compare current supply APYs across protocols and show you:\n\n- Expected yield over different time horizons\n- Protocol risk ratings\n- Withdrawal flexibility\n\nWould you like to see the comparison?"
        }
        if lower.contains("vote") || lower.contains("propose") {
            return "I'll help you participate in governance. I can show you active proposals, help you understand their implications, and submit your vote on-chain. Which DAO or protocol are you looking to participate in?"
        }
        if lower.contains("insure") || lower.contains("insurance") || lower.contains("coverage") {
            return "I can help you get coverage. MTRX offers several insurance products:\n\n- Smart contract cover (protect against exploits)\n- Parametric insurance (weather, flight delays)\n- DeFi position insurance (impermanent loss, liquidation)\n- Renters and travel insurance\n\nWhat type of coverage are you looking for?"
        }
        if lower.contains("list") || lower.contains("auction") {
            return "I'll help you list your asset on the marketplace. Please provide:\n\n- The asset to list (NFT, token, or RWA)\n- Sale type: fixed price or auction\n- Starting price and optional reserve price\n- Duration for the listing\n\nI'll handle the on-chain listing and notify you of any offers."
        }
        if lower.contains("donate") || lower.contains("fund") || lower.contains("campaign") {
            return "I can help with fundraising. Would you like to:\n\n- Create a new fundraising campaign with milestone-based releases\n- Donate to an existing campaign\n- View campaign progress and milestone status\n\nAll campaigns use transparent on-chain accounting with milestone verification."
        }
        if lower.contains("delegate") {
            return "I'll help you delegate your voting power. I can show you active delegates, their voting history, and alignment with your preferences. Which governance token would you like to delegate?"
        }

        return "I'll help you with that action. Let me prepare everything needed. Could you confirm the specific details so I can proceed safely?"
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

// MARK: - MTRX API Client

/// API client for communicating with the MTRX backend runtime.
/// Singleton that manages agent message routing and conversation context.
final class MTRXAPIClient {
    static let shared = MTRXAPIClient()

    private let session: URLSession
    private let baseURL: URL

    struct AgentResponse {
        let text: String
        let suggestedActions: [SuggestedAction]
        let metadata: [String: String]
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        // Default to local runtime; override via environment or config
        self.baseURL = URL(string: ProcessInfo.processInfo.environment["MTRX_API_URL"] ?? "https://api.mtrx.run/v1")!
    }

    /// Send a message to an agent and receive a response.
    /// - Parameters:
    ///   - agent: The agent name ("trinity", "morpheus", "neo").
    ///   - message: The user's message.
    ///   - context: The assembled prompt/context string.
    ///   - conversationHistory: Recent conversation entries for continuity.
    /// - Returns: The agent's response.
    func sendAgentMessage(
        agent: String,
        message: String,
        context: String,
        conversationHistory: [[String: String]]
    ) async throws -> AgentResponse {
        let url = baseURL.appendingPathComponent("agent/\(agent)/message")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "message": message,
            "context": context,
            "history": conversationHistory
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw APIError.invalidResponse
        }

        let suggestedActions: [SuggestedAction]
        if let actionsArray = json["suggestedActions"] as? [[String: String]] {
            suggestedActions = actionsArray.compactMap { dict in
                guard let title = dict["title"],
                      let description = dict["description"],
                      let action = dict["action"] else { return nil }
                return SuggestedAction(title: title, description: description, action: action)
            }
        } else {
            suggestedActions = []
        }

        let metadata = json["metadata"] as? [String: String] ?? [:]

        return AgentResponse(text: text, suggestedActions: suggestedActions, metadata: metadata)
    }

    enum APIError: Error {
        case requestFailed
        case invalidResponse
    }
}

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
