// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../tokens/interfaces/IWETH.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultStorage.sol";
import "../tokens/interfaces/IMintable.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";
import "./interfaces/ITradeStorage.sol";


contract RouterSign is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public weth;
    address public vault;
    address public priceFeed;
    address public tradeStorage;

    mapping (address => uint256) public swapMaxRatio;

    event Swap(address account, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    // event IncreasePosition(address[] _path, address _indexToken, uint256 _amountIn, uint256 _sizeDelta, bool _isLong, uint256 _price,
    //         bytes[] _updaterSignedMsg);
    // event DecreasePosition(address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _price,
    //             bytes[] _updaterSignedMsg);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(address _vault, address _weth, address _priceFeed, address _tStorage) external onlyOwner {
        vault = _vault;
        weth = _weth;
        priceFeed = _priceFeed;
        tradeStorage = _tStorage;
    }

    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }
    
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
        
    function setMaxSwapRatio(address _token, uint256 _ratio) external onlyOwner{
        swapMaxRatio[_token] = _ratio;
    }


    function increasePositionAndUpdate(address[] memory _path, address _indexToken, uint256 _amountIn, uint256 _sizeDelta, bool _isLong,             bytes[] memory _updaterSignedMsg) external{
        require(_amountIn > 0, "zero amount in");

        VaultMSData.TokenBase memory _tokenInBase = IVault(vault).getTokenBase(_path[0]);
        require(_tokenInBase.isFundable ,  "not funding token");

        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        address _account = _sender();
        IERC20(_path[0]).safeTransferFrom(_account, vault, _amountIn);
        // if (_path.length > 1) {
        //     uint256 amountOut = _swap(_path, 0, address(this), _account);
        //     IERC20(_path[_path.length - 1]).safeTransfer(vault, amountOut);
        // }
        _increasePosition(_path[0], _indexToken, _sizeDelta, _isLong);
    }

    // function increasePositionETHAndUpdate(address[] memory _path, address _indexToken, uint256 _sizeDelta, bool _isLong, uint256,
    //             bytes[] memory _updaterSignedMsg) external payable{
    //     IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
    //     require(_path[0] == weth, "Router: invalid _path");
    //     uint256 increaseValue = msg.value;
    //     require(increaseValue > 0, "zero amount in");
    //     _transferETHToVault(increaseValue);
    //     if (_path.length > 1) {
    //         uint256 amountOut = _swap(_path, 0, address(this), _sender());
    //         IERC20(_path[_path.length - 1]).safeTransfer(vault, amountOut);
    //     }
    //     _increasePosition(_path[_path.length - 1], _indexToken, _sizeDelta, _isLong);
    // }

    function decreasePositionAndUpdate(
            address _collateralToken, address _indexToken, 
            uint256 _collateralDelta, uint256 _sizeDelta, 
            bool _isLong, address _receiver, 
            bytes[] memory _updaterSignedMsg) external {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        _decreasePosition(_collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
    }

    // function decreasePositionETHAndUpdate(address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address payable _receiver, uint256,
    //             bytes[] memory _updaterSignedMsg) external{
    //     IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
    //     (uint256 amountOut, ) = _decreasePosition(_collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, address(this));
    //     _transferOutETH(amountOut, _receiver);
    // }
    // function decreasePositionAndSwapUpdate(address[] memory _path, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256, uint256 _minOut,
    //             bytes[] memory _updaterSignedMsg) external{
    //     IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
    //     (uint256 amount, )= _decreasePosition(_path[0], _indexToken, _collateralDelta, _sizeDelta, _isLong, address(this));
    //     IERC20(_path[0]).safeTransfer(vault, amount);
    //     _swap(_path, _minOut, _receiver, msg.sender);
    // }
    // function decreasePositionAndSwapETHUpdate(address[] memory _path, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address payable _receiver, uint256, uint256 _minOut,
    //             bytes[] memory _updaterSignedMsg) external{
    //     IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
    //     require(_path[_path.length - 1] == weth, "Router: invalid _path");
    //     (uint256 amount, ) = _decreasePosition(_path[0], _indexToken, _collateralDelta, _sizeDelta, _isLong, address(this));
    //     IERC20(_path[0]).safeTransfer(vault, amount);
    //     uint256 amountOut = _swap(_path, _minOut, address(this), msg.sender);
    //     _transferOutETH(amountOut, _receiver);
    // }



    //-------- swap functions
    function directPoolDeposit(address _token, uint256 _amount) external {
        VaultMSData.TokenBase memory _tokenInBase = IVault(vault).getTokenBase(_token);
        require(_tokenInBase.isFundable ,  "not funding token");
        IERC20(_token).safeTransferFrom(_sender(), vault, _amount);
        IVault(vault).directPoolDeposit(_token);
    }

    // function validSwap(address _token, uint256 _amount) public view returns(bool){
    //     VaultMSData.TokenBase memory _tokenInBase = IVault(vault).getTokenBase(_token);
    //     require(_tokenInBase.isSwappable ,  "not swappable token");
    //     if (swapMaxRatio[_token] == 0) return true;
    //     address[] memory fundingTokenList = IVaultStorage(IVault(vault).vaultStorage()).fundingTokenList();
    //     uint256 aum = 0;
    //     uint256 token_mt = IVaultPriceFeed(priceFeed).tokenToUsdUnsafe(_token, _amount, true);
    //     for (uint256 i = 0; i < fundingTokenList.length; i++) {
    //         address token_i = fundingTokenList[i];
    //         uint256 poolUsd = IVaultPriceFeed(priceFeed).tokenToUsdUnsafe(token_i, IVault(vault).poolAmount(token_i), true);
    //         if (token_i == _token){
    //             token_mt = token_mt.add(poolUsd);
    //         }
    //         aum = aum.add(poolUsd);
    //     }
        
    //     if (aum == 0) return true;
    //     return token_mt.mul(1000).div(aum) < swapMaxRatio[_token];
    // }

    // function swap(address[] memory _path, uint256 _amountIn, uint256 _minOut, address _receiver,
    //             bytes[] memory _updaterSignedMsg) external{
    //     require(validSwap(_path[0], _amountIn), "Swap limit reached.");
    //     IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
    //     IERC20(_path[0]).safeTransferFrom(_sender(), vault, _amountIn);
    //     uint256 amountOut = _swap(_path, _minOut, _receiver, msg.sender);
    //     emit Swap(msg.sender, _path[0], _path[_path.length - 1], _amountIn, amountOut);
    // }

    // function swapETHToTokens(address[] memory _path, uint256 _minOut, address _receiver,
    //             bytes[] memory _updaterSignedMsg) external payable{
    //     require(_path[0] == weth, "Router: invalid _path");
    //     IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
    //     require(validSwap(_path[0], msg.value), "Swap limit reached.");
    //     _transferETHToVault(msg.value);
    //     uint256 amountOut = _swap(_path, _minOut, _receiver, msg.sender);
    //     emit Swap(msg.sender, _path[0], _path[_path.length - 1], msg.value, amountOut);
    // }

    // function swapTokensToETH(address[] memory _path, uint256 _amountIn, uint256 _minOut, address payable _receiver,
    //             bytes[] memory _updaterSignedMsg) external{
    //     require(validSwap(_path[0], _amountIn), "Swap limit reached.");
    //     require(_path[_path.length - 1] == weth, "Router: invalid _path");
    //     IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);

    //     IERC20(_path[0]).safeTransferFrom(_sender(), vault, _amountIn);
    //     uint256 amountOut = _swap(_path, _minOut, address(this), msg.sender);
    //     _transferOutETH(amountOut, _receiver);
    //     emit Swap(msg.sender, _path[0], _path[_path.length - 1], _amountIn, amountOut);
    // }



    //------------------------------ Private Functions ------------------------------
    function _increasePosition(address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) private {
        // if (_isLong) {
        //     require(IVault(vault).getMaxPrice(_indexToken) <= _price, "Router: mark price higher than limit");
        // } else {
        //     require(IVault(vault).getMinPrice(_indexToken) >= _price, "Router: mark price lower than limit");
        // }
        address tradeAccount = _sender();
        IVault(vault).increasePosition(tradeAccount, _collateralToken, _indexToken, _sizeDelta, _isLong);
        ITradeStorage(tradeStorage).updateTrade(tradeAccount, _sizeDelta);
    }

    function _decreasePosition(address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) private returns (uint256, bool) {
        // if (_isLong) {
        //     require(IVault(vault).getMinPrice(_indexToken) >= _price, "Router: mark price lower than limit");
        // } else {
        //     require(IVault(vault).getMaxPrice(_indexToken) <= _price, "Router: mark price higher than limit");
        // }
        address tradeAccount = _sender();
        ITradeStorage(tradeStorage).updateTrade(tradeAccount, _sizeDelta);
        return IVault(vault).decreasePosition(tradeAccount, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
    }

    function _transferETHToVault(uint256 _value) private {
        IWETH(weth).deposit{value: _value}();
        IERC20(weth).safeTransfer(vault, _value);
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _swap(address[] memory _path, uint256 _minOut, address _receiver, address _user) private returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_path[0], _path[1], _minOut, _receiver, _user);
        }
        if (_path.length == 3) {
            uint256 midOut = _vaultSwap(_path[0], _path[1], 0, address(this), _user);
            IERC20(_path[1]).safeTransfer(vault, midOut);
            return _vaultSwap(_path[1], _path[2], _minOut, _receiver, _user);
        }
        revert("Router: invalid _path.length");
    }

    function _vaultSwap(address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver, address _account) private returns (uint256) {
        uint256 amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
        require(amountOut >= _minOut, "Router: amountOut not satisfied.");
        uint256 _sizeDelta = IVaultPriceFeed(priceFeed).tokenToUsdUnsafe(_tokenOut, amountOut, false);
        ITradeStorage(tradeStorage).updateSwap(_account, _sizeDelta);
        return amountOut;
    }

    function _sender() private view returns (address) {
        return msg.sender;
    }


}
