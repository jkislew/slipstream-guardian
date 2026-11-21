// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { StopLossReactive } from "../src/StopLossReactive.sol";

/// @notice Step 4 (Reactive Lasna, chain 5318007): wire the vault into the
///         reactive contract. This subscribes the reactive contract to the
///         vault's PositionOpened / PositionClosed events on Base Sepolia.
/// @dev Env: PRIVATE_KEY (must be the reactive contract's owner),
///           REACTIVE_ADDR, VAULT_ADDR.
///      Run:
///        forge script script/SetVault.s.sol --rpc-url lasna \
///          --broadcast --private-key $PRIVATE_KEY
contract SetVault is Script {
    function run() external {
        StopLossReactive reactive = StopLossReactive(payable(vm.envAddress("REACTIVE_ADDR")));
        address vault = vm.envAddress("VAULT_ADDR");

        vm.startBroadcast();
        reactive.setVault(vault);
        vm.stopBroadcast();

        console.log("Vault wired into reactive contract:", vault);
    }
}
