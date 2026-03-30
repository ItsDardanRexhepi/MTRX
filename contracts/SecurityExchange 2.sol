// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SecurityExchange
 * @notice Peer-to-peer exchange for ERC-3643 compliant security tokens on Base.
 * @dev Implements a mutually-agreed-terms order book where both buyer and seller
 *      must explicitly accept the terms before a trade executes.
 *
 *      Fee structure:
 *        - 0.25% of trade value is routed to NeoSafe on every executed trade.
 *        - Fee is deducted from the payment token amount.
 *
 *      Trade lifecycle:
 *        1. Seller creates an order (listing security tokens for a payment token).
 *        2. Buyer agrees to the terms and funds the trade.
 *        3. Seller confirms (mutual agreement).
 *        4. Contract atomically swaps tokens and routes the fee.
 *
 *      Compliance:
 *        - The security token contract itself enforces transfer restrictions
 *          (ERC-3643). This exchange does not duplicate those checks.
 *        - Orders can be cancelled by either party before settlement.
 */
contract SecurityExchange is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice NeoSafe multi-sig receiving the 0.25% trade fee.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Trade fee in basis points (0.25% = 25 bps).
    uint256 public constant TRADE_FEE_BPS = 25;

    /// @notice Basis-point denominator.
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    enum OrderStatus {
        Open,
        BuyerAgreed,
        Settled,
        CancelledBySeller,
        CancelledByBuyer,
        Expired
    }

    struct Order {
        address seller;
        address buyer;               // address(0) until a buyer agrees
        address securityToken;        // ERC-3643 token being sold
        address paymentToken;         // ERC-20 token used for payment
        uint256 securityAmount;       // Amount of security tokens
        uint256 paymentAmount;        // Total payment (before fee)
        uint256 expiration;           // Unix timestamp; 0 = no expiry
        OrderStatus status;
        string terms;                 // Human-readable terms hash/URI
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Auto-incrementing order ID counter.
    uint256 public nextOrderId;

    /// @notice All orders by ID.
    mapping(uint256 => Order) public orders;

    /// @notice Compliance filter contract (optional, address(0) = disabled).
    address public complianceFilter;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event OrderCreated(
        uint256 indexed orderId,
        address indexed seller,
        address securityToken,
        address paymentToken,
        uint256 securityAmount,
        uint256 paymentAmount,
        uint256 expiration,
        string terms
    );
    event BuyerAgreed(uint256 indexed orderId, address indexed buyer);
    event OrderSettled(
        uint256 indexed orderId,
        address indexed seller,
        address indexed buyer,
        uint256 feeAmount
    );
    event OrderCancelled(uint256 indexed orderId, address indexed cancelledBy);
    event OrderExpired(uint256 indexed orderId);
    event ComplianceFilterUpdated(address indexed newFilter);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error InvalidOrder();
    error NotSeller();
    error NotBuyer();
    error OrderNotOpen();
    error OrderNotAgreed();
    error OrderAlreadyExpired();
    error BuyerAlreadySet();
    error ZeroAddress();
    error ZeroAmount();
    error ComplianceCheckFailed();

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor() {}

    // ----------------------------------------------------------------
    // Order Lifecycle
    // ----------------------------------------------------------------

    /**
     * @notice Create a sell order for security tokens.
     * @param securityToken  Address of the ERC-3643 security token.
     * @param paymentToken   Address of the ERC-20 payment token.
     * @param securityAmount Amount of security tokens to sell.
     * @param paymentAmount  Requested payment amount (before fee).
     * @param expiration     Unix timestamp for order expiry (0 = no expiry).
     * @param terms          URI or hash of the mutually-agreed terms document.
     * @return orderId       The ID of the newly created order.
     */
    function createOrder(
        address securityToken,
        address paymentToken,
        uint256 securityAmount,
        uint256 paymentAmount,
        uint256 expiration,
        string calldata terms
    ) external whenNotPaused returns (uint256 orderId) {
        if (securityToken == address(0) || paymentToken == address(0)) revert ZeroAddress();
        if (securityAmount == 0 || paymentAmount == 0) revert ZeroAmount();
        if (expiration != 0 && expiration <= block.timestamp) revert OrderAlreadyExpired();

        orderId = nextOrderId++;

        orders[orderId] = Order({
            seller: msg.sender,
            buyer: address(0),
            securityToken: securityToken,
            paymentToken: paymentToken,
            securityAmount: securityAmount,
            paymentAmount: paymentAmount,
            expiration: expiration,
            status: OrderStatus.Open,
            terms: terms
        });

        // Seller escrows security tokens into the contract
        IERC20(securityToken).safeTransferFrom(msg.sender, address(this), securityAmount);

        emit OrderCreated(
            orderId, msg.sender, securityToken, paymentToken,
            securityAmount, paymentAmount, expiration, terms
        );
    }

    /**
     * @notice Buyer agrees to the order terms and escrows payment tokens.
     * @param orderId The order to agree to.
     */
    function agreeToOrder(uint256 orderId) external whenNotPaused nonReentrant {
        Order storage order = orders[orderId];
        if (order.status != OrderStatus.Open) revert OrderNotOpen();
        if (order.expiration != 0 && block.timestamp >= order.expiration) {
            order.status = OrderStatus.Expired;
            emit OrderExpired(orderId);
            revert OrderAlreadyExpired();
        }
        if (order.buyer != address(0)) revert BuyerAlreadySet();

        // Compute total payment including fee
        uint256 fee = (order.paymentAmount * TRADE_FEE_BPS) / BPS_DENOMINATOR;
        uint256 totalPayment = order.paymentAmount + fee;

        order.buyer = msg.sender;
        order.status = OrderStatus.BuyerAgreed;

        // Buyer escrows payment tokens (amount + fee)
        IERC20(order.paymentToken).safeTransferFrom(msg.sender, address(this), totalPayment);

        emit BuyerAgreed(orderId, msg.sender);
    }

    /**
     * @notice Seller confirms the trade after buyer has agreed (mutual agreement).
     * @dev Atomically settles the trade: security tokens to buyer, payment to seller, fee to NeoSafe.
     * @param orderId The order to settle.
     */
    function settleOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        if (order.status != OrderStatus.BuyerAgreed) revert OrderNotAgreed();
        if (msg.sender != order.seller) revert NotSeller();
        if (order.expiration != 0 && block.timestamp >= order.expiration) {
            order.status = OrderStatus.Expired;
            emit OrderExpired(orderId);
            revert OrderAlreadyExpired();
        }

        uint256 fee = (order.paymentAmount * TRADE_FEE_BPS) / BPS_DENOMINATOR;

        order.status = OrderStatus.Settled;

        // Transfer security tokens to buyer
        IERC20(order.securityToken).safeTransfer(order.buyer, order.securityAmount);

        // Transfer payment to seller
        IERC20(order.paymentToken).safeTransfer(order.seller, order.paymentAmount);

        // Route fee to NeoSafe
        IERC20(order.paymentToken).safeTransfer(NEOSAFE, fee);

        emit OrderSettled(orderId, order.seller, order.buyer, fee);
    }

    /**
     * @notice Cancel an order. Seller can cancel when Open or BuyerAgreed.
     *         Buyer can cancel only when BuyerAgreed.
     * @param orderId The order to cancel.
     */
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];

        if (msg.sender == order.seller) {
            if (order.status == OrderStatus.Open) {
                order.status = OrderStatus.CancelledBySeller;
                // Return escrowed security tokens
                IERC20(order.securityToken).safeTransfer(order.seller, order.securityAmount);
            } else if (order.status == OrderStatus.BuyerAgreed) {
                order.status = OrderStatus.CancelledBySeller;
                uint256 fee = (order.paymentAmount * TRADE_FEE_BPS) / BPS_DENOMINATOR;
                // Return escrowed tokens to both parties
                IERC20(order.securityToken).safeTransfer(order.seller, order.securityAmount);
                IERC20(order.paymentToken).safeTransfer(order.buyer, order.paymentAmount + fee);
            } else {
                revert OrderNotOpen();
            }
        } else if (msg.sender == order.buyer) {
            if (order.status != OrderStatus.BuyerAgreed) revert OrderNotAgreed();
            order.status = OrderStatus.CancelledByBuyer;
            uint256 fee = (order.paymentAmount * TRADE_FEE_BPS) / BPS_DENOMINATOR;
            // Return payment to buyer, security tokens stay with contract for seller
            IERC20(order.paymentToken).safeTransfer(order.buyer, order.paymentAmount + fee);
            // Return security tokens to seller
            IERC20(order.securityToken).safeTransfer(order.seller, order.securityAmount);
        } else {
            revert InvalidOrder();
        }

        emit OrderCancelled(orderId, msg.sender);
    }

    /**
     * @notice Claim back tokens from an expired order.
     * @param orderId The expired order.
     */
    function claimExpired(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        if (order.expiration == 0 || block.timestamp < order.expiration) revert OrderAlreadyExpired();
        if (order.status == OrderStatus.Settled ||
            order.status == OrderStatus.CancelledBySeller ||
            order.status == OrderStatus.CancelledByBuyer ||
            order.status == OrderStatus.Expired) revert InvalidOrder();

        OrderStatus previousStatus = order.status;
        order.status = OrderStatus.Expired;

        // Return security tokens to seller
        IERC20(order.securityToken).safeTransfer(order.seller, order.securityAmount);

        // If buyer had agreed, return payment tokens
        if (previousStatus == OrderStatus.BuyerAgreed && order.buyer != address(0)) {
            uint256 fee = (order.paymentAmount * TRADE_FEE_BPS) / BPS_DENOMINATOR;
            IERC20(order.paymentToken).safeTransfer(order.buyer, order.paymentAmount + fee);
        }

        emit OrderExpired(orderId);
    }

    // ----------------------------------------------------------------
    // Administrative
    // ----------------------------------------------------------------

    /// @notice Update the optional compliance filter contract.
    function setComplianceFilter(address filter) external onlyOwner {
        complianceFilter = filter;
        emit ComplianceFilterUpdated(filter);
    }

    /// @notice Pause the exchange.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the exchange.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------

    /**
     * @notice Calculate the fee for a given payment amount.
     * @param paymentAmount The payment amount before fee.
     * @return fee The 0.25% fee amount.
     */
    function calculateFee(uint256 paymentAmount) external pure returns (uint256 fee) {
        fee = (paymentAmount * TRADE_FEE_BPS) / BPS_DENOMINATOR;
    }

    /**
     * @notice Get full order details.
     * @param orderId The order ID.
     * @return The Order struct.
     */
    function getOrder(uint256 orderId) external view returns (Order memory) {
        return orders[orderId];
    }
}
