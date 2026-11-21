// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { GuardianVault } from "../src/GuardianVault.sol";

/// @notice Step 3 (Base Sepolia, chain 84532): deploy the GuardianVault,
///         authorizing the reactive contract deployed in step 2, and fund it
///         with Base Sepolia ETH so it can pay for its own callbacks.
/// @dev Env: PRIVATE_KEY, REACTIVE_ADDR (from DeployReactive),
///           USDX_ADDR, VOLT_ADDR, FEED_ADDR, AMM_ADDR (from DeployOrigin),
///           FUND_CALLBACK_ETH (wei sent with deployment, default 0.2 ether).
///      The Base Sepolia callback proxy is a protocol constant:
///      0x476F44b11F5C942c58f4c8E3d0300E5710743585 (dev.reactive.network).
///      Run:
///        forge script script/DeployVault.s.sol --rpc-url base_sepolia \
///          --broadcast --private-key $PRIVATE_KEY
contract DeployVault is Script {
    address internal constant BASE_SEPOLIA_CALLBACK_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    function run() external {
        address reactive = vm.envAddress("REACTIVE_ADDR");
        uint256 funding = vm.envOr("FUND_CALLBACK_ETH", uint256(0.2 ether));

        vm.startBroadcast();
        GuardianVault vault = new GuardianVault{ value: funding }(
            BASE_SEPOLIA_CALLBACK_PROXY,
            reactive,
            vm.envAddress("USDX_ADDR"),
            vm.envAddress("VOLT_ADDR"),
            vm.envAddress("FEED_ADDR"),
            vm.envAddress("AMM_ADDR")
        );
        vm.stopBroadcast();

        console.log("GuardianVault   :", address(vault));
        console.log("Funded (wei)    :", funding);
    }
}
