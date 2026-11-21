// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { MockToken } from "../src/MockToken.sol";
import { GuardianVault } from "../src/GuardianVault.sol";

/// @notice Demo step (Base Sepolia): the demo user claims test USDX from the
///         faucet and opens a protected position — 1,000 USDX into VOLT with
///         a -10% stop-loss and +25% take-profit by default.
/// @dev Env: PRIVATE_KEY (demo user), USDX_ADDR, VAULT_ADDR,
///           AMOUNT (wei, default 1000 ether), STOP_BPS (default 1000),
///           TARGET_BPS (default 2500).
contract OpenPosition is Script {
    function run() external {
        MockToken usdx = MockToken(vm.envAddress("USDX_ADDR"));
        GuardianVault vault = GuardianVault(payable(vm.envAddress("VAULT_ADDR")));
        uint256 amount = vm.envOr("AMOUNT", uint256(1000 ether));
        uint32 stop = uint32(vm.envOr("STOP_BPS", uint256(1000)));
        uint32 target = uint32(vm.envOr("TARGET_BPS", uint256(2500)));

        vm.startBroadcast();
        if (usdx.balanceOf(msg.sender) < amount) {
            usdx.faucet();
        }
        usdx.approve(address(vault), amount);
        vault.openPosition(amount, stop, target);
        vm.stopBroadcast();

        console.log("Position opened.");
        console.log("  amount (wei):", amount);
        console.log("  stop bps    :", stop);
        console.log("  target bps  :", target);
    }
}
