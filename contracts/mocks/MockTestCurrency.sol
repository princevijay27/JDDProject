// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

contract MockPaymentCurrency is ERC20 {
    constructor() ERC20("PaymentToken", "PT") {
        uint256 totalSupply = 1000000000 * 10 ** decimals();
        _mint(address(this), totalSupply); // 5% Airdrop community rewards
    }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
