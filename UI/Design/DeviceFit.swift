// DeviceFit.swift
// MTRX — one look on every iPhone
//
// The app is composed against the largest iPhone (17 / 16 Pro Max). Fixed
// screens — the Home dashboard, the Account page — are meant to sit on ONE
// screen with nothing clipped, nothing off the edge, and no scrolling. On a
// smaller iPhone the very same composition simply wouldn't fit at the same
// point sizes, so it would clip or start scrolling.
//
// `FitToReferenceScreen` removes that difference: it lays a screen out at the
// proportions it has on the reference device, then uniformly scales the whole
// thing to the actual device. Every iPhone therefore shows the IDENTICAL
// layout — same spacing, same balance — just resized to its screen. On the
// reference device the scale is exactly 1.0 (pixel-for-pixel unchanged); every
// smaller iPhone shrinks to fit. It never scales UP past the reference.

import SwiftUI

enum DeviceFit {
    /// The design reference: iPhone 17 / 16 Pro Max in portrait points. This is
    /// the LARGEST iPhone, so the per-device scale below is always ≤ 1.
    static let referenceScreen = CGSize(width: 440, height: 956)

    /// The current device's full portrait screen size. Read from the active
    /// window scene (the app is iPhone-only, portrait, single-window), falling
    /// back to the main screen if no scene is attached yet.
    static var screenSize: CGSize {
        let sceneSize = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.size
        return sceneSize ?? UIScreen.main.bounds.size
    }

    /// Uniform shrink factor for THIS device versus the reference — 1.0 on a
    /// Pro Max, smaller on every other iPhone, never above 1.0. A single number
    /// per device, so every fixed screen scales in lockstep and the app looks
    /// the same everywhere.
    static var scale: CGFloat {
        let s = screenSize
        guard s.width > 0, s.height > 0 else { return 1 }
        return min(min(s.width / referenceScreen.width,
                       s.height / referenceScreen.height), 1)
    }
}

/// Wraps a fixed-composition screen so it renders at the reference device's
/// proportions and is then scaled to fit the real device. Use it around a
/// screen that must fit on ONE screen with no scroll (the Home dashboard, the
/// Account page). The content is handed a canvas the size this area WOULD be on
/// the reference device, so the layout is identical everywhere; scaling that
/// canvas back down by the same factor lands it exactly in the real area, with
/// nothing clipped and nothing off-screen.
struct FitToReferenceScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let scale = DeviceFit.scale
        GeometryReader { geo in
            content
                .frame(width: geo.size.width / scale,
                       height: geo.size.height / scale,
                       alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

extension View {
    /// Lay this fixed-composition screen out at reference proportions and scale
    /// it to fit the current iPhone — identical look on every device, no scroll,
    /// nothing off-screen. See `FitToReferenceScreen`.
    func fitToReferenceScreen() -> some View {
        FitToReferenceScreen { self }
    }
}
