// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVaultPriceFeed {   
    /// @dev owner setting
    function setGap(uint256 _priceSafetyTimeGap,uint256 _stablePriceSafetyTimeGap, uint256 _stopTradingPriceGap) external;
    function setSpreadBasisPoints(address _token, uint24 _priceSpreadMax, uint24 _priceSpreadTimeStart, uint24 _priceSpreadTimeMax) external ;


    function getPrice(address _token, bool _maximise,bool,bool) external view returns (uint256);
    function getPriceUnsafe(address _token, bool _maximise, bool, bool _adjust) external view returns (uint256);
    function priceTime(address _token) external view returns (uint256);
    function tokenToUsdUnsafe(address _token, uint256 _tokenAmount, bool _max) external view returns (uint256);
    function usdToTokenUnsafe( address _token, uint256 _usdAmount, bool _max ) external view returns (uint256);

    // function updatePriceFeedsIfNecessary(bytes[] memory updateData, bytes32[] memory priceIds, uint64[] memory publishTimes) external;
    // function updatePriceFeedsIfNecessaryTokens(bytes[] memory updateData, address[] memory _tokens, uint64[] memory publishTimes) external;
    function updatePriceFeeds(bytes[] memory updateData) external;
    // function updatePriceFeedsIfNecessaryTokensSt(bytes[] memory updateData, address[] memory _tokens) external;
    function getUpdateFee(bytes[] memory _data) external view returns(uint256);



    function tokenToUsd(address _token, uint256 _tokenAmount, bool _max) external view returns (uint256);
    function usdToToken( address _token, uint256 _usdAmount, bool _max ) external view returns (uint256);
    function tokenToUsdMeanUnsafe(address _token, uint256 _tokenAmount) external view returns (uint256);

}

