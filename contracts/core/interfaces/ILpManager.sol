// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILpManager {
    function addLiquidity(address _token, uint256 _amount, uint256 _minPlp, bytes[] memory _priceUpdateData) external payable returns (uint256);
    function removeLiquidity(address _tokenOut, uint256 _plpAmount, uint256 _minOut, bytes[] memory _priceUpdateData) external payable returns (uint256);
    function addLiquidityETH(uint256 _minElp, bytes[] memory _priceUpdateData) external payable returns (uint256);
    function removeLiquidityETH(uint256 _plpAmount, bytes[] memory _priceUpdateData) external payable returns (uint256);
    function addLiquidityNoUpdate(address _token, uint256 _amount, uint256 _minPlp, address _receipt) external payable;

    // function isLpVault(address _vault) external view returns(bool);
    // function getLpVaultsList() external view returns (address[] memory);
    function getAum( bool _maximise) external view returns (uint256);
    // function vaultLpToken(address _vault) external view returns (address);
    function weth() external view returns (address);
    function elp() external view returns (address);
}