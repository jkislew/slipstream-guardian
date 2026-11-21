// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";

/// @notice Test double for the Reactive system contract, etched onto the real
///         system address (0x8888...8888) in unit tests. On Lasna the genuine
///         system contract lives there; locally it records subscriptions and
///         callback requests so tests can assert exactly what the reactive
///         contract asked the network to do, then deliver the callback the
///         way the network would.
contract MockSystemContract {
    struct Recorded {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    Recorded public lastCallback;
    uint256 public callbackCount;
    uint256 public subscriptionCount;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscriptionCount++;
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external { }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        lastCallback = Recorded({
            chainId: config_.chainId, recipient: config_.recipient, gasLimit: config_.gasLimit, payload: config_.payload
        });
        callbackCount++;
    }

    function requestCallback(ISystemContract.CallbackVersion, bytes memory) external {
        callbackCount++;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }
}
