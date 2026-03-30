// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title OpenMatrixDID
 * @notice Component 5 - Decentralized Identity (DID) Registry
 * @dev W3C DID standard compliant on-chain identity registry.
 *
 *      Core principles:
 *        - Users control exactly what personal info they put on the platform
 *        - Nothing is ever required
 *        - All gas costs are covered by the platform, always
 *        - Users own their identity data - the platform never has access
 *
 *      DID format: did:openmatrix:<ethereum-address>
 *
 *      Each DID document can hold an arbitrary number of credentials
 *      (as hashes), service endpoints, and verification methods, all
 *      controlled exclusively by the DID subject.
 */
contract OpenMatrixDID is Ownable, ReentrancyGuard {
    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice The NeoSafe multi-sig wallet.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice DID method prefix.
    string public constant DID_METHOD = "did:openmatrix:";

    // ----------------------------------------------------------------
    // Enums
    // ----------------------------------------------------------------

    enum DIDStatus {
        NONEXISTENT,
        ACTIVE,
        REVOKED
    }

    enum VerificationMethodType {
        ED25519,
        SECP256K1,
        RSA,
        X25519
    }

    // ----------------------------------------------------------------
    // Structs
    // ----------------------------------------------------------------

    struct VerificationMethod {
        bytes32 methodId;
        VerificationMethodType methodType;
        bytes publicKeyData;
        bool active;
    }

    struct ServiceEndpoint {
        bytes32 serviceId;
        string serviceType;
        string endpoint;
        bool active;
    }

    struct Credential {
        bytes32 credentialHash;
        string credentialType;
        address issuer;
        uint256 issuedAt;
        uint256 expiresAt;
        bool revoked;
    }

    struct DIDDocument {
        address subject;
        DIDStatus status;
        uint256 createdAt;
        uint256 updatedAt;
        uint256 nonce;
        bytes32[] verificationMethodIds;
        bytes32[] serviceEndpointIds;
        bytes32[] credentialHashes;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Rexhepi gate address authorised to call gated functions.
    address public rexhepiGate;

    /// @notice DID documents by subject address.
    mapping(address => DIDDocument) public didDocuments;

    /// @notice Verification methods: subject -> methodId -> method.
    mapping(address => mapping(bytes32 => VerificationMethod)) public verificationMethods;

    /// @notice Service endpoints: subject -> serviceId -> endpoint.
    mapping(address => mapping(bytes32 => ServiceEndpoint)) public serviceEndpoints;

    /// @notice Credentials: subject -> credentialHash -> credential.
    mapping(address => mapping(bytes32 => Credential)) public credentials;

    /// @notice Total number of DIDs created.
    uint256 public totalDIDs;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event DIDCreated(
        address indexed subject,
        uint256 timestamp
    );

    event DIDUpdated(
        address indexed subject,
        uint256 nonce,
        uint256 timestamp
    );

    event DIDRevoked(
        address indexed subject,
        uint256 timestamp
    );

    event CredentialAdded(
        address indexed subject,
        bytes32 indexed credentialHash,
        string credentialType,
        address indexed issuer,
        uint256 timestamp
    );

    event CredentialRevoked(
        address indexed subject,
        bytes32 indexed credentialHash,
        uint256 timestamp
    );

    event VerificationMethodAdded(
        address indexed subject,
        bytes32 indexed methodId,
        VerificationMethodType methodType,
        uint256 timestamp
    );

    event ServiceEndpointAdded(
        address indexed subject,
        bytes32 indexed serviceId,
        string serviceType,
        uint256 timestamp
    );

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyThroughRexhepiGate() {
        require(
            msg.sender == rexhepiGate,
            "OpenMatrixDID: caller is not the Rexhepi gate"
        );
        _;
    }

    modifier didExists(address _subject) {
        require(
            didDocuments[_subject].status != DIDStatus.NONEXISTENT,
            "OpenMatrixDID: DID does not exist"
        );
        _;
    }

    modifier didActive(address _subject) {
        require(
            didDocuments[_subject].status == DIDStatus.ACTIVE,
            "OpenMatrixDID: DID is not active"
        );
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor(address _rexhepiGate) Ownable(msg.sender) {
        require(
            _rexhepiGate != address(0),
            "OpenMatrixDID: gate cannot be zero address"
        );
        rexhepiGate = _rexhepiGate;
    }

    // ----------------------------------------------------------------
    // External / Public Functions
    // ----------------------------------------------------------------

    /**
     * @notice Create a new DID for a subject.
     *         Nothing is required from the user - the DID is a blank canvas
     *         they can populate at their discretion.
     * @param _subject The address creating the DID (the DID subject).
     */
    function createDID(
        address _subject
    ) external onlyThroughRexhepiGate {
        require(
            _subject != address(0),
            "OpenMatrixDID: subject cannot be zero address"
        );
        require(
            didDocuments[_subject].status == DIDStatus.NONEXISTENT,
            "OpenMatrixDID: DID already exists for this subject"
        );

        didDocuments[_subject] = DIDDocument({
            subject: _subject,
            status: DIDStatus.ACTIVE,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            nonce: 0,
            verificationMethodIds: new bytes32[](0),
            serviceEndpointIds: new bytes32[](0),
            credentialHashes: new bytes32[](0)
        });

        totalDIDs++;

        emit DIDCreated(_subject, block.timestamp);
    }

    /**
     * @notice Add a verification method to a DID document.
     * @param _subject    The DID subject.
     * @param _methodId   Unique identifier for the method.
     * @param _methodType The type of verification method.
     * @param _publicKey  The public key data.
     */
    function addVerificationMethod(
        address _subject,
        bytes32 _methodId,
        VerificationMethodType _methodType,
        bytes calldata _publicKey
    )
        external
        onlyThroughRexhepiGate
        didActive(_subject)
    {
        require(
            verificationMethods[_subject][_methodId].methodId == bytes32(0),
            "OpenMatrixDID: verification method already exists"
        );
        require(
            _publicKey.length > 0,
            "OpenMatrixDID: public key data required"
        );

        verificationMethods[_subject][_methodId] = VerificationMethod({
            methodId: _methodId,
            methodType: _methodType,
            publicKeyData: _publicKey,
            active: true
        });

        didDocuments[_subject].verificationMethodIds.push(_methodId);
        _touchDID(_subject);

        emit VerificationMethodAdded(_subject, _methodId, _methodType, block.timestamp);
    }

    /**
     * @notice Add a service endpoint to a DID document.
     * @param _subject     The DID subject.
     * @param _serviceId   Unique identifier for the service.
     * @param _serviceType The type of service (e.g. "LinkedDomains", "MessagingService").
     * @param _endpoint    The service endpoint URL.
     */
    function addServiceEndpoint(
        address _subject,
        bytes32 _serviceId,
        string calldata _serviceType,
        string calldata _endpoint
    )
        external
        onlyThroughRexhepiGate
        didActive(_subject)
    {
        require(
            serviceEndpoints[_subject][_serviceId].serviceId == bytes32(0),
            "OpenMatrixDID: service endpoint already exists"
        );

        serviceEndpoints[_subject][_serviceId] = ServiceEndpoint({
            serviceId: _serviceId,
            serviceType: _serviceType,
            endpoint: _endpoint,
            active: true
        });

        didDocuments[_subject].serviceEndpointIds.push(_serviceId);
        _touchDID(_subject);

        emit ServiceEndpointAdded(_subject, _serviceId, _serviceType, block.timestamp);
    }

    /**
     * @notice Add a credential to a DID document.
     *         The credential data itself is stored off-chain, encrypted with
     *         the user's own keys. Only the hash is recorded on-chain.
     * @param _subject        The DID subject.
     * @param _credentialHash keccak256 hash of the credential data.
     * @param _credentialType Human-readable credential type.
     * @param _issuer         Address of the credential issuer.
     * @param _expiresAt      Expiry timestamp (0 for no expiry).
     */
    function addCredential(
        address _subject,
        bytes32 _credentialHash,
        string calldata _credentialType,
        address _issuer,
        uint256 _expiresAt
    )
        external
        onlyThroughRexhepiGate
        didActive(_subject)
    {
        require(
            _credentialHash != bytes32(0),
            "OpenMatrixDID: credential hash required"
        );
        require(
            credentials[_subject][_credentialHash].credentialHash == bytes32(0),
            "OpenMatrixDID: credential already exists"
        );

        credentials[_subject][_credentialHash] = Credential({
            credentialHash: _credentialHash,
            credentialType: _credentialType,
            issuer: _issuer,
            issuedAt: block.timestamp,
            expiresAt: _expiresAt,
            revoked: false
        });

        didDocuments[_subject].credentialHashes.push(_credentialHash);
        _touchDID(_subject);

        emit CredentialAdded(
            _subject,
            _credentialHash,
            _credentialType,
            _issuer,
            block.timestamp
        );
    }

    /**
     * @notice Update a DID document (bump nonce, update timestamp).
     *         Used when off-chain DID document content has changed.
     * @param _subject The DID subject.
     */
    function updateDID(
        address _subject
    )
        external
        onlyThroughRexhepiGate
        didActive(_subject)
    {
        _touchDID(_subject);

        emit DIDUpdated(
            _subject,
            didDocuments[_subject].nonce,
            block.timestamp
        );
    }

    /**
     * @notice Resolve a DID - return the on-chain DID document.
     * @param _subject The DID subject address.
     * @return document The DID document.
     */
    function resolveDID(
        address _subject
    )
        external
        view
        didExists(_subject)
        returns (DIDDocument memory document)
    {
        return didDocuments[_subject];
    }

    /**
     * @notice Revoke a DID permanently.
     * @param _subject The DID subject.
     */
    function revokeDID(
        address _subject
    )
        external
        onlyThroughRexhepiGate
        didActive(_subject)
    {
        didDocuments[_subject].status = DIDStatus.REVOKED;
        didDocuments[_subject].updatedAt = block.timestamp;

        emit DIDRevoked(_subject, block.timestamp);
    }

    /**
     * @notice Revoke a specific credential.
     * @param _subject        The DID subject.
     * @param _credentialHash The credential to revoke.
     */
    function revokeCredential(
        address _subject,
        bytes32 _credentialHash
    )
        external
        onlyThroughRexhepiGate
        didActive(_subject)
    {
        require(
            credentials[_subject][_credentialHash].credentialHash != bytes32(0),
            "OpenMatrixDID: credential does not exist"
        );
        require(
            !credentials[_subject][_credentialHash].revoked,
            "OpenMatrixDID: credential already revoked"
        );

        credentials[_subject][_credentialHash].revoked = true;
        _touchDID(_subject);

        emit CredentialRevoked(_subject, _credentialHash, block.timestamp);
    }

    // ----------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------

    /**
     * @notice Check if a credential is valid (exists, not revoked, not expired).
     * @param _subject        The DID subject.
     * @param _credentialHash The credential hash to check.
     * @return valid Whether the credential is currently valid.
     */
    function isCredentialValid(
        address _subject,
        bytes32 _credentialHash
    ) external view returns (bool valid) {
        Credential storage cred = credentials[_subject][_credentialHash];
        if (cred.credentialHash == bytes32(0)) return false;
        if (cred.revoked) return false;
        if (cred.expiresAt != 0 && cred.expiresAt < block.timestamp) return false;
        return true;
    }

    /**
     * @notice Update the Rexhepi gate address. Owner-only.
     * @param _newGate The new gate address.
     */
    function setRexhepiGate(address _newGate) external onlyOwner {
        require(
            _newGate != address(0),
            "OpenMatrixDID: gate cannot be zero address"
        );
        rexhepiGate = _newGate;
    }

    // ----------------------------------------------------------------
    // Internal Functions
    // ----------------------------------------------------------------

    /**
     * @dev Bump the nonce and update timestamp on a DID document.
     */
    function _touchDID(address _subject) internal {
        didDocuments[_subject].nonce++;
        didDocuments[_subject].updatedAt = block.timestamp;
    }

    // ----------------------------------------------------------------
    // Receive / Fallback
    // ----------------------------------------------------------------

    receive() external payable {}
    fallback() external payable {}
}
