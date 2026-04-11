// LaunchView.swift
// MTRX
//
// Animated splash screen — the very first thing users see.
// Minimal, premium, and unforgettable.

import SwiftUI

struct LaunchView: View {
    @State private var phase: LaunchPhase = .dark
    @State private var glowOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var ringRotation: Double = 0
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var taglineOffset: CGFloat = 12
    @State private var particleOpacity: Double = 0

    let onComplete: () -> Void

    enum LaunchPhase {
        case dark, logoIn, ringPulse, tagline, fadeOut
    }

    var body: some View {
        ZStack {
            // Deep black background
            Color.black.ignoresSafeArea()

            // Radial glow behind logo
            RadialGradient(
                colors: [
                    Color.accentPrimary.opacity(glowOpacity * 0.25),
                    Color.accentPrimary.opacity(glowOpacity * 0.08),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .ignoresSafeArea()

            // Particle field (subtle floating dots)
            particleField
                .opacity(particleOpacity)

            // Center content
            VStack(spacing: Spacing.lg) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color.accentPrimary,
                                    Color.accentPrimary.opacity(0.3),
                                    Color.accentSecondary.opacity(0.5),
                                    Color.accentPrimary
                                ],
                                center: .center
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                        .rotationEffect(.degrees(ringRotation))

                    // Logo mark
                    Text("M")
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentPrimary, Color.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }

                // Wordmark
                Text("MTRX")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .tracking(8)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .opacity(taglineOpacity)
                    .offset(y: taglineOffset)
            }
        }
        .onAppear(perform: runSequence)
    }

    // MARK: - Particle Field

    private var particleField: some View {
        GeometryReader { geo in
            ForEach(0..<20, id: \.self) { i in
                Circle()
                    .fill(Color.accentPrimary.opacity(Double.random(in: 0.05...0.2)))
                    .frame(width: CGFloat.random(in: 1...3))
                    .position(
                        x: CGFloat.random(in: 0...geo.size.width),
                        y: CGFloat.random(in: 0...geo.size.height)
                    )
            }
        }
    }

    // MARK: - Animation Sequence

    private func runSequence() {
        // Phase 1: Logo appears (0.0 - 0.5s)
        withAnimation(.easeOut(duration: 0.5)) {
            logoOpacity = 1
            logoScale = 1.0
            glowOpacity = 1
        }

        // Phase 2: Ring appears and rotates (0.3s)
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            ringOpacity = 1
            ringScale = 1.0
        }
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false).delay(0.3)) {
            ringRotation = 360
        }

        // Phase 3: Particles fade in (0.5s)
        withAnimation(.easeIn(duration: 0.8).delay(0.5)) {
            particleOpacity = 1
        }

        // Phase 4: Tagline slides up (0.7s)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.7)) {
            taglineOpacity = 1
            taglineOffset = 0
        }

        // Phase 5: Complete after pause (2.0s total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            onComplete()
        }
    }
}

#Preview {
    LaunchView { }
}
