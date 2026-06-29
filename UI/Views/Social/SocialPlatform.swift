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
import WebKit

// MARK: - Social Identity

extension UIImage {
    /// On-device average color — used for the avatar's ambient glow.
    /// All computation is local (CoreImage), nothing leaves the device.
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let filter = CIFilter(name: "CIAreaAverage",
                              parameters: [kCIInputImageKey: inputImage,
                                           kCIInputExtentKey: CIVector(cgRect: extent)])
        guard let output = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(output, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255,
                       green: CGFloat(bitmap[1]) / 255,
                       blue: CGFloat(bitmap[2]) / 255,
                       alpha: 1)
    }
}

/// The user's social identity. Avatar image is stored on disk;
/// everything else in UserDefaults.
@MainActor
final class SocialIdentity: ObservableObject {

    static let shared = SocialIdentity()

    @AppStorage("com.mtrx.social.username") var username: String = ""
    @AppStorage("com.mtrx.social.bio") var bio: String = "Building on MTRX."
    @Published var avatarImage: UIImage?
    @Published var bannerImage: UIImage?
    /// Mirrored from AppState by the Social view so any post card can tell
    /// whether a post belongs to the signed-in user (to show their photo).
    @Published var currentDisplayName: String = ""

    /// The signed-in user's effective @handle.
    var myHandle: String { handle(displayName: currentDisplayName) }

    static let mediaDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTRX/SocialMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var avatarURL: URL { Self.mediaDirectory.appendingPathComponent("avatar.jpg") }
    private var bannerURL: URL { Self.mediaDirectory.appendingPathComponent("banner.jpg") }

    private init() {
        if let data = try? Data(contentsOf: avatarURL) {
            avatarImage = UIImage(data: data)
        }
        if let data = try? Data(contentsOf: bannerURL) {
            bannerImage = UIImage(data: data)
        }
    }

    func updateAvatar(_ image: UIImage) {
        avatarImage = image
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: avatarURL, options: .atomic)
        }
    }

    /// A soft ambient color sampled from the avatar — averages the
    /// image's pixels on-device so the glow matches the photo. Falls
    /// back to the signature teal when there's no photo.
    var avatarGlow: Color {
        guard let image = avatarImage,
              let avg = image.averageColor else { return .trinityPrimary }
        return Color(avg)
    }

    func updateBanner(_ image: UIImage) {
        bannerImage = image
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: bannerURL, options: .atomic)
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

/// Who can see a story — everyone, or just close friends (green ring).
enum StoryAudience: String, Codable {
    case everyone
    case closeFriends
}

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
    var audience: StoryAudience = .everyone
    var fileName: String?
}

@MainActor
final class StoryStore: ObservableObject {

    static let shared = StoryStore()

    @Published var stories: [SocialStory] = []
    /// Handles allowed to see close-friends stories. Persisted.
    @Published var closeFriends: Set<String> {
        didSet { UserDefaults.standard.set(Array(closeFriends), forKey: "com.mtrx.social.closeFriends") }
    }

    /// Authors whose current story stack you've already opened → their ring goes
    /// gray (Instagram/iMessage convention). Keyed by author name → the number of
    /// active stories you'd seen, so a brand-new story (count grows) re-brightens it.
    /// Count-based, not timestamp-based, so a saved "seen" mark survives relaunch
    /// even though sample stories are re-seeded with fresh timestamps each launch.
    @Published private var viewedCounts: [String: Int] = [:]
    private let viewedKey = "com.mtrx.social.viewedStoryCounts"

    /// How a contact's story ring renders in Messages.
    enum StoryRing: Equatable { case none, everyone, closeFriends, seen }

    /// The follower roster offered when picking close friends.
    static let followers: [String] = [
        "@elena.eth", "@ravi_dao", "@sofia.base", "@nomad_anon",
        "@vitalik.eth", "@maria.lens", "@kenji.sol", "@aisha.dao",
    ]

    private var indexURL: URL { SocialIdentity.mediaDirectory.appendingPathComponent("my-stories.json") }

    private struct MyStoryMeta: Codable {
        let fileName: String
        let timestamp: Date
        let audience: StoryAudience
    }

    private init() {
        closeFriends = Set(UserDefaults.standard.stringArray(forKey: "com.mtrx.social.closeFriends") ?? [])
        viewedCounts = (UserDefaults.standard.dictionary(forKey: "com.mtrx.social.viewedStoryCounts") as? [String: Int]) ?? [:]
        let now = Date()
        stories = [
            SocialStory(author: "Elena Vasquez", initials: "EV", color: .accentPrimary, image: nil,
                        caption: "Escrow contract live on Base 🚀", timestamp: now.addingTimeInterval(-5400)),
            SocialStory(author: "Elena Vasquez", initials: "EV", color: .accentPrimary, image: nil,
                        caption: "AMA on trustless escrow at 6pm — bring questions", timestamp: now.addingTimeInterval(-4800)),
            SocialStory(author: "Ravi Patel", initials: "RP", color: .statusInfo, image: nil,
                        caption: "Vote on Proposal #47 before Friday", timestamp: now.addingTimeInterval(-9000)),
            SocialStory(author: "Sofia Nakamura", initials: "SN", color: .accentTertiary, image: nil,
                        caption: "8.7% APY on the 90-day vault", timestamp: now.addingTimeInterval(-12600)),
            SocialStory(author: "Marcus Chen", initials: "MC", color: .statusInfo, image: nil,
                        caption: "Proposal draft is ready for review", timestamp: now.addingTimeInterval(-3000)),
            SocialStory(author: "Aisha Patel", initials: "AP", color: .statusSuccess, image: nil,
                        caption: "Close-friends staking alpha 👀", timestamp: now.addingTimeInterval(-2000),
                        audience: .closeFriends),
            SocialStory(author: "Priya Sharma", initials: "PS", color: .trinityPrimary, image: nil,
                        caption: "Escrow funded — receipts in the thread", timestamp: now.addingTimeInterval(-1500)),
        ]
        restoreMyStories()
    }

    private func restoreMyStories() {
        var restored: [SocialStory] = []
        if let data = try? Data(contentsOf: indexURL),
           let metas = try? JSONDecoder().decode([MyStoryMeta].self, from: data) {
            for meta in metas where Date().timeIntervalSince(meta.timestamp) < 24 * 60 * 60 {
                if let d = try? Data(contentsOf: SocialIdentity.mediaURL(meta.fileName)),
                   let image = UIImage(data: d) {
                    restored.append(SocialStory(author: "Your Story", initials: "ME", color: .trinityPrimary,
                                                image: image, caption: "", timestamp: meta.timestamp,
                                                isMine: true, audience: meta.audience, fileName: meta.fileName))
                }
            }
        } else {
            // Legacy single-story migration.
            let url = SocialIdentity.mediaDirectory.appendingPathComponent("my-story.jpg")
            if let data = try? Data(contentsOf: url),
               let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modified = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) < 24 * 60 * 60,
               let image = UIImage(data: data) {
                restored.append(SocialStory(author: "Your Story", initials: "ME", color: .trinityPrimary,
                                            image: image, caption: "", timestamp: modified,
                                            isMine: true, audience: .everyone, fileName: "my-story.jpg"))
            }
        }
        stories.insert(contentsOf: restored.sorted { $0.timestamp < $1.timestamp }, at: 0)
    }

    /// Stories live for 24 hours, then vanish — pruned on every read.
    func prune() {
        stories.removeAll { Date().timeIntervalSince($0.timestamp) > 24 * 60 * 60 }
        persistIndex()
    }

    /// Add a new story — stacks behind any you've already posted today,
    /// exactly like adding to an Instagram story.
    func addMyStory(_ image: UIImage, author: String, audience: StoryAudience) {
        let fileName = "my-story-\(UUID().uuidString).jpg"
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: SocialIdentity.mediaURL(fileName), options: .atomic)
        }
        let story = SocialStory(author: author.isEmpty ? "Your Story" : author,
                                initials: "ME", color: .trinityPrimary,
                                image: image, caption: "", timestamp: Date(),
                                isMine: true, audience: audience, fileName: fileName)
        let insertAt = stories.lastIndex(where: { $0.isMine }).map { $0 + 1 } ?? 0
        stories.insert(story, at: insertAt)
        persistIndex()
    }

    /// Delete any of your stories, any time.
    func deleteStory(_ id: UUID) {
        guard let idx = stories.firstIndex(where: { $0.id == id }), stories[idx].isMine else { return }
        if let file = stories[idx].fileName {
            try? FileManager.default.removeItem(at: SocialIdentity.mediaURL(file))
        }
        stories.remove(at: idx)
        persistIndex()
    }

    private func persistIndex() {
        let metas = stories.filter(\.isMine).compactMap { story in
            story.fileName.map { MyStoryMeta(fileName: $0, timestamp: story.timestamp, audience: story.audience) }
        }
        if let data = try? JSONEncoder().encode(metas) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    /// Stories grouped per author, yours first — the unit the viewer
    /// plays through, Instagram-style.
    var groups: [[SocialStory]] {
        var order: [String] = []
        var byAuthor: [String: [SocialStory]] = [:]
        for story in stories {
            let key = story.isMine ? "ME" : story.author
            if byAuthor[key] == nil { order.append(key) }
            byAuthor[key, default: []].append(story)
        }
        var result = order.compactMap { byAuthor[$0] }
        if let mineIndex = result.firstIndex(where: { $0.first?.isMine == true }), mineIndex != 0 {
            let mine = result.remove(at: mineIndex)
            result.insert(mine, at: 0)
        }
        return result
    }

    // MARK: - Story ring state (for Messages avatars)

    /// A contact's active (unexpired) stories — what powers the Messages ring.
    func activeStories(forAuthor name: String) -> [SocialStory] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return stories.filter { !$0.isMine && $0.author == name && $0.timestamp > cutoff }
    }

    /// The ring to draw around a contact's avatar in Messages.
    func ring(forAuthor name: String) -> StoryRing {
        let active = activeStories(forAuthor: name)
        guard !active.isEmpty else { return .none }
        if let seen = viewedCounts[name], seen >= active.count { return .seen }
        let representative = active.max { $0.timestamp < $1.timestamp }
        return representative?.audience == .closeFriends ? .closeFriends : .everyone
    }

    /// Index of a contact's story group in `groups`, for opening the viewer.
    func groupIndex(forAuthor name: String) -> Int? {
        groups.firstIndex { $0.first?.isMine != true && $0.first?.author == name }
    }

    /// Record that you've opened a contact's current story stack → ring goes gray
    /// until they post another story (which grows the active count and re-brightens it).
    func markViewed(author name: String) {
        let count = activeStories(forAuthor: name).count
        guard count > 0 else { return }
        viewedCounts[name] = count
        UserDefaults.standard.set(viewedCounts, forKey: viewedKey)
    }
}

// MARK: - Stories Rail

struct StoriesRail: View {
    @ObservedObject private var store = StoryStore.shared
    @ObservedObject private var identity = SocialIdentity.shared
    @EnvironmentObject private var appState: AppState

    @State private var viewerStart: StoryViewerStart?
    @State private var storyPickerItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var showAudienceSheet = false

    struct StoryViewerStart: Identifiable {
        let id = UUID()
        let groupIndex: Int
    }

    private var groups: [[SocialStory]] { store.groups }
    private var myGroupIndex: Int? { groups.firstIndex { $0.first?.isMine == true } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                // Your story — view your stack, or add the first one.
                if let mineIndex = myGroupIndex {
                    storyBubble(group: groups[mineIndex], groupIndex: mineIndex, addsMore: true)
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

                ForEach(Array(groups.enumerated()), id: \.element.first?.id) { index, group in
                    if group.first?.isMine != true {
                        storyBubble(group: group, groupIndex: index, addsMore: false)
                    }
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
                    pendingImage = image
                    showAudienceSheet = true
                }
                storyPickerItem = nil
            }
        }
        .sheet(isPresented: $showAudienceSheet) {
            StoryAudienceSheet(
                onPost: { audience in
                    if let image = pendingImage {
                        store.addMyStory(image,
                                         author: appState.displayName.isEmpty ? "Your Story" : appState.displayName,
                                         audience: audience)
                        MtrxHaptics.success()
                    }
                    pendingImage = nil
                    showAudienceSheet = false
                },
                onCancel: { pendingImage = nil; showAudienceSheet = false }
            )
            .presentationDetents([.height(440)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .fullScreenCover(item: $viewerStart) { start in
            StoryViewer(groups: groups, startGroup: start.groupIndex)
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

    private func storyBubble(group: [SocialStory], groupIndex: Int, addsMore: Bool) -> some View {
        let story = group.first ?? group[0]
        // Close-friends stories wear the green ring, like Instagram.
        let isCloseFriends = story.audience == .closeFriends
        return Button {
            MtrxHaptics.impact(.light)
            if !story.isMine { store.markViewed(author: story.author) }
            viewerStart = StoryViewerStart(groupIndex: groupIndex)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .stroke(
                                isCloseFriends
                                    ? LinearGradient(colors: [.statusSuccess, .statusSuccess.opacity(0.6)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [.trinityPrimary, .accentPrimary, .statusSuccess],
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

                    // Add-more affordance on your own ring.
                    if addsMore {
                        PhotosPicker(selection: $storyPickerItem, matching: .images) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.accentPrimary)
                                .background(Circle().fill(Color.backgroundPrimary))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(story.isMine ? "Your Story" : story.author.split(separator: " ").first.map(String.init) ?? story.author)
                    .font(.mtrxCaption2)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Story Audience Sheet

/// Before posting, choose who sees it — everyone, or close friends you
/// pick from your followers. Mirrors Instagram's audience control.
struct StoryAudienceSheet: View {
    let onPost: (StoryAudience) -> Void
    let onCancel: () -> Void

    @ObservedObject private var store = StoryStore.shared
    @State private var audience: StoryAudience = .everyone

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Share story")
                .font(.mtrxTitle3)
                .foregroundStyle(Color.labelPrimary)
                .padding(.top, Spacing.md)

            // Audience toggle.
            HStack(spacing: Spacing.sm) {
                audienceChip("Everyone", icon: "globe", value: .everyone, color: .trinityPrimary)
                audienceChip("Close Friends", icon: "star.fill", value: .closeFriends, color: .statusSuccess)
            }

            if audience == .closeFriends {
                Text("Only these followers will see it")
                    .font(.mtrxCaption1)
                    .foregroundStyle(Color.labelSecondary)

                ScrollView {
                    VStack(spacing: Spacing.xs) {
                        ForEach(StoryStore.followers, id: \.self) { handle in
                            Button {
                                MtrxHaptics.selection()
                                if store.closeFriends.contains(handle) {
                                    store.closeFriends.remove(handle)
                                } else {
                                    store.closeFriends.insert(handle)
                                }
                            } label: {
                                HStack {
                                    Text(handle)
                                        .font(.mtrxCaptionBold)
                                        .foregroundStyle(Color.labelPrimary)
                                    Spacer()
                                    Image(systemName: store.closeFriends.contains(handle)
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(store.closeFriends.contains(handle)
                                                         ? Color.statusSuccess : Color.labelTertiary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, Spacing.ms)
                                .background(Color.surfaceOverlay.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            Spacer(minLength: 0)

            Button {
                onPost(audience)
            } label: {
                Text("Share to Story")
                    .font(.mtrxCalloutBold)
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.accentPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.contentPadding)
        .padding(.bottom, Spacing.lg)
    }

    private func audienceChip(_ label: String, icon: String, value: StoryAudience, color: Color) -> some View {
        Button {
            MtrxHaptics.selection()
            withAnimation(Motion.springSnappy) { audience = value }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(label).font(.mtrxCaptionBold)
            }
            .foregroundStyle(audience == value ? Color.backgroundPrimary : Color.labelPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(audience == value ? color : Color.surfaceOverlay)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Story Viewer

/// Full-screen Instagram-style playback: tap right to advance through a
/// person's stack and on to the next person; tap left to go back; swipe
/// sideways to jump between people; swipe down to leave; delete your own.
struct StoryViewer: View {
    let groups: [[SocialStory]]
    let startGroup: Int

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoryStore.shared

    @State private var groupIndex: Int = 0
    @State private var storyIndex: Int = 0
    @State private var progress: CGFloat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var advanceToken = 0
    @State private var showDeleteConfirm = false

    private var liveGroups: [[SocialStory]] { groups }
    private var currentGroup: [SocialStory] {
        guard liveGroups.indices.contains(groupIndex) else { return [] }
        return liveGroups[groupIndex]
    }
    private var story: SocialStory? {
        currentGroup.indices.contains(storyIndex) ? currentGroup[storyIndex] : nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if let story {
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

                // Invisible tap zones: left third = back, right = forward.
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { goBack() }
                        .frame(maxWidth: .infinity)
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { advance() }
                        .frame(maxWidth: .infinity)
                        .frame(width: nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: Spacing.ms) {
                    // One segment per story in THIS person's group.
                    HStack(spacing: 4) {
                        ForEach(Array(currentGroup.enumerated()), id: \.element.id) { i, _ in
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.25))
                                    Capsule()
                                        .fill(.white)
                                        .frame(width: i < storyIndex ? geo.size.width
                                               : (i == storyIndex ? geo.size.width * progress : 0))
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

                        Text(story.isMine ? "Your Story" : story.author)
                            .font(.mtrxCaptionBold)
                            .foregroundStyle(.white)

                        Text(story.timestamp.formatted(.relative(presentation: .named)))
                            .font(.mtrxCaption2)
                            .foregroundStyle(.white.opacity(0.7))

                        if story.audience == .closeFriends {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.statusSuccess)
                                .accessibilityLabel("Close friends only")
                        }

                        Spacer()

                        // Delete — only your own stories.
                        if story.isMine {
                            Button {
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .accessibilityLabel("Delete story")
                            }
                        }

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .accessibilityLabel("Close story viewer")
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
            }
        }
        .offset(dragOffset)
        .opacity(dragOffset.height > 0 ? max(0.4, 1 - dragOffset.height / 600) : 1)
        // Drag down to leave; drag sideways to change person.
        .gesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    if value.translation.height > abs(value.translation.width) {
                        dragOffset = CGSize(width: 0, height: max(0, value.translation.height))
                    } else {
                        dragOffset = CGSize(width: value.translation.width, height: 0)
                    }
                }
                .onEnded { value in
                    if value.translation.height > 110 {
                        dismiss()
                    } else if value.translation.width < -70 {
                        withAnimation(Motion.springSnappy) { dragOffset = .zero }
                        nextGroup()
                    } else if value.translation.width > 70 {
                        withAnimation(Motion.springSnappy) { dragOffset = .zero }
                        previousGroup()
                    } else {
                        withAnimation(Motion.springSnappy) { dragOffset = .zero }
                    }
                }
        )
        .confirmationDialog("Delete this story?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteCurrent() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            groupIndex = min(startGroup, max(liveGroups.count - 1, 0))
            storyIndex = 0
            startProgress()
        }
    }

    // MARK: - Playback

    private func advance() {
        if storyIndex + 1 < currentGroup.count {
            withAnimation(.easeInOut(duration: 0.16)) { storyIndex += 1 }
            startProgress()
        } else {
            nextGroup()
        }
    }

    private func goBack() {
        if storyIndex > 0 {
            withAnimation(.easeInOut(duration: 0.16)) { storyIndex -= 1 }
            startProgress()
        } else {
            previousGroup()
        }
    }

    private func nextGroup() {
        if groupIndex + 1 < liveGroups.count {
            withAnimation(.easeInOut(duration: 0.2)) {
                groupIndex += 1
                storyIndex = 0
            }
            startProgress()
        } else {
            dismiss()
        }
    }

    private func previousGroup() {
        if groupIndex > 0 {
            withAnimation(.easeInOut(duration: 0.2)) {
                groupIndex -= 1
                storyIndex = 0
            }
            startProgress()
        } else {
            startProgress()
        }
    }

    private func deleteCurrent() {
        guard let story else { return }
        let wasLast = currentGroup.count <= 1
        store.deleteStory(story.id)
        MtrxHaptics.warning()
        if wasLast {
            dismiss()
        } else {
            storyIndex = min(storyIndex, max(currentGroup.count - 1, 0))
            startProgress()
        }
    }

    /// 5 seconds per story; auto-advances unless the viewer tapped or
    /// swiped ahead (token guards stale timers).
    private func startProgress() {
        advanceToken += 1
        let token = advanceToken
        progress = 0
        withAnimation(.linear(duration: 5)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.05) {
            if token == advanceToken { advance() }
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

    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Banner with the avatar overlapping its bottom edge.
                    // Clean display only — all editing lives in Edit profile.
                    ZStack(alignment: .bottomLeading) {
                        // A clear frame fixes the banner's footprint to the
                        // screen width; the image fills it via overlay so a
                        // tall photo can never overflow and shove the whole
                        // profile sideways. It just fits to screen, edge to
                        // edge, reaching up behind the status bar.
                        Color.clear
                            .frame(height: 178)
                            .frame(maxWidth: .infinity)
                            .overlay {
                                if let banner = identity.bannerImage {
                                    Image(uiImage: banner)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    LinearGradient(
                                        colors: [Color.trinityPrimary.opacity(0.55), Color.trinitySecondary.opacity(0.35), Color.backgroundPrimary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                }
                            }
                            .clipped()
                            .ignoresSafeArea(edges: .top)

                        Group {
                            if let avatar = identity.avatarImage {
                                Image(uiImage: avatar)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
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
                        // Square frame → a perfect circle, never an oval.
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 4))
                        .offset(x: Spacing.contentPadding, y: 42)
                    }
                    .padding(.bottom, 46)

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        // Edit profile pill — opens the full editor.
                        HStack {
                            Spacer()
                            Button {
                                MtrxHaptics.impact(.light)
                                showEditProfile = true
                            } label: {
                                Text("Edit profile")
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
            .ignoresSafeArea(edges: .top)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
                    .environmentObject(appState)
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

// MARK: - Edit Profile

/// The full profile editor — change your avatar, banner, name, handle,
/// and bio in one place. Opened from the Edit profile button.
struct EditProfileView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var identity = SocialIdentity.shared
    @Environment(\.dismiss) private var dismiss

    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var bannerPickerItem: PhotosPickerItem?
    @State private var name = ""
    @State private var username = ""
    @State private var bio = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Banner + avatar pickers live here, with clear labels.
                    ZStack(alignment: .bottomLeading) {
                        PhotosPicker(selection: $bannerPickerItem, matching: .images) {
                            ZStack {
                                Group {
                                    if let banner = identity.bannerImage {
                                        Image(uiImage: banner).resizable().scaledToFill()
                                    } else {
                                        LinearGradient(colors: [Color.trinityPrimary.opacity(0.5), Color.trinitySecondary.opacity(0.3)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                    }
                                }
                                .frame(height: 120).frame(maxWidth: .infinity).clipped()
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(.black.opacity(0.35))
                                    .clipShape(Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))

                        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                            ZStack {
                                Group {
                                    if let avatar = identity.avatarImage {
                                        Image(uiImage: avatar).resizable().scaledToFill()
                                    } else {
                                        LinearGradient(colors: [.trinityPrimary, .trinitySecondary],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                    }
                                }
                                .frame(width: 76, height: 76).clipShape(Circle())
                                .overlay(Circle().stroke(Color.backgroundPrimary, lineWidth: 3))
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(7)
                                    .background(.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                        }
                        .buttonStyle(.plain)
                        .offset(x: Spacing.md, y: 38)
                    }
                    .padding(.bottom, 40)

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        editField("Display name", text: $name, placeholder: "Your name")
                        editField("Username", text: $username, placeholder: "@username", lower: true)
                        editField("Bio", text: $bio, placeholder: "Tell people about yourself", multiline: true)
                    }
                    .padding(.horizontal, Spacing.contentPadding)
                }
            }
            .background(MtrxGradientBackground(style: .primary))
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.mtrxCalloutBold)
                }
            }
            .onAppear {
                name = appState.displayName
                username = identity.username.isEmpty
                    ? identity.handle(displayName: appState.displayName)
                    : identity.username
                bio = identity.bio
            }
            .onChange(of: avatarPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        identity.updateAvatar(image); MtrxHaptics.success()
                    }
                    avatarPickerItem = nil
                }
            }
            .onChange(of: bannerPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        identity.updateBanner(image); MtrxHaptics.success()
                    }
                    bannerPickerItem = nil
                }
            }
        }
    }

    private func save() {
        appState.updateDisplayName(name)
        identity.username = username.trimmingCharacters(in: .whitespaces)
        identity.bio = bio
        MtrxHaptics.success()
        dismiss()
    }

    @ViewBuilder
    private func editField(_ label: String, text: Binding<String>, placeholder: String, lower: Bool = false, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
            if multiline {
                TextField(placeholder, text: text, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.mtrxBody)
                    .padding(Spacing.ms)
                    .background(Color.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            } else {
                TextField(placeholder, text: text)
                    .font(.mtrxBody)
                    .textInputAutocapitalization(lower ? .never : .sentences)
                    .autocorrectionDisabled(lower)
                    .padding(Spacing.ms)
                    .background(Color.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.sm, style: .continuous))
            }
        }
    }
}

// MARK: - Post Attachment Views

/// Renders a post's attached photo, video, or link.
struct PostAttachmentView: View {
    let imageData: Data?
    let videoFileName: String?
    let linkURL: String?

    @State private var fullscreenImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Photos render inline; tap to view full-screen.
            if let imageData, let image = UIImage(data: imageData) {
                Button { fullscreenImage = image } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Videos play inline. Pro & Enterprise members get true
            // Picture-in-Picture — the video pops out and keeps playing when
            // they leave the app.
            if let videoFileName {
                Group {
                    if FeatureGate.shared.currentTier >= .pro {
                        PiPVideoPlayer(url: SocialIdentity.mediaURL(videoFileName))
                    } else {
                        VideoPlayer(player: AVPlayer(url: SocialIdentity.mediaURL(videoFileName)))
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
            }

            if let linkURL {
                if let ytID = Self.youTubeID(from: linkURL) {
                    // YouTube links play right in the feed.
                    YouTubePlayerView(videoID: ytID)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.md, style: .continuous))
                } else if let url = URL(string: linkURL) {
                    Link(destination: url) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "link")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.accentPrimary)
                            Text(linkURL)
                                .font(.mtrxCaption1)
                                .foregroundStyle(Color.accentPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
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
        .fullScreenCover(item: Binding(
            get: { fullscreenImage.map { ImageWrapper(image: $0) } },
            set: { fullscreenImage = $0?.image }
        )) { wrapper in
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: wrapper.image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
                VStack {
                    HStack {
                        Spacer()
                        Button { fullscreenImage = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white, .black.opacity(0.5))
                                .accessibilityLabel("Close fullscreen image")
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
    }

    /// Extracts a YouTube video id from the common URL shapes.
    static func youTubeID(from urlString: String) -> String? {
        let lower = urlString.lowercased()
        guard lower.contains("youtube.com") || lower.contains("youtu.be") else { return nil }
        guard let comps = URLComponents(string: urlString) else { return nil }
        if let host = comps.host, host.contains("youtu.be") {
            let id = comps.path.replacingOccurrences(of: "/", with: "")
            return id.isEmpty ? nil : id
        }
        if comps.path.contains("/embed/") {
            return comps.path.components(separatedBy: "/embed/").last
        }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        return nil
    }
}

private struct ImageWrapper: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - YouTube Player (inline WKWebView)

struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let html = """
        <html><head><meta name='viewport' content='initial-scale=1.0'/>
        <style>html,body{margin:0;background:#000;height:100%}iframe{width:100%;height:100%;border:0}</style>
        </head><body>
        <iframe src='https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0' allow='accelerometer; encrypted-media; gyroscope; picture-in-picture' allowfullscreen></iframe>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
}

// MARK: - Picture-in-Picture Video (Pro / Enterprise)

/// An AVPlayerViewController-backed player that supports Picture-in-Picture
/// so the video pops out and keeps playing after the user leaves the app.
/// Requires the "audio" background mode (Info.plist) to continue in the
/// background.
struct PiPVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        // Playback category keeps audio/PiP alive when the app backgrounds.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
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
                                Text("Upgrade to Pro — $9.99/mo")
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
