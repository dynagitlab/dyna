// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tokens/interfaces/IMintable.sol";
import "./VaultMSData.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./interfaces/IVaultStorage.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";
import "../DID/interfaces/IPID.sol";
import "../fee/interfaces/IUserFeeResv.sol";
import "./FullMath.sol";
import "./BlastBase.sol";

contract Vault is IVault, Ownable, BlastBase, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    IPID public pid;
    IVaultUtils public vaultUtils;
    address public override vaultStorage;
    address public override priceFeed;
    address public feeRouter;

    mapping(address => bool) public override isManager;
    mapping(address => bool) public override approvedRouters;

    mapping(address => uint256) public override balance;// tokenBalances is used only to determine _transferIn values
    mapping(address => uint256) public override poolAmount;// poolAmounts tracks the number of received tokens that can be used for leverage
                                // this is tracked separately from tokenBalances to exclude funds that are deposited as margin collateral
    mapping(address => uint256) public override reservedAmount;// reservedAmounts tracks the number of tokens reserved for open leverage positions

    uint256 public override globalShortSize;
    uint256 public override globalLongSize;

    mapping(address => VaultMSData.TokenBase) private tokenBase;
    // mapping(address => VaultMSData.TradingFee) tradingFee;
    mapping(bytes32 => VaultMSData.Position) private positions;
    mapping(address => VaultMSData.TradingRec) tradingRec;

    modifier onlyManager() {
        _validate(isManager[msg.sender], 4);
        _;
    }

    event Swap(address account, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 amountOutAfterFees, uint256 feeBasisPoints);
    event IncreasePosition(bytes32 key, address account, address collateralToken, address indexToken, uint256 collateralDelta, uint256 sizeDelta,bool isLong, uint256 price, uint256 fee);
    event DecreasePosition(bytes32 key, VaultMSData.Position position, uint256 collateralDelta, uint256 sizeDelta, uint256 price, int256 fee, uint256 usdOut, uint256 latestCollatral, uint256 prevCollateral);
    event DecreasePositionTransOut( bytes32 key,uint256 transOut);
    event LiquidatePosition(bytes32 key, address account, address collateralToken, address indexToken, bool isLong, uint256 size, uint256 collateral, uint256 reserveAmount, int256 realisedPnl, uint256 markPrice);
    event UpdatePosition(bytes32 key, address account, uint256 size,  uint256 collateral, uint256 averagePrice, uint256 entryFundingRate, uint256 reserveAmount, int256 realisedPnl, uint256 markPrice);
    event ClosePosition(bytes32 key, address account, uint256 size, uint256 collateral, uint256 averagePrice, uint256 entryFundingRate, uint256 reserveAmount, int256 realisedPnl);
    event UpdateFundingRate(address token, uint256 fundingRate);
    event UpdatePnl(bytes32 key, bool hasProfit, uint256 delta, uint256 currentSize, uint256 currentCollateral, uint256 usdOut, uint256 usdOutAfterFee);
    event CollectSwapFees(address token, uint256 feeUsd, uint256 feeTokens);
    event CollectMarginFees(address token, uint256 feeUsd, uint256 feeTokens);
    event DirectPoolDeposit(address token, uint256 amount);
    event IncreasePoolAmount(address token, uint256 amount);
    event DecreasePoolAmount(address token, uint256 amount);
    event IncreaseReservedAmount(address token, uint256 amount);
    event DecreaseReservedAmount(address token, uint256 amount);
    event IncreaseGuaranteedUsd(address token, uint256 amount);
    event DecreaseGuaranteedUsd(address token, uint256 amount);
    // event PayTax(address _account, bytes32 _key, uint256 profit, uint256 usdTax);
    // event UpdateGlobalSize(address _indexToken, uint256 tokenSize, uint256 globalSize, uint256 averagePrice, bool _increase, bool _isLong );
    event CollectPremiumFee(address account,uint256 _size, int256 _entryPremiumRate, int256 _premiumFeeUSD);
    event SetManager(address account, bool state);
    event SetRouter(address account, bool state);
    event SetTokenConfig(address _token, uint256 _tokenWeight, bool _isStable, bool _isFundingToken, bool _isTradingToken);
    // event ClearTokenConfig(address _token, bool del);


    // ---------- owner setting part ----------
    function setAdd(address[] calldata _addList) external override onlyOwner{
        vaultUtils = IVaultUtils(_addList[0]);
        vaultStorage = _addList[1];
        pid = IPID(_addList[2]);
        priceFeed = _addList[3];
        feeRouter = _addList[4];
    }

    function setManager(address _manager, bool _isManager) external override onlyOwner{
        isManager[_manager] = _isManager;
        emit SetManager(_manager, _isManager);
    }

    function setRouter(address _router, bool _status) external override onlyOwner{
        approvedRouters[_router] = _status;
        emit SetRouter(_router, _status);
    }

    function setTokenConfig(address _token, uint256 _tokenWeight, bool _isSwappable, bool _isStable, bool _isFundingToken, bool _isTradingToken) external onlyOwner{
        VaultMSData.TokenBase storage tBase = tokenBase[_token];
        IVaultStorage(vaultStorage).setTokenConfig(_token, _tokenWeight, _isStable, _isFundingToken, _isTradingToken);
        tBase.isStable = _isStable;
        tBase.isFundable = _isFundingToken;
        tBase.isSwappable = _isSwappable;
        tBase.isTradable = !_isStable;
        tBase.decimal = IMintable(_token).decimals();
        getMaxPrice(_token);// validate price feed
        emit SetTokenConfig(_token, _tokenWeight, _isStable, _isFundingToken, _isTradingToken);
    }

    function clearTokenConfig(address _token) external onlyOwner{
        IVaultStorage(vaultStorage).clearTokenConfig(_token);
        delete tokenBase[_token];
    }
    // the governance controlling this function should have a timelock
    function upgradeVault(address _newVault, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_newVault, _amount);
    }
    //---------- END OF owner setting part ----------



    //---------- FUNCTIONS FOR MANAGER ----------
    function buyUSD(address _token) external override nonReentrant onlyManager returns (uint256) {
        _validate(tokenBase[_token].isFundable, 6);
        _updateRate(_token);//update first to calculate fee
        uint256 tokenAmount = _transferIn(_token);
        _validate(tokenAmount > 0, 7);

        uint256 feeInToken = _collectSwapFee(_token, tokenAmount, vaultUtils.getBuyLpFeeBasisPoints(_token, 0));
        tokenAmount = tokenAmount.sub(feeInToken);
        _increasePoolAmount(_token, tokenAmount);
        _updateRate(_token);//update first to calculate fee
        return tokenToUsdMin(_token, tokenAmount);
    }

    function sellUSD(address _token, address _receiver,  uint256 _usdAmount) external override nonReentrant onlyManager returns (uint256) {
        _validate(tokenBase[_token].isFundable, 6);
        _validate(_usdAmount > 0, 9);
        _updateRate(_token);
        uint256 redemptionTokenAmount = usdToTokenMin(_token, _usdAmount);
        _validate(redemptionTokenAmount > 0, 10);
        _decreasePoolAmount(_token, redemptionTokenAmount);

        uint256 feeInToken = _collectSwapFee(_token, redemptionTokenAmount, vaultUtils.getSellLpFeeBasisPoints(_token, _usdAmount));
        redemptionTokenAmount = redemptionTokenAmount.sub(feeInToken);
        _transferOut(_token, redemptionTokenAmount, _receiver);
        _updateRate(_token);//update first to calculate fee
        return redemptionTokenAmount;
    }


    //---------------------------------------- TRADING FUNCTIONS --------------------------------------------------
    function swap(address _tokenIn,  address _tokenOut, address _receiver ) external nonReentrant override returns (uint256) {
        _validate(approvedRouters[msg.sender], 20);
        return _swap(_tokenIn, _tokenOut, _receiver);
    }


    function increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external nonReentrant override {
        _validate(approvedRouters[msg.sender], 20);
        bytes32 key = vaultUtils.getPositionKey( _account, _collateralToken, _indexToken, _isLong, 0);
        VaultMSData.Position memory position = positions[key];
        _validate(tokenBase[_collateralToken].isFundable, 6);
        _validate(tokenBase[_indexToken].isTradable, 5);
        //update cumulative funding rate
        // if (_indexToken!= _collateralToken)_updateRate(_indexToken);
        // vaultUtils.validateIncreasePosition(_collateralToken, _indexToken, position.sizeUSD, _sizeDelta ,_isLong);

        uint256 price = _isLong ? getMaxPrice(_indexToken) : getMinPrice(_indexToken);
        // uint64 _accumulativefundingRateSec = 0;
        // {
        //     VaultMSData.TokenBase memory tBase = tokenBase[_collateralToken];
        //     uint256 timepastSec = tBase.latestUpdateTime > 0 ? block.timestamp.sub(_tradingFee.latestUpdateTime) : 0;
        //     _accumulativefundingRateSec = tBase.accumulativefundingRateSec + uint128(uint256(tBase.fundingRatePerSec).mul(timepastSec));
        // }
    
        uint256 feeUsd = 0;
        (feeUsd, position.entryFundingRateSec) = calFundingFee(position.sizeUSD, position.entryFundingRateSec, position.collateralToken);

        if (position.sizeUSD == 0) {
            position.account = _account;
            position.averagePrice = price;
            position.aveIncreaseTime = uint32(block.timestamp);
            position.collateralToken = _collateralToken;
            position.indexToken = _indexToken;
            position.isLong = _isLong;       
        }
        else if (position.sizeUSD > 0 && _sizeDelta > 0) {
            position.aveIncreaseTime = uint32(vaultUtils.getNextIncreaseTime(position.aveIncreaseTime, position.sizeUSD, _sizeDelta)); 
            position.averagePrice = vaultUtils.getPositionNextAveragePrice(position.sizeUSD, position.averagePrice, price, _sizeDelta, true);
        }
        
        uint128 _colIn = _transferIn(_collateralToken);
        uint256 collateralDeltaUsd = 0;
        if (_colIn > 0){
            position.colInAmount += _colIn;
            collateralDeltaUsd = tokenToUsdMin(_collateralToken, _colIn);
            position.collateralUSD = position.collateralUSD.add(collateralDeltaUsd);
        }

        if (_sizeDelta > 0){
            feeUsd = feeUsd.add(vaultUtils.getPositionFee(position.indexToken, _sizeDelta));
            position.sizeUSD = position.sizeUSD.add(_sizeDelta);
        }
        _validate(_colIn + _sizeDelta > 0, 8);

        if (feeUsd > 0){
            _validate(position.collateralUSD > feeUsd, 14);
            uint256 feeInColToken = usdToTokenMax(position.collateralToken, feeUsd);
            _validate(position.colInAmount > feeInColToken, 14);

            // collateral subtraction
            position.collateralUSD = position.collateralUSD.sub(feeUsd);
            position.colInAmount -= uint128(feeInColToken);

            _transferOut(position.collateralToken, feeInColToken, feeRouter); 

            emit CollectMarginFees(position.collateralToken, feeUsd, feeInColToken);
        }

        //decrease 
        // _decreaseGuaranteedUsd(_position.collateralToken, feeUsd);
        //decrease pool into fee
        // _collectFeeResv(_position.account, _position.collateralToken, feeUsd);
        //call_updateRate before collect Margin Fees
        // uint256 fee = _collectMarginFees(key, _sizeDelta); //increase collateral before collectMarginFees
        
        // run after collectMarginFees

        _validate(position.sizeUSD > 0, 15);
        _validatePosition(position.sizeUSD, position.collateralUSD);

        _validate(position.collateralUSD.mul(IVaultUtils(vaultUtils).maxLeverage()) > position.sizeUSD, 0);
        _validate(position.collateralUSD < position.sizeUSD, 17);
        // vaultUtils.validateLiquidationPos(position, true);//TODO: opt.to save gas

        // reserve tokens to pay profits on the position
        {
            uint256 _newReserveAmount = usdToTokenMax(_collateralToken, position.sizeUSD);
            if (position.reserveAmount > _newReserveAmount){
                _decreaseReservedAmount(_collateralToken, position.reserveAmount - _newReserveAmount);
            }
            else{
                _increaseReservedAmount(_collateralToken, _newReserveAmount - position.reserveAmount);
            }
            position.reserveAmount = uint128(_newReserveAmount);
        }
       
        _updateGlobalSize(_isLong, _indexToken, _sizeDelta, price, true);
    
        //update rates according to latest positions and token utilizations
        _updateRate(_collateralToken);
        // if (_indexToken!= _collateralToken)_updateRate(_indexToken);            
        
        // sWrite to update
        positions[key] = position;
        IVaultStorage(vaultStorage).addKey(_account,key);
        emit IncreasePosition(key, _account, _collateralToken, _indexToken, collateralDeltaUsd,
            _sizeDelta, _isLong, price, feeUsd);
        emit UpdatePosition( key, _account, position.sizeUSD, position.collateralUSD, position.averagePrice,
            position.entryFundingRateSec * (3600) / (1000000), position.reserveAmount, position.realisedPnl, price );
    }


    function decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver
        ) external nonReentrant override returns (uint256, bool) {
        _validate(approvedRouters[msg.sender], 20);
        bytes32 key = vaultUtils.getPositionKey(_account, _collateralToken, _indexToken, _isLong, 0);
        return _decreasePosition(key, _collateralDelta, _sizeDelta, _receiver, _receiver);
    }

    struct DecreaseCache{
        bool posIsDel;
        bool hasProfit;
        uint256 delta;
    }

    function _decreasePosition(
            bytes32 _key, 
            uint256 _collateralDeltaUsd, 
            uint256 _sizeDelta, 
            address _receiver, 
            address _feeReceipt) private returns (uint256 amountOut, bool posIsLiq) {

        VaultMSData.Position memory position = positions[_key];
        if (_sizeDelta < 1)
            _sizeDelta = position.sizeUSD;

        DecreaseCache memory decCache;

        vaultUtils.validateDecreasePosition(position, _sizeDelta, _collateralDeltaUsd);
        
        if (_collateralDeltaUsd == position.collateralUSD){
            _collateralDeltaUsd = 0;
            _sizeDelta = position.sizeUSD;
            decCache.posIsDel = true;
        }
        else if (_sizeDelta == position.sizeUSD){
            decCache.posIsDel = true;
            _collateralDeltaUsd = 0;
        }

        uint256 _price = position.isLong ? getMinPrice(position.indexToken) : getMaxPrice(position.indexToken); 
        (decCache.hasProfit, decCache.delta, ) = vaultUtils.getDelta(position, _price);

        {
            uint256 feeUsd = 0; 
            (feeUsd, position.entryFundingRateSec) = calFundingFee(position.sizeUSD, position.entryFundingRateSec, position.collateralToken);        

            uint256 positionFeeUsd = vaultUtils.getPositionFee(position.indexToken, position.sizeUSD);
            uint256 unPft = feeUsd + positionFeeUsd + (decCache.hasProfit ? 0 : decCache.delta);
            if (unPft >= position.collateralUSD){
                posIsLiq = true;
                decCache.posIsDel = true;
                _sizeDelta = position.sizeUSD;
            }
            else if (!decCache.posIsDel){ // if isDelete position, sizeDelta = positionSize, combine to save gas
                unPft = unPft + _collateralDeltaUsd;
                _validate(position.collateralUSD > unPft, 2);
                _validate((position.collateralUSD - unPft) * vaultUtils.maxLeverage() > position.sizeUSD, 0);
                decCache.delta = FullMath.mulDiv(decCache.delta, _sizeDelta, position.sizeUSD);
                positionFeeUsd = FullMath.mulDiv(positionFeeUsd, _sizeDelta, position.sizeUSD);
            }


            
            feeUsd = feeUsd + positionFeeUsd;

            // _validate(position.collateralUSD > feeUsd, 29);
            if (feeUsd > position.collateralUSD){
                feeUsd = position.collateralUSD;
                position.collateralUSD = 0;
                posIsLiq = true;
                _sizeDelta = position.sizeUSD;
            }else{
                position.collateralUSD = position.collateralUSD.sub(feeUsd);
            }

            // transfer fee from collateral to fee router
            uint256 feeInColToken = usdToTokenMax(position.collateralToken, feeUsd);
            if (posIsLiq){
                uint256 _liqFeeUsd = vaultUtils.liquidationFeeUsd();
                if (feeUsd > _liqFeeUsd){
                    feeUsd = feeUsd - _liqFeeUsd;
                    uint256 _tokenLiq = FullMath.mulDiv(_liqFeeUsd, feeInColToken, feeUsd);
                    _transferOut(position.collateralToken, _tokenLiq, _feeReceipt); 
                    feeInColToken -= _tokenLiq;
                }
            }

            feeInColToken = feeInColToken > position.colInAmount ?  position.colInAmount : feeInColToken;
            position.colInAmount -= uint128(feeInColToken);
            _transferOut(position.collateralToken, feeInColToken, feeRouter); 
            
            emit CollectMarginFees(position.collateralToken, feeUsd, feeInColToken);
        }


        _decreaseReservedAmount(position.collateralToken, position.reserveAmount);
        if (position.collateralUSD < 1 || posIsLiq ){
            //settle directly
            decCache.posIsDel = true;
            _sizeDelta = position.sizeUSD;
            emit LiquidatePosition(_key, position.account, position.collateralToken,position.indexToken, position.isLong,
                 position.sizeUSD, position.collateralUSD, position.reserveAmount, position.realisedPnl, _price);
        }
        else{
            if (decCache.hasProfit){
                amountOut = usdToTokenMin(position.collateralToken, decCache.delta);
                _decreasePoolAmount(position.collateralToken, amountOut);
                position.realisedPnl = position.realisedPnl + int256(decCache.delta);
            }
            else{
                position.collateralUSD = position.collateralUSD > decCache.delta? position.collateralUSD - decCache.delta : 0;
                position.realisedPnl = position.realisedPnl - int256(decCache.delta);
            }
            emit UpdatePnl(_key, decCache.hasProfit, decCache.delta, position.sizeUSD, position.collateralUSD, amountOut, decCache.delta);
           
            position.sizeUSD = position.sizeUSD.sub(_sizeDelta);
            if (position.sizeUSD < 1){
                decCache.posIsDel = true;
                _collateralDeltaUsd = position.collateralUSD;
            }

            if (_collateralDeltaUsd > 0){
                _validate(position.collateralUSD >= _collateralDeltaUsd, 2);
                position.collateralUSD = position.collateralUSD.sub(_collateralDeltaUsd);
                uint256 _colOutAmount = usdToTokenMin(position.collateralToken, _collateralDeltaUsd);
                _colOutAmount = _colOutAmount > position.colInAmount ? position.colInAmount : _colOutAmount;
                position.colInAmount -= uint128(_colOutAmount);
                amountOut += _colOutAmount;
            }
            _transferOut(position.collateralToken, amountOut, _receiver); 


            _validatePosition(position.sizeUSD, position.collateralUSD);

            uint256 _newReserveAmount = usdToTokenMax(position.collateralToken, position.sizeUSD);
            _increaseReservedAmount(position.collateralToken, _newReserveAmount);
            
            // vaultUtils.validateLiquidation(_key, true);
            
            emit UpdatePosition(_key, position.account, position.sizeUSD, position.collateralUSD, position.averagePrice, position.entryFundingRateSec,
                    position.reserveAmount, position.realisedPnl, _price);
        }


        _updateGlobalSize(position.isLong, position.indexToken, _sizeDelta, position.averagePrice, false);

        
        // // scrop variables to avoid stack too deep errors
        // {
        //     //do not add spread price impact in decrease position
        //     emit DecreasePosition( key, position, _collateralDelta, _sizeDelta, price, int256(usdOut) - int256(usdOutAfterFee), usdOut, position.collateralUSD, collateral);
        //     if (position.sizeUSD != _sizeDelta) {
        //         // position.entryFundingRateSec = tradingFee[_collateralToken].accumulativefundingRateSec;
        //         position.sizeUSD = position.sizeUSD.sub(_sizeDelta);
        //         _validatePosition(position.sizeUSD, position.collateralUSD);
        //     } else {
        //         // _decreaseReservedAmount(position.collateralToken, position.reserveAmount);
        //         position.sizeUSD = 0;
        //         _del = true;
        //     }
        // }
        // update global trading size and average prie
        // _updateGlobalSize(position.isLong, position.indexToken, position.sizeUSD, position.averagePrice, true);

        _updateRate(position.collateralToken);
        
        positions[_key] = position;
        
        // if (position.indexToken!= position.collateralToken)_updateRate(position.indexToken);
        if (decCache.posIsDel || posIsLiq) {
            emit ClosePosition(_key, position.account,
                position.sizeUSD, position.collateralUSD,position.averagePrice, position.entryFundingRateSec * (3600) / (1000000), position.reserveAmount, position.realisedPnl);
            if (position.colInAmount > 0){
                _increasePoolAmount(position.collateralToken, position.colInAmount);
            }
            _delPosition(position.account, _key);
        }
        // return usdOutAfterFee;
    }



    function liquidatePosition(address _account, address _collateralToken, address _indexToken, bool _isLong, address _feeReceiver) external override {
        vaultUtils.validLiq(msg.sender);
        _updateRate(_collateralToken);
        // if (_indexToken!= _collateralToken)_updateRate(_indexToken);
        bytes32 key = vaultUtils.getPositionKey(_account, _collateralToken, _indexToken, _isLong, 0);

        (, bool posIsLiq) = _decreasePosition(key, 0, 0, _account, _feeReceiver);
        _validate(posIsLiq, 1);
    }
    
    //---------- PUBLIC FUNCTIONS ----------
    function directPoolDeposit(address _token) external nonReentrant override {
        _validate(tokenBase[_token].isFundable, 6);
        uint256 tokenAmount = _transferIn(_token);
        _validate(tokenAmount > 0, 7);
        _increasePoolAmount(_token, tokenAmount);
        emit DirectPoolDeposit(_token, tokenAmount);
    }

    function getMaxPrice(address _token) public view override returns (uint256) {
        return IVaultPriceFeed(priceFeed).getPrice(_token, true, true, true);
    }
    function getMinPrice(address _token) public view override returns (uint256) {
        return IVaultPriceFeed(priceFeed).getPrice(_token, false, true, true);
    }
    function tokenToUsdMin(address _token, uint256 _tokenAmount) public view override returns (uint256) {
        uint256 price = getMinPrice(_token);
        uint256 decimals = tokenBase[_token].decimal;
        return FullMath.mulDiv(_tokenAmount, price, 10**decimals);
    }
    function usdToTokenMax(address _token, uint256 _usdAmount) public override view returns (uint256) {
        return _usdAmount > 0 ? usdToToken(_token, _usdAmount, getMinPrice(_token)) : 0;
    }
    function usdToTokenMin(address _token, uint256 _usdAmount) public override view returns (uint256) {
        return _usdAmount > 0 ? usdToToken(_token, _usdAmount, getMaxPrice(_token)) : 0;
    }
    function usdToToken( address _token, uint256 _usdAmount, uint256 _price ) public view returns (uint256) {
        uint256 decimals = tokenBase[_token].decimal;
        require(decimals > 0 && _price > 0);
        return FullMath.mulDiv(_usdAmount, 10**decimals, _price);
    }

    function getPositionStructByKey(bytes32 _key) public override view returns (VaultMSData.Position memory){
        return positions[_key];
    }
    function getTokenBase(address _token) public override view returns (VaultMSData.TokenBase memory){
        return tokenBase[_token];
    }
    function getTradingRec(address _token) public override view returns (VaultMSData.TradingRec memory){
        return tradingRec[_token];
    }
    //---------- END OF PUBLIC VIEWS ----------



    //---------------------------------------- PRIVATE Functions --------------------------------------------------
    function calFundingFee(
            uint256 _positionSizeUSD, 
            uint256 _entryFundingRateSec, 
            address _colToken) public override view returns (uint256 feeUsd, uint128 _accumulativefundingRateSec){
        
        VaultMSData.TokenBase memory tBase = tokenBase[_colToken];
        uint256 timepastSec = tBase.latestUpdateTime > 0 ? block.timestamp.sub(tBase.latestUpdateTime) : 0;
        _accumulativefundingRateSec = tBase.accumulativefundingRateSec + uint128(uint256(tBase.fundingRatePerSec).mul(timepastSec));
        
        if (_positionSizeUSD > 0 && _entryFundingRateSec < _accumulativefundingRateSec){
            feeUsd = FullMath.mulDiv(_accumulativefundingRateSec - _entryFundingRateSec, _positionSizeUSD, VaultMSData.PRC_RATE_PRECISION);
        }
    }

    function _updateRate(address _token) private {
        // VaultMSData.TradingFee memory _tradingFee = tradingFee[_token];
        VaultMSData.TokenBase memory tBase = tokenBase[_token];
        // require(tBase.isFundingToken, "ft");
        // if (!tBase.isFundable)
        //     return 0;
        uint256 timepastSec = tBase.latestUpdateTime > 0 ? block.timestamp.sub(tBase.latestUpdateTime) : 0;
        if (timepastSec < 1)
            return ;
        
        tBase.latestUpdateTime = uint32(block.timestamp);

        tBase.accumulativefundingRateSec += uint128(uint256(tBase.fundingRatePerSec).mul(timepastSec));
        tBase.fundingRatePerSec = IVaultUtils(vaultUtils).fundingRateSec(reservedAmount[_token], poolAmount[_token]);
        tokenBase[_token] = tBase;
    }

    function _swap(address _tokenIn,  address _tokenOut, address _receiver ) private returns (uint256) {
        _validate(tokenBase[_tokenIn].isSwappable, 11);
        _validate(tokenBase[_tokenOut].isSwappable, 12);
        _validate(_tokenIn != _tokenOut, 13);
        _updateRate(_tokenIn);
        _updateRate(_tokenOut);

        uint256 amountIn = _transferIn(_tokenIn);
        _validate(amountIn > 0, 7);
        uint256 _amountInUsd = tokenToUsdMin(_tokenIn, amountIn);
        uint256 feeBasisPoints = vaultUtils.getSwapFeeBasisPoints(_tokenIn, _tokenOut, _amountInUsd);

        uint256 feeInToken = _collectSwapFee(_tokenIn, amountIn, feeBasisPoints);
        
        amountIn = amountIn.sub(feeInToken);
        _increasePoolAmount(_tokenIn, amountIn);

        _amountInUsd = tokenToUsdMin(_tokenIn, amountIn);
        uint256 _amountOut = usdToTokenMin(_tokenOut, _amountInUsd);

        _decreasePoolAmount(_tokenOut, _amountOut);
        _transferOut(_tokenOut, _amountOut, _receiver);
        
        _updateRate(_tokenIn);
        _updateRate(_tokenOut);
        emit Swap( _receiver, _tokenIn, _tokenOut, amountIn, _amountOut, _amountOut, feeBasisPoints);
        return _amountOut;
    }



    function _validatePosition(uint256 _size, uint256 _collateral) private view {
        if (_size == 0) {
            _validate(_collateral == 0, 16);
            return;
        }
        _validate(_size >= _collateral, 40);
        _validate(_size < _collateral * vaultUtils.maxLeverage(), 0);
    }
    
    function _collectSwapFee(address _token, uint256 _amount, uint256 _feeBasisPoints) private returns (uint256) {
        uint256 fee = _amount
            .mul(_feeBasisPoints)
            .div(VaultMSData.COM_RATE_PRECISION);
        //_feeTokenAmount : swap fee rep. in token
        // uint256 _feeTokenAmount = _amount.sub(afterFeeAmount);//usdToTokenMin(_token, feeUSD);
        //decrease fee in pool
        // _decreasePoolAmount(_token, _feeTokenAmount);
        //and transfer to eusd collateral pool.
        _transferOut(_token, fee, feeRouter); 

        emit CollectSwapFees(_token, fee, _amount);
        return fee;
    }


    function _transferIn(address _token) private returns (uint128) {
        uint256 prevBalance = balance[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        require(nextBalance >= prevBalance);
        balance[_token] = nextBalance;
        return uint128(nextBalance.sub(prevBalance));
    }

    function _transferOut( address _token, uint256 _amount, address _receiver ) private {
        if (_amount > 0)
            IERC20(_token).safeTransfer(_receiver, _amount);
        balance[_token] = IERC20(_token).balanceOf(address(this));
    }

    function _increasePoolAmount(address _token, uint256 _amount) private {
        poolAmount[_token] = poolAmount[_token].add(_amount);
        emit IncreasePoolAmount(_token, _amount);
    }

    function _decreasePoolAmount(address _token, uint256 _amount) private {
        poolAmount[_token] = poolAmount[_token].sub(_amount, "PoolAmount exceeded");
        // require(poolAmount[_token])
        emit DecreasePoolAmount(_token, _amount);
    }

    function _increaseReservedAmount(address _token, uint256 _amount) private {
        if(_amount < 1)
            return ;
        reservedAmount[_token] = reservedAmount[_token].add(_amount);
        _validate(
            reservedAmount[_token]
            <= 
            poolAmount[_token].mul(vaultUtils.maxReserveRatio()) / VaultMSData.COM_RATE_PRECISION, 
            18);
        emit IncreaseReservedAmount(_token, _amount);
    }

    function _decreaseReservedAmount(address _token, uint256 _amount) private {
        // reservedAmount[_token] = reservedAmount[_token].sub( _amount, "Vault: insufficient reserve" );
        reservedAmount[_token] = reservedAmount[_token] > _amount ?
                                  reservedAmount[_token] - _amount : 0;
        emit DecreaseReservedAmount(_token, _amount);
    }

    function _validate(bool _condition, uint256 _errorCode) private view {
        require(_condition, vaultUtils.errors(_errorCode));
    }

    function _updateGlobalSize(bool _isLong, address _indexToken, uint256 _sizeDelta, uint256 _price, bool _increase) private {
        VaultMSData.TradingRec storage ttREC = tradingRec[_indexToken];
        if (_isLong) {
            ttREC.longAveragePrice = vaultUtils.getNextAveragePrice(ttREC.longSize,  ttREC.longAveragePrice, _price, _sizeDelta, _increase);
            if (_increase){
                ttREC.longSize = ttREC.longSize.add(_sizeDelta);
                globalLongSize = globalLongSize.add(_sizeDelta);
            }else{
                ttREC.longSize = ttREC.longSize.sub(_sizeDelta);
                globalLongSize = globalLongSize.sub(_sizeDelta);
            }
            // emit UpdateGlobalSize(_indexToken, ttREC.longSize, globalLongSize,ttREC.longAveragePrice, _increase, _isLong );
        } else {
            ttREC.shortAveragePrice = vaultUtils.getNextAveragePrice(ttREC.shortSize,  ttREC.shortAveragePrice, _price, _sizeDelta, _increase);  
            if (_increase){
                ttREC.shortSize = ttREC.shortSize.add(_sizeDelta);
                globalShortSize = globalShortSize.add(_sizeDelta);
            }else{
                ttREC.shortSize = ttREC.shortSize.sub(_sizeDelta);
                globalShortSize = globalShortSize.sub(_sizeDelta);    
            }
            // emit UpdateGlobalSize(_indexToken, ttREC.shortSize, globalShortSize,ttREC.shortAveragePrice, _increase, _isLong );
        }
    }

    function _delPosition(address _account, bytes32 _key) private {
        delete positions[_key];
        IVaultStorage(vaultStorage).delKey(_account, _key);
    }


}
