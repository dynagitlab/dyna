// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DYNA is ERC20 {
    constructor() ERC20("DYNA", "DYNA") {
        uint256 initialSupply = 88480000 * (10 ** 18);
        _mint(msg.sender, initialSupply);
    }
    
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}