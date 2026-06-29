// StoryAvatar.swift
// MTRX — a profile avatar that wears a social story ring
//
// Shows a contact's profile photo (or initials), wrapped in a story ring when
// they have an active story: a bright cyan ring for an everyone story, a green
// ring for a close-friends story, a gray ring once you've watched it, and no ring
// when there's nothing to view. The footprint stays constant whether or not a
// ring is present, so rows stay aligned. Ring state is resolved from StoryStore
// (24h expiry + a viewed-set), and the colors mirror the Social stories rail.

import SwiftUI

struct StoryAvatar: View {
    let initials: String
    let color: Color
    var image: UIImage? = nil
    /// Total footprint (kept constant so ringed and ring-less rows align).
    var size: CGFloat = 52
    var ring: StoryStore.StoryRing = .none

    private let ringWidth: CGFloat = 2.5
    private let gap: CGFloat = 3

    private var hasRing: Bool { ring != .none }
    /// The inner photo shrinks when a ring is present so the footprint is constant.
    private var inner: CGFloat { hasRing ? size - (ringWidth + gap) * 2 : size }

    var body: some View {
        ZStack {
            if hasRing {
                Circle()
                    .stroke(ringStyle, lineWidth: ringWidth)
                    .frame(width: size - ringWidth, height: size - ringWidth)
            }
            avatar
                .frame(width: inner, height: inner)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var avatar: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Circle()
                .fill(LinearGradient(colors: [color, color.opacity(0.65)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Text(initials.prefix(2).uppercased())
                        .font(.system(size: inner * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
        }
    }

    private var ringStyle: AnyShapeStyle {
        switch ring {
        case .everyone:
            // Same cyan→aqua→green lockup the stories rail uses for everyone stories.
            return AnyShapeStyle(LinearGradient(colors: [.trinityPrimary, .accentPrimary, .statusSuccess],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .closeFriends:
            return AnyShapeStyle(LinearGradient(colors: [.statusSuccess, .statusSuccess.opacity(0.6)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .seen:
            return AnyShapeStyle(Color.labelQuaternary)
        case .none:
            return AnyShapeStyle(Color.clear)
        }
    }
}

extension View {
    /// Routes taps on a story avatar to the story viewer when (and only when) the
    /// person has a story — taps elsewhere on the row fall through to opening the chat.
    @ViewBuilder
    func storyTap(_ enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            highPriorityGesture(TapGesture().onEnded(action))
        } else {
            self
        }
    }
}
