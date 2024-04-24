// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract bridge  {
    uint256 c = 0;

    function bridgeERC20(address localToken,address remoteToken,uint256 amount,uint32, bytes memory) external{
        c++;
    }
}
