// SocialManager.swift
// MTRX Blockchain - Components - Social
//
// On-chain social: posts, follows, messaging, reputation graphs

import Foundation
import Combine

// MARK: - Data Models

struct SocialProfile: Identifiable, Codable {
    let id: String
    let address: String
    var displayName: String
    var bio: String
    var avatarURI: String?
    let createdAt: Date
    var followerCount: Int
    var followingCount: Int
    var postCount: Int
    let ensName: String?
}

struct SocialPost: Identifiable, Codable {
    let id: String
    let authorAddress: String
    let content: String
    let contentHash: String
    let createdAt: Date
    var likeCount: Int
    var repostCount: Int
    var replyCount: Int
    let parentPostId: String?
    let attachments: [PostAttachment]
    let tags: [String]
    let transactionHash: String?
}

struct PostAttachment: Codable {
    let type: AttachmentType
    let uri: String
    let mimeType: String
}

enum AttachmentType: String, Codable {
    case image, video, link, nft, transaction, proposal
}

struct SocialMessage: Identifiable, Codable {
    let id: String
    let senderAddress: String
    let recipientAddress: String
    let content: String
    let encryptedContent: String?
    let sentAt: Date
    var isRead: Bool
    let conversationId: String
}

struct FollowRelation: Codable {
    let follower: String
    let following: String
    let followedAt: Date
}

enum SocialError: Error, LocalizedError {
    case profileNotFound(String)
    case postNotFound(String)
    case alreadyFollowing
    case notFollowing
    case contentTooLong
    case messagingDisabled

    var errorDescription: String? {
        switch self {
        case .profileNotFound(let a): return "Profile not found: \(a)"
        case .postNotFound(let id): return "Post not found: \(id)"
        case .alreadyFollowing: return "Already following this user."
        case .notFollowing: return "Not following this user."
        case .contentTooLong: return "Content exceeds maximum length."
        case .messagingDisabled: return "Messaging is disabled for this user."
        }
    }
}

// MARK: - SocialManager

final class SocialManager: ObservableObject {

    static let shared = SocialManager()

    @Published private(set) var feed: [SocialPost] = []
    @Published private(set) var conversations: [String: [SocialMessage]] = [:]
    @Published var userProfile: SocialProfile?

    private var profileStore: [String: SocialProfile] = [:]
    private var postStore: [String: SocialPost] = [:]
    private var followGraph: [String: Set<String>] = [:] // follower -> Set<following>
    private var messageStore: [String: [SocialMessage]] = [:] // conversationId -> messages

    private let maxPostLength = 1000

    // MARK: - Profile

    func createProfile(address: String, displayName: String, bio: String, avatarURI: String? = nil) async throws -> SocialProfile {
        let profile = SocialProfile(
            id: UUID().uuidString, address: address, displayName: displayName,
            bio: bio, avatarURI: avatarURI, createdAt: Date(),
            followerCount: 0, followingCount: 0, postCount: 0, ensName: nil
        )
        profileStore[address] = profile
        await MainActor.run { userProfile = profile }
        return profile
    }

    func getProfile(address: String) -> SocialProfile? { profileStore[address] }

    // MARK: - Posts

    func createPost(author: String, content: String, parentPostId: String? = nil, attachments: [PostAttachment] = [], tags: [String] = []) async throws -> SocialPost {
        guard content.count <= maxPostLength else { throw SocialError.contentTooLong }

        let contentHash = content.data(using: .utf8)?.base64EncodedString() ?? ""

        let post = SocialPost(
            id: UUID().uuidString, authorAddress: author, content: content,
            contentHash: contentHash, createdAt: Date(),
            likeCount: 0, repostCount: 0, replyCount: 0,
            parentPostId: parentPostId, attachments: attachments,
            tags: tags, transactionHash: nil
        )

        postStore[post.id] = post
        if var profile = profileStore[author] { profile.postCount += 1; profileStore[author] = profile }
        await MainActor.run { feed.insert(post, at: 0) }
        return post
    }

    func likePost(postId: String) async throws {
        guard var post = postStore[postId] else { throw SocialError.postNotFound(postId) }
        post.likeCount += 1
        postStore[postId] = post
    }

    func getPostsByUser(address: String) -> [SocialPost] {
        postStore.values.filter { $0.authorAddress == address }.sorted { $0.createdAt > $1.createdAt }
    }

    func getReplies(postId: String) -> [SocialPost] {
        postStore.values.filter { $0.parentPostId == postId }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Social Graph

    func follow(follower: String, following: String) async throws {
        guard profileStore[following] != nil else { throw SocialError.profileNotFound(following) }
        var follows = followGraph[follower] ?? []
        guard !follows.contains(following) else { throw SocialError.alreadyFollowing }

        follows.insert(following)
        followGraph[follower] = follows

        if var fp = profileStore[follower] { fp.followingCount += 1; profileStore[follower] = fp }
        if var tp = profileStore[following] { tp.followerCount += 1; profileStore[following] = tp }
    }

    func unfollow(follower: String, following: String) async throws {
        guard var follows = followGraph[follower], follows.contains(following) else {
            throw SocialError.notFollowing
        }
        follows.remove(following)
        followGraph[follower] = follows

        if var fp = profileStore[follower] { fp.followingCount -= 1; profileStore[follower] = fp }
        if var tp = profileStore[following] { tp.followerCount -= 1; profileStore[following] = tp }
    }

    func getFollowers(address: String) -> [String] {
        followGraph.filter { $0.value.contains(address) }.map { $0.key }
    }

    func getFollowing(address: String) -> [String] {
        Array(followGraph[address] ?? [])
    }

    // MARK: - Feed

    func getUserFeed(address: String) -> [SocialPost] {
        let following = followGraph[address] ?? []
        return postStore.values
            .filter { following.contains($0.authorAddress) || $0.authorAddress == address }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Messaging

    func sendMessage(sender: String, recipient: String, content: String) async throws -> SocialMessage {
        let conversationId = [sender, recipient].sorted().joined(separator: ":")
        let message = SocialMessage(
            id: UUID().uuidString, senderAddress: sender, recipientAddress: recipient,
            content: content, encryptedContent: nil, sentAt: Date(),
            isRead: false, conversationId: conversationId
        )
        messageStore[conversationId, default: []].append(message)
        await MainActor.run { conversations[conversationId] = messageStore[conversationId] }
        return message
    }

    func getConversation(user1: String, user2: String) -> [SocialMessage] {
        let conversationId = [user1, user2].sorted().joined(separator: ":")
        return messageStore[conversationId] ?? []
    }
}
