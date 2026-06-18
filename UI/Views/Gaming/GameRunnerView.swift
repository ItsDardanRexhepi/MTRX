// GameRunnerView.swift
// MTRX
//
// Fully playable on-device demo games. Three mechanics — Targets,
// Reflex, Sequence — each with escalating levels, score, lives, and a
// win state. Everything runs locally; no network, no telemetry.

import SwiftUI

// MARK: - Game Runner

struct GameRunnerView: View {
    let game: GameItem

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: GameEngine

    init(game: GameItem) {
        self.game = game
        _engine = StateObject(wrappedValue: GameEngine(game: game))
    }

    var body: some View {
        switch game.kind {
        case .solitaire: SolitaireGameView(accent: game.accent)
        case .blocks:    BlockGameView(accent: game.accent)
        case .match3:    ColorBurstGameView(accent: game.accent)
        case .merge2048: Game2048View(accent: game.accent)
        case .breakout:  BrickBreakerView(accent: game.accent)
        case .asteroids: AsteroidStormView(accent: game.accent)
        default:         arcadeBody
        }
    }

    private var arcadeBody: some View {
        ZStack {
            // Deep arena, tinted to the game's accent.
            LinearGradient(
                colors: [Color.backgroundPrimary, game.accent.opacity(0.10), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                scoreBar

                ZStack {
                    switch engine.phase {
                    case .ready:
                        readyOverlay
                    case .playing:
                        playfield
                    case .levelComplete:
                        levelCompleteOverlay
                    case .won:
                        endOverlay(won: true)
                    case .lost:
                        endOverlay(won: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear { engine.stop() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .accessibilityLabel("Close game")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            Spacer()
            Text(game.name)
                .font(.mtrxHeadline)
                .foregroundStyle(.white)
            Spacer()
            // Record / clip this game (ReplayKit). Sits where the layout-balance
            // slot was, mirroring the close button on the left.
            GameRecordControl()
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.top, Spacing.sm)
    }

    private var scoreBar: some View {
        HStack(spacing: Spacing.lg) {
            stat("LEVEL", "\(engine.level)/\(engine.maxLevel)")
            stat("SCORE", "\(engine.score)")
            HStack(spacing: 3) {
                ForEach(0..<engine.maxLives, id: \.self) { i in
                    Image(systemName: i < engine.lives ? "heart.fill" : "heart")
                        .font(.system(size: 13))
                        .foregroundStyle(i < engine.lives ? game.accent : Color.labelTertiary)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.contentPadding)
        .frame(maxWidth: .infinity)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.labelTertiary).kerning(1)
            Text(value).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.white)
        }
    }

    // MARK: Playfield

    @ViewBuilder
    private var playfield: some View {
        switch game.kind {
        case .targets: targetsField
        case .reflex:  reflexField
        case .sequence: sequenceField
        default: EmptyView()
        }
    }

    private var targetsField: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(engine.targets) { target in
                    Circle()
                        .fill(
                            RadialGradient(colors: [.white, game.accent, game.accent.opacity(0.3)],
                                           center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 34)
                        )
                        .frame(width: 58, height: 58)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                        .shadow(color: game.accent.opacity(0.6), radius: 10)
                        .position(x: target.x * geo.size.width, y: target.y * geo.size.height)
                        .opacity(target.life)
                        .onTapGesture { engine.hitTarget(target.id) }
                }
            }
            .onAppear { engine.fieldSize = geo.size }
        }
    }

    private var reflexField: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text(engine.reflexArmed ? "TAP NOW" : "wait for teal…")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(engine.reflexArmed ? game.accent : Color.labelSecondary)

            Circle()
                .fill(engine.reflexArmed ? game.accent : Color.surfaceElevated)
                .frame(width: 200, height: 200)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 2))
                .shadow(color: engine.reflexArmed ? game.accent.opacity(0.7) : .clear, radius: 24)
                .scaleEffect(engine.reflexArmed ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.12), value: engine.reflexArmed)
                .onTapGesture { engine.reflexTap() }
            Spacer()
            Text("Round \(engine.reflexRound)/\(engine.reflexRoundsNeeded) · don't tap early")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelTertiary)
            Spacer()
        }
    }

    private var sequenceField: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Text(engine.sequenceShowing ? "Watch the pattern" : "Repeat it")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(engine.sequenceShowing ? Color.labelSecondary : game.accent)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                ForEach(0..<4, id: \.self) { pad in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(padColor(pad))
                        .frame(height: 110)
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.15), lineWidth: 1))
                        .scaleEffect(engine.litPad == pad ? 1.04 : 1.0)
                        .shadow(color: engine.litPad == pad ? padBase(pad).opacity(0.8) : .clear, radius: 14)
                        .onTapGesture { engine.tapPad(pad) }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .disabled(engine.sequenceShowing)
            Spacer()
            Text("Pattern length \(engine.sequence.count)")
                .font(.mtrxCaption1)
                .foregroundStyle(Color.labelTertiary)
            Spacer()
        }
    }

    private func padBase(_ pad: Int) -> Color {
        [Color(red: 0.13, green: 0.83, blue: 0.93),
         Color(red: 0.20, green: 0.84, blue: 0.40),
         Color(red: 0.97, green: 0.30, blue: 0.55),
         Color(red: 0.98, green: 0.65, blue: 0.15)][pad % 4]
    }
    private func padColor(_ pad: Int) -> Color {
        engine.litPad == pad ? padBase(pad) : padBase(pad).opacity(0.28)
    }

    // MARK: Overlays

    private var readyOverlay: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 44))
                .foregroundStyle(game.accent)
            Text(rulesText)
                .font(.mtrxBody)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            startButton("Start Level \(engine.level)") { engine.startLevel() }
        }
    }

    private var levelCompleteOverlay: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.statusSuccess)
            Text("Level \(engine.level) cleared")
                .font(.mtrxTitle3).foregroundStyle(.white)
            Text("Score \(engine.score)")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
            startButton("Next Level") { engine.nextLevel() }
        }
    }

    private func endOverlay(won: Bool) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: won ? "trophy.fill" : "xmark.octagon.fill")
                .font(.system(size: 52))
                .foregroundStyle(won ? Color.accentSecondary : Color.statusError)
            Text(won ? "You won!" : "Game over")
                .font(.mtrxTitle1).foregroundStyle(.white)
            Text("Final score \(engine.score)")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
            if won {
                Text("All \(engine.maxLevel) levels cleared · \(game.name)")
                    .font(.mtrxCaption1).foregroundStyle(Color.labelTertiary)
            }
            startButton("Play Again") { engine.reset() }
            Button("Leave") { dismiss() }
                .font(.mtrxCalloutBold)
                .foregroundStyle(Color.labelSecondary)
                .padding(.top, Spacing.xs)
        }
    }

    private func startButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button {
            MtrxHaptics.impact(.medium)
            action()
        } label: {
            Text(title)
                .font(.mtrxCalloutBold)
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.ms)
                .background(game.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.sm)
    }

    private var rulesText: String {
        switch game.kind {
        case .targets: return "Tap the glowing nodes before they fade. Clear the quota each level — miss too many and you lose a life."
        case .reflex:  return "Wait for the circle to turn teal, then tap as fast as you can. Tap early and you lose a life."
        case .sequence: return "Watch the pattern light up, then repeat it. Each level adds one more step."
        default: return ""
        }
    }
}

// MARK: - Game Engine

@MainActor
final class GameEngine: ObservableObject {
    enum Phase { case ready, playing, levelComplete, won, lost }

    struct Target: Identifiable { let id = UUID(); var x: CGFloat; var y: CGFloat; var life: Double }

    let game: GameItem
    let maxLevel = 5
    let maxLives = 3

    @Published var phase: Phase = .ready
    @Published var level = 1
    @Published var score = 0
    @Published var lives = 3

    // Targets
    @Published var targets: [Target] = []
    var fieldSize: CGSize = .zero
    private var hitsThisLevel = 0
    private var spawnedThisLevel = 0
    private var missesThisLevel = 0

    // Reflex
    @Published var reflexArmed = false
    @Published var reflexRound = 0
    var reflexRoundsNeeded: Int { 3 + level }
    private var reflexWindowOpen = false

    // Sequence
    @Published var sequence: [Int] = []
    @Published var litPad: Int? = nil
    @Published var sequenceShowing = false
    private var inputIndex = 0

    private var timer: Timer?

    init(game: GameItem) { self.game = game }

    // MARK: Lifecycle

    func startLevel() {
        phase = .playing
        switch game.kind {
        case .targets: startTargets()
        case .reflex:  startReflex()
        case .sequence: startSequence()
        default: break
        }
    }

    func nextLevel() {
        level += 1
        if level > maxLevel { phase = .won; return }
        phase = .ready
    }

    func reset() {
        stop()
        level = 1; score = 0; lives = maxLives
        targets = []; sequence = []; reflexRound = 0; litPad = nil
        phase = .ready
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func loseLife() {
        lives -= 1
        MtrxHaptics.error()
        if lives <= 0 { stop(); phase = .lost }
    }

    private func completeLevel() {
        stop()
        score += level * 50
        MtrxHaptics.success()
        phase = (level >= maxLevel) ? .won : .levelComplete
    }

    // MARK: Targets

    private func startTargets() {
        targets = []; hitsThisLevel = 0; spawnedThisLevel = 0; missesThisLevel = 0; spawnAccumulator = 0
        // Generous, then tightening: ~2.6s lifetime at L1 down to ~1.6s.
        let interval = max(0.8, 1.4 - Double(level) * 0.12)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickTargets(spawnEvery: interval) }
        }
    }

    private var spawnAccumulator: Double = 0
    private func tickTargets(spawnEvery: Double) {
        // Age existing targets — slower decay so they're easy to catch.
        let decay = 0.05 / max(1.4, 2.8 - Double(level) * 0.18)
        for i in targets.indices { targets[i].life -= decay }
        let expired = targets.filter { $0.life <= 0 }
        if !expired.isEmpty {
            missesThisLevel += expired.count
            targets.removeAll { $0.life <= 0 }
            // Forgiving: only a run of 5 misses costs a life.
            if missesThisLevel >= 5 { loseLife(); missesThisLevel = 0; if phase == .lost { return } }
        }
        // Spawn, capped so the field never floods.
        spawnAccumulator += 0.05
        let quota = 8 + level * 2
        if spawnAccumulator >= spawnEvery && spawnedThisLevel < quota && targets.count < 4 {
            spawnAccumulator = 0
            spawnedThisLevel += 1
            targets.append(Target(x: .random(in: 0.14...0.86), y: .random(in: 0.14...0.82), life: 1.0))
        }
        if spawnedThisLevel >= quota && targets.isEmpty { completeLevel() }
    }

    func hitTarget(_ id: UUID) {
        guard let idx = targets.firstIndex(where: { $0.id == id }) else { return }
        targets.remove(at: idx)
        score += 10
        hitsThisLevel += 1
        // A clean hit also forgives a little of the miss streak.
        if missesThisLevel > 0 { missesThisLevel -= 1 }
        MtrxHaptics.impact(.light)
    }

    // MARK: Reflex

    private func startReflex() {
        reflexRound = 0
        armNextReflex()
    }

    private func armNextReflex() {
        reflexArmed = false
        reflexWindowOpen = false
        let delay = Double.random(in: 1.0...2.6)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .playing else { return }
                self.reflexArmed = true
                self.reflexWindowOpen = true
                MtrxHaptics.selection()
            }
        }
    }

    func reflexTap() {
        if !reflexWindowOpen {
            // Tapped too early.
            timer?.invalidate()
            loseLife()
            if phase == .playing { armNextReflex() }
            return
        }
        reflexWindowOpen = false
        reflexArmed = false
        reflexRound += 1
        score += 20
        MtrxHaptics.impact(.medium)
        if reflexRound >= reflexRoundsNeeded { completeLevel() }
        else { armNextReflex() }
    }

    // MARK: Sequence

    private func startSequence() {
        sequence = []
        extendAndShowSequence()
    }

    private func extendAndShowSequence() {
        sequence.append(Int.random(in: 0..<4))
        inputIndex = 0
        playSequence()
    }

    private func playSequence() {
        sequenceShowing = true
        litPad = nil
        var step = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.62, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if step < self.sequence.count {
                    self.litPad = self.sequence[step]
                    MtrxHaptics.selection()
                    // Brief flash off.
                    Timer.scheduledTimer(withTimeInterval: 0.34, repeats: false) { _ in
                        Task { @MainActor in self.litPad = nil }
                    }
                    step += 1
                } else {
                    self.timer?.invalidate()
                    self.sequenceShowing = false
                }
            }
        }
    }

    func tapPad(_ pad: Int) {
        guard !sequenceShowing else { return }
        MtrxHaptics.impact(.light)
        litPad = pad
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            Task { @MainActor in self.litPad = nil }
        }
        if sequence[inputIndex] == pad {
            inputIndex += 1
            score += 5
            if inputIndex >= sequence.count {
                // Round done — each level needs level+2 successful rounds.
                if sequence.count >= level + 2 { completeLevel() }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.extendAndShowSequence() } }
            }
        } else {
            loseLife()
            if phase == .playing {
                inputIndex = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.playSequence() }
            }
        }
    }
}
