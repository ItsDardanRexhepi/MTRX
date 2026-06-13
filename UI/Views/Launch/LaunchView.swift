// LaunchView.swift
// MTRX
//
// The launch is a portal: a glass orb breathes into existence, then the
// ocean dissolves and the orb expands as a clear glass window — Home is
// already mounted beneath, so you come straight through the portal into
// the app with one continuous transition and no black buffer.

import SwiftUI

struct LaunchView: View {
    let onComplete: () -> Void

    @State private var orbScale: CGFloat = 0.35
    @State private var orbOpacity: Double = 0
    @State private var auraOpacity: Double = 0
    @State private var bgOpacity: Double = 1
    @State private var breathe = false
    /// Expands the orb into a full-screen glass window onto Home.
    @State private var portalScale: CGFloat = 1
    @State private var orbExitOpacity: Double = 1

    var body: some View {
        ZStack {
            // The ocean field — fades early so Home shows through the orb.
            Color.backgroundPrimary
                .ignoresSafeArea()
                .opacity(bgOpacity)

            RadialGradient(
                colors: [Color.trinityPrimary.opacity(0.16), .clear],
                center: .init(x: 0.5, y: 0.42),
                startRadius: 10, endRadius: 420
            )
            .ignoresSafeArea()
            .opacity(auraOpacity)

            // The signature glass orb — transparent, so as it expands it
            // becomes a window onto Home beneath.
            GlassOrb(size: 132)
                .scaleEffect(orbScale * (breathe ? 1.03 : 0.99) * portalScale)
                .opacity(orbOpacity * orbExitOpacity)
        }
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
        // The portal opens — gently, so it never flashes bright.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            // Ocean + aura fade first → Home is revealed beneath the orb.
            withAnimation(.easeInOut(duration: 0.55)) {
                bgOpacity = 0
                auraOpacity = 0
            }
            // The glass orb expands, but a softer scale so it doesn't
            // engulf the screen in light.
            withAnimation(.easeInOut(duration: 0.85)) {
                portalScale = 13
            }
            // The glass dissolves as it grows — overlapping the zoom so
            // the brightness peels away instead of filling the screen.
            withAnimation(.easeInOut(duration: 0.7).delay(0.18)) {
                orbExitOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                onComplete()
            }
        }
    }
}

#Preview {
    LaunchView {}
}
