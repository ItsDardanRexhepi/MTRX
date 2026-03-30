// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SupplyChain
 * @author 0pnMatrx Platform
 * @notice Component 12 — Chain-of-custody tracking for ANY asset (physical or digital).
 * @dev Every step is permanently recorded on-chain. The platform covers ALL gas costs;
 *      usage is completely free to end users. Emits granular events consumed by off-chain
 *      QR generator and verification-UI services.
 *
 *      Designed to interoperate with:
 *        - Component 4  (JointOwnership) via OwnershipTransferListener
 *        - Component 14 (GameAsset) for in-game item provenance
 */
contract SupplyChain is Ownable, ReentrancyGuard {

    // -------------------------------------------------------------------------
    //  Constants
    // -------------------------------------------------------------------------

    /// @notice NeoSafe treasury wallet
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    // -------------------------------------------------------------------------
    //  Enums
    // -------------------------------------------------------------------------

    enum AssetType {
        PHYSICAL,
        DIGITAL,
        VEHICLE,
        PROPERTY,
        ARTWORK,
        COLLECTIBLE,
        GAME_ITEM,
        OTHER
    }

    enum CustodyAction {
        REGISTERED,
        TRANSFERRED,
        INSPECTED,
        REPAIRED,
        STORED,
        SHIPPED,
        DELIVERED,
        RETURNED,
        CUSTOM
    }

    enum InspectionResult {
        PASS,
        FAIL,
        CONDITIONAL,
        PENDING
    }

    // -------------------------------------------------------------------------
    //  Structs
    // -------------------------------------------------------------------------

    struct Asset {
        uint256 assetId;
        AssetType assetType;
        address registrant;
        address currentCustodian;
        string metadataURI;
        uint256 registeredAt;
        bool active;
    }

    struct CustodyEvent {
        uint256 eventId;
        uint256 assetId;
        CustodyAction action;
        address fromCustodian;
        address toCustodian;
        string notes;
        string locationHash;
        uint256 timestamp;
    }

    struct Inspection {
        uint256 inspectionId;
        uint256 assetId;
        address inspector;
        InspectionResult result;
        string reportURI;
        string notes;
        uint256 timestamp;
    }

    // -------------------------------------------------------------------------
    //  State
    // -------------------------------------------------------------------------

    uint256 private _assetIdCounter;
    uint256 private _eventIdCounter;
    uint256 private _inspectionIdCounter;

    /// @dev assetId -> Asset
    mapping(uint256 => Asset) public assets;

    /// @dev assetId -> ordered list of custody events
    mapping(uint256 => uint256[]) public assetCustodyEvents;

    /// @dev eventId -> CustodyEvent
    mapping(uint256 => CustodyEvent) public custodyEvents;

    /// @dev assetId -> ordered list of inspections
    mapping(uint256 => uint256[]) public assetInspections;

    /// @dev inspectionId -> Inspection
    mapping(uint256 => Inspection) public inspections;

    /// @dev Authorised recorders (platform relayer addresses that submit meta-txs)
    mapping(address => bool) public authorisedRecorders;

    /// @dev External reference hash -> assetId (e.g., VIN hash, property deed hash)
    mapping(bytes32 => uint256) public externalRefToAsset;

    // -------------------------------------------------------------------------
    //  Events
    // -------------------------------------------------------------------------

    event ProductRegistered(
        uint256 indexed assetId,
        AssetType assetType,
        address indexed registrant,
        string metadataURI,
        uint256 timestamp
    );

    event CustodyTransferred(
        uint256 indexed assetId,
        uint256 indexed eventId,
        CustodyAction action,
        address indexed fromCustodian,
        address toCustodian,
        string notes,
        uint256 timestamp
    );

    event InspectionRecorded(
        uint256 indexed assetId,
        uint256 indexed inspectionId,
        address indexed inspector,
        InspectionResult result,
        string reportURI,
        uint256 timestamp
    );

    event QRGenerated(
        uint256 indexed assetId,
        string verificationURL,
        uint256 timestamp
    );

    event RecorderAuthorised(address indexed recorder, bool status);
    event AssetDeactivated(uint256 indexed assetId, uint256 timestamp);
    event ExternalRefLinked(uint256 indexed assetId, bytes32 indexed refHash);

    // -------------------------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------------------------

    modifier onlyAuthorised() {
        require(
            authorisedRecorders[msg.sender] || msg.sender == owner(),
            "SupplyChain: caller not authorised"
        );
        _;
    }

    modifier assetExists(uint256 _assetId) {
        require(assets[_assetId].registeredAt != 0, "SupplyChain: asset does not exist");
        _;
    }

    modifier assetActive(uint256 _assetId) {
        require(assets[_assetId].active, "SupplyChain: asset is inactive");
        _;
    }

    // -------------------------------------------------------------------------
    //  Constructor
    // -------------------------------------------------------------------------

    constructor() Ownable(msg.sender) {
        // Owner (platform deployer) is auto-authorised
        authorisedRecorders[msg.sender] = true;
    }

    // -------------------------------------------------------------------------
    //  Admin
    // -------------------------------------------------------------------------

    /**
     * @notice Authorise or revoke a recorder address (platform relayer).
     * @param _recorder Address to authorise/revoke.
     * @param _status   true = authorised, false = revoked.
     */
    function setRecorder(address _recorder, bool _status) external onlyOwner {
        require(_recorder != address(0), "SupplyChain: zero address");
        authorisedRecorders[_recorder] = _status;
        emit RecorderAuthorised(_recorder, _status);
    }

    // -------------------------------------------------------------------------
    //  Registration
    // -------------------------------------------------------------------------

    /**
     * @notice Register a new asset on-chain. Gas covered by the platform.
     * @param _assetType   Type of asset.
     * @param _registrant  Address of the original registrant (real user).
     * @param _metadataURI Off-chain metadata link (IPFS / Arweave).
     * @param _externalRef Optional external reference hash (e.g., VIN SHA-256). Pass bytes32(0) to skip.
     * @return assetId The newly assigned asset ID.
     */
    function registerAsset(
        AssetType _assetType,
        address _registrant,
        string calldata _metadataURI,
        bytes32 _externalRef
    ) external onlyAuthorised returns (uint256 assetId) {
        require(_registrant != address(0), "SupplyChain: zero registrant");

        _assetIdCounter++;
        assetId = _assetIdCounter;

        assets[assetId] = Asset({
            assetId: assetId,
            assetType: _assetType,
            registrant: _registrant,
            currentCustodian: _registrant,
            metadataURI: _metadataURI,
            registeredAt: block.timestamp,
            active: true
        });

        // Record the initial registration as the first custody event
        _recordCustodyEvent(
            assetId,
            CustodyAction.REGISTERED,
            address(0),
            _registrant,
            "Initial registration",
            ""
        );

        // Link external reference if provided
        if (_externalRef != bytes32(0)) {
            require(
                externalRefToAsset[_externalRef] == 0,
                "SupplyChain: external ref already linked"
            );
            externalRefToAsset[_externalRef] = assetId;
            emit ExternalRefLinked(assetId, _externalRef);
        }

        emit ProductRegistered(assetId, _assetType, _registrant, _metadataURI, block.timestamp);
    }

    // -------------------------------------------------------------------------
    //  Custody Transfer
    // -------------------------------------------------------------------------

    /**
     * @notice Transfer custody of an asset. Gas covered by the platform.
     * @param _assetId      Asset identifier.
     * @param _action       Type of custody action.
     * @param _toCustodian  New custodian address.
     * @param _notes        Descriptive notes for this event.
     * @param _locationHash Hash of location data (for privacy).
     */
    function transferCustody(
        uint256 _assetId,
        CustodyAction _action,
        address _toCustodian,
        string calldata _notes,
        string calldata _locationHash
    )
        external
        onlyAuthorised
        assetExists(_assetId)
        assetActive(_assetId)
    {
        require(_toCustodian != address(0), "SupplyChain: zero custodian");

        address fromCustodian = assets[_assetId].currentCustodian;
        assets[_assetId].currentCustodian = _toCustodian;

        _recordCustodyEvent(
            _assetId,
            _action,
            fromCustodian,
            _toCustodian,
            _notes,
            _locationHash
        );
    }

    // -------------------------------------------------------------------------
    //  Inspection
    // -------------------------------------------------------------------------

    /**
     * @notice Record an inspection for an asset. Gas covered by the platform.
     * @param _assetId   Asset identifier.
     * @param _inspector Address of the inspector.
     * @param _result    Inspection result.
     * @param _reportURI Off-chain report link.
     * @param _notes     Inspector notes.
     * @return inspectionId The newly assigned inspection ID.
     */
    function recordInspection(
        uint256 _assetId,
        address _inspector,
        InspectionResult _result,
        string calldata _reportURI,
        string calldata _notes
    )
        external
        onlyAuthorised
        assetExists(_assetId)
        assetActive(_assetId)
        returns (uint256 inspectionId)
    {
        require(_inspector != address(0), "SupplyChain: zero inspector");

        _inspectionIdCounter++;
        inspectionId = _inspectionIdCounter;

        inspections[inspectionId] = Inspection({
            inspectionId: inspectionId,
            assetId: _assetId,
            inspector: _inspector,
            result: _result,
            reportURI: _reportURI,
            notes: _notes,
            timestamp: block.timestamp
        });

        assetInspections[_assetId].push(inspectionId);

        emit InspectionRecorded(
            _assetId,
            inspectionId,
            _inspector,
            _result,
            _reportURI,
            block.timestamp
        );
    }

    // -------------------------------------------------------------------------
    //  QR Code Generation Trigger
    // -------------------------------------------------------------------------

    /**
     * @notice Emit a QR-generated event consumed by the off-chain QR service.
     * @param _assetId          Asset identifier.
     * @param _verificationURL  The URL the QR code will resolve to.
     */
    function emitQRGenerated(
        uint256 _assetId,
        string calldata _verificationURL
    ) external onlyAuthorised assetExists(_assetId) {
        emit QRGenerated(_assetId, _verificationURL, block.timestamp);
    }

    // -------------------------------------------------------------------------
    //  Deactivation
    // -------------------------------------------------------------------------

    /**
     * @notice Deactivate an asset (e.g., destroyed, consumed, end-of-life).
     * @param _assetId Asset identifier.
     */
    function deactivateAsset(uint256 _assetId)
        external
        onlyAuthorised
        assetExists(_assetId)
        assetActive(_assetId)
    {
        assets[_assetId].active = false;
        emit AssetDeactivated(_assetId, block.timestamp);
    }

    // -------------------------------------------------------------------------
    //  View Helpers
    // -------------------------------------------------------------------------

    /// @notice Total number of registered assets.
    function totalAssets() external view returns (uint256) {
        return _assetIdCounter;
    }

    /// @notice Number of custody events for an asset.
    function custodyEventCount(uint256 _assetId) external view returns (uint256) {
        return assetCustodyEvents[_assetId].length;
    }

    /// @notice Number of inspections for an asset.
    function inspectionCount(uint256 _assetId) external view returns (uint256) {
        return assetInspections[_assetId].length;
    }

    /// @notice Get all custody event IDs for an asset.
    function getCustodyEventIds(uint256 _assetId) external view returns (uint256[] memory) {
        return assetCustodyEvents[_assetId];
    }

    /// @notice Get all inspection IDs for an asset.
    function getInspectionIds(uint256 _assetId) external view returns (uint256[] memory) {
        return assetInspections[_assetId];
    }

    /// @notice Resolve an external reference to an asset ID.
    function resolveExternalRef(bytes32 _refHash) external view returns (uint256) {
        return externalRefToAsset[_refHash];
    }

    // -------------------------------------------------------------------------
    //  Internal
    // -------------------------------------------------------------------------

    function _recordCustodyEvent(
        uint256 _assetId,
        CustodyAction _action,
        address _from,
        address _to,
        string memory _notes,
        string memory _locationHash
    ) internal {
        _eventIdCounter++;
        uint256 eventId = _eventIdCounter;

        custodyEvents[eventId] = CustodyEvent({
            eventId: eventId,
            assetId: _assetId,
            action: _action,
            fromCustodian: _from,
            toCustodian: _to,
            notes: _notes,
            locationHash: _locationHash,
            timestamp: block.timestamp
        });

        assetCustodyEvents[_assetId].push(eventId);

        emit CustodyTransferred(
            _assetId,
            eventId,
            _action,
            _from,
            _to,
            _notes,
            block.timestamp
        );
    }
}
