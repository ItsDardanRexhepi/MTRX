// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title StablecoinTransfer
 * @notice Component 7 - Stablecoin Infrastructure
 * @dev Handles USDC transfers on Base mainnet with tiered fee structure
 *      based on wallet LIFETIME balance history.
 *
 * Fee schedule (based on wallet lifetime balance history):
 *   Lifetime wallet under $5,000: ALL transfers ALWAYS free permanently
 *   Under $1,000 transfer:        Free, max 2 per 48-hour rolling window
 *   $1,000 - $25,000:             0.5% flat
 *   $25,000 - $250,000:           2.5% flat
 *   >$250,000:                    5.0% flat
 *
 * All fees route to NeoSafe.
 *
 * On-chain qualification record for free tier is IMMUTABLE and NOT subject
 * to Component 29 deletion rights.
 */
contract StablecoinTransfer is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice The NeoSafe multi-sig that receives all transfer fees.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice USDC on Base mainnet.
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    /// @notice Basis-point denominator.
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Lifetime balance threshold for permanent free transfers (6 decimals for USDC).
    uint256 public constant FREE_TIER_LIFETIME_MAX = 5_000e6;    // $5,000

    /// @notice Transfer amount threshold for free transfers with rate limiting.
    uint256 public constant FREE_TRANSFER_MAX = 1_000e6;         // $1,000

    /// @notice Fee tier boundaries (USDC 6 decimals).
    uint256 public constant TIER1_CEILING = 25_000e6;            // $25,000
    uint256 public constant TIER2_CEILING = 250_000e6;           // $250,000

    /// @notice Fee rates in basis points.
    uint256 public constant TIER1_FEE_BPS = 50;     // 0.5%
    uint256 public constant TIER2_FEE_BPS = 250;    // 2.5%
    uint256 public constant TIER3_FEE_BPS = 500;    // 5.0%

    /// @notice Rate-limiting constants for free transfers.
    uint256 public constant FREE_TRANSFER_WINDOW = 48 hours;
    uint256 public constant FREE_TRANSFER_LIMIT = 2;

    // ----------------------------------------------------------------
    // Structs
    // ----------------------------------------------------------------

    struct WalletRecord {
        uint256 lifetimeBalance;          // Peak/cumulative lifetime balance
        uint256 totalTransferred;         // Total amount transferred through platform
        bool qualifiesForFreeTier;        // IMMUTABLE once set true - NOT deletable
        uint256 qualifiedAt;              // Timestamp of free-tier qualification
        uint256[] freeTransferTimestamps; // Rolling window timestamps
    }

    struct TransferRecord {
        address sender;
        address recipient;
        uint256 amount;
        uint256 fee;
        uint256 timestamp;
        bool wasFree;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Rexhepi gate address authorised to call gated functions.
    address public rexhepiGate;

    /// @notice Per-wallet lifetime records.
    mapping(address => WalletRecord) public walletRecords;

    /// @notice Transfer history per wallet.
    mapping(address => TransferRecord[]) private _transferHistory;

    /// @notice Total fees routed to NeoSafe.
    uint256 public totalRoutedToNeoSafe;

    /// @notice Total transfers processed.
    uint256 public totalTransfers;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event TransferExecuted(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 fee,
        bool wasFree,
        uint256 timestamp
    );

    event FeeRouted(
        address indexed sender,
        uint256 feeAmount,
        uint256 timestamp
    );

    event FreeTierQualified(
        address indexed wallet,
        uint256 lifetimeBalance,
        uint256 timestamp
    );

    event LifetimeBalanceUpdated(
        address indexed wallet,
        uint256 previousBalance,
        uint256 newBalance,
        uint256 timestamp
    );

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyThroughRexhepiGate() {
        require(
            msg.sender == rexhepiGate,
            "StablecoinTransfer: caller is not the Rexhepi gate"
        );
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @param _rexhepiGate The address authorised to call gated functions.
     */
    constructor(address _rexhepiGate) Ownable(msg.sender) {
        require(
            _rexhepiGate != address(0),
            "StablecoinTransfer: gate cannot be zero address"
        );
        rexhepiGate = _rexhepiGate;
    }

    // ----------------------------------------------------------------
    // External Functions - Transfers
    // ----------------------------------------------------------------

    /**
     * @notice Execute a USDC transfer with automatic fee calculation.
     * @dev Caller must have approved this contract for amount + fee.
     * @param _sender    The address sending USDC.
     * @param _recipient The address receiving USDC.
     * @param _amount    The transfer amount in USDC (6 decimals).
     */
    function executeTransfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external onlyThroughRexhepiGate nonReentrant {
        require(_sender != address(0), "StablecoinTransfer: sender is zero");
        require(_recipient != address(0), "StablecoinTransfer: recipient is zero");
        require(_amount > 0, "StablecoinTransfer: amount must be > 0");

        // Update lifetime balance tracking
        _updateLifetimeBalance(_sender, _amount);

        // Calculate fee
        (uint256 fee, bool isFree) = calculateFee(_sender, _amount);

        // If free transfer, validate rate limit
        if (isFree && !walletRecords[_sender].qualifiesForFreeTier) {
            // Only rate-limit if not permanently free-tier qualified
            require(
                _checkAndUpdateRateLimit(_sender),
                "StablecoinTransfer: free transfer rate limit exceeded"
            );
        }

        uint256 totalRequired = _amount + fee;

        // Transfer USDC from sender to recipient
        IERC20(USDC).safeTransferFrom(_sender, _recipient, _amount);

        // Route fee to NeoSafe if applicable
        if (fee > 0) {
            IERC20(USDC).safeTransferFrom(_sender, NEOSAFE, fee);
            totalRoutedToNeoSafe += fee;

            emit FeeRouted(_sender, fee, block.timestamp);
        }

        // Record transfer
        totalTransfers++;
        _transferHistory[_sender].push(TransferRecord({
            sender: _sender,
            recipient: _recipient,
            amount: _amount,
            fee: fee,
            timestamp: block.timestamp,
            wasFree: isFree
        }));

        emit TransferExecuted(
            _sender,
            _recipient,
            _amount,
            fee,
            isFree,
            block.timestamp
        );
    }

    /**
     * @notice Record a wallet's balance for lifetime tracking.
     * @dev Called by the platform to update peak/lifetime balances.
     * @param _wallet  The wallet address.
     * @param _balance The current balance to record.
     */
    function recordBalance(
        address _wallet,
        uint256 _balance
    ) external onlyThroughRexhepiGate {
        require(_wallet != address(0), "StablecoinTransfer: wallet is zero");

        WalletRecord storage record = walletRecords[_wallet];
        uint256 previous = record.lifetimeBalance;

        // Track peak lifetime balance
        if (_balance > record.lifetimeBalance) {
            record.lifetimeBalance = _balance;

            emit LifetimeBalanceUpdated(
                _wallet,
                previous,
                _balance,
                block.timestamp
            );
        }

        // Check and set immutable free-tier qualification
        if (!record.qualifiesForFreeTier && record.lifetimeBalance <= FREE_TIER_LIFETIME_MAX) {
            record.qualifiesForFreeTier = true;
            record.qualifiedAt = block.timestamp;

            emit FreeTierQualified(
                _wallet,
                record.lifetimeBalance,
                block.timestamp
            );
        }
    }

    // ----------------------------------------------------------------
    // View Functions
    // ----------------------------------------------------------------

    /**
     * @notice Calculate the fee for a transfer.
     * @param _sender The sender wallet (for tier determination).
     * @param _amount The transfer amount in USDC.
     * @return fee    The fee amount in USDC.
     * @return isFree Whether this transfer qualifies as free.
     */
    function calculateFee(
        address _sender,
        uint256 _amount
    ) public view returns (uint256 fee, bool isFree) {
        WalletRecord storage record = walletRecords[_sender];

        // Permanent free tier: lifetime wallet under $5,000
        if (record.qualifiesForFreeTier) {
            return (0, true);
        }

        // Free for transfers under $1,000 (subject to rate limit)
        if (_amount < FREE_TRANSFER_MAX) {
            uint256 activeCount = _countActiveTransfers(_sender);
            if (activeCount < FREE_TRANSFER_LIMIT) {
                return (0, true);
            }
        }

        // Tiered fees based on transfer amount
        uint256 bps;
        if (_amount < TIER1_CEILING) {
            bps = TIER1_FEE_BPS;     // 0.5%
        } else if (_amount < TIER2_CEILING) {
            bps = TIER2_FEE_BPS;     // 2.5%
        } else {
            bps = TIER3_FEE_BPS;     // 5.0%
        }

        fee = (_amount * bps) / BPS_DENOMINATOR;
        isFree = false;
    }

    /**
     * @notice Check how many free transfers remain in the current 48-hour window.
     * @param _wallet The wallet to check.
     * @return remaining Number of free transfers remaining.
     */
    function freeTransfersRemaining(
        address _wallet
    ) external view returns (uint256 remaining) {
        if (walletRecords[_wallet].qualifiesForFreeTier) {
            return type(uint256).max; // Unlimited for permanently free wallets
        }

        uint256 active = _countActiveTransfers(_wallet);
        if (active >= FREE_TRANSFER_LIMIT) {
            return 0;
        }
        remaining = FREE_TRANSFER_LIMIT - active;
    }

    /**
     * @notice Get the transfer history for a wallet.
     * @param _wallet The wallet to query.
     * @return records Array of transfer records.
     */
    function getTransferHistory(
        address _wallet
    ) external view returns (TransferRecord[] memory records) {
        records = _transferHistory[_wallet];
    }

    /**
     * @notice Check if a wallet qualifies for the permanent free tier.
     * @param _wallet The wallet to check.
     * @return qualified Whether the wallet is permanently free.
     */
    function isFreeTierQualified(
        address _wallet
    ) external view returns (bool qualified) {
        qualified = walletRecords[_wallet].qualifiesForFreeTier;
    }

    // ----------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------

    /**
     * @notice Update the Rexhepi gate address. Owner-only.
     * @param _newGate The new gate address.
     */
    function setRexhepiGate(address _newGate) external onlyOwner {
        require(
            _newGate != address(0),
            "StablecoinTransfer: gate cannot be zero address"
        );
        rexhepiGate = _newGate;
    }

    // ----------------------------------------------------------------
    // Internal Functions
    // ----------------------------------------------------------------

    /**
     * @dev Update the lifetime balance tracking for a wallet.
     */
    function _updateLifetimeBalance(
        address _wallet,
        uint256 _transferAmount
    ) internal {
        WalletRecord storage record = walletRecords[_wallet];
        record.totalTransferred += _transferAmount;

        // Update lifetime balance if current total exceeds previous peak
        if (record.totalTransferred > record.lifetimeBalance) {
            uint256 previous = record.lifetimeBalance;
            record.lifetimeBalance = record.totalTransferred;

            emit LifetimeBalanceUpdated(
                _wallet,
                previous,
                record.totalTransferred,
                block.timestamp
            );
        }
    }

    /**
     * @dev Count the number of free transfers in the current 48-hour window.
     */
    function _countActiveTransfers(
        address _wallet
    ) internal view returns (uint256 count) {
        WalletRecord storage record = walletRecords[_wallet];
        uint256 cutoff = block.timestamp - FREE_TRANSFER_WINDOW;

        for (uint256 i = 0; i < record.freeTransferTimestamps.length; i++) {
            if (record.freeTransferTimestamps[i] >= cutoff) {
                count++;
            }
        }
    }

    /**
     * @dev Check rate limit and record a new free transfer timestamp.
     * @return allowed Whether the free transfer is allowed.
     */
    function _checkAndUpdateRateLimit(
        address _wallet
    ) internal returns (bool allowed) {
        uint256 active = _countActiveTransfers(_wallet);
        if (active >= FREE_TRANSFER_LIMIT) {
            return false;
        }

        walletRecords[_wallet].freeTransferTimestamps.push(block.timestamp);
        return true;
    }

    // ----------------------------------------------------------------
    // Receive / Fallback
    // ----------------------------------------------------------------

    receive() external payable {}
    fallback() external payable {}
}
