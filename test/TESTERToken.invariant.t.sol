// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "./lib/forge-std/src/Test.sol";
import {TESTERToken} from "../src/TESTERToken.sol";

/// @notice Drives the token with random, bounded call sequences from a small cast of actors and
/// keeps its own books so the invariants can compare the token's state against what every
/// successful call should have done. Failing calls (over balance, over allowance, zero address,
/// unknown selectors) are part of the sequence on purpose: they must leave no trace.
contract TESTERHandler is Test {
    TESTERToken public immutable token;
    address[] public actors;

    // Ghost books.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;
    uint256 public ghostMoved;
    uint256 public successfulTransfers;
    uint256 public successfulTransferFroms;
    uint256 public rejectedCalls;

    constructor(TESTERToken token_, address deployer, address[] memory others) {
        token = token_;
        actors.push(deployer);
        for (uint256 i; i < others.length; ++i) {
            actors.push(others[i]);
        }
        ghostBalance[deployer] = token_.totalSupply();
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "transfer returned false");
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostMoved += amount;
        ++successfulTransfers;
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = token.balanceOf(from);
        excess = bound(excess, 1, type(uint256).max - held);
        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, from, held, held + excess)
        );
        token.transfer(to, held + excess);
        ++rejectedCalls;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        ++rejectedCalls;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(from, spender);
        uint256 cap = allowed < token.balanceOf(from) ? allowed : token.balanceOf(from);
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostMoved += amount;
        ++successfulTransferFroms;
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(from, spender);
        if (allowed == type(uint256).max) return;
        excess = bound(excess, 1, type(uint256).max - allowed);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, spender, allowed, allowed + excess)
        );
        token.transferFrom(from, to, allowed + excess);
        ++rejectedCalls;
    }

    function transferFromOverBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = token.balanceOf(from);
        uint256 allowed = token.allowance(from, spender);
        if (allowed <= held) return;
        uint256 room = allowed == type(uint256).max ? type(uint256).max - held : allowed - held;
        excess = bound(excess, 1, room);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, from, held, held + excess)
        );
        token.transferFrom(from, to, held + excess);
        ++rejectedCalls;
    }

    /// @dev A stranger (not an actor) throws arbitrary calldata and ether at the token.
    function strangerCall(bytes4 selector, bytes calldata args, uint64 value) external {
        address stranger = address(uint160(uint256(keccak256(abi.encodePacked("stranger", selector)))));
        vm.deal(stranger, value);
        vm.prank(stranger);
        (bool ok,) = address(token).call{value: value}(abi.encodePacked(selector, args));
        ok;
        assertEq(token.balanceOf(stranger), 0, "stranger obtained tokens");
    }
}

/// @title Swarm Tester invariants
/// @notice The token keeps balances for everyone who holds it, so random call sequences must never
/// change the supply, never let the books disagree with the ledger, and never create or destroy a unit.
contract TESTERTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    TESTERToken internal token;
    TESTERHandler internal handler;
    address internal deployer = makeAddr("factory");

    function setUp() public {
        vm.prank(deployer);
        token = new TESTERToken();

        address[] memory others = new address[](5);
        others[0] = makeAddr("distributor");
        others[1] = POOL_MANAGER;
        others[2] = makeAddr("alice");
        others[3] = makeAddr("bob");
        others[4] = 0x000000000000000000000000000000000000dEaD;
        handler = new TESTERHandler(token, deployer, others);

        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 100
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY, "supply drifted");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 100
    function invariant_sumOfBalancesEqualsSupply() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY, "units were created or destroyed");
        assertEq(token.balanceOf(address(0)), 0, "zero address holds tokens");
        assertEq(token.balanceOf(address(token)), 0, "token holds tokens");
        assertEq(token.balanceOf(address(handler)), 0, "handler holds tokens");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 100
    function invariant_ledgerMatchesGhostBooks() public view {
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            address a = handler.actors(i);
            assertEq(token.balanceOf(a), handler.ghostBalance(a), "balance disagrees with successful calls");
            assertLe(token.balanceOf(a), SUPPLY, "a balance exceeds the supply");
            for (uint256 j; j < n; ++j) {
                address s = handler.actors(j);
                assertEq(token.allowance(a, s), handler.ghostAllowance(a, s), "allowance disagrees with approvals");
            }
        }
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 100
    function invariant_noAdminSurfaceAppeared() public view {
        // Nothing in any sequence can create an owner, a pause or a mint: the selectors do not exist.
        (bool ok,) = address(token).staticcall(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "owner() appeared");
        (ok,) = address(token).staticcall(abi.encodeWithSignature("paused()"));
        assertFalse(ok, "paused() appeared");
        assertEq(address(token).balance, 0, "token accepted ether");
    }
}
