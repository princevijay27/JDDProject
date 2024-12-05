// SPDX-License-Identifier: MIT

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDMStablecoin is IERC20{
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}
