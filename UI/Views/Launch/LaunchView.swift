// LaunchView.swift
// MTRX
//
// The first three seconds of the app: a deep-ocean field, a living
// aurora orb breathing into existence, and the rounded MTRX wordmark.
// Springs only — nothing linear — then a soft handoff into Home.

import SwiftUI

struct LaunchView: View {
    let onComplete: () -> Void

    @State private var orbScale: CGFloat = 0.4
    @State private var orbOpacity: Double = 0
    @State private var haloScale: CGFloat = 0.2
    @State private var haloOpacity: Double = 0
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 16
    @State private var taglineOpacity: Double = 0
    @State private var sceneOpacity: Double = 1
    @State private var breathe = false

    var body: some View {
        ZStack {
            // The ocean field — same world the whole app lives in.
            Color.backgroundPrimary.ignoresSafeArea()

            RadialGradient(
                colors: [Color.trinityPrimary.opacity(0.14), .clear],
                center: .init(x: 0.5, y: 0.32),
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.lg) {
                // The orb — layered light, gently breathing.
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.trinityPrimary, .statusSuccess, .accentPrimary, .purple.opacity(0.7), .trinityPrimary],
                                center: .center
                            )
                        )
                        .frame(width: 132, height: 132)
                        .blur(radius: 26)
                        .scaleEffect(haloScale * (breathe ? 1.06 : 0.96))
                        .opacity(haloOpacity * 0.8)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.95), .trinityPrimary, Color(red: 0.02, green: 0.45, blue: 0.55)],
                                center: .init(x: 0.36, y: 0.30),
                                startRadius: 2,
                                endRadius: 64
                            )
                        )
                        .frame(width: 96, height: 96)
                        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                        .scaleEffect(orbScale * (breathe ? 1.02 : 0.99))
                        .opacity(orbOpacity)
                }
                .drawingGroup()

                VStack(spacing: Spacing.sm) {
                    Text("MTRX")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .kerning(6)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .trinityPrimary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(wordmarkOpacity)
                        .offset(y: wordmarkOffset)

                    Text("Your whole day. One app.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.labelSecondary)
                        .opacity(taglineOpacity)
                }
            }
        }
        .opacity(sceneOpacity)
        .onAppear(perform: run)
    }

    private func run() {
        // Orb blooms in.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) {
            orbScale = 1
            orbOpacity = 1
            haloScale = 1
            haloOpacity = 1
        }
        // It breathes while the wordmark arrives.
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            breathe = true
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.45)) {
            wordmarkOpacity = 1
            wordmarkOffset = 0
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.85)) {
            taglineOpacity = 1
        }
        // Soft handoff.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeInOut(duration: 0.45)) {
                sceneOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onComplete()
            }
        }
    }
}

#Preview {
    LaunchView {}
}
