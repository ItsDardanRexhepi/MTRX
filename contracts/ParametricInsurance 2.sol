// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title ParametricInsurance
 * @notice Parametric insurance with oracle-triggered automatic payouts on Base.
 * @dev Policies are defined with measurable trigger conditions. When an
 *      authorised oracle reports a parameter value that breaches the trigger
 *      threshold, the payout is executed automatically -- no claims process.
 *
 *      Phase 2 injection points are marked with `PHASE2:` comments for future
 *      expansion (e.g. Chainlink Functions, cross-chain oracles, pool-based
 *      underwriting, risk tranching).
 *
 *      Architecture:
 *        - Insurer creates a policy pool and deposits collateral.
 *        - Policyholders purchase coverage by paying premiums into the pool.
 *        - Authorised oracles submit parameter readings.
 *        - If a reading triggers a policy, the payout is automatic.
 *        - Unclaimed/expired policies return collateral to the insurer.
 */
contract ParametricInsurance is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice NeoSafe multi-sig for administrative fee routing.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    enum TriggerOperator {
        GreaterThan,
        LessThan,
        GreaterOrEqual,
        LessOrEqual
    }

    enum PolicyStatus {
        Active,
        Triggered,
        Expired,
        Cancelled
    }

    enum PoolStatus {
        Active,
        Depleted,
        Closed
    }

    struct InsurancePool {
        address insurer;
        address paymentToken;         // ERC-20 token for premiums and payouts
        uint256 totalCollateral;      // Total collateral deposited
        uint256 availableCollateral;  // Collateral not yet committed
        uint256 totalPremiums;        // Total premiums collected
        string parameterName;         // e.g. "rainfall_mm", "earthquake_magnitude"
        PoolStatus status;
    }

    struct Policy {
        uint256 poolId;
        address policyholder;
        uint256 premium;              // Premium paid
        uint256 coverageAmount;       // Maximum payout
        int256 triggerValue;          // Threshold value
        TriggerOperator triggerOp;    // Comparison operator
        uint256 startTime;
        uint256 endTime;
        PolicyStatus status;
    }

    struct OracleReading {
        uint256 poolId;
        int256 value;
        uint256 timestamp;
        address oracle;
        bytes32 dataHash;             // Hash of off-chain data proof
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    uint256 public nextPoolId;
    uint256 public nextPolicyId;
    uint256 public nextReadingId;

    mapping(uint256 => InsurancePool) public pools;
    mapping(uint256 => Policy) public policies;
    mapping(uint256 => OracleReading) public readings;

    /// @notice Authorised oracle addresses per pool.
    mapping(uint256 => mapping(address => bool)) public poolOracles;

    /// @notice Policies belonging to a pool.
    mapping(uint256 => uint256[]) public poolPolicies;

    /// @notice Policies belonging to a policyholder.
    mapping(address => uint256[]) public holderPolicies;

    // PHASE2: Chainlink automation keeper registry address
    // PHASE2: Cross-chain oracle bridge interface
    // PHASE2: Risk tranche mapping for pool segmentation
    // PHASE2: Reinsurance pool linkage

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event PoolCreated(uint256 indexed poolId, address indexed insurer, address paymentToken, string parameterName);
    event CollateralDeposited(uint256 indexed poolId, uint256 amount);
    event CollateralWithdrawn(uint256 indexed poolId, uint256 amount);
    event OracleAdded(uint256 indexed poolId, address indexed oracle);
    event OracleRemoved(uint256 indexed poolId, address indexed oracle);
    event PolicyPurchased(uint256 indexed policyId, uint256 indexed poolId, address indexed policyholder, uint256 premium, uint256 coverageAmount);
    event OracleReadingSubmitted(uint256 indexed readingId, uint256 indexed poolId, int256 value, address indexed oracle);
    event PolicyTriggered(uint256 indexed policyId, uint256 indexed readingId, uint256 payoutAmount);
    event PolicyExpired(uint256 indexed policyId);
    event PolicyCancelled(uint256 indexed policyId, uint256 refund);
    event PoolClosed(uint256 indexed poolId);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error NotInsurer();
    error NotOracle();
    error NotPolicyholder();
    error PoolNotActive();
    error PolicyNotActive();
    error PolicyNotExpired();
    error InsufficientCollateral();
    error InvalidTimeRange();
    error ZeroAmount();
    error ZeroAddress();

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyInsurer(uint256 poolId) {
        if (msg.sender != pools[poolId].insurer) revert NotInsurer();
        _;
    }

    modifier onlyOracle(uint256 poolId) {
        if (!poolOracles[poolId][msg.sender]) revert NotOracle();
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor() {}

    // ----------------------------------------------------------------
    // Pool Management
    // ----------------------------------------------------------------

    /**
     * @notice Create a new insurance pool.
     * @param paymentToken   ERC-20 token for premiums and payouts.
     * @param parameterName  Name of the parameter being insured against.
     * @param initialCollateral Initial collateral deposit.
     * @return poolId        The new pool's ID.
     */
    function createPool(
        address paymentToken,
        string calldata parameterName,
        uint256 initialCollateral
    ) external whenNotPaused returns (uint256 poolId) {
        if (paymentToken == address(0)) revert ZeroAddress();

        poolId = nextPoolId++;

        pools[poolId] = InsurancePool({
            insurer: msg.sender,
            paymentToken: paymentToken,
            totalCollateral: 0,
            availableCollateral: 0,
            totalPremiums: 0,
            parameterName: parameterName,
            status: PoolStatus.Active
        });

        emit PoolCreated(poolId, msg.sender, paymentToken, parameterName);

        if (initialCollateral > 0) {
            _depositCollateral(poolId, initialCollateral);
        }
    }

    /**
     * @notice Deposit additional collateral into a pool.
     * @param poolId The pool to fund.
     * @param amount Amount of collateral to deposit.
     */
    function depositCollateral(uint256 poolId, uint256 amount)
        external
        onlyInsurer(poolId)
        whenNotPaused
    {
        _depositCollateral(poolId, amount);
    }

    function _depositCollateral(uint256 poolId, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        InsurancePool storage pool = pools[poolId];
        if (pool.status != PoolStatus.Active) revert PoolNotActive();

        IERC20(pool.paymentToken).safeTransferFrom(msg.sender, address(this), amount);
        pool.totalCollateral += amount;
        pool.availableCollateral += amount;

        emit CollateralDeposited(poolId, amount);
    }

    /**
     * @notice Withdraw uncommitted collateral from a pool.
     * @param poolId The pool to withdraw from.
     * @param amount Amount to withdraw.
     */
    function withdrawCollateral(uint256 poolId, uint256 amount)
        external
        onlyInsurer(poolId)
        nonReentrant
    {
        InsurancePool storage pool = pools[poolId];
        if (amount == 0) revert ZeroAmount();
        if (amount > pool.availableCollateral) revert InsufficientCollateral();

        pool.availableCollateral -= amount;
        pool.totalCollateral -= amount;

        IERC20(pool.paymentToken).safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(poolId, amount);
    }

    /// @notice Add an authorised oracle to a pool.
    function addOracle(uint256 poolId, address oracle)
        external
        onlyInsurer(poolId)
    {
        if (oracle == address(0)) revert ZeroAddress();
        poolOracles[poolId][oracle] = true;
        emit OracleAdded(poolId, oracle);
    }

    /// @notice Remove an oracle from a pool.
    function removeOracle(uint256 poolId, address oracle)
        external
        onlyInsurer(poolId)
    {
        poolOracles[poolId][oracle] = false;
        emit OracleRemoved(poolId, oracle);
    }

    /// @notice Close a pool (no new policies, insurer can withdraw remaining collateral).
    function closePool(uint256 poolId) external onlyInsurer(poolId) {
        pools[poolId].status = PoolStatus.Closed;
        emit PoolClosed(poolId);
    }

    // ----------------------------------------------------------------
    // Policy Purchase
    // ----------------------------------------------------------------

    /**
     * @notice Purchase an insurance policy from a pool.
     * @param poolId         The pool to purchase from.
     * @param premium        Premium amount to pay.
     * @param coverageAmount Maximum payout on trigger.
     * @param triggerValue   Threshold value for the trigger.
     * @param triggerOp      Comparison operator.
     * @param duration       Policy duration in seconds.
     * @return policyId      The new policy's ID.
     */
    function purchasePolicy(
        uint256 poolId,
        uint256 premium,
        uint256 coverageAmount,
        int256 triggerValue,
        TriggerOperator triggerOp,
        uint256 duration
    ) external whenNotPaused nonReentrant returns (uint256 policyId) {
        InsurancePool storage pool = pools[poolId];
        if (pool.status != PoolStatus.Active) revert PoolNotActive();
        if (premium == 0 || coverageAmount == 0) revert ZeroAmount();
        if (duration == 0) revert InvalidTimeRange();
        if (coverageAmount > pool.availableCollateral) revert InsufficientCollateral();

        policyId = nextPolicyId++;

        policies[policyId] = Policy({
            poolId: poolId,
            policyholder: msg.sender,
            premium: premium,
            coverageAmount: coverageAmount,
            triggerValue: triggerValue,
            triggerOp: triggerOp,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            status: PolicyStatus.Active
        });

        // Reserve collateral for this policy
        pool.availableCollateral -= coverageAmount;
        pool.totalPremiums += premium;

        // Collect premium
        IERC20(pool.paymentToken).safeTransferFrom(msg.sender, address(this), premium);

        poolPolicies[poolId].push(policyId);
        holderPolicies[msg.sender].push(policyId);

        emit PolicyPurchased(policyId, poolId, msg.sender, premium, coverageAmount);
    }

    // ----------------------------------------------------------------
    // Oracle Data Submission & Automatic Payout
    // ----------------------------------------------------------------

    /**
     * @notice Submit an oracle reading. If the value triggers any active policy
     *         in the pool, the payout is executed automatically.
     * @param poolId   The pool this reading applies to.
     * @param value    The measured parameter value.
     * @param dataHash Hash of the off-chain data proof.
     */
    function submitReading(
        uint256 poolId,
        int256 value,
        bytes32 dataHash
    ) external onlyOracle(poolId) nonReentrant whenNotPaused {
        InsurancePool storage pool = pools[poolId];
        if (pool.status == PoolStatus.Closed) revert PoolNotActive();

        uint256 readingId = nextReadingId++;
        readings[readingId] = OracleReading({
            poolId: poolId,
            value: value,
            timestamp: block.timestamp,
            oracle: msg.sender,
            dataHash: dataHash
        });

        emit OracleReadingSubmitted(readingId, poolId, value, msg.sender);

        // Check all active policies in this pool
        uint256[] storage policyIds = poolPolicies[poolId];
        for (uint256 i = 0; i < policyIds.length; i++) {
            Policy storage policy = policies[policyIds[i]];
            if (policy.status != PolicyStatus.Active) continue;
            if (block.timestamp > policy.endTime) continue;

            if (_isTriggered(value, policy.triggerValue, policy.triggerOp)) {
                _executePayout(policyIds[i], readingId, pool);
            }
        }
    }

    /**
     * @dev Check whether a value triggers the threshold.
     */
    function _isTriggered(
        int256 value,
        int256 threshold,
        TriggerOperator op
    ) internal pure returns (bool) {
        if (op == TriggerOperator.GreaterThan) return value > threshold;
        if (op == TriggerOperator.LessThan) return value < threshold;
        if (op == TriggerOperator.GreaterOrEqual) return value >= threshold;
        if (op == TriggerOperator.LessOrEqual) return value <= threshold;
        return false;
    }

    /**
     * @dev Execute an automatic payout for a triggered policy.
     */
    function _executePayout(
        uint256 policyId,
        uint256 readingId,
        InsurancePool storage pool
    ) internal {
        Policy storage policy = policies[policyId];
        policy.status = PolicyStatus.Triggered;

        uint256 payout = policy.coverageAmount;

        // Reduce total collateral (already removed from available)
        pool.totalCollateral -= payout;

        // Check if pool is depleted
        if (pool.totalCollateral == 0) {
            pool.status = PoolStatus.Depleted;
        }

        // Transfer payout to policyholder
        IERC20(pool.paymentToken).safeTransfer(policy.policyholder, payout);

        emit PolicyTriggered(policyId, readingId, payout);
    }

    // ----------------------------------------------------------------
    // Policy Expiry
    // ----------------------------------------------------------------

    /**
     * @notice Mark an expired policy and release its collateral back to the pool.
     * @param policyId The policy to expire.
     */
    function expirePolicy(uint256 policyId) external {
        Policy storage policy = policies[policyId];
        if (policy.status != PolicyStatus.Active) revert PolicyNotActive();
        if (block.timestamp <= policy.endTime) revert PolicyNotExpired();

        policy.status = PolicyStatus.Expired;
        InsurancePool storage pool = pools[policy.poolId];

        // Release reserved collateral
        pool.availableCollateral += policy.coverageAmount;

        emit PolicyExpired(policyId);
    }

    /**
     * @notice Cancel a policy early (insurer-initiated, refunds partial premium).
     * @param policyId The policy to cancel.
     */
    function cancelPolicy(uint256 policyId) external {
        Policy storage policy = policies[policyId];
        if (policy.status != PolicyStatus.Active) revert PolicyNotActive();

        InsurancePool storage pool = pools[policy.poolId];
        if (msg.sender != pool.insurer) revert NotInsurer();

        policy.status = PolicyStatus.Cancelled;

        // Release reserved collateral
        pool.availableCollateral += policy.coverageAmount;

        // Pro-rata premium refund based on remaining time
        uint256 totalDuration = policy.endTime - policy.startTime;
        uint256 elapsed = block.timestamp - policy.startTime;
        uint256 refund = 0;
        if (elapsed < totalDuration) {
            refund = (policy.premium * (totalDuration - elapsed)) / totalDuration;
            pool.totalPremiums -= refund;
            IERC20(pool.paymentToken).safeTransfer(policy.policyholder, refund);
        }

        emit PolicyCancelled(policyId, refund);
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    /// @notice Get all policy IDs for a pool.
    function getPoolPolicies(uint256 poolId) external view returns (uint256[] memory) {
        return poolPolicies[poolId];
    }

    /// @notice Get all policy IDs for a holder.
    function getHolderPolicies(address holder) external view returns (uint256[] memory) {
        return holderPolicies[holder];
    }

    /// @notice Check if a value would trigger a specific policy.
    function wouldTrigger(uint256 policyId, int256 value) external view returns (bool) {
        Policy storage policy = policies[policyId];
        return _isTriggered(value, policy.triggerValue, policy.triggerOp);
    }

    // PHASE2: function registerChainlinkKeeper(uint256 poolId, ...) external
    // PHASE2: function linkReinsurancePool(uint256 poolId, uint256 reinsurancePoolId) external
    // PHASE2: function setRiskTranche(uint256 poolId, uint8 tranche, uint256 allocation) external
    // PHASE2: function bridgeOracleData(uint256 poolId, uint256 sourceChainId, bytes calldata proof) external

    // ----------------------------------------------------------------
    // Administrative
    // ----------------------------------------------------------------

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
}
