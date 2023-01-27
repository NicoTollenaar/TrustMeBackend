// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

error InvalidAddress();
error CannotTradeSameToken();
error CannotTradeWithSelf();
error DeadlineShouldBeAtLeast5Minutes();
error InvalidAmount();
error InsufficientBalance();
error OnlyBuyer();
error OnlySeller();
error TradeIsNotPending();
error TradeIsExpired();
error InsufficientAllowance();
error UpkeepNotNeeded();
error CannotWithdrawTimeNotPassed();
error IncorrectAmoutOfETHTransferred();

contract TrustMe is AutomationCompatible {
	using SafeERC20 for IERC20;
	/*********
	 * TYPES *
	 *********/
	enum TradeStatus {
		Pending,
		Confirmed,
		Canceled,
		Expired,
		Withdrawn
	}

	// NT - should we reconsider including a Trade ID in the trade struct? It would at least make a number of things quite a bit easier.

	// Dont we need to track a seller's tokens/ETH in the contract to a specific transaction, e.g. mapping(seller=>(mapping(uint=>uint))) sellerToTradeIdToTokenBalance? And the same for ETH balance?

	struct Trade {
		address seller;
		address buyer;
		address tokenToSell;
		address tokenToBuy;
		uint256 amountOfETHToSell;
		uint256 amountOfTokenToSell;
		uint256 amountOfETHToBuy;
		uint256 amountOfTokenToBuy;
		uint256 deadline;
		bool isAvailableToWithdraw;
		TradeStatus status;
	}

	/**********************
	 *  STATE VARIABLES *
	 **********************/

	mapping(address => Trade[]) public userToTrades;
	address[] private sellerAddresses;

	// NT - is it necessary to keep track of seller token and ETH balances in contract? I have done so now for ETH;

	mapping(address => uint) sellerToETHBalances;

	/**********
	 * EVENTS *
	 **********/
	event TradeCreated(
		address indexed seller,
		address indexed buyer,
		address tokenToSell,
		address tokenToBuy,
		uint256 amountOfETHToSell,
		uint256 amountOfTokenToSell,
		uint256 amountOfETHToBuy,
		uint256 amountOfTokenToBuy,
		uint deadline
	);
	event TradeConfirmed(address indexed seller, address indexed buyer);
	event TradeExpired(address indexed seller, address indexed buyer);
	event TradeCanceled(address indexed seller, address indexed buyer, address tokenToSell, address tokenToBuy);
	event TokensWithdrawn(address indexed seller, uint tradeIndex);

	/***************
	 * MODIFIERS *
	 ***************/

	//  NT: do we need to require that either tokens or ETH are are traded but not both at the same time on one side? In the current UI it is either one or the other, but future versions should facilitate batching multiple assets on either side of the trade (including both ETH and tokens on one side of the trade).

	modifier validateAddTrade(
		address _buyer,
		address _tokenToSell,
		address _tokenToBuy,
		uint256 _amountOfETHToSell,
		uint256 _amountOfTokenToSell,
		uint256 _amountOfETHToBuy,
		uint256 _amountOfTokenToBuy
	) {
		if (msg.sender == address(0)) revert InvalidAddress();
		if (_buyer == address(0)) revert InvalidAddress();
		if (_tokenToSell == address(0)) revert InvalidAddress();
		if (_tokenToBuy == address(0)) revert InvalidAddress();
		if (_tokenToSell == _tokenToBuy) revert CannotTradeSameToken();
		if (msg.sender == _buyer) revert CannotTradeWithSelf();
		if (_amountOfTokenToSell == 0 && _amountOfETHToSell == 0) revert InvalidAmount();
		if (_amountOfTokenToBuy == 0 && _amountOfETHToBuy == 0) revert InvalidAmount();
		if (IERC20(_tokenToSell).balanceOf(msg.sender) < _amountOfTokenToSell) revert InsufficientBalance();
		if (msg.value != _amountOfETHToSell) revert IncorrectAmoutOfETHTransferred();
		_;
	}

	// NT: in validateCloseTrade - do we also need to (double)check whether the contract (still) has enough tokensToSell / ETHToSell?

	modifier validateCloseTrade(address seller, uint256 index) {
		Trade memory trade = userToTrades[seller][index];
		if (trade.buyer != msg.sender) revert OnlyBuyer();
		if (trade.status != TradeStatus.Pending) revert TradeIsNotPending(); //Do we need to check this?
		if (trade.deadline < block.timestamp) revert TradeIsExpired();
		IERC20 token = IERC20(trade.tokenToBuy);
		if (token.allowance(msg.sender, address(this)) < trade.amountOfTokenToBuy) revert InsufficientAllowance();
		if (token.balanceOf(msg.sender) < trade.amountOfTokenToBuy) revert InsufficientBalance();

		// check if buyer has transferred correct amountOfETHToBuy

		if (msg.value != trade.amountOfETHToBuy) revert IncorrectAmoutOfETHTransferred();

		// check if contract has enough ETH from seller to transfer amountOfETHToSell.

		// Do we also need to check this for tokens to sell?

		if (address(this).balance < trade.amountOfETHToSell || sellerToETHBalances[seller] < trade.amountOfETHToSell)
			revert InsufficientBalance();
		_;
	}

	// NT - suggestion to also enable buyer to cancel trade.
	modifier validateCancelTrade(uint index) {
		Trade memory trade = userToTrades[msg.sender][index];
		if (trade.seller != msg.sender) revert OnlySeller();
		if (trade.status != TradeStatus.Pending) revert TradeIsNotPending();
		if (trade.deadline < block.timestamp) revert TradeIsExpired();

		// This needs to be adapted if also buyer is enabled to cancel. Do we need to double check the same for tokens, ie. whether contract has sufficient tokens held for seller?

		if (
			address(this).balance < trade.amountOfETHToSell || sellerToETHBalances[msg.sender] < trade.amountOfETHToSell
		) revert InsufficientBalance();
		_;
	}

	/**
	 *@dev  Create Trade to initialize a trade as a seller
	 *@param _buyer address of the buyer
	 *@param _tokenToSell address of the token to sell
	 *@param _tokenToBuy address of the token to buy
	 *@param _amountOfETHToSell amount of ETH to sell
	 *@param _amountOfTokenToSell amount of token to sell
	 *@param _amountOfETHToBuy amount of ETH to buy
	 *@param _amountOfTokenToBuy amount of token to buy
	 *@param  _tradePeriod duration of trade
	 */

	// NT: should we leave the option open to sell both tokens and ETH or require that it must be either one or the other but not both - see my above remark.

	function addTrade(
		address _buyer,
		address _tokenToSell,
		address _tokenToBuy,
		uint256 _amountOfETHToSell,
		uint256 _amountOfTokenToSell,
		uint256 _amountOfETHToBuy,
		uint256 _amountOfTokenToBuy,
		uint256 _tradePeriod
	)
		external
		payable
		validateAddTrade(
			_buyer,
			_tokenToSell,
			_tokenToBuy,
			_amountOfETHToSell,
			_amountOfTokenToSell,
			_amountOfETHToBuy,
			_amountOfTokenToBuy
		)
	{
		uint tradePeriod = block.timestamp + _tradePeriod;
		IERC20 token = IERC20(_tokenToSell);

		if (_amountOfTokenToSell > 0) token.safeTransferFrom(msg.sender, address(this), _amountOfTokenToSell);

		// NT: is it necessary to keep track of sellers ETH in the contract (it certainly feels "safer") and, if so, do we need to do the same for seller's tokens? See also comment above.

		sellerToETHBalances[msg.sender] += msg.value;
		Trade memory trade = Trade(
			msg.sender,
			_buyer,
			_tokenToSell,
			_tokenToBuy,
			0,
			0,
			0,
			0,
			0,
			false,
			TradeStatus.Pending
		);

		{
			trade.amountOfETHToSell = _amountOfETHToSell;
			trade.amountOfTokenToSell = _amountOfTokenToSell;
			trade.amountOfETHToBuy = _amountOfETHToBuy;
			trade.amountOfTokenToBuy = _amountOfTokenToBuy;
			trade.deadline = _tradePeriod;
			trade.isAvailableToWithdraw = false;
			trade.status = TradeStatus.Pending;
		}

		userToTrades[msg.sender].push(trade);
		sellerAddresses.push(msg.sender);

		emit TradeCreated(
			msg.sender,
			_buyer,
			_tokenToSell,
			_tokenToBuy,
			_amountOfETHToSell,
			_amountOfTokenToSell,
			_amountOfETHToBuy,
			_amountOfTokenToBuy,
			tradePeriod
		);
	}

	function confirmTrade(address seller, uint256 index) external payable validateCloseTrade(seller, index) {
		Trade storage trade = userToTrades[seller][index];

		// NT - see comment above on option or not to trade both ETH and tokens at the same time;

		if (trade.amountOfTokenToBuy > 0)
			IERC20(trade.tokenToBuy).safeTransferFrom(msg.sender, trade.seller, trade.amountOfTokenToBuy);

		if (trade.amountOfETHToBuy > 0) payable(seller).transfer(msg.value);

		if (trade.amountOfTokenToSell > 0)
			IERC20(trade.tokenToSell).safeTransfer(trade.buyer, trade.amountOfTokenToSell);

		if (trade.amountOfETHToSell > 0) payable(msg.sender).transfer(trade.amountOfETHToSell);

		sellerToETHBalances[seller] -= trade.amountOfETHToSell;

		trade.status = TradeStatus.Confirmed;
		emit TradeConfirmed(seller, msg.sender);
	}

	// NT - my suggestion would be to also allow the buyer to cancel a trade - see my comments in discord. If we do so msg.sender must be replaced by seller in the function below (cancelTrade)

	function cancelTrade(uint256 index) external validateCancelTrade(index) {
		Trade storage trade = userToTrades[msg.sender][index];
		trade.status = TradeStatus.Canceled;

		if (trade.amountOfTokenToSell > 0) IERC20(trade.tokenToSell).transfer(trade.seller, trade.amountOfTokenToSell);

		if (trade.amountOfETHToSell > 0) payable(msg.sender).transfer(trade.amountOfETHToSell);

		sellerToETHBalances[msg.sender] -= trade.amountOfETHToSell;

		emit TradeCanceled(msg.sender, trade.buyer, trade.tokenToSell, trade.tokenToBuy);
	}

	// NT: in withdrawToken - do we need seller address as a parameter given that if it will only we seller who can invoke this function? Cant we just use msg.sender?

	function withdrawToken(address seller, uint index) public {
		if (msg.sender != seller) revert OnlySeller();
		Trade memory trade = userToTrades[seller][index];
		if (trade.isAvailableToWithdraw == false) revert CannotWithdrawTimeNotPassed();

		// do we need to double check the same for tokens?
		if (
			address(this).balance < trade.amountOfETHToSell || sellerToETHBalances[msg.sender] < trade.amountOfETHToSell
		) revert InsufficientBalance();

		if (trade.amountOfTokenToSell > 0) IERC20(trade.tokenToSell).safeTransfer(seller, trade.amountOfTokenToSell);

		// transfer ETH back to seller
		if (trade.amountOfETHToSell > 0) payable(msg.sender).transfer(trade.amountOfETHToSell);

		sellerToETHBalances[msg.sender] -= trade.amountOfETHToSell;

		userToTrades[seller][index].isAvailableToWithdraw = false;
		userToTrades[seller][index].status = TradeStatus.Withdrawn;
		emit TokensWithdrawn(msg.sender, trade.amountOfTokenToSell);
	}

	/************************
	 * CHAINLINK AUTOMATION *
	 ************************/

	function checkUpkeep(
		bytes memory /*checkData*/
	) public override returns (bool upkeepNeeded, bytes memory performData) {
		for (uint i = 0; i < sellerAddresses.length; i++) {
			address sellerAddress = sellerAddresses[i];
			Trade storage trade = userToTrades[sellerAddress][i];
			if (
				trade.deadline <= block.timestamp &&
				trade.status == TradeStatus.Pending &&
				trade.seller == sellerAddress
			) {
				trade.isAvailableToWithdraw = true;
				upkeepNeeded = true;
				performData = abi.encode(sellerAddress, i);
			}
		}
	}

	/**
	 *@dev Perform Upkeep to withdraw tokens from contract
	 *@dev This is called by the Chainlink Keeper Network if checkUpkeep returns true or someone can manully call it if checkUpkeep is true
	 */
	function performUpkeep(bytes calldata /*performData*/) external override {
		(bool upkeepNeeded, bytes memory performData) = checkUpkeep("");
		if (!upkeepNeeded) revert UpkeepNotNeeded();
		(address sellerAddress, uint256 index) = abi.decode(performData, (address, uint256));
		Trade storage _trade = userToTrades[sellerAddress][index];
		_trade.isAvailableToWithdraw = true;
		// withdrawToken(sellerAddress, index); //! we can either directly transfer the tokens here or let the seller manually withdraw them
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

	function getLatestTradeIndex(address userAddress) external view returns (uint256) {
		return userToTrades[userAddress].length - 1;
	}

	function getSellersAddress() external view returns (address[] memory) {
		return sellerAddresses;
	}
}
