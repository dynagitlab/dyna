// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../DID/interfaces/IPID.sol";
import "../tokens/interfaces/IMintable.sol";
import "../core/FullMath.sol";

contract Univ2Factory is Ownable { //IERC20,

    mapping(address => mapping(address => uint )) poolmap;
    uint id;

    function createPair(address tokenA, address tokenB) public returns (address pair){
        id += 1;
        poolmap[tokenA][tokenB] = id;
    }
    function getPair(address tokenA, address tokenB) external view returns (address pair){
        return tokenA;
    }

}

