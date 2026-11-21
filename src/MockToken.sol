// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title MockToken
/// @notice Minimal ERC-20 used for the demo market (USDX stable + VOLT volatile).
/// @dev Includes a public faucet so judges can reproduce the demo without us.
///      Testnet-only code; do not deploy to mainnet.
contract MockToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 public constant FAUCET_AMOUNT = 10_000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    /// @notice Demo faucet: anyone can mint themselves a fixed test amount.
    function faucet() external {
        _mint(msg.sender, FAUCET_AMOUNT);
    }

    /// @notice Ownerless mint used once at deployment to seed the AMM reserves.
    /// @dev Guarded by a one-time flag per caller balance is overkill for a mock;
    ///      instead the deploy script mints through `faucet` + transfers. This
    ///      function exists for the AMM seeding in tests. It is intentionally
    ///      permissionless because both tokens are worthless test assets.
    function mint(address to_, uint256 amount_) external {
        _mint(to_, amount_);
    }

    function approve(address spender_, uint256 amount_) external returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        _transfer(msg.sender, to_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        uint256 allowed = allowance[from_][msg.sender];
        require(allowed >= amount_, "MockToken: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from_][msg.sender] = allowed - amount_;
        }
        _transfer(from_, to_, amount_);
        return true;
    }

    function _transfer(address from_, address to_, uint256 amount_) internal {
        require(balanceOf[from_] >= amount_, "MockToken: insufficient balance");
        balanceOf[from_] -= amount_;
        balanceOf[to_] += amount_;
        emit Transfer(from_, to_, amount_);
    }

    function _mint(address to_, uint256 amount_) internal {
        totalSupply += amount_;
        balanceOf[to_] += amount_;
        emit Transfer(address(0), to_, amount_);
    }
}
