// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title GameAsset
 * @author MTRX Protocol
 * @notice ERC-1155 game assets on Base. Players fully own their assets and
 *         can trade, sell, or transfer them freely. Supports play-to-earn.
 * @dev Uses AccessControl for role-based minting (game servers, P2E systems).
 *      Players always retain full custody of their tokens.
 */
contract GameAsset is ERC1155, ERC1155Burnable, ERC1155Supply, AccessControl, ReentrancyGuard {
    // -----------------------------------------------------------------------
    // Constants & Roles
    // -----------------------------------------------------------------------

    /// @notice NeoSafe treasury on Base
    address public constant NEOSAFE = 0x46fF491D7054A6F500026B3E81f358190f8d8Ec5;

    /// @notice Role for minting game assets (game servers, reward systems)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role for managing asset metadata and types
    bytes32 public constant GAME_ADMIN_ROLE = keccak256("GAME_ADMIN_ROLE");

    // -----------------------------------------------------------------------
    // Structs
    // -----------------------------------------------------------------------

    struct AssetType {
        string name;
        uint256 maxSupply;        // 0 = unlimited
        bool transferable;        // whether players can trade/sell
        bool playToEarnEligible;  // can be earned through gameplay
        uint256 earnCooldown;     // seconds between P2E claims per player
        bool exists;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /// @notice Game identifier
    uint256 public immutable gameId;

    /// @notice tokenId => AssetType definition
    mapping(uint256 => AssetType) public assetTypes;

    /// @notice tokenId => player => last P2E claim timestamp
    mapping(uint256 => mapping(address => uint256)) public lastEarnClaim;

    /// @notice Token-level URI overrides (tokenId => uri)
    mapping(uint256 => string) private _tokenURIs;

    /// @notice Contract-level name for marketplace display
    string public name;

    /// @notice Contract-level symbol
    string public symbol;

    /// @notice Next token type ID
    uint256 public nextTokenId;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// @notice Emitted when a new asset type is created
    event AssetTypeCreated(
        uint256 indexed tokenId,
        string name,
        uint256 maxSupply,
        bool transferable,
        bool playToEarnEligible
    );

    /// @notice Emitted when assets are minted to a player
    event AssetsMinted(address indexed to, uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when a player earns assets through gameplay
    event PlayToEarnClaimed(address indexed player, uint256 indexed tokenId, uint256 amount);

    /// @notice Emitted when asset metadata URI is updated
    event AssetURIUpdated(uint256 indexed tokenId, string newURI);

    /// @notice Emitted when assets are batch minted
    event BatchMinted(address indexed to, uint256[] tokenIds, uint256[] amounts);

    // -----------------------------------------------------------------------
    // Modifiers
    // -----------------------------------------------------------------------

    modifier assetExists(uint256 _tokenId) {
        require(assetTypes[_tokenId].exists, "GameAsset: asset type does not exist");
        _;
    }

    modifier withinSupply(uint256 _tokenId, uint256 _amount) {
        AssetType storage at_ = assetTypes[_tokenId];
        if (at_.maxSupply > 0) {
            require(
                totalSupply(_tokenId) + _amount <= at_.maxSupply,
                "GameAsset: exceeds max supply"
            );
        }
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    /**
     * @notice Deploy ERC-1155 game asset contract.
     * @param _baseURI Base metadata URI.
     * @param _name Collection name.
     * @param _symbol Collection symbol.
     * @param _gameId Game identifier for reference.
     * @param _admin Initial admin address.
     */
    constructor(
        string memory _baseURI,
        string memory _name,
        string memory _symbol,
        uint256 _gameId,
        address _admin
    ) ERC1155(_baseURI) {
        name = _name;
        symbol = _symbol;
        gameId = _gameId;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(GAME_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
    }

    // -----------------------------------------------------------------------
    // Asset Type Management
    // -----------------------------------------------------------------------

    /**
     * @notice Create a new asset type.
     * @param _name Asset name.
     * @param _maxSupply Maximum supply (0 = unlimited).
     * @param _transferable Whether players can trade/sell.
     * @param _playToEarnEligible Whether this asset can be earned via gameplay.
     * @param _earnCooldown Seconds between P2E claims per player.
     * @return tokenId The new token ID.
     */
    function createAssetType(
        string calldata _name,
        uint256 _maxSupply,
        bool _transferable,
        bool _playToEarnEligible,
        uint256 _earnCooldown
    ) external onlyRole(GAME_ADMIN_ROLE) returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        assetTypes[tokenId] = AssetType({
            name: _name,
            maxSupply: _maxSupply,
            transferable: _transferable,
            playToEarnEligible: _playToEarnEligible,
            earnCooldown: _earnCooldown,
            exists: true
        });

        emit AssetTypeCreated(tokenId, _name, _maxSupply, _transferable, _playToEarnEligible);
    }

    /**
     * @notice Set per-token metadata URI.
     * @param _tokenId Token ID.
     * @param _uri New URI string.
     */
    function setTokenURI(uint256 _tokenId, string calldata _uri)
        external
        onlyRole(GAME_ADMIN_ROLE)
        assetExists(_tokenId)
    {
        _tokenURIs[_tokenId] = _uri;
        emit AssetURIUpdated(_tokenId, _uri);
        emit URI(_uri, _tokenId);
    }

    // -----------------------------------------------------------------------
    // Minting
    // -----------------------------------------------------------------------

    /**
     * @notice Mint assets to a player.
     * @param _to Recipient address.
     * @param _tokenId Token type ID.
     * @param _amount Number of tokens.
     * @param _data Additional data.
     */
    function mint(address _to, uint256 _tokenId, uint256 _amount, bytes calldata _data)
        external
        onlyRole(MINTER_ROLE)
        assetExists(_tokenId)
        withinSupply(_tokenId, _amount)
    {
        _mint(_to, _tokenId, _amount, _data);
        emit AssetsMinted(_to, _tokenId, _amount);
    }

    /**
     * @notice Batch mint multiple asset types to a player.
     * @param _to Recipient address.
     * @param _tokenIds Array of token type IDs.
     * @param _amounts Array of amounts.
     * @param _data Additional data.
     */
    function mintBatch(
        address _to,
        uint256[] calldata _tokenIds,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external onlyRole(MINTER_ROLE) {
        require(_tokenIds.length == _amounts.length, "GameAsset: length mismatch");
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(assetTypes[_tokenIds[i]].exists, "GameAsset: asset type missing");
            AssetType storage at_ = assetTypes[_tokenIds[i]];
            if (at_.maxSupply > 0) {
                require(
                    totalSupply(_tokenIds[i]) + _amounts[i] <= at_.maxSupply,
                    "GameAsset: exceeds max supply"
                );
            }
        }
        _mintBatch(_to, _tokenIds, _amounts, _data);
        emit BatchMinted(_to, _tokenIds, _amounts);
    }

    // -----------------------------------------------------------------------
    // Play-to-Earn
    // -----------------------------------------------------------------------

    /**
     * @notice Claim play-to-earn rewards. Authorized minters call on behalf of players.
     * @param _player Player address.
     * @param _tokenId Token type to earn.
     * @param _amount Amount to earn.
     */
    function claimPlayToEarn(address _player, uint256 _tokenId, uint256 _amount)
        external
        onlyRole(MINTER_ROLE)
        assetExists(_tokenId)
        withinSupply(_tokenId, _amount)
        nonReentrant
    {
        AssetType storage at_ = assetTypes[_tokenId];
        require(at_.playToEarnEligible, "GameAsset: not P2E eligible");
        require(
            block.timestamp >= lastEarnClaim[_tokenId][_player] + at_.earnCooldown,
            "GameAsset: cooldown active"
        );

        lastEarnClaim[_tokenId][_player] = block.timestamp;
        _mint(_player, _tokenId, _amount, "");

        emit PlayToEarnClaimed(_player, _tokenId, _amount);
    }

    // -----------------------------------------------------------------------
    // Transfer Restrictions
    // -----------------------------------------------------------------------

    /**
     * @dev Override to enforce transferability rules. Non-transferable assets
     *      can only be minted/burned, not traded.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) {
        // Allow minting (from == 0) and burning (to == 0) always
        if (from != address(0) && to != address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {
                require(
                    assetTypes[ids[i]].transferable,
                    "GameAsset: asset not transferable"
                );
            }
        }
        super._update(from, to, ids, values);
    }

    // -----------------------------------------------------------------------
    // View
    // -----------------------------------------------------------------------

    /**
     * @notice Get the URI for a specific token ID, falling back to base URI.
     * @param _tokenId Token ID.
     * @return Token metadata URI.
     */
    function uri(uint256 _tokenId) public view override returns (string memory) {
        string memory tokenURI = _tokenURIs[_tokenId];
        if (bytes(tokenURI).length > 0) {
            return tokenURI;
        }
        return super.uri(_tokenId);
    }

    /**
     * @notice Get asset type details.
     * @param _tokenId Token ID.
     */
    function getAssetType(uint256 _tokenId) external view returns (AssetType memory) {
        return assetTypes[_tokenId];
    }

    /// @dev Required override for AccessControl + ERC1155.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
