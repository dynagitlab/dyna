// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/interfaces/IVault.sol";
import "../core/Handler.sol";
import "../core/BlastBase.sol";


contract VaultResv is Handler, BlastBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;


    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
    }
    
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    
    function redeem(address _token, uint256 _amount, address _receipt) external onlyManager{
        IERC20(_token).transfer(_receipt,  _amount);
    }



}