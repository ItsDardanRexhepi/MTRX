// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SecurityToken
 * @notice ERC-3643 compliant tokenized securities for the MTRX platform.
 * @dev Implements identity-based transfer restrictions following the ERC-3643
 *      (T-REX) standard pattern. Only verified investors whose identity has
 *      been attested through an Identity Registry may hold or transfer tokens.
 *
 *      Key constraints:
 *        - Transfers are restricted to verified (KYC/AML) investors.
 *        - Compliance checks are enforced at the contract level.
 *        - The issuer can freeze wallets, pause the token, or force transfers
 *          to comply with legal/regulatory requirements.
 *        - Country-based restrictions are supported.
 *        - Deploys on Base L2.
 *
 *      All administrative actions emit events for full on-chain auditability.
 */
contract SecurityToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ReentrancyGuard {
    // ----------------------------------------------------------------
    // Constants
    // ----------------------------------------------------------------

    /// @notice The NeoSafe multi-sig receiving administrative fees.
    address public constant NEOSAFE =
        0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    // ----------------------------------------------------------------
    // State - Identity Registry
    // ----------------------------------------------------------------

    /// @notice External identity registry contract (ERC-3643 ONCHAINID pattern).
    address public identityRegistry;

    /// @notice Mapping of wallet address to verified status.
    mapping(address => bool) public isVerifiedInvestor;

    /// @notice Mapping of wallet address to investor country code (ISO 3166-1 numeric).
    mapping(address => uint16) public investorCountry;

    /// @notice Set of country codes that are restricted from holding tokens.
    mapping(uint16 => bool) public restrictedCountry;

    /// @notice Mapping of wallet address to frozen status.
    mapping(address => bool) public frozenWallet;

    /// @notice Compliance agent addresses authorised to manage investor verification.
    mapping(address => bool) public isComplianceAgent;

    // ----------------------------------------------------------------
    // State - Token metadata
    // ----------------------------------------------------------------

    /// @notice ISIN or other security identifier.
    string public securityIdentifier;

    /// @notice Legal jurisdiction of the security issuance.
    string public jurisdiction;

    /// @notice Maximum number of token holders allowed (0 = unlimited).
    uint256 public maxHolders;

    /// @notice Current number of unique token holders.
    uint256 public holderCount;

    /// @notice Tracks whether an address currently holds a non-zero balance.
    mapping(address => bool) private _isHolder;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event InvestorVerified(address indexed investor, uint16 countryCode);
    event InvestorRemoved(address indexed investor);
    event WalletFrozen(address indexed wallet);
    event WalletUnfrozen(address indexed wallet);
    event CountryRestricted(uint16 indexed countryCode);
    event CountryUnrestricted(uint16 indexed countryCode);
    event ComplianceAgentAdded(address indexed agent);
    event ComplianceAgentRemoved(address indexed agent);
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);
    event IdentityRegistryUpdated(address indexed newRegistry);
    event TokensRecovered(address indexed token, uint256 amount);
    event MaxHoldersUpdated(uint256 newMax);
    event SecurityIdentifierUpdated(string identifier);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error NotVerified(address account);
    error WalletIsFrozen(address account);
    error CountryIsRestricted(uint16 countryCode);
    error MaxHoldersReached(uint256 max);
    error NotComplianceAgent(address caller);
    error ZeroAddress();
    error InvalidAmount();

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    /// @dev Restricts function access to the owner or a compliance agent.
    modifier onlyComplianceAgent() {
        if (!isComplianceAgent[msg.sender] && msg.sender != owner()) {
            revert NotComplianceAgent(msg.sender);
        }
        _;
    }

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @param name_     Token name (e.g. "MTRX Security A").
     * @param symbol_   Token symbol (e.g. "MTRX-SA").
     * @param identityRegistry_ Address of the identity registry contract.
     * @param jurisdiction_     Legal jurisdiction string.
     * @param securityId_       ISIN or equivalent identifier.
     * @param maxHolders_       Maximum holder cap (0 = unlimited).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address identityRegistry_,
        string memory jurisdiction_,
        string memory securityId_,
        uint256 maxHolders_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        if (identityRegistry_ == address(0)) revert ZeroAddress();

        identityRegistry = identityRegistry_;
        jurisdiction = jurisdiction_;
        securityIdentifier = securityId_;
        maxHolders = maxHolders_;
    }

    // ----------------------------------------------------------------
    // ERC-3643 Transfer Compliance
    // ----------------------------------------------------------------

    /**
     * @notice Checks whether a transfer between two addresses is compliant.
     * @param from  Sender address (address(0) for minting).
     * @param to    Receiver address (address(0) for burning).
     * @return True if the transfer passes all compliance checks.
     */
    function canTransfer(address from, address to) public view returns (bool) {
        // Minting: only receiver needs verification
        if (from != address(0)) {
            if (!isVerifiedInvestor[from]) return false;
            if (frozenWallet[from]) return false;
            if (restrictedCountry[investorCountry[from]]) return false;
        }

        // Burning: no receiver check needed
        if (to != address(0)) {
            if (!isVerifiedInvestor[to]) return false;
            if (frozenWallet[to]) return false;
            if (restrictedCountry[investorCountry[to]]) return false;

            // Max holder check
            if (maxHolders > 0 && !_isHolder[to] && balanceOf(to) == 0) {
                if (holderCount >= maxHolders) return false;
            }
        }

        return true;
    }

    /**
     * @dev Internal override that enforces compliance and tracks holder count on every transfer (OZ v5).
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        // Compliance checks before the transfer
        if (from == address(0) && msg.sender == owner()) {
            // Minting: ensure receiver is verified
            if (to != address(0)) {
                if (!isVerifiedInvestor[to]) revert NotVerified(to);
                if (frozenWallet[to]) revert WalletIsFrozen(to);
                if (restrictedCountry[investorCountry[to]]) {
                    revert CountryIsRestricted(investorCountry[to]);
                }
            }
        } else if (to == address(0)) {
            // Burning: sender must not be frozen
            if (frozenWallet[from]) revert WalletIsFrozen(from);
        } else {
            // Standard transfer: full compliance
            if (!isVerifiedInvestor[from]) revert NotVerified(from);
            if (!isVerifiedInvestor[to]) revert NotVerified(to);
            if (frozenWallet[from]) revert WalletIsFrozen(from);
            if (frozenWallet[to]) revert WalletIsFrozen(to);
            if (restrictedCountry[investorCountry[from]]) {
                revert CountryIsRestricted(investorCountry[from]);
            }
            if (restrictedCountry[investorCountry[to]]) {
                revert CountryIsRestricted(investorCountry[to]);
            }
        }

        // Perform the actual transfer (includes pausable check)
        super._update(from, to, value);

        // Track new holders
        if (to != address(0) && !_isHolder[to] && balanceOf(to) > 0) {
            if (maxHolders > 0 && holderCount >= maxHolders) {
                revert MaxHoldersReached(maxHolders);
            }
            _isHolder[to] = true;
            holderCount++;
        }

        // Remove holders with zero balance
        if (from != address(0) && _isHolder[from] && balanceOf(from) == 0) {
            _isHolder[from] = false;
            holderCount--;
        }
    }

    // ----------------------------------------------------------------
    // Issuance
    // ----------------------------------------------------------------

    /**
     * @notice Mint new security tokens to a verified investor.
     * @param to     Recipient address (must be verified).
     * @param amount Number of tokens to mint (18 decimals).
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        _mint(to, amount);
    }

    // ----------------------------------------------------------------
    // Compliance Agent Management
    // ----------------------------------------------------------------

    /**
     * @notice Add a compliance agent.
     * @param agent Address to grant compliance agent role.
     */
    function addComplianceAgent(address agent) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();
        isComplianceAgent[agent] = true;
        emit ComplianceAgentAdded(agent);
    }

    /**
     * @notice Remove a compliance agent.
     * @param agent Address to revoke compliance agent role.
     */
    function removeComplianceAgent(address agent) external onlyOwner {
        isComplianceAgent[agent] = false;
        emit ComplianceAgentRemoved(agent);
    }

    // ----------------------------------------------------------------
    // Investor Verification (Identity Registry)
    // ----------------------------------------------------------------

    /**
     * @notice Register a verified investor.
     * @param investor    The investor wallet address.
     * @param countryCode ISO 3166-1 numeric country code.
     */
    function verifyInvestor(address investor, uint16 countryCode)
        external
        onlyComplianceAgent
    {
        if (investor == address(0)) revert ZeroAddress();
        isVerifiedInvestor[investor] = true;
        investorCountry[investor] = countryCode;
        emit InvestorVerified(investor, countryCode);
    }

    /**
     * @notice Remove an investor's verified status.
     * @param investor The investor wallet address.
     */
    function removeInvestor(address investor) external onlyComplianceAgent {
        isVerifiedInvestor[investor] = false;
        investorCountry[investor] = 0;
        emit InvestorRemoved(investor);
    }

    /**
     * @notice Batch verify multiple investors.
     * @param investors    Array of investor addresses.
     * @param countryCodes Array of corresponding country codes.
     */
    function batchVerifyInvestors(
        address[] calldata investors,
        uint16[] calldata countryCodes
    ) external onlyComplianceAgent {
        require(investors.length == countryCodes.length, "Length mismatch");
        for (uint256 i = 0; i < investors.length; i++) {
            if (investors[i] == address(0)) revert ZeroAddress();
            isVerifiedInvestor[investors[i]] = true;
            investorCountry[investors[i]] = countryCodes[i];
            emit InvestorVerified(investors[i], countryCodes[i]);
        }
    }

    // ----------------------------------------------------------------
    // Wallet Freezing
    // ----------------------------------------------------------------

    /// @notice Freeze a wallet, preventing all transfers.
    function freezeWallet(address wallet) external onlyComplianceAgent {
        if (wallet == address(0)) revert ZeroAddress();
        frozenWallet[wallet] = true;
        emit WalletFrozen(wallet);
    }

    /// @notice Unfreeze a wallet.
    function unfreezeWallet(address wallet) external onlyComplianceAgent {
        frozenWallet[wallet] = false;
        emit WalletUnfrozen(wallet);
    }

    // ----------------------------------------------------------------
    // Country Restrictions
    // ----------------------------------------------------------------

    /// @notice Restrict a country from holding tokens.
    function restrictCountry(uint16 countryCode) external onlyOwner {
        restrictedCountry[countryCode] = true;
        emit CountryRestricted(countryCode);
    }

    /// @notice Remove a country restriction.
    function unrestrictCountry(uint16 countryCode) external onlyOwner {
        restrictedCountry[countryCode] = false;
        emit CountryUnrestricted(countryCode);
    }

    // ----------------------------------------------------------------
    // Forced Transfer (Regulatory Compliance)
    // ----------------------------------------------------------------

    /**
     * @notice Force a transfer between two wallets for regulatory compliance.
     * @dev Bypasses frozen-wallet checks but requires both parties to be verified.
     * @param from   Source wallet.
     * @param to     Destination wallet (must be verified).
     * @param amount Token amount to transfer.
     * @param reason Human-readable reason for the forced transfer.
     */
    function forceTransfer(
        address from,
        address to,
        uint256 amount,
        string calldata reason
    ) external onlyOwner {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (!isVerifiedInvestor[to]) revert NotVerified(to);

        // Temporarily unfreeze for transfer
        bool wasFrozenFrom = frozenWallet[from];
        bool wasFrozenTo = frozenWallet[to];
        frozenWallet[from] = false;
        frozenWallet[to] = false;

        _transfer(from, to, amount);

        // Restore freeze state
        frozenWallet[from] = wasFrozenFrom;
        frozenWallet[to] = wasFrozenTo;

        emit ForcedTransfer(from, to, amount, reason);
    }

    // ----------------------------------------------------------------
    // Pause
    // ----------------------------------------------------------------

    /// @notice Pause all token transfers.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause all token transfers.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ----------------------------------------------------------------
    // Administrative
    // ----------------------------------------------------------------

    /// @notice Update the identity registry contract address.
    function setIdentityRegistry(address newRegistry) external onlyOwner {
        if (newRegistry == address(0)) revert ZeroAddress();
        identityRegistry = newRegistry;
        emit IdentityRegistryUpdated(newRegistry);
    }

    /// @notice Update the maximum holder cap.
    function setMaxHolders(uint256 newMax) external onlyOwner {
        maxHolders = newMax;
        emit MaxHoldersUpdated(newMax);
    }

    /// @notice Update the security identifier.
    function setSecurityIdentifier(string calldata id) external onlyOwner {
        securityIdentifier = id;
        emit SecurityIdentifierUpdated(id);
    }

    /**
     * @notice Recover ERC-20 tokens accidentally sent to this contract.
     * @param token  The ERC-20 token address.
     * @param amount Amount to recover.
     */
    function recoverTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(NEOSAFE, amount);
        emit TokensRecovered(token, amount);
    }
}
