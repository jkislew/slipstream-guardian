// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { PriceFeed } from "../src/PriceFeed.sol";

/// @notice Demo step (Base Sepolia): move the market. Setting the price below
///         the stop (e.g. NEW_PRICE=8900000000 for $89.00 from a $100 entry
///         with a -10% stop) is the origin event that starts the reactive
///         loop. Record this transaction's hash — it is leg 1 of the latency
///         measurement.
/// @dev Env: PRIVATE_KEY (feed owner), FEED_ADDR, NEW_PRICE (1e8-scaled).
contract MovePrice is Script {
    function run() external {
        PriceFeed feed = PriceFeed(vm.envAddress("FEED_ADDR"));
        uint256 newPrice = vm.envUint("NEW_PRICE");

        vm.startBroadcast();
        feed.setPrice(newPrice);
        vm.stopBroadcast();

        console.log("Price set to (1e8-scaled):", newPrice);
    }
}
