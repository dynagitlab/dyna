// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IUserFeeResv {
    function claim(address _account) external;
    function updateAll(address _account) external payable;
    function update(address _account, address _token, uint256 _amount) external payable;
    function claimable(address _account) external view returns (uint256);

}