// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPRegistry
 * @notice IP registry with blockchain timestamping, qualifying transaction types
 *         defined at registration, and immutable ownership record.
 *         Royalty percentage is set at registration and cannot be changed.
 */
contract IPRegistry {

    // ─── Types ───────────────────────────────────────────────────────────

    enum TransactionType {
        Resale,
        Licensing,
        Streaming,
        Reproduction,
        Derivative
    }

    struct IPRecord {
        address owner;
        bytes32 contentHash;
        uint256 registeredAt;       // block.timestamp at registration
        uint256 blockNumber;        // block number for anchoring proof
        uint16  royaltyBps;         // basis points (e.g. 200 = 2%)
        bool    exists;
    }

    // ─── State ───────────────────────────────────────────────────────────

    /// @dev ipId => IPRecord
    mapping(bytes32 => IPRecord) private _records;

    /// @dev ipId => TransactionType => qualified
    mapping(bytes32 => mapping(TransactionType => bool)) private _qualifyingTypes;

    /// @dev ipId => list of qualifying types (for enumeration)
    mapping(bytes32 => TransactionType[]) private _qualifyingTypeList;

    /// @dev owner => list of ipIds
    mapping(address => bytes32[]) private _ownerWorks;

    uint256 public totalRegistrations;

    // ─── Events ──────────────────────────────────────────────────────────

    event IPRegistered(
        bytes32 indexed ipId,
        address indexed owner,
        bytes32 contentHash,
        uint256 timestamp,
        uint256 blockNumber,
        uint16  royaltyBps
    );

    event QualifyingTypeAdded(bytes32 indexed ipId, TransactionType txType);

    // ─── Errors ──────────────────────────────────────────────────────────

    error AlreadyRegistered(bytes32 ipId);
    error NotRegistered(bytes32 ipId);
    error NotOwner(bytes32 ipId, address caller);
    error InvalidRoyalty(uint16 bps);
    error TypeAlreadyQualified(bytes32 ipId, TransactionType txType);
    error NoQualifyingTypes();

    // ─── Modifiers ───────────────────────────────────────────────────────

    modifier onlyIPOwner(bytes32 ipId) {
        if (!_records[ipId].exists) revert NotRegistered(ipId);
        if (_records[ipId].owner != msg.sender) revert NotOwner(ipId, msg.sender);
        _;
    }

    // ─── Registration ────────────────────────────────────────────────────

    /**
     * @notice Register a new IP work with immutable ownership, royalty rate,
     *         and initial qualifying transaction types.
     * @param contentHash  Keccak-256 hash of the work's content/metadata.
     * @param royaltyBps   Royalty in basis points (max 10 000 = 100%).
     * @param qualifyingTypes  Array of transaction types that trigger royalties.
     * @return ipId  Unique identifier for the registered work.
     */
    function registerIP(
        bytes32 contentHash,
        uint16  royaltyBps,
        TransactionType[] calldata qualifyingTypes
    ) external returns (bytes32 ipId) {
        if (royaltyBps > 10_000) revert InvalidRoyalty(royaltyBps);
        if (qualifyingTypes.length == 0) revert NoQualifyingTypes();

        ipId = keccak256(abi.encodePacked(msg.sender, contentHash, block.timestamp));
        if (_records[ipId].exists) revert AlreadyRegistered(ipId);

        _records[ipId] = IPRecord({
            owner: msg.sender,
            contentHash: contentHash,
            registeredAt: block.timestamp,
            blockNumber: block.number,
            royaltyBps: royaltyBps,
            exists: true
        });

        for (uint256 i = 0; i < qualifyingTypes.length; i++) {
            TransactionType t = qualifyingTypes[i];
            if (!_qualifyingTypes[ipId][t]) {
                _qualifyingTypes[ipId][t] = true;
                _qualifyingTypeList[ipId].push(t);
                emit QualifyingTypeAdded(ipId, t);
            }
        }

        _ownerWorks[msg.sender].push(ipId);
        totalRegistrations++;

        emit IPRegistered(
            ipId, msg.sender, contentHash,
            block.timestamp, block.number, royaltyBps
        );
    }

    // ─── Qualifying-Type Management (add-only) ───────────────────────────

    /**
     * @notice Add a new qualifying transaction type. Owner can add but NEVER remove.
     */
    function addQualifyingType(bytes32 ipId, TransactionType txType)
        external
        onlyIPOwner(ipId)
    {
        if (_qualifyingTypes[ipId][txType])
            revert TypeAlreadyQualified(ipId, txType);

        _qualifyingTypes[ipId][txType] = true;
        _qualifyingTypeList[ipId].push(txType);

        emit QualifyingTypeAdded(ipId, txType);
    }

    // ─── Views ───────────────────────────────────────────────────────────

    function getIPRecord(bytes32 ipId) external view returns (IPRecord memory) {
        if (!_records[ipId].exists) revert NotRegistered(ipId);
        return _records[ipId];
    }

    function isQualifyingType(bytes32 ipId, TransactionType txType)
        external view returns (bool)
    {
        return _qualifyingTypes[ipId][txType];
    }

    function getQualifyingTypes(bytes32 ipId)
        external view returns (TransactionType[] memory)
    {
        if (!_records[ipId].exists) revert NotRegistered(ipId);
        return _qualifyingTypeList[ipId];
    }

    function getOwnerWorks(address owner)
        external view returns (bytes32[] memory)
    {
        return _ownerWorks[owner];
    }
}
