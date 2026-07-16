// TrinityAppTools.swift
// MTRX — Trinity
//
// App-action tools the on-device model can call (Foundation Models tool
// calling, iOS 26+). These are wired ONLY into Trinity's session (not Neo /
// Morpheus). Two honesty tiers:
//
//   LIVE NOW (genuinely act on-device): playMusic, controlMusic, openTab,
//     setTheme, updateProfile, createPost.
//   HONEST-PENDING (need the on-chain backend, which isn't connected): moveFunds,
//     deployContract — these REPORT that they can't execute yet. They never
//     fake a result. getPortfolio reads the current state but flags demo data.

import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)

// MARK: - Music (LIVE)

@available(iOS 26.0, macOS 26.0, *)
struct TrinityMusicTool: Tool {
    let name = "playMusic"
    let description = """
    Play music on Apple Music. Call when the user wants to hear, play, or put \
    on a song, artist, album, or vibe. Pass what they asked for in their words.
    """
    @Generable
    struct Arguments {
        @Guide(description: "What to play — a song, artist, album, or mood, e.g. 'Drake', 'lofi beats'.")
        var query: String
    }
    func call(arguments: Arguments) async throws -> String {
        let outcome = await MusicKitManager.shared.play(query: arguments.query)
        return outcome.message
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct TrinityMusicControlTool: Tool {
    let name = "controlMusic"
    let description = "Control current Apple Music playback: pause, resume, skip to next, or go to previous track."
    @Generable
    struct Arguments {
        @Guide(description: "One of: pause, resume, next, previous")
        var action: String
    }
    @MainActor
    func call(arguments: Arguments) async throws -> String {
        let music = MusicKitManager.shared
        switch arguments.action.lowercased() {
        case "pause":
            if music.isPlaying { music.togglePlayPause(); return "Paused." }
            return music.hasNowPlaying ? "Already paused." : "Nothing is playing right now."
        case "resume", "play":
            guard music.hasNowPlaying else { return "Nothing is queued — tell me what to play." }
            if !music.isPlaying { music.togglePlayPause() }
            return "Playing."
        case "next", "skip":
            guard music.hasNowPlaying else { return "Nothing is playing to skip." }
            music.skipNext(); return "Skipped to the next track."
        case "previous", "back":
            guard music.hasNowPlaying else { return "Nothing is playing." }
            music.skipPrevious(); return "Went back a track."
        default:
            return "Unknown music action."
        }
    }
}

// MARK: - Navigation (LIVE)

@available(iOS 26.0, macOS 26.0, *)
struct TrinityNavigateTool: Tool {
    let name = "openTab"
    let description = """
    Open one of the app's five tabs for the user: discover (marketplace, DeFi & \
    real-world assets), create (smart contracts), home (dashboard), social \
    (feed, posts, messages), account (wallet & settings). Call when they ask to \
    go to, open, or show one.
    """
    @Generable
    struct Arguments {
        @Guide(description: "One of: discover, create, home, social, account")
        var tab: String
    }
    @MainActor
    func call(arguments: Arguments) async throws -> String {
        // "build" kept as a legacy alias for the renamed Create tab (index 1).
        let map = ["discover": 0, "create": 1, "build": 1, "home": 2, "social": 3, "account": 4]
        guard let index = map[arguments.tab.lowercased()] else {
            return "I can open Discover, Create, Home, Social, or Account. Which one?"
        }
        // Keep Trinity docked as the floating orb after she navigates, and switch the
        // tab after a short beat so her confirmation reply streams in first, then the
        // chat folds into the orb. Mirrors the scripted navigate(to:) path.
        AgentPresence.shared.dock(.trinity)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            NotificationCenter.default.post(name: .mtrxSwitchTab, object: nil, userInfo: ["index": index])
        }
        let canonical = ["Discover", "Create", "Home", "Social", "Account"][index]
        return "Opened the \(canonical) tab."
    }
}

// MARK: - Profile / theme / post (LIVE — real local app state)

@available(iOS 26.0, macOS 26.0, *)
struct TrinityThemeTool: Tool {
    let name = "setTheme"
    let description = "Change the user's app accent theme color. Call when they ask to set or change their theme."
    @Generable
    struct Arguments {
        @Guide(description: "The theme color name, e.g. 'violet', 'cyan'.")
        var color: String
    }
    @MainActor
    func call(arguments: Arguments) async throws -> String {
        let want = arguments.color.lowercased()
        for preset in SocialTheme.presets {
            let key = preset.name.lowercased()
            if key.contains(want) || want.contains(key) {
                SocialTheme.shared.set(preset.color)
                return "Theme set to \(preset.name)."
            }
        }
        return "I can set these themes: \(SocialTheme.presets.map(\.name).joined(separator: ", ")). Which one?"
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct TrinityProfileTool: Tool {
    let name = "updateProfile"
    let description = "Update the user's social profile — their bio or their username/handle."
    @Generable
    struct Arguments {
        @Guide(description: "Which field: 'bio' or 'handle'")
        var field: String
        @Guide(description: "The new value")
        var value: String
    }
    @MainActor
    func call(arguments: Arguments) async throws -> String {
        switch arguments.field.lowercased() {
        case "bio":
            SocialIdentity.shared.bio = arguments.value
            return "Your bio now reads: \"\(arguments.value)\"."
        case "handle", "username":
            let cleaned = arguments.value.replacingOccurrences(of: " ", with: "").lowercased()
            SocialIdentity.shared.username = cleaned
            let shown = cleaned.hasPrefix("@") ? cleaned : "@" + cleaned
            return "You're \(shown) now."
        default:
            return "I can update your bio or your handle — which one?"
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct TrinityPostTool: Tool {
    let name = "createPost"
    let description = "Publish a post to the user's social feed. Pass the exact text to post."
    @Generable
    struct Arguments {
        @Guide(description: "The post text to publish.")
        var text: String
    }
    @MainActor
    func call(arguments: Arguments) async throws -> String {
        let social = SocialViewModel.shared
        social.composerText = arguments.text
        social.composerImageData = nil
        social.composerVideoFileName = nil
        social.composerLink = ""
        social.attachProof = false
        social.publishPost(displayName: UserDefaults.standard.string(forKey: "displayName") ?? "You")
        social.composerText = ""
        return "Posted to your feed: \"\(arguments.text)\""
    }
}

// MARK: - Money / contracts (HONEST-PENDING — needs the on-chain backend)

@available(iOS 26.0, macOS 26.0, *)
struct TrinityTransactionTool: Tool {
    let name = "moveFunds"
    let description = """
    Send, swap, or stake crypto, or send cash. Call when the user asks to move \
    money. This reports honestly whether it can actually execute — it never \
    moves funds silently and never fakes a transfer.
    """
    @Generable
    struct Arguments {
        @Guide(description: "What the user wants to do, in their words, e.g. 'send 0.1 ETH to alice.eth'.")
        var request: String
    }
    func call(arguments: Arguments) async throws -> String {
        if PendingCredentials.isChainConfigured {
            return """
            For security, every transfer goes through MTRX's on-device \
            confirmation with Face ID — I won't move funds silently. Tell the \
            user to type it as a request (e.g. "send 0.1 ETH to alice.eth") and \
            the app will walk them through the secure approval.
            """
        }
        return """
        Tell the user honestly: I can't actually move funds yet. MTRX's \
        on-chain backend isn't connected on this build, so there's no live \
        wallet to send from — I won't pretend a transfer happened. Once the \
        network is connected I'll be able to do this for real, with Face ID \
        approval.
        """
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct TrinityDeployTool: Tool {
    let name = "deployContract"
    let description = "Deploy or manage a smart contract. Reports honestly whether it can execute yet — never fakes a deployment."
    @Generable
    struct Arguments {
        @Guide(description: "What contract the user wants, in their words.")
        var request: String
    }
    func call(arguments: Arguments) async throws -> String {
        if PendingCredentials.isChainConfigured {
            return "Tell the user deployment runs through the Create tab's guided flow so they can review gas and confirm — I won't deploy silently. Offer to open Create."
        }
        return """
        Tell the user honestly: I can't deploy a contract yet — the on-chain \
        backend isn't connected on this build, so there's nothing to deploy to. \
        I won't fake it. Once the network's live, this works for real.
        """
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct TrinityPortfolioTool: Tool {
    let name = "getPortfolio"
    let description = "Get the user's current portfolio value and top holdings. Call when they ask about their balance, portfolio, or holdings."
    @Generable
    struct Arguments {}
    func call(arguments: Arguments) async throws -> String {
        guard let snap = WidgetSharedStore.portfolio() else {
            return "I can't read the portfolio right now — tell the user to open Home or Wallet so it loads."
        }
        let holdings = snap.tokens.prefix(3).map { "\($0.symbol) \($0.value)" }.joined(separator: ", ")
        let caveat = PendingCredentials.isBackendConfigured
            ? ""
            : " Note for you: these are sample/demo balances — the live on-chain backend isn't connected, so this isn't real money. Say so if you report it."
        return "Portfolio total \(snap.totalValue), \(snap.changePercent) today. Top holdings: \(holdings).\(caveat)"
    }
}

#endif
