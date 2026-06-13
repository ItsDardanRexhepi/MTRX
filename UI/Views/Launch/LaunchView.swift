// LaunchView.swift
// MTRX
//
// The launch is a portal: a single glass orb breathes into existence,
// then rushes forward and opens straight into the Home screen with a
// silky liquid-glass transition. No wordmark, no tagline — just the orb
// and the door it opens.

import SwiftUI

struct LaunchView: View {
    let onComplete: () -> Void

    @State private var orbScale: CGFloat = 0.35
    @State private var orbOpacity: Double = 0
    @State private var auraOpacity: Double = 0
    @State private var breathe = false
    @State private var sceneOpacity: Double = 1
    /// Expands the orb forward to "open" the portal into Home.
    @State private var portalScale: CGFloat = 1

    var body: some View {
        ZStack {
            // The ocean field — same world Home lives in.
            Color.backgroundPrimary.ignoresSafeArea()

            RadialGradient(
                colors: [Color.trinityPrimary.opacity(0.16), .clear],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 10, endRadius: 420
            )
            .ignoresSafeArea()
            .opacity(auraOpacity)

            // The signature glass orb — clear, reflective, iridescent.
            GlassOrb(size: 132)
                .scaleEffect(orbScale * (breathe ? 1.03 : 0.99) * portalScale)
                .opacity(orbOpacity)
        }
        .opacity(sceneOpacity)
        .onAppear(perform: run)
    }

    private func run() {
        // Orb blooms in.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) {
            orbScale = 1; orbOpacity = 1; auraOpacity = 1
        }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            breathe = true
        }
        // The portal opens: the orb rushes forward, its glass filling the
        // screen, and dissolves straight into Home.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            withAnimation(.easeIn(duration: 0.6)) {
                portalScale = 18
            }
            withAnimation(.easeIn(duration: 0.5).delay(0.18)) {
                sceneOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                onComplete()
            }
        }
    }
}

#Preview {
    LaunchView {}
}
