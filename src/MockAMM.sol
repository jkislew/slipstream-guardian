// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { MockToken } from "./MockToken.sol";
import { PriceFeed } from "./PriceFeed.sol";

/// @title MockAMM
/// @notice A constant-price exchange for the demo market: swaps USDX <-> VOLT
///         at whatever price the PriceFeed currently reports. It stands in for
///         a real DEX pool so the demo has deterministic, always-available
///         liquidity; the guardian logic under test does not depend on AMM
///         internals, only on getting a fair fill at the feed price.
/// @dev Prices are scaled by 1e8. voltOut = usdxIn * 1e8 / price and
///      usdxOut = voltIn * price / 1e8. Both tokens use 18 decimals, so the
///      scaling is exact.
contract MockAMM {
    MockToken public immutable usdx;
    MockToken public immutable volt;
    PriceFeed public immutable feed;

    event Swapped(address indexed trader, bool boughtVolt, uint256 amountIn, uint256 amountOut, uint256 price);

    constructor(address usdx_, address volt_, address feed_) {
        usdx = MockToken(usdx_);
        volt = MockToken(volt_);
        feed = PriceFeed(feed_);
    }

    /// @notice Buy VOLT with USDX at the current feed price.
    /// @dev Caller must have approved this contract to spend USDX.
    function buyVolt(uint256 usdxIn_) external returns (uint256 voltOut) {
        uint256 p = feed.price();
        require(p > 0, "MockAMM: no price");
        voltOut = (usdxIn_ * 1e8) / p;
        require(voltOut > 0, "MockAMM: dust trade");
        require(usdx.transferFrom(msg.sender, address(this), usdxIn_), "MockAMM: usdx in failed");
        require(volt.transfer(msg.sender, voltOut), "MockAMM: volt out failed");
        emit Swapped(msg.sender, true, usdxIn_, voltOut, p);
    }

    /// @notice Sell VOLT for USDX at the current feed price.
    /// @dev Caller must have approved this contract to spend VOLT.
    function sellVolt(uint256 voltIn_) external returns (uint256 usdxOut) {
        uint256 p = feed.price();
        require(p > 0, "MockAMM: no price");
        usdxOut = (voltIn_ * p) / 1e8;
        require(usdxOut > 0, "MockAMM: dust trade");
        require(volt.transferFrom(msg.sender, address(this), voltIn_), "MockAMM: volt in failed");
        require(usdx.transfer(msg.sender, usdxOut), "MockAMM: usdx out failed");
        emit Swapped(msg.sender, false, voltIn_, usdxOut, p);
    }
}
