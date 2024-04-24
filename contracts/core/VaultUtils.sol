// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../utils/EnumerableValues.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";
import "./VaultMSData.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./interfaces/IVaultStorage.sol";
import "./FullMath.sol";


contract VaultUtils is IVaultUtils, Ownable {
    using SafeMath for uint256;
    
    bool public override inPrivateLiquidationMode = false;
    mapping(address => bool) public override isLiquidator;

    //Fees related to swap

    uint256 public override liquidationFeeUsd = 5 * VaultMSData.PRICE_PRECISION;

    uint256 public override taxBasisPoints = VaultMSData.COM_RATE_PRECISION * 5 / 1000; //0.5% default
    uint256 public override stableTaxBasisPoints     = 60; // 0.2%
    uint256 public override mintBurnFeeBasisPoints   = 0; // 0.3%
    uint256 public override swapFeeBasisPoints       = 30; // 0.3%
    uint256 public override stableSwapFeeBasisPoints = 10; // 0.04%
    uint256 public override marginFeeBasisPoints     = 10; // 0.1%

    uint256 public override maxLeverage     = VaultMSData.COM_RATE_PRECISION * 80 ; // 80x
    uint256 public override maxReserveRatio = VaultMSData.COM_RATE_PRECISION * 50 / 100; // 50% default
    uint256 public override maxProfitRatio  = VaultMSData.COM_RATE_PRECISION * 15; //15 times max
    
    uint256 public constant MAX_FEE_BASIS_POINTS = VaultMSData.COM_RATE_PRECISION * 5 / 100; // 5%   50000
    uint256 public constant MAX_NON_PROFIT_TIME = 25 minutes; // 5min
    uint256 public constant MAX_LIQUIDATION_FEE_USD = 200 * VaultMSData.PRICE_PRECISION; // 100 USD

    //Fees related to funding
    uint256 public baseFundingRatePerHour = VaultMSData.PRC_RATE_PRECISION * 1 / 10000 ; //0.01% per hour
    uint256 public baseFundingRatePerSec;

    struct TaxSetting{
        uint32 duration;
        uint32 nonProfitTime;
        uint64 taxMax;
    }
    TaxSetting public taxSetting;


    //trading profit limitation part

    IVault public immutable vault;
    mapping(uint256 => string) public override errors;


    struct SpreadSetting{
        uint64 basisMax;
        uint64 trigUSDx30;
        uint64 maxUSDx30;
        uint64 gapUSDx30;
    }
    mapping(address => SpreadSetting) public spreadSettings;



    event SetPriceSpreadBasis(address _token, uint256 _spreadBasis, uint256 _maxSpreadBasis, uint256 gapMax);
    event SetSizeSpreadBasis(address _token, uint256 _spreadBasis, uint256 _maxSpreadBasis, uint256 _minSpreadCalUSD);
    event SetPremiumRate(uint256 _premiumBasisPoints, int256 _posIndexMaxPoints, int256 _negIndexMaxPoints, uint256 _maxPremiumBasisErrorUSD);
    event SetFundingRate(uint256 _fundingRateFactor, uint256 _stableFundingRateFactor);
    event SetMaxLeverage(uint256 _maxLeverage);
    event SetTaxRate(uint256 _taxMax, uint256 _taxTime, uint256 _nonProfitTime);
    event SetFees(uint256 _taxBasisPoints,uint256 _stableTaxBasisPoints, uint256 _mintBurnFeeBasisPoints, uint256 _swapFeeBasisPoints, uint256 _stableSwapFeeBasisPoints, uint256 _marginFeeBasisPoints, uint256 _liquidationFeeUsd, bool _hasDynamicFees);


    constructor(IVault _vault) {
        vault = _vault;
        baseFundingRatePerSec = baseFundingRatePerHour.div(3600);
    }

    
    function setMaxReserveRatio(uint256 _setRatio) external onlyOwner{
        require(_setRatio <= VaultMSData.COM_RATE_PRECISION, "ratio small");
        maxReserveRatio = _setRatio;
    }

    function setMaxProfitRatio(uint256 _setRatio) external onlyOwner{
        require(_setRatio > VaultMSData.COM_RATE_PRECISION, "ratio small");
        maxProfitRatio = _setRatio;
    }

    function setSizeSpreadBasis(address _token, 
            uint64 _basisMax, uint64 _trigUSDx30, uint64 _maxUSDx30) external onlyOwner{

        require(_basisMax <= VaultMSData.COM_RATE_PRECISION / 2, "max basis"); //50% max
        require(_trigUSDx30 <= 1e10, "max trig"); //50% max
        require(_maxUSDx30 <= 1e10, "max trig"); //50% max
        require(_trigUSDx30 <= _maxUSDx30);

        if (_basisMax > 0)
            require(_maxUSDx30 > 0);

        spreadSettings[_token] = SpreadSetting({
                basisMax : _basisMax,
                trigUSDx30 : _trigUSDx30,
                maxUSDx30 : _maxUSDx30,
                gapUSDx30 : _maxUSDx30 - _trigUSDx30
            });
        emit SetSizeSpreadBasis(_token, _basisMax, _trigUSDx30, _maxUSDx30);
    }

    function setLiquidator(address _liquidator, bool _isActive) external override onlyOwner {
        isLiquidator[_liquidator] = _isActive;
    }

    function setInPrivateLiquidationMode(bool _inPrivateLiquidationMode) external override onlyOwner {
        inPrivateLiquidationMode = _inPrivateLiquidationMode;
    }



    function setFundingRate(uint256 _fundingRatePerHour) external onlyOwner {
        require(_fundingRatePerHour <= VaultMSData.PRC_RATE_PRECISION * 100 / 10000, "funding rate too large" ); //1% per hour max
        baseFundingRatePerHour = _fundingRatePerHour;
        baseFundingRatePerSec = _fundingRatePerHour.div(3600);
        emit SetFundingRate(baseFundingRatePerHour, baseFundingRatePerSec);
    }

    function setMaxLeverage(uint256 _maxLeverage) public override onlyOwner{
        require(_maxLeverage > VaultMSData.COM_RATE_PRECISION, "ERROR2");
        require(_maxLeverage < 200 * VaultMSData.COM_RATE_PRECISION, "Max leverage reached");
        maxLeverage = _maxLeverage;
        emit SetMaxLeverage(_maxLeverage);
    }



    function setTaxRate(uint64 _taxMax, uint32 _duration, uint32 _nonProfitTime) external onlyOwner{
        require(_taxMax <= VaultMSData.PRC_RATE_PRECISION, "TAX MAX exceed");
        require(_nonProfitTime <= MAX_NON_PROFIT_TIME, "Max non-profit time exceed.");
        require(_duration <= MAX_NON_PROFIT_TIME, "Max tax time exceed.");

        taxSetting = TaxSetting({
                duration: _duration,
                nonProfitTime : _nonProfitTime,
                taxMax : _taxMax
            });

        emit SetTaxRate(_taxMax, _duration, _nonProfitTime);
    }

    function setFees(
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd,
        bool _hasDynamicFees
    ) external override onlyOwner {
        require(_taxBasisPoints <= MAX_FEE_BASIS_POINTS, "3");
        require(_stableTaxBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR4");
        require(_mintBurnFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR5");
        require(_swapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR6");
        require(_stableSwapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR7");
        require(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, "ERROR8");
        require(_liquidationFeeUsd <= MAX_LIQUIDATION_FEE_USD, "ERROR9");
        taxBasisPoints = _taxBasisPoints;
        stableTaxBasisPoints = _stableTaxBasisPoints;
        mintBurnFeeBasisPoints = _mintBurnFeeBasisPoints;
        swapFeeBasisPoints = _swapFeeBasisPoints;
        stableSwapFeeBasisPoints = _stableSwapFeeBasisPoints;
        marginFeeBasisPoints = _marginFeeBasisPoints;
        liquidationFeeUsd = _liquidationFeeUsd;
        emit SetFees(_taxBasisPoints,_stableTaxBasisPoints, _mintBurnFeeBasisPoints, _swapFeeBasisPoints, _stableSwapFeeBasisPoints, _marginFeeBasisPoints, _liquidationFeeUsd, _hasDynamicFees);

    }

    function fundingRateSec(uint256 _resvAmount, uint256 _poolAmount) public view override returns (uint64){
        if (_poolAmount < 1)
            return 0;
        return uint64(FullMath.mulDiv(_resvAmount, baseFundingRatePerSec, _poolAmount));
    }

    function getNextIncreaseTime(uint256 _prev_time, uint256 _prev_size,uint256 _sizeDelta) public view override returns (uint256){
        return _prev_time.mul(_prev_size).add(_sizeDelta.mul(block.timestamp)).div(_sizeDelta.add(_prev_size));
    }         
    

    function validateDecreasePosition(VaultMSData.Position memory _position, uint256 _sizeDelta, uint256 _collateralDelta) external override view {
        // no additional validations
        _validate(_position.sizeUSD > 0, 30);
        _validate(_position.sizeUSD >= _sizeDelta, 21);
        _validate(_position.collateralUSD >= _collateralDelta, 22);

        // require(vault.isFundingToken(_position.collateralToken), "not funding token");
        // require(vault.isTradingToken(_position.indexToken), "not trading token");
    }

    function getPositionKey(address _account,address _collateralToken, address _indexToken, bool _isLong, uint256) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong) );
    }


    function getLiqPrice(bytes32 _key) public view override returns (int256){
        VaultMSData.Position memory position = vault.getPositionStructByKey(_key);
        // DecreaseCache memory decCache;
        if (position.sizeUSD < 1)
            return 0;

        (uint256 feeUsd, ) = vault.calFundingFee(position.sizeUSD, position.entryFundingRateSec, position.collateralToken);        

        feeUsd = feeUsd + getPositionFee(position.indexToken, position.sizeUSD);

        if (feeUsd > position.collateralUSD)
            return 0;

        uint256 colRemain = position.collateralUSD.sub(feeUsd);

        // uint256 _liqPriceDelta = colremain
        int256 _priceDelta = int256(FullMath.mulDiv(colRemain, position.averagePrice, position.sizeUSD ) );
        if (position.isLong){
            // size * (open - close) / open = colremain
            // open - col * open / size
            return int256(position.averagePrice) - _priceDelta;
        }else{
            // size * (close - open) / open = colremain
            // open + col * open / size
            return int256(position.averagePrice) + _priceDelta;      
        }
    }

    function getNextAveragePrice(uint256 _size, uint256 _averagePrice,  uint256 _nextPrice, uint256 _sizeDelta, bool _isIncrease) public pure override returns (uint256) {
        if (_size == 0) return _nextPrice;
        if (_isIncrease){
            uint256 nextSize = _size.add(_sizeDelta) ;
            return nextSize > 0 ? (_averagePrice.mul(_size)).add(_sizeDelta.mul(_nextPrice)).div(nextSize) : 0;   
        }
        else{
            uint256 _latestSize = _size > _sizeDelta ? _size.sub(_sizeDelta) : 0;
            uint256 _preAum = _averagePrice.mul(_size);
            uint256 _deltaAum =_sizeDelta.mul(_nextPrice);
            return (_latestSize > 0 && _preAum > _deltaAum) ? (_preAum.sub(_deltaAum)).div(_latestSize) : 0;
        }
    }



    function getPositionNextAveragePrice(uint256 _size, uint256 _averagePrice, uint256 _nextPrice, uint256 _sizeDelta, bool _isIncrease) public override pure returns (uint256) {
        if (_isIncrease){
            uint256 _tps = _averagePrice.mul(_nextPrice).div(VaultMSData.PRICE_PRECISION).mul(_size.add(_sizeDelta));
            uint256 _tpp = (_averagePrice.mul(_sizeDelta).add(_nextPrice.mul(_size))).div(VaultMSData.PRICE_PRECISION);
            require(_tpp > 0, "empty size");
            return _tps.div(_tpp);
            // return (_size.mul(_averagePrice)).add(_sizeDelta.mul(_nextPrice)).div(_size.add(_sizeDelta));
        }
        else{
            require(_size >= _sizeDelta, "invalid size delta");
            return _averagePrice;
            // return (_size.mul(_averagePrice)).sub(_sizeDelta.mul(_nextPrice)).div(_size.sub(_sizeDelta));
        }
    }

    function calculateTax(uint256 _profit, uint256 _aveIncreaseTime) public view override returns(uint256){     
    //         struct TaxSetting{
    //     uint32 duration;
    //     uint32 nonProfitTime;
    //     uint64 taxMax;
    // }
        TaxSetting memory _taxSetting = taxSetting;

        if (_taxSetting.taxMax < 1)
            return 0;
        uint32 _positionDuration = uint32(block.timestamp.sub(_aveIncreaseTime));

        if (_positionDuration >= _taxSetting.duration + _taxSetting.nonProfitTime)
            return 0;
       
        else if (_positionDuration >= _taxSetting.nonProfitTime){
            _positionDuration = _taxSetting.duration + _taxSetting.nonProfitTime - _positionDuration;
            uint256 _percent = FullMath.mulDiv(_taxSetting.taxMax, _positionDuration, _taxSetting.duration);
            return _profit.mul(_percent).div(VaultMSData.PRC_RATE_PRECISION);
        }
        else
            return _profit.mul(uint256(_taxSetting.taxMax)).div(VaultMSData.PRC_RATE_PRECISION);

    }

    function validateLiquidation(bytes32 _key, bool _raise) public view returns (bool){
        VaultMSData.Position memory position = vault.getPositionStructByKey(_key);
        return _validateLiquidation(position, _raise);
    }

    function validateLiquidationPar(address _account, 
                address _collateralToken, 
                address _indexToken, 
                bool _isLong, 
                bool _raise) public view returns (bool) {
        VaultMSData.Position memory position = vault.getPositionStructByKey(getPositionKey( _account, _collateralToken, _indexToken, _isLong, 0));
        return _validateLiquidation(position, _raise);
    }
    
    function _validateLiquidation(VaultMSData.Position memory position, bool _raise) public view returns (bool) {
        if (position.sizeUSD == 0) return false;
        
        address pricefeed = vault.priceFeed();
        uint256 _price = IVaultPriceFeed(pricefeed).getPriceUnsafe(position.indexToken, !position.isLong, true, true);
        (bool hasProfit, uint256 delta, ) = getDelta(position, _price);

        uint256 decOverall = 0; 
        (decOverall, position.entryFundingRateSec) = vault.calFundingFee(position.sizeUSD, position.entryFundingRateSec, position.collateralToken);        
        decOverall  += getPositionFee(position.indexToken, position.sizeUSD);
        if (!hasProfit){
            decOverall += delta;
        }
        bool isLiquidated = delta > position.collateralUSD;
        if (_raise)
            revert("position liquidated");
        return isLiquidated;
    }
    

    // function getDelta(address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _aveIncreasedTime, uint256 _colSize) public view override returns (bool, uint256) {
    function getDelta(VaultMSData.Position memory _position, uint256 _price) public view override returns (bool, uint256, uint256) {
        _validate(_position.averagePrice > 0, 23);
        // uint256 price = _isLong ? vault.getMinPrice(_indexToken) : vault.getMaxPrice(_indexToken);
        uint256 priceDelta = _position.averagePrice > _price ? _position.averagePrice.sub(_price) : _price.sub(_position.averagePrice);
        uint256 delta = FullMath.mulDiv(_position.sizeUSD, priceDelta, _position.averagePrice);
        bool hasProfit;
        uint256 termTax = 0;


        uint256 _nonProfitTime = uint256(taxSetting.nonProfitTime);

        if (_position.isLong) {
            hasProfit = _price > _position.averagePrice;
        } else {
            hasProfit = _position.averagePrice > _price;
        }       
        if (hasProfit){
            uint256 resvProfit = uint256(_position.reserveAmount) > _position.collateralUSD ? uint256(_position.reserveAmount).sub(_position.collateralUSD) : 0;
            delta = delta > resvProfit ? delta : resvProfit;
            if (maxProfitRatio > 0){
                uint256 _maxProfit = _position.collateralUSD.mul(maxProfitRatio).div(VaultMSData.COM_RATE_PRECISION);
                delta = delta > _maxProfit ? _maxProfit : delta;
            }
            if (_nonProfitTime > 0 && block.timestamp < uint256(_position.aveIncreaseTime).add(_nonProfitTime)){
                hasProfit = false;
                delta = 0;
            }
            else{
                termTax = calculateTax(delta, _position.aveIncreaseTime);
                if (termTax > 0)
                    delta = delta.sub(termTax, "taxCal");
            }

        }

        return (hasProfit, delta, termTax);
    }

    function getTaxSetting( ) public override view returns (   uint256 taxDuration, uint256 taxMax,uint256 nonProfitTime ) {
        taxDuration = taxSetting.duration;
        taxMax = taxSetting.taxMax;
        nonProfitTime = taxSetting.nonProfitTime;
    }

    function getSpread( address _token) public override view returns ( 
            uint256 spreadBasisMax,
            uint256 sizeSpreadGapStart,
            uint256 sizeSpreadGapMax){
        spreadBasisMax = uint256(spreadSettings[_token].basisMax);
        sizeSpreadGapStart = uint256(spreadSettings[_token].trigUSDx30).mul(VaultMSData.PRICE_PRECISION);
        sizeSpreadGapMax = uint256(spreadSettings[_token].maxUSDx30).mul(VaultMSData.PRICE_PRECISION);

    }




    function getPositionFee(address _indexToken, uint256 _sizeDelta) public override view returns (uint256) {
        if (_sizeDelta == 0) { return 0; }
        uint256 spreadBasisPoints = marginFeeBasisPoints;
        SpreadSetting memory _sprSet = spreadSettings[_indexToken];


        // struct SpreadSetting{
        //     uint64 basisMax;
        //     uint64 trigUSDx30;
        //     uint64 maxUSDx30;
        //     uint64 gapUSDx30;
        // }
        if (_sprSet.basisMax > 0){
            uint64 deltaUSDx30 = uint64(_sizeDelta.div(VaultMSData.PRICE_PRECISION));
            if (deltaUSDx30 > _sprSet.trigUSDx30){
                deltaUSDx30 = deltaUSDx30 - _sprSet.trigUSDx30;
                deltaUSDx30 = deltaUSDx30 > _sprSet.gapUSDx30 ? _sprSet.gapUSDx30 : deltaUSDx30;

                uint256 _spread = FullMath.mulDiv(_sprSet.basisMax, deltaUSDx30, _sprSet.gapUSDx30);
                spreadBasisPoints = spreadBasisPoints.add(_spread);
            }

        }
        return _sizeDelta.mul(spreadBasisPoints).div(VaultMSData.COM_RATE_PRECISION);
        // uint256 afterFeeUsd = _sizeDelta.mul(VaultMSData.COM_RATE_PRECISION.sub(spreadBasisPoints)).div(VaultMSData.COM_RATE_PRECISION);
        // return _sizeDelta.sub(afterFeeUsd);
    }

    // function getBuyLpFeeBasisPoints(address _token, uint256 _usdAmount) public override view returns (uint256) {
    function getBuyLpFeeBasisPoints(address, uint256) public override view returns (uint256) {
        return stableSwapFeeBasisPoints; 
        // return getFeeBasisPoints(_token, _usdAmount, mintBurnFeeBasisPoints, taxBasisPoints, true);
    }

    // function getSellLpFeeBasisPoints(address _token, uint256 _usdAmount) public override view returns (uint256) {
    function getSellLpFeeBasisPoints(address, uint256) public override view returns (uint256) {
        return stableSwapFeeBasisPoints; 
        // return getFeeBasisPoints(_token, _usdAmount, mintBurnFeeBasisPoints, taxBasisPoints, false);
    }

    function getSwapFeeBasisPoints(address _tokenIn, address _tokenOut, uint256 _usdAmount) public override view returns (uint256) {
        VaultMSData.TokenBase memory _tokenInBase = vault.getTokenBase(_tokenIn);
        VaultMSData.TokenBase memory _tokenOutBase = vault.getTokenBase(_tokenOut);
        bool isStableSwap = _tokenInBase.isStable && _tokenOutBase.isStable;
        uint256 baseBps = isStableSwap ? stableSwapFeeBasisPoints: swapFeeBasisPoints;
        uint256 taxBps = isStableSwap ? stableTaxBasisPoints : taxBasisPoints;
        uint256 feesBasisPoints0 = getFeeBasisPoints(_tokenIn, _usdAmount, baseBps, taxBps, true);
        uint256 feesBasisPoints1 = getFeeBasisPoints(_tokenOut, _usdAmount, baseBps, taxBps, false);
        // use the higher of the two fee basis points
        return feesBasisPoints0 > feesBasisPoints1 ? feesBasisPoints0 : feesBasisPoints1;
    }

    // cases to consider
    // 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
    // 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
    // 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
    // 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
    // 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
    // 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
    // 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
    // 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
    // function getFeeBasisPoints(address _token, uint256 _usdDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) public override view returns (uint256) {
    function getFeeBasisPoints(address, uint256 , uint256 _feeBasisPoints, uint256 , bool ) public override pure returns (uint256) {
        return _feeBasisPoints; 
    }


    function setErrorContenct(uint256[] memory _idxR, string[] memory _errorInstru) external onlyOwner{
        for(uint16 i = 0; i < _errorInstru.length; i++)
            errors[_idxR[i]] = _errorInstru[i];
    }

    function _validate(bool _condition, uint256 _errorCode) private view {
        require(_condition, string.concat(Strings.toString(_errorCode), errors[_errorCode]));
    }

    function tokenUtilization(address _token) public view  override returns (uint256) {
        // VaultMSData.TokenBase memory tokenBase = vault.getTokenBase(_token);
        uint256 _poolAmount = vault.poolAmount(_token);
        uint256 _reservedAmount = vault.reservedAmount(_token);
        return _poolAmount > 0 ? _reservedAmount.mul(1000000).div(_poolAmount) : 0;
    }


    function validLiq(address _account) public view override {
        if (inPrivateLiquidationMode) {
            require(isLiquidator[_account], "not liquidator");
        }
    }
}
