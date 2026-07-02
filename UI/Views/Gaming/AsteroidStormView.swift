// AsteroidStormView.swift
// MTRX
//
// Asteroid Storm — a modern take on the classic 1979 rock-shooter. Rotate and
// thrust a drifting ship through space, fire to break asteroids into smaller
// pieces, and clear the field while the screen wraps at every edge. Rendered
// with a SwiftUI Canvas for a glowing, glassy, modern look; MTRX's own palette;
// a real-time loop tuned for ProMotion. Fully on-device.

import SwiftUI

@MainActor
final class AsteroidStormEngine: ObservableObject {
    struct Bullet { var x, y, vx, vy, life: CGFloat }
    struct Rock {
        var x, y, vx, vy: CGFloat
        var radius: CGFloat
        var stage: Int          // 2 = large, 1 = medium, 0 = small
        var angle: CGFloat
        var spin: CGFloat
        var verts: [CGFloat]    // jagged radius multipliers
    }

    // Redraw trigger — bumped every tick so the Canvas re-renders.
    @Published private(set) var frame = 0
    @Published var score = 0
    @Published var lives = 3
    @Published var level = 1
    @Published var gameOver = false
    @Published var victory = false          // cleared level 50

    /// The level this run started on — a game-over retries THIS level, not 1.
    private(set) var startLevel = 1

    // Game objects (plain vars; the Canvas reads them on each frame).
    var shipX: CGFloat = 0, shipY: CGFloat = 0, shipAngle: CGFloat = 0
    var shipVX: CGFloat = 0, shipVY: CGFloat = 0
    var bullets: [Bullet] = []
    var rocks: [Rock] = []
    var invincible: CGFloat = 0
    var thrusting = false
    var rotatingLeft = false
    var rotatingRight = false

    var size: CGSize = .zero
    let shipR: CGFloat = 13
    private var fireCooldown: CGFloat = 0
    var firing = false
    private var timer: Timer?

    private var pendingStart = false

    func configure(_ s: CGSize) {
        size = s
        // The level is chosen before the board lays out, so the actual start is
        // deferred until we have a real size.
        if pendingStart && s != .zero {
            pendingStart = false
            start(at: startLevel)
        }
    }

    /// Begin a run at the chosen (unlocked) level. Each cleared level records
    /// completion to the shared GameProgress store; clearing level 50 wins.
    func start(at level: Int) {
        stop()
        startLevel = max(1, level)
        self.level = max(1, level)
        guard size != .zero else { pendingStart = true; return }
        score = 0; lives = 3
        gameOver = false; victory = false
        bullets = []
        resetShip()
        spawnWave()
        startTimer()
    }

    /// Retry the level this run started on.
    func retry() { start(at: startLevel) }

    private func resetShip() {
        shipX = size.width / 2; shipY = size.height / 2
        shipVX = 0; shipVY = 0; shipAngle = 0
        invincible = 120
    }

    private func spawnWave() {
        rocks = []
        let count = 3 + level
        for _ in 0..<count {
            // Spawn away from the centre so the ship isn't hit instantly.
            var x = CGFloat.random(in: 0...size.width)
            var y = CGFloat.random(in: 0...size.height)
            if abs(x - size.width / 2) < 120 && abs(y - size.height / 2) < 120 {
                x = CGFloat.random(in: 0...60); y = CGFloat.random(in: 0...60)
            }
            rocks.append(makeRock(x: x, y: y, stage: 2))
        }
    }

    private func makeRock(x: CGFloat, y: CGFloat, stage: Int) -> Rock {
        let radius: CGFloat = stage == 2 ? 38 : stage == 1 ? 23 : 13
        let speed = CGFloat.random(in: 0.5...1.3) + CGFloat(level) * 0.06
        let dir = CGFloat.random(in: 0...(2 * .pi))
        let verts = (0..<11).map { _ in CGFloat.random(in: 0.74...1.12) }
        return Rock(x: x, y: y, vx: cos(dir) * speed, vy: sin(dir) * speed,
                    radius: radius, stage: stage, angle: .random(in: 0...(2 * .pi)),
                    spin: .random(in: -0.03...0.03), verts: verts)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }

    func fire() {
        let nx = sin(shipAngle), ny = -cos(shipAngle)
        bullets.append(Bullet(x: shipX + nx * shipR, y: shipY + ny * shipR,
                              vx: shipVX + nx * 7.5, vy: shipVY + ny * 7.5, life: 80))
        MtrxHaptics.impact(.light)
    }

    private func wrap(_ v: CGFloat, _ max: CGFloat) -> CGFloat {
        var x = v
        if x < 0 { x += max }; if x > max { x -= max }
        return x
    }

    private func tick() {
        guard !gameOver, size != .zero else { return }

        if rotatingLeft { shipAngle -= 0.05 }
        if rotatingRight { shipAngle += 0.05 }
        if thrusting {
            shipVX += sin(shipAngle) * 0.07
            shipVY += -cos(shipAngle) * 0.07
        }
        shipVX *= 0.992; shipVY *= 0.992
        let sp = sqrt(shipVX * shipVX + shipVY * shipVY)
        if sp > 5.2 { shipVX *= 5.2 / sp; shipVY *= 5.2 / sp }
        shipX = wrap(shipX + shipVX, size.width)
        shipY = wrap(shipY + shipVY, size.height)
        if invincible > 0 { invincible -= 1 }

        if firing { fireCooldown -= 1; if fireCooldown <= 0 { fire(); fireCooldown = 16 } }

        for i in bullets.indices {
            bullets[i].x = wrap(bullets[i].x + bullets[i].vx, size.width)
            bullets[i].y = wrap(bullets[i].y + bullets[i].vy, size.height)
            bullets[i].life -= 1
        }
        bullets.removeAll { $0.life <= 0 }

        for i in rocks.indices {
            rocks[i].x = wrap(rocks[i].x + rocks[i].vx, size.width)
            rocks[i].y = wrap(rocks[i].y + rocks[i].vy, size.height)
            rocks[i].angle += rocks[i].spin
        }

        // Bullet vs rock.
        var newRocks: [Rock] = []
        var bulletHit = Set<Int>()
        for r in rocks {
            var destroyed = false
            for (bi, b) in bullets.enumerated() where !bulletHit.contains(bi) {
                if hypot(b.x - r.x, b.y - r.y) < r.radius {
                    bulletHit.insert(bi)
                    destroyed = true
                    score += r.stage == 2 ? 20 : r.stage == 1 ? 50 : 100
                    if r.stage > 0 {
                        for _ in 0..<2 { newRocks.append(makeRock(x: r.x, y: r.y, stage: r.stage - 1)) }
                    }
                    MtrxHaptics.impact(.medium)
                    break
                }
            }
            if !destroyed { newRocks.append(r) }
        }
        if !bulletHit.isEmpty {
            bullets = bullets.enumerated().filter { !bulletHit.contains($0.offset) }.map { $0.element }
        }
        rocks = newRocks

        // Ship vs rock.
        if invincible <= 0 {
            for r in rocks where hypot(r.x - shipX, r.y - shipY) < r.radius + shipR * 0.6 {
                lives -= 1
                if lives <= 0 { gameOver = true; stop(); MtrxHaptics.error() } else { resetShip(); MtrxHaptics.error() }
                break
            }
        }

        // Level cleared. Record completion (unlocks the next), then either
        // advance to the next level or — at 50 — win.
        if rocks.isEmpty && !gameOver && !victory {
            GameProgress.shared.recordCompletion(level: level, in: .asteroids)
            if level >= GameProgress.shared.totalLevels(for: .asteroids) {
                victory = true; stop(); MtrxHaptics.success()
            } else {
                level += 1; spawnWave(); resetShip(); MtrxHaptics.impact(.rigid)
            }
        }

        frame &+= 1
    }
}

// MARK: - Game View

struct AsteroidStormView: View {
    var accent: Color = Color(red: 0.25, green: 0.55, blue: 0.98)

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = AsteroidStormEngine()

    /// nil until the player picks a level from the shared level-select.
    @State private var playingLevel: Int?

    // A static starfield, generated once.
    private let stars: [(CGFloat, CGFloat, CGFloat)] = (0..<60).map { _ in
        (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1), CGFloat.random(in: 0.6...1.8))
    }

    private var totalLevels: Int { GameProgress.shared.totalLevels(for: .asteroids) }

    var body: some View {
        Group {
            if playingLevel == nil {
                GameLevelSelectView(
                    game: .asteroids, title: "Asteroid Storm", accent: accent,
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
        .onDisappear { engine.stop() }
        .onChange(of: engine.gameOver) { _, over in
            if over { GameKitManager.shared.recordGameOver(.asteroids, score: engine.score) }
        }
        .onChange(of: engine.victory) { _, won in
            if won { GameKitManager.shared.recordGameOver(.asteroids, score: engine.score, won: true) }
        }
    }

    /// Return to the level grid (progress is already persisted per cleared level).
    private func backToLevels() {
        engine.stop()
        playingLevel = nil
    }

    private var gameBody: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(red: 0.04, green: 0.05, blue: 0.12), Color.black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: Spacing.sm) {
                header
                statBar
                board
                    .padding(.horizontal, Spacing.sm)
                controls
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.sm)
            }
            .padding(.top, Spacing.xs)

            if engine.victory {
                overlay("All Sectors Cleared", "trophy.fill", accent,
                        primaryTitle: "Back to Levels", primary: backToLevels)
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
            Text("Asteroid Storm")
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
            stat("SCORE", "\(engine.score)")
            stat("LEVEL", "\(engine.level)/\(totalLevels)")
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < engine.lives ? "airplane" : "airplane")
                        .font(.system(size: 12))
                        .foregroundStyle(i < engine.lives ? accent : Color.labelTertiary)
                        .opacity(i < engine.lives ? 1 : 0.3)
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
            let _ = engine.frame   // depend on the frame tick so Canvas redraws
            Canvas { ctx, size in
                // Starfield.
                for s in stars {
                    let rect = CGRect(x: s.0 * size.width, y: s.1 * size.height, width: s.2, height: s.2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.35)))
                }
                // Asteroids.
                for r in engine.rocks {
                    var p = Path()
                    let n = r.verts.count
                    for i in 0..<n {
                        let a = r.angle + CGFloat(i) / CGFloat(n) * 2 * .pi
                        let rad = r.radius * r.verts[i]
                        let pt = CGPoint(x: r.x + cos(a) * rad, y: r.y + sin(a) * rad)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                    ctx.fill(p, with: .linearGradient(
                        Gradient(colors: [Color(white: 0.45), Color(white: 0.22)]),
                        startPoint: CGPoint(x: r.x, y: r.y - r.radius),
                        endPoint: CGPoint(x: r.x, y: r.y + r.radius)))
                    ctx.stroke(p, with: .color(.white.opacity(0.5)), lineWidth: 1.2)
                }
                // Bullets.
                for b in engine.bullets {
                    let dot = CGRect(x: b.x - 2.5, y: b.y - 2.5, width: 5, height: 5)
                    ctx.fill(Path(ellipseIn: dot.insetBy(dx: -3, dy: -3)), with: .color(accent.opacity(0.4)))
                    ctx.fill(Path(ellipseIn: dot), with: .color(.white))
                }
                // Ship.
                if !engine.gameOver, engine.invincible <= 0 || (engine.frame / 8) % 2 == 0 {
                    let r = engine.shipR
                    let pts = [CGPoint(x: 0, y: -r),
                               CGPoint(x: -r * 0.72, y: r * 0.78),
                               CGPoint(x: 0, y: r * 0.4),
                               CGPoint(x: r * 0.72, y: r * 0.78)]
                    var ship = Path()
                    for (i, pt) in pts.enumerated() {
                        let rx = pt.x * cos(engine.shipAngle) - pt.y * sin(engine.shipAngle)
                        let ry = pt.x * sin(engine.shipAngle) + pt.y * cos(engine.shipAngle)
                        let g = CGPoint(x: engine.shipX + rx, y: engine.shipY + ry)
                        if i == 0 { ship.move(to: g) } else { ship.addLine(to: g) }
                    }
                    ship.closeSubpath()
                    ctx.fill(ship, with: .linearGradient(
                        Gradient(colors: [accent.opacity(0.95), accent.opacity(0.55)]),
                        startPoint: CGPoint(x: engine.shipX, y: engine.shipY - r),
                        endPoint: CGPoint(x: engine.shipX, y: engine.shipY + r)))
                    ctx.stroke(ship, with: .color(.white.opacity(0.85)), lineWidth: 1.4)

                    // Thrust flame.
                    if engine.thrusting {
                        let fa = engine.shipAngle
                        let bx = engine.shipX - sin(fa) * r * 0.9
                        let by = engine.shipY + cos(fa) * r * 0.9
                        let flame = CGRect(x: bx - 3, y: by - 3, width: 6, height: 6)
                        ctx.fill(Path(ellipseIn: flame), with: .color(.orange.opacity(0.9)))
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.02)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
            .onAppear { engine.configure(geo.size) }
            .onChange(of: geo.size) { _, s in engine.configure(s) }
        }
    }

    private var controls: some View {
        HStack {
            HStack(spacing: Spacing.sm) {
                holdButton("arrow.counterclockwise", press: { engine.rotatingLeft = true }, release: { engine.rotatingLeft = false })
                holdButton("arrow.clockwise", press: { engine.rotatingRight = true }, release: { engine.rotatingRight = false })
            }
            Spacer()
            HStack(spacing: Spacing.sm) {
                holdButton("flame.fill", tint: .orange, press: { engine.thrusting = true }, release: { engine.thrusting = false })
                holdButton("circle.fill", tint: accent, press: {
                    engine.firing = true; engine.fire()
                }, release: { engine.firing = false })
            }
        }
    }

    private func holdButton(_ symbol: String, tint: Color = .white, press: @escaping () -> Void, release: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 64, height: 56)
            .mtrxLiquidGlass(cornerRadius: Spacing.CornerRadius.md)
            .contentShape(Rectangle())
            // High-priority so the hold isn't stolen by an ancestor scroll or
            // the left-edge back-swipe — otherwise onEnded fires instantly and
            // resets the flag, making only the tap-to-fire button seem to work.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in press() }
                    .onEnded { _ in release() }
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
