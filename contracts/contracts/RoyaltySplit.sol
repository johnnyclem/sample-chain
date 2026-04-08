// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RoyaltySplit
 * @notice Implements EIP-2981 royalty info and handles royalty distribution
 *         between the platform operator and sample creators.
 *         Uses a pull (withdrawal) pattern for gas-efficient payouts.
 */
contract RoyaltySplit is IERC2981, Ownable, ReentrancyGuard {
    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice Royalty percentage in basis points (e.g. 500 = 5%). Immutable.
    uint96 public immutable royaltyBps;

    /// @notice Operator fee as a percentage of the royalty, in basis points.
    ///         For example 2000 = 20% of the royalty goes to the operator.
    ///         Immutable after deployment.
    uint96 public immutable operatorFeeBps;

    /// @notice Address that receives the operator share.
    address public immutable operator;

    /// @notice Accrued balances available for withdrawal (creator => amount).
    mapping(address => uint256) public balances;

    /// @notice Accrued operator balance.
    uint256 public operatorBalance;

    /// @notice Mapping from tokenId to creator address.
    mapping(uint256 => address) public tokenCreators;

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event RoyaltyReceived(uint256 indexed tokenId, uint256 amount, address creator);
    event Withdrawn(address indexed payee, uint256 amount);
    event OperatorWithdrawn(address indexed operator, uint256 amount);
    event CreatorRegistered(uint256 indexed tokenId, address creator);

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @param _operator        Address of the platform operator.
     * @param _royaltyBps      Total royalty in basis points (max 10000).
     * @param _operatorFeeBps  Operator's share of the royalty in basis points (max 10000).
     */
    constructor(
        address _operator,
        uint96 _royaltyBps,
        uint96 _operatorFeeBps
    ) Ownable(msg.sender) {
        require(_operator != address(0), "RoyaltySplit: zero operator");
        require(_royaltyBps <= 10000, "RoyaltySplit: royalty > 100%");
        require(_operatorFeeBps <= 10000, "RoyaltySplit: opFee > 100%");

        operator = _operator;
        royaltyBps = _royaltyBps;
        operatorFeeBps = _operatorFeeBps;
    }

    // ----------------------------------------------------------------
    // EIP-2981
    // ----------------------------------------------------------------

    /**
     * @inheritdoc IERC2981
     * @dev Returns this contract as the receiver so royalties flow here
     *      for later splitting.
     */
    function royaltyInfo(
        uint256 /* tokenId */,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyAmount) {
        royaltyAmount = (salePrice * royaltyBps) / 10000;
        receiver = address(this);
    }

    // ----------------------------------------------------------------
    // Creator registration (only owner, i.e. SampleNFT)
    // ----------------------------------------------------------------

    /**
     * @notice Register the creator for a given tokenId. Called by SampleNFT on mint.
     */
    function registerCreator(uint256 tokenId, address creator) external onlyOwner {
        require(creator != address(0), "RoyaltySplit: zero creator");
        tokenCreators[tokenId] = creator;
        emit CreatorRegistered(tokenId, creator);
    }

    // ----------------------------------------------------------------
    // Receive royalty
    // ----------------------------------------------------------------

    /**
     * @notice Accept royalty payment for a specific token and split it
     *         between operator and creator balances.
     */
    function receiveRoyalty(uint256 tokenId) external payable {
        require(msg.value > 0, "RoyaltySplit: no value");
        address creator = tokenCreators[tokenId];
        require(creator != address(0), "RoyaltySplit: unknown token");

        uint256 opShare = (msg.value * operatorFeeBps) / 10000;
        uint256 creatorShare = msg.value - opShare;

        operatorBalance += opShare;
        balances[creator] += creatorShare;

        emit RoyaltyReceived(tokenId, msg.value, creator);
    }

    // ----------------------------------------------------------------
    // Withdrawals (pull pattern)
    // ----------------------------------------------------------------

    /**
     * @notice Withdraw accrued royalty balance for the caller.
     */
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "RoyaltySplit: nothing to withdraw");

        balances[msg.sender] = 0;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "RoyaltySplit: transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Withdraw accrued operator balance. Callable by the operator.
     */
    function withdrawOperator() external nonReentrant {
        require(msg.sender == operator, "RoyaltySplit: not operator");
        uint256 amount = operatorBalance;
        require(amount > 0, "RoyaltySplit: nothing to withdraw");

        operatorBalance = 0;

        (bool ok, ) = payable(operator).call{value: amount}("");
        require(ok, "RoyaltySplit: transfer failed");

        emit OperatorWithdrawn(operator, amount);
    }

    /**
     * @dev Accept plain ETH transfers (e.g. from marketplaces that just send ETH).
     */
    receive() external payable {}

    // ----------------------------------------------------------------
    // View helpers
    // ----------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == 0x01ffc9a7; // ERC-165
    }
}
