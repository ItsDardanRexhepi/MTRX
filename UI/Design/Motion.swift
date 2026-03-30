// Motion.swift
// MTRX
//
// HIG-compliant animation system with spring animations and standard curves.

import SwiftUI

// MARK: - Motion System

enum Motion {

    // MARK: - Spring Animations (Apple HIG)

    /// Default interactive spring — responsive feel for UI interactions
    static let springDefault = Animation.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0)

    /// Snappy spring — quick, crisp animations for toggles and selections
    static let springSnappy = Animation.spring(response: 0.25, dampingFraction: 0.9, blendDuration: 0)

    /// Bouncy spring — playful animations for success states and celebrations
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0)

    /// Gentle spring — smooth, relaxed animations for large transitions
    static let springGentle = Animation.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)

    /// Stiff spring — minimal overshoot for precise movements
    static let springStiff = Animation.spring(response: 0.2, dampingFraction: 0.95, blendDuration: 0)

    // MARK: - Standard Durations (Apple HIG)

    /// Ultra-fast — 100ms for micro-interactions (opacity, color changes)
    static let durationUltraFast: Double = 0.1

    /// Fast — 200ms for small element transitions
    static let durationFast: Double = 0.2

    /// Standard — 300ms for most animations
    static let durationStandard: Double = 0.3

    /// Moderate — 400ms for medium transitions
    static let durationModerate: Double = 0.4

    /// Slow — 500ms for large element transitions
    static let durationSlow: Double = 0.5

    /// Extra slow — 700ms for dramatic transitions
    static let durationExtraSlow: Double = 0.7

    // MARK: - Easing Curves

    /// Standard ease in-out for general transitions
    static let easeStandard = Animation.easeInOut(duration: durationStandard)

    /// Ease out for elements entering the screen
    static let easeEnter = Animation.easeOut(duration: durationStandard)

    /// Ease in for elements leaving the screen
    static let easeExit = Animation.easeIn(duration: durationFast)

    /// Linear for progress indicators and continuous animations
    static let linear = Animation.linear(duration: durationStandard)

    // MARK: - Stagger Delay

    /// Calculate stagger delay for list animations
    /// - Parameter index: Item index in the list
    /// - Returns: Delay interval for the item
    static func staggerDelay(for index: Int, baseDelay: Double = 0.05) -> Double {
        Double(index) * baseDelay
    }

    // MARK: - Reduced Motion Support

    /// Returns the appropriate animation respecting reduce motion preferences
    /// - Parameter animation: The desired animation
    /// - Returns: The animation or nil if reduce motion is enabled
    static func respectingReduceMotion(_ animation: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : animation
    }

    /// Returns a cross-dissolve alternative when reduce motion is enabled
    /// - Parameter animation: The desired animation
    /// - Returns: Either the animation or a simple opacity fade
    static func adaptiveAnimation(_ animation: Animation) -> Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .easeInOut(duration: durationFast)
            : animation
    }
}

// MARK: - Animation View Modifiers

extension View {

    /// Apply a spring transition animation
    func mtrxSpringAnimation() -> some View {
        animation(Motion.springDefault, value: UUID())
    }

    /// Fade-in animation from bottom
    func mtrxFadeInFromBottom(isVisible: Bool, delay: Double = 0) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .animation(
                Motion.adaptiveAnimation(Motion.springDefault).delay(delay),
                value: isVisible
            )
    }

    /// Scale-in animation
    func mtrxScaleIn(isVisible: Bool, delay: Double = 0) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.8)
            .animation(
                Motion.adaptiveAnimation(Motion.springBouncy).delay(delay),
                value: isVisible
            )
    }

    /// Shimmer loading effect
    func mtrxShimmer(isActive: Bool) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }

    /// Pulse animation for attention-drawing elements
    func mtrxPulse(isActive: Bool) -> some View {
        modifier(PulseModifier(isActive: isActive))
    }

    /// Staggered list item appearance
    func mtrxStaggeredAppearance(index: Int, isVisible: Bool) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .animation(
                Motion.adaptiveAnimation(Motion.springDefault)
                    .delay(Motion.staggerDelay(for: index)),
                value: isVisible
            )
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if isActive {
            content
                .overlay(
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.3),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: phase * geometry.size.width * 1.6 - geometry.size.width * 0.3)
                    }
                )
                .clipped()
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive && isPulsing ? 1.05 : 1.0)
            .opacity(isActive && isPulsing ? 0.8 : 1.0)
            .onAppear {
                guard isActive else { return }
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Transition Extensions

extension AnyTransition {

    /// Slide up with fade
    static var mtrxSlideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    /// Scale with fade
    static var mtrxScale: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        )
    }

    /// Blur transition
    static var mtrxBlur: AnyTransition {
        .opacity.animation(Motion.easeStandard)
    }
}
