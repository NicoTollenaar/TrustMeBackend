// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// imported for ChainLink automation
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

error InvalidAddress();
error CannotTradeSameToken();
error CannotTradeWithSelf();
error DeadlineShouldBeAtLeastAMinute();
error InvalidAmount();
error InsufficientBalance();
error OnlyBuyer();
error TradeIsNotPending();
error TradeIsExpired();
error InsufficientAllowance();

contract TrustMe is AutomationCompatibleInterface {
	// Events
	event TradeCreated(
		address indexed seller,
		address indexed buyer,
		address tokenToSell,
		address tokenToBuy,
		uint256 amountOfTokenToSell,
		uint256 amountOfTokenToBuy,
		uint deadline
	);

	event TradeAccepted(address indexed seller, address indexed buyer);

	event TradeExpired(address indexed seller, address indexed buyer);

	using SafeERC20 for IERC20;
	// State Variables

	enum TradeStatus {
		Pending,
		Accepted,
		Expired,
		Canceled
	}

	struct Trade {
		address seller;
		address buyer;
		address tokenToSell;
		address tokenToBuy;
		uint256 amountOfTokenToSell;
		uint256 amountOfTokenToBuy;
		uint256 deadline;
		TradeStatus status;
	}
	mapping(address => Trade[]) public userToTrades; // would it be better to call this sellerToTrades? There is no mapping for buyers
	mapping(address => mapping(address => uint256)) public userToTokenToAmount;

	// variable added for ChainLink automation
	Trade[] pendingTrades;

	modifier onlyValidTrade(
		address _buyer,
		address _tokenToSell,
		address _tokenToBuy,
		uint256 _amountOfTokenToSell,
		uint256 _amountOfTokenToBuy
	) {
		if (msg.sender == address(0)) revert InvalidAddress();
		if (_buyer == address(0)) revert InvalidAddress();
		if (_tokenToSell == address(0)) revert InvalidAddress();
		if (_tokenToBuy == address(0)) revert InvalidAddress();
		if (_tokenToSell == _tokenToBuy) revert CannotTradeSameToken();
		if (msg.sender == _buyer) revert CannotTradeWithSelf();
		if (_amountOfTokenToSell == 0) revert InvalidAmount();
		if (_amountOfTokenToBuy == 0) revert InvalidAmount();
		if (IERC20(_tokenToSell).balanceOf(msg.sender) < _amountOfTokenToSell) revert InsufficientBalance();
		_;
	}

	modifier validateCloseTrade(address seller, uint256 index) {
		Trade memory trade = userToTrades[seller][index];
		if (trade.buyer != msg.sender) revert OnlyBuyer();
		if (trade.status != TradeStatus.Pending) revert TradeIsNotPending(); //Do we need to check this?
		if (trade.deadline < block.timestamp) revert TradeIsExpired();
		IERC20 token = IERC20(trade.tokenToBuy);
		if (token.allowance(msg.sender, address(this)) < trade.amountOfTokenToBuy) revert InsufficientAllowance();
		if (token.balanceOf(msg.sender) < trade.amountOfTokenToBuy) revert InsufficientBalance();
		_;
	}

	/**
	 *@dev  Create Trade to initialize a trade as a seller
	 *@param _buyer address of the buyer
	 *@param _tokenToSell address of the token to sell
	 *@param _tokenToBuy address of the token to buy
	 *@param _amountOfTokenToSell amount of token to sell
	 *@param _amountOfTokenToBuy amount of token to buy
	 *@param _deadline deadline of the trade in unix timestamp
	 */

	function addTrade(
		address _buyer,
		address _tokenToSell,
		address _tokenToBuy,
		uint256 _amountOfTokenToSell,
		uint256 _amountOfTokenToBuy,
		uint256 _deadline
	) external onlyValidTrade(_buyer, _tokenToSell, _tokenToBuy, _amountOfTokenToSell, _amountOfTokenToBuy) {
		IERC20 token = IERC20(_tokenToSell);
		token.safeTransferFrom(msg.sender, address(this), _amountOfTokenToSell);

		Trade memory trade = Trade(
			msg.sender,
			_buyer,
			_tokenToSell,
			_tokenToBuy,
			_amountOfTokenToSell,
			_amountOfTokenToBuy,
			_deadline,
			TradeStatus.Pending
		);

		userToTrades[msg.sender].push(trade);
		userToTokenToAmount[msg.sender][_tokenToSell] = _amountOfTokenToSell;
		pendingTrades.push(trade);

		emit TradeCreated(
			msg.sender,
			_buyer,
			_tokenToSell,
			_tokenToBuy,
			_amountOfTokenToSell,
			_amountOfTokenToBuy,
			_deadline
		);
	}

	function closeTrade(address seller, uint256 index) external validateCloseTrade(seller, index) {
		Trade memory trade = userToTrades[seller][index];

		IERC20(trade.tokenToBuy).safeTransferFrom(msg.sender, trade.seller, trade.amountOfTokenToBuy);
		// Transfer token to buyer from contract
		IERC20(trade.tokenToSell).safeTransfer(trade.buyer, trade.amountOfTokenToSell);
		//function call added for ChainLink Automation
		removePendingTrade(trade);
		trade.status = TradeStatus.Accepted;

		userToTokenToAmount[seller][trade.tokenToSell] = 0;
		emit TradeAccepted(seller, msg.sender);
	}

	event TokensWithdrawn(address indexed seller, uint indexTrade);

	function withdrawTokens(address seller, uint _indexTrade) public {
		Trade storage trade = userToTrades[seller][_indexTrade];
		IERC20 token = IERC20(trade.tokenToSell);
		require(token.balanceOf(address(this)) == trade.amountOfTokenToSell);
		token.safeTransfer(seller, trade.amountOfTokenToSell);
		emit TokensWithdrawn(msg.sender, _indexTrade);
	}

	/***********
	 * GETTERS *
	 ***********/

	function getTrades(address userAddress) external view returns (Trade[] memory) {
		return userToTrades[userAddress];
	}

	function getTrade(address userAddress, uint256 index) external view returns (Trade memory) {
		return userToTrades[userAddress][index];
	}

	function getLatestTrade(address userAddress) external view returns (uint256) {
		return userToTrades[userAddress].length - 1;
	}

	/************************
	 * CHAINLINK AUTOMATION *
	 ************************/

	function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData) {
		(bool somethingExpired, bytes memory expiredTradesPlusCountInBytes) = getExpiredTrades();
		return (somethingExpired, expiredTradesPlusCountInBytes);
	}

	function performUpkeep(bytes calldata performData) external override {
		Trade[] memory expiredTrades = abi.decode(performData, (Trade[]));
		uint indexTrade;
		for (uint i = 0; i < expiredTrades.length; i++) {
			require(expiredTrades[i].deadline < block.timestamp);
			indexTrade = uint(getIndexUserToTrades(expiredTrades[i]));
			removePendingTrade(expiredTrades[i]);
			changeStatusToExpired(expiredTrades[i].seller, indexTrade);
			withdrawTokens(expiredTrades[i].seller, indexTrade); //delete this line if seller is to withdraw manually
		}
	}

	event TradeExpired(address indexed seller, uint indexed indexTrade);

	function changeStatusToExpired(address _seller, uint _indexTrade) internal {
		Trade storage trade = userToTrades[_seller][_indexTrade];
		trade.status == TradeStatus.Expired;
		emit TradeExpired(_seller, _indexTrade);
	}

	function getExpiredTrades() internal view returns (bool, bytes memory) {
		uint counter;
		for (uint i = 0; i < pendingTrades.length; i++) {
			if (block.timestamp > pendingTrades[i].deadline) {
				counter++;
			}
		}
		Trade[] memory expiredTrades = new Trade[](counter);
		for (uint i = 0; i < pendingTrades.length; i++) {
			if (block.timestamp > pendingTrades[i].deadline) {
				expiredTrades[i] = pendingTrades[i];
			}
		}
		return (counter != 0, abi.encode(expiredTrades));
	}

	function removePendingTrade(Trade memory _trade) internal {
		uint index;
		for (uint i = 0; i < pendingTrades.length; i++) {
			if (
				pendingTrades[i].seller == _trade.seller &&
				pendingTrades[i].buyer == _trade.buyer &&
				pendingTrades[i].tokenToSell == _trade.tokenToSell &&
				pendingTrades[i].tokenToBuy == _trade.tokenToBuy &&
				pendingTrades[i].amountOfTokenToSell == _trade.amountOfTokenToSell &&
				pendingTrades[i].amountOfTokenToBuy == _trade.amountOfTokenToBuy &&
				pendingTrades[i].deadline == _trade.deadline &&
				pendingTrades[i].status == _trade.status
			) index = i;
		}
		pendingTrades[pendingTrades.length - 1] = pendingTrades[index];
		pendingTrades.pop();
	}

	function getIndexUserToTrades(Trade memory _trade) internal view returns (int) {
		for (uint i = 0; i < userToTrades[_trade.seller].length; i++) {
			Trade memory trade = userToTrades[_trade.seller][i];
			if (
				trade.seller == _trade.seller &&
				trade.buyer == _trade.buyer &&
				trade.tokenToSell == _trade.tokenToSell &&
				trade.tokenToBuy == _trade.tokenToBuy &&
				trade.amountOfTokenToSell == _trade.amountOfTokenToSell &&
				trade.amountOfTokenToBuy == _trade.amountOfTokenToBuy &&
				trade.deadline == _trade.deadline &&
				trade.status == _trade.status
			) return int(i);
		}
		return -1;
	}
}
