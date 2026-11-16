// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AgentPay — AI agent spending allowances in tUSD8
/// @notice A user deposits tUSD8, grants an AI agent a capped, expiring
///         allowance, and the agent pays payees within that allowance.
///         The user can revoke anytime; every payment emits an auditable receipt.
/// @dev Built for the Aevum Builder Challenge #1 (Native AI Assistants track)
///      on QDay Aevum Testnet (chain ID 44005). Token is tUSD8 (6 decimals).
contract AgentPay is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    struct Allowance {
        address owner;
        address agent;
        uint256 cap;
        uint256 spent;
        uint256 expiry;
        bool revoked;
    }

    mapping(address => uint256) public vaultBalance;
    mapping(uint256 => Allowance) public allowances;
    uint256 public nextAllowanceId;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event AllowanceCreated(
        uint256 indexed id, address indexed owner, address indexed agent, uint256 cap, uint256 expiry
    );
    event AllowanceRevoked(uint256 indexed id);
    event PaymentMade(
        uint256 indexed id, address indexed agent, address indexed payee, uint256 amount, string memo
    );

    error ZeroAddress();
    error ZeroAmount();
    error InvalidExpiry();
    error NotOwner();
    error NotAgent();
    error AllowanceAlreadyRevoked();
    error AllowanceExpired();
    error CapExceeded();
    error InsufficientVault();

    constructor(address _token) {
        if (_token == address(0)) revert ZeroAddress();
        token = IERC20(_token);
    }

    /// @notice Deposit tUSD8 into your vault (requires prior ERC-20 approval).
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        vaultBalance[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Withdraw unspent tUSD8 from your vault.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (vaultBalance[msg.sender] < amount) revert InsufficientVault();
        vaultBalance[msg.sender] -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Grant an agent a spending allowance: max `cap`, valid until `expiry`.
    function createAllowance(address agent, uint256 cap, uint256 expiry)
        external
        returns (uint256 id)
    {
        if (agent == address(0)) revert ZeroAddress();
        if (cap == 0) revert ZeroAmount();
        if (expiry <= block.timestamp) revert InvalidExpiry();
        id = nextAllowanceId++;
        allowances[id] = Allowance({
            owner: msg.sender,
            agent: agent,
            cap: cap,
            spent: 0,
            expiry: expiry,
            revoked: false
        });
        emit AllowanceCreated(id, msg.sender, agent, cap, expiry);
    }

    /// @notice Revoke an allowance immediately. The agent cannot spend after this.
    function revokeAllowance(uint256 id) external {
        Allowance storage a = allowances[id];
        if (a.owner != msg.sender) revert NotOwner();
        a.revoked = true;
        emit AllowanceRevoked(id);
    }

    /// @notice Called by the allowance's agent to pay `payee` from the owner's vault.
    /// @dev Enforces: caller is the agent, allowance active + unexpired,
    ///      amount within remaining cap, owner vault funded. Reverts otherwise.
    function pay(uint256 id, address payee, uint256 amount, string calldata memo)
        external
        nonReentrant
    {
        Allowance storage a = allowances[id];
        if (a.agent != msg.sender) revert NotAgent();
        if (a.revoked) revert AllowanceAlreadyRevoked();
        if (block.timestamp >= a.expiry) revert AllowanceExpired();
        if (payee == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (a.spent + amount > a.cap) revert CapExceeded();
        if (vaultBalance[a.owner] < amount) revert InsufficientVault();
        a.spent += amount;
        vaultBalance[a.owner] -= amount;
        token.safeTransfer(payee, amount);
        emit PaymentMade(id, msg.sender, payee, amount, memo);
    }

    /// @notice Remaining spendable amount for an allowance (0 if revoked/expired).
    function allowanceRemaining(uint256 id) external view returns (uint256) {
        Allowance storage a = allowances[id];
        if (a.revoked || block.timestamp >= a.expiry) return 0;
        return a.cap - a.spent;
    }
}
