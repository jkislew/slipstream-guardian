// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { MockToken } from "./MockToken.sol";
import { PriceFeed } from "./PriceFeed.sol";
import { MockAMM } from "./MockAMM.sol";

/// @title GuardianVault
/// @notice Destination-chain contract (Base Sepolia). Holds user positions in
///         the volatile VOLT token and executes protective exits when the
///         reactive contract on Reactive Lasna orders one via callback.
/// @dev Callback authentication follows the Reactive Omni pattern exactly:
///      the call must arrive through the chain's callback proxy
///      (`onlyServiceProvider`) and the first payload argument — overwritten
///      by the network with the requesting reactive contract's address — must
///      match the authorized StopLossReactive contract (`onlyCallbackSender`).
///      This contract also pays for its own callbacks in Base Sepolia ETH
///      (see AbstractPayer), which is why the constructor is payable.
contract GuardianVault is AbstractCallback {
    uint8 public constant KIND_STOP_LOSS = 0;
    uint8 public constant KIND_TAKE_PROFIT = 1;

    struct Position {
        uint256 voltAmount; // VOLT held for the user, 18 decimals
        uint256 entryPrice; // feed price at open, scaled by 1e8
        uint32 stopLossBps; // e.g. 1000 == exit at -10% from entry
        uint32 takeProfitBps; // e.g. 2500 == exit at +25% from entry
        bool open;
    }

    MockToken public immutable usdx;
    MockToken public immutable volt;
    PriceFeed public immutable feed;
    MockAMM public immutable amm;

    mapping(address => Position) public positions;
    /// @notice USDX proceeds waiting for the user after an exit.
    mapping(address => uint256) public claimable;

    /// @notice Subscribed to by StopLossReactive (topic1 = user).
    event PositionOpened(
        address indexed user, uint256 entryPrice, uint256 voltAmount, uint32 stopLossBps, uint32 takeProfitBps
    );
    /// @notice Subscribed to by StopLossReactive so it stops tracking the user.
    event PositionClosed(address indexed user);
    /// @notice The visible end of the reactive loop on the destination chain.
    event ProtectionExecuted(
        address indexed user, uint8 kind, uint256 triggerPrice, uint256 executionPrice, uint256 usdxOut
    );
    event Withdrawn(address indexed user, uint256 amount);

    constructor(
        address callbackProxy_,
        address reactiveContract_,
        address usdx_,
        address volt_,
        address feed_,
        address amm_
    )
        payable
        AbstractCallback(IPayable(payable(callbackProxy_)), reactiveContract_)
    {
        usdx = MockToken(usdx_);
        volt = MockToken(volt_);
        feed = PriceFeed(feed_);
        amm = MockAMM(amm_);
    }

    /// @notice Open a protected position: spend `usdxAmount_` of USDX on VOLT
    ///         at the current feed price and arm the stop-loss / take-profit.
    /// @dev One open position per user keeps the demo (and the reactive
    ///      contract's bookkeeping) simple. Emits PositionOpened, which the
    ///      reactive contract uses to start tracking this position.
    function openPosition(uint256 usdxAmount_, uint32 stopLossBps_, uint32 takeProfitBps_) external {
        require(usdxAmount_ > 0, "GuardianVault: zero amount");
        require(stopLossBps_ > 0 && stopLossBps_ < 10_000, "GuardianVault: bad stop-loss");
        require(takeProfitBps_ > 0 && takeProfitBps_ < 100_000, "GuardianVault: bad take-profit");
        require(!positions[msg.sender].open, "GuardianVault: position already open");

        require(usdx.transferFrom(msg.sender, address(this), usdxAmount_), "GuardianVault: usdx in failed");
        require(usdx.approve(address(amm), usdxAmount_), "GuardianVault: approve failed");
        uint256 voltOut = amm.buyVolt(usdxAmount_);

        uint256 entry = feed.price();
        positions[msg.sender] = Position({
            voltAmount: voltOut, entryPrice: entry, stopLossBps: stopLossBps_, takeProfitBps: takeProfitBps_, open: true
        });
        emit PositionOpened(msg.sender, entry, voltOut, stopLossBps_, takeProfitBps_);
    }

    /// @notice Manual exit at the current price. The reactive contract sees
    ///         PositionClosed and stops tracking the position.
    function closePosition() external {
        Position storage pos = positions[msg.sender];
        require(pos.open, "GuardianVault: no open position");
        uint256 usdxOut = _exit(pos);
        _credit(msg.sender, usdxOut);
        emit PositionClosed(msg.sender);
    }

    /// @notice The callback entry point. Only the Base Sepolia callback proxy
    ///         may call this, and only on behalf of our reactive contract.
    /// @param reactive_ Overwritten by the network with the reactive
    ///        contract's address; checked by `onlyCallbackSender`.
    /// @param user_ The position owner to protect.
    /// @param triggerPrice_ The price the reactive contract observed when the
    ///        threshold broke (scaled by 1e8). Execution uses the live feed
    ///        price, which is also recorded so judges can compare the two.
    /// @param kind_ KIND_STOP_LOSS or KIND_TAKE_PROFIT.
    function protectPosition(address reactive_, address user_, uint256 triggerPrice_, uint8 kind_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        Position storage pos = positions[user_];
        require(pos.open, "GuardianVault: no open position");
        require(kind_ == KIND_STOP_LOSS || kind_ == KIND_TAKE_PROFIT, "GuardianVault: bad kind");
        uint256 executionPrice = feed.price();
        uint256 usdxOut = _exit(pos);
        _credit(user_, usdxOut);
        emit ProtectionExecuted(user_, kind_, triggerPrice_, executionPrice, usdxOut);
        emit PositionClosed(user_);
    }

    /// @notice Withdraw USDX proceeds credited by an exit.
    function withdraw() external {
        uint256 amount = claimable[msg.sender];
        require(amount > 0, "GuardianVault: nothing to withdraw");
        claimable[msg.sender] = 0;
        require(usdx.transfer(msg.sender, amount), "GuardianVault: transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Settles any callback debt from this contract's own balance so
    ///         the proxy resumes delivering callbacks. Open to anyone: paying
    ///         this contract's debt can only help its users.
    function coverDebt() external {
        _coverDebt();
    }

    /// @dev Sells the position's VOLT through the AMM and marks it closed.
    ///      Proceeds land in this contract's USDX balance; the caller credits
    ///      them to the user with `_credit`.
    function _exit(Position storage pos_) internal returns (uint256 usdxOut) {
        uint256 voltAmount = pos_.voltAmount;
        pos_.open = false;
        pos_.voltAmount = 0;
        require(volt.approve(address(amm), voltAmount), "GuardianVault: approve failed");
        usdxOut = amm.sellVolt(voltAmount);
    }

    function _credit(address user_, uint256 amount_) internal {
        claimable[user_] += amount_;
    }
}
