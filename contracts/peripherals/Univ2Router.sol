// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Univ2Router { 
    uint addCount = 0;


    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity){
        addCount++;
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] memory path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts){
        addCount++;
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] memory path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts){
        addCount++;
    }
}

