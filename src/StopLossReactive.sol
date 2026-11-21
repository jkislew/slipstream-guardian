// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title StopLossReactive
/// @notice The reactive contract, deployed on Reactive Lasna (chain 5318007).
///         It watches a demo market on Base Sepolia (chain 84532) and protects
///         GuardianVault positions the moment their stop-loss or take-profit
///         breaks — no keeper bot, no polling, no one awake at 3 a.m.
///
///         Subscriptions (all on Base Sepolia):
///           - PriceFeed.PriceUpdated        -> evaluate every tracked position
///           - GuardianVault.PositionOpened  -> start tracking a position
///           - GuardianVault.PositionClosed  -> stop tracking a position
///
///         On a breach it asks the system contract to post a callback to
///         GuardianVault.protectPosition() on Base Sepolia. This contract
///         pays for its reactive transactions in lREACT, so it is deployed
///         with funding and exposes `coverDebt()`.
contract StopLossReactive is AbstractReactive {
    uint256 public constant ORIGIN_CHAIN_ID = 84532; // Base Sepolia
    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    uint8 public constant KIND_STOP_LOSS = 0;
    uint8 public constant KIND_TAKE_PROFIT = 1;

    // Topic0 values of the subscribed events.
    uint256 private constant PRICE_UPDATED_TOPIC0 =
        uint256(keccak256("PriceUpdated(uint256,uint256)"));
    uint256 private constant POSITION_OPENED_TOPIC0 =
        uint256(keccak256("PositionOpened(address,uint256,uint256,uint32,uint32)"));
    uint256 private constant POSITION_CLOSED_TOPIC0 = uint256(keccak256("PositionClosed(address)"));

    struct Tracked {
        uint256 entryPrice; // scaled by 1e8
        uint32 stopLossBps;
        uint32 takeProfitBps;
        bool known; // user has been seen at least once (array bookkeeping)
        bool active; // position currently open
    }

    address public owner;
    address public immutable feed;
    address public vault;

    mapping(address => Tracked) public tracked;
    address[] public users;

    uint256 public reactions; // total react() deliveries
    uint256 public triggers; // total protection callbacks requested
    uint256 public lastPrice; // last observed price, scaled by 1e8

    event PositionTracked(address indexed user, uint256 entryPrice, uint32 stopLossBps, uint32 takeProfitBps);
    event PositionUntracked(address indexed user);
    event ProtectionTriggered(address indexed user, uint8 kind, uint256 triggerPrice, uint256 entryPrice);
    event VaultSet(address indexed vault);

    modifier onlyOwner() {
        require(msg.sender == owner, "StopLossReactive: not owner");
        _;
    }

    /// @param feed_ PriceFeed address on Base Sepolia.
    /// @dev Payable so the contract starts life funded: reactive transactions
    ///      are billed to this contract in lREACT.
    constructor(address feed_) payable {
        owner = msg.sender;
        feed = feed_;
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID, feed_, PRICE_UPDATED_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @notice Second deployment step: point at the GuardianVault on Base
    ///         Sepolia and subscribe to its position events. The vault had to
    ///         be deployed after this contract (it authorizes this address
    ///         immutably), so the wiring cannot happen in the constructor.
    function setVault(address vault_) external onlyOwner {
        require(vault_ != address(0), "StopLossReactive: zero vault");
        require(vault == address(0), "StopLossReactive: vault already set");
        vault = vault_;
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID, vault_, POSITION_OPENED_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID, vault_, POSITION_CLOSED_TOPIC0, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        emit VaultSet(vault_);
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        reactions++;
        if (log_.topic0 == PRICE_UPDATED_TOPIC0) {
            (uint256 price,) = abi.decode(log_.data, (uint256, uint256));
            lastPrice = price;
            _evaluate(price);
        } else if (log_.topic0 == POSITION_OPENED_TOPIC0) {
            address user = address(uint160(log_.topic1));
            (uint256 entryPrice,, uint32 stopLossBps, uint32 takeProfitBps) =
                abi.decode(log_.data, (uint256, uint256, uint32, uint32));
            Tracked storage t = tracked[user];
            if (!t.known) {
                t.known = true;
                users.push(user);
            }
            t.entryPrice = entryPrice;
            t.stopLossBps = stopLossBps;
            t.takeProfitBps = takeProfitBps;
            t.active = true;
            emit PositionTracked(user, entryPrice, stopLossBps, takeProfitBps);
        } else if (log_.topic0 == POSITION_CLOSED_TOPIC0) {
            address user = address(uint160(log_.topic1));
            if (tracked[user].active) {
                tracked[user].active = false;
                emit PositionUntracked(user);
            }
        }
        // Anything else falls through silently: reverting here would still
        // bill this contract for the delivery (see Reactive docs).
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    function trackedUsers() external view returns (uint256) {
        return users.length;
    }

    /// @dev Threshold math is cross-multiplied to avoid precision loss:
    ///      stop-loss  triggers when price * 10_000 <= entry * (10_000 - slBps)
    ///      take-profit triggers when price * 10_000 >= entry * (10_000 + tpBps)
    function _evaluate(uint256 price_) internal {
        uint256 count = users.length;
        for (uint256 i = 0; i < count; i++) {
            address user = users[i];
            Tracked storage t = tracked[user];
            if (!t.active) continue;

            uint8 kind;
            bool hit;
            if (price_ * 10_000 <= t.entryPrice * (10_000 - t.stopLossBps)) {
                kind = KIND_STOP_LOSS;
                hit = true;
            } else if (price_ * 10_000 >= t.entryPrice * (10_000 + t.takeProfitBps)) {
                kind = KIND_TAKE_PROFIT;
                hit = true;
            }
            if (!hit) continue;

            // Mark inactive BEFORE requesting the callback so a burst of
            // price updates can never double-fire protection for one position.
            t.active = false;
            triggers++;
            emit ProtectionTriggered(user, kind, price_, t.entryPrice);
            _requestProtection(user, price_, kind);
        }
    }

    function _requestProtection(address user_, uint256 price_, uint8 kind_) internal {
        // The first payload argument is reserved: the network overwrites it
        // with this contract's address so the vault can authenticate us.
        bytes memory payload = abi.encodeWithSignature(
            "protectPosition(address,address,uint256,uint8)", address(0), user_, price_, kind_
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: ORIGIN_CHAIN_ID, recipient: vault, gasLimit: CALLBACK_GAS_LIMIT, payload: payload
            })
        );
    }
}
