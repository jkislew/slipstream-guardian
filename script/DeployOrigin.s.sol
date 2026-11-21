// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { MockToken } from "../src/MockToken.sol";
import { PriceFeed } from "../src/PriceFeed.sol";
import { MockAMM } from "../src/MockAMM.sol";

/// @notice Step 1 (Base Sepolia, chain 84532): deploy the demo market —
///         USDX, VOLT, the price feed (starts at $100.00) and the AMM, and
///         seed the AMM with mock liquidity.
/// @dev Env: PRIVATE_KEY (deployer, funded with Base Sepolia ETH).
///      Run:
///        forge script script/DeployOrigin.s.sol --rpc-url base_sepolia \
///          --broadcast --private-key $PRIVATE_KEY
contract DeployOrigin is Script {
    function run() external {
        vm.startBroadcast();

        MockToken usdx = new MockToken("Mock USD", "USDX");
        MockToken volt = new MockToken("Volatile Token", "VOLT");
        PriceFeed feed = new PriceFeed(100e8);
        MockAMM amm = new MockAMM(address(usdx), address(volt), address(feed));

        usdx.mint(address(amm), 1_000_000 ether);
        volt.mint(address(amm), 1_000_000 ether);

        vm.stopBroadcast();

        console.log("USDX      :", address(usdx));
        console.log("VOLT      :", address(volt));
        console.log("PriceFeed :", address(feed));
        console.log("MockAMM   :", address(amm));
    }
}
