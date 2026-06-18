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
}

enum SlideDir { case up, down, left, right }

// MARK: - Engine

@MainActor
final class Game2048Engine: ObservableObject {
    static let size = 4

    @Published var tiles: [Tile2048] = []
    @Published var score = 0
    @Published var best = 0
    @Published var won = false
    @Published var keepGoing = false
    @Published var gameOver = false
    @Published private(set) var busy = false

    init() { newGame() }

    func newGame() {
        tiles = []; score = 0; won = false; keepGoing = false; gameOver = false; busy = false
        spawnTile(); spawnTile()
    }

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

    private func indexGrid() -> [[Int]] {
        var g = Array(repeating: Array(repeating: -1, count: Self.size), count: Self.size)
        for (i, t) in tiles.enumerated() where !t.absorbed { g[t.row][t.col] = i }
        return g
    }

    func move(_ dir: SlideDir) {
        guard !busy, !gameOver else { return }
        let g = indexGrid()
        var moved = false

        withAnimation(.spring(response: 0.2, dampingFraction: 0.86)) {
            for line in 0..<Self.size {
                // Gather tile indices in the order they travel toward the wall.
                var order: [Int] = []
                switch dir {
                case .left:  for c in 0..<Self.size { if g[line][c] >= 0 { order.append(g[line][c]) } }
                case .right: for c in stride(from: Self.size - 1, through: 0, by: -1) { if g[line][c] >= 0 { order.append(g[line][c]) } }
                case .up:    for r in 0..<Self.size { if g[r][line] >= 0 { order.append(g[r][line]) } }
                case .down:  for r in stride(from: Self.size - 1, through: 0, by: -1) { if g[r][line] >= 0 { order.append(g[r][line]) } }
                }
                moved = processLine(order, line: line, dir: dir) || moved
            }
        }

        guard moved else { return }
        busy = true
        MtrxHaptics.impact(.light)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { [weak self] in
            guard let self else { return }
            self.tiles.removeAll { $0.absorbed }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { self.spawnTile() }
            self.evaluateEnd()
            self.busy = false
        }
    }

    /// Slot 0 is the wall side. Returns true if anything moved or merged.
    private func processLine(_ order: [Int], line: Int, dir: SlideDir) -> Bool {
        func coord(_ slot: Int) -> (Int, Int) {
            switch dir {
            case .left:  return (line, slot)
            case .right: return (line, Self.size - 1 - slot)
            case .up:    return (slot, line)
            case .down:  return (Self.size - 1 - slot, line)
            }
        }
        var moved = false
        var slot = 0
        var i = 0
        while i < order.count {
            let idx = order[i]
            if i + 1 < order.count, tiles[idx].value == tiles[order[i + 1]].value {
                // Merge idx + next into one doubled tile at `slot`.
                let nextIdx = order[i + 1]
                let (r, c) = coord(slot)
                tiles[idx].row = r; tiles[idx].col = c
                tiles[nextIdx].row = r; tiles[nextIdx].col = c
                tiles[nextIdx].absorbed = true
                tiles[idx].value *= 2
                score += tiles[idx].value
                if tiles[idx].value >= best { best = tiles[idx].value }
                if tiles[idx].value == 2048 && !won { won = true }
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

    private func evaluateEnd() {
        guard emptyCells().isEmpty else { return }
        // No empty cells — game over only if no adjacent equal pair exists.
        var grid = Array(repeating: Array(repeating: 0, count: Self.size), count: Self.size)
        for t in tiles where !t.absorbed { grid[t.row][t.col] = t.value }
        for r in 0..<Self.size {
            for c in 0..<Self.size {
                if c + 1 < Self.size && grid[r][c] == grid[r][c + 1] { return }
                if r + 1 < Self.size && grid[r][c] == grid[r + 1][c] { return }
            }
        }
        gameOver = true
        MtrxHaptics.error()
    }
}

// MARK: - Game View

struct Game2048View: View {
    var accent: Color = Color(red: 0.98, green: 0.65, blue: 0.15)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = Game2048Engine()

    var body: some View {
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

            if engine.gameOver { overlay(title: "Game Over", symbol: "xmark.octagon.fill", tint: Color.statusError, primary: "Play Again") { engine.newGame() } }
            else if engine.won && !engine.keepGoing {
                overlay(title: "2048!", symbol: "crown.fill", tint: accent, primary: "Keep Going") { engine.keepGoing = true }
            }
        }
        .onAppear {}
    }

    private var header: some View {
        HStack {
            roundButton("xmark") { dismiss() }
            Spacer()
            Text("2048")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            GameRecordControl()
            roundButton("arrow.clockwise") { withAnimation(.easeInOut(duration: 0.2)) { engine.newGame() } }
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
            statChip("SCORE", "\(engine.score)")
            statChip("BEST", "\(engine.best)")
        }
        .padding(.horizontal, Spacing.lg)
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

    private func tileView(_ tile: Tile2048, cell: CGFloat) -> some View {
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

    private func overlay(title: String, symbol: String, tint: Color, primary: String, action: @escaping () -> Void) -> some View {
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
                Button("Leave") { dismiss() }
                    .font(.mtrxCalloutBold).foregroundStyle(Color.labelSecondary).padding(.top, Spacing.xs)
            }
            .padding(Spacing.xl)
            .mtrxLiquidGlass(cornerRadius: 28)
            .padding(Spacing.xl)
        }
    }
}
