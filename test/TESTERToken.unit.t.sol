// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "./lib/forge-std/src/Test.sol";
import {Vm} from "./lib/forge-std/src/Vm.sol";
import {TESTERToken} from "../src/TESTERToken.sol";

/// @title Swarm Tester (TESTER) unit and property tests
/// @notice Every rule in the brief, read adversarially: fixed 1e27 supply minted once to the
/// deployer, no mint afterwards, plain ERC-20 transfers with no fee, tax or limit, no owner and no
/// admin surface. Each rule is checked on its failure path as well as its happy path.
contract TESTERTokenUnitTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address internal constant REMAINDER_TO = 0x000000000000000000000000000000000000dEaD;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    TESTERToken internal token;
    address internal deployer = makeAddr("factory");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        vm.prank(deployer);
        token = new TESTERToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Supply: 1,000,000,000 * 1e18 minted once, to whoever deploys, and never again.
    // ---------------------------------------------------------------------------------------------

    function test_constructorMintsWholeSupplyToDeployerOnly() public view {
        assertEq(token.totalSupply(), SUPPLY, "supply is not 1e27");
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer did not receive 100%");
        assertEq(token.balanceOf(address(token)), 0, "token kept something");
        assertEq(token.balanceOf(address(this)), 0, "test contract was credited");
        assertEq(token.balanceOf(address(0)), 0, "zero address was credited");
    }

    function test_constructorEmitsMintTransferFromZero() public {
        address other = makeAddr("other-deployer");
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), other, SUPPLY);
        vm.prank(other);
        TESTERToken fresh = new TESTERToken();
        assertEq(fresh.balanceOf(other), SUPPLY, "a second deployment mints to its own deployer");
        assertEq(fresh.totalSupply(), SUPPLY);
        // Independent instance: the first deployment's balances are untouched.
        assertEq(token.balanceOf(other), 0);
    }

    function test_metadataIsFixedAsTheBriefStates() public view {
        assertEq(token.name(), "Swarm Tester");
        assertEq(token.symbol(), "TESTER");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000e18);
    }

    /// @dev A contract with no mint, no burn, no owner, no pause: every common admin selector must
    /// be absent, which on a contract without a fallback means the call reverts and nothing moves.
    function test_noAdminOrMintSelectorExists() public {
        string[24] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burn(address,uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "setOwner(address)",
            "pause()",
            "unpause()",
            "paused()",
            "blacklist(address)",
            "setBlacklist(address,bool)",
            "freeze(address)",
            "setFee(uint256)",
            "setTaxRate(uint256)",
            "setMaxTx(uint256)",
            "setMaxWallet(uint256)",
            "upgradeTo(address)",
            "upgradeToAndCall(address,bytes)",
            "initialize(address)",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, type(uint128).max);
            // From a stranger and from the deployer, the only address a token would plausibly trust.
            vm.prank(stranger);
            (bool okStranger,) = address(token).call(data);
            assertFalse(okStranger, string.concat("stranger reached: ", signatures[i]));
            vm.prank(deployer);
            (bool okDeployer,) = address(token).call(data);
            assertFalse(okDeployer, string.concat("deployer reached: ", signatures[i]));
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(deployer), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(alice), 0, signatures[i]);
        }
    }

    function test_noFallbackAndNoReceive() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool okEth,) = address(token).call{value: 1 wei}("");
        assertFalse(okEth, "token accepted ether");
        (bool okEmpty,) = address(token).call("");
        assertFalse(okEmpty, "token has a fallback");
        (bool okGarbage,) = address(token).call(hex"deadbeef");
        assertFalse(okGarbage, "unknown selector did not revert");
        assertEq(address(token).balance, 0);
    }

    /// @dev Pure ERC-20: no DELEGATECALL, CALLCODE, SELFDESTRUCT, and (as the implementation
    /// documents) no outgoing calls or contract creation either. Scans the runtime, skipping PUSH data.
    function test_runtimeContainsNoDangerousOrExternalCallOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL present");
            assertTrue(op != 0xF2, "CALLCODE present");
            assertTrue(op != 0xFF, "SELFDESTRUCT present");
            assertTrue(op != 0xF1, "CALL present");
            assertTrue(op != 0xFA, "STATICCALL present");
            assertTrue(op != 0xF0, "CREATE present");
            assertTrue(op != 0xF5, "CREATE2 present");
        }
    }

    // ---------------------------------------------------------------------------------------------
    // transfer: exact amounts, no fee, no limit; failure paths leave state untouched.
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit Transfer(deployer, alice, 123_456_789e18);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123_456_789e18));
        assertEq(token.balanceOf(alice), 123_456_789e18, "recipient short-changed");
        assertEq(token.balanceOf(deployer), SUPPLY - 123_456_789e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireBalanceThenSenderHasExactlyZero() public {
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        // The emptied account can still send zero and still cannot send one.
        vm.prank(deployer);
        assertTrue(token.transfer(bob, 0));
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transfer(bob, 1);
    }

    function test_transferOneMoreThanBalanceRevertsExactlyAtTheBoundary() public {
        vm.prank(deployer);
        token.transfer(alice, 1000);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1000), "exact balance must be spendable");
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, bob, 1000, 1001));
        token.transfer(alice, 1001);
        assertEq(token.balanceOf(bob), 1000, "failed transfer changed sender");
        assertEq(token.balanceOf(alice), 0, "failed transfer changed recipient");
    }

    function test_transferToZeroAddressRevertsEvenForZeroValue() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY, "a transfer to zero must not act as a burn");
    }

    function test_selfTransferIsNeutralAndEmits() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY, "self transfer changed the balance");
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(deployer, SUPPLY + 1);
    }

    function test_zeroValueTransferFromEmptyAccountSucceedsAndEmits() public {
        vm.expectEmit(true, true, true, true, address(token));
        emit Transfer(stranger, alice, 0);
        vm.prank(stranger);
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(alice), 0);
    }

    function test_noFeeTaxOrLimitOnLaunchAndPoolFlows() public {
        // The factory's three flows: 10% to the distributor, 90% to the pool manager, the rest to dead.
        address distributor = makeAddr("distributor");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 9000 / 10_000;
        vm.startPrank(deployer);
        token.transfer(distributor, swarm);
        token.transfer(POOL_MANAGER, pool);
        token.transfer(REMAINDER_TO, token.balanceOf(deployer));
        vm.stopPrank();
        assertEq(token.balanceOf(distributor), swarm, "swarm share arrived short");
        assertEq(token.balanceOf(POOL_MANAGER), pool, "pool seed arrived short");
        assertEq(token.balanceOf(REMAINDER_TO), 0, "nominal shares consume the whole supply");
        assertEq(token.balanceOf(deployer), 0);
        // The pool manager can hand every unit back out; a claimant receives a claim whole.
        vm.prank(POOL_MANAGER);
        token.transfer(alice, pool);
        vm.prank(distributor);
        token.transfer(bob, swarm);
        assertEq(token.balanceOf(alice), pool);
        assertEq(token.balanceOf(bob), swarm);
        assertEq(token.balanceOf(POOL_MANAGER), 0);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), SUPPLY);
        // Dust-sized and whale-sized transfers behave the same: 1 wei moves 1 wei.
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), swarm + 1);
        assertEq(token.balanceOf(alice), pool - 1);
    }

    function test_transferToTokenContractIsAllowedAndIrrecoverable() public {
        // Plain ERC-20: nothing stops a holder from sending to the token itself, and the
        // contract has no function that could ever move that balance again. Documented, not a defect.
        vm.prank(deployer);
        token.transfer(address(token), 5);
        assertEq(token.balanceOf(address(token)), 5);
        vm.prank(address(token));
        assertTrue(token.transfer(alice, 5), "only the contract itself could move it, and it never calls");
    }

    // ---------------------------------------------------------------------------------------------
    // approve / transferFrom: allowance semantics and their failure paths.
    // ---------------------------------------------------------------------------------------------

    function test_approveReplacesRatherThanAccumulates() public {
        vm.startPrank(alice);
        token.approve(spender, 100);
        token.approve(spender, 40);
        assertEq(token.allowance(alice, spender), 40, "approve must overwrite");
        token.approve(spender, 0);
        assertEq(token.allowance(alice, spender), 0, "approve(0) must clear");
        vm.stopPrank();
        // Allowances are per (owner, spender) pair only.
        assertEq(token.allowance(spender, alice), 0);
        assertEq(token.allowance(alice, alice), 0);
    }

    function test_approveDoesNotRequireABalanceOrAlterOne() public {
        vm.prank(stranger);
        assertTrue(token.approve(spender, SUPPLY * 2));
        assertEq(token.allowance(stranger, spender), SUPPLY * 2, "allowance may exceed balance and supply");
        assertEq(token.balanceOf(stranger), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, stranger, 0, 1));
        token.transferFrom(stranger, alice, 1);
        assertEq(token.allowance(stranger, spender), SUPPLY * 2, "failed spend must not consume allowance");
    }

    function test_approveZeroSpenderReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_transferFromExactAllowanceSpendsToZero() public {
        vm.prank(deployer);
        token.approve(spender, 777);
        vm.expectEmit(true, true, true, true, address(token));
        emit Transfer(deployer, bob, 777);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 777));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(bob), 777);
        assertEq(token.balanceOf(deployer), SUPPLY - 777);
        // Zero-value spend is still allowed with a zero allowance; one unit is not.
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 0));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromOneOverAllowanceRevertsAndKeepsAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 500);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, spender, 500, 501));
        token.transferFrom(deployer, bob, 501);
        assertEq(token.allowance(deployer, spender), 500);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromPartialSpendsDecrementAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 1000);
        vm.startPrank(spender);
        token.transferFrom(deployer, alice, 300);
        assertEq(token.allowance(deployer, spender), 700);
        token.transferFrom(deployer, bob, 700);
        assertEq(token.allowance(deployer, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, bob, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), 1000);
    }

    function test_unlimitedAllowanceIsNotConsumedButMaxMinusOneIs() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(deployer, alice, SUPPLY / 2);
        assertEq(token.allowance(deployer, spender), type(uint256).max, "unlimited allowance was consumed");

        vm.prank(alice);
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max - 2, "max-1 is a finite allowance");
    }

    function test_transferFromDoesNotEmitApprovalOnConsumption() public {
        vm.prank(deployer);
        token.approve(spender, 10);
        vm.recordLogs();
        vm.prank(spender);
        token.transferFrom(deployer, alice, 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event per transferFrom");
        assertEq(logs[0].topics[0], Transfer.selector);
        assertEq(address(uint160(uint256(logs[0].topics[1]))), deployer);
        assertEq(address(uint160(uint256(logs[0].topics[2]))), alice);
        assertEq(abi.decode(logs[0].data, (uint256)), 4);
    }

    function test_transferFromToZeroRevertsAfterAllowanceCheck() public {
        vm.prank(deployer);
        token.approve(spender, 10);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 1);
        assertEq(token.allowance(deployer, spender), 10, "reverted spend must not consume allowance");
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromTheZeroAddressRevertsEvenForZeroValue() public {
        // allowance[0][spender] is 0, so a zero-value pull passes the allowance check and must
        // still be refused as an invalid sender.
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function test_holderMayPullFromThemselvesOnlyThroughAnAllowance() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
        vm.prank(deployer);
        token.approve(deployer, 5);
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 5));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(alice), 5);
    }

    function test_nobodyCanSpendAHolderWithoutThatHoldersApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 1e18);
        // Deployer, a stranger and the pool manager all lack an allowance from alice.
        address[3] memory callers = [deployer, stranger, POOL_MANAGER];
        for (uint256 i; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, callers[i], 0, 1));
            token.transferFrom(alice, callers[i], 1);
        }
        // An allowance to one spender is not an allowance to another.
        vm.prank(alice);
        token.approve(spender, 1e18);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, stranger, 0, 1e18));
        token.transferFrom(alice, stranger, 1e18);
        assertEq(token.balanceOf(alice), 1e18);
    }

    // ---------------------------------------------------------------------------------------------
    // Property tests over the arithmetic and over arbitrary calldata.
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupplyAndMovesExactly(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), toBefore + amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
            assertEq(token.balanceOf(to) + token.balanceOf(deployer), SUPPLY);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceAlwaysReverts(uint256 held, uint256 attempt) public {
        held = bound(held, 0, SUPPLY);
        attempt = bound(attempt, held + 1, type(uint256).max);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, alice, held, attempt));
        token.transfer(bob, attempt);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzz_allowanceAccounting(uint256 allowed, uint256 spend) public {
        allowed = bound(allowed, 0, type(uint256).max);
        spend = bound(spend, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(spender, allowed);
        assertEq(token.allowance(deployer, spender), allowed, "approve stores the value verbatim");
        vm.prank(spender);
        if (spend > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, spender, allowed, spend)
            );
            token.transferFrom(deployer, alice, spend);
            assertEq(token.allowance(deployer, spender), allowed);
            assertEq(token.balanceOf(alice), 0);
            return;
        }
        assertTrue(token.transferFrom(deployer, alice, spend));
        assertEq(token.balanceOf(alice), spend);
        assertEq(token.balanceOf(deployer), SUPPLY - spend);
        if (allowed == type(uint256).max) {
            assertEq(token.allowance(deployer, spender), type(uint256).max);
        } else {
            assertEq(token.allowance(deployer, spender), allowed - spend);
        }
    }

    function testFuzz_roundTripBetweenHoldersLosesNothing(uint256 amount, uint8 hops) public {
        amount = bound(amount, 0, SUPPLY);
        hops = uint8(bound(hops, 1, 16));
        address[3] memory ring = [alice, bob, POOL_MANAGER];
        vm.prank(deployer);
        token.transfer(ring[0], amount);
        for (uint256 i; i < hops; ++i) {
            address from = ring[i % 3];
            address to = ring[(i + 1) % 3];
            vm.prank(from);
            token.transfer(to, amount);
            assertEq(token.balanceOf(from), 0);
            assertEq(token.balanceOf(to), amount);
        }
        assertEq(token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(POOL_MANAGER), amount);
        assertEq(token.balanceOf(deployer) + amount, SUPPLY);
    }

    /// @dev Whatever a stranger sends to the token, the supply and every balance it does not own
    /// stay put. Covers unknown selectors, approve from a stranger, and zero-value pulls alike.
    function testFuzz_arbitraryCalldataFromAStrangerMovesNothing(bytes4 selector, bytes calldata args, uint96 value)
        public
    {
        vm.prank(deployer);
        token.transfer(alice, 1e24);
        vm.deal(stranger, value);
        vm.prank(stranger);
        (bool ok,) = address(token).call{value: value}(abi.encodePacked(selector, args));
        ok;
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
        assertEq(token.balanceOf(deployer), SUPPLY - 1e24, "deployer balance changed");
        assertEq(token.balanceOf(alice), 1e24, "holder balance changed");
        assertEq(token.balanceOf(stranger), 0, "stranger gained tokens");
        assertEq(address(token).balance, 0, "token accepted ether");
    }
}
