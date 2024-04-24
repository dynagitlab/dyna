// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./VaultMSData.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultStorage.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "./interfaces/ILpManager.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";

pragma solidity ^0.8.0;

contract LpManager is ILpManager, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;
    
    IVault public vault;
    address public override elp;
    address public override weth;
    address public priceFeed;


    uint256 public aumAddition;
    uint256 public aumDeduction;

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsdx,
        uint256 elpSupply,
        uint256 usdxAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 elpAmount,
        uint256 aumInUsdx,
        uint256 elpSupply,
        uint256 usdxAmount,
        uint256 amountOut
    );

    constructor(address _vault, address _elp, address _weth) {
        vault = IVault(_vault);
        elp = _elp;
        weth = _weth;
    }
    

    receive() external payable {
        require(msg.sender == weth, "invalid sender");
    }

    function setAdd(address _priceFeed) external onlyOwner{
        priceFeed = _priceFeed;
    }
    function withdrawToken(address _account, address _token,uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyOwner {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addLiquidity(address _token, uint256 _amount, uint256 _minPlp, bytes[] memory _priceUpdateData) external nonReentrant payable override returns (uint256) {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _addLiquidity( _token, _amount, _minPlp, msg.sender);
    }

    function addLiquidityETH(uint256 _minElp, bytes[] memory _priceUpdateData) external nonReentrant payable override returns (uint256) {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _addLiquidity(address(0), msg.value, _minElp, msg.sender);
    }

    function addLiquidityNoUpdate(address _token, uint256 _amount, uint256 _minPlp, address _receipt) external nonReentrant payable override{
        _addLiquidity( _token, _amount, _minPlp, _receipt);
    }

    function _addLiquidity(address _token, uint256 _amount, uint256 _minlp, address _receipt) private returns (uint256) {
        uint256 _fundAmount = _amount;
        address _fundToken = _token;
        
        if (_token == address(0)){
            _fundToken = weth;
            _fundAmount = _amount;
            IWETH(weth).deposit{value: _amount}();
        }else{
            IERC20(_fundToken).safeTransferFrom(msg.sender, address(this), _fundAmount);
        }
        VaultMSData.TokenBase memory tBase = vault.getTokenBase(_fundToken);
        require(tBase.isFundable, "[ElpManager] not supported lp token");
        require(_fundAmount > 0, "[ElpManager] invalid amount");
        IERC20(_fundToken).safeTransfer(address(vault), _fundAmount);
    
        // calculate aum before buyUSD
        uint256 aumInUSD = getAumSafe(true);
        uint256 lpSupply = IERC20(elp).totalSupply();
        uint256 usdAmount = vault.buyUSD(_fundToken);
        uint256 mintAmount = aumInUSD == 0 ? usdAmount.mul(10 ** IMintable(elp).decimals()).div(PRICE_PRECISION) : usdAmount.mul(lpSupply).div(aumInUSD);
        require(mintAmount >= _minlp, "[ElpManager] min output not satisfied");
        IMintable(elp).mint(_receipt, mintAmount);
        emit AddLiquidity(msg.sender, _fundToken, _fundAmount, aumInUSD, lpSupply, usdAmount, mintAmount); 
        return mintAmount;
    }

    function removeLiquidity(address _tokenOut, uint256 _elpAmount, uint256 _minOut, bytes[] memory _priceUpdateData) external nonReentrant payable override returns (uint256) {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _removeLiquidity(_elpAmount,_tokenOut, _minOut);
    }

    function _removeLiquidity(uint256 _lpAmount, address _tokenOutOri, uint256 _minOut) private returns (uint256) {
        require(_lpAmount > 0, "[LpManager]: invalid lp amount");
        address _tokenOut = _tokenOutOri==address(0) ? weth : _tokenOutOri;
        VaultMSData.TokenBase memory tBase = vault.getTokenBase(_tokenOut);
        require(tBase.isFundable, "[LpManager] not supported lp token");
        address _account = msg.sender;
        IERC20(elp).safeTransferFrom(_account, address(this), _lpAmount );
        
        // calculate aum before sellUSD
        uint256 aumInUSD = getAumSafe(false);
        uint256 lpSupply = IERC20(elp).totalSupply();
        uint256 usdAmount = _lpAmount.mul(aumInUSD).div(lpSupply); //30b
        IMintable(elp).burn(_lpAmount);
        uint256 amountOut = vault.sellUSD(_tokenOut, address(this), usdAmount);
        require(amountOut >= _minOut, "LpManager: insufficient output");
        
        if (_tokenOutOri == address(0)){
            IWETH(weth).withdraw(amountOut);
            payable(_account).sendValue(amountOut);
        }else{
            IERC20(_tokenOut).safeTransfer(_account, amountOut);
        }
        emit RemoveLiquidity(_account, _tokenOut, _lpAmount, aumInUSD, lpSupply, usdAmount, amountOut);
        return amountOut;
    }

    function removeLiquidityETH(uint256 _elpAmount, bytes[] memory _priceUpdateData) external nonReentrant payable override returns (uint256) {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_priceUpdateData);
        return _removeLiquidity(  _elpAmount,address(0), 0);
    }

    function getPoolInfo() public view returns (uint256[] memory) {
        uint256[] memory poolInfo = new uint256[](4);
        poolInfo[0] = getAum(true);
        poolInfo[1] = 0;
        poolInfo[2] = IERC20(elp).totalSupply();
        poolInfo[3] = 0;
        return poolInfo;
    }


    function getPoolTokenList() public view returns (address[] memory) {
        return IVaultStorage(vault.vaultStorage()).fundingTokenList();
    }


    function getPoolTokenInfo(address _token) public view returns (uint256[] memory, int256[] memory) {
        // require(vault.whitelistedTokens(_token), "invalid token");
        // require(vault.isFundingToken(_token) || vault.isTradingToken(_token), "not )
        uint256[] memory tokenInfo_U= new uint256[](8);       
        int256[] memory tokenInfo_I = new int256[](4);       
        VaultMSData.TokenBase memory tBae = vault.getTokenBase(_token);

        VaultMSData.TokenBase memory tBase = vault.getTokenBase(_token);

        uint256 _poolAmount = vault.poolAmount(_token);
        tokenInfo_U[0] = 1000;
        tokenInfo_U[1] = _poolAmount > 0 ? vault.reservedAmount(_token).mul(1000000).div(_poolAmount) : 0;
        tokenInfo_U[2] = _poolAmount;//vault.getTokenBalance(_token).sub(vault.feeReserves(_token)).add(vault.feeSold(_token));
        tokenInfo_U[3] = IVaultPriceFeed(priceFeed).getPriceUnsafe(_token, true, false, false);
        tokenInfo_U[4] = IVaultPriceFeed(priceFeed).getPriceUnsafe(_token, false, false, false);
        tokenInfo_U[5] = tBase.fundingRatePerSec;
        tokenInfo_U[6] = tBase.accumulativefundingRateSec;
        tokenInfo_U[7] = tBase.latestUpdateTime;


        return (tokenInfo_U, tokenInfo_I);
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAumInUSD(bool maximise) public view returns (uint256) {
        return getAum(maximise);
    }

    function getAumSafe(bool maximise) public view returns (uint256) {
        address[] memory fundingTokenList = IVaultStorage(vault.vaultStorage()).fundingTokenList();
        address[] memory tradingTokenList = IVaultStorage(vault.vaultStorage()).tradingTokenList();

        uint256 aum = aumAddition;
        uint256 userShortProfits = 0;
        uint256 userLongProfits = 0;

        for (uint256 i = 0; i < fundingTokenList.length; i++) {
            address token = fundingTokenList[i];
            uint256 price = IVaultPriceFeed(priceFeed).getPrice(token, maximise, false, false);
            VaultMSData.TokenBase memory tBae = vault.getTokenBase(token);
            uint256 poolAmount = vault.poolAmount(token);
            uint256 decimals = tBae.decimal;
            poolAmount = poolAmount.mul(price).div(10 ** decimals);
            aum = aum.add(poolAmount);
        }

        for (uint256 i = 0; i < tradingTokenList.length; i++) {
            address token = tradingTokenList[i];
            VaultMSData.TradingRec memory tradingRec = vault.getTradingRec(token);

            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            uint256 shortSize = tradingRec.shortSize;
            if (shortSize > 0){
                uint256 averagePrice = tradingRec.shortAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = shortSize.mul(priceDelta).div(averagePrice);
                if (price > averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userShortProfits = userShortProfits.add(delta);
                }    
            }

            uint256 longSize = tradingRec.longSize;
            if (longSize > 0){
                uint256 averagePrice = tradingRec.longAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = longSize.mul(priceDelta).div(averagePrice);
                if (price < averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userLongProfits = userLongProfits.add(delta);
                }    
            }
        }

        uint256 _totalUserProfits = userLongProfits.add(userShortProfits);
        aum = _totalUserProfits > aum ? 0 : aum.sub(_totalUserProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);  
    }


    function getAum(bool maximise) public view returns (uint256) {
        address[] memory fundingTokenList = IVaultStorage(vault.vaultStorage()).fundingTokenList();
        address[] memory tradingTokenList = IVaultStorage(vault.vaultStorage()).tradingTokenList();
        uint256 aum = aumAddition;
        uint256 userShortProfits = 0;
        uint256 userLongProfits = 0;

        for (uint256 i = 0; i < fundingTokenList.length; i++) {
            address token = fundingTokenList[i];
            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            uint256 poolAmount = vault.poolAmount(token);
            VaultMSData.TokenBase memory tBae = vault.getTokenBase(token);
            uint256 decimals = tBae.decimal;
            poolAmount = poolAmount.mul(price).div(10 ** decimals);
            aum = aum.add(poolAmount);
        }

        for (uint256 i = 0; i < tradingTokenList.length; i++) {
            address token = tradingTokenList[i];
            VaultMSData.TradingRec memory tradingRec = vault.getTradingRec(token);

            uint256 price = IVaultPriceFeed(priceFeed).getPriceUnsafe(token, maximise, false, false);
            uint256 shortSize = tradingRec.shortSize;
            if (shortSize > 0){
                uint256 averagePrice = tradingRec.shortAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = shortSize.mul(priceDelta).div(averagePrice);
                if (price > averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userShortProfits = userShortProfits.add(delta);
                }    
            }

            uint256 longSize = tradingRec.longSize;
            if (longSize > 0){
                uint256 averagePrice = tradingRec.longAveragePrice;
                uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                uint256 delta = longSize.mul(priceDelta).div(averagePrice);
                if (price < averagePrice) {
                    aum = aum.add(delta);
                } else {
                    userLongProfits = userLongProfits.add(delta);
                }    
            }
        }

        uint256 _totalUserProfits = userLongProfits.add(userShortProfits);
        aum = _totalUserProfits > aum ? 0 : aum.sub(_totalUserProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);  
    }

}

