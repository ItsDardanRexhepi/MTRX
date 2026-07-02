// Game2048View.swift
// MTRX
//
// 2048 — the sliding-tile merge puzzle (open-source mechanic). Swipe to slide
// every tile; equal tiles that collide merge and double. Reach 2048, then keep
// going for a high score. MTRX's own look: liquid-glass tiles over a soft 4×4
// well, a modern palette, ProMotion-smooth slides. Fully on-device.

import SwiftUI

// MARK: - Tile

struct Tile2048: Identifiable, Equatable {
    let id = UUID()
    var value: Int
    var row: Int
    var col: Int
    var absorbed = false   // merged into another tile this move; removed after the slide
    var isBlocker = false  // immovable wall (gauntlet mode) — never slides or merges
}

enum SlideDir { case up, down, left, right }

/// 2048 ships two modes: classic endless (reach 2048, keep going for a high
/// score) and a 50-level Gauntlet (reach a target tile within a move budget,
/// past board blockers). The user's locked decision keeps BOTH.
enum Game2048Mode { case endless, gauntlet }

// MARK: - Gauntlet levels

struct Game2048Level {
    let targetTile: Int
    let moves: Int
    let blockers: [(Int, Int)]   // immovable cells (row, col)
}

enum Game2048Levels {
    /// Authored tiered table. Difficulty climbs by target tile, tightens the
    /// move budget within each tier, and introduces board blockers on the back
    /// half of the higher tiers. On a 4×4 board blockers are brutal, so a
    /// blocked level eases its target one tier down to stay winnable.
    static func level(_ n: Int) -> Game2048Level {
        let lvl = max(1, min(50, n))
        let tier = (lvl - 1) / 10          // 0…4
        let within = (lvl - 1) % 10        // 0…9
        let targets = [64, 128, 256, 512, 1024]
        let baseBudget = [42, 74, 132, 260, 520]
        let budgetDrop = [1, 2, 3, 5, 8]

        var target = targets[tier]
        var moves = baseBudget[tier] - within * budgetDrop[tier]

        var blockers: [(Int, Int)] = []
        if tier >= 2 && within >= 5 {
            blockers = blockerPattern(lvl)
            if tier >= 3 { target = targets[tier - 1] }  // ease a cramped board
        }
        return Game2048Level(targetTile: target, moves: max(20, moves), blockers: blockers)
    }

    /// Deterministic small blocker layouts (1–2 cells) that keep the 4×4 board
    /// playable: a single centre-ish wall, or a diagonal pair.
    private static func blockerPattern(_ lvl: Int) -> [(Int, Int)] {
        switch lvl % 3 {
        case 0:  return [(1, 1)]
        case 1:  return [(2, 2)]
        default: return [(1, 1), (2, 2)]
        }
    }
}

// MARK: - Engine

@MainActor
final class Game2048Engine: ObservableObject {
    static let size = 4

    @Published var tiles: [Tile2048] = []
    @Published var score = 0
    @Published var best = 0
    @Published var won = false          // endless: reached 2048
    @Published var keepGoing = false
    @Published var gameOver = false
    @Published private(set) var busy = false

    // Gauntlet state.
    @Published var mode: Game2048Mode = .endless
    @Published var level = 1
    @Published var targetTile = 0
    @Published var moveBudget = 0
    @Published var moves = 0
    @Published var levelCleared = false
    private(set) var startLevel = 1

    /// Bumped on every (re)start so a pending post-move closure from the prior
    /// game can't fire against a freshly-dealt board.
    private var gen = 0

    /// Classic endless: reach 2048, then keep going for a high score.
    func startEndless() {
        gen &+= 1
        mode = .endless
        tiles = []; score = 0; won = false; keepGoing = false
        gameOver = false; busy = false; levelCleared = false; moves = 0
        spawnTile(); spawnTile()
    }

    /// Gauntlet level: reach the target tile within the move budget, past any
    /// board blockers.
    func startGauntlet(at level: Int) {
        gen &+= 1
        mode = .gauntlet
        startLevel = max(1, level); self.level = max(1, level)
        let def = Game2048Levels.level(self.level)
        targetTile = def.targetTile; moveBudget = def.moves
        tiles = []; score = 0; won = false; keepGoing = false
        gameOver = false; busy = false; levelCleared = false; moves = 0
        for (r, c) in def.blockers {
            tiles.append(Tile2048(value: 0, row: r, col: c, isBlocker: true))
        }
        spawnTile(); spawnTile()
    }

    func retry() { mode == .gauntlet ? startGauntlet(at: startLevel) : startEndless() }

    private func emptyCells() -> [(Int, Int)] {
        var occupied = Set<Int>()
        for t in tiles where !t.absorbed { occupied.insert(t.row * Self.size + t.col) }
        var out: [(Int, Int)] = []
        for r in 0..<Self.size {
            for c in 0..<Self.size where !occupied.contains(r * Self.size + c) { out.append((r, c)) }
        }
        return out
    }

    private func spawnTile() {
        let cells = emptyCells()
        guard let (r, c) = cells.randomElement() else { return }
        let value = Double.random(in: 0...1) < 0.9 ? 2 : 4
        tiles.append(Tile2048(value: value, row: r, col: c))
    }

    func move(_ dir: SlideDir) {
        guard !busy, !gameOver, !levelCleared, !(won && !keepGoing && mode == .endless) else { return }
        var moved = false

        withAnimation(.spring(response: 0.2, dampingFraction: 0.86)) {
            for line in 0..<Self.size {
                moved = processLine(line: line, dir: dir) || moved
            }
        }

        guard moved else { return }
        moves += 1
        busy = true
        MtrxHaptics.impact(.light)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { [weak self] in
            guard let self else { return }
            self.tiles.removeAll { $0.absorbed }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { self.spawnTile() }
            if self.mode == .gauntlet { self.evaluateGauntlet() } else { self.evaluateEndless() }
            self.busy = false
        }
    }

    /// Blocker-aware line slide. Slot 0 is the wall side. A line is split into
    /// segments by immovable blockers; movable tiles pack + merge within their
    /// own segment only (they cannot pass a blocker). Returns true if anything
    /// moved or merged.
    private func processLine(line: Int, dir: SlideDir) -> Bool {
        func coord(_ slot: Int) -> (Int, Int) {
            switch dir {
            case .left:  return (line, slot)
            case .right: return (line, Self.size - 1 - slot)
            case .up:    return (slot, line)
            case .down:  return (Self.size - 1 - slot, line)
            }
        }
        // Slot contents: -1 empty, -2 blocker, >=0 movable tile index.
        var content = Array(repeating: -1, count: Self.size)
        for slot in 0..<Self.size {
            let (r, c) = coord(slot)
            if let idx = tiles.firstIndex(where: { !$0.absorbed && $0.row == r && $0.col == c }) {
                content[slot] = tiles[idx].isBlocker ? -2 : idx
            }
        }

        var moved = false
        var seg: [Int] = []
        var segStart = 0
        func flush(_ start: Int) {
            if packSegment(seg, startSlot: start, coord: coord) { moved = true }
            seg = []
        }
        for slot in 0..<Self.size {
            if content[slot] == -2 {          // blocker ends the current segment
                flush(segStart)
                segStart = slot + 1
            } else if content[slot] >= 0 {
                seg.append(content[slot])
            }
        }
        flush(segStart)
        return moved
    }

    /// Pack + merge one segment of movable tile indices toward `startSlot`.
    private func packSegment(_ order: [Int], startSlot: Int, coord: (Int) -> (Int, Int)) -> Bool {
        var moved = false
        var slot = startSlot
        var i = 0
        while i < order.count {
            let idx = order[i]
            if i + 1 < order.count, tiles[idx].value == tiles[order[i + 1]].value {
                let nextIdx = order[i + 1]
                let (r, c) = coord(slot)
                tiles[idx].row = r; tiles[idx].col = c
                tiles[nextIdx].row = r; tiles[nextIdx].col = c
                tiles[nextIdx].absorbed = true
                tiles[idx].value *= 2
                score += tiles[idx].value
                if tiles[idx].value > best { best = tiles[idx].value }
                if tiles[idx].value == 2048 && !won && mode == .endless { won = true }
                moved = true
                i += 2
            } else {
                let (r, c) = coord(slot)
                if tiles[idx].row != r || tiles[idx].col != c { moved = true }
                tiles[idx].row = r; tiles[idx].col = c
                i += 1
            }
            slot += 1
        }
        return moved
    }

    private func evaluateEndless() {
        if noMovesLeft() { gameOver = true; MtrxHaptics.error() }
    }

    private func evaluateGauntlet() {
        let maxTile = tiles.filter { !$0.absorbed && !$0.isBlocker }.map { $0.value }.max() ?? 0
        if maxTile >= targetTile {
            levelCleared = true
            GameProgress.shared.recordCompletion(level: level, in: .merge2048)
            MtrxHaptics.success()
            return
        }
        if moves >= moveBudget || noMovesLeft() {
            gameOver = true
            MtrxHaptics.error()
        }
    }

    /// Deadlock check, blocker-aware: an empty non-blocker cell, or any pair of
    /// adjacent equal movable tiles, means a move is still possible.
    private func noMovesLeft() -> Bool {
        if !emptyCells().isEmpty { return false }
        var grid = Array(repeating: Array(repeating: 0, count: Self.size), count: Self.size)
        for t in tiles where !t.absorbed { grid[t.row][t.col] = t.isBlocker ? -1 : t.value }
        for r in 0..<Self.size {
            for c in 0..<Self.size {
                let v = grid[r][c]
                if v == -1 { continue }   // blocker never merges
                if c + 1 < Self.size && grid[r][c + 1] == v { return false }
                if r + 1 < Self.size && grid[r + 1][c] == v { return false }
            }
        }
        return true
    }
}

// MARK: - Game View

struct Game2048View: View {
    var accent: Color = Color(red: 0.98, green: 0.65, blue: 0.15)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = Game2048Engine()

    private enum Stage { case choosing, levelSelect, playing }
    @State private var stage: Stage = .choosing

    private var totalLevels: Int { GameProgress.shared.totalLevels(for: .merge2048) }

    var body: some View {
        Group {
            switch stage {
            case .choosing:    modeChooser
            case .levelSelect:
                GameLevelSelectView(
                    game: .merge2048, title: "2048 · Gauntlet", accent: accent,
                    onSelect: { level in
                        engine.startGauntlet(at: level)
                        withAnimation(.easeInOut(duration: 0.2)) { stage = .playing }
                    },
                    onClose: { stage = .choosing }
                )
            case .playing:     gameBody
            }
        }
        .onChange(of: engine.gameOver) { _, over in
            if over { GameKitManager.shared.recordGameOver(.merge2048, score: engine.score, won: engine.won) }
        }
        .onChange(of: engine.levelCleared) { _, cleared in
            if cleared { GameKitManager.shared.recordGameOver(.merge2048, score: engine.score, won: true) }
        }
    }

    private var modeChooser: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.10, green: 0.08, blue: 0.04), Color.black],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.16), .clear], center: .top, startRadius: 4, endRadius: 480)
                .ignoresSafeArea()
            VStack(spacing: Spacing.lg) {
                HStack {
                    roundButton("xmark") { dismiss() }
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                Spacer()
                Text("2048").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Choose a mode").font(.mtrxCallout).foregroundStyle(Color.labelSecondary)

                modeCard("Gauntlet", "50 levels · target tile in a move budget, past blockers",
                         symbol: "flag.checkered") {
                    stage = .levelSelect
                }
                modeCard("Endless", "Classic — reach 2048, then chase a high score",
                         symbol: "infinity") {
                    engine.startEndless()
                    stage = .playing
                }
                Spacer(); Spacer()
            }
            .padding(Spacing.xl)
        }
    }

    private func modeCard(_ title: String, _ subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            MtrxHaptics.impact(.medium)
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol).font(.system(size: 26, weight: .bold)).foregroundStyle(accent).frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.mtrxTitle3).foregroundStyle(Color.labelPrimary)
                    Text(subtitle).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Color.labelTertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.lg)
        }
        .buttonStyle(.plain)
    }

    private func backToModes() { engine.won = false; stage = .choosing }

    private var gameBody: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.10, green: 0.08, blue: 0.04), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.14), .clear], center: .top, startRadius: 4, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                header
                statBar
                board
                    .padding(.horizontal, Spacing.lg)
                Text("Swipe to slide the tiles")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelTertiary)
                Spacer(minLength: 0)
            }
            .padding(.top, Spacing.xs)

            if engine.mode == .gauntlet && engine.levelCleared {
                overlay(title: engine.level >= totalLevels ? "Gauntlet Complete" : "Level \(engine.level) Cleared",
                        symbol: "checkmark.seal.fill", tint: accent,
                        primary: "Levels", action: backToLevels)
            } else if engine.gameOver {
                let t = engine.mode == .gauntlet ? "Out of Moves" : "Game Over"
                overlay(title: t, symbol: "xmark.octagon.fill", tint: Color.statusError,
                        primary: engine.mode == .gauntlet ? "Retry Level \(engine.level)" : "Play Again",
                        action: { withAnimation { engine.retry() } },
                        secondary: engine.mode == .gauntlet ? "Levels" : "Modes",
                        secondaryAction: engine.mode == .gauntlet ? backToLevels : backToModes)
            } else if engine.mode == .endless && engine.won && !engine.keepGoing {
                overlay(title: "2048!", symbol: "crown.fill", tint: accent, primary: "Keep Going") { engine.keepGoing = true }
            }
        }
    }

    private func backToLevels() { stage = .levelSelect }

    private var header: some View {
        HStack {
            roundButton(engine.mode == .gauntlet ? "square.grid.2x2" : "arrow.left") {
                engine.mode == .gauntlet ? backToLevels() : backToModes()
            }
            Spacer()
            Text(engine.mode == .gauntlet ? "2048 · Gauntlet" : "2048")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            GameRecordControl()
            roundButton("arrow.clockwise") { withAnimation(.easeInOut(duration: 0.2)) { engine.retry() } }
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

    @ViewBuilder
    private var statBar: some View {
        if engine.mode == .gauntlet {
            HStack(spacing: Spacing.sm) {
                statChip("LEVEL", "\(engine.level)/\(totalLevels)")
                statChip("TARGET", "\(engine.targetTile)")
                statChip("MOVES", "\(max(0, engine.moveBudget - engine.moves))")
                statChip("SCORE", "\(engine.score)")
            }
            .padding(.horizontal, Spacing.lg)
        } else {
            HStack(spacing: Spacing.lg) {
                statChip("SCORE", "\(engine.score)")
                statChip("BEST", "\(engine.best)")
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .bold)).kerning(1).foregroundStyle(Color.labelTertiary)
            Text(value).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
    }

    private var board: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let pad: CGFloat = side * 0.03
            let cell = (side - pad * CGFloat(Game2048Engine.size + 1)) / CGFloat(Game2048Engine.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: side * 0.06, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.06, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))

                // Empty cell wells.
                ForEach(0..<Game2048Engine.size, id: \.self) { r in
                    ForEach(0..<Game2048Engine.size, id: \.self) { c in
                        RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                            .frame(width: cell, height: cell)
                            .position(x: cellCenter(c, cell: cell, pad: pad), y: cellCenter(r, cell: cell, pad: pad))
                    }
                }

                // Tiles.
                ForEach(engine.tiles) { tile in
                    tileView(tile, cell: cell)
                        .frame(width: cell, height: cell)
                        .position(x: cellCenter(tile.col, cell: cell, pad: pad),
                                  y: cellCenter(tile.row, cell: cell, pad: pad))
                        .transition(.scale(scale: 0.1).combined(with: .opacity))
                        .zIndex(tile.absorbed ? 0 : 1)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { v in
                        let dx = v.translation.width, dy = v.translation.height
                        if abs(dx) > abs(dy) { engine.move(dx > 0 ? .right : .left) }
                        else { engine.move(dy > 0 ? .down : .up) }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func cellCenter(_ i: Int, cell: CGFloat, pad: CGFloat) -> CGFloat {
        pad + CGFloat(i) * (cell + pad) + cell / 2
    }

    @ViewBuilder
    private func tileView(_ tile: Tile2048, cell: CGFloat) -> some View {
        if tile.isBlocker {
            RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
                .fill(Color(white: 0.16))
                .overlay(RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1))
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: cell * 0.30, weight: .bold))
                        .foregroundStyle(Color.labelTertiary)
                )
        } else {
            valueTileView(tile, cell: cell)
        }
    }

    private func valueTileView(_ tile: Tile2048, cell: CGFloat) -> some View {
        let color = tileColor(tile.value)
        let digits = "\(tile.value)".count
        let fontSize = cell * (digits <= 2 ? 0.40 : digits == 3 ? 0.32 : 0.26)
        return RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.98), color.opacity(0.66)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: cell * 0.18, style: .continuous).stroke(.white.opacity(0.4), lineWidth: 1))
            .overlay(
                RoundedRectangle(cornerRadius: cell * 0.14, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                    .padding(cell * 0.12)
            )
            .overlay(
                Text("\(tile.value)")
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            )
            .shadow(color: color.opacity(0.4), radius: 4, y: 2)
    }

    /// MTRX's own value palette.
    private func tileColor(_ v: Int) -> Color {
        switch v {
        case 2:    return Color(red: 0.42, green: 0.62, blue: 0.82)
        case 4:    return Color(red: 0.30, green: 0.71, blue: 0.79)
        case 8:    return Color(red: 0.32, green: 0.77, blue: 0.60)
        case 16:   return Color(red: 0.48, green: 0.81, blue: 0.45)
        case 32:   return Color(red: 0.76, green: 0.80, blue: 0.39)
        case 64:   return Color(red: 0.96, green: 0.74, blue: 0.35)
        case 128:  return Color(red: 0.97, green: 0.60, blue: 0.35)
        case 256:  return Color(red: 0.97, green: 0.45, blue: 0.50)
        case 512:  return Color(red: 0.93, green: 0.42, blue: 0.67)
        case 1024: return Color(red: 0.72, green: 0.46, blue: 0.93)
        default:   return Color(red: 0.36, green: 0.80, blue: 0.96)   // 2048+
        }
    }

    private func overlay(title: String, symbol: String, tint: Color, primary: String,
                         action: @escaping () -> Void,
                         secondary: String? = nil, secondaryAction: (() -> Void)? = nil) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(tint)
                Text(title).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Score \(engine.score)").font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                Button {
                    MtrxHaptics.impact(.medium)
                    withAnimation(.easeInOut(duration: 0.2)) { action() }
                } label: {
                    Text(primary)
                        .font(.mtrxCalloutBold).foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, Spacing.xl).padding(.vertical, Spacing.ms)
                        .background(accent).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if let secondary, let secondaryAction {
                    Button(secondary) { MtrxHaptics.impact(.light); withAnimation { secondaryAction() } }
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
