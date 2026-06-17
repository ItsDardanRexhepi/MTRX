// SolitaireGameView.swift
// MTRX
//
// A complete, fully playable Klondike Solitaire (the public-domain card
// game). Tap-to-move interaction, auto-collect, real win detection, score,
// moves and a timer. Built for ProMotion: spring-animated moves, liquid-glass
// chrome, and a clean San-Francisco-modern aesthetic.

import SwiftUI

// MARK: - Card Model

enum CardSuit: Int, CaseIterable {
    case spades, hearts, diamonds, clubs
    var symbol: String {
        switch self {
        case .spades:   return "suit.spade.fill"
        case .hearts:   return "suit.heart.fill"
        case .diamonds: return "suit.diamond.fill"
        case .clubs:    return "suit.club.fill"
        }
    }
    var isRed: Bool { self == .hearts || self == .diamonds }
}

struct SolitaireCard: Identifiable, Equatable {
    let id = UUID()
    let rank: Int          // 1 = A … 13 = K
    let suit: CardSuit
    var faceUp: Bool = false

    var isRed: Bool { suit.isRed }
    var rankLabel: String {
        switch rank {
        case 1:  return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }
    static func == (a: SolitaireCard, b: SolitaireCard) -> Bool { a.id == b.id }
}

// MARK: - Engine

@MainActor
final class SolitaireEngine: ObservableObject {

    /// Identifies a pile (and, for the tableau, a card within it).
    struct Selection: Equatable {
        enum Source: Equatable {
            case waste
            case tableau(Int)
            case foundation(Int)
        }
        let source: Source
        let cardIndex: Int
    }

    @Published var stock: [SolitaireCard] = []
    @Published var waste: [SolitaireCard] = []
    @Published var foundations: [[SolitaireCard]] = [[], [], [], []]
    @Published var tableau: [[SolitaireCard]] = Array(repeating: [], count: 7)
    @Published var selection: Selection?

    @Published var moves = 0
    @Published var score = 0
    @Published var seconds = 0
    @Published var won = false

    private var timer: Timer?
    private let move = Animation.spring(response: 0.34, dampingFraction: 0.82)

    init() { newGame() }

    // MARK: Setup

    func newGame() {
        var deck: [SolitaireCard] = []
        for suit in CardSuit.allCases {
            for rank in 1...13 { deck.append(SolitaireCard(rank: rank, suit: suit)) }
        }
        deck.shuffle()

        stock = []; waste = []
        foundations = [[], [], [], []]
        tableau = Array(repeating: [], count: 7)
        moves = 0; score = 0; seconds = 0; won = false; selection = nil

        var idx = 0
        for col in 0..<7 {
            for row in 0...col {
                var c = deck[idx]; idx += 1
                c.faceUp = (row == col)
                tableau[col].append(c)
            }
        }
        while idx < deck.count {
            var c = deck[idx]; idx += 1
            c.faceUp = false
            stock.append(c)
        }
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.won else { return }
                self.seconds += 1
            }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    // MARK: Rules

    func canPlaceOnFoundation(_ card: SolitaireCard, _ f: Int) -> Bool {
        guard f >= 0, f < 4 else { return false }
        if let top = foundations[f].last { return top.suit == card.suit && card.rank == top.rank + 1 }
        return card.rank == 1
    }

    func canPlaceOnTableau(_ card: SolitaireCard, _ col: Int) -> Bool {
        guard col >= 0, col < 7 else { return false }
        if let top = tableau[col].last { return top.faceUp && top.isRed != card.isRed && top.rank == card.rank + 1 }
        return card.rank == 13
    }

    private func selectedGroup() -> [SolitaireCard]? {
        guard let sel = selection else { return nil }
        switch sel.source {
        case .waste:           return waste.last.map { [$0] }
        case .foundation(let f): return foundations[f].last.map { [$0] }
        case .tableau(let c):
            guard sel.cardIndex < tableau[c].count else { return nil }
            return Array(tableau[c][sel.cardIndex...])
        }
    }

    private func removeSelectedFromSource() {
        guard let sel = selection else { return }
        switch sel.source {
        case .waste:           if !waste.isEmpty { waste.removeLast() }
        case .foundation(let f): if !foundations[f].isEmpty { foundations[f].removeLast() }
        case .tableau(let c):
            guard sel.cardIndex < tableau[c].count else { return }
            tableau[c].removeSubrange(sel.cardIndex...)
            if var top = tableau[c].last, !top.faceUp {
                top.faceUp = true
                tableau[c][tableau[c].count - 1] = top
                score += 5
            }
        }
    }

    @discardableResult
    private func moveSelection(toTableau col: Int) -> Bool {
        guard let group = selectedGroup(), let bottom = group.first,
              canPlaceOnTableau(bottom, col) else { return false }
        withAnimation(move) {
            removeSelectedFromSource()
            tableau[col].append(contentsOf: group)
            selection = nil
        }
        afterMove()
        return true
    }

    @discardableResult
    private func moveSelection(toFoundation f: Int) -> Bool {
        guard let group = selectedGroup(), group.count == 1, let card = group.first,
              canPlaceOnFoundation(card, f) else { return false }
        withAnimation(move) {
            removeSelectedFromSource()
            foundations[f].append(card)
            selection = nil
        }
        score += 10
        afterMove()
        return true
    }

    private func afterMove() {
        moves += 1
        MtrxHaptics.impact(.light)
        checkWin()
    }

    private func checkWin() {
        if foundations.allSatisfy({ $0.count == 13 }) {
            won = true
            stop()
            MtrxHaptics.success()
        }
    }

    // MARK: Tap handling

    func tapStock() {
        selection = nil
        if stock.isEmpty {
            guard !waste.isEmpty else { return }
            withAnimation(move) {
                stock = waste.reversed().map { var c = $0; c.faceUp = false; return c }
                waste = []
            }
            moves += 1
            MtrxHaptics.impact(.light)
            return
        }
        withAnimation(move) {
            var c = stock.removeLast()
            c.faceUp = true
            waste.append(c)
        }
        moves += 1
        MtrxHaptics.impact(.light)
    }

    private func sameSource(_ a: Selection.Source, _ b: Selection.Source) -> Bool {
        switch (a, b) {
        case (.waste, .waste): return true
        case let (.tableau(x), .tableau(y)): return x == y
        case let (.foundation(x), .foundation(y)): return x == y
        default: return false
        }
    }

    /// Tap on a specific card. Selects it, moves the current selection onto its
    /// pile, or deselects — whichever is appropriate.
    func cardTapped(_ source: Selection.Source, _ index: Int) {
        if let sel = selection, !sameSource(sel.source, source) {
            if moveSelectionTo(source) { return }   // tried as a destination
        }
        if let sel = selection, sameSource(sel.source, source) {
            if case .tableau(let c) = source, case .tableau = sel.source,
               sel.cardIndex != index, tableau[c][index].faceUp {
                select(source, index); return
            }
            selection = nil
            return
        }
        select(source, index)
    }

    /// Tap on an empty pile slot (used as a move destination).
    func emptyTapped(_ dest: Selection.Source) {
        guard selection != nil else { return }
        _ = moveSelectionTo(dest)
    }

    private func moveSelectionTo(_ dest: Selection.Source) -> Bool {
        switch dest {
        case .tableau(let c):    return moveSelection(toTableau: c)
        case .foundation(let f): return moveSelection(toFoundation: f)
        case .waste:             return false
        }
    }

    private func select(_ source: Selection.Source, _ index: Int) {
        switch source {
        case .waste:
            guard !waste.isEmpty else { return }
            selection = Selection(source: .waste, cardIndex: waste.count - 1)
        case .foundation(let f):
            guard !foundations[f].isEmpty else { return }
            selection = Selection(source: .foundation(f), cardIndex: foundations[f].count - 1)
        case .tableau(let c):
            guard index < tableau[c].count, tableau[c][index].faceUp else { return }
            selection = Selection(source: .tableau(c), cardIndex: index)
        }
        MtrxHaptics.selection()
    }

    // MARK: Auto-collect

    /// Sweep every card that can go up to a foundation, one cascading step at a
    /// time — great for finishing a solved board.
    func autoCollect() {
        if autoStep() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in self?.autoCollect() }
        } else {
            selection = nil
        }
    }

    private func autoStep() -> Bool {
        if let c = waste.last {
            for f in 0..<4 where canPlaceOnFoundation(c, f) {
                selection = Selection(source: .waste, cardIndex: waste.count - 1)
                return moveSelection(toFoundation: f)
            }
        }
        for col in 0..<7 {
            if let c = tableau[col].last, c.faceUp {
                for f in 0..<4 where canPlaceOnFoundation(c, f) {
                    selection = Selection(source: .tableau(col), cardIndex: tableau[col].count - 1)
                    return moveSelection(toFoundation: f)
                }
            }
        }
        return false
    }

    var timeLabel: String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Card View

struct PlayingCardView: View {
    let card: SolitaireCard
    let w: CGFloat
    let h: CGFloat
    var selected: Bool = false
    var accent: Color = .cyan

    private var ink: Color {
        card.isRed ? Color(red: 0.87, green: 0.17, blue: 0.27) : Color(red: 0.11, green: 0.12, blue: 0.16)
    }

    var body: some View {
        ZStack {
            if card.faceUp {
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.92)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 0.7))

                // The rank alone sits in the corner; the suit shows once, in
                // the centre — no redundant second suit symbol.
                VStack {
                    HStack(alignment: .top) {
                        Text(card.rankLabel)
                            .font(.system(size: h * 0.28, weight: .bold, design: .rounded))
                            .foregroundStyle(ink)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.leading, w * 0.15)
                .padding(.top, h * 0.08)

                Image(systemName: card.suit.symbol)
                    .font(.system(size: h * 0.32))
                    .foregroundStyle(ink.opacity(0.9))
            } else {
                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.46, blue: 0.56),
                                                  Color(red: 0.05, green: 0.18, blue: 0.30)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1))
                    .overlay(
                        RoundedRectangle(cornerRadius: w * 0.10, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                            .padding(w * 0.16)
                    )
                    .overlay(Image(systemName: "suit.spade.fill")
                        .font(.system(size: h * 0.28))
                        .foregroundStyle(.white.opacity(0.20)))
            }
        }
        .frame(width: w, height: h)
        .overlay(
            RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                .stroke(accent, lineWidth: 2.5)
                .opacity(selected ? 1 : 0)
        )
        .shadow(color: .black.opacity(0.32), radius: 2.5, y: 1.5)
        .scaleEffect(selected ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

// MARK: - Game View

struct SolitaireGameView: View {
    var accent: Color = Color(red: 0.13, green: 0.83, blue: 0.93)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = SolitaireEngine()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.backgroundPrimary, Color(red: 0.04, green: 0.12, blue: 0.10), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.10), .clear], center: .top, startRadius: 4, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: Spacing.sm) {
                header
                statBar
                board
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.xs)

            if engine.won { winOverlay }
        }
        .onDisappear { engine.stop() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            roundButton("xmark") { dismiss() }
            Spacer()
            Text("Solitaire")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            roundButton("arrow.clockwise") {
                withAnimation(.easeInOut(duration: 0.25)) { engine.newGame() }
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func roundButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { MtrxHaptics.impact(.light); action() }) {
            Image(systemName: symbol)
                .accessibilityLabel(symbol == "xmark" ? "Close game" : symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .mtrxLiquidGlass(cornerRadius: 19)
        }
        .buttonStyle(.plain)
    }

    private var statBar: some View {
        HStack(spacing: Spacing.md) {
            stat("TIME", engine.timeLabel)
            stat("MOVES", "\(engine.moves)")
            stat("SCORE", "\(engine.score)")
            Spacer()
            Button {
                MtrxHaptics.impact(.medium)
                engine.autoCollect()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "wand.and.stars").font(.system(size: 12, weight: .bold))
                    Text("Auto").font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            // Always size to its one-line content — never let the stat bar
            // squeeze it into wrapping "Aut / o".
            .fixedSize()
        }
        .padding(.horizontal, Spacing.xs)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 8, weight: .bold)).kerning(0.8).foregroundStyle(Color.labelTertiary)
            Text(value).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
    }

    // MARK: Board

    private var board: some View {
        GeometryReader { geo in
            let gap: CGFloat = 5
            let cardW = (geo.size.width - gap * 6) / 7
            let cardH = cardW * 1.4
            VStack(spacing: Spacing.sm) {
                topRow(cardW: cardW, cardH: cardH, gap: gap)
                tableauRow(cardW: cardW, cardH: cardH, gap: gap)
                Spacer(minLength: 0)
            }
        }
    }

    private func topRow(cardW: CGFloat, cardH: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            stockSlot(cardW: cardW, cardH: cardH)
            wasteSlot(cardW: cardW, cardH: cardH)
            Color.clear.frame(width: cardW, height: cardH)
            ForEach(0..<4, id: \.self) { f in
                foundationSlot(f, cardW: cardW, cardH: cardH)
            }
        }
    }

    private func slotBackground(_ w: CGFloat, _ h: CGFloat, symbol: String? = nil) -> some View {
        RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1))
            .overlay {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: h * 0.30)).foregroundStyle(.white.opacity(0.18))
                }
            }
            .frame(width: w, height: h)
    }

    private func stockSlot(cardW: CGFloat, cardH: CGFloat) -> some View {
        Button {
            engine.tapStock()
        } label: {
            ZStack {
                if let top = engine.stock.last {
                    PlayingCardView(card: top, w: cardW, h: cardH, accent: accent)
                } else {
                    slotBackground(cardW, cardH, symbol: "arrow.clockwise")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func wasteSlot(cardW: CGFloat, cardH: CGFloat) -> some View {
        ZStack {
            if let top = engine.waste.last {
                PlayingCardView(card: top, w: cardW, h: cardH,
                                selected: isSelected(.waste, engine.waste.count - 1), accent: accent)
                    .onTapGesture { engine.cardTapped(.waste, engine.waste.count - 1) }
            } else {
                slotBackground(cardW, cardH)
            }
        }
    }

    private func foundationSlot(_ f: Int, cardW: CGFloat, cardH: CGFloat) -> some View {
        ZStack {
            if let top = engine.foundations[f].last {
                PlayingCardView(card: top, w: cardW, h: cardH,
                                selected: isSelected(.foundation(f), engine.foundations[f].count - 1), accent: accent)
            } else {
                slotBackground(cardW, cardH, symbol: CardSuit(rawValue: f)?.symbol ?? "suit.spade.fill")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if engine.selection != nil { engine.emptyTapped(.foundation(f)) }
            else { engine.cardTapped(.foundation(f), engine.foundations[f].count - 1) }
        }
    }

    private func tableauRow(cardW: CGFloat, cardH: CGFloat, gap: CGFloat) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<7, id: \.self) { col in
                column(col, cardW: cardW, cardH: cardH)
            }
        }
    }

    private func column(_ col: Int, cardW: CGFloat, cardH: CGFloat) -> some View {
        let cards = engine.tableau[col]
        // Face-up cards fan enough that a stacked card's rank stays fully
        // readable above the card on top of it — no cramped clusters.
        let faceUpFan = cardH * 0.40
        let faceDownFan = cardH * 0.17
        return ZStack(alignment: .top) {
            // Empty-column drop target.
            slotBackground(cardW, cardH)
                .opacity(cards.isEmpty ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { engine.emptyTapped(.tableau(col)) }

            ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                PlayingCardView(card: card, w: cardW, h: cardH,
                                selected: isSelected(.tableau(col), idx, groupable: true), accent: accent)
                    .offset(y: yOffset(cards, idx, faceUpFan: faceUpFan, faceDownFan: faceDownFan))
                    .zIndex(Double(idx))
                    .onTapGesture { engine.cardTapped(.tableau(col), idx) }
            }
        }
        .frame(width: cardW, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func yOffset(_ cards: [SolitaireCard], _ idx: Int, faceUpFan: CGFloat, faceDownFan: CGFloat) -> CGFloat {
        var y: CGFloat = 0
        for i in 0..<idx { y += cards[i].faceUp ? faceUpFan : faceDownFan }
        return y
    }

    // Highlights the selected card and, for a tableau run, every card on top of it.
    private func isSelected(_ source: SolitaireEngine.Selection.Source, _ index: Int, groupable: Bool = false) -> Bool {
        guard let sel = engine.selection else { return false }
        switch (sel.source, source) {
        case (.waste, .waste): return true
        case let (.foundation(a), .foundation(b)): return a == b
        case let (.tableau(a), .tableau(b)):
            return a == b && (groupable ? index >= sel.cardIndex : index == sel.cardIndex)
        default: return false
        }
    }

    // MARK: Win

    private var winOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Image(systemName: "trophy.fill").font(.system(size: 54)).foregroundStyle(accent)
                Text("You won!").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(engine.moves) moves · \(engine.timeLabel) · \(engine.score) pts")
                    .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                Button {
                    MtrxHaptics.impact(.medium)
                    withAnimation(.easeInOut(duration: 0.25)) { engine.newGame() }
                } label: {
                    Text("New Game")
                        .font(.mtrxCalloutBold).foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, Spacing.xl).padding(.vertical, Spacing.ms)
                        .background(accent).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button("Leave") { dismiss() }
                    .font(.mtrxCalloutBold).foregroundStyle(Color.labelSecondary).padding(.top, Spacing.xs)
            }
            .padding(Spacing.xl)
            .mtrxLiquidGlass(cornerRadius: 28)
            .padding(Spacing.xl)
        }
    }
}
