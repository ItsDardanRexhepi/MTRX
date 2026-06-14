// GlassOrb.swift
// MTRX
//
// The app's signature orb: a clear, transparent liquid-glass sphere with
// a thin iridescent refraction that drifts across it — reflective and
// see-through, like light catching a glass bead. One reusable view so
// the splash, Home header, floating agent orb, and switcher all share
// the exact same look and behavior.

import SwiftUI

struct GlassOrb: View {
    var size: CGFloat = 54
    /// nil → full rainbow iridescence. A tint array gives an agent its
    /// own gentle key while staying transparent glass.
    var tint: [Color]? = nil
    /// Drives the slow drift of the refraction. Internal by default.
    var animates: Bool = true

    @State private var drift = false
    @State private var pulse = false

    /// The orb's own key color, used for the living halo.
    private var keyColor: Color {
        tint?.first ?? Color(red: 0.60, green: 0.92, blue: 0.96)
    }

    private var film: [Color] {
        tint ?? [
            Color(red: 0.60, green: 0.92, blue: 0.96),
            Color(red: 0.78, green: 0.80, blue: 0.99),
            Color(red: 0.99, green: 0.82, blue: 0.93),
            Color(red: 0.99, green: 0.94, blue: 0.80),
            Color(red: 0.70, green: 0.97, blue: 0.88),
            Color(red: 0.60, green: 0.92, blue: 0.96),
        ]
    }

    var body: some View {
        ZStack {
            // No ambient halo — just the orb itself, nothing radiating from it.

            // Clear glass body — barely there, so the page shows through.
            Circle()
                .fill(.ultraThinMaterial)
                .opacity(0.22)

            // Smooth iridescent refraction filling the whole sphere and
            // dissolving softly toward the edge. No bright blobs, no rim.
            Circle()
                .fill(AngularGradient(colors: film, center: .center))
                .mask(
                    RadialGradient(colors: [.white, .white.opacity(0.35), .white.opacity(0)],
                                   center: .center, startRadius: 1, endRadius: size * 0.52)
                )
                .opacity(0.40)
                .blendMode(.screen)
                .rotationEffect(.degrees(drift ? 360 : 0))

            // A gentle off-center sheen — light through glass, not a dot.
            Circle()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.30), .clear],
                                   center: .init(x: 0.36, y: 0.32),
                                   startRadius: 0, endRadius: size * 0.42)
                )
                .blendMode(.screen)
        }
        .frame(width: size, height: size)
        // The whole sphere breathes — a slow, living pulse.
        .scaleEffect(pulse ? 1.05 : 0.98)
        .onAppear {
            guard animates else { return }
            withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) {
                drift = true
            }
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Per-agent gentle tints for the glass orb — kept faint so the orb
/// still reads as transparent glass, just in their key.
func agentGlassTint(_ agent: AgentAccessControl.ActiveAgent) -> [Color] {
    switch agent {
    case .trinity:
        return [Color(red: 0.60, green: 0.92, blue: 0.96), Color(red: 0.78, green: 0.84, blue: 0.99),
                Color(red: 0.85, green: 0.95, blue: 0.99), Color(red: 0.60, green: 0.92, blue: 0.96)]
    case .morpheus:
        return [Color(red: 0.99, green: 0.80, blue: 0.84), Color(red: 0.99, green: 0.90, blue: 0.80),
                Color(red: 0.98, green: 0.84, blue: 0.95), Color(red: 0.99, green: 0.80, blue: 0.84)]
    case .neo:
        return [Color(red: 0.74, green: 0.96, blue: 0.82), Color(red: 0.92, green: 0.98, blue: 0.78),
                Color(red: 0.72, green: 0.95, blue: 0.93), Color(red: 0.74, green: 0.96, blue: 0.82)]
    }
}
