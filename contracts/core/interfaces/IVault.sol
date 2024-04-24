// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../VaultMSData.sol";

interface IVault {
    function priceFeed() external view returns (address);
    function vaultStorage() external view returns (address);

    function approvedRouters(address _router) external view returns (bool);
    function isManager(address _account) external view returns (bool);

    // function feeReserves(address _token) external view returns (uint256);
    // function feeSold (address _token)  external view returns (uint256);
    // function feeReservesUSD() external view returns (uint256);
    // function feeReservesDiscountedUSD() external view returns (uint256);
    // function feeClaimedUSD() external view returns (uint256);
    function globalShortSize( ) external view returns (uint256);
    function globalLongSize( ) external view returns (uint256);


    //---------------------------------------- owner FUNCTIONS --------------------------------------------------
    // function setPID(address _pid) external;
    // function setVaultStorage(address _vaultStorage) external;
    // function setVaultUtils(address _vaultUtils) external;
    // function setPriceFeed(address _priceFeed) external;
    function setAdd(address[] memory _addList) external;
    function setManager(address _manager, bool _isManager) external;
    function setRouter(address _router, bool _status) external;
    // function setTokenConfig(address _token, uint256 _tokenWeight, bool _isStable, bool _isFundingToken, bool _isTradingToken) external;
    // function clearTokenConfig(address _token) external;
    // function updateRate(address _token) external returns (uint64);
    // function tokenDecimals(address _token) external view returns (uint8);
    //-------------------------------------------------- FUNCTIONS FOR MANAGER --------------------------------------------------
    function buyUSD(address _token) external returns (uint256);
    function sellUSD(address _token, address _receiver, uint256 _usdxAmount) external returns (uint256);


    //---------------------------------------- TRADING FUNCTIONS --------------------------------------------------
    function swap(address _tokenIn, address _tokenOut, address _receiver) external returns (uint256);
    function increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external;
    function decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) external returns (uint256, bool);
    function liquidatePosition(address _account, address _collateralToken, address _indexToken, bool _isLong, address _feeReceiver) external;


    //-------------------------------------------------- PUBLIC FUNCTIONS --------------------------------------------------
    function directPoolDeposit(address _token) external;

    function calFundingFee(
            uint256 _positionSizeUSD, 
            uint256 _entryFundingRateSec, 
            address _colToken) external view returns (uint256 feeUsd, uint128 _accumulativefundingRateSec);

    function getMaxPrice(address _token) external view returns (uint256);
    function getMinPrice(address _token) external view returns (uint256);
    // function getRedemptionAmount(address _token, uint256 _usdxAmount) external view returns (uint256);
    function tokenToUsdMin(address _token, uint256 _tokenAmount) external view returns (uint256);
    function usdToTokenMax(address _token, uint256 _usdAmount) external view returns (uint256);
    function usdToTokenMin(address _token, uint256 _usdAmount) external view returns (uint256);


    function balance(address _token) external view returns (uint256);
    function poolAmount(address _token) external view returns (uint256);
    function reservedAmount(address _token) external view returns (uint256);

    // function isFundingToken(address _token) external view returns(bool);
    // function isTradingToken(address _token) external view returns(bool);
    // function tokenDecimals(address _token) external view returns (uint256);
    function getPositionStructByKey(bytes32 _key) external view returns (VaultMSData.Position memory);
    // function getPositionStruct(address _account, address _collateralToken, address _indexToken, bool _isLong) external view returns (VaultMSData.Position memory);
    function getTokenBase(address _token) external view returns (VaultMSData.TokenBase memory);
    // function getTradingFee(address _token) external view returns (VaultMSData.TradingFee memory);
    function getTradingRec(address _token) external view returns (VaultMSData.TradingRec memory);
    // function getUserKeys(address _account, uint256 _start, uint256 _end) external view returns (bytes32[] memory);
    // function getKeys(uint256 _start, uint256 _end) external view returns (bytes32[] memory);
}
