// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title JointOwnership
 * @notice Component 4 - Real-World Asset Joint Ownership Contract
 * @dev N-party ownership splits with configurable governance.
 *      Follows a pending/active state model:
 *        deployed -> pending (until all parties sign legal doc) -> active
 *      Funds held in escrow remain locked until the contract is fully active.
 *
 *      The platform covers ALL gas costs and takes NOTHING from any party.
 *      Every ownership transfer emits events consumed by Component 12
 *      (Supply Chain / Chain of Custody).
 *
 *      The on-chain contract and off-chain legal document reference each
 *      other by mutual hash - neither can be altered without breaking the link.
 */
contract JointOwnership is Ownable, ReentrancyGuard {
    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice The NeoSafe multi-sig wallet.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Basis-point denominator for percentage calculations.
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // ----------------------------------------------------------------
    // Enums
    // ----------------------------------------------------------------

    enum ContractState {
        DEPLOYED,
        PENDING,
        ACTIVE,
        DISPUTED,
        TERMINATED
    }

    enum DecisionRule {
        UNANIMOUS,
        MAJORITY,
        SUPERMAJORITY,
        WEIGHTED
    }

    enum DisputeStatus {
        NONE,
        FILED,
        UNDER_REVIEW,
        RESOLVED
    }

    // ----------------------------------------------------------------
    // Structs
    // ----------------------------------------------------------------

    struct OwnershipShare {
        address party;
        uint256 shareBps;           // ownership in basis points
        bool hasSigned;
        uint256 escrowBalance;
        uint256 profitWithdrawn;
    }

    struct GovernanceConfig {
        DecisionRule decisionRule;
        uint256 supermajorityThresholdBps; // e.g. 6667 for 66.67 %
        uint256 exitNoticePeriod;          // seconds
        uint256 maintenanceAllocationBps;  // portion reserved for upkeep
    }

    struct JointContract {
        bytes32 contractId;
        ContractState state;
        bytes32 legalDocumentHash;
        bytes32 contractCodeHash;
        string assetIdentifier;
        uint256 createdAt;
        uint256 activatedAt;
        uint256 totalEscrow;
        uint256 totalProfitDistributed;
        GovernanceConfig governance;
        DisputeStatus disputeStatus;
        address[] partyAddresses;
    }

    struct TransferRecord {
        bytes32 contractId;
        address from;
        address to;
        uint256 shareBps;
        uint256 timestamp;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Rexhepi gate address authorised to call gated functions.
    address public rexhepiGate;

    /// @notice All joint contracts by ID.
    mapping(bytes32 => JointContract) public jointContracts;

    /// @notice Ownership shares: contractId -> party address -> share.
    mapping(bytes32 => mapping(address => OwnershipShare)) public shares;

    /// @notice Transfer history per contract.
    mapping(bytes32 => TransferRecord[]) private _transferHistory;

    /// @notice Running counter for unique contract IDs.
    uint256 public contractCount;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event ContractCreated(
        bytes32 indexed contractId,
        string assetIdentifier,
        address[] parties,
        uint256[] sharesBps,
        bytes32 legalDocumentHash,
        uint256 timestamp
    );

    event SignatureReceived(
        bytes32 indexed contractId,
        address indexed party,
        uint256 timestamp
    );

    event ContractActivated(
        bytes32 indexed contractId,
        uint256 timestamp
    );

    event OwnershipTransferred(
        bytes32 indexed contractId,
        address indexed from,
        address indexed to,
        uint256 shareBps,
        uint256 timestamp
    );

    event DisputeFiled(
        bytes32 indexed contractId,
        address indexed filedBy,
        string reason,
        uint256 timestamp
    );

    event EscrowDeposited(
        bytes32 indexed contractId,
        address indexed party,
        uint256 amount,
        uint256 timestamp
    );

    event ProfitDistributed(
        bytes32 indexed contractId,
        uint256 totalAmount,
        uint256 timestamp
    );

    event ContractTerminated(
        bytes32 indexed contractId,
        uint256 timestamp
    );

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyThroughRexhepiGate() {
        require(
            msg.sender == rexhepiGate,
            "JointOwnership: caller is not the Rexhepi gate"
        );
        _;
    }

    modifier contractExists(bytes32 _contractId) {
        require(
            jointContracts[_contractId].createdAt != 0,
            "JointOwnership: contract does not exist"
        );
        _;
    }

    modifier onlyParty(bytes32 _contractId, address _party) {
        require(
            shares[_contractId][_party].party != address(0),
            "JointOwnership: not a party to this contract"
        );
        _;
    }

    modifier inState(bytes32 _contractId, ContractState _state) {
        require(
            jointContracts[_contractId].state == _state,
            "JointOwnership: invalid contract state for this action"
        );
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor(address _rexhepiGate) Ownable(msg.sender) {
        require(
            _rexhepiGate != address(0),
            "JointOwnership: gate cannot be zero address"
        );
        rexhepiGate = _rexhepiGate;
    }

    // ----------------------------------------------------------------
    // External / Public Functions
    // ----------------------------------------------------------------

    /**
     * @notice Create a new joint ownership contract.
     * @param _assetIdentifier   Human-readable asset reference.
     * @param _parties           Addresses of all co-owners.
     * @param _sharesBps         Ownership percentages in basis points (must sum to 10000).
     * @param _legalDocumentHash keccak256 hash of the corresponding legal document.
     * @param _decisionRule      Governance decision-making rule.
     * @param _supermajorityBps  Threshold for supermajority votes (ignored if not SUPERMAJORITY).
     * @param _exitNoticePeriod  Required notice period in seconds for exit.
     * @param _maintenanceBps    Basis points reserved for maintenance allocation.
     * @return contractId        Unique identifier for this joint contract.
     */
    function createContract(
        string calldata _assetIdentifier,
        address[] calldata _parties,
        uint256[] calldata _sharesBps,
        bytes32 _legalDocumentHash,
        DecisionRule _decisionRule,
        uint256 _supermajorityBps,
        uint256 _exitNoticePeriod,
        uint256 _maintenanceBps
    )
        external
        onlyThroughRexhepiGate
        nonReentrant
        returns (bytes32 contractId)
    {
        require(
            _parties.length >= 2,
            "JointOwnership: minimum 2 parties required"
        );
        require(
            _parties.length == _sharesBps.length,
            "JointOwnership: parties and shares length mismatch"
        );
        require(
            _legalDocumentHash != bytes32(0),
            "JointOwnership: legal document hash required"
        );

        // Validate shares sum to 100 %
        uint256 totalShares = 0;
        for (uint256 i = 0; i < _sharesBps.length; i++) {
            require(_sharesBps[i] > 0, "JointOwnership: share must be > 0");
            totalShares += _sharesBps[i];
        }
        require(
            totalShares == BPS_DENOMINATOR,
            "JointOwnership: shares must sum to 10000 bps"
        );

        // Generate unique contract ID
        contractCount++;
        contractId = keccak256(
            abi.encodePacked(
                msg.sender,
                _assetIdentifier,
                contractCount,
                block.timestamp
            )
        );

        // Store governance config
        GovernanceConfig memory gov = GovernanceConfig({
            decisionRule: _decisionRule,
            supermajorityThresholdBps: _supermajorityBps,
            exitNoticePeriod: _exitNoticePeriod,
            maintenanceAllocationBps: _maintenanceBps
        });

        // Initialise contract record
        jointContracts[contractId].contractId = contractId;
        jointContracts[contractId].state = ContractState.PENDING;
        jointContracts[contractId].legalDocumentHash = _legalDocumentHash;
        jointContracts[contractId].contractCodeHash = keccak256(
            abi.encodePacked(address(this).code)
        );
        jointContracts[contractId].assetIdentifier = _assetIdentifier;
        jointContracts[contractId].createdAt = block.timestamp;
        jointContracts[contractId].governance = gov;
        jointContracts[contractId].disputeStatus = DisputeStatus.NONE;
        jointContracts[contractId].partyAddresses = _parties;

        // Initialise ownership shares
        for (uint256 i = 0; i < _parties.length; i++) {
            require(
                _parties[i] != address(0),
                "JointOwnership: party cannot be zero address"
            );
            require(
                shares[contractId][_parties[i]].party == address(0),
                "JointOwnership: duplicate party address"
            );

            shares[contractId][_parties[i]] = OwnershipShare({
                party: _parties[i],
                shareBps: _sharesBps[i],
                hasSigned: false,
                escrowBalance: 0,
                profitWithdrawn: 0
            });
        }

        emit ContractCreated(
            contractId,
            _assetIdentifier,
            _parties,
            _sharesBps,
            _legalDocumentHash,
            block.timestamp
        );
    }

    /**
     * @notice Record a party's signature on the legal document.
     *         When all parties have signed the contract activates automatically.
     * @param _contractId The joint contract to sign.
     * @param _party      The signing party's address.
     */
    function signContract(
        bytes32 _contractId,
        address _party
    )
        external
        onlyThroughRexhepiGate
        contractExists(_contractId)
        onlyParty(_contractId, _party)
        inState(_contractId, ContractState.PENDING)
    {
        require(
            !shares[_contractId][_party].hasSigned,
            "JointOwnership: party has already signed"
        );

        shares[_contractId][_party].hasSigned = true;

        emit SignatureReceived(_contractId, _party, block.timestamp);

        // Check if all parties have signed
        if (_allPartiesSigned(_contractId)) {
            _activateContract(_contractId);
        }
    }

    /**
     * @notice Deposit funds into escrow for a pending or active contract.
     *         Escrow remains locked until the contract is fully active.
     * @param _contractId The joint contract.
     * @param _party      The depositing party.
     */
    function depositEscrow(
        bytes32 _contractId,
        address _party
    )
        external
        payable
        onlyThroughRexhepiGate
        contractExists(_contractId)
        onlyParty(_contractId, _party)
        nonReentrant
    {
        require(msg.value > 0, "JointOwnership: deposit must be > 0");
        require(
            jointContracts[_contractId].state == ContractState.PENDING ||
            jointContracts[_contractId].state == ContractState.ACTIVE,
            "JointOwnership: contract not accepting deposits"
        );

        shares[_contractId][_party].escrowBalance += msg.value;
        jointContracts[_contractId].totalEscrow += msg.value;

        emit EscrowDeposited(_contractId, _party, msg.value, block.timestamp);
    }

    /**
     * @notice Transfer ownership share from one party to another.
     *         Emits OwnershipTransferred for Component 12 consumption.
     * @param _contractId The joint contract.
     * @param _from       The current owner transferring shares.
     * @param _to         The recipient of the shares.
     * @param _shareBps   The amount of ownership to transfer in basis points.
     */
    function transferOwnership(
        bytes32 _contractId,
        address _from,
        address _to,
        uint256 _shareBps
    )
        external
        onlyThroughRexhepiGate
        contractExists(_contractId)
        onlyParty(_contractId, _from)
        inState(_contractId, ContractState.ACTIVE)
        nonReentrant
    {
        require(_to != address(0), "JointOwnership: cannot transfer to zero address");
        require(_shareBps > 0, "JointOwnership: transfer share must be > 0");
        require(
            shares[_contractId][_from].shareBps >= _shareBps,
            "JointOwnership: insufficient ownership share"
        );

        // Reduce sender's share
        shares[_contractId][_from].shareBps -= _shareBps;

        // Add or create recipient's share
        if (shares[_contractId][_to].party == address(0)) {
            // New party
            shares[_contractId][_to] = OwnershipShare({
                party: _to,
                shareBps: _shareBps,
                hasSigned: true,
                escrowBalance: 0,
                profitWithdrawn: 0
            });
            jointContracts[_contractId].partyAddresses.push(_to);
        } else {
            shares[_contractId][_to].shareBps += _shareBps;
        }

        // Remove sender if fully transferred
        if (shares[_contractId][_from].shareBps == 0) {
            shares[_contractId][_from].party = address(0);
        }

        // Record transfer
        _transferHistory[_contractId].push(TransferRecord({
            contractId: _contractId,
            from: _from,
            to: _to,
            shareBps: _shareBps,
            timestamp: block.timestamp
        }));

        // Emit for Component 12 chain of custody
        emit OwnershipTransferred(
            _contractId,
            _from,
            _to,
            _shareBps,
            block.timestamp
        );
    }

    /**
     * @notice Distribute profit to all active parties proportional to ownership.
     * @param _contractId The joint contract.
     */
    function distributeProfits(
        bytes32 _contractId
    )
        external
        payable
        onlyThroughRexhepiGate
        contractExists(_contractId)
        inState(_contractId, ContractState.ACTIVE)
        nonReentrant
    {
        require(msg.value > 0, "JointOwnership: profit must be > 0");

        JointContract storage jc = jointContracts[_contractId];

        // Reserve maintenance allocation
        uint256 maintenanceReserve = (msg.value * jc.governance.maintenanceAllocationBps) / BPS_DENOMINATOR;
        uint256 distributable = msg.value - maintenanceReserve;

        // Distribute proportionally
        for (uint256 i = 0; i < jc.partyAddresses.length; i++) {
            address party = jc.partyAddresses[i];
            OwnershipShare storage share = shares[_contractId][party];

            if (share.party == address(0) || share.shareBps == 0) continue;

            uint256 partyAmount = (distributable * share.shareBps) / BPS_DENOMINATOR;
            share.profitWithdrawn += partyAmount;

            (bool sent, ) = payable(party).call{value: partyAmount}("");
            require(sent, "JointOwnership: profit transfer failed");
        }

        jc.totalProfitDistributed += distributable;

        emit ProfitDistributed(_contractId, distributable, block.timestamp);
    }

    /**
     * @notice File a dispute on a joint contract. Routes to Component 30.
     * @param _contractId The joint contract.
     * @param _filedBy    The party filing the dispute.
     * @param _reason     Description of the dispute.
     */
    function fileDispute(
        bytes32 _contractId,
        address _filedBy,
        string calldata _reason
    )
        external
        onlyThroughRexhepiGate
        contractExists(_contractId)
        onlyParty(_contractId, _filedBy)
    {
        require(
            jointContracts[_contractId].state == ContractState.ACTIVE,
            "JointOwnership: can only dispute active contracts"
        );

        jointContracts[_contractId].state = ContractState.DISPUTED;
        jointContracts[_contractId].disputeStatus = DisputeStatus.FILED;

        emit DisputeFiled(_contractId, _filedBy, _reason, block.timestamp);
    }

    /**
     * @notice Resolve a dispute and return the contract to active state.
     * @param _contractId The disputed contract.
     */
    function resolveDispute(
        bytes32 _contractId
    )
        external
        onlyThroughRexhepiGate
        contractExists(_contractId)
        inState(_contractId, ContractState.DISPUTED)
    {
        jointContracts[_contractId].state = ContractState.ACTIVE;
        jointContracts[_contractId].disputeStatus = DisputeStatus.RESOLVED;
    }

    /**
     * @notice Terminate a joint contract.
     * @param _contractId The contract to terminate.
     */
    function terminateContract(
        bytes32 _contractId
    )
        external
        onlyThroughRexhepiGate
        contractExists(_contractId)
    {
        jointContracts[_contractId].state = ContractState.TERMINATED;
        emit ContractTerminated(_contractId, block.timestamp);
    }

    // ----------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------

    /**
     * @notice Get the full transfer history for a contract.
     * @param _contractId The joint contract.
     * @return records Array of transfer records.
     */
    function getTransferHistory(
        bytes32 _contractId
    ) external view returns (TransferRecord[] memory records) {
        return _transferHistory[_contractId];
    }

    /**
     * @notice Get the list of party addresses for a contract.
     * @param _contractId The joint contract.
     * @return parties Array of party addresses.
     */
    function getParties(
        bytes32 _contractId
    ) external view returns (address[] memory parties) {
        return jointContracts[_contractId].partyAddresses;
    }

    /**
     * @notice Update the Rexhepi gate address. Owner-only.
     * @param _newGate The new gate address.
     */
    function setRexhepiGate(address _newGate) external onlyOwner {
        require(
            _newGate != address(0),
            "JointOwnership: gate cannot be zero address"
        );
        rexhepiGate = _newGate;
    }

    // ----------------------------------------------------------------
    // Internal Functions
    // ----------------------------------------------------------------

    /**
     * @dev Check whether every party has signed the legal document.
     */
    function _allPartiesSigned(bytes32 _contractId) internal view returns (bool) {
        address[] storage parties = jointContracts[_contractId].partyAddresses;
        for (uint256 i = 0; i < parties.length; i++) {
            if (!shares[_contractId][parties[i]].hasSigned) {
                return false;
            }
        }
        return true;
    }

    /**
     * @dev Activate a contract once all parties have signed.
     */
    function _activateContract(bytes32 _contractId) internal {
        jointContracts[_contractId].state = ContractState.ACTIVE;
        jointContracts[_contractId].activatedAt = block.timestamp;
        emit ContractActivated(_contractId, block.timestamp);
    }

    // ----------------------------------------------------------------
    // Receive / Fallback
    // ----------------------------------------------------------------

    receive() external payable {}
    fallback() external payable {}
}
