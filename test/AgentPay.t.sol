// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AgentPay} from "../src/AgentPay.sol";

/// @notice Minimal tUSD8 stand-in: ERC-20 with 6 decimals, open mint for tests.
contract MockUSD8 is ERC20 {
    constructor() ERC20("Test USD8", "tUSD8") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AgentPayTest is Test {
    AgentPay public agentPay;
    MockUSD8 public tusd8;

    address public owner = address(0xA11CE);
    address public agent = address(0xA6E17);
    address public payee = address(0xBEEF);
    address public stranger = address(0x5EED);

    uint256 constant DEPOSIT = 100_000_000; // 100 tUSD8 (6 decimals)
    uint256 constant CAP = 10_000_000; // 10 tUSD8
    uint256 constant PAY = 2_000_000; // 2 tUSD8

    function setUp() public {
        tusd8 = new MockUSD8();
        agentPay = new AgentPay(address(tusd8));
        tusd8.mint(owner, DEPOSIT);
        vm.prank(owner);
        tusd8.approve(address(agentPay), type(uint256).max);
    }

    function _depositAndAllow() internal returns (uint256 id) {
        vm.prank(owner);
        agentPay.deposit(DEPOSIT);
        vm.prank(owner);
        id = agentPay.createAllowance(agent, CAP, block.timestamp + 7 days);
    }

    function testDepositWithdraw() public {
        vm.prank(owner);
        agentPay.deposit(DEPOSIT);
        assertEq(agentPay.vaultBalance(owner), DEPOSIT);
        assertEq(tusd8.balanceOf(address(agentPay)), DEPOSIT);

        vm.prank(owner);
        agentPay.withdraw(40_000_000);
        assertEq(agentPay.vaultBalance(owner), 60_000_000);
        assertEq(tusd8.balanceOf(owner), 40_000_000);
    }

    function testPayWithinCap() public {
        uint256 id = _depositAndAllow();
        vm.prank(agent);
        agentPay.pay(id, payee, PAY, "api-call #1");
        assertEq(tusd8.balanceOf(payee), PAY);
        assertEq(agentPay.vaultBalance(owner), DEPOSIT - PAY);
        assertEq(agentPay.allowanceRemaining(id), CAP - PAY);
    }

    function testPayFullCapThenReverts() public {
        uint256 id = _depositAndAllow();
        vm.prank(agent);
        agentPay.pay(id, payee, CAP, "full cap");
        assertEq(agentPay.allowanceRemaining(id), 0);
        vm.prank(agent);
        vm.expectRevert(AgentPay.CapExceeded.selector);
        agentPay.pay(id, payee, 1, "one more");
    }

    function testPayOverCapReverts() public {
        uint256 id = _depositAndAllow();
        vm.prank(agent);
        vm.expectRevert(AgentPay.CapExceeded.selector);
        agentPay.pay(id, payee, CAP + 1, "too much");
    }

    function testPayAfterExpiryReverts() public {
        uint256 id = _depositAndAllow();
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(agent);
        vm.expectRevert(AgentPay.AllowanceExpired.selector);
        agentPay.pay(id, payee, PAY, "late");
        assertEq(agentPay.allowanceRemaining(id), 0);
    }

    function testPayByNonAgentReverts() public {
        uint256 id = _depositAndAllow();
        vm.prank(stranger);
        vm.expectRevert(AgentPay.NotAgent.selector);
        agentPay.pay(id, payee, PAY, "intruder");
    }

    function testRevokeThenPayReverts() public {
        uint256 id = _depositAndAllow();
        vm.prank(owner);
        agentPay.revokeAllowance(id);
        vm.prank(agent);
        vm.expectRevert(AgentPay.AllowanceAlreadyRevoked.selector);
        agentPay.pay(id, payee, PAY, "revoked");
    }

    function testRevokeByNonOwnerReverts() public {
        uint256 id = _depositAndAllow();
        vm.prank(stranger);
        vm.expectRevert(AgentPay.NotOwner.selector);
        agentPay.revokeAllowance(id);
    }

    function testWithdrawMoreThanBalanceReverts() public {
        vm.prank(owner);
        agentPay.deposit(DEPOSIT);
        vm.prank(owner);
        vm.expectRevert(AgentPay.InsufficientVault.selector);
        agentPay.withdraw(DEPOSIT + 1);
    }

    function testPayToZeroAddressReverts() public {
        uint256 id = _depositAndAllow();
        vm.prank(agent);
        vm.expectRevert(AgentPay.ZeroAddress.selector);
        agentPay.pay(id, address(0), PAY, "nowhere");
    }

    function testCreateAllowanceBadParamsRevert() public {
        vm.prank(owner);
        vm.expectRevert(AgentPay.ZeroAddress.selector);
        agentPay.createAllowance(address(0), CAP, block.timestamp + 1 days);
        vm.prank(owner);
        vm.expectRevert(AgentPay.ZeroAmount.selector);
        agentPay.createAllowance(agent, 0, block.timestamp + 1 days);
        vm.prank(owner);
        vm.expectRevert(AgentPay.InvalidExpiry.selector);
        agentPay.createAllowance(agent, CAP, block.timestamp);
    }
}
