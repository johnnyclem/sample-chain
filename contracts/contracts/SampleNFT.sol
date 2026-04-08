// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// Local import
import {RoyaltySplit} from "./RoyaltySplit.sol";

/**
 * @title SampleNFT
 * @notice ERC-1155 NFT contract for music samples on SampleChain.
 *         Supports 1-of-1 and edition-based minting with rich on-chain metadata.
 *         Delegates ERC-2981 royalty queries to a companion RoyaltySplit contract.
 */
contract SampleNFT is ERC1155, ERC1155Supply, AccessControl, Pausable {
    using Strings for uint256;

    // ----------------------------------------------------------------
    // Roles
    // ----------------------------------------------------------------

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // ----------------------------------------------------------------
    // Enums
    // ----------------------------------------------------------------

    enum SampleType {
        Oneshot,
        Loop,
        Hit,
        Texture,
        Vocal,
        Fx,
        Other
    }

    enum LicenseTier {
        Free,
        Paid
    }

    // ----------------------------------------------------------------
    // Structs
    // ----------------------------------------------------------------

    struct SampleMetadata {
        address creator;
        string ipfsCid;
        uint16 bpm;
        uint8 musicalKey; // 0-11 for C through B; 255 = unspecified
        SampleType sampleType;
        LicenseTier licenseTier;
        uint256 maxSupply; // 0 = unlimited (open edition)
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Auto-incrementing token ID counter. First token = 1.
    uint256 public nextTokenId = 1;

    /// @notice On-chain metadata per token.
    mapping(uint256 => SampleMetadata) public sampleMetadata;

    /// @notice Reference to the royalty-split contract.
    RoyaltySplit public royaltySplit;

    /// @notice Base URI for token metadata (off-chain JSON).
    string private _baseTokenURI;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event SampleMinted(
        uint256 indexed tokenId,
        address indexed creator,
        string ipfsCid,
        uint16 bpm,
        uint8 musicalKey,
        SampleType sampleType,
        LicenseTier licenseTier,
        uint256 amount,
        uint256 maxSupply
    );

    event BaseURIUpdated(string newBaseURI);

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @param baseURI_       Base URI prefix (e.g. "https://api.samplechain.xyz/meta/").
     * @param _royaltySplit  Address of the deployed RoyaltySplit contract.
     */
    constructor(
        string memory baseURI_,
        address _royaltySplit
    ) ERC1155("") {
        require(_royaltySplit != address(0), "SampleNFT: zero royaltySplit");

        _baseTokenURI = baseURI_;
        royaltySplit = RoyaltySplit(payable(_royaltySplit));

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    // ----------------------------------------------------------------
    // Minting
    // ----------------------------------------------------------------

    /**
     * @notice Mint a new sample token (1-of-1 or edition).
     * @param to          Recipient of the minted tokens.
     * @param amount      Number of copies to mint (1 for a 1-of-1).
     * @param maxSupply   Maximum editions allowed (0 = unlimited).
     * @param ipfsCid     IPFS content identifier for the audio.
     * @param bpm         Beats per minute.
     * @param musicalKey  Musical key (0-11 or 255 for unspecified).
     * @param sampleType  Category of the sample.
     * @param licenseTier License tier.
     * @return tokenId    The newly created token ID.
     */
    function mint(
        address to,
        uint256 amount,
        uint256 maxSupply,
        string calldata ipfsCid,
        uint16 bpm,
        uint8 musicalKey,
        SampleType sampleType,
        LicenseTier licenseTier
    ) external onlyRole(MINTER_ROLE) whenNotPaused returns (uint256 tokenId) {
        require(amount > 0, "SampleNFT: amount = 0");
        require(bytes(ipfsCid).length > 0, "SampleNFT: empty CID");
        require(
            maxSupply == 0 || amount <= maxSupply,
            "SampleNFT: amount > maxSupply"
        );

        tokenId = nextTokenId++;

        sampleMetadata[tokenId] = SampleMetadata({
            creator: to,
            ipfsCid: ipfsCid,
            bpm: bpm,
            musicalKey: musicalKey,
            sampleType: sampleType,
            licenseTier: licenseTier,
            maxSupply: maxSupply
        });

        // Register creator in royalty split
        royaltySplit.registerCreator(tokenId, to);

        _mint(to, tokenId, amount, "");

        emit SampleMinted(
            tokenId,
            to,
            ipfsCid,
            bpm,
            musicalKey,
            sampleType,
            licenseTier,
            amount,
            maxSupply
        );
    }

    /**
     * @notice Mint additional editions of an existing token.
     *         Only for tokens with open editions (maxSupply == 0) or
     *         tokens that still have capacity.
     */
    function mintEdition(
        address to,
        uint256 tokenId,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) whenNotPaused {
        require(amount > 0, "SampleNFT: amount = 0");
        SampleMetadata storage meta = sampleMetadata[tokenId];
        require(meta.creator != address(0), "SampleNFT: nonexistent token");
        require(
            meta.maxSupply == 0 ||
                totalSupply(tokenId) + amount <= meta.maxSupply,
            "SampleNFT: exceeds maxSupply"
        );

        _mint(to, tokenId, amount, "");
    }

    // ----------------------------------------------------------------
    // URI
    // ----------------------------------------------------------------

    /**
     * @notice Returns the metadata URI for a given token.
     *         Format: {baseURI}{tokenId}
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        require(
            sampleMetadata[tokenId].creator != address(0),
            "SampleNFT: nonexistent token"
        );
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString()));
    }

    /**
     * @notice Update the base URI (admin only).
     */
    function setBaseURI(string calldata newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    // ----------------------------------------------------------------
    // Pause
    // ----------------------------------------------------------------

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ----------------------------------------------------------------
    // ERC-2981 delegation
    // ----------------------------------------------------------------

    /**
     * @notice Delegates royalty info to the RoyaltySplit contract.
     */
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view returns (address, uint256) {
        return royaltySplit.royaltyInfo(tokenId, salePrice);
    }

    // ----------------------------------------------------------------
    // Interface support
    // ----------------------------------------------------------------

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155, AccessControl) returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // ----------------------------------------------------------------
    // Internal overrides required by Solidity
    // ----------------------------------------------------------------

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        super._update(from, to, ids, values);
    }
}
