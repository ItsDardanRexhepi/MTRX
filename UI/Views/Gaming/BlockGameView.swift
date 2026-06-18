// BlockGameView.swift
// MTRX
//
// An original falling-block stacking puzzle. Ten-by-twenty well, the seven
// four-cell shapes, gravity that quickens with each level, full-row clears,
// scoring, a ghost drop preview and wall-kick rotation. The look is MTRX's
// own: liquid-glass blocks over a soft grid, a modern color palette, tuned
// for ProMotion-smooth motion. Fully on-device.

import SwiftUI

// MARK: - Shapes

enum BlockShape: Int, CaseIterable {
    case i, o, t, s, z, j, l

    var box: Int { self == .i ? 4 : (self == .o ? 2 : 3) }

    /// The four cells of the piece, as (row, col) inside its bounding box.
    var base: [(Int, Int)] {
        switch self {
        case .i: return [(1, 0), (1, 1), (1, 2), (1, 3)]
        case .o: return [(0, 0), (0, 1), (1, 0), (1, 1)]
        case .t: return [(0, 1), (1, 0), (1, 1), (1, 2)]
        case .s: return [(0, 1), (0, 2), (1, 0), (1, 1)]
        case .z: return [(0, 0), (0, 1), (1, 1), (1, 2)]
        case .j: return [(0, 0), (1, 0), (1, 1), (1, 2)]
        case .l: return [(0, 2), (1, 0), (1, 1), (1, 2)]
        }
    }

    var colorIndex: Int { rawValue + 1 }

    /// MTRX's own palette — not a copy of any existing game's colors.
    static let palette: [Color] = [
        Color(red: 0.36, green: 0.80, blue: 0.99),  // i — sky
        Color(red: 0.99, green: 0.82, blue: 0.38),  // o — gold
        Color(red: 0.73, green: 0.53, blue: 0.99),  // t — violet
        Color(red: 0.40, green: 0.88, blue: 0.60),  // s — mint
        Color(red: 0.99, green: 0.46, blue: 0.56),  // z — rose
        Color(red: 0.43, green: 0.60, blue: 0.99),  // j — blue
        Color(red: 0.99, green: 0.63, blue: 0.41)   // l — coral
    ]

    static func color(_ index: Int) -> Color {
        guard index >= 1, index <= palette.count else { return .clear }
        return palette[index - 1]
    }
}

struct ActivePiece {
    var shape: BlockShape
    var rotation: Int
    var row: Int
    var col: Int

    func cells() -> [(Int, Int)] {
        var cs = shape.base
        let box = shape.box
        for _ in 0..<((rotation % 4 + 4) % 4) {
            cs = cs.map { (r, c) in (c, box - 1 - r) }
        }
        return cs.map { (r, c) in (r + row, c + col) }
    }
}

private struct GridPoint: Hashable { let r: Int; let c: Int }

// MARK: - Engine

@MainActor
final class BlockEngine: ObservableObject {
    static let cols = 10
    static let rows = 20

    @Published var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: cols), count: rows)
    @Published var piece: ActivePiece?
    @Published var nextShape: BlockShape = .t
    @Published var score = 0
    @Published var lines = 0
    @Published var level = 1
    @Published var gameOver = false
    @Published var paused = false
    @Published var clearing: Set<Int> = []

    private var timer: Timer?

    init() { start() }

    func start() {
        grid = Array(repeating: Array(repeating: 0, count: Self.cols), count: Self.rows)
        score = 0; lines = 0; level = 1; gameOver = false; paused = false; clearing = []
        nextShape = BlockShape.allCases.randomElement() ?? .t
        spawn()
        restartTimer()
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func restartTimer() {
        timer?.invalidate()
        let interval = max(0.09, 0.85 - Double(level - 1) * 0.07)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func spawn() {
        let shape = nextShape
        nextShape = BlockShape.allCases.randomElement() ?? .t
        let p = ActivePiece(shape: shape, rotation: 0, row: 0, col: (Self.cols - shape.box) / 2)
        if valid(p) { piece = p }
        else { piece = nil; gameOver = true; stop(); MtrxHaptics.error() }
    }

    private func valid(_ p: ActivePiece) -> Bool {
        for (r, c) in p.cells() {
            if c < 0 || c >= Self.cols || r >= Self.rows { return false }
            if r >= 0 && grid[r][c] != 0 { return false }
        }
        return true
    }

    private func tick() {
        guard !paused, !gameOver, var p = piece else { return }
        p.row += 1
        if valid(p) { withAnimation(.linear(duration: 0.05)) { piece = p } }
        else { lockPiece() }
    }

    private func lockPiece() {
        guard let p = piece else { return }
        for (r, c) in p.cells() where r >= 0 { grid[r][c] = p.shape.colorIndex }
        MtrxHaptics.impact(.light)
        piece = nil
        clearLines { [weak self] in self?.spawn() }
    }

    private func clearLines(_ completion: @escaping () -> Void) {
        let full = (0..<Self.rows).filter { r in grid[r].allSatisfy { $0 != 0 } }
        guard !full.isEmpty else { completion(); return }

        withAnimation(.easeIn(duration: 0.10)) { clearing = Set(full) }
        let count = full.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard let self else { return }
            var newGrid = self.grid.enumerated().filter { !full.contains($0.offset) }.map { $0.element }
            while newGrid.count < Self.rows {
                newGrid.insert(Array(repeating: 0, count: Self.cols), at: 0)
            }
            withAnimation(.easeOut(duration: 0.12)) {
                self.grid = newGrid
                self.clearing = []
            }
            self.score += [0, 100, 300, 500, 800][min(count, 4)] * self.level
            self.lines += count
            let lvl = self.lines / 10 + 1
            if lvl != self.level { self.level = lvl; self.restartTimer() }
            MtrxHaptics.success()
            completion()
        }
    }

    // MARK: Controls

    func move(_ dx: Int) {
        guard var p = piece, !paused, !gameOver else { return }
        p.col += dx
        if valid(p) { piece = p; MtrxHaptics.selection() }
    }

    func rotate() {
        guard let base = piece, !paused, !gameOver, base.shape != .o else {
            if piece?.shape == .o { MtrxHaptics.selection() }
            return
        }
        var p = base
        p.rotation = (p.rotation + 1) % 4
        for dx in [0, -1, 1, -2, 2] {
            var q = p; q.col += dx
            if valid(q) { piece = q; MtrxHaptics.impact(.light); return }
        }
    }

    func softDrop() {
        guard var p = piece, !paused, !gameOver else { return }
        p.row += 1
        if valid(p) { piece = p; score += 1 }
        else { lockPiece() }
    }

    func hardDrop() {
        guard var p = piece, !paused, !gameOver else { return }
        var dropped = 0
        while true {
            var q = p; q.row += 1
            if valid(q) { p = q; dropped += 1 } else { break }
        }
        piece = p
        score += dropped * 2
        MtrxHaptics.impact(.medium)
        lockPiece()
    }

    func togglePause() {
        guard !gameOver else { return }
        paused.toggle()
        MtrxHaptics.impact(.light)
    }

    func ghost() -> ActivePiece? {
        guard var p = piece else { return nil }
        while true {
            var q = p; q.row += 1
            if valid(q) { p = q } else { break }
        }
        return p
    }
}

// MARK: - Game View

struct BlockGameView: View {
    var accent: Color = Color(red: 0.62, green: 0.40, blue: 0.96)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = BlockEngine()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.06, green: 0.04, blue: 0.12), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.16), .clear], center: .top, startRadius: 4, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: Spacing.sm) {
                header
                HStack(alignment: .top, spacing: Spacing.md) {
                    statColumn
                    Spacer()
                    nextPreview
                }
                .padding(.horizontal, Spacing.md)

                well
                    .padding(.horizontal, Spacing.md)

                controls
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.sm)
            }
            .padding(.top, Spacing.xs)

            if engine.gameOver { overlay(title: "Game Over", symbol: "xmark.octagon.fill", tint: Color.statusError) }
            else if engine.paused { overlay(title: "Paused", symbol: "pause.circle.fill", tint: accent) }
        }
        .onDisappear { engine.stop() }
        .onChange(of: engine.gameOver) { _, over in
            if over { GameKitManager.shared.recordGameOver(.blocks, score: engine.score) }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            roundButton("xmark") { dismiss() }
            Spacer()
            Text("Tetris")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            GameRecordControl()
            roundButton(engine.gameOver ? "arrow.clockwise" : (engine.paused ? "play.fill" : "pause.fill")) {
                if engine.gameOver { engine.start() } else { engine.togglePause() }
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

    private var statColumn: some View {
        HStack(spacing: Spacing.lg) {
            stat("SCORE", "\(engine.score)")
            stat("LINES", "\(engine.lines)")
            stat("LEVEL", "\(engine.level)")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 8, weight: .bold)).kerning(0.8).foregroundStyle(Color.labelTertiary)
            Text(value).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
    }

    private var nextPreview: some View {
        VStack(spacing: 3) {
            Text("NEXT").font(.system(size: 8, weight: .bold)).kerning(0.8).foregroundStyle(Color.labelTertiary)
            let s = engine.nextShape
            let size: CGFloat = 12
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: size * 4, height: size * 2)
                ForEach(Array(s.base.enumerated()), id: \.offset) { _, cell in
                    glassBlock(BlockShape.color(s.colorIndex), size: size, flashing: false)
                        .frame(width: size, height: size)
                        .offset(x: CGFloat(cell.1) * size, y: CGFloat(cell.0) * size)
                }
            }
            .frame(width: size * 4, height: size * 2, alignment: .topLeading)
        }
        .padding(Spacing.sm)
        .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
    }

    // MARK: Well

    private var well: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(BlockEngine.cols),
                           geo.size.height / CGFloat(BlockEngine.rows))
            let boardW = cell * CGFloat(BlockEngine.cols)
            let boardH = cell * CGFloat(BlockEngine.rows)

            let pieceCells = Set((engine.piece?.cells() ?? []).map { GridPoint(r: $0.0, c: $0.1) })
            let ghostCells = Set((engine.ghost()?.cells() ?? []).map { GridPoint(r: $0.0, c: $0.1) })
            let pieceColor = engine.piece.map { BlockShape.color($0.shape.colorIndex) } ?? .clear

            VStack(spacing: 0) {
                ForEach(0..<BlockEngine.rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<BlockEngine.cols, id: \.self) { c in
                            cellView(r: r, c: c, cell: cell,
                                     pieceCells: pieceCells, ghostCells: ghostCells, pieceColor: pieceColor)
                        }
                    }
                }
            }
            .frame(width: boardW, height: boardH)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { v in
                        if abs(v.translation.width) > abs(v.translation.height) {
                            engine.move(v.translation.width > 0 ? 1 : -1)
                        } else if v.translation.height > 0 {
                            engine.hardDrop()
                        } else {
                            engine.rotate()
                        }
                    }
            )
        }
    }

    @ViewBuilder
    private func cellView(r: Int, c: Int, cell: CGFloat,
                          pieceCells: Set<GridPoint>, ghostCells: Set<GridPoint>, pieceColor: Color) -> some View {
        let p = GridPoint(r: r, c: c)
        let locked = engine.grid[r][c]
        if pieceCells.contains(p) {
            glassBlock(pieceColor, size: cell, flashing: false).frame(width: cell, height: cell)
        } else if locked != 0 {
            glassBlock(BlockShape.color(locked), size: cell, flashing: engine.clearing.contains(r))
                .frame(width: cell, height: cell)
        } else if ghostCells.contains(p) {
            RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                .stroke(pieceColor.opacity(0.5), lineWidth: 1.5)
                .padding(2)
                .frame(width: cell, height: cell)
        } else {
            RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .padding(1)
                .frame(width: cell, height: cell)
        }
    }

    private func glassBlock(_ color: Color, size: CGFloat, flashing: Bool) -> some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.96), color.opacity(0.62)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(.white.opacity(0.40), lineWidth: 1))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                         startPoint: .top, endPoint: .center))
                    .padding(size * 0.16)
            )
            .overlay(flashing ? Color.white.opacity(0.85) : Color.clear)
            .padding(1)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ctrl("arrow.left") { engine.move(-1) }
                ctrl("arrow.clockwise") { engine.rotate() }
                ctrl("arrow.down") { engine.softDrop() }
                ctrl("arrow.right") { engine.move(1) }
            }
            Button {
                engine.hardDrop()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 15, weight: .bold))
                    Text("Drop").font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.ms)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func ctrl(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: Overlay

    private func overlay(title: String, symbol: String, tint: Color) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(tint)
                Text(title).font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(engine.score) pts · \(engine.lines) lines")
                    .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                Button {
                    MtrxHaptics.impact(.medium)
                    if engine.gameOver { engine.start() } else { engine.togglePause() }
                } label: {
                    Text(engine.gameOver ? "Play Again" : "Resume")
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
