// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {RoyaltySplit} from "./RoyaltySplit.sol";

/**
 * @title SampleMarketplace
 * @notice A simple marketplace for SampleNFT ERC-1155 tokens on Base L2.
 *         Sellers list samples with a price (ETH). Buyers purchase and
 *         royalties are automatically split via the RoyaltySplit contract.
 */
contract SampleMarketplace is ReentrancyGuard, Ownable {
    // ----------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------

    struct Listing {
        address seller;
        uint256 tokenId;
        uint256 amount;
        uint256 pricePerUnit; // in wei; 0 = free
        bool active;
    }

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice The SampleNFT ERC-1155 contract.
    IERC1155 public immutable nft;

    /// @notice The RoyaltySplit contract for royalty calculations.
    RoyaltySplit public immutable royaltySplit;

    /// @notice Auto-incrementing listing ID. First listing = 1.
    uint256 public nextListingId = 1;

    /// @notice All listings by ID.
    mapping(uint256 => Listing) public listings;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event SampleListed(
        uint256 indexed listingId,
        address indexed seller,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 pricePerUnit
    );

    event SampleSold(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 amount,
        uint256 totalPrice
    );

    event ListingCancelled(uint256 indexed listingId);

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    constructor(
        address _nft,
        address payable _royaltySplit
    ) Ownable(msg.sender) {
        require(_nft != address(0), "Marketplace: zero nft");
        require(_royaltySplit != address(0), "Marketplace: zero royaltySplit");

        nft = IERC1155(_nft);
        royaltySplit = RoyaltySplit(_royaltySplit);
    }

    // ----------------------------------------------------------------
    // Listing
    // ----------------------------------------------------------------

    /**
     * @notice List a sample for sale. Seller must have approved this contract
     *         via setApprovalForAll on the NFT contract before listing.
     * @param tokenId       Token ID to list.
     * @param amount        Number of editions to list.
     * @param pricePerUnit  Price per edition in wei (0 for free).
     * @return listingId    The ID of the new listing.
     */
    function list(
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerUnit
    ) external returns (uint256 listingId) {
        require(amount > 0, "Marketplace: amount = 0");
        require(
            nft.balanceOf(msg.sender, tokenId) >= amount,
            "Marketplace: insufficient balance"
        );
        require(
            nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace: not approved"
        );

        listingId = nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            tokenId: tokenId,
            amount: amount,
            pricePerUnit: pricePerUnit,
            active: true
        });

        emit SampleListed(listingId, msg.sender, tokenId, amount, pricePerUnit);
    }

    /**
     * @notice Cancel an active listing. Only the seller can cancel.
     */
    function cancel(uint256 listingId) external {
        Listing storage l = listings[listingId];
        require(l.active, "Marketplace: not active");
        require(l.seller == msg.sender, "Marketplace: not seller");

        l.active = false;
        emit ListingCancelled(listingId);
    }

    // ----------------------------------------------------------------
    // Purchasing
    // ----------------------------------------------------------------

    /**
     * @notice Buy copies from a listing.
     * @param listingId  Listing to buy from.
     * @param amount     Number of copies to buy.
     */
    function buy(
        uint256 listingId,
        uint256 amount
    ) external payable nonReentrant {
        Listing storage l = listings[listingId];
        require(l.active, "Marketplace: not active");
        require(amount > 0 && amount <= l.amount, "Marketplace: bad amount");

        uint256 totalPrice = l.pricePerUnit * amount;
        require(msg.value == totalPrice, "Marketplace: wrong ETH amount");

        // Update listing state first (checks-effects-interactions)
        l.amount -= amount;
        if (l.amount == 0) {
            l.active = false;
        }

        // Transfer NFT from seller to buyer
        nft.safeTransferFrom(l.seller, msg.sender, l.tokenId, amount, "");

        if (totalPrice > 0) {
            // Calculate royalty
            (, uint256 royaltyAmount) = royaltySplit.royaltyInfo(
                l.tokenId,
                totalPrice
            );

            uint256 sellerProceeds = totalPrice - royaltyAmount;

            // Send royalty to RoyaltySplit
            if (royaltyAmount > 0) {
                royaltySplit.receiveRoyalty{value: royaltyAmount}(l.tokenId);
            }

            // Send remaining to seller
            if (sellerProceeds > 0) {
                (bool ok, ) = payable(l.seller).call{value: sellerProceeds}("");
                require(ok, "Marketplace: seller transfer failed");
            }
        }

        emit SampleSold(listingId, msg.sender, amount, totalPrice);
    }
}
