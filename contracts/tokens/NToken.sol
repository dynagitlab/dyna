// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NToken is ERC20 {
    constructor(string memory name) ERC20(name, name) {
        //meaningless token
    }
    
    function burn(uint256 _amount) external {
        _burn(msg.sender, _amount);
    }
}