// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title Marketplace
 * @author MTRX Protocol
 * @notice NFT/game asset marketplace on Base. 5% to NeoSafe, 95% to seller.
 * @dev Supports ERC-721 and ERC-1155. Compliance filter integration point
 *      for restricted assets. EAS attestation hooks for verified listings.
 */
contract Marketplace is Ownable, ReentrancyGuard, Pausable, ERC1155Holder, ERC721Holder {

    /// @notice NeoSafe treasury on Base
    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Platform fee (5% = 500 BPS)
    uint256 public constant PLATFORM_FEE_BPS = 500;

    /// @notice BPS denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    // -----------------------------------------------------------------------
    // Enums & Structs
    // -----------------------------------------------------------------------

    enum AssetStandard { ERC721, ERC1155 }
    enum ListingStatus { Active, Sold, Cancelled }

    struct Listing {
        uint256 listingId;
        address seller;
        address assetContract;
        uint256 tokenId;
        uint256 amount;
        uint256 pricePerUnit;
        AssetStandard standard;
        ListingStatus status;
        bytes32 easAttestation;
        uint256 createdAt;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    mapping(uint256 => Listing) public listings;
    uint256 public nextListingId;

    /// @notice Compliance filter contract (optional)
    address public complianceFilter;

    /// @notice EAS registry address (optional)
    address public easRegistry;

    /// @notice Blocked asset contracts
    mapping(address => bool) public blockedContracts;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event Listed(uint256 indexed listingId, address indexed seller, address indexed assetContract, uint256 tokenId, uint256 amount, uint256 pricePerUnit, AssetStandard standard);
    event Purchased(uint256 indexed listingId, address indexed buyer, uint256 totalPrice, uint256 platformFee, uint256 sellerProceeds);
    event ListingCancelled(uint256 indexed listingId, address indexed seller);
    event ComplianceFilterUpdated(address indexed newFilter);
    event EASRegistryUpdated(address indexed newRegistry);
    event ContractBlocked(address indexed assetContract);
    event ContractUnblocked(address indexed assetContract);
    event EASAttestationAttached(uint256 indexed listingId, bytes32 attestationUID);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier onlySeller(uint256 _listingId) {
        require(msg.sender == listings[_listingId].seller, "Marketplace: not seller");
        _;
    }

    modifier listingActive(uint256 _listingId) {
        require(listings[_listingId].status == ListingStatus.Active, "Marketplace: not active");
        _;
    }

    modifier compliant(address _assetContract) {
        require(!blockedContracts[_assetContract], "Marketplace: asset blocked");
        if (complianceFilter != address(0)) {
            (bool ok, bytes memory data) = complianceFilter.staticcall(
                abi.encodeWithSignature("isCompliant(address)", _assetContract)
            );
            if (ok && data.length >= 32) {
                require(abi.decode(data, (bool)), "Marketplace: compliance check failed");
            }
        }
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor() Ownable(msg.sender) {}

    // -----------------------------------------------------------------------
    // Listing
    // -----------------------------------------------------------------------

    /**
     * @notice List an ERC-721 token for sale.
     * @param _assetContract NFT contract address.
     * @param _tokenId Token ID.
     * @param _price Sale price in wei.
     * @return listingId Created listing ID.
     */
    function listERC721(address _assetContract, uint256 _tokenId, uint256 _price)
        external
        whenNotPaused
        compliant(_assetContract)
        returns (uint256 listingId)
    {
        require(_price > 0, "Marketplace: zero price");
        IERC721(_assetContract).transferFrom(msg.sender, address(this), _tokenId);

        listingId = nextListingId++;
        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            assetContract: _assetContract,
            tokenId: _tokenId,
            amount: 1,
            pricePerUnit: _price,
            standard: AssetStandard.ERC721,
            status: ListingStatus.Active,
            easAttestation: bytes32(0),
            createdAt: block.timestamp
        });

        emit Listed(listingId, msg.sender, _assetContract, _tokenId, 1, _price, AssetStandard.ERC721);
    }

    /**
     * @notice List ERC-1155 tokens for sale.
     * @param _assetContract Asset contract address.
     * @param _tokenId Token ID.
     * @param _amount Number of tokens.
     * @param _pricePerUnit Price per token in wei.
     * @return listingId Created listing ID.
     */
    function listERC1155(address _assetContract, uint256 _tokenId, uint256 _amount, uint256 _pricePerUnit)
        external
        whenNotPaused
        compliant(_assetContract)
        returns (uint256 listingId)
    {
        require(_amount > 0 && _pricePerUnit > 0, "Marketplace: zero amount or price");
        IERC1155(_assetContract).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "");

        listingId = nextListingId++;
        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            assetContract: _assetContract,
            tokenId: _tokenId,
            amount: _amount,
            pricePerUnit: _pricePerUnit,
            standard: AssetStandard.ERC1155,
            status: ListingStatus.Active,
            easAttestation: bytes32(0),
            createdAt: block.timestamp
        });

        emit Listed(listingId, msg.sender, _assetContract, _tokenId, _amount, _pricePerUnit, AssetStandard.ERC1155);
    }

    // -----------------------------------------------------------------------
    // Purchase
    // -----------------------------------------------------------------------

    /**
     * @notice Purchase a listed item. 5% to NeoSafe, 95% to seller.
     * @param _listingId Listing ID to purchase.
     */
    function purchase(uint256 _listingId)
        external
        payable
        listingActive(_listingId)
        nonReentrant
        whenNotPaused
    {
        Listing storage listing = listings[_listingId];
        uint256 totalPrice = listing.pricePerUnit * listing.amount;
        require(msg.value >= totalPrice, "Marketplace: insufficient payment");

        listing.status = ListingStatus.Sold;

        uint256 fee = (totalPrice * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 sellerProceeds = totalPrice - fee;

        if (listing.standard == AssetStandard.ERC721) {
            IERC721(listing.assetContract).transferFrom(address(this), msg.sender, listing.tokenId);
        } else {
            IERC1155(listing.assetContract).safeTransferFrom(address(this), msg.sender, listing.tokenId, listing.amount, "");
        }

        (bool s1, ) = listing.seller.call{value: sellerProceeds}("");
        require(s1, "Marketplace: seller payment failed");

        (bool s2, ) = NEOSAFE.call{value: fee}("");
        require(s2, "Marketplace: fee payment failed");

        if (msg.value > totalPrice) {
            (bool s3, ) = msg.sender.call{value: msg.value - totalPrice}("");
            require(s3, "Marketplace: refund failed");
        }

        emit Purchased(_listingId, msg.sender, totalPrice, fee, sellerProceeds);
    }

    // -----------------------------------------------------------------------
    // Cancellation
    // -----------------------------------------------------------------------

    /**
     * @notice Cancel an active listing and return assets to seller.
     * @param _listingId Listing ID.
     */
    function cancelListing(uint256 _listingId)
        external
        onlySeller(_listingId)
        listingActive(_listingId)
        nonReentrant
    {
        Listing storage listing = listings[_listingId];
        listing.status = ListingStatus.Cancelled;

        if (listing.standard == AssetStandard.ERC721) {
            IERC721(listing.assetContract).transferFrom(address(this), listing.seller, listing.tokenId);
        } else {
            IERC1155(listing.assetContract).safeTransferFrom(address(this), listing.seller, listing.tokenId, listing.amount, "");
        }

        emit ListingCancelled(_listingId, listing.seller);
    }

    // -----------------------------------------------------------------------
    // EAS Attestation Hooks
    // -----------------------------------------------------------------------

    /**
     * @notice Attach an EAS attestation to a listing.
     * @param _listingId Listing ID.
     * @param _attestationUID EAS attestation UID.
     */
    function attachAttestation(uint256 _listingId, bytes32 _attestationUID)
        external
        onlySeller(_listingId)
        listingActive(_listingId)
    {
        listings[_listingId].easAttestation = _attestationUID;
        emit EASAttestationAttached(_listingId, _attestationUID);
    }

    /**
     * @notice Check attestation status for a listing.
     * @param _listingId Listing ID.
     * @return hasAttestation Whether an attestation is attached.
     * @return attestationUID The attestation UID.
     */
    function getAttestation(uint256 _listingId)
        external
        view
        returns (bool hasAttestation, bytes32 attestationUID)
    {
        attestationUID = listings[_listingId].easAttestation;
        hasAttestation = attestationUID != bytes32(0);
    }

    // -----------------------------------------------------------------------
    // Admin
    // -----------------------------------------------------------------------

    /// @notice Set compliance filter contract (0 to disable).
    function setComplianceFilter(address _filter) external onlyOwner {
        complianceFilter = _filter;
        emit ComplianceFilterUpdated(_filter);
    }

    /// @notice Set EAS registry contract.
    function setEASRegistry(address _registry) external onlyOwner {
        easRegistry = _registry;
        emit EASRegistryUpdated(_registry);
    }

    /// @notice Block an asset contract from listing.
    function blockContract(address _contract) external onlyOwner {
        blockedContracts[_contract] = true;
        emit ContractBlocked(_contract);
    }

    /// @notice Unblock an asset contract.
    function unblockContract(address _contract) external onlyOwner {
        blockedContracts[_contract] = false;
        emit ContractUnblocked(_contract);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // -----------------------------------------------------------------------
    // View
    // -----------------------------------------------------------------------

    /// @notice Get listing details.
    function getListing(uint256 _listingId) external view returns (Listing memory) {
        return listings[_listingId];
    }
}
