// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { StopLossReactive } from "../src/StopLossReactive.sol";

/// @notice Step 2 (Reactive Lasna, chain 5318007): deploy the reactive
///         contract, funded with lREACT so it can pay for reactive
///         transactions from the start.
/// @dev Env: PRIVATE_KEY (deployer, funded with lREACT),
///           FEED_ADDR (PriceFeed on Base Sepolia, from DeployOrigin),
///           FUND_LREACT (wei to send with deployment, default 5 ether).
///      Run:
///        forge script script/DeployReactive.s.sol --rpc-url lasna \
///          --broadcast --private-key $PRIVATE_KEY
contract DeployReactive is Script {
    function run() external {
        address feed = vm.envAddress("FEED_ADDR");
        uint256 funding = vm.envOr("FUND_LREACT", uint256(5 ether));

        vm.startBroadcast();
        StopLossReactive reactive = new StopLossReactive{ value: funding }(feed);
        vm.stopBroadcast();

        console.log("StopLossReactive:", address(reactive));
        console.log("Funded (wei)    :", funding);
    }
}
