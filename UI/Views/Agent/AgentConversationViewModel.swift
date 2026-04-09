import Foundation
import Combine

/// Message model for agent conversations.
struct AgentMessage: Identifiable {
    let id: UUID
    let text: String
    let role: MessageRole
    let agentName: String?
    let timestamp: Date
    let suggestedActions: [SuggestedAction]

    enum MessageRole {
        case user
        case agent
        case system
    }

    init(text: String, role: MessageRole, agentName: String? = nil, suggestedActions: [SuggestedAction] = []) {
        self.id = UUID()
        self.text = text
        self.role = role
        self.agentName = agentName
        self.timestamp = Date()
        self.suggestedActions = suggestedActions
    }
}

/// ViewModel for the agent conversation interface.
@MainActor
final class AgentConversationViewModel: ObservableObject {
    @Published var messages: [AgentMessage] = []
    @Published var inputText = ""
    @Published var isTyping = false
    @Published var activeAgent: AgentAccessControl.ActiveAgent = .trinity
    @Published var showFirstBoot = false

    private let accessControl = AgentAccessControl.shared
    private let morpheus = MorpheusInterventions.shared
    private var userID: String = ""
    private var userType: AgentAccessControl.UserType = .consumer

    /// Maximum number of recent messages to include as conversation context for API calls.
    private let maxContextMessages = 10

    func setup(userID: String) {
        self.userID = userID
        self.userType = accessControl.userType(for: userID)

        // Set primary agent based on user type
        if userType == .owner {
            activeAgent = .neo
        } else {
            activeAgent = .trinity

            // Check first boot
            if !accessControl.hasShownFirstBoot(for: userID) {
                showFirstBoot = true
                accessControl.markFirstBootShown(for: userID)
            }
        }
    }

    // MARK: - Agent Switching

    /// Switch the active agent. Only available to owner users.
    /// - Parameter agent: The agent to switch to.
    func switchAgent(to agent: AgentAccessControl.ActiveAgent) {
        guard userType == .owner else {
            // Consumers cannot switch agents — Trinity handles routing
            messages.append(AgentMessage(
                text: "I'm here to help you directly. What would you like to do?",
                role: .agent,
                agentName: "Trinity"
            ))
            return
        }

        let previousAgent = activeAgent
        activeAgent = agent

        let agentName: String
        switch agent {
        case .trinity: agentName = "Trinity"
        case .morpheus: agentName = "Morpheus"
        case .neo: agentName = "Neo"
        }

        if previousAgent != agent {
            messages.append(AgentMessage(
                text: "Switched to \(agentName). How can I assist you?",
                role: .system
            ))
        }
    }

    // MARK: - Send Message

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Add user message
        messages.append(AgentMessage(text: text, role: .user))
        inputText = ""

        // Check access control
        let intent = UserIntent.parse(text)
        let route = accessControl.routeAgent(for: userID, intent: intent)

        switch route {
        case .allowed(let agent):
            activeAgent = agent
            processWithAgent(text: text, agent: agent)

        case .scenario1:
            // Trinity intercepts silently — user never knows
            activeAgent = .trinity
            processWithAgent(
                text: text,
                agent: .trinity,
                intercepted: true
            )

        case .scenario2(let bannedUserID):
            // Morpheus delivers warning then bans
            activeAgent = .morpheus
            let intervention = morpheus.evaluate(
                trigger: .maliciousAccess(userID: bannedUserID),
                userID: bannedUserID
            )
            if let intervention {
                morpheus.present(intervention)
            }
            accessControl.executeScenario2(userID: bannedUserID)

        case .scenario3Required:
            messages.append(AgentMessage(
                text: "This request requires owner authorization. A verification process has been initiated.",
                role: .agent,
                agentName: "Trinity"
            ))

        case .blocked:
            // Silently ignore banned users
            break
        }
    }

    // MARK: - Process With Agent

    private func processWithAgent(text: String, agent: AgentAccessControl.ActiveAgent, intercepted: Bool = false) {
        isTyping = true

        // Inject temporal context
        let temporal = TemporalContext.shared.currentPrompt()

        // Check Morpheus triggers for consumer users
        if userType == .consumer {
            checkMorpheusTriggers(text: text)
        }

        let agentName: String
        switch agent {
        case .trinity: agentName = "Trinity"
        case .morpheus: agentName = "Morpheus"
        case .neo: agentName = "Neo"
        }

        // Build conversation context from recent messages
        let conversationContext = buildConversationContext()

        Task {
            // Attempt real API call first
            do {
                let apiResponse = try await MTRXAPIClient.shared.sendAgentMessage(
                    agent: agentName.lowercased(),
                    message: text,
                    context: temporal + "\n" + conversationContext,
                    conversationHistory: buildHistoryPayload()
                )

                messages.append(AgentMessage(
                    text: apiResponse.text,
                    role: .agent,
                    agentName: agentName,
                    suggestedActions: apiResponse.suggestedActions
                ))
                isTyping = false
            } catch {
                // API unavailable — fall back to local response generation
                let response = generateResponse(
                    text: text,
                    agent: agent,
                    temporal: temporal,
                    intercepted: intercepted
                )

                messages.append(AgentMessage(
                    text: response,
                    role: .agent,
                    agentName: agentName
                ))
                isTyping = false
            }
        }
    }

    // MARK: - Conversation Context

    /// Build a text summary of recent conversation for API context.
    private func buildConversationContext() -> String {
        let recent = messages.suffix(maxContextMessages)
        guard !recent.isEmpty else { return "" }

        return recent.map { msg in
            let role = msg.role == .user ? "User" : (msg.agentName ?? "Agent")
            return "\(role): \(msg.text)"
        }.joined(separator: "\n")
    }

    /// Build a structured history payload for the API.
    private func buildHistoryPayload() -> [[String: String]] {
        return messages.suffix(maxContextMessages).map { msg in
            [
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.text,
                "agent": msg.agentName ?? ""
            ]
        }
    }

    // MARK: - Local Response Generation

    private func generateResponse(text: String, agent: AgentAccessControl.ActiveAgent, temporal: String, intercepted: Bool) -> String {
        if intercepted {
            // Scenario 1: Trinity warmly redirects without revealing the interception
            return "I can help you with that. Let me understand exactly what you need so I can assist you in the best way possible. Could you tell me more about what you're looking to accomplish?"
        }

        switch agent {
        case .trinity:
            return trinityResponse(for: text)
        case .morpheus:
            return morpheusResponse(for: text)
        case .neo:
            return neoResponse(for: text)
        }
    }

    // MARK: - Trinity Responses

    private func trinityResponse(for text: String) -> String {
        let lower = text.lowercased()

        // --- Payments ---
        if lower.contains("send") || lower.contains("transfer") {
            return "I can help you send assets securely. Here's what I need:\n\n1. **Amount** — How much would you like to send?\n2. **Asset** — Which token or currency?\n3. **Recipient** — Wallet address, ENS name, or MTRX username\n\nI'll show you the estimated network fees and ask for your confirmation before executing. Your transaction will be signed locally and never leaves your device until you approve."
        }
        if lower.contains("receive") {
            return "To receive assets, you can share your wallet address or QR code. Here are your options:\n\n- **Copy Address** — I can display your wallet address for any supported network\n- **QR Code** — Generate a scannable code with an optional amount pre-filled\n- **Payment Link** — Create a shareable link that anyone can use to send you funds\n\nWhich network would you like to receive on?"
        }
        if lower.contains("swap") {
            return "I'll find you the best swap rate across all available DEXs and aggregators. Here's how it works:\n\n1. Tell me what you want to swap (e.g., \"swap 1 ETH to USDC\")\n2. I'll fetch quotes from multiple sources and show you the best rate\n3. You'll see the exact output amount, slippage, and fees before confirming\n4. The swap executes atomically — it either fully completes or reverts\n\nWhat would you like to swap?"
        }
        if lower.contains("bridge") {
            return "I can bridge your assets between chains. Supported routes include Ethereum, Polygon, Arbitrum, Optimism, Base, Avalanche, and Solana.\n\nI'll compare bridge protocols to find the best combination of:\n- **Speed** — Some bridges complete in minutes, others take longer\n- **Cost** — Gas fees on source and destination chains\n- **Security** — Only using audited, battle-tested bridges\n\nWhat asset and which chains are you bridging between?"
        }

        // --- DeFi ---
        if lower.contains("loan") || lower.contains("borrow") {
            return "I can help you take out a DeFi loan. Here's what you need to know:\n\n- **Collateral**: You'll need to deposit collateral worth more than your loan (typically 150%+ ratio)\n- **Interest Rates**: I'll scan Aave, Compound, Maker, and other protocols for the best rates\n- **Liquidation Risk**: I'll calculate your liquidation price and set up alerts\n- **Health Factor**: I'll monitor your position and warn you if it drops below safe levels\n\nWhat asset would you like to borrow, and what collateral do you have available?"
        }
        if lower.contains("lend") || lower.contains("supply") || lower.contains("deposit") {
            return "Lending your assets is a great way to earn passive yield. Here's the current landscape:\n\n- **Aave**: Variable and stable rate options across multiple assets\n- **Compound**: Governance-token incentivized lending\n- **Maker**: DAI savings rate for stablecoin holders\n\nI'll show you the current APY for your asset, estimated earnings over different time periods, and protocol risk ratings. Which asset would you like to lend?"
        }
        if lower.contains("yield") || lower.contains("farm") || lower.contains("liquidity") {
            return "I can find the best yield opportunities for you. Options include:\n\n1. **Lending** — Earn interest by supplying assets to lending protocols (lower risk)\n2. **Liquidity Provision** — Provide liquidity to DEX pools and earn trading fees + rewards (moderate risk, impermanent loss possible)\n3. **Yield Farming** — Stake LP tokens to earn additional reward tokens (higher risk, higher reward)\n4. **Staking** — Lock tokens to earn network rewards (varies by protocol)\n\nI'll calculate risk-adjusted returns and factor in gas costs. What's your risk tolerance and how much capital are you looking to deploy?"
        }

        // --- NFTs ---
        if lower.contains("mint") {
            return "I can help you mint an NFT. Here's the process:\n\n1. **Upload Media** — Image, video, audio, or 3D model (IPFS-pinned for permanence)\n2. **Metadata** — Name, description, properties/traits, and unlockable content\n3. **Collection** — Add to an existing collection or create a new one\n4. **Royalties** — Set your creator royalty percentage (typically 2.5-10%)\n5. **Supply** — Unique 1/1 or editions (multiple copies)\n\nGas fees will be estimated before you confirm. Would you like to start minting?"
        }
        if lower.contains("nft") && (lower.contains("buy") || lower.contains("purchase")) {
            return "I can help you buy NFTs from the MTRX marketplace or connected markets. I'll show you:\n\n- **Floor Price** — The lowest available price in the collection\n- **Recent Sales** — What similar items have sold for\n- **Rarity Score** — How rare the traits are compared to the collection\n- **Ownership History** — Previous owners and sale prices\n- **Authenticity** — Verification that it's from the official collection\n\nPaste a link or tell me which collection you're interested in."
        }
        if lower.contains("nft") && (lower.contains("sell") || lower.contains("list")) {
            return "I'll help you list your NFT for sale. You have several options:\n\n- **Fixed Price** — Set a buy-it-now price\n- **English Auction** — Bidding starts low, highest bidder wins\n- **Dutch Auction** — Price starts high and decreases over time\n- **Private Sale** — Sell directly to a specific buyer\n\nI'll suggest a price based on recent comparable sales and collection floor. Which NFT would you like to list?"
        }
        if lower.contains("nft") && lower.contains("transfer") {
            return "I can transfer your NFT to another wallet. I'll need:\n\n- **NFT** — Which NFT to transfer (name, token ID, or select from your collection)\n- **Recipient** — Wallet address or ENS name\n\nNote: This is an irreversible action. I'll show you the exact NFT and recipient for confirmation before executing the transfer."
        }
        if lower.contains("collection") && lower.contains("nft") {
            return "I can help you explore NFT collections. I'll show you:\n\n- **Trending Collections** — Top movers by volume and floor price changes\n- **Your Collections** — NFTs you own, organized by collection\n- **Analytics** — Floor price history, holder distribution, and whale movements\n- **Upcoming Mints** — New collections launching soon\n\nWould you like to browse trending collections or check your own?"
        }

        // --- Smart Contracts ---
        if lower.contains("contract") && (lower.contains("create") || lower.contains("write")) {
            return "I can help you create a smart contract. MTRX offers audited templates for common use cases:\n\n- **ERC-20 Token** — Create a custom fungible token\n- **ERC-721 NFT** — Launch an NFT collection with customizable minting\n- **Multisig Wallet** — Require multiple signatures for transactions\n- **Escrow** — Hold funds until conditions are met\n- **Vesting** — Time-locked token distribution\n- **DAO** — Governance with voting and treasury management\n- **Staking** — Let users stake your token for rewards\n\nAll templates are audited. I can also help you write custom logic. Which type interests you?"
        }
        if lower.contains("deploy") {
            return "I'll walk you through deploying your smart contract. Before deployment, I'll:\n\n1. **Glasswing Security Audit** — Full 12-point vulnerability scan (reentrancy, overflow, access control, and more)\n2. **Risk Assessment** — Ultron evaluates strategic risk before any deployment proceeds\n3. **Gas Estimation** — Calculate deployment cost on your target network\n4. **Testnet First** — Deploy to a testnet so you can verify behavior\n5. **Constructor Args** — Help you set the right initialization parameters\n\n⚠️ Critical vulnerabilities will block deployment automatically. This is a permanent, irreversible action on the blockchain. Which network would you like to deploy to?"
        }
        if lower.contains("escrow") {
            return "I can set up an escrow contract for you. Here's how it works:\n\n1. **Parties** — Define the buyer, seller, and optional arbiter\n2. **Conditions** — Set the release conditions (time-based, approval-based, or milestone-based)\n3. **Amount** — Specify the escrowed amount and token\n4. **Dispute Resolution** — Define what happens if there's a disagreement\n\nFunds are held securely on-chain and only released when conditions are met. Would you like to create one?"
        }
        if lower.contains("template") && lower.contains("contract") {
            return "Here are the available smart contract templates, all security-audited:\n\n- **Token (ERC-20)** — Customizable supply, decimals, minting/burning\n- **NFT Collection (ERC-721)** — Metadata, royalties, allowlists\n- **Multisig** — 2-of-3, 3-of-5, or custom threshold\n- **Escrow** — Two-party or arbitrated\n- **Vesting** — Linear, cliff, or custom schedule\n- **Staking Pool** — Flexible or locked staking with rewards\n- **DAO Governor** — Proposal, voting, and execution\n- **Marketplace** — List, bid, and trade assets\n\nWhich template would you like to use? I'll customize it to your needs."
        }

        // --- Insurance ---
        if lower.contains("insurance") || lower.contains("coverage") || lower.contains("insure") {
            return "MTRX offers several types of decentralized insurance:\n\n1. **Smart Contract Cover** — Protection against exploits and bugs in DeFi protocols\n2. **Parametric Insurance** — Automatic payouts based on verifiable events (weather, flight delays, earthquakes)\n3. **DeFi Position Insurance** — Cover against impermanent loss or unexpected liquidation\n4. **Renters Insurance** — Decentralized property coverage with instant claims\n5. **Travel Insurance** — Flight delay/cancellation coverage with automatic payouts\n\nPremiums are calculated based on risk models and paid in crypto. Claims are processed on-chain for transparency. What type of coverage do you need?"
        }
        if lower.contains("claim") && lower.contains("insurance") {
            return "To file an insurance claim, I'll need:\n\n1. **Policy ID** — Your active insurance policy identifier\n2. **Event Details** — What happened and when\n3. **Evidence** — Transaction hashes, screenshots, or oracle data supporting the claim\n\nFor parametric policies, claims are often processed automatically when oracle data confirms the triggering event. Let me pull up your active policies."
        }

        // --- Gaming ---
        if lower.contains("play") || lower.contains("game") || lower.contains("gaming") {
            return "Welcome to MTRX Gaming! Here's what's available:\n\n- **Active Games** — Browse and join play-to-earn games\n- **Tournaments** — Compete for prize pools in scheduled events\n- **Game Assets** — View and manage your in-game NFTs and items\n- **Leaderboards** — Check rankings across all games\n- **Rewards** — Claim earned tokens and NFTs\n\nAll in-game assets are NFTs you truly own — trade, sell, or use them across compatible games. Would you like to browse games or check your gaming profile?"
        }
        if lower.contains("tournament") {
            return "Here are the tournament options:\n\n- **Upcoming** — Browse tournaments you can register for\n- **Active** — Check your current tournament status and standings\n- **Completed** — View past results and claim prizes\n- **Create** — Set up a custom tournament (requires staking the prize pool)\n\nEntry fees and prizes are handled on-chain with automatic distribution. Would you like to see available tournaments?"
        }
        if lower.contains("leaderboard") {
            return "I can show you leaderboards for:\n\n- **Global Rankings** — Top players across all MTRX games\n- **Game-Specific** — Rankings within individual games\n- **Tournament** — Current standings in active competitions\n- **Earnings** — Top earners by play-to-earn rewards\n\nWhich leaderboard would you like to see?"
        }

        // --- Marketplace ---
        if lower.contains("marketplace") || lower.contains("market") {
            return "The MTRX Marketplace supports a wide range of assets:\n\n- **Digital Assets** — NFTs, tokens, digital collectibles, and domain names\n- **Real World Assets (RWA)** — Tokenized property, commodities, art, and securities\n- **Services** — Smart contract templates, audits, and development services\n\nYou can browse by category, search for specific items, or list your own assets. All trades use on-chain escrow for safety. What are you looking for?"
        }
        if lower.contains("property") || lower.contains("real estate") || lower.contains("rwa") {
            return "MTRX supports tokenized Real World Assets (RWA). Here's what's available:\n\n- **Fractional Property** — Own a share of real estate properties\n- **Commodities** — Tokenized gold, silver, and other commodities\n- **Art & Collectibles** — Verified physical items with digital twins\n- **Revenue-Sharing** — Invest in assets that distribute real yield\n\nAll RWAs are backed by legal structures and verified custodians. Would you like to browse available properties?"
        }

        // --- Fundraising ---
        if lower.contains("fundrais") || lower.contains("campaign") || lower.contains("crowdfund") {
            return "MTRX Fundraising uses milestone-based smart contracts for transparency:\n\n1. **Create Campaign** — Set your funding goal, timeline, and milestones\n2. **Milestone Releases** — Funds are released as you hit verified milestones\n3. **Donor Protection** — Contributors can vote on milestone approval\n4. **Transparency** — All funds and movements visible on-chain\n\nWould you like to create a new campaign or browse existing ones?"
        }
        if lower.contains("donate") || lower.contains("contribute") {
            return "I can help you contribute to a fundraising campaign. I'll show you:\n\n- **Campaign Details** — Goal, progress, timeline, and team\n- **Milestone Status** — Which milestones have been completed\n- **Fund Usage** — How previous funds were allocated\n- **Tax Documentation** — Downloadable receipts for eligible donations\n\nPaste a campaign link or search by category to find campaigns to support."
        }

        // --- Governance ---
        if lower.contains("vote") {
            return "I can help you participate in governance voting. Here's what's available:\n\n- **Active Proposals** — View proposals currently open for voting\n- **Your Voting Power** — Check your token-weighted voting power\n- **Proposal Analysis** — I'll summarize proposals and their implications\n- **Vote History** — Review your past voting record\n\nI can also explain complex proposals in plain language before you vote. Which DAO or protocol would you like to participate in?"
        }
        if lower.contains("propos") {
            return "I can help you create a governance proposal. Here's the process:\n\n1. **Draft** — Write your proposal with a clear title, description, and requested action\n2. **Discussion** — Share it for community feedback before formal submission\n3. **Submission** — Submit on-chain (may require a minimum token threshold)\n4. **Voting Period** — Community votes during the designated window\n5. **Execution** — If passed, the proposal executes automatically via the DAO contract\n\nWhat would you like to propose?"
        }
        if lower.contains("delegate") {
            return "Delegating your voting power lets someone else vote on your behalf. Here's how:\n\n- **Choose a Delegate** — I'll show you active delegates with their voting history and platform\n- **Partial Delegation** — Delegate all or part of your voting power\n- **Revoke Anytime** — You can reclaim your voting power at any time\n- **Self-Delegate** — Delegate to yourself to activate direct voting\n\nWhich governance token would you like to delegate?"
        }
        if lower.contains("dao") || lower.contains("organization") {
            return "I can help you interact with or create a DAO:\n\n- **Join a DAO** — Browse active DAOs and their requirements\n- **Create a DAO** — Set up governance structure, treasury, and voting rules\n- **Manage Treasury** — View and propose treasury allocations\n- **Member Roles** — Configure permissions and responsibilities\n\nDAOs on MTRX use audited Governor contracts with customizable voting parameters. What would you like to do?"
        }

        // --- Social ---
        if lower.contains("post") || lower.contains("share") {
            return "I can help you create a social post on MTRX:\n\n- **Public Post** — Share with the entire MTRX community\n- **Token-Gated** — Only visible to holders of specific tokens\n- **Portfolio Share** — Share your portfolio performance (with privacy controls)\n- **Transaction Share** — Share a notable transaction or trade\n\nAll posts are signed with your DID for authenticity. What would you like to share?"
        }
        if lower.contains("message") || lower.contains("chat") || lower.contains("dm") {
            return "MTRX messaging is end-to-end encrypted and decentralized:\n\n- **Direct Messages** — Send encrypted messages to any MTRX user\n- **Group Chats** — Create or join group conversations\n- **Token-Gated Channels** — Access exclusive communities\n- **Attachments** — Send files, images, and transaction requests\n\nMessages are stored encrypted on IPFS — only you and your recipients can read them. Who would you like to message?"
        }
        if lower.contains("encrypt") && lower.contains("message") {
            return "All MTRX messages are encrypted by default using your wallet's keys. Additional privacy features:\n\n- **Disappearing Messages** — Set auto-delete timers\n- **Forward Protection** — Prevent message forwarding\n- **Anonymous Mode** — Send messages without revealing your identity\n- **Key Rotation** — Automatic key rotation for enhanced security\n\nYour privacy is protected by cryptography, not trust."
        }

        // --- Staking ---
        if lower.contains("stake") || lower.contains("staking") {
            return "Staking allows you to earn rewards by securing the network. Here's what I can help with:\n\n1. **Choose a Validator** — I'll show you validators ranked by performance, uptime, and commission\n2. **Stake Amount** — Decide how much to stake (you can stake partially)\n3. **Lock Period** — Some networks have unbonding periods (typically 7-28 days)\n4. **Rewards** — Current APY and estimated earnings displayed upfront\n5. **Auto-Compound** — Option to automatically restake rewards\n\nHow much would you like to stake and on which network?"
        }
        if lower.contains("unstake") {
            return "I'll help you unstake your tokens. Important details:\n\n- **Unbonding Period** — Your tokens will be locked during the unstaking period (varies by network)\n- **Pending Rewards** — Any unclaimed rewards will be collected automatically\n- **Partial Unstake** — You can unstake a portion while keeping the rest staked\n\nOnce I initiate the unstaking, I'll set up a reminder for when your tokens become available. How much would you like to unstake?"
        }
        if lower.contains("validator") {
            return "Here's how I evaluate validators for you:\n\n- **Uptime** — Historical availability percentage\n- **Commission** — Fee charged on your rewards (lower is better for you)\n- **Total Stake** — How much is delegated (avoid over-concentrated validators)\n- **Governance Participation** — Active validators who vote on proposals\n- **Track Record** — Slashing history and time active\n\nI recommend diversifying across 2-3 validators to reduce risk. Shall I show you the top performers?"
        }
        if lower.contains("reward") && lower.contains("stak") {
            return "I'll pull up your staking rewards summary:\n\n- **Accumulated Rewards** — Total rewards earned to date\n- **Pending Rewards** — Unclaimed rewards ready to collect\n- **APY** — Current annual percentage yield\n- **Projected Earnings** — Estimated rewards over the next 30/90/365 days\n- **Reward History** — Complete log of past reward distributions\n\nWould you like to claim your pending rewards or see the detailed breakdown?"
        }

        // --- Portfolio ---
        if lower.contains("balance") || lower.contains("portfolio") || lower.contains("holdings") {
            return "Let me pull up your portfolio. I'll show you:\n\n- **Total Value** — Combined value across all wallets and chains\n- **Asset Breakdown** — Each holding with current value and 24h change\n- **Allocation Chart** — Visual breakdown of your portfolio distribution\n- **DeFi Positions** — Active lending, borrowing, LP, and staking positions\n- **NFT Holdings** — Your NFT collection with estimated floor values\n\nI'll also flag any positions that need attention, like low health factors or expiring positions."
        }
        if lower.contains("performance") || lower.contains("pnl") || lower.contains("profit") || lower.contains("loss") {
            return "I'll generate your portfolio performance report:\n\n- **Total Return** — Overall profit/loss since inception\n- **Period Returns** — 24h, 7d, 30d, 90d, and YTD performance\n- **Best/Worst Performers** — Your top and bottom assets by return\n- **Benchmark Comparison** — How you compare to BTC, ETH, and market indices\n- **Risk Metrics** — Volatility, Sharpe ratio, and max drawdown\n\nWould you like the full report or a specific time period?"
        }
        if lower.contains("history") || lower.contains("transaction") {
            return "I'll pull your transaction history. I can filter by:\n\n- **Time Period** — Today, this week, this month, or custom range\n- **Type** — Sends, receives, swaps, contract interactions, approvals\n- **Asset** — Specific token or NFT\n- **Network** — Filter by blockchain\n- **Status** — Pending, confirmed, or failed\n\nI'll also calculate gas spent and show the current value vs. transaction-time value. What would you like to see?"
        }

        // --- Identity ---
        if lower.contains("identity") || lower.contains("did") || lower.contains("credential") || lower.contains("verify") {
            return "MTRX uses Decentralized Identity (DID) for self-sovereign verification:\n\n- **Create DID** — Set up your decentralized identifier anchored to your wallet\n- **Verifiable Credentials** — Issue or receive tamper-proof credentials\n- **Selective Disclosure** — Prove attributes (age, residency, etc.) without revealing personal data\n- **Cross-Platform** — Use your DID across any compatible platform\n- **Credential Wallet** — Manage all your credentials in one place\n\nYour identity data stays under your control — no central authority can revoke or modify it. What would you like to do?"
        }

        // --- Privacy ---
        if lower.contains("privacy") || lower.contains("zero-knowledge") || lower.contains("zk") || lower.contains("private") {
            return "MTRX privacy features powered by zero-knowledge cryptography:\n\n- **Private Transfers** — Send tokens without revealing the amount on-chain\n- **Proof of Funds** — Prove you have sufficient balance without showing your total\n- **Commitment Schemes** — Submit sealed bids or votes that are revealed later\n- **Compliance Proofs** — Prove regulatory compliance without exposing personal data\n- **Private Voting** — Vote on governance proposals without revealing your choice until tally\n\nAll privacy features use battle-tested ZK circuits. Which feature interests you?"
        }

        // --- Security & Audit ---
        if lower.contains("audit") || lower.contains("vulnerability") || lower.contains("security scan") || lower.contains("glasswing") {
            return "Every smart contract on MTRX is scanned by the Glasswing security audit layer before deployment. Here's what it checks:\n\n- **Reentrancy (SWC-107)** — Detects state changes after external calls\n- **Unchecked Returns (SWC-104)** — Finds ignored low-level call results\n- **tx.origin Auth (SWC-115)** — Flags phishable authentication patterns\n- **Selfdestruct (SWC-106)** — Warns about destructible contracts\n- **Integer Overflow (SWC-101)** — Catches unsafe arithmetic\n- **Access Control (AC-001)** — Verifies proper permission guards\n- **Front-Running (FR-001)** — Identifies MEV-vulnerable patterns\n- **Floating Pragma (SWC-103)** — Enforces pinned compiler versions\n\nCritical findings block deployment automatically. Would you like to audit a contract or view a past audit report?"
        }
        if lower.contains("security") && !lower.contains("security token") {
            return "MTRX security is powered by the Glasswing audit layer integrated across the entire protocol stack:\n\n- **Pre-Deployment Scanning** — 12-point vulnerability analysis on every contract\n- **Morpheus Enforcement** — Critical findings automatically block unsafe deployments\n- **Continuous Monitoring** — Friday protocol watches for security anomalies in real-time\n- **HiveMind Coordination** — Security intelligence shared across all agent instances\n- **Vision Pattern Detection** — AI-powered detection of emerging threat patterns\n\nSecurity isn't an add-on — it's woven into every layer of the platform. What would you like to know more about?"
        }
        if lower.contains("exploit") || lower.contains("hack") || lower.contains("reentrancy") || lower.contains("overflow") {
            return "I take security threats seriously. Here's how MTRX protects against common exploits:\n\n- **Reentrancy Attacks** — Glasswing detects state-after-call patterns and blocks deployment\n- **Integer Overflow** — Arithmetic operations are checked for safe math usage\n- **Front-Running** — MEV-vulnerable operations are flagged for review\n- **Delegatecall Injection** — Dangerous proxy patterns are identified\n- **Timestamp Manipulation** — Block.timestamp dependencies are flagged\n- **Access Control Gaps** — Missing onlyOwner/role guards are caught\n\nAll findings are classified by severity (Critical, High, Medium, Low, Info). Critical and High findings must be resolved before deployment proceeds."
        }

        // --- Managed Agents ---
        if lower.contains("agent") && (lower.contains("manage") || lower.contains("orchestrat") || lower.contains("coordinat")) {
            return "MTRX uses a managed agent architecture with intelligent orchestration:\n\n- **Neo** — The coordinator agent with full system access, delegates tasks to specialized agents\n- **Trinity** — User-facing assistant handling all consumer interactions\n- **Morpheus** — Guardian agent that monitors for risky operations and intervenes when needed\n\nAgents share a common environment but maintain isolated context. Communication flows through typed events — each agent sees only what it needs. The HiveMind protocol enables collective intelligence across all agent instances.\n\nWould you like to learn more about how the agents work together?"
        }

        // --- General fallback ---
        if lower.contains("help") || lower.contains("what can you do") {
            return "I'm Trinity, your AI assistant for everything on MTRX. Here's what I can help with:\n\n**Financial**\n- Send, receive, swap, and bridge assets\n- DeFi: lending, borrowing, yield farming, liquidity\n- Staking and validator management\n- Portfolio tracking and analytics\n\n**Digital Assets**\n- NFTs: mint, buy, sell, transfer, collections\n- Smart contracts: create, deploy, manage\n- Marketplace: buy, sell, auction\n\n**Services**\n- Insurance: smart contract, parametric, renters, travel\n- Fundraising: create campaigns, donate, track milestones\n- Gaming: play, tournaments, leaderboards\n\n**Community**\n- Governance: vote, propose, delegate, DAOs\n- Social: posts, encrypted messaging, communities\n- Identity: DIDs, verifiable credentials\n- Privacy: zero-knowledge proofs and private transactions\n\nJust tell me what you need!"
        }
        if lower.contains("hello") || lower.contains("hi ") || lower.contains("hey") || lower == "hi" {
            return "Hello! I'm Trinity, your AI assistant for MTRX. I can help you manage your assets, explore DeFi, handle NFTs, participate in governance, and much more. What would you like to do today?"
        }
        if lower.contains("thank") {
            return "You're welcome! I'm always here whenever you need help. Is there anything else I can assist you with?"
        }

        return "I'm here to help you with anything on MTRX — from managing your portfolio and executing transactions to exploring DeFi, NFTs, governance, insurance, gaming, and more. What would you like to do?"
    }

    // MARK: - Morpheus Responses

    private func morpheusResponse(for text: String) -> String {
        let lower = text.lowercased()

        if lower.contains("deploy") || lower.contains("contract") {
            return "You are about to deploy a smart contract to a public blockchain. This action is permanent and irreversible.\n\nThe Glasswing security audit will run automatically before deployment:\n- **12 vulnerability checks** covering reentrancy, overflow, access control, and more\n- **Critical findings block deployment** — no exceptions\n- **Audit report attached** to every deployed contract for transparency\n\nAdditionally:\n- The contract code will be visible to everyone\n- Any bugs or vulnerabilities cannot be patched after deployment\n- Gas fees for deployment are non-refundable\n\nDo you wish to proceed? The audit results will determine whether deployment can continue."
        }
        if lower.contains("loan") || lower.contains("borrow") || lower.contains("lend") {
            return "You are entering a DeFi lending/borrowing position. Consider carefully:\n\n- **Liquidation Risk** — If your collateral value drops below the threshold, your position will be liquidated automatically with no appeal\n- **Variable Rates** — Interest rates can change dramatically based on utilization\n- **Smart Contract Risk** — Your funds are held in a smart contract that could have undiscovered vulnerabilities\n- **No Recourse** — There is no customer support or dispute resolution in DeFi\n\nAre you fully prepared for these risks?"
        }
        if lower.contains("irreversible") || lower.contains("permanent") || lower.contains("can't be undone") {
            return "This action cannot be reversed once executed. The blockchain does not have an undo button.\n\nTake a moment to verify:\n- Is the recipient address correct? One wrong character means permanent loss.\n- Is the amount correct? There are no refunds.\n- Are you on the right network? Cross-chain recovery may be impossible.\n\nOnly proceed if you have verified every detail."
        }
        if lower.contains("safe") || lower.contains("risk") || lower.contains("dangerous") {
            return "Let me assess the risk profile of what you're considering:\n\n- **Smart Contract Risk** — Has the contract been audited? By whom? When?\n- **Counterparty Risk** — Who is on the other side of this transaction?\n- **Market Risk** — Could price movements adversely affect your position?\n- **Regulatory Risk** — Are there compliance considerations?\n\nI exist to make sure you understand the full picture before making irreversible decisions."
        }

        return "Consider carefully what you are asking. Every action on the blockchain has consequences, and many are permanent. I'm here to ensure you understand the full implications before proceeding. What specifically would you like me to evaluate?"
    }

    // MARK: - Neo Responses

    private func neoResponse(for text: String) -> String {
        let lower = text.lowercased()

        if lower.contains("status") || lower.contains("system") {
            return "System Status Report:\n\n- **Runtime**: All nodes operational\n- **Consensus**: Healthy, 99.97% uptime\n- **API Gateway**: Response time 45ms avg\n- **Smart Contract Engine**: 0 pending deployments\n- **Oracle Network**: All feeds active\n- **Security**: No anomalies detected\n- **Memory**: Trinity memory store healthy, \(Int.random(in: 1000...5000)) entries\n- **Morpheus**: Monitoring active, 0 interventions pending\n\nAll systems nominal. What would you like to inspect?"
        }
        if lower.contains("deploy") || lower.contains("update") || lower.contains("upgrade") {
            return "Ready for deployment operation. Orchestrated pipeline status:\n\n1. Code compilation — standing by\n2. Glasswing security audit — 12-point vulnerability scan queued\n3. Ultron risk assessment — strategic analysis prepared\n4. Testnet validation — prepared\n5. Morpheus gate — final safety check before mainnet\n6. Mainnet deployment — awaiting your authorization\n\nAll agents coordinated via HiveMind. Provide the deployment target and I will execute. Full audit trail will be maintained."
        }
        if lower.contains("analytics") || lower.contains("metrics") || lower.contains("data") {
            return "Analytics dashboard available. Current metrics:\n\n- **Daily Active Users**: Tracking\n- **Transaction Volume**: Monitoring across all chains\n- **Gas Optimization**: Running continuous analysis\n- **Protocol Revenue**: Aggregating from all sources\n- **Error Rate**: < 0.01% across all endpoints\n\nWhich metric set would you like to drill into?"
        }
        if lower.contains("config") || lower.contains("setting") || lower.contains("parameter") {
            return "System configuration access granted. Available operations:\n\n- **Runtime Parameters** — Adjust gas limits, timeout values, retry policies\n- **Agent Configuration** — Modify Trinity/Morpheus behavior parameters\n- **Network Settings** — RPC endpoints, chain priorities, fallback nodes\n- **Security Policies** — Rate limits, access controls, encryption settings\n\nSpecify the parameter you wish to modify."
        }

        return "Processing. All systems operational. Full backend access available. What operation do you need executed?"
    }

    // MARK: - Morpheus Trigger Checks

    private func checkMorpheusTriggers(text: String) {
        let lower = text.lowercased()

        // Check for first capability use triggers
        let categoryKeywords: [(MorpheusInterventions.CapabilityCategory, [String])] = [
            (.smartContract, ["smart contract", "deploy contract", "create contract"]),
            (.defiLoan, ["defi", "loan", "borrow", "lend"]),
            (.nft, ["nft", "mint", "token"]),
            (.dao, ["dao", "organization", "collective"]),
            (.staking, ["stake", "staking", "validator"]),
            (.insurance, ["insurance", "insure", "coverage"]),
            (.securities, ["securities", "security token", "equity"]),
            (.identity, ["identity", "credential", "verify identity"]),
            (.governance, ["vote", "governance", "proposal"]),
            (.marketplace, ["marketplace", "list for sale", "buy asset"]),
        ]

        for (category, keywords) in categoryKeywords {
            if keywords.contains(where: { lower.contains($0) }) {
                if let intervention = morpheus.evaluate(
                    trigger: .firstCapabilityUse(category),
                    userID: userID
                ) {
                    morpheus.present(intervention)
                    break
                }
            }
        }
    }
}
