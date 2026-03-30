// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SocialPost
 * @notice On-chain verified social posts with optional EAS attestation on Base.
 * @dev Posts are stored on-chain with content hashes. Authors can optionally
 *      link an Ethereum Attestation Service (EAS) attestation for independent
 *      verification of post authenticity.
 *
 *      Features:
 *        - On-chain post creation with content hash.
 *        - Optional EAS attestation linkage.
 *        - Reply threading.
 *        - Post editing (creates a new version, preserves history).
 *        - Author-controlled deletion (marks as deleted, data persists for audit).
 *        - Verified author registry (optional blue-check equivalent).
 */
contract SocialPost is Ownable, Pausable {
    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    struct Post {
        address author;
        bytes32 contentHash;          // Keccak256 of the off-chain content
        string contentURI;            // IPFS/Arweave URI for full content
        uint256 parentPostId;         // 0 = top-level post, >0 = reply
        uint256 createdAt;
        uint256 editedAt;
        uint256 version;              // Increments on edit
        bool deleted;
        bytes32 easAttestationUID;    // Optional EAS attestation UID
        address easSchemaResolver;    // EAS schema resolver used
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    uint256 public nextPostId;

    mapping(uint256 => Post) public posts;

    /// @notice Post ID => array of reply post IDs.
    mapping(uint256 => uint256[]) public replies;

    /// @notice Author => array of their post IDs.
    mapping(address => uint256[]) public authorPosts;

    /// @notice Verified authors (platform-verified identity).
    mapping(address => bool) public isVerifiedAuthor;

    /// @notice EAS contract address on Base.
    address public easContract;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event PostCreated(uint256 indexed postId, address indexed author, bytes32 contentHash, string contentURI, uint256 parentPostId);
    event PostEdited(uint256 indexed postId, bytes32 newContentHash, string newContentURI, uint256 newVersion);
    event PostDeleted(uint256 indexed postId, address indexed author);
    event EASAttestationLinked(uint256 indexed postId, bytes32 indexed attestationUID, address schemaResolver);
    event AuthorVerified(address indexed author);
    event AuthorUnverified(address indexed author);
    event EASContractUpdated(address indexed newEAS);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error NotAuthor();
    error PostNotFound();
    error PostDeleted_();
    error ParentPostNotFound();
    error EmptyContent();
    error ZeroAddress();

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @param easContract_ Address of the EAS contract on Base (can be address(0) if not yet deployed).
     */
    constructor(address easContract_) Ownable(msg.sender) {
        easContract = easContract_;
    }

    // ----------------------------------------------------------------
    // Post Creation
    // ----------------------------------------------------------------

    /**
     * @notice Create a new post.
     * @param contentHash     Keccak256 hash of the off-chain content.
     * @param contentURI      IPFS/Arweave URI for the full content.
     * @param parentPostId    Parent post ID for replies (0 = top-level).
     * @return postId         The new post ID.
     */
    function createPost(
        bytes32 contentHash,
        string calldata contentURI,
        uint256 parentPostId
    ) external whenNotPaused returns (uint256 postId) {
        if (contentHash == bytes32(0)) revert EmptyContent();

        // Validate parent exists if this is a reply
        if (parentPostId > 0) {
            if (posts[parentPostId].author == address(0)) revert ParentPostNotFound();
            if (posts[parentPostId].deleted) revert PostDeleted_();
        }

        postId = ++nextPostId; // Start from 1

        posts[postId] = Post({
            author: msg.sender,
            contentHash: contentHash,
            contentURI: contentURI,
            parentPostId: parentPostId,
            createdAt: block.timestamp,
            editedAt: 0,
            version: 1,
            deleted: false,
            easAttestationUID: bytes32(0),
            easSchemaResolver: address(0)
        });

        authorPosts[msg.sender].push(postId);

        if (parentPostId > 0) {
            replies[parentPostId].push(postId);
        }

        emit PostCreated(postId, msg.sender, contentHash, contentURI, parentPostId);
    }

    /**
     * @notice Create a post with an EAS attestation.
     * @param contentHash       Keccak256 hash of the off-chain content.
     * @param contentURI        IPFS/Arweave URI.
     * @param parentPostId      Parent post ID (0 = top-level).
     * @param attestationUID    EAS attestation UID.
     * @param schemaResolver    EAS schema resolver address.
     * @return postId           The new post ID.
     */
    function createVerifiedPost(
        bytes32 contentHash,
        string calldata contentURI,
        uint256 parentPostId,
        bytes32 attestationUID,
        address schemaResolver
    ) external whenNotPaused returns (uint256 postId) {
        if (contentHash == bytes32(0)) revert EmptyContent();
        if (attestationUID == bytes32(0)) revert EmptyContent();

        if (parentPostId > 0) {
            if (posts[parentPostId].author == address(0)) revert ParentPostNotFound();
            if (posts[parentPostId].deleted) revert PostDeleted_();
        }

        postId = ++nextPostId;

        posts[postId] = Post({
            author: msg.sender,
            contentHash: contentHash,
            contentURI: contentURI,
            parentPostId: parentPostId,
            createdAt: block.timestamp,
            editedAt: 0,
            version: 1,
            deleted: false,
            easAttestationUID: attestationUID,
            easSchemaResolver: schemaResolver
        });

        authorPosts[msg.sender].push(postId);

        if (parentPostId > 0) {
            replies[parentPostId].push(postId);
        }

        emit PostCreated(postId, msg.sender, contentHash, contentURI, parentPostId);
        emit EASAttestationLinked(postId, attestationUID, schemaResolver);
    }

    // ----------------------------------------------------------------
    // Post Editing
    // ----------------------------------------------------------------

    /**
     * @notice Edit a post (creates a new version).
     * @param postId         Post to edit.
     * @param newContentHash New content hash.
     * @param newContentURI  New content URI.
     */
    function editPost(
        uint256 postId,
        bytes32 newContentHash,
        string calldata newContentURI
    ) external {
        Post storage p = posts[postId];
        if (p.author == address(0)) revert PostNotFound();
        if (p.deleted) revert PostDeleted_();
        if (msg.sender != p.author) revert NotAuthor();
        if (newContentHash == bytes32(0)) revert EmptyContent();

        p.contentHash = newContentHash;
        p.contentURI = newContentURI;
        p.editedAt = block.timestamp;
        p.version++;

        emit PostEdited(postId, newContentHash, newContentURI, p.version);
    }

    // ----------------------------------------------------------------
    // Post Deletion
    // ----------------------------------------------------------------

    /**
     * @notice Delete a post (soft delete -- data persists for audit).
     * @param postId Post to delete.
     */
    function deletePost(uint256 postId) external {
        Post storage p = posts[postId];
        if (p.author == address(0)) revert PostNotFound();
        if (msg.sender != p.author && msg.sender != owner()) revert NotAuthor();

        p.deleted = true;
        emit PostDeleted(postId, p.author);
    }

    // ----------------------------------------------------------------
    // EAS Attestation
    // ----------------------------------------------------------------

    /**
     * @notice Link an EAS attestation to an existing post.
     * @param postId          Post to attest.
     * @param attestationUID  EAS attestation UID.
     * @param schemaResolver  Schema resolver used.
     */
    function linkAttestation(
        uint256 postId,
        bytes32 attestationUID,
        address schemaResolver
    ) external {
        Post storage p = posts[postId];
        if (p.author == address(0)) revert PostNotFound();
        if (msg.sender != p.author) revert NotAuthor();
        if (attestationUID == bytes32(0)) revert EmptyContent();

        p.easAttestationUID = attestationUID;
        p.easSchemaResolver = schemaResolver;

        emit EASAttestationLinked(postId, attestationUID, schemaResolver);
    }

    // ----------------------------------------------------------------
    // Author Verification
    // ----------------------------------------------------------------

    function verifyAuthor(address author) external onlyOwner {
        if (author == address(0)) revert ZeroAddress();
        isVerifiedAuthor[author] = true;
        emit AuthorVerified(author);
    }

    function unverifyAuthor(address author) external onlyOwner {
        isVerifiedAuthor[author] = false;
        emit AuthorUnverified(author);
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    function getPost(uint256 postId) external view returns (Post memory) {
        return posts[postId];
    }

    function getReplies(uint256 postId) external view returns (uint256[] memory) {
        return replies[postId];
    }

    function getAuthorPosts(address author) external view returns (uint256[] memory) {
        return authorPosts[author];
    }

    function getReplyCount(uint256 postId) external view returns (uint256) {
        return replies[postId].length;
    }

    function isPostVerified(uint256 postId) external view returns (bool) {
        return posts[postId].easAttestationUID != bytes32(0);
    }

    // ----------------------------------------------------------------
    // Administrative
    // ----------------------------------------------------------------

    function setEASContract(address newEAS) external onlyOwner {
        easContract = newEAS;
        emit EASContractUpdated(newEAS);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
