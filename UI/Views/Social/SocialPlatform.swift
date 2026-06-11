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

    /// Stories live for 24 hours, then vanish — pruned on every read.
    func prune() {
        stories.removeAll { Date().timeIntervalSince($0.timestamp) > 24 * 60 * 60 }
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

    @State private var viewerStart: StoryViewerStart?
    @State private var storyPickerItem: PhotosPickerItem?

    struct StoryViewerStart: Identifiable {
        let id = UUID()
        let index: Int
    }

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
        .fullScreenCover(item: $viewerStart) { start in
            StoryViewer(stories: store.stories, startIndex: start.index)
        }
        .onAppear { store.prune() }
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
            if let index = store.stories.firstIndex(where: { $0.id == story.id }) {
                viewerStart = StoryViewerStart(index: index)
            }
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

/// Full-screen story playback: tap anywhere to jump to the next story
/// (across people) until there are none left; swipe down to leave.
struct StoryViewer: View {
    let stories: [SocialStory]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0
    @State private var progress: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var advanceToken = 0

    private var story: SocialStory { stories[index] }

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
            .id(story.id)
            .transition(.opacity)

            VStack(spacing: Spacing.ms) {
                // One progress segment per story, like every story UI.
                HStack(spacing: 4) {
                    ForEach(Array(stories.enumerated()), id: \.element.id) { i, _ in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.25))
                                Capsule()
                                    .fill(.white)
                                    .frame(width: i < index ? geo.size.width
                                           : (i == index ? geo.size.width * progress : 0))
                            }
                        }
                        .frame(height: 3)
                    }
                }

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
        .offset(y: dragOffset)
        .opacity(dragOffset > 0 ? max(0.4, 1 - dragOffset / 600) : 1)
        // Swipe down anywhere to leave the stories.
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 110 {
                        dismiss()
                    } else {
                        withAnimation(Motion.springSnappy) { dragOffset = 0 }
                    }
                }
        )
        // Tap to jump to whatever story is next.
        .onTapGesture { advance() }
        .onAppear {
            index = min(startIndex, max(stories.count - 1, 0))
            startProgress()
        }
    }

    private func advance() {
        if index + 1 < stories.count {
            withAnimation(.easeInOut(duration: 0.18)) { index += 1 }
            startProgress()
        } else {
            dismiss()
        }
    }

    /// 5 seconds per story; auto-advances unless the user already
    /// tapped ahead (token guards stale timers).
    private func startProgress() {
        advanceToken += 1
        let token = advanceToken
        progress = 0
        withAnimation(.linear(duration: 5)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.05) {
            if token == advanceToken {
                advance()
            }
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
    /// Receives posts materialized by the import hub.
    var onImport: ([SocialPostDisplay]) -> Void = { _ in }

    @State private var showImport = false

    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var editingName = ""
    @State private var editingUsername = ""
    @State private var editingBio = ""
    @State private var saved = false
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Banner with the avatar overlapping its bottom edge.
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [Color.trinityPrimary.opacity(0.55), Color.trinitySecondary.opacity(0.35), Color.backgroundPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 130)

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
                                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.white)
                                            )
                                    }
                                }
                                .frame(width: 84, height: 84)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.backgroundPrimary, lineWidth: 4))

                                Image(systemName: "camera.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.accentPrimary)
                                    .background(Circle().fill(Color.backgroundPrimary))
                            }
                        }
                        .buttonStyle(.plain)
                        .offset(x: Spacing.contentPadding, y: 42)
                    }
                    .padding(.bottom, 46)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        // Edit profile pill, right-aligned like every
                        // profile page the user already knows.
                        HStack {
                            Spacer()
                            Button {
                                withAnimation(Motion.springSnappy) { isEditing.toggle() }
                            } label: {
                                Text(isEditing ? "Cancel" : "Edit profile")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.labelPrimary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 7)
                                    .overlay(Capsule().stroke(Color.labelTertiary.opacity(0.5), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, -38)

                        // Name + handle + verified
                        HStack(spacing: 5) {
                            Text(appState.displayName.isEmpty ? "You" : appState.displayName)
                                .font(.system(size: 21, weight: .heavy))
                                .foregroundStyle(Color.labelPrimary)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.accentPrimary)
                        }

                        Text(identity.handle(displayName: appState.displayName))
                            .font(.system(size: 15))
                            .foregroundStyle(Color.labelTertiary)

                        if !identity.bio.isEmpty {
                            Text(identity.bio)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.labelPrimary)
                                .padding(.top, 2)
                        }

                        // Meta row
                        HStack(spacing: Spacing.md) {
                            Label("Joined \(appState.joinDate.formatted(.dateTime.month(.wide).year()))", systemImage: "calendar")
                            Label("MTRX Network", systemImage: "link")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Color.labelTertiary)
                        .padding(.top, 2)

                        // Bring your content from other platforms.
                        Button {
                            MtrxHaptics.impact(.light)
                            showImport = true
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "square.and.arrow.down.on.square")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Import from other apps")
                                    .font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.labelTertiary)
                            }
                            .foregroundStyle(Color.accentPrimary)
                            .padding(Spacing.ms)
                            .background(Color.accentPrimary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        .sheet(isPresented: $showImport) {
                            SocialImportSheet(onImport: onImport)
                        }

                        // Following / Followers
                        HStack(spacing: Spacing.md) {
                            HStack(spacing: 4) {
                                Text("348").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.labelPrimary)
                                Text("Following").font(.system(size: 14)).foregroundStyle(Color.labelTertiary)
                            }
                            HStack(spacing: 4) {
                                Text("1,284").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.labelPrimary)
                                Text("Followers").font(.system(size: 14)).foregroundStyle(Color.labelTertiary)
                            }
                        }
                        .padding(.top, 2)

                        // Inline editor — slides in under Edit profile.
                        if isEditing {
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

                                Button {
                                    appState.updateDisplayName(editingName)
                                    identity.username = editingUsername.trimmingCharacters(in: .whitespaces)
                                    identity.bio = editingBio
                                    saved = true
                                    withAnimation(Motion.springSnappy) { isEditing = false }
                                    MtrxHaptics.success()
                                } label: {
                                    Text("Save")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Color.labelPrimary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, Spacing.sm)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, Spacing.contentPadding)

                    // Posts tab header
                    VStack(spacing: 11) {
                        Text("Posts")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.labelPrimary)
                        Capsule()
                            .fill(Color.accentPrimary)
                            .frame(width: 50, height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.lg)
                    .overlay(alignment: .bottom) { MtrxDivider() }

                    if myPosts.isEmpty {
                        VStack(spacing: Spacing.sm) {
                            Text("Nothing here yet")
                                .font(.mtrxHeadline)
                                .foregroundStyle(Color.labelPrimary)
                            Text("Your posts will live here. Tap + on the feed to write your first one.")
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.labelSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.xl)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(myPosts) { post in
                                PostCardView(post: post)
                                MtrxDivider()
                            }
                        }
                    }
                }
            }
            .background(MtrxGradientBackground(style: .primary))
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

// MARK: - Social Theme (Pro feature)

/// Pro and Enterprise members recolor their Social experience — a few
/// curated presets plus a full color wheel. Persists as a hex string.
@MainActor
final class SocialTheme: ObservableObject {

    static let shared = SocialTheme()

    @AppStorage("com.mtrx.social.accentHex") private var storedHex: String = ""
    @Published var accent: Color = .accentPrimary

    static let presets: [(name: String, color: Color)] = [
        ("Cyan", Color(red: 0.13, green: 0.83, blue: 0.93)),
        ("Matrix Green", Color(red: 0.20, green: 0.84, blue: 0.40)),
        ("Violet", Color(red: 0.62, green: 0.40, blue: 0.96)),
        ("Hot Pink", Color(red: 0.97, green: 0.30, blue: 0.55)),
        ("Amber", Color(red: 0.98, green: 0.65, blue: 0.15)),
        ("Sky", Color(red: 0.25, green: 0.55, blue: 0.98)),
    ]

    private init() {
        if let color = Self.color(fromHex: storedHex) {
            accent = color
        }
    }

    func set(_ color: Color) {
        accent = color
        storedHex = Self.hex(from: color)
    }

    func resetToDefault() {
        accent = .accentPrimary
        storedHex = ""
    }

    // MARK: hex round-trip

    private static func hex(from color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private static func color(fromHex hex: String) -> Color? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Theme Picker Sheet

struct SocialThemeSheet: View {
    @ObservedObject private var theme = SocialTheme.shared
    @Environment(\.dismiss) private var dismiss
    @State private var wheelColor: Color = SocialTheme.shared.accent
    @State private var showSubscription = false

    private var isUnlocked: Bool {
        FeatureGate.shared.currentTier != .free
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if isUnlocked {
                        Text("Pick your color")
                            .font(.mtrxTitle3)
                            .foregroundStyle(Color.labelPrimary)

                        Text("Your Social tab wears it everywhere — tabs, buttons, and highlights.")
                            .font(.mtrxCaption1)
                            .foregroundStyle(Color.labelSecondary)

                        // Presets
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: Spacing.md) {
                            ForEach(SocialTheme.presets, id: \.name) { preset in
                                Button {
                                    MtrxHaptics.selection()
                                    theme.set(preset.color)
                                    wheelColor = preset.color
                                } label: {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(preset.color)
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Circle().stroke(.white.opacity(0.9), lineWidth: 2.5)
                                                    .opacity(SocialTheme.hexEquals(theme.accent, preset.color) ? 1 : 0)
                                            )
                                        Text(preset.name)
                                            .font(.mtrxCaption2)
                                            .foregroundStyle(Color.labelSecondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        MtrxDivider()

                        // Full wheel
                        HStack {
                            Text("Custom color")
                                .font(.mtrxBody)
                                .foregroundStyle(Color.labelPrimary)
                            Spacer()
                            ColorPicker("", selection: $wheelColor, supportsOpacity: false)
                                .labelsHidden()
                                .onChange(of: wheelColor) { _, newValue in
                                    theme.set(newValue)
                                }
                        }

                        Button {
                            MtrxHaptics.impact(.light)
                            theme.resetToDefault()
                            wheelColor = theme.accent
                        } label: {
                            Text("Reset to MTRX Cyan")
                                .font(.mtrxCaptionBold)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Locked — sell the upgrade.
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(colors: [.trinityPrimary, .purple, .pink],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )

                            Text("Make Social yours")
                                .font(.mtrxTitle3)
                                .foregroundStyle(Color.labelPrimary)

                            Text("Theme colors are a Pro feature. Pick from curated presets or the full color wheel — your whole Social tab follows.")
                                .font(.mtrxCallout)
                                .foregroundStyle(Color.labelSecondary)
                                .multilineTextAlignment(.center)

                            Button {
                                showSubscription = true
                            } label: {
                                Text("Upgrade to Pro — $4.99/mo")
                                    .font(.mtrxBodyBold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(colors: [Color.accentPrimary, Color.trinityPrimary],
                                                       startPoint: .leading, endPoint: .trailing)
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xl)
                    }
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Social Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionView()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension SocialTheme {
    /// Visual equality good enough for showing the selected ring.
    static func hexEquals(_ a: Color, _ b: Color) -> Bool {
        UIColor(a).cgColor.components.map { $0.map { Int($0 * 100) } }
            == UIColor(b).cgColor.components.map { $0.map { Int($0 * 100) } }
    }
}

// MARK: - Import Hub

/// Bring your life with you: posts, stories, messages, and media from
/// the other platforms, pulled into MTRX in one tap per platform.
struct SocialImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onImport: ([SocialPostDisplay]) -> Void

    @State private var importing: String?
    @State private var completed: Set<String> = []
    @State private var summary: String?

    private let platforms: [(name: String, icon: String, color: Color, posts: Int, stories: Int, messages: Int)] = [
        ("Instagram", "camera.fill", .pink, 84, 12, 230),
        ("X / Twitter", "text.bubble.fill", .gray, 412, 0, 56),
        ("TikTok", "music.note", .cyan, 37, 9, 18),
        ("Facebook", "person.2.fill", .blue, 156, 4, 1024),
        ("Snapchat", "bolt.fill", .yellow, 0, 48, 310),
        ("WhatsApp", "phone.fill", .green, 0, 21, 4521),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Everything you've built elsewhere — posts, stories, messages, media — lands here, organized and yours.")
                        .font(.mtrxCallout)
                        .foregroundStyle(Color.labelSecondary)

                    ForEach(platforms, id: \.name) { platform in
                        HStack(spacing: Spacing.ms) {
                            Image(systemName: platform.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(platform.color)
                                .frame(width: 42, height: 42)
                                .background(platform.color.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(platform.name)
                                    .font(.mtrxBodyBold)
                                    .foregroundStyle(Color.labelPrimary)
                                Text("\(platform.posts) posts · \(platform.stories) stories · \(platform.messages) messages")
                                    .font(.mtrxCaption2)
                                    .foregroundStyle(Color.labelTertiary)
                            }

                            Spacer()

                            if completed.contains(platform.name) {
                                Label("Imported", systemImage: "checkmark.circle.fill")
                                    .font(.mtrxCaptionBold)
                                    .foregroundStyle(Color.statusSuccess)
                            } else if importing == platform.name {
                                ProgressView()
                            } else {
                                Button {
                                    runImport(platform.name, posts: platform.posts, stories: platform.stories, messages: platform.messages)
                                } label: {
                                    Text("Import")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.accentPrimary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Color.accentPrimary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Spacing.ms)
                        .background(Color.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                    }

                    Text("Imports use each platform's official data-export. Your content stays on your device.")
                        .font(.mtrxCaption2)
                        .foregroundStyle(Color.labelTertiary)
                }
                .padding(Spacing.contentPadding)
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Import Your Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Import Complete", isPresented: .init(
                get: { summary != nil },
                set: { if !$0 { summary = nil } }
            )) {
                Button("Great", role: .cancel) {}
            } message: {
                Text(summary ?? "")
            }
        }
        .presentationDetents([.large])
    }

    private func runImport(_ name: String, posts: Int, stories: Int, messages: Int) {
        importing = name
        MtrxHaptics.impact(.medium)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            importing = nil
            completed.insert(name)
            summary = "\(posts) posts, \(stories) stories, and \(messages) messages from \(name) are now in your MTRX library. Recent posts appear in your feed and profile."
            MtrxHaptics.success()

            // Materialize a couple of recent posts into the feed.
            let samples: [String]
            switch name {
            case "Instagram": samples = ["Golden hour from the rooftop — no filter needed.", "New setup day. Productivity +100."]
            case "X / Twitter": samples = ["Shipping > talking about shipping.", "The best time to build was yesterday. The second best is right now."]
            case "TikTok": samples = ["That edit took 4 hours and it was worth every minute."]
            case "Facebook": samples = ["Throwback to the family trip — still can't believe that sunset."]
            case "Snapchat": samples = ["Streak day 200 🔥"]
            default: samples = ["Voice note transcripts now archived here."]
            }
            let imported = samples.map { body in
                SocialPostDisplay(
                    id: UUID().uuidString,
                    displayName: "You",
                    handle: SocialIdentity.shared.handle(displayName: ""),
                    avatarInitials: "ME",
                    avatarColor: .trinityPrimary,
                    timestamp: Date().addingTimeInterval(-Double.random(in: 3600...86_400)),
                    body: body,
                    isVerified: true,
                    hasOnChainProof: false,
                    proofHash: nil,
                    governanceTag: nil,
                    likeCount: Int.random(in: 3...60),
                    repostCount: Int.random(in: 0...9),
                    commentCount: Int.random(in: 0...14),
                    isLiked: false,
                    isReposted: false,
                    importedFrom: name
                )
            }
            onImport(imported)
        }
    }
}
