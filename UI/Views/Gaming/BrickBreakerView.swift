// BrickBreakerView.swift
// MTRX
//
// Brick Breaker — the classic paddle-and-ball brick game. Drag the paddle,
// launch the ball, clear every brick; the ball angles off the paddle by where
// it strikes, bounces the walls, and a miss costs a life. MTRX's own look:
// liquid-glass bricks, ball and paddle, a modern palette, a real-time loop
// tuned for ProMotion. Fully on-device.

import SwiftUI

@MainActor
final class BrickBreakerEngine: ObservableObject {
    struct Brick: Identifiable { let id = UUID(); let row: Int; let col: Int; var alive = true }

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

    var paddleY: CGFloat { size.height - 40 }

    func configure(_ s: CGSize) {
        let fresh = size == .zero
        size = s
        if fresh { newGame() }
    }

    func newGame() {
        stop()
        score = 0; lives = 3; level = 1; gameOver = false; won = false
        buildLevel()
        startTimer()
    }

    private func buildLevel() {
        bricks = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols { bricks.append(Brick(row: r, col: c)) }
        }
        speed = 5.4 + CGFloat(level - 1) * 0.5
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

    func nextLevel() {
        level += 1
        won = false
        buildLevel()
        startTimer()
    }

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

        ballX += vx; ballY += vy

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

        // Bricks.
        let ball = CGRect(x: ballX - ballR, y: ballY - ballR, width: ballR * 2, height: ballR * 2)
        for i in bricks.indices where bricks[i].alive {
            let br = brickRect(bricks[i])
            if ball.intersects(br) {
                bricks[i].alive = false
                score += 10
                MtrxHaptics.impact(.light)
                let prevY = ballY - vy
                if prevY - ballR >= br.maxY || prevY + ballR <= br.minY { vy = -vy } else { vx = -vx }
                break
            }
        }

        // Miss.
        if ballY > size.height + ballR * 2 {
            lives -= 1
            if lives <= 0 { gameOver = true; stop(); MtrxHaptics.error() } else { resetBall(); MtrxHaptics.error() }
        }

        // Cleared.
        if bricks.allSatisfy({ !$0.alive }) { won = true; stop(); MtrxHaptics.success() }
    }
}

// MARK: - Game View

struct BrickBreakerView: View {
    var accent: Color = Color(red: 0.97, green: 0.30, blue: 0.55)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = BrickBreakerEngine()

    private static let rowColors: [Color] = [
        Color(red: 0.98, green: 0.37, blue: 0.45),
        Color(red: 0.99, green: 0.63, blue: 0.31),
        Color(red: 0.99, green: 0.84, blue: 0.39),
        Color(red: 0.41, green: 0.87, blue: 0.55),
        Color(red: 0.37, green: 0.71, blue: 0.99)
    ]

    var body: some View {
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

            if engine.gameOver {
                overlay("Game Over", "xmark.octagon.fill", Color.statusError, "Play Again") { engine.newGame() }
            } else if engine.won {
                overlay("Cleared!", "checkmark.seal.fill", Color.statusSuccess, "Next Level") { engine.nextLevel() }
            }
        }
        .onChange(of: engine.gameOver) { _, over in
            if over { GameKitManager.shared.recordGameOver(.breakout, score: engine.score, won: engine.won) }
        }
        // Brick Breaker is endless via "Next Level" — also submit the cleared
        // session score on exit (recordGameOver de-dupes via local best).
        .onDisappear {
            engine.stop()
            GameKitManager.shared.recordGameOver(.breakout, score: engine.score, won: engine.won)
        }
    }

    private var header: some View {
        HStack {
            roundButton("xmark") { dismiss() }
            Spacer()
            Text("Brick Breaker")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            GameRecordControl()
            roundButton("arrow.clockwise") { engine.newGame() }
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
            stat("SCORE", "\(engine.score)")
            stat("LEVEL", "\(engine.level)")
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
                        glassBlock(Self.rowColors[brick.row % Self.rowColors.count], radius: 6)
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

    private func overlay(_ title: String, _ symbol: String, _ tint: Color, _ primary: String, _ action: @escaping () -> Void) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                Image(systemName: symbol).font(.system(size: 52)).foregroundStyle(tint)
                Text(title).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Score \(engine.score)").font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                Button {
                    MtrxHaptics.impact(.medium)
                    action()
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
