// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

contract MockDDToken is ERC20 {
    constructor() ERC20("Discount Dao", "DD") {
        uint256 totalSupply = 1000000000 * 10 ** decimals();
        _mint(address(this), totalSupply); // 5% Airdrop community rewards
    }

    function mint(address _account, uint256 _amount) public {
        _mint(_account, _amount);
    }
}

contract MockToken is ERC20 {
    // ERC20 token with name, symbol and initial supply in constructor
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) ERC20(_name, _symbol) {
        _mint(msg.sender, _initialSupply);
    }
}
