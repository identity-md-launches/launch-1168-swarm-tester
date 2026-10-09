// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TESTERToken} from "../src/TESTERToken.sol";

/// @dev Only the Foundry cheatcodes used by this dependency-free smoke suite.
interface VmTESTERSmoke {
    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
}

contract TESTERTokenSmokeTest {
    VmTESTERSmoke private constant vm = VmTESTERSmoke(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(uint160(uint256(keccak256("smoke:alice"))));
    address private constant SPENDER = address(uint160(uint256(keccak256("smoke:spender"))));
    address private constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    TESTERToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new TESTERToken();
    }

    function test_DeploymentMintsEntireSupplyToDeployer() public view {
        require(keccak256(bytes(token.name())) == keccak256("Swarm Tester"), "wrong name");
        require(keccak256(bytes(token.symbol())) == keccak256("TESTER"), "wrong symbol");
        require(token.decimals() == 18, "wrong decimals");
        require(token.totalSupply() == SUPPLY, "wrong supply");
        require(token.balanceOf(address(this)) == SUPPLY, "deployer must receive 100%");
        require(token.balanceOf(address(token)) == 0, "token retained supply");
    }

    // Token movement only: no Uniswap pool or swap implementation is mocked here.
    function test_FullBalanceTransfersToAndFromPoolManagerWithoutFeesOrLimits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), POOL_MANAGER, SUPPLY);
        require(token.transfer(POOL_MANAGER, SUPPLY), "transfer returned false");
        require(token.balanceOf(address(this)) == 0, "sender not debited");
        require(token.balanceOf(POOL_MANAGER) == SUPPLY, "pool received less");

        vm.prank(POOL_MANAGER);
        require(token.transfer(address(this), SUPPLY), "return transfer failed");
        require(token.balanceOf(POOL_MANAGER) == 0, "pool retained balance");
        require(token.balanceOf(address(this)) == SUPPLY, "round trip lost tokens");
        require(token.totalSupply() == SUPPLY, "supply changed");
    }

    function test_ApprovalAllowsOnlyTheApprovedAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 10 ether);
        require(token.approve(SPENDER, 10 ether), "approve returned false");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), ALICE, 10 ether), "transferFrom returned false");
        require(token.balanceOf(ALICE) == 10 ether, "recipient received less");
        require(token.balanceOf(address(this)) == SUPPLY - 10 ether, "wrong debit");
        require(token.allowance(address(this), SPENDER) == 0, "allowance not spent");

        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        require(token.balanceOf(ALICE) == 10 ether, "failed spend changed balance");
    }

    function test_InfiniteAllowanceSelfTransferAndZeroTransfer() public {
        require(token.approve(SPENDER, type(uint256).max), "approve failed");
        vm.prank(SPENDER);
        require(token.transferFrom(address(this), address(this), SUPPLY), "self transfer failed");
        require(token.allowance(address(this), SPENDER) == type(uint256).max, "unlimited allowance changed");
        require(token.balanceOf(address(this)) == SUPPLY, "self transfer changed balance");
        vm.prank(ALICE);
        require(token.transfer(SPENDER, 0), "zero transfer failed");
        require(token.balanceOf(SPENDER) == 0, "zero transfer changed balance");
    }

    function test_RevertWhenTransferExceedsBalance() public {
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(address(this), 1);
        require(token.balanceOf(address(this)) == SUPPLY, "failed transfer changed balance");
        require(token.balanceOf(ALICE) == 0, "sender balance changed");
    }

    function test_DeployerCannotSpendHolderBalanceWithoutApproval() public {
        require(token.transfer(ALICE, 10 ether), "fund holder failed");
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        require(token.balanceOf(ALICE) == 10 ether, "deployer seized tokens");
    }

    function test_FailedTransferFromPreservesAllowance() public {
        vm.prank(ALICE);
        require(token.approve(SPENDER, 10 ether), "approve failed");
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, ALICE, 0, 10 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(this), 10 ether);
        require(token.allowance(ALICE, SPENDER) == 10 ether, "failed transfer consumed allowance");
        require(token.balanceOf(address(this)) == SUPPLY, "failed transfer moved funds");
    }

    function test_ZeroRecipientAndZeroSpenderRevert() public {
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        require(token.totalSupply() == SUPPLY, "supply changed");
        require(token.balanceOf(address(this)) == SUPPLY, "failed transfer changed balance");
    }
}
