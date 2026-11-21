// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { MockToken } from "../src/MockToken.sol";
import { PriceFeed } from "../src/PriceFeed.sol";
import { MockAMM } from "../src/MockAMM.sol";
import { GuardianVault } from "../src/GuardianVault.sol";
import { StopLossReactive } from "../src/StopLossReactive.sol";
import { MockSystemContract } from "./MockSystemContract.sol";

/// @notice End-to-end simulation of the event -> react -> callback loop on a
///         single local chain. Cross-chain deliveries are reproduced by
///         pranking the two real network actors:
///           - reactive deliveries come from the system contract
///             0x8888888888888888888888888888888888888888 (onlySystem check)
///           - callback deliveries come from the Base Sepolia callback proxy
///             0x476F44b11F5C942c58f4c8E3d0300E5710743585 (onlyServiceProvider)
///         On the live networks the Reactive Network itself plays both roles;
///         the contract code under test is byte-identical either way.
contract GuardianLoopTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    address internal constant BASE_SEPOLIA_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    uint256 internal constant PRICE_TOPIC0 = uint256(keccak256("PriceUpdated(uint256,uint256)"));
    uint256 internal constant OPENED_TOPIC0 =
        uint256(keccak256("PositionOpened(address,uint256,uint256,uint32,uint32)"));
    uint256 internal constant CLOSED_TOPIC0 = uint256(keccak256("PositionClosed(address)"));

    MockToken internal usdx;
    MockToken internal volt;
    PriceFeed internal feed;
    MockAMM internal amm;
    GuardianVault internal vault;
    StopLossReactive internal reactive;
    MockSystemContract internal mockSystem;

    address internal user = address(0xA11CE);

    function setUp() public {
        // Put a recording stand-in for the system contract at its real
        // address so constructor subscriptions succeed locally.
        mockSystem = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(mockSystem).code);

        usdx = new MockToken("Mock USD", "USDX");
        volt = new MockToken("Volatile Token", "VOLT");
        feed = new PriceFeed(100e8); // $100.00
        amm = new MockAMM(address(usdx), address(volt), address(feed));
        usdx.mint(address(amm), 1_000_000 ether);
        volt.mint(address(amm), 1_000_000 ether);

        reactive = new StopLossReactive{ value: 1 ether }(address(feed));
        vault = new GuardianVault{ value: 1 ether }(
            BASE_SEPOLIA_PROXY, address(reactive), address(usdx), address(volt), address(feed), address(amm)
        );
        reactive.setVault(address(vault));

        vm.deal(user, 1 ether);
        vm.prank(user);
        usdx.faucet(); // 10,000 USDX
    }

    // ---- helpers -----------------------------------------------------------

    function _record(address emitter_, uint256 topic0_, uint256 topic1_, bytes memory data_, uint256 opCode_)
        internal
        view
        returns (IReactive.LogRecord memory rec)
    {
        rec.chainId = 84532;
        rec.contractAddress = emitter_;
        rec.topic0 = topic0_;
        rec.topic1 = topic1_;
        rec.data = data_;
        rec.blockNumber = block.number;
        rec.opCode = opCode_;
    }

    function _openPosition() internal returns (uint256 entry, uint256 voltOut) {
        vm.startPrank(user);
        usdx.approve(address(vault), 1_000 ether);
        vault.openPosition(1_000 ether, 1000, 2500); // -10% stop, +25% target
        vm.stopPrank();
        (voltOut, entry,,,) = vault.positions(user);
    }

    function _deliverOpened() internal {
        (uint256 voltOut, uint256 entry, uint32 sl, uint32 tp,) = vault.positions(user);
        IReactive.LogRecord memory rec = _record(
            address(vault),
            OPENED_TOPIC0,
            uint256(uint160(user)),
            abi.encode(entry, voltOut, sl, tp),
            2 // LOG2: topic0 + indexed user
        );
        vm.prank(SYSTEM_ADDR);
        reactive.react(rec);
    }

    function _deliverPrice(uint256 price_) internal {
        IReactive.LogRecord memory rec =
            _record(address(feed), PRICE_TOPIC0, 0, abi.encode(price_, block.timestamp), 1);
        vm.prank(SYSTEM_ADDR);
        reactive.react(rec);
    }

    // ---- tests -------------------------------------------------------------

    function test_openPosition_buysVoltAtFeedPrice() public {
        (uint256 entry, uint256 voltOut) = _openPosition();
        assertEq(entry, 100e8);
        assertEq(voltOut, 10 ether); // 1,000 USDX at $100
        assertEq(volt.balanceOf(address(vault)), 10 ether);
    }

    function test_reactive_tracksPositionOnOpenedEvent() public {
        _openPosition();
        _deliverOpened();
        (uint256 entry, uint32 sl, uint32 tp, bool known, bool active) = reactive.tracked(user);
        assertEq(entry, 100e8);
        assertEq(sl, 1000);
        assertEq(tp, 2500);
        assertTrue(known);
        assertTrue(active);
        assertEq(reactive.trackedUsers(), 1);
    }

    function test_priceInsideBand_doesNothing() public {
        _openPosition();
        _deliverOpened();
        _deliverPrice(95e8); // -5%, inside the band
        assertEq(reactive.triggers(), 0);
        (,,,, bool active) = reactive.tracked(user);
        assertTrue(active);
    }

    function test_stopLoss_fullLoop() public {
        _openPosition();
        _deliverOpened();

        feed.setPrice(89e8); // -11% -> breaches the -10% stop
        _deliverPrice(89e8);

        // Reactive side: fired exactly once and stopped tracking.
        assertEq(reactive.triggers(), 1);
        (,,,, bool active) = reactive.tracked(user);
        assertFalse(active);

        // The system contract recorded exactly one callback request, aimed at
        // the vault on Base Sepolia, first payload arg left as the address(0)
        // placeholder the network overwrites with the reactive address.
        // (State is read at SYSTEM_ADDR: etched code runs with that storage.)
        MockSystemContract system = MockSystemContract(SYSTEM_ADDR);
        assertEq(system.callbackCount(), 1);
        (uint256 cbChain, address cbRecipient,, bytes memory cbPayload) = system.lastCallback();
        assertEq(cbChain, 84532);
        assertEq(cbRecipient, address(vault));
        bytes memory expectedPayload =
            abi.encodeWithSignature("protectPosition(address,address,uint256,uint8)", address(0), user, 89e8, 0);
        assertEq(keccak256(cbPayload), keccak256(expectedPayload));

        // A second, deeper price update must not fire again.
        _deliverPrice(80e8);
        assertEq(reactive.triggers(), 1);

        // Destination side: the network (pranked proxy) delivers the callback.
        vm.prank(BASE_SEPOLIA_PROXY);
        vault.protectPosition(address(reactive), user, 89e8, 0);

        // 10 VOLT sold at $89 -> 890 USDX claimable, position closed.
        assertEq(vault.claimable(user), 890 ether);
        (uint256 voltAmt,,,, bool open) = vault.positions(user);
        assertEq(voltAmt, 0);
        assertFalse(open);

        uint256 before = usdx.balanceOf(user);
        vm.prank(user);
        vault.withdraw();
        assertEq(usdx.balanceOf(user), before + 890 ether);
    }

    function test_takeProfit_fullLoop() public {
        _openPosition();
        _deliverOpened();

        feed.setPrice(126e8); // +26% -> breaches the +25% target
        _deliverPrice(126e8);
        assertEq(reactive.triggers(), 1);

        vm.prank(BASE_SEPOLIA_PROXY);
        vault.protectPosition(address(reactive), user, 126e8, 1);

        assertEq(vault.claimable(user), 1260 ether); // 10 VOLT at $126
    }

    function test_manualClose_untracksPosition() public {
        _openPosition();
        _deliverOpened();

        vm.prank(user);
        vault.closePosition();
        assertEq(vault.claimable(user), 1000 ether); // price unchanged

        IReactive.LogRecord memory rec =
            _record(address(vault), CLOSED_TOPIC0, uint256(uint160(user)), bytes(""), 2);
        vm.prank(SYSTEM_ADDR);
        reactive.react(rec);

        (,,,, bool active) = reactive.tracked(user);
        assertFalse(active);

        // Later crashes are no longer our problem.
        _deliverPrice(50e8);
        assertEq(reactive.triggers(), 0);
    }

    function test_callback_fromStranger_reverts() public {
        _openPosition();
        vm.expectRevert();
        vault.protectPosition(address(reactive), user, 89e8, 0);
    }

    function test_callback_withWrongReactiveSender_reverts() public {
        _openPosition();
        vm.prank(BASE_SEPOLIA_PROXY);
        vm.expectRevert();
        vault.protectPosition(address(0xBEEF), user, 89e8, 0);
    }

    function test_react_fromNonSystem_reverts() public {
        IReactive.LogRecord memory rec =
            _record(address(feed), PRICE_TOPIC0, 0, abi.encode(89e8, block.timestamp), 1);
        vm.expectRevert();
        reactive.react(rec);
    }
}
