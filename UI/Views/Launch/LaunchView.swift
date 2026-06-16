// LaunchView.swift
// MTRX
//
// The launch is a portal: a glass orb breathes into existence, then the
// ocean dissolves and the orb expands as a clear glass window — the app is
// already mounted beneath, so you come straight through the portal into
// it with one continuous transition. It always completes on its own.

import SwiftUI

struct LaunchView: View {
    let onComplete: () -> Void

    @State private var orbScale: CGFloat = 0.35
    @State private var orbOpacity: Double = 0
    @State private var auraOpacity: Double = 0
    @State private var bgOpacity: Double = 1
    @State private var breathe = false
    /// Expands the orb into a full-screen glass window onto whatever is beneath.
    @State private var portalScale: CGFloat = 1
    @State private var orbExitOpacity: Double = 1

    var body: some View {
        ZStack {
            // The ocean field — fades early so the app shows through the orb.
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

            // An edgeless bloom of light that feathers away to nothing, then
            // pulses and dissolves into the portal.
            splashOrb
                .scaleEffect(orbScale * (breathe ? 1.05 : 0.97) * portalScale)
                .opacity(orbOpacity * orbExitOpacity)
        }
        .onAppear(perform: run)
    }

    /// The launch light: concentric radial gradients that fade fully to clear
    /// at every edge, softened further with a blur — so there is no visible
    /// shape outline of any kind. It simply belongs to the screen.
    private var splashOrb: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.82, green: 0.96, blue: 0.99).opacity(0.55),
                    Color(red: 0.66, green: 0.91, blue: 0.97).opacity(0.30),
                    Color(red: 0.58, green: 0.86, blue: 0.95).opacity(0.10),
                    Color(red: 0.55, green: 0.84, blue: 0.94).opacity(0.0),
                ],
                center: .center, startRadius: 2, endRadius: 150
            )
            RadialGradient(
                colors: [Color(red: 0.87, green: 0.85, blue: 0.99).opacity(0.30), .clear],
                center: .init(x: 0.42, y: 0.40),
                startRadius: 0, endRadius: 120
            )
            .blendMode(.screen)
        }
        .frame(width: 300, height: 300)
        .blur(radius: 7)
    }

    private func run() {
        // Orb blooms in.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) {
            orbScale = 1; orbOpacity = 1; auraOpacity = 1
        }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            breathe = true
        }
        // The portal opens on its own — it never waits on anything, so it can
        // never get stuck. The app (Home, or the Face-ID orb that swaps to
        // Home) is revealed beneath.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.6)) {
                bgOpacity = 0
                auraOpacity = 0
            }
            withAnimation(.easeInOut(duration: 0.85)) {
                portalScale = 2.8
            }
            withAnimation(.easeInOut(duration: 0.75)) {
                orbExitOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) {
                onComplete()
            }
        }
    }
}

#Preview {
    LaunchView {}
}
