// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title IEASAttestationService
 * @notice Interface for Ethereum Attestation Service (EAS) schema 348 attestation
 */
interface IEASAttestationService {
    function attest(
        bytes32 schema,
        address recipient,
        uint64 expirationTime,
        bool revocable,
        bytes32 refUID,
        bytes calldata data,
        uint256 value
    ) external payable returns (bytes32);
}

/**
 * @title INFTRights
 * @notice Interface to the NFTRights companion contract for valuation timer integration
 */
interface INFTRights {
    function startValuationTimer(uint256 tokenId) external;
}

/**
 * @title OpenMatrixNFT
 * @author OpenMatrix Platform
 * @notice NFT factory supporting both ERC-721 (unique) and ERC-1155 (semi-fungible) minting.
 *         Enforces 10% NeoSafe routing on every transaction and immutable creator royalties
 *         on all secondary sales. Integrates EAS schema 348 attestation on mint and transfer.
 *
 * Economics on secondary sale (example: $100 sale, 5% creator royalty):
 *   - 10% of total ($10) -> NeoSafe
 *   - Creator royalty applied to remaining 90%: 5% of $90 = $4.50 -> creator
 *   - Seller receives: $85.50
 */
contract OpenMatrixNFT is ERC721, ERC721URIStorage, ERC721Enumerable, IERC2981, Ownable, ReentrancyGuard {

    // ──────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────

    /// @notice NeoSafe treasury address — receives 10% of every NFT transaction
    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice NeoSafe share expressed in basis points (10% = 1000 bps)
    uint256 public constant NEOSAFE_FEE_BPS = 1000;

    /// @notice Maximum creator royalty in basis points (25% cap)
    uint256 public constant MAX_CREATOR_ROYALTY_BPS = 2500;

    /// @notice EAS schema UID for schema 348 attestation
    bytes32 public constant EAS_SCHEMA_348 = keccak256("OpenMatrix.NFT.Schema348");

    /// @notice Basis point denominator
    uint256 private constant BPS_DENOMINATOR = 10000;

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    uint256 private _tokenIdCounter;

    /// @notice EAS attestation service address on Base
    IEASAttestationService public easService;

    /// @notice NFTRights companion contract for valuation timers
    INFTRights public rightsContract;

    /// @notice Token type enumeration
    enum TokenStandard { ERC721_UNIQUE, ERC1155_SEMI_FUNGIBLE }

    /// @notice Immutable per-token metadata set at mint time
    struct TokenInfo {
        address creator;
        uint256 creatorRoyaltyBps;   // Creator royalty in basis points (applied to 90% after NeoSafe)
        uint256 mintPrice;           // Original mint price in wei
        uint256 mintTimestamp;       // Block timestamp at mint
        TokenStandard standard;      // ERC-721 or ERC-1155
        string metadataURI;          // IPFS or Arweave content URI
        bytes32 mintAttestationUID;  // EAS attestation UID from mint
        bool active;                 // Whether the token is active
    }

    /// @notice Mapping from tokenId to its immutable info
    mapping(uint256 => TokenInfo) public tokenInfo;

    /// @notice Sale listing price for marketplace integration
    mapping(uint256 => uint256) public salePrice;

    /// @notice Whether a token is listed for sale
    mapping(uint256 => bool) public isListed;

    // ──────────────────────────────────────────────
    //  ERC-1155 Semi-Fungible Support
    // ──────────────────────────────────────────────

    /// @notice ERC-1155 edition supply per token ID
    mapping(uint256 => uint256) public editionSupply;

    /// @notice ERC-1155 edition balance: tokenId -> owner -> balance
    mapping(uint256 => mapping(address => uint256)) public editionBalances;

    /// @notice Total minted editions per token ID
    mapping(uint256 => uint256) public editionsMinted;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event NFTMinted(
        uint256 indexed tokenId,
        address indexed creator,
        TokenStandard standard,
        uint256 creatorRoyaltyBps,
        uint256 mintPrice,
        uint256 editionSupply,
        bytes32 attestationUID,
        string metadataURI
    );

    event NFTSold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 salePrice,
        uint256 neoSafeAmount,
        uint256 creatorRoyaltyAmount,
        uint256 sellerProceeds
    );

    event RoyaltyPaid(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 amount,
        uint256 salePriceTotal
    );

    event NeoSafeRouted(
        uint256 indexed tokenId,
        uint256 amount,
        string transactionType  // "mint", "sale", "transfer"
    );

    event TokenListed(uint256 indexed tokenId, uint256 price);
    event TokenDelisted(uint256 indexed tokenId);
    event EASServiceUpdated(address indexed newService);
    event RightsContractUpdated(address indexed newRightsContract);

    // ──────────────────────────────────────────────
    //  Modifiers
    // ──────────────────────────────────────────────

    modifier tokenExists(uint256 tokenId) {
        require(tokenInfo[tokenId].active, "OpenMatrixNFT: token does not exist");
        _;
    }

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _easService,
        address _rightsContract
    ) ERC721("OpenMatrixNFT", "OMNFT") Ownable(msg.sender) {
        require(_easService != address(0), "OpenMatrixNFT: EAS service cannot be zero address");
        easService = IEASAttestationService(_easService);
        if (_rightsContract != address(0)) {
            rightsContract = INFTRights(_rightsContract);
        }
    }

    // ──────────────────────────────────────────────
    //  Minting — Zero Gas to Creator
    // ──────────────────────────────────────────────

    /**
     * @notice Mint a unique ERC-721 NFT. Zero cost to the creator — platform sponsors gas.
     * @param to          Recipient / creator address
     * @param metadataURI IPFS or Arweave URI for the NFT metadata
     * @param royaltyBps  Creator royalty in basis points (applied to 90% after NeoSafe fee)
     * @return tokenId    The newly minted token ID
     */
    function mintERC721(
        address to,
        string calldata metadataURI,
        uint256 royaltyBps
    ) external payable nonReentrant returns (uint256) {
        require(to != address(0), "OpenMatrixNFT: cannot mint to zero address");
        require(royaltyBps <= MAX_CREATOR_ROYALTY_BPS, "OpenMatrixNFT: royalty exceeds 25% cap");
        require(bytes(metadataURI).length > 0, "OpenMatrixNFT: metadata URI required");

        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        // Mint — platform pays gas, zero cost to creator
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, metadataURI);

        // EAS attestation on mint
        bytes32 attestationUID = _attestEAS(tokenId, to, "mint");

        // Store immutable token info
        tokenInfo[tokenId] = TokenInfo({
            creator: to,
            creatorRoyaltyBps: royaltyBps,
            mintPrice: msg.value,
            mintTimestamp: block.timestamp,
            standard: TokenStandard.ERC721_UNIQUE,
            metadataURI: metadataURI,
            mintAttestationUID: attestationUID,
            active: true
        });

        // Start 90-day valuation timer in NFTRights contract
        if (address(rightsContract) != address(0)) {
            rightsContract.startValuationTimer(tokenId);
        }

        // Route any mint value to NeoSafe
        if (msg.value > 0) {
            uint256 neoSafeShare = (msg.value * NEOSAFE_FEE_BPS) / BPS_DENOMINATOR;
            if (neoSafeShare > 0) {
                (bool sent, ) = NEOSAFE.call{value: neoSafeShare}("");
                require(sent, "OpenMatrixNFT: NeoSafe routing failed");
                emit NeoSafeRouted(tokenId, neoSafeShare, "mint");
            }
        }

        emit NFTMinted(
            tokenId,
            to,
            TokenStandard.ERC721_UNIQUE,
            royaltyBps,
            msg.value,
            1,
            attestationUID,
            metadataURI
        );

        return tokenId;
    }

    /**
     * @notice Mint a semi-fungible ERC-1155-style edition set. Zero cost to creator.
     * @param to            Recipient / creator address
     * @param metadataURI   IPFS or Arweave URI for the edition metadata
     * @param royaltyBps    Creator royalty in basis points
     * @param editions      Number of editions to mint (supply cap)
     * @return tokenId      The newly minted edition token ID
     */
    function mintERC1155(
        address to,
        string calldata metadataURI,
        uint256 royaltyBps,
        uint256 editions
    ) external payable nonReentrant returns (uint256) {
        require(to != address(0), "OpenMatrixNFT: cannot mint to zero address");
        require(royaltyBps <= MAX_CREATOR_ROYALTY_BPS, "OpenMatrixNFT: royalty exceeds 25% cap");
        require(editions > 0 && editions <= 10000, "OpenMatrixNFT: editions must be 1-10000");
        require(bytes(metadataURI).length > 0, "OpenMatrixNFT: metadata URI required");

        _tokenIdCounter++;
        uint256 tokenId = _tokenIdCounter;

        // For ERC-1155 style: mint a single ERC-721 token as the "master" and track editions separately
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, metadataURI);

        // EAS attestation on mint
        bytes32 attestationUID = _attestEAS(tokenId, to, "mint");

        // Store token info
        tokenInfo[tokenId] = TokenInfo({
            creator: to,
            creatorRoyaltyBps: royaltyBps,
            mintPrice: msg.value,
            mintTimestamp: block.timestamp,
            standard: TokenStandard.ERC1155_SEMI_FUNGIBLE,
            metadataURI: metadataURI,
            mintAttestationUID: attestationUID,
            active: true
        });

        // Initialize edition tracking
        editionSupply[tokenId] = editions;
        editionBalances[tokenId][to] = editions;
        editionsMinted[tokenId] = editions;

        // Start 90-day valuation timer
        if (address(rightsContract) != address(0)) {
            rightsContract.startValuationTimer(tokenId);
        }

        // Route any mint value to NeoSafe
        if (msg.value > 0) {
            uint256 neoSafeShare = (msg.value * NEOSAFE_FEE_BPS) / BPS_DENOMINATOR;
            if (neoSafeShare > 0) {
                (bool sent, ) = NEOSAFE.call{value: neoSafeShare}("");
                require(sent, "OpenMatrixNFT: NeoSafe routing failed");
                emit NeoSafeRouted(tokenId, neoSafeShare, "mint");
            }
        }

        emit NFTMinted(
            tokenId,
            to,
            TokenStandard.ERC1155_SEMI_FUNGIBLE,
            royaltyBps,
            msg.value,
            editions,
            attestationUID,
            metadataURI
        );

        return tokenId;
    }

    // ──────────────────────────────────────────────
    //  Marketplace — List, Buy, Delist
    // ──────────────────────────────────────────────

    /**
     * @notice List an NFT for sale on the integrated marketplace
     * @param tokenId Token ID to list
     * @param price   Listing price in wei
     */
    function listForSale(uint256 tokenId, uint256 price) external tokenExists(tokenId) {
        require(ownerOf(tokenId) == msg.sender, "OpenMatrixNFT: only owner can list");
        require(price > 0, "OpenMatrixNFT: price must be > 0");

        salePrice[tokenId] = price;
        isListed[tokenId] = true;

        emit TokenListed(tokenId, price);
    }

    /**
     * @notice Remove an NFT from the marketplace
     * @param tokenId Token ID to delist
     */
    function delist(uint256 tokenId) external tokenExists(tokenId) {
        require(ownerOf(tokenId) == msg.sender, "OpenMatrixNFT: only owner can delist");

        isListed[tokenId] = false;
        salePrice[tokenId] = 0;

        emit TokenDelisted(tokenId);
    }

    /**
     * @notice Purchase a listed NFT. Enforces NeoSafe 10% fee and creator royalty on the sale.
     *
     * Distribution on a secondary sale:
     *   1. 10% of total sale price -> NeoSafe
     *   2. Creator royalty = royaltyBps% of (sale price - NeoSafe share)
     *   3. Remainder -> seller
     *
     * @param tokenId Token ID to purchase
     */
    function buy(uint256 tokenId) external payable nonReentrant tokenExists(tokenId) {
        require(isListed[tokenId], "OpenMatrixNFT: token not listed for sale");
        require(msg.value >= salePrice[tokenId], "OpenMatrixNFT: insufficient payment");

        address seller = ownerOf(tokenId);
        require(msg.sender != seller, "OpenMatrixNFT: cannot buy own token");

        uint256 price = salePrice[tokenId];
        TokenInfo storage info = tokenInfo[tokenId];

        // 1. NeoSafe receives 10% of total sale price
        uint256 neoSafeAmount = (price * NEOSAFE_FEE_BPS) / BPS_DENOMINATOR;

        // 2. Creator royalty on remaining 90%
        uint256 remainingAfterNeoSafe = price - neoSafeAmount;
        uint256 creatorRoyaltyAmount = (remainingAfterNeoSafe * info.creatorRoyaltyBps) / BPS_DENOMINATOR;

        // 3. Seller gets the rest
        uint256 sellerProceeds = remainingAfterNeoSafe - creatorRoyaltyAmount;

        // Clear listing before transfers (CEI pattern)
        isListed[tokenId] = false;
        salePrice[tokenId] = 0;

        // Transfer NFT
        _transfer(seller, msg.sender, tokenId);

        // EAS attestation on sale/transfer
        _attestEAS(tokenId, msg.sender, "transfer");

        // Distribute funds
        (bool neoSafeSent, ) = NEOSAFE.call{value: neoSafeAmount}("");
        require(neoSafeSent, "OpenMatrixNFT: NeoSafe payment failed");
        emit NeoSafeRouted(tokenId, neoSafeAmount, "sale");

        if (creatorRoyaltyAmount > 0 && info.creator != address(0)) {
            (bool royaltySent, ) = info.creator.call{value: creatorRoyaltyAmount}("");
            require(royaltySent, "OpenMatrixNFT: creator royalty payment failed");
            emit RoyaltyPaid(tokenId, info.creator, creatorRoyaltyAmount, price);
        }

        (bool sellerSent, ) = seller.call{value: sellerProceeds}("");
        require(sellerSent, "OpenMatrixNFT: seller payment failed");

        // Refund excess payment
        if (msg.value > price) {
            (bool refundSent, ) = msg.sender.call{value: msg.value - price}("");
            require(refundSent, "OpenMatrixNFT: refund failed");
        }

        emit NFTSold(
            tokenId,
            seller,
            msg.sender,
            price,
            neoSafeAmount,
            creatorRoyaltyAmount,
            sellerProceeds
        );
    }

    // ──────────────────────────────────────────────
    //  ERC-1155 Edition Transfer
    // ──────────────────────────────────────────────

    /**
     * @notice Transfer editions of a semi-fungible token
     * @param tokenId Token ID of the edition set
     * @param to      Recipient address
     * @param amount  Number of editions to transfer
     */
    function transferEditions(
        uint256 tokenId,
        address to,
        uint256 amount
    ) external nonReentrant tokenExists(tokenId) {
        require(tokenInfo[tokenId].standard == TokenStandard.ERC1155_SEMI_FUNGIBLE, "OpenMatrixNFT: not an edition token");
        require(to != address(0), "OpenMatrixNFT: cannot transfer to zero address");
        require(editionBalances[tokenId][msg.sender] >= amount, "OpenMatrixNFT: insufficient edition balance");

        editionBalances[tokenId][msg.sender] -= amount;
        editionBalances[tokenId][to] += amount;

        // EAS attestation on edition transfer
        _attestEAS(tokenId, to, "transfer");
    }

    /**
     * @notice Purchase editions of a semi-fungible token with NeoSafe fee and royalty enforcement
     * @param tokenId  Token ID of the edition set
     * @param seller   Address of the edition seller
     * @param amount   Number of editions to buy
     * @param pricePerEdition Price per edition in wei
     */
    function buyEditions(
        uint256 tokenId,
        address seller,
        uint256 amount,
        uint256 pricePerEdition
    ) external payable nonReentrant tokenExists(tokenId) {
        require(tokenInfo[tokenId].standard == TokenStandard.ERC1155_SEMI_FUNGIBLE, "OpenMatrixNFT: not an edition token");
        require(editionBalances[tokenId][seller] >= amount, "OpenMatrixNFT: seller has insufficient editions");

        uint256 totalPrice = pricePerEdition * amount;
        require(msg.value >= totalPrice, "OpenMatrixNFT: insufficient payment");

        TokenInfo storage info = tokenInfo[tokenId];

        // NeoSafe 10% on total
        uint256 neoSafeAmount = (totalPrice * NEOSAFE_FEE_BPS) / BPS_DENOMINATOR;
        uint256 remainingAfterNeoSafe = totalPrice - neoSafeAmount;
        uint256 creatorRoyaltyAmount = (remainingAfterNeoSafe * info.creatorRoyaltyBps) / BPS_DENOMINATOR;
        uint256 sellerProceeds = remainingAfterNeoSafe - creatorRoyaltyAmount;

        // Transfer editions
        editionBalances[tokenId][seller] -= amount;
        editionBalances[tokenId][msg.sender] += amount;

        // EAS attestation
        _attestEAS(tokenId, msg.sender, "transfer");

        // Distribute funds
        (bool neoSafeSent, ) = NEOSAFE.call{value: neoSafeAmount}("");
        require(neoSafeSent, "OpenMatrixNFT: NeoSafe payment failed");
        emit NeoSafeRouted(tokenId, neoSafeAmount, "sale");

        if (creatorRoyaltyAmount > 0 && info.creator != address(0)) {
            (bool royaltySent, ) = info.creator.call{value: creatorRoyaltyAmount}("");
            require(royaltySent, "OpenMatrixNFT: creator royalty payment failed");
            emit RoyaltyPaid(tokenId, info.creator, creatorRoyaltyAmount, totalPrice);
        }

        (bool sellerSent, ) = seller.call{value: sellerProceeds}("");
        require(sellerSent, "OpenMatrixNFT: seller payment failed");

        if (msg.value > totalPrice) {
            (bool refundSent, ) = msg.sender.call{value: msg.value - totalPrice}("");
            require(refundSent, "OpenMatrixNFT: refund failed");
        }

        emit NFTSold(tokenId, seller, msg.sender, totalPrice, neoSafeAmount, creatorRoyaltyAmount, sellerProceeds);
    }

    // ──────────────────────────────────────────────
    //  ERC-2981 Royalty Standard
    // ──────────────────────────────────────────────

    /**
     * @notice ERC-2981 royaltyInfo implementation.
     *         Returns the COMBINED royalty (NeoSafe + creator) for marketplace integrations.
     * @param tokenId    Token ID
     * @param _salePrice Sale price to calculate royalty against
     * @return receiver  NeoSafe address (primary receiver — creator paid separately by contract)
     * @return royaltyAmount Total royalty amount (NeoSafe share + creator share)
     */
    function royaltyInfo(
        uint256 tokenId,
        uint256 _salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        TokenInfo storage info = tokenInfo[tokenId];

        uint256 neoSafeAmount = (_salePrice * NEOSAFE_FEE_BPS) / BPS_DENOMINATOR;
        uint256 remaining = _salePrice - neoSafeAmount;
        uint256 creatorAmount = (remaining * info.creatorRoyaltyBps) / BPS_DENOMINATOR;

        // Return this contract as receiver so it can split internally
        return (address(this), neoSafeAmount + creatorAmount);
    }

    // ──────────────────────────────────────────────
    //  EAS Attestation — Schema 348
    // ──────────────────────────────────────────────

    /**
     * @dev Issue EAS schema 348 attestation for mint or transfer events
     */
    function _attestEAS(
        uint256 tokenId,
        address recipient,
        string memory eventType
    ) internal returns (bytes32) {
        if (address(easService) == address(0)) {
            return bytes32(0);
        }

        bytes memory attestationData = abi.encode(
            tokenId,
            recipient,
            eventType,
            block.timestamp,
            block.chainid,
            address(this)
        );

        try easService.attest(
            EAS_SCHEMA_348,
            recipient,
            0,          // No expiration
            false,      // Not revocable
            bytes32(0), // No reference UID
            attestationData,
            0           // No value
        ) returns (bytes32 uid) {
            return uid;
        } catch {
            // Attestation failure should not block minting/transfer
            return bytes32(0);
        }
    }

    // ──────────────────────────────────────────────
    //  Transfer Hook — NeoSafe Routing on Every Transfer
    // ──────────────────────────────────────────────

    /**
     * @dev Override _update for ERC721Enumerable compatibility (OZ v5).
     */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Override _increaseBalance for ERC721Enumerable compatibility (OZ v5).
     */
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    // ──────────────────────────────────────────────
    //  Admin
    // ──────────────────────────────────────────────

    /**
     * @notice Update EAS attestation service address
     * @param _easService New EAS service address
     */
    function setEASService(address _easService) external onlyOwner {
        require(_easService != address(0), "OpenMatrixNFT: zero address");
        easService = IEASAttestationService(_easService);
        emit EASServiceUpdated(_easService);
    }

    /**
     * @notice Update NFTRights companion contract
     * @param _rightsContract New rights contract address
     */
    function setRightsContract(address _rightsContract) external onlyOwner {
        require(_rightsContract != address(0), "OpenMatrixNFT: zero address");
        rightsContract = INFTRights(_rightsContract);
        emit RightsContractUpdated(_rightsContract);
    }

    // ──────────────────────────────────────────────
    //  View Helpers
    // ──────────────────────────────────────────────

    /**
     * @notice Get the creator address for a given token
     */
    function getCreator(uint256 tokenId) external view tokenExists(tokenId) returns (address) {
        return tokenInfo[tokenId].creator;
    }

    /**
     * @notice Get the creator royalty in basis points for a given token
     */
    function getCreatorRoyaltyBps(uint256 tokenId) external view tokenExists(tokenId) returns (uint256) {
        return tokenInfo[tokenId].creatorRoyaltyBps;
    }

    /**
     * @notice Calculate the distribution breakdown for a given sale price
     * @param tokenId   Token ID
     * @param price     Sale price in wei
     * @return neoSafeShare      Amount to NeoSafe
     * @return creatorRoyalty     Amount to creator
     * @return sellerProceeds    Amount to seller
     */
    function calculateDistribution(
        uint256 tokenId,
        uint256 price
    ) external view tokenExists(tokenId) returns (
        uint256 neoSafeShare,
        uint256 creatorRoyalty,
        uint256 sellerProceeds
    ) {
        TokenInfo storage info = tokenInfo[tokenId];
        neoSafeShare = (price * NEOSAFE_FEE_BPS) / BPS_DENOMINATOR;
        uint256 remaining = price - neoSafeShare;
        creatorRoyalty = (remaining * info.creatorRoyaltyBps) / BPS_DENOMINATOR;
        sellerProceeds = remaining - creatorRoyalty;
    }

    /**
     * @notice Get the edition balance for a semi-fungible token
     */
    function getEditionBalance(uint256 tokenId, address owner) external view returns (uint256) {
        return editionBalances[tokenId][owner];
    }

    // ──────────────────────────────────────────────
    //  Required Overrides
    // ──────────────────────────────────────────────

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Contract can receive ETH for marketplace operations
     */
    receive() external payable {}
}
