// Symbols.swift
// MTRX
//
// Centralized SF Symbols iconography organized by feature area.

import SwiftUI

// MARK: - SF Symbols

enum Symbols {

    // MARK: - Tab Bar

    static let home = "message.fill"
    static let discover = "safari"
    static let build = "hammer"
    static let social = "globe"
    static let account = "person.crop.circle"

    // MARK: - Navigation

    static let back = "chevron.left"
    static let forward = "chevron.right"
    static let close = "xmark"
    static let more = "ellipsis"
    static let moreCircle = "ellipsis.circle"
    static let search = "magnifyingglass"
    static let filter = "line.3.horizontal.decrease.circle"
    static let sort = "arrow.up.arrow.down"
    static let settings = "gearshape.fill"
    static let share = "square.and.arrow.up"
    static let qrCode = "qrcode"
    static let qrScanner = "qrcode.viewfinder"

    // MARK: - Trinity AI

    static let trinity = "brain.head.profile"
    static let trinityActive = "brain.head.profile.fill"
    static let sparkle = "sparkles"
    static let wand = "wand.and.stars"
    static let microphone = "mic.fill"
    static let microphoneSlash = "mic.slash.fill"
    static let textBubble = "text.bubble.fill"

    // MARK: - Wallet & Finance

    static let wallet = "wallet.pass.fill"
    static let portfolio = "chart.pie.fill"
    static let send = "arrow.up.circle.fill"
    static let receive = "arrow.down.circle.fill"
    static let swap = "arrow.left.arrow.right.circle.fill"
    static let bridge = "arrow.triangle.branch"
    static let stake = "lock.circle.fill"
    static let unstake = "lock.open.fill"
    static let token = "circle.circle.fill"
    static let nft = "square.stack.3d.up.fill"
    static let transaction = "arrow.left.arrow.right"
    static let gas = "fuelpump.fill"
    static let fee = "banknote.fill"

    // MARK: - Charts & Data

    static let chartLine = "chart.xyaxis.line"
    static let chartBar = "chart.bar.fill"
    static let chartPie = "chart.pie.fill"
    static let trendUp = "arrow.up.right"
    static let trendDown = "arrow.down.right"
    static let trendFlat = "arrow.right"

    // MARK: - Smart Contracts

    static let contract = "doc.text.fill"
    static let contractCreate = "doc.badge.plus"
    static let contractSign = "signature"
    static let contractActive = "doc.text.magnifyingglass"
    static let template = "doc.on.doc.fill"
    static let milestone = "flag.fill"
    static let milestone_complete = "flag.checkered"
    static let escrow = "lock.shield.fill"
    static let dispute = "exclamationmark.triangle.fill"

    // MARK: - Marketplace

    static let marketplace = "storefront.fill"
    static let listing = "tag.fill"
    static let listingNew = "tag.circle.fill"
    static let cart = "cart.fill"
    static let purchase = "creditcard.fill"
    static let auction = "hammer.circle.fill"
    static let bid = "hand.raised.fill"
    static let property = "building.2.fill"
    static let land = "map.fill"

    // MARK: - Fundraising

    static let fundraiser = "heart.circle.fill"
    static let donate = "gift.fill"
    static let goal = "target"
    static let progress = "chart.bar.xaxis"
    static let backers = "person.3.fill"
    static let reward = "star.fill"

    // MARK: - DAO & Governance

    static let dao = "building.columns.fill"
    static let proposal = "text.badge.checkmark"
    static let vote = "checkmark.seal.fill"
    static let voteYes = "hand.thumbsup.fill"
    static let voteNo = "hand.thumbsdown.fill"
    static let voteAbstain = "minus.circle.fill"
    static let delegate = "person.badge.key.fill"
    static let treasury = "banknote.fill"
    static let quorum = "person.3.sequence.fill"

    // MARK: - Social & Messaging

    static let post = "square.and.pencil"
    static let comment = "bubble.left.fill"
    static let like = "heart.fill"
    static let repost = "arrow.2.squarepath"
    static let message = "envelope.fill"
    static let messageEncrypted = "lock.fill"
    static let groupChat = "person.2.fill"
    static let attachment = "paperclip"
    static let emoji = "face.smiling.fill"

    // MARK: - Notifications & Alerts

    static let notification = "bell.fill"
    static let notificationBadge = "bell.badge.fill"
    static let alertWarning = "exclamationmark.triangle.fill"
    static let alertCritical = "exclamationmark.octagon.fill"
    static let alertInfo = "info.circle.fill"
    static let alertSuccess = "checkmark.circle.fill"

    // MARK: - Security & Privacy

    static let shield = "shield.fill"
    static let shieldCheck = "shield.checkered"
    static let privacy = "hand.raised.slash.fill"
    static let biometric = "faceid"
    static let key = "key.fill"
    static let lock = "lock.fill"
    static let unlock = "lock.open.fill"
    static let zeroKnowledge = "eye.slash.fill"
    static let encrypted = "lock.shield.fill"
    static let verified = "checkmark.seal.fill"

    // MARK: - Insurance

    static let insurance = "umbrella.fill"
    static let claim = "doc.text.below.ecg"
    static let payout = "dollarsign.arrow.circlepath"
    static let weatherEvent = "cloud.bolt.fill"
    static let coverage = "shield.lefthalf.filled"

    // MARK: - Status

    static let pending = "clock.fill"
    static let processing = "arrow.triangle.2.circlepath"
    static let complete = "checkmark.circle.fill"
    static let failed = "xmark.circle.fill"
    static let cancelled = "nosign"

    // MARK: - Accessibility

    static let accessibility = "accessibility"
    static let voiceOver = "speaker.wave.3.fill"
    static let dynamicType = "textformat.size"
    static let switchControl = "hand.point.up.left.fill"
    static let reduceMotion = "figure.walk"

    // MARK: - Misc

    static let copy = "doc.on.doc"
    static let paste = "doc.on.clipboard"
    static let refresh = "arrow.clockwise"
    static let externalLink = "arrow.up.right.square"
    static let add = "plus"
    static let addCircle = "plus.circle.fill"
    static let remove = "minus.circle.fill"
    static let edit = "pencil"
    static let delete = "trash.fill"
    static let camera = "camera.fill"
    static let photo = "photo.fill"
    static let location = "location.fill"
    static let calendar = "calendar"
    static let clock = "clock"
    static let link = "link"
    static let globe = "globe"
    static let info = "info.circle"
    static let help = "questionmark.circle"
}

// MARK: - Symbol Image Convenience

extension Image {
    static func mtrx(_ symbol: String) -> Image {
        Image(systemName: symbol)
    }
}

// MARK: - Symbol Configuration

extension View {
    func mtrxSymbolStyle(size: CGFloat = 20, weight: Font.Weight = .medium) -> some View {
        self
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.hierarchical)
    }

    func mtrxSymbolVariant(_ variant: SymbolVariants = .fill) -> some View {
        self.symbolVariant(variant)
    }
}
