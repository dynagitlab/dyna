// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPID {
    function nickName(address _account) external view returns (string memory);
    function getRefCode(address _account) external view returns (string memory);
    function rank(address _account) external view returns (uint256);
    function updateRank(address _account) external;
    function boost(address _account) external view returns (uint256, uint256);
    function inviter(address _account) external view returns (address);

    // function tokenInfo(address _account) external view returns (uint8, uint64, address);
    function inviterRebatesValue(address _account, uint256 _value) external view returns (address, uint256);

    //=================Public data reading =================
    struct PidDispInfo{
        uint64 id;
        string refCode;
        string nickName;
        uint8 rank;
        uint64 nomNumber;
        uint64 idvPoints;
        uint64 rebPoints;
        address inviter;
        uint256 boost;
        address account;
        uint256 stakedBalance;
        uint256 tradeVolume;
    }

    function getBasicInfo(address _account) external view returns (PidDispInfo memory disp);

}


