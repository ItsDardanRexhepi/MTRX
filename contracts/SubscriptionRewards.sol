// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SubscriptionRewards
 * @author OpenMatrix
 * @notice Subscription system with 10% NeoSafe / 90% creator revenue split,
 *         flexible auto-renewal frequencies, 48-hour grace period with single
 *         retry on failed renewal, and cancellation always available.
 * @dev Creators define subscription tiers with arbitrary period lengths supporting
 *      daily, weekly, monthly, quarterly, annual, or custom frequencies.
 *
 *      Revenue split:
 *        - 10% routed to NeoSafe FIRST on every payment
 *        - 90% routed to the creator
 *
 *      Auto-renewal:
 *        - Subscriptions auto-renew if the subscriber has approved sufficient
 *          token allowance. Anyone can trigger renewal (gas incentive).
 *        - On failed renewal (insufficient allowance/balance), a single retry
 *          is permitted within the 48-hour grace period.
 *
 *      Grace period:
 *        - 48 hours after expiry, the subscription remains active.
 *        - After the grace period without successful renewal, the subscription lapses.
 *        - Renewal during grace period continues from the original expiry (no gap).
 *
 *      Cancellation:
 *        - Always available, no lock-in beyond current billing period.
 *        - Subscription remains active until current period expires.
 *        - No refunds for partial periods.
 */
contract SubscriptionRewards is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice NeoSafe multi-sig receiving platform fees.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice NeoSafe revenue share (10% = 1000 bps).
    uint256 public constant PLATFORM_SHARE_BPS = 1_000;

    /// @notice Creator revenue share (90% = 9000 bps).
    uint256 public constant CREATOR_SHARE_BPS = 9_000;

    /// @notice Basis-point denominator.
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Grace period after subscription expiry (48 hours).
    uint256 public constant GRACE_PERIOD = 48 hours;

    /// @notice Common period presets (convenience constants, not enforced).
    uint256 public constant PERIOD_DAILY = 1 days;
    uint256 public constant PERIOD_WEEKLY = 7 days;
    uint256 public constant PERIOD_MONTHLY = 30 days;
    uint256 public constant PERIOD_QUARTERLY = 90 days;
    uint256 public constant PERIOD_ANNUALLY = 365 days;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    /// @notice Renewal frequency hint (informational, actual period is in seconds).
    enum Frequency {
        Daily,
        Weekly,
        Monthly,
        Quarterly,
        Annually,
        Custom
    }

    /**
     * @notice Subscription tier created by a content creator.
     * @param creator       Address of the tier creator / revenue recipient.
     * @param paymentToken  ERC-20 token used for payments.
     * @param price         Price per billing period (in token smallest unit).
     * @param period        Billing period duration in seconds.
     * @param frequency     Informational frequency label.
     * @param name          Human-readable tier name.
     * @param metadataURI   Off-chain metadata URI (IPFS/Arweave).
     * @param active        Whether the tier accepts new subscriptions.
     * @param subscriberCount Current number of active subscribers.
     */
    struct Tier {
        address creator;
        address paymentToken;
        uint256 price;
        uint256 period;
        Frequency frequency;
        string name;
        string metadataURI;
        bool active;
        uint256 subscriberCount;
    }

    /**
     * @notice Individual subscription record.
     * @param tierId        Tier this subscription belongs to.
     * @param subscriber    Address of the subscriber.
     * @param startTime     Timestamp of the most recent period start.
     * @param expiresAt     Timestamp when the current period ends.
     * @param autoRenew     Whether auto-renewal is enabled.
     * @param cancelled     Whether the subscriber has cancelled.
     * @param retryUsed     Whether the single grace-period retry has been used.
     * @param totalPaid     Cumulative amount paid across all periods.
     * @param renewalCount  Number of successful renewals.
     */
    struct Subscription {
        uint256 tierId;
        address subscriber;
        uint256 startTime;
        uint256 expiresAt;
        bool autoRenew;
        bool cancelled;
        bool retryUsed;
        uint256 totalPaid;
        uint256 renewalCount;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Auto-incrementing tier ID counter.
    uint256 public nextTierId;

    /// @notice Auto-incrementing subscription ID counter (starts at 1).
    uint256 public nextSubscriptionId;

    /// @notice Tier ID => Tier data.
    mapping(uint256 => Tier) public tiers;

    /// @notice Subscription ID => Subscription data.
    mapping(uint256 => Subscription) public subscriptions;

    /// @notice subscriber => tierId => active subscription ID (0 = none).
    mapping(address => mapping(uint256 => uint256)) public activeSubscription;

    /// @notice creator => paymentToken => cumulative earnings.
    mapping(address => mapping(address => uint256)) public creatorEarnings;

    /// @notice subscriber => array of all subscription IDs.
    mapping(address => uint256[]) public subscriberHistory;

    /// @notice creator => array of all tier IDs.
    mapping(address => uint256[]) public creatorTiers;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    /// @notice Emitted when a new tier is created.
    event TierCreated(
        uint256 indexed tierId,
        address indexed creator,
        string name,
        uint256 price,
        uint256 period,
        Frequency frequency
    );

    /// @notice Emitted when a tier's price or name is updated.
    event TierUpdated(uint256 indexed tierId, uint256 newPrice, string newName);

    /// @notice Emitted when a tier is deactivated.
    event TierDeactivated(uint256 indexed tierId);

    /// @notice Emitted when a tier is reactivated.
    event TierActivated(uint256 indexed tierId);

    /// @notice Emitted when a new subscription is created.
    event Subscribed(
        uint256 indexed subscriptionId,
        uint256 indexed tierId,
        address indexed subscriber,
        uint256 expiresAt,
        uint256 creatorAmount,
        uint256 platformAmount
    );

    /// @notice Emitted on successful subscription renewal.
    event SubscriptionRenewed(
        uint256 indexed subscriptionId,
        uint256 newExpiresAt,
        uint256 creatorAmount,
        uint256 platformAmount,
        uint256 renewalCount
    );

    /// @notice Emitted when a renewal attempt fails.
    event RenewalFailed(
        uint256 indexed subscriptionId,
        address indexed subscriber,
        string reason
    );

    /// @notice Emitted when the single retry is attempted.
    event RenewalRetryAttempted(
        uint256 indexed subscriptionId,
        bool success
    );

    /// @notice Emitted when a subscription is cancelled.
    event SubscriptionCancelled(
        uint256 indexed subscriptionId,
        address indexed subscriber,
        uint256 activeUntil
    );

    /// @notice Emitted when auto-renew preference changes.
    event AutoRenewToggled(uint256 indexed subscriptionId, bool autoRenew);

    /// @notice Emitted when a subscription lapses after grace period.
    event SubscriptionLapsed(
        uint256 indexed subscriptionId,
        address indexed subscriber,
        uint256 lapsedAt
    );

    /// @notice Emitted when a subscription enters the grace period.
    event GracePeriodEntered(
        uint256 indexed subscriptionId,
        uint256 graceEndsAt
    );

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error NotCreator();
    error NotSubscriber();
    error TierNotActive();
    error AlreadySubscribed();
    error NotSubscribed();
    error SubscriptionNotExpired();
    error SubscriptionLapsed_();
    error RetryAlreadyUsed();
    error InsufficientAllowance();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidPeriod();
    error SubscriptionCancelled_();

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    /// @notice Restricts to the creator of a specific tier.
    modifier onlyTierCreator(uint256 tierId) {
        if (msg.sender != tiers[tierId].creator) revert NotCreator();
        _;
    }

    /// @notice Restricts to the subscriber of a specific subscription.
    modifier onlySubscriber(uint256 subscriptionId) {
        if (msg.sender != subscriptions[subscriptionId].subscriber)
            revert NotSubscriber();
        _;
    }

    /// @notice Ensures a tier is active.
    modifier tierIsActive(uint256 tierId) {
        if (!tiers[tierId].active) revert TierNotActive();
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /// @notice Deploys the SubscriptionRewards contract.
    constructor() Ownable(msg.sender) {}

    // ----------------------------------------------------------------
    // Tier Management
    // ----------------------------------------------------------------

    /**
     * @notice Create a new subscription tier.
     * @param paymentToken ERC-20 token address for payments.
     * @param price        Price per billing period (smallest token unit).
     * @param period       Period duration in seconds (use PERIOD_* constants or custom).
     * @param frequency    Informational frequency label.
     * @param name         Human-readable tier name.
     * @param metadataURI  Off-chain metadata URI.
     * @return tierId      The newly created tier ID.
     */
    function createTier(
        address paymentToken,
        uint256 price,
        uint256 period,
        Frequency frequency,
        string calldata name,
        string calldata metadataURI
    ) external whenNotPaused returns (uint256 tierId) {
        if (paymentToken == address(0)) revert ZeroAddress();
        if (price == 0) revert ZeroAmount();
        if (period == 0) revert InvalidPeriod();

        tierId = nextTierId++;

        tiers[tierId] = Tier({
            creator: msg.sender,
            paymentToken: paymentToken,
            price: price,
            period: period,
            frequency: frequency,
            name: name,
            metadataURI: metadataURI,
            active: true,
            subscriberCount: 0
        });

        creatorTiers[msg.sender].push(tierId);

        emit TierCreated(tierId, msg.sender, name, price, period, frequency);
    }

    /**
     * @notice Update tier price and name (only affects future renewals/subscriptions).
     * @param tierId   Tier to update.
     * @param newPrice New price per period.
     * @param newName  New tier name.
     */
    function updateTier(
        uint256 tierId,
        uint256 newPrice,
        string calldata newName
    ) external onlyTierCreator(tierId) {
        if (newPrice == 0) revert ZeroAmount();

        tiers[tierId].price = newPrice;
        tiers[tierId].name = newName;
        emit TierUpdated(tierId, newPrice, newName);
    }

    /// @notice Deactivate a tier (prevents new subscriptions; existing ones continue).
    function deactivateTier(uint256 tierId) external onlyTierCreator(tierId) {
        tiers[tierId].active = false;
        emit TierDeactivated(tierId);
    }

    /// @notice Reactivate a deactivated tier.
    function activateTier(uint256 tierId) external onlyTierCreator(tierId) {
        tiers[tierId].active = true;
        emit TierActivated(tierId);
    }

    // ----------------------------------------------------------------
    // Subscription Lifecycle
    // ----------------------------------------------------------------

    /**
     * @notice Subscribe to a tier. Payment is processed immediately with
     *         10% to NeoSafe first, then 90% to creator.
     * @param tierId    Tier to subscribe to.
     * @param autoRenew Whether to enable auto-renewal.
     * @return subscriptionId The new subscription ID.
     */
    function subscribe(uint256 tierId, bool autoRenew)
        external
        nonReentrant
        whenNotPaused
        tierIsActive(tierId)
        returns (uint256 subscriptionId)
    {
        // Prevent duplicate active subscriptions to same tier
        uint256 existingId = activeSubscription[msg.sender][tierId];
        if (existingId != 0) {
            Subscription storage existing = subscriptions[existingId];
            if (
                !existing.cancelled &&
                block.timestamp < existing.expiresAt + GRACE_PERIOD
            ) {
                revert AlreadySubscribed();
            }
        }

        subscriptionId = ++nextSubscriptionId;

        Tier storage t = tiers[tierId];
        uint256 expiresAt = block.timestamp + t.period;

        subscriptions[subscriptionId] = Subscription({
            tierId: tierId,
            subscriber: msg.sender,
            startTime: block.timestamp,
            expiresAt: expiresAt,
            autoRenew: autoRenew,
            cancelled: false,
            retryUsed: false,
            totalPaid: t.price,
            renewalCount: 0
        });

        activeSubscription[msg.sender][tierId] = subscriptionId;
        t.subscriberCount++;
        subscriberHistory[msg.sender].push(subscriptionId);

        // Process payment: 10% to NeoSafe FIRST, 90% to creator
        (uint256 platformAmount, uint256 creatorAmount) = _splitPayment(t.price);
        IERC20(t.paymentToken).safeTransferFrom(msg.sender, NEOSAFE, platformAmount);
        IERC20(t.paymentToken).safeTransferFrom(msg.sender, t.creator, creatorAmount);

        creatorEarnings[t.creator][t.paymentToken] += creatorAmount;

        emit Subscribed(
            subscriptionId,
            tierId,
            msg.sender,
            expiresAt,
            creatorAmount,
            platformAmount
        );
    }

    /**
     * @notice Renew a subscription. Can be called by anyone to trigger
     *         auto-renewal (gas incentive for keepers/bots).
     * @dev Renewal during the grace period continues from the original expiry
     *      to prevent billing gaps. If renewal fails, a single retry is allowed.
     * @param subscriptionId The subscription to renew.
     */
    function renew(uint256 subscriptionId) external nonReentrant whenNotPaused {
        Subscription storage sub = subscriptions[subscriptionId];
        Tier storage t = tiers[sub.tierId];

        if (sub.cancelled) revert SubscriptionCancelled_();
        if (!t.active) revert TierNotActive();
        if (block.timestamp < sub.expiresAt) revert SubscriptionNotExpired();

        // Check grace period
        if (block.timestamp > sub.expiresAt + GRACE_PERIOD) {
            sub.cancelled = true;
            if (t.subscriberCount > 0) t.subscriberCount--;
            emit SubscriptionLapsed(subscriptionId, sub.subscriber, block.timestamp);
            revert SubscriptionLapsed_();
        }

        // Emit grace period event if we just entered it
        if (block.timestamp >= sub.expiresAt && block.timestamp <= sub.expiresAt + GRACE_PERIOD) {
            emit GracePeriodEntered(subscriptionId, sub.expiresAt + GRACE_PERIOD);
        }

        // Attempt payment: 10% to NeoSafe FIRST, then 90% to creator
        (uint256 platformAmount, uint256 creatorAmount) = _splitPayment(t.price);

        bool success = _tryTransferFrom(
            t.paymentToken,
            sub.subscriber,
            NEOSAFE,
            platformAmount
        );

        if (success) {
            success = _tryTransferFrom(
                t.paymentToken,
                sub.subscriber,
                t.creator,
                creatorAmount
            );
        }

        if (!success) {
            emit RenewalFailed(subscriptionId, sub.subscriber, "INSUFFICIENT_FUNDS_OR_ALLOWANCE");
            revert InsufficientAllowance();
        }

        // Renew from the expiry time (not current time) to prevent gaps
        sub.expiresAt = sub.expiresAt + t.period;
        sub.startTime = block.timestamp;
        sub.renewalCount++;
        sub.totalPaid += t.price;
        sub.retryUsed = false; // Reset retry for the new period

        creatorEarnings[t.creator][t.paymentToken] += creatorAmount;

        emit SubscriptionRenewed(
            subscriptionId,
            sub.expiresAt,
            creatorAmount,
            platformAmount,
            sub.renewalCount
        );
    }

    /**
     * @notice Single retry attempt for a failed renewal within the grace period.
     * @dev Each billing period allows exactly one retry. The retry is only
     *      available during the 48-hour grace period.
     * @param subscriptionId The subscription to retry renewal for.
     */
    function retryRenewal(uint256 subscriptionId) external nonReentrant whenNotPaused {
        Subscription storage sub = subscriptions[subscriptionId];
        Tier storage t = tiers[sub.tierId];

        if (sub.cancelled) revert SubscriptionCancelled_();
        if (!t.active) revert TierNotActive();
        if (sub.retryUsed) revert RetryAlreadyUsed();
        if (block.timestamp < sub.expiresAt) revert SubscriptionNotExpired();
        if (block.timestamp > sub.expiresAt + GRACE_PERIOD) {
            revert SubscriptionLapsed_();
        }

        sub.retryUsed = true;

        // Attempt payment: 10% to NeoSafe FIRST
        (uint256 platformAmount, uint256 creatorAmount) = _splitPayment(t.price);

        bool success = _tryTransferFrom(
            t.paymentToken,
            sub.subscriber,
            NEOSAFE,
            platformAmount
        );

        if (success) {
            success = _tryTransferFrom(
                t.paymentToken,
                sub.subscriber,
                t.creator,
                creatorAmount
            );
        }

        if (success) {
            sub.expiresAt = sub.expiresAt + t.period;
            sub.startTime = block.timestamp;
            sub.renewalCount++;
            sub.totalPaid += t.price;
            sub.retryUsed = false;

            creatorEarnings[t.creator][t.paymentToken] += creatorAmount;

            emit RenewalRetryAttempted(subscriptionId, true);
            emit SubscriptionRenewed(
                subscriptionId,
                sub.expiresAt,
                creatorAmount,
                platformAmount,
                sub.renewalCount
            );
        } else {
            emit RenewalRetryAttempted(subscriptionId, false);
            emit RenewalFailed(
                subscriptionId,
                sub.subscriber,
                "RETRY_FAILED_INSUFFICIENT_FUNDS_OR_ALLOWANCE"
            );
        }
    }

    /**
     * @notice Cancel a subscription. Always available, no lock-in.
     * @dev Subscription remains active until the current period expires.
     *      No refunds for partial periods. Auto-renew is disabled.
     * @param subscriptionId The subscription to cancel.
     */
    function cancelSubscription(uint256 subscriptionId)
        external
        onlySubscriber(subscriptionId)
    {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.cancelled) revert SubscriptionCancelled_();

        sub.cancelled = true;
        sub.autoRenew = false;

        Tier storage t = tiers[sub.tierId];
        if (t.subscriberCount > 0) t.subscriberCount--;

        emit SubscriptionCancelled(subscriptionId, msg.sender, sub.expiresAt);
    }

    /**
     * @notice Toggle auto-renewal for a subscription.
     * @param subscriptionId The subscription to modify.
     * @param autoRenew      New auto-renew preference.
     */
    function setAutoRenew(uint256 subscriptionId, bool autoRenew)
        external
        onlySubscriber(subscriptionId)
    {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.cancelled) revert SubscriptionCancelled_();

        sub.autoRenew = autoRenew;
        emit AutoRenewToggled(subscriptionId, autoRenew);
    }

    // ----------------------------------------------------------------
    // Internal
    // ----------------------------------------------------------------

    /**
     * @notice Calculate the platform/creator split.
     * @dev 10% to NeoSafe (platform), 90% to creator.
     * @param totalPrice The total price to split.
     * @return platformAmount Amount for NeoSafe.
     * @return creatorAmount  Amount for the creator.
     */
    function _splitPayment(uint256 totalPrice)
        internal
        pure
        returns (uint256 platformAmount, uint256 creatorAmount)
    {
        platformAmount = (totalPrice * PLATFORM_SHARE_BPS) / BPS_DENOMINATOR;
        creatorAmount = totalPrice - platformAmount;
    }

    /**
     * @notice Attempt a transferFrom, returning false on failure instead of reverting.
     * @param token  ERC-20 token address.
     * @param from   Source address.
     * @param to     Destination address.
     * @param amount Amount to transfer.
     * @return success Whether the transfer succeeded.
     */
    function _tryTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal returns (bool success) {
        try IERC20(token).transferFrom(from, to, amount) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    /**
     * @notice Check if a subscription is currently active (including grace period).
     * @param subscriptionId The subscription to check.
     * @return Whether the subscription is active.
     */
    function isActive(uint256 subscriptionId) external view returns (bool) {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.cancelled) return false;
        return block.timestamp < sub.expiresAt + GRACE_PERIOD;
    }

    /**
     * @notice Check if a subscription is in the 48-hour grace period.
     * @param subscriptionId The subscription to check.
     * @return Whether it is currently in the grace period.
     */
    function isInGracePeriod(uint256 subscriptionId) external view returns (bool) {
        Subscription storage sub = subscriptions[subscriptionId];
        if (sub.cancelled) return false;
        return
            block.timestamp >= sub.expiresAt &&
            block.timestamp < sub.expiresAt + GRACE_PERIOD;
    }

    /**
     * @notice Get time remaining until expiry (0 if expired).
     * @param subscriptionId The subscription to check.
     * @return Seconds remaining until expiry.
     */
    function timeRemaining(uint256 subscriptionId) external view returns (uint256) {
        Subscription storage sub = subscriptions[subscriptionId];
        if (block.timestamp >= sub.expiresAt) return 0;
        return sub.expiresAt - block.timestamp;
    }

    /// @notice Get full tier data.
    function getTier(uint256 tierId) external view returns (Tier memory) {
        return tiers[tierId];
    }

    /// @notice Get full subscription data.
    function getSubscription(uint256 subscriptionId) external view returns (Subscription memory) {
        return subscriptions[subscriptionId];
    }

    /// @notice Get all subscription IDs for a subscriber.
    function getSubscriberHistory(address subscriber) external view returns (uint256[] memory) {
        return subscriberHistory[subscriber];
    }

    /// @notice Get all tier IDs for a creator.
    function getCreatorTiers(address creator) external view returns (uint256[] memory) {
        return creatorTiers[creator];
    }

    /// @notice Check if the single retry has been used for the current period.
    function isRetryAvailable(uint256 subscriptionId) external view returns (bool) {
        Subscription storage sub = subscriptions[subscriptionId];
        return !sub.retryUsed && !sub.cancelled;
    }

    // ----------------------------------------------------------------
    // Administrative
    // ----------------------------------------------------------------

    /// @notice Pause all subscription operations (owner only).
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause subscription operations (owner only).
    function unpause() external onlyOwner {
        _unpause();
    }
}
