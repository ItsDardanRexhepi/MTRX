// SocialPlatform.swift
// MTRX
//
// The pieces that make Social feel like a full platform: the user's
// own editable profile (avatar, @username, bio), a stories rail with a
// full-screen viewer, and attachment support — photos, videos, links —
// for posts. Media lives in Application Support; identity fields
// persist via AppStorage.

import AVKit
import PhotosUI
import SwiftUI

// MARK: - Social Identity

/// The user's social identity. Avatar image is stored on disk;
/// everything else in UserDefaults.
@MainActor
final class SocialIdentity: ObservableObject {

    static let shared = SocialIdentity()

    @AppStorage("com.mtrx.social.username") var username: String = ""
    @AppStorage("com.mtrx.social.bio") var bio: String = "Building on MTRX."
    @Published var avatarImage: UIImage?

    static let mediaDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTRX/SocialMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var avatarURL: URL { Self.mediaDirectory.appendingPathComponent("avatar.jpg") }

    private init() {
        if let data = try? Data(contentsOf: avatarURL) {
            avatarImage = UIImage(data: data)
        }
    }

    func updateAvatar(_ image: UIImage) {
        avatarImage = image
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: avatarURL, options: .atomic)
        }
    }

    /// Effective @handle — falls back to a handle derived from the
    /// display name until the user sets their own.
    func handle(displayName: String) -> String {
        if !username.isEmpty {
            return username.hasPrefix("@") ? username : "@" + username
        }
        let base = displayName.isEmpty ? "you" : displayName.lowercased().replacingOccurrences(of: " ", with: "")
        return "@" + base + ".eth"
    }

    /// Save arbitrary media data into the social media directory.
    static func saveMedia(_ data: Data, fileExtension: String) -> String {
        let name = UUID().uuidString + "." + fileExtension
        try? data.write(to: mediaDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func mediaURL(_ fileName: String) -> URL {
        mediaDirectory.appendingPathComponent(fileName)
    }
}

// MARK: - Stories

struct SocialStory: Identifiable {
    let id = UUID()
    let author: String
    let initials: String
    let color: Color
    /// nil image → gradient placeholder story (sample accounts).
    var image: UIImage?
    let caption: String
    let timestamp: Date
    var isMine: Bool = false
}

@MainActor
final class StoryStore: ObservableObject {

    static let shared = StoryStore()

    @Published var stories: [SocialStory] = []

    private init() {
        let now = Date()
        stories = [
            SocialStory(author: "Elena Vasquez", initials: "EV", color: .accentPrimary, image: nil,
                        caption: "Escrow contract live on Base 🚀", timestamp: now.addingTimeInterval(-5400)),
            SocialStory(author: "Ravi Patel", initials: "RP", color: .statusInfo, image: nil,
                        caption: "Vote on Proposal #47 before Friday", timestamp: now.addingTimeInterval(-9000)),
            SocialStory(author: "Sofia Nakamura", initials: "SN", color: .accentTertiary, image: nil,
                        caption: "8.7% APY on the 90-day vault", timestamp: now.addingTimeInterval(-12600)),
        ]
        // Restore the user's story from disk if one was posted recently.
        let url = SocialIdentity.mediaDirectory.appendingPathComponent("my-story.jpg")
        if let data = try? Data(contentsOf: url),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 24 * 60 * 60,
           let image = UIImage(data: data) {
            stories.insert(SocialStory(author: "Your Story", initials: "ME", color: .trinityPrimary,
                                       image: image, caption: "", timestamp: modified, isMine: true), at: 0)
        }
    }

    func setMyStory(_ image: UIImage, author: String) {
        stories.removeAll { $0.isMine }
        stories.insert(SocialStory(author: author.isEmpty ? "Your Story" : author,
                                   initials: "ME", color: .trinityPrimary,
                                   image: image, caption: "", timestamp: Date(), isMine: true), at: 0)
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: SocialIdentity.mediaDirectory.appendingPathComponent("my-story.jpg"), options: .atomic)
        }
    }
}

// MARK: - Stories Rail

struct StoriesRail: View {
    @ObservedObject private var store = StoryStore.shared
    @ObservedObject private var identity = SocialIdentity.shared
    @EnvironmentObject private var appState: AppState

    @State private var viewingStory: SocialStory?
    @State private var storyPickerItem: PhotosPickerItem?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                // Your story — add or view.
                if let mine = store.stories.first(where: { $0.isMine }) {
                    storyBubble(mine)
                } else {
                    PhotosPicker(selection: $storyPickerItem, matching: .images) {
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottomTrailing) {
                                avatarCircle
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.accentPrimary)
                                    .background(Circle().fill(Color.backgroundPrimary))
                            }
                            Text("Your Story")
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(store.stories.filter { !$0.isMine }) { story in
                    storyBubble(story)
                }
            }
            .padding(.horizontal, Spacing.contentPadding)
            .padding(.vertical, Spacing.sm)
        }
        .onChange(of: storyPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    store.setMyStory(image, author: appState.displayName.isEmpty ? "Your Story" : appState.displayName)
                    MtrxHaptics.success()
                }
                storyPickerItem = nil
            }
        }
        .fullScreenCover(item: $viewingStory) { story in
            StoryViewer(story: story)
        }
    }

    private var avatarCircle: some View {
        Group {
            if let avatar = identity.avatarImage {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [.trinityPrimary, .trinitySecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(Circle())
    }

    private func storyBubble(_ story: SocialStory) -> some View {
        Button {
            MtrxHaptics.impact(.light)
            viewingStory = story
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(colors: [.trinityPrimary, .accentPrimary, .statusSuccess],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2.5
                        )
                        .frame(width: 68, height: 68)

                    Group {
                        if let image = story.image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            LinearGradient(colors: [story.color, story.color.opacity(0.5)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .overlay(
                                    Text(story.initials)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                }

                Text(story.isMine ? "Your Story" : story.author.split(separator: " ").first.map(String.init) ?? story.author)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Story Viewer

struct StoryViewer: View {
    let story: SocialStory
    @Environment(\.dismiss) private var dismiss
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            Group {
                if let image = story.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    LinearGradient(colors: [story.color, .black], startPoint: .top, endPoint: .bottom)
                        .overlay(
                            Text(story.caption)
                                .font(.mtrxTitle2)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(Spacing.xl)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: Spacing.ms) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25)).frame(height: 3)
                        Capsule().fill(.white).frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)

                HStack(spacing: Spacing.ms) {
                    Circle()
                        .fill(story.color)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Text(story.initials)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        )

                    Text(story.author)
                        .font(.mtrxCaptionBold)
                        .foregroundStyle(.white)

                    Text(story.timestamp.formatted(.relative(presentation: .named)))
                        .font(.mtrxCaption2)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
        }
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.linear(duration: 5)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.1) { dismiss() }
        }
    }
}

// MARK: - Profile Sheet

struct SocialProfileSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var identity = SocialIdentity.shared
    @Environment(\.dismiss) private var dismiss

    /// All posts in the feed authored by the user.
    let myPosts: [SocialPostDisplay]

    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var editingName = ""
    @State private var editingUsername = ""
    @State private var editingBio = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Avatar — tap to change.
                    PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let avatar = identity.avatarImage {
                                    Image(uiImage: avatar).resizable().scaledToFill()
                                } else {
                                    LinearGradient(colors: [.trinityPrimary, .trinitySecondary],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                        .overlay(
                                            Text(initials)
                                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                        )
                                }
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.trinityPrimary.opacity(0.5), lineWidth: 2))

                            Image(systemName: "camera.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.accentPrimary)
                                .background(Circle().fill(Color.backgroundPrimary))
                        }
                    }
                    .buttonStyle(.plain)

                    // Stats — social proof, front and center.
                    HStack(spacing: 0) {
                        statColumn("\(myPosts.count)", "Posts")
                        statColumn("1.2K", "Followers")
                        statColumn("348", "Following")
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(Color.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))

                    // Editable identity
                    VStack(alignment: .leading, spacing: Spacing.ms) {
                        fieldLabel("Display name")
                        TextField("Your name", text: $editingName)
                            .textFieldStyle(.plain)
                            .font(.mtrxBody)
                            .padding(Spacing.ms)
                            .background(Color.surfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                        fieldLabel("Username")
                        TextField("@username", text: $editingUsername)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.mtrxBody)
                            .padding(Spacing.ms)
                            .background(Color.surfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))

                        fieldLabel("Bio")
                        TextField("Tell people about yourself", text: $editingBio, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                            .font(.mtrxBody)
                            .padding(Spacing.ms)
                            .background(Color.surfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                    }

                    Button {
                        appState.updateDisplayName(editingName)
                        identity.username = editingUsername.trimmingCharacters(in: .whitespaces)
                        identity.bio = editingBio
                        saved = true
                        MtrxHaptics.success()
                    } label: {
                        Text("Save Profile")
                    }
                    .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))

                    // My posts
                    if !myPosts.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.ms) {
                            Text("My Posts")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                                .textCase(.uppercase)
                                .kerning(1.1)

                            ForEach(myPosts) { post in
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(post.body)
                                        .font(.mtrxCallout)
                                        .foregroundStyle(Color.labelPrimary)
                                        .lineLimit(3)
                                    Text("\(post.likeCount) likes · \(post.timestamp.formatted(.relative(presentation: .named)))")
                                        .font(.mtrxCaption2)
                                        .foregroundStyle(Color.labelTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Spacing.ms)
                                .background(Color.surfaceCard)
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("My Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Profile Saved", isPresented: $saved) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your name, username, and bio are updated everywhere.")
            }
            .onAppear {
                editingName = appState.displayName
                editingUsername = identity.username.isEmpty
                    ? identity.handle(displayName: appState.displayName)
                    : identity.username
                editingBio = identity.bio
            }
            .onChange(of: avatarPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        identity.updateAvatar(image)
                        MtrxHaptics.success()
                    }
                    avatarPickerItem = nil
                }
            }
        }
    }

    private var initials: String {
        let name = appState.displayName
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }
        return parts.isEmpty ? "ME" : parts.joined().uppercased()
    }

    private func statColumn(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.mtrxHeadline)
                .foregroundStyle(Color.labelPrimary)
            Text(label)
                .font(.mtrxCaption2)
                .foregroundStyle(Color.labelTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.mtrxCaption1)
            .foregroundStyle(Color.labelSecondary)
    }
}

// MARK: - Post Attachment Views

/// Renders a post's attached photo, video, or link.
struct PostAttachmentView: View {
    let imageData: Data?
    let videoFileName: String?
    let linkURL: String?

    @State private var playingVideo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
            }

            if let videoFileName {
                Button {
                    playingVideo = true
                } label: {
                    HStack(spacing: Spacing.ms) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.accentPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Video")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelPrimary)
                            Text("Tap to play")
                                .font(.mtrxCaption2)
                                .foregroundStyle(Color.labelTertiary)
                        }
                        Spacer()
                    }
                    .padding(Spacing.ms)
                    .background(Color.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $playingVideo) {
                    VideoPlayer(player: AVPlayer(url: SocialIdentity.mediaURL(videoFileName)))
                        .ignoresSafeArea()
                        .presentationDetents([.large])
                }
            }

            if let linkURL, let url = URL(string: linkURL) {
                Link(destination: url) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "link")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentPrimary)
                        Text(linkURL)
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.accentPrimary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.labelTertiary)
                    }
                    .padding(Spacing.ms)
                    .background(Color.accentPrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                }
            }
        }
    }
}
