// BrickBreakerView.swift
// MTRX
//
// Brick Breaker — the classic paddle-and-ball brick game. Drag the paddle,
// launch the ball, clear every brick; the ball angles off the paddle by where
// it strikes, bounces the walls, and a miss costs a life. MTRX's own look:
// liquid-glass bricks, ball and paddle, a modern palette, a real-time loop
// tuned for ProMotion. Fully on-device.

import SwiftUI

// MARK: - Authored boards

/// The 50 hand-designed BrickBreaker boards. Each board is a compact pattern
/// of up to `maxRows` rows × 7 columns. Legend: '.' empty, 'o' 1-hit, 'x'
/// 2-hit, '#' 3-hit. A level is one distinct board; difficulty climbs by shape
/// density and tougher (multi-hit) bricks, NOT by uncapped ball speed.
enum BrickBreakerBoards {
    static let cols = 7
    static let maxRows = 7

    /// Ball speed by level, CAPPED at 8 px/tick. With the 120 Hz loop this stays
    /// well under the brick height (22) and width, which — together with
    /// sub-stepped collision — makes brick tunneling impossible.
    static let maxSpeed: CGFloat = 8.0
    static func cappedSpeed(_ level: Int) -> CGFloat {
        // Climbs with level but the cap binds for the hardest levels (~46+),
        // which is exactly where an uncapped speed used to tunnel.
        min(maxSpeed, 4.8 + CGFloat(max(1, level)) * 0.075)
    }

    static func board(_ level: Int) -> [String] {
        let idx = (max(1, min(50, level)) - 1)
        return patterns[idx]
    }

    /// 50 authored layouts (7 wide). Legend: '.' empty, 'o' 1-hit, 'x' 2-hit,
    /// '#' 3-hit.
    static let patterns: [[String]] = [
        // 1–10 — gentle: rows, gaps, simple shapes (all 1-hit)
        ["ooooooo", "ooooooo"],
        ["ooooooo", ".ooooo.", "..ooo.."],
        ["o.o.o.o", "o.o.o.o", "o.o.o.o"],
        ["ooooooo", "o.....o", "o.....o", "ooooooo"],
        ["..ooo..", ".ooooo.", "ooooooo"],
        ["ooooooo", ".......", "ooooooo", ".......", "ooooooo"],
        ["o.ooo.o", ".ooooo.", "o.ooo.o"],
        ["ooo.ooo", "ooo.ooo", "ooo.ooo"],
        ["ooooooo", "oo...oo", "o.....o", "oo...oo", "ooooooo"],
        ["o.o.o.o", ".o.o.o.", "o.o.o.o", ".o.o.o."],
        // 11–20 — shapes & columns (first 2-hit accents)
        ["...o...", "..ooo..", ".ooooo.", "ooooooo"],
        ["ooooooo", ".ooooo.", "..ooo..", "...o..."],
        ["x.....x", "x.ooo.x", "x.ooo.x", "x.....x"],
        ["o.o.o.o", "ooooooo", "o.o.o.o", "ooooooo"],
        ["...x...", "..xox..", ".xooox.", "xooooox"],
        ["oooxooo", "oo.x.oo", "o..x..o", "oooxooo"],
        ["xooooox", "o.....o", "o.ooo.o", "o.....o", "xooooox"],
        ["ooo.ooo", "oo.x.oo", "o.xxx.o", "oo.x.oo", "ooo.ooo"],
        ["x.x.x.x", ".o.o.o.", "x.x.x.x", ".o.o.o.", "x.x.x.x"],
        ["oooxooo", "oooxooo", "xxxxxxx", "oooxooo", "oooxooo"],
        // 21–30 — checkerboards, fortress edges (more 2-hit)
        ["xoxoxox", "oxoxoxo", "xoxoxox", "oxoxoxo"],
        ["xxxxxxx", "x.....x", "x.ooo.x", "x.....x", "xxxxxxx"],
        ["x.ooo.x", "xo.o.ox", "xoo.oox", "xo.o.ox", "x.ooo.x"],
        ["..x.x..", ".xoxox.", "xoxoxox", ".xoxox.", "..x.x.."],
        ["xoxoxox", "xoxoxox", "xoxoxox"],
        ["#.....#", ".xxxxx.", ".xooox.", ".xxxxx.", "#.....#"],
        ["ooxoxoo", "oxxxxxo", "xxxxxxx", "oxxxxxo", "ooxoxoo"],
        ["x.x.x.x", "x.x.x.x", "ooooooo", "x.x.x.x", "x.x.x.x"],
        ["#ooooo#", "oxxxxxo", "oxoooxo", "oxxxxxo", "#ooooo#"],
        ["xxx.xxx", "xx...xx", "x..o..x", "xx...xx", "xxx.xxx"],
        // 31–40 — fortresses & 3-hit cores
        ["#######", "#.....#", "#.xxx.#", "#.xxx.#", "#.....#", "#######"],
        ["x#x#x#x", "#x#x#x#", "x#x#x#x", "#x#x#x#"],
        ["##ooo##", "#xxxxx#", "oxoooxo", "#xxxxx#", "##ooo##"],
        ["#.#.#.#", ".x.x.x.", "#.#.#.#", ".x.x.x.", "#.#.#.#"],
        ["#o#o#o#", "o#o#o#o", "#o#o#o#", "o#o#o#o", "#o#o#o#"],
        ["xxxxxxx", "x#####x", "x#ooo#x", "x#####x", "xxxxxxx"],
        ["#..o..#", "xxoxxox", "xxxxxxx", "xxoxxox", "#..o..#"],
        ["##...##", "#xx.xx#", "#xooox#", "#xx.xx#", "##...##"],
        ["#x#x#x#", "x#x#x#x", "#x#x#x#", "x#x#x#x", "#x#x#x#"],
        ["#######", "#xxxxx#", "#x###x#", "#xxxxx#", "#######"],
        // 41–50 — hardest, dense multi-hit
        ["#######", "#######", "#..o..#", "#######", "#######"],
        ["#x#x#x#", "#x#x#x#", "#x#x#x#", "#x#x#x#", "#x#x#x#"],
        ["###.###", "##x.x##", "#x#.#x#", "##x.x##", "###.###"],
        ["#o#o#o#", "#x#x#x#", "#######", "#x#x#x#", "#o#o#o#"],
        ["#######", "#x#x#x#", "#######", "#x#x#x#", "#######", "ooooooo"],
        ["##x#x##", "#xx#xx#", "x##x##x", "#xx#xx#", "##x#x##"],
        ["#######", "#######", "#######", "#######", "#######", "#######"],
        ["#x#x#x#", "x#x#x#x", "#x#x#x#", "x#x#x#x", "#x#x#x#", "x#x#x#x"],
        ["#######", "#o###o#", "###o###", "#o###o#", "#######", "#######"],
        ["#######", "#######", "#######", "#######", "#######", "#######", "#######"],
    ]
}

@MainActor
final class BrickBreakerEngine: ObservableObject {
    struct Brick: Identifiable { let id = UUID(); let row: Int; let col: Int; var hp: Int; var alive: Bool { hp > 0 } }

    static let cols = 7
    static let rows = 5

    @Published var bricks: [Brick] = []
    @Published var ballX: CGFloat = 0
    @Published var ballY: CGFloat = 0
    @Published var paddleX: CGFloat = 0
    @Published var score = 0
    @Published var lives = 3
    @Published var level = 1
    @Published var launched = false
    @Published var gameOver = false
    @Published var won = false

    let ballR: CGFloat = 7
    let paddleW: CGFloat = 92
    let paddleH: CGFloat = 14
    let brickH: CGFloat = 22
    let brickGap: CGFloat = 5
    let brickTop: CGFloat = 24

    var size: CGSize = .zero
    private var vx: CGFloat = 0
    private var vy: CGFloat = 0
    private var speed: CGFloat = 5.4
    private var timer: Timer?

    private(set) var startLevel = 1
    private var pendingStart = false

    var paddleY: CGFloat { size.height - 40 }

    func configure(_ s: CGSize) {
        size = s
        if pendingStart && s != .zero {
            pendingStart = false
            start(at: startLevel)
        }
    }

    /// Begin one authored board. Clearing it records completion + unlocks the
    /// next; running out of lives is a loss.
    func start(at level: Int) {
        stop()
        startLevel = max(1, level); self.level = max(1, level)
        score = 0; lives = 3; gameOver = false; won = false
        guard size != .zero else { pendingStart = true; return }
        buildLevel()
        startTimer()
    }

    func retry() { start(at: startLevel) }

    private func buildLevel() {
        bricks = []
        let pattern = BrickBreakerBoards.board(level)
        for (r, rowStr) in pattern.enumerated() {
            for (c, ch) in rowStr.enumerated() where c < Self.cols {
                let hp: Int
                switch ch {
                case "o": hp = 1
                case "x": hp = 2
                case "#": hp = 3
                default:  hp = 0
                }
                if hp > 0 { bricks.append(Brick(row: r, col: c, hp: hp)) }
            }
        }
        // Ball speed is CAPPED (kills the tunneling bug): with the 120 Hz loop
        // and sub-stepped collision, the ball can never skip a brick between
        // frames regardless of level.
        speed = BrickBreakerBoards.cappedSpeed(level)
        resetBall()
    }

    private func resetBall() {
        launched = false
        paddleX = size.width / 2
        ballX = paddleX
        ballY = paddleY - ballR - 1
    }

    func launch() {
        guard !launched, !gameOver, !won else { return }
        launched = true
        vx = speed * 0.35
        vy = -speed * 0.94
        MtrxHaptics.impact(.light)
    }

    func nextLevel() { start(at: level + 1) }

    func movePaddle(to x: CGFloat) {
        paddleX = max(paddleW / 2, min(size.width - paddleW / 2, x))
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    func brickRect(_ b: Brick) -> CGRect {
        let w = (size.width - brickGap * CGFloat(Self.cols + 1)) / CGFloat(Self.cols)
        let x = brickGap + CGFloat(b.col) * (w + brickGap)
        let y = brickTop + CGFloat(b.row) * (brickH + brickGap)
        return CGRect(x: x, y: y, width: w, height: brickH)
    }

    private func tick() {
        guard !gameOver, !won, size != .zero else { return }
        guard launched else { ballX = paddleX; ballY = paddleY - ballR - 1; return }

        // Sub-step the movement so the ball can never skip over a brick between
        // frames (the tunneling bug). Each sub-step advances at most ~0.7·ballR.
        // Step count is fixed for the tick (|velocity| == speed is preserved by
        // every reflection), but the per-step delta is RECOMPUTED each iteration
        // from the CURRENT velocity — otherwise a bounce mid-tick would keep
        // driving the ball along the old heading and double-hit the same brick.
        let steps = max(1, Int(ceil(max(abs(vx), abs(vy)) / (ballR * 0.7))))

        for _ in 0..<steps {
            let svx = vx / CGFloat(steps)
            let svy = vy / CGFloat(steps)
            ballX += svx; ballY += svy

            if ballX < ballR { ballX = ballR; vx = abs(vx) }
            if ballX > size.width - ballR { ballX = size.width - ballR; vx = -abs(vx) }
            if ballY < ballR { ballY = ballR; vy = abs(vy) }

            // Paddle — angle off the strike point.
            if vy > 0, ballY + ballR >= paddleY, ballY - ballR <= paddleY + paddleH,
               ballX >= paddleX - paddleW / 2 - ballR, ballX <= paddleX + paddleW / 2 + ballR {
                let offset = max(-1, min(1, (ballX - paddleX) / (paddleW / 2)))
                let angle = offset * (CGFloat.pi / 3)
                vx = speed * sin(angle)
                vy = -speed * cos(angle)
                if abs(vx) < speed * 0.14 { vx = speed * 0.14 * (offset >= 0 ? 1 : -1) }
                ballY = paddleY - ballR
                MtrxHaptics.impact(.light)
            }

            // Bricks — one contact per sub-step. A multi-hit brick survives
            // until its hp reaches zero; the ball always bounces.
            let ball = CGRect(x: ballX - ballR, y: ballY - ballR, width: ballR * 2, height: ballR * 2)
            for i in bricks.indices where bricks[i].alive {
                let br = brickRect(bricks[i])
                if ball.intersects(br) {
                    bricks[i].hp -= 1
                    score += 10
                    MtrxHaptics.impact(bricks[i].alive ? .light : .medium)
                    let prevY = ballY - svy
                    if prevY - ballR >= br.maxY || prevY + ballR <= br.minY { vy = -vy } else { vx = -vx }
                    break
                }
            }

            // Miss — a life lost ends this frame's stepping.
            if ballY > size.height + ballR * 2 {
                lives -= 1
                if lives <= 0 { gameOver = true; stop(); MtrxHaptics.error() }
                else { resetBall(); MtrxHaptics.error() }
                return
            }

            // Board cleared.
            if bricks.allSatisfy({ !$0.alive }) {
                won = true; stop(); MtrxHaptics.success()
                GameProgress.shared.recordCompletion(level: level, in: .breakout)
                return
            }
        }
    }
}

// MARK: - Game View

struct BrickBreakerView: View {
    var accent: Color = Color(red: 0.97, green: 0.30, blue: 0.55)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = BrickBreakerEngine()

    @State private var playingLevel: Int?

    private var totalLevels: Int { GameProgress.shared.totalLevels(for: .breakout) }

    /// Brick colour by remaining hit points — tougher bricks read as darker,
    /// heavier glass.
    private static func hpColor(_ hp: Int) -> Color {
        switch hp {
        case 3:  return Color(red: 0.62, green: 0.28, blue: 0.72)   // deep — 3-hit
        case 2:  return Color(red: 0.97, green: 0.55, blue: 0.30)   // amber — 2-hit
        default: return Color(red: 0.41, green: 0.80, blue: 0.99)   // bright — 1-hit
        }
    }

    var body: some View {
        Group {
            if playingLevel == nil {
                GameLevelSelectView(
                    game: .breakout, title: "Brick Breaker", accent: accent,
                    onSelect: { level in
                        playingLevel = level
                        engine.start(at: level)
                    },
                    onClose: { dismiss() }
                )
            } else {
                gameBody
            }
        }
        .onChange(of: engine.gameOver) { _, over in
            if over { GameKitManager.shared.recordGameOver(.breakout, score: engine.score) }
        }
        .onChange(of: engine.won) { _, won in
            if won { GameKitManager.shared.recordGameOver(.breakout, score: engine.score, won: true) }
        }
        .onDisappear { engine.stop() }
    }

    private func backToLevels() { engine.stop(); playingLevel = nil }

    private var gameBody: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.10, green: 0.04, blue: 0.08), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [accent.opacity(0.14), .clear], center: .top, startRadius: 4, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: Spacing.sm) {
                header
                statBar
                board
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
            }
            .padding(.top, Spacing.xs)

            if engine.won {
                overlay(engine.level >= totalLevels ? "All Boards Cleared" : "Board Cleared",
                        "checkmark.seal.fill", Color.statusSuccess,
                        primaryTitle: engine.level >= totalLevels ? "Levels" : "Next Board",
                        primary: engine.level >= totalLevels ? backToLevels : { engine.nextLevel() },
                        secondaryTitle: "Levels", secondary: backToLevels)
            } else if engine.gameOver {
                overlay("Game Over", "xmark.octagon.fill", Color.statusError,
                        primaryTitle: "Retry Level \(engine.level)", primary: { engine.retry() },
                        secondaryTitle: "Levels", secondary: backToLevels)
            }
        }
    }

    private var header: some View {
        HStack {
            roundButton("square.grid.2x2") { backToLevels() }
            Spacer()
            Text("Brick Breaker")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            GameRecordControl()
            roundButton("arrow.clockwise") { engine.retry() }
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
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < engine.lives ? "heart.fill" : "heart")
                        .font(.system(size: 13))
                        .foregroundStyle(i < engine.lives ? accent : Color.labelTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 8, weight: .bold)).kerning(0.8).foregroundStyle(Color.labelTertiary)
            Text(value).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
    }

    private var board: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))

                ForEach(engine.bricks) { brick in
                    if brick.alive {
                        let r = engine.brickRect(brick)
                        glassBlock(Self.hpColor(brick.hp), radius: 6)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }

                // Paddle.
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 1))
                    .frame(width: engine.paddleW, height: engine.paddleH)
                    .position(x: engine.paddleX, y: engine.paddleY + engine.paddleH / 2)
                    .shadow(color: accent.opacity(0.5), radius: 6)

                // Ball.
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: 0.78)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: engine.ballR))
                    .frame(width: engine.ballR * 2, height: engine.ballR * 2)
                    .position(x: engine.ballX, y: engine.ballY)
                    .shadow(color: .white.opacity(0.5), radius: 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in engine.movePaddle(to: v.location.x) }
                    .onEnded { v in
                        // A tap (no real drag) launches the ball; a drag moves
                        // the paddle. One gesture handles both.
                        if abs(v.translation.width) < 6 && abs(v.translation.height) < 6 {
                            engine.launch()
                        }
                    }
            )
            .onAppear { engine.configure(geo.size) }
            .onChange(of: geo.size) { _, s in engine.configure(s) }
            .overlay(alignment: .center) {
                if !engine.launched && !engine.gameOver && !engine.won {
                    Text("Tap to launch · drag to move")
                        .font(.mtrxCaption1)
                        .foregroundStyle(Color.labelSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .offset(y: 40)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func glassBlock(_ color: Color, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.96), color.opacity(0.62)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.4), lineWidth: 1))
            .overlay(
                RoundedRectangle(cornerRadius: radius * 0.7, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center))
                    .padding(3)
            )
    }

    private func overlay(_ title: String, _ symbol: String, _ tint: Color,
                         primaryTitle: String, primary: @escaping () -> Void,
                         secondaryTitle: String? = nil, secondary: (() -> Void)? = nil) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(tint)
                Text(title).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Score \(engine.score)").font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
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
