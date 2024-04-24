// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPID {
    function rank(address _account) external view returns (uint256);
}