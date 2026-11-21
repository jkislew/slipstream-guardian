// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title PriceFeed
/// @notice A deliberately simple price oracle for the demo market on Base Sepolia.
/// @dev The owner (demo operator) sets the VOLT price; every update emits
///      `PriceUpdated`, which is the origin event the reactive contract on
///      Reactive Lasna subscribes to. In production this role would be played
///      by a DEX pool `Sync` event or a Chainlink aggregator; the reactive
///      wiring is identical, only the subscribed contract/topic changes.
///      Prices are scaled by 1e8 (Chainlink-style): $100.00 == 100e8.
contract PriceFeed {
    address public owner;
    uint256 public price; // scaled by 1e8

    /// @notice The origin event of the whole system. Topic0 is subscribed to
    ///         by StopLossReactive on Lasna (chain 5318007).
    event PriceUpdated(uint256 price, uint256 updatedAt);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "PriceFeed: not owner");
        _;
    }

    constructor(uint256 initialPrice_) {
        require(initialPrice_ > 0, "PriceFeed: zero price");
        owner = msg.sender;
        price = initialPrice_;
        emit PriceUpdated(initialPrice_, block.timestamp);
    }

    /// @notice Push a new price. Emits the event Reactive is watching for.
    function setPrice(uint256 newPrice_) external onlyOwner {
        require(newPrice_ > 0, "PriceFeed: zero price");
        price = newPrice_;
        emit PriceUpdated(newPrice_, block.timestamp);
    }

    function transferOwnership(address newOwner_) external onlyOwner {
        require(newOwner_ != address(0), "PriceFeed: zero address");
        emit OwnershipTransferred(owner, newOwner_);
        owner = newOwner_;
    }
}
