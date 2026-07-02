// ColorBurstGameView.swift
// MTRX
//
// Color Burst — an original match-3 swap puzzle. Swap two adjacent gems to
// line up three or more of a colour; they burst, the gems above fall to fill
// the gap, fresh gems drop in, and chains cascade for bonus points. MTRX's own
// look: liquid-glass gems over a soft grid, a modern palette, ProMotion-smooth
// falls and bursts. Fully on-device.

import SwiftUI

// MARK: - Gem

struct Gem: Identifiable, Equatable {
    let id = UUID()
    var color: Int      // 1...colorCount
    var row: Int
    var col: Int
}

enum ColorBurst {
    /// MTRX's own candy palette — not a copy of any existing game's colours.
    static let palette: [Color] = [
        Color(red: 0.98, green: 0.37, blue: 0.45),  // 1 — red
        Color(red: 0.99, green: 0.63, blue: 0.31),  // 2 — orange
        Color(red: 0.99, green: 0.84, blue: 0.39),  // 3 — yellow
        Color(red: 0.41, green: 0.87, blue: 0.55),  // 4 — green
        Color(red: 0.37, green: 0.71, blue: 0.99),  // 5 — blue
        Color(red: 0.75, green: 0.53, blue: 0.99)   // 6 — purple
    ]
    static func color(_ i: Int) -> Color {
        (i >= 1 && i <= palette.count) ? palette[i - 1] : .clear
    }
}

// MARK: - Levels

/// A ColorBurst level: reach `target` points within `moves` swaps.
struct ColorBurstLevel {
    let target: Int
    let moves: Int
}

enum ColorBurstLevels {
    /// Hybrid: a smooth difficulty formula with a few milestone "boss" overrides
    /// so 25 and 50 feel like a real step up. Move budget tightens as levels
    /// climb, so late levels demand cascades, not just more taps.
    static func level(_ n: Int) -> ColorBurstLevel {
        let lvl = max(1, min(50, n))
        // Move budget: generous early, tighter late (difficulty from efficiency).
        let moves: Int
        switch lvl {
        case 1...10:  moves = 26
        case 11...20: moves = 24
        case 21...30: moves = 22
        case 31...40: moves = 20
        default:      moves = 18
        }
        // Target: linear base + a gentle acceleration past the midpoint.
        var target = 200 + (lvl - 1) * 80 + max(0, lvl - 25) * 30
        // Sparse milestone overrides.
        switch lvl {
        case 25: target = 2600   // mid boss
        case 50: target = 5200   // final boss
        default: break
        }
        return ColorBurstLevel(target: target, moves: moves)
    }
}

// MARK: - Engine

@MainActor
final class ColorBurstEngine: ObservableObject {
    static let cols = 7
    static let rows = 8
    static let colorCount = 6

    @Published var gems: [Gem] = []
    @Published var score = 0
    @Published var moves = 0
    @Published var selected: UUID?
    @Published private(set) var busy = false

    @Published var level = 1
    @Published var targetScore = 0
    @Published var moveBudget = 0
    @Published var won = false
    @Published var gameOver = false
    private(set) var startLevel = 1

    /// Begin a run at the chosen (unlocked) level.
    func start(at level: Int) {
        startLevel = max(1, level)
        self.level = max(1, level)
        let def = ColorBurstLevels.level(self.level)
        targetScore = def.target
        moveBudget = def.moves
        score = 0; moves = 0; selected = nil; busy = false
        won = false; gameOver = false
        gems = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                var color = Int.random(in: 1...Self.colorCount)
                while wouldMatchOnFill(r: r, c: c, color: color) {
                    color = Int.random(in: 1...Self.colorCount)
                }
                gems.append(Gem(color: color, row: r, col: c))
            }
        }
    }

    /// Retry the level this run started on.
    func retry() { start(at: startLevel) }

    /// Win/lose check, called once a move's cascades have fully settled.
    private func checkOutcome() {
        guard !won, !gameOver else { return }
        if score >= targetScore {
            won = true
            GameProgress.shared.recordCompletion(level: level, in: .colorburst)
            MtrxHaptics.success()
        } else if moves >= moveBudget {
            gameOver = true
            MtrxHaptics.error()
        }
    }

    private func gemAt(_ r: Int, _ c: Int) -> Gem? { gems.first { $0.row == r && $0.col == c } }
    private func index(_ id: UUID) -> Int? { gems.firstIndex { $0.id == id } }

    private func wouldMatchOnFill(r: Int, c: Int, color: Int) -> Bool {
        if c >= 2, gemAt(r, c - 1)?.color == color, gemAt(r, c - 2)?.color == color { return true }
        if r >= 2, gemAt(r - 1, c)?.color == color, gemAt(r - 2, c)?.color == color { return true }
        return false
    }

    // MARK: Input

    func tap(_ id: UUID) {
        guard !busy, !won, !gameOver, let g = gems.first(where: { $0.id == id }) else { return }
        guard let selID = selected, let sel = gems.first(where: { $0.id == selID }) else {
            selected = id
            MtrxHaptics.selection()
            return
        }
        if selID == id { selected = nil; return }
        if abs(sel.row - g.row) + abs(sel.col - g.col) == 1 {
            selected = nil
            attemptSwap(sel.id, g.id)
        } else {
            selected = id
            MtrxHaptics.selection()
        }
    }

    private func swap(_ id1: UUID, _ id2: UUID) {
        guard let i = index(id1), let j = index(id2) else { return }
        let r = gems[i].row, c = gems[i].col
        gems[i].row = gems[j].row; gems[i].col = gems[j].col
        gems[j].row = r; gems[j].col = c
    }

    private func attemptSwap(_ id1: UUID, _ id2: UUID) {
        busy = true
        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) { swap(id1, id2) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            guard let self else { return }
            if self.matches().isEmpty {
                // No match — swap back.
                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) { self.swap(id1, id2) }
                MtrxHaptics.error()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { self.busy = false }
            } else {
                self.moves += 1
                self.resolve(chain: 1)
            }
        }
    }

    // MARK: Matching & cascades

    private func matches() -> Set<UUID> {
        var out = Set<UUID>()
        func scan(_ line: [Gem?]) {
            var run: [Gem] = []
            for cell in line {
                if let g = cell, let last = run.last, last.color == g.color {
                    run.append(g)
                } else {
                    if run.count >= 3 { out.formUnion(run.map { $0.id }) }
                    run = cell.map { [$0] } ?? []
                }
            }
            if run.count >= 3 { out.formUnion(run.map { $0.id }) }
        }
        for r in 0..<Self.rows { scan((0..<Self.cols).map { gemAt(r, $0) }) }
        for c in 0..<Self.cols { scan((0..<Self.rows).map { gemAt($0, c) }) }
        return out
    }

    private func resolve(chain: Int) {
        let m = matches()
        if m.isEmpty { busy = false; checkOutcome(); return }
        score += m.count * 10 * chain
        MtrxHaptics.impact(chain > 1 ? .medium : .light)
        withAnimation(.easeOut(duration: 0.18)) {
            gems.removeAll { m.contains($0.id) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            guard let self else { return }
            self.collapseAndRefill()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                self.resolve(chain: chain + 1)
            }
        }
    }

    private func collapseAndRefill() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            for c in 0..<Self.cols {
                let survivors = gems.filter { $0.col == c }.sorted { $0.row > $1.row }
                for (k, gem) in survivors.enumerated() {
                    if let gi = index(gem.id) { gems[gi].row = Self.rows - 1 - k }
                }
                let needed = Self.rows - survivors.count
                for newRow in 0..<needed {
                    gems.append(Gem(color: Int.random(in: 1...Self.colorCount), row: newRow, col: c))
                }
            }
        }
    }
}

// MARK: - Game View

struct ColorBurstGameView: View {
    var accent: Color = Color(red: 0.20, green: 0.84, blue: 0.40)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = ColorBurstEngine()

    /// nil until a level is chosen from the shared level-select.
    @State private var playingLevel: Int?

    private var totalLevels: Int { GameProgress.shared.totalLevels(for: .colorburst) }

    var body: some View {
        Group {
            if playingLevel == nil {
                GameLevelSelectView(
                    game: .colorburst, title: "Color Burst", accent: accent,
                    onSelect: { level in
                        playingLevel = level
                        withAnimation(.easeInOut(duration: 0.2)) { engine.start(at: level) }
                    },
                    onClose: { dismiss() }
                )
            } else {
                gameBody
            }
        }
        // Submit the session's score on exit (best-score board is honest either way).
        .onDisappear {
            GameKitManager.shared.recordGameOver(.colorburst, score: engine.score)
        }
        .onChange(of: engine.won) { _, won in
            if won { GameKitManager.shared.recordGameOver(.colorburst, score: engine.score, won: true) }
        }
    }

    private func backToLevels() { playingLevel = nil }

    private var gameBody: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.05, green: 0.10, blue: 0.07), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.14), .clear], center: .top, startRadius: 4, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: Spacing.sm) {
                header
                statBar
                board
                    .padding(.horizontal, Spacing.md)
                Spacer(minLength: 0)
            }
            .padding(.top, Spacing.xs)

            if engine.won {
                outcomeOverlay(engine.level >= totalLevels ? "All Levels Cleared" : "Level \(engine.level) Cleared",
                               "checkmark.seal.fill", accent,
                               primaryTitle: engine.level >= totalLevels ? "Back to Levels" : "Next Levels",
                               primary: backToLevels)
            } else if engine.gameOver {
                outcomeOverlay("Out of Moves", "hourglass.bottomhalf.filled", Color.statusError,
                               primaryTitle: "Retry Level \(engine.level)", primary: { engine.retry() },
                               secondaryTitle: "Levels", secondary: backToLevels)
            }
        }
    }

    private var header: some View {
        HStack {
            roundButton("square.grid.2x2") { backToLevels() }
            Spacer()
            Text("Color Burst")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            GameRecordControl()
            roundButton("arrow.clockwise") {
                withAnimation(.easeInOut(duration: 0.25)) { engine.retry() }
            }
        }
        .padding(.horizontal, Spacing.md)
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
        HStack(spacing: Spacing.lg) {
            stat("LEVEL", "\(engine.level)/\(totalLevels)")
            stat("SCORE", "\(engine.score)")
            stat("TARGET", "\(engine.targetScore)")
            stat("MOVES", "\(max(0, engine.moveBudget - engine.moves))")
        }
        .padding(.vertical, 2)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 8, weight: .bold)).kerning(0.8).foregroundStyle(Color.labelTertiary)
            Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(ColorBurstEngine.cols),
                           geo.size.height / CGFloat(ColorBurstEngine.rows))
            let boardW = cell * CGFloat(ColorBurstEngine.cols)
            let boardH = cell * CGFloat(ColorBurstEngine.rows)

            ZStack(alignment: .topLeading) {
                // Soft grid backdrop.
                ForEach(0..<ColorBurstEngine.rows, id: \.self) { r in
                    ForEach(0..<ColorBurstEngine.cols, id: \.self) { c in
                        RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                            .frame(width: cell, height: cell)
                            .padding(1.5)
                            .position(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
                    }
                }

                ForEach(engine.gems) { gem in
                    gemView(gem.color, size: cell, selected: engine.selected == gem.id)
                        .frame(width: cell, height: cell)
                        .position(x: (CGFloat(gem.col) + 0.5) * cell, y: (CGFloat(gem.row) + 0.5) * cell)
                        .onTapGesture { engine.tap(gem.id) }
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                        .zIndex(engine.selected == gem.id ? 2 : 1)
                }
            }
            .frame(width: boardW, height: boardH)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func gemView(_ color: Int, size: CGFloat, selected: Bool) -> some View {
        let c = ColorBurst.color(color)
        return RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [c.opacity(0.98), c.opacity(0.6)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(.white.opacity(0.42), lineWidth: 1))
            .overlay(
                Ellipse()
                    .fill(.white.opacity(0.4))
                    .frame(width: size * 0.42, height: size * 0.22)
                    .offset(y: -size * 0.16)
                    .blur(radius: 0.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(.white, lineWidth: 2.5)
                    .opacity(selected ? 1 : 0)
            )
            .padding(size * 0.08)
            .scaleEffect(selected ? 1.12 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: selected)
    }

    private func outcomeOverlay(_ title: String, _ symbol: String, _ tint: Color,
                                primaryTitle: String, primary: @escaping () -> Void,
                                secondaryTitle: String? = nil, secondary: (() -> Void)? = nil) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(tint)
                Text(title).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Score \(engine.score) / \(engine.targetScore)")
                    .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                Button {
                    MtrxHaptics.impact(.medium)
                    primary()
                } label: {
                    Text(primaryTitle)
                        .font(.mtrxCalloutBold).foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, Spacing.xl).padding(.vertical, Spacing.ms)
                        .background(accent).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if let secondaryTitle, let secondary {
                    Button(secondaryTitle) { MtrxHaptics.impact(.light); secondary() }
                        .font(.mtrxCalloutBold).foregroundStyle(Color.labelPrimary).padding(.top, Spacing.xs)
                }
                Button("Leave") { dismiss() }
                    .font(.mtrxCalloutBold).foregroundStyle(Color.labelSecondary).padding(.top, Spacing.xs)
            }
            .padding(Spacing.xl)
            .mtrxLiquidGlass(cornerRadius: 28)
            .padding(Spacing.xl)
        }
    }
}
