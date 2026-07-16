// DemoDataProvider.swift
// MTRX
//
// Provides realistic demo data for every service when the backend
// is unavailable. The app must never show a blank screen or crash.
// Used automatically when API calls fail or time out.

import Foundation
import SwiftUI

// MARK: - Demo Data Provider

enum DemoDataProvider {

    // MARK: - Wallet

    static let walletAddress = "0x742d35Cc6634C0532925a3b8D4C9B7D8e3F2a1b"
    static let ensName = "neo.eth"
    static let ethBalance = 2.847
    static let ethPrice = 3137.89
    static let portfolioTotal = 12847.33
    static let portfolioChange24h = 4.2

    static let tokens: [DemoToken] = [
        DemoToken(symbol: "ETH", name: "Ethereum", balance: 2.847, priceUSD: 3137.89, change24h: 3.12, iconColor: .blue),
        DemoToken(symbol: "USDC", name: "USD Coin", balance: 2100.00, priceUSD: 1.00, change24h: 0.01, iconColor: .green),
        DemoToken(symbol: "LINK", name: "Chainlink", balance: 61.2, priceUSD: 14.56, change24h: 5.67, iconColor: .blue),
        DemoToken(symbol: "UNI", name: "Uniswap", balance: 56.9, priceUSD: 7.82, change24h: -0.45, iconColor: .pink),
        DemoToken(symbol: "AAVE", name: "Aave", balance: 5.3, priceUSD: 89.98, change24h: 2.34, iconColor: .purple),
    ]

    static let transactions: [DemoTransaction] = [
        DemoTransaction(type: .receive, title: "Received ETH", subtitle: "From 0x1a2b...3c4d", amount: "+0.5 ETH", date: Date().addingTimeInterval(-3600), status: .confirmed),
        DemoTransaction(type: .swap, title: "Swap ETH \u{2192} USDC", subtitle: "Via Uniswap V3", amount: "1,250 USDC", date: Date().addingTimeInterval(-7200), status: .confirmed),
        DemoTransaction(type: .stake, title: "Staked LINK", subtitle: "Chainlink Staking v0.2", amount: "25 LINK", date: Date().addingTimeInterval(-86400), status: .confirmed),
        DemoTransaction(type: .send, title: "Sent USDC", subtitle: "To 0x9f8e...7d6c", amount: "-500 USDC", date: Date().addingTimeInterval(-172800), status: .confirmed),
        DemoTransaction(type: .contract, title: "Deploy Contract", subtitle: "Escrow Agreement", amount: "-0.003 ETH", date: Date().addingTimeInterval(-259200), status: .confirmed),
    ]

    static let nfts: [DemoNFT] = [
        DemoNFT(name: "Genesis Pass #0042", collection: "MTRX Genesis", floorPrice: 0.85, rarity: "Legendary", icon: "star.circle.fill", colors: [.accentPrimary, .blue]),
        DemoNFT(name: "Protocol Badge #128", collection: "MTRX Badges", floorPrice: 0.12, rarity: "Rare", icon: "shield.checkered", colors: [.purple, .pink]),
        DemoNFT(name: "DAO Founder #7", collection: "Governance NFTs", floorPrice: 2.1, rarity: "Epic", icon: "crown.fill", colors: [.orange, .red]),
    ]

    static let defiPositions: [DemoDefiPosition] = [
        DemoDefiPosition(protocol_: "Aave V3", type: "Lending", value: 2500.00, apy: 4.2, healthFactor: 2.8, icon: "building.columns"),
        DemoDefiPosition(protocol_: "Uniswap V3", type: "Liquidity", value: 1800.50, apy: 12.5, healthFactor: nil, icon: "arrow.left.arrow.right"),
    ]

    // MARK: - Discover

    static let featuredItems: [DemoFeaturedItem] = [
        DemoFeaturedItem(title: "Smart Escrow", subtitle: "Trustless payments for freelancers", category: "Contracts", icon: "doc.text.fill"),
        DemoFeaturedItem(title: "DAO Toolkit", subtitle: "Launch a DAO in minutes", category: "Governance", icon: "person.3.fill"),
        DemoFeaturedItem(title: "NFT Collection", subtitle: "Create and mint NFT collections", category: "NFTs", icon: "sparkles"),
        DemoFeaturedItem(title: "DeFi Dashboard", subtitle: "Monitor all your DeFi positions", category: "DeFi", icon: "chart.bar.fill"),
    ]

    // MARK: - Social Feed

    static let socialPosts: [DemoSocialPost] = [
        DemoSocialPost(author: "alice.eth", content: "Just deployed my first smart contract on MTRX. The escrow template is incredible.", likes: 42, timestamp: Date().addingTimeInterval(-1800)),
        DemoSocialPost(author: "bob.eth", content: "Staking rewards are looking great this month. 8.7% APY on MTRX tokens.", likes: 28, timestamp: Date().addingTimeInterval(-5400)),
        DemoSocialPost(author: "carol.eth", content: "Governance proposal #12 passed. New fee structure goes live next week.", likes: 156, timestamp: Date().addingTimeInterval(-14400)),
    ]

    // MARK: - Trinity Chat Responses

    static func trinityResponse(for input: String) -> String {
        let lowered = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if lowered.isEmpty {
            return "I'm Trinity, your AI financial assistant. How can I help you today?"
        }

        // Greetings
        if lowered.hasPrefix("hi") || lowered.hasPrefix("hello") || lowered.hasPrefix("hey") || lowered == "yo" || lowered == "sup" {
            return "Hey! I'm Trinity, your AI assistant in MTRX. I can help you manage your portfolio, send tokens, swap assets, check your NFTs, explore DeFi positions, and more. What would you like to do?"
        }

        // Balance / Portfolio
        if lowered.contains("balance") || lowered.contains("portfolio") || lowered.contains("worth") || lowered.contains("how much") {
            return "Your portfolio is valued at **$12,847.33**, up **4.2%** today.\n\n\u{2022} ETH: 2.847 ($8,934.21)\n\u{2022} USDC: 2,100.00 ($2,100.00)\n\u{2022} LINK: 61.2 ($891.07)\n\u{2022} AAVE: 5.3 ($476.89)\n\u{2022} UNI: 56.9 ($445.16)\n\nWant me to break it down further?"
        }

        // Send
        if lowered.contains("send") || lowered.contains("transfer") {
            return "I can help you send tokens. Just tell me:\n\n1. **Which token** (e.g., ETH, USDC)\n2. **How much** (e.g., 0.5 ETH)\n3. **To whom** (address or ENS name)\n\nOr tap the Send button in your wallet to get started."
        }

        // Swap
        if lowered.contains("swap") || lowered.contains("exchange") || lowered.contains("trade") {
            return "Ready to swap! You can exchange any token pair through integrated DEX aggregation.\n\nPopular swaps right now:\n\u{2022} ETH \u{2192} USDC (low slippage)\n\u{2022} ETH \u{2192} LINK (trending)\n\u{2022} USDC \u{2192} AAVE\n\nTap the Swap button or tell me what you'd like to swap."
        }

        // NFTs
        if lowered.contains("nft") {
            return "You own **3 NFTs** across 3 collections:\n\n\u{2022} Genesis Pass #0042 \u{2014} Floor: 0.85 ETH (Legendary)\n\u{2022} Protocol Badge #128 \u{2014} Floor: 0.12 ETH (Rare)\n\u{2022} DAO Founder #7 \u{2014} Floor: 2.1 ETH (Epic)\n\nTotal estimated value: **3.07 ETH** ($9,633.13)"
        }

        // Staking
        if lowered.contains("stake") || lowered.contains("staking") || lowered.contains("yield") {
            return "Your staking positions:\n\n\u{2022} **Aave V3 Lending** \u{2014} $2,500 at 4.2% APY\n\u{2022} **Uniswap V3 LP** \u{2014} $1,800 at 12.5% APY\n\nEstimated annual yield: **$330**\n\nWant to explore more staking opportunities?"
        }

        // Help
        if lowered.contains("help") || lowered.contains("what can you do") || lowered.contains("commands") {
            return "Here's what I can help with:\n\n\u{2022} **Portfolio** \u{2014} Check balances and performance\n\u{2022} **Send** \u{2014} Transfer tokens to any address\n\u{2022} **Swap** \u{2014} Exchange tokens via DEX\n\u{2022} **NFTs** \u{2014} View and manage your collection\n\u{2022} **Staking** \u{2014} DeFi positions and yields\n\u{2022} **Contracts** \u{2014} Deploy and manage smart contracts\n\u{2022} **Governance** \u{2014} DAO proposals and voting\n\nJust ask naturally \u{2014} I understand plain English."
        }

        // Gas / Fees
        if lowered.contains("gas") || lowered.contains("fee") {
            return "Current gas prices on Ethereum:\n\n\u{2022} \u{26A1} Fast: 28 gwei (~$2.10)\n\u{2022} \u{1F3CE}\u{FE0F} Standard: 22 gwei (~$1.65)\n\u{2022} \u{1F422} Slow: 15 gwei (~$1.12)\n\nGas is relatively low right now. Good time to transact!"
        }

        // Contract
        if lowered.contains("contract") || lowered.contains("deploy") {
            return "I can help you deploy smart contracts from our template library:\n\n\u{2022} **Escrow** \u{2014} Trustless payments\n\u{2022} **Token** \u{2014} ERC-20 token creation\n\u{2022} **NFT Collection** \u{2014} ERC-721 minting\n\u{2022} **DAO** \u{2014} Governance framework\n\u{2022} **Vesting** \u{2014} Token unlock schedules\n\nHead to the Create tab to get started."
        }

        // Default
        return "I can help you with that. What would you like to do first? You can ask about your portfolio, send or swap tokens, check your NFTs, explore DeFi, or deploy contracts."
    }
}

// MARK: - Demo Data Models

struct DemoToken: Identifiable {
    let id = UUID()
    let symbol: String
    let name: String
    let balance: Double
    let priceUSD: Double
    let change24h: Double
    let iconColor: Color
    var valueUSD: Double { balance * priceUSD }
}

struct DemoTransaction: Identifiable {
    let id = UUID()
    let type: TxKind
    let title: String
    let subtitle: String
    let amount: String
    let date: Date
    let status: TxState

    enum TxKind { case send, receive, swap, stake, contract }
    enum TxState { case confirmed, pending, failed }
}

struct DemoNFT: Identifiable {
    let id = UUID()
    let name: String
    let collection: String
    let floorPrice: Double
    let rarity: String
    let icon: String
    let colors: [Color]
}

struct DemoDefiPosition: Identifiable {
    let id = UUID()
    let protocol_: String
    let type: String
    let value: Double
    let apy: Double
    let healthFactor: Double?
    let icon: String
}

struct DemoFeaturedItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let category: String
    let icon: String
}

struct DemoSocialPost: Identifiable {
    let id = UUID()
    let author: String
    let content: String
    let likes: Int
    let timestamp: Date
}
