// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../utils/EnumerableValues.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "../tokens/interfaces/IMintable.sol";


interface IServerPriceFeed {
    function getPrice(address _token) external view returns (uint256, uint256);
}

interface PythStructs {
    struct Price {
        int64 price;// Price
        uint64 conf;// Confidence interval around the price
        int32 expo;// Price exponent
        uint publishTime;// Unix timestamp describing when the price was published
    }
}

interface IPyth {
    function queryPriceFeed(bytes32 id) external view returns (PythStructs.Price memory price);
    function priceFeedExists(bytes32 id) external view returns (bool exists);
    function getValidTimePeriod() external view returns(uint validTimePeriod);
    function getPrice(bytes32 id) external view returns (PythStructs.Price memory price);
    function getUpdateFee(bytes[] memory data) external view returns (uint256);
    function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);
    function updatePriceFeedsIfNecessary(bytes[] memory updateData,bytes32[] memory priceIds,uint64[] memory publishTimes) payable external;
    function updatePriceFeeds(bytes[]memory updateData) payable external;
}


contract VaultPriceFeed is IVaultPriceFeed, Ownable {
    using SafeMath for uint256;
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant MIN_PRICE_THRES = 10 ** 20;
    uint256 public constant PRICE_VARIANCE_PRECISION = 10000;
    uint256 public constant MAX_SPREAD_BASIS_POINTS =   50000; //5% max
    uint256 public constant BASIS_POINTS_DIVISOR    = 1000000; //

    struct TokenInfo {
        bytes32 pythKey;
        address token;
        uint24 priceSpreadBasisMax;
        uint24 spreadTimeStart;
        uint24 spreadTimeMax;
        bool isStable;
    }

    EnumerableSet.AddressSet private tokens;
    mapping(address => TokenInfo) private tokensInfo;
    mapping(address => bool) public isStrictStable;


    //global setting
    uint256 public nonstablePriceSafetyTimeGap = 55; //seconds
    uint256 public stablePriceSafetyTimeGap = 1 hours;

    IPyth public pyth;

    event UpdatePriceFeedsIfNecessary(bytes[] updateData, bytes32[] priceIds,uint64[] publishTimes);
    event UpdatePriceFeeds(bytes[] updateData);
    event DepositFee(address _account, uint256 _value);
    event SetStrictStableToken(address _token, bool _sta);


    function depositFee() external payable {
        emit DepositFee(msg.sender, msg.value);
    }

    //----- owner setting
    function setServerOracle(address _pyth) external onlyOwner{
        pyth = IPyth(_pyth);
    }

    function initTokens(address[] memory _tokenList, bool[] memory _isStable, bytes32[] memory _key) external onlyOwner {
        for(uint8 i = 0; i < _tokenList.length; i++) {
            require(_key[i] !=  bytes32(0) && pyth.priceFeedExists(_key[i]), "key not exist in pyth");
            if (!tokens.contains(_tokenList[i])){
                tokens.add(_tokenList[i]);
            }
            tokensInfo[_tokenList[i]].token = _tokenList[i];
            tokensInfo[_tokenList[i]].isStable = _isStable[i];
            tokensInfo[_tokenList[i]].pythKey = _key[i];
        }
    }

    function setStrictStableToken(address _token, bool _sta) external onlyOwner{
        isStrictStable[_token] = _sta;
        emit SetStrictStableToken(_token, _sta);
    }
    
    function deleteToken(address[] memory _tokenList) external onlyOwner {
        for(uint8 i = 0; i < _tokenList.length; i++) {
            if (tokens.contains(_tokenList[i])){
                tokens.remove(_tokenList[i]);
            }
            delete tokensInfo[_tokenList[i]];
        }
    }

    function setGap(uint256 _priceSafetyTimeGap,uint256 _stablePriceSafetyTimeGap, uint256) external override onlyOwner {
        nonstablePriceSafetyTimeGap = _priceSafetyTimeGap;
        stablePriceSafetyTimeGap = _stablePriceSafetyTimeGap;
    }
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    function setSpreadBasisPoints(address _token, uint24 _priceSpreadMax,
            uint24 _spreadTimeStart, uint24 _spreadTimeMax) external override onlyOwner {
        _validToken(_token);
        require(_priceSpreadMax <= MAX_SPREAD_BASIS_POINTS, "msbp");
        require(_spreadTimeStart <= _spreadTimeMax, "xT");
        tokensInfo[_token].priceSpreadBasisMax = _priceSpreadMax;
        tokensInfo[_token].spreadTimeStart = _spreadTimeStart;
        tokensInfo[_token].spreadTimeMax = _spreadTimeMax;
    }
    //----- end of owner setting


    //----- interface for pyth update 
    function updatePriceFeeds(bytes[] memory updateData) override external{
        uint256 updFee = _validUpdateFee(updateData);
        pyth.updatePriceFeeds{value:updFee}(updateData);
        emit UpdatePriceFeeds(updateData);
    }


    //----- public view 
    function isSupportToken(address _token) public view returns (bool){
        return tokens.contains(_token);
    }
    function priceTime(address _token) external view override returns (uint256){
        (, , uint256 pyUpdatedTime) = getPythPrice(_token);
        return pyUpdatedTime;
    }
    //----- END of public view 


    function _getCombPrice(address _token, bool _maximise, uint256 _curTime) internal view returns (uint256, uint256){
        uint256 _price = 0;
        uint256 pyUpdatedTime = 0;
        bool statePy;
        (_price, statePy, pyUpdatedTime) = getPythPrice(_token);
        require(statePy, "[Oracle] price failed.");
        _price = _addBasisSpread(_token, _price, pyUpdatedTime, _maximise, _curTime);
        require(_price > 0, "[Oracle] ORACLE FAILS");
        return (_price, pyUpdatedTime);    
    }

    function _getOgPrice(address _token) internal view returns (uint256, uint256){
        // uint256 cur_timestamp = block.timestamp;
        (uint256 pricePy, bool statePy, uint256 pyUpdatedTime) = getPythPrice(_token);
        require(statePy, "[Oracle] price failed.");
        require(pricePy > 0, "[Oracle] ORACLE FAILS");
        return (pricePy, pyUpdatedTime);    
    }

    function _addBasisSpread(address _token, uint256 _price, uint256 _priceTime, bool _max, uint256 _curTime) internal view returns (uint256){
        TokenInfo memory _tokenInf = tokensInfo[_token];
        uint256 spread = uint256(_tokenInf.priceSpreadBasisMax);
        uint256 spreadTimeStart = uint256(_tokenInf.spreadTimeStart);
        uint256 _psTime = _priceTime.add(spreadTimeStart);
        if (spread < 1 || _curTime < _psTime)
            return _price;
        
        uint256 spreadTimeMax = uint256(_tokenInf.spreadTimeMax);
        
        uint256 _timeGap = _curTime.sub(_psTime); //_curTime is \geq _psTime
        if (_timeGap < spreadTimeMax){
            spread = _timeGap.mul(spread).div(spreadTimeMax);
        }

        if (_max){
            _price = _price.mul(BASIS_POINTS_DIVISOR.add(spread)).div(BASIS_POINTS_DIVISOR);
        }
        else{
            _price = _price.mul(BASIS_POINTS_DIVISOR.sub(spread)).div(BASIS_POINTS_DIVISOR);
        }
    
        return _price;
    }

    //public read
    function getPrice(address _token, bool _maximise, bool , bool) public override view returns (uint256) {
        _validToken(_token);
        uint256 _curTime = block.timestamp;
        (uint256 price, uint256 updatedTime) = _getCombPrice(_token, _maximise, _curTime);
        uint256 safeGapTime = tokensInfo[_token].isStable ? stablePriceSafetyTimeGap : nonstablePriceSafetyTimeGap;
        if (_curTime > updatedTime){
            require(_curTime < updatedTime.add(safeGapTime), "[Oracle] Price out of time.");
        }
        require(price > 10, "[Oracle] invalid price");
        return price;
    }

    function getPriceUnsafe(address _token, bool _maximise, bool, bool) public override view returns (uint256) {
        _validToken(_token);
        (uint256 price, ) = _getCombPrice(_token, _maximise, block.timestamp);
        require(price > 10, "[Oracle] invalid price");
        return price;
    }

    function getConvertedPyth(address _token) public view returns(uint256, uint256, int256){
        PythStructs.Price memory _pyPrice = pyth.getPriceUnsafe(tokensInfo[_token].pythKey) ;
        uint256 it_price = uint256(int256(_pyPrice.price));
        uint256 upd_time = uint256(_pyPrice.publishTime);
        int256 _expo = int256(_pyPrice.expo);
        return(it_price,upd_time,_expo);
    }

    function getPythPrice(address _token) public view returns(uint256, bool, uint256){
        if (isStrictStable[_token])
            return (PRICE_PRECISION, true, block.timestamp);
        uint256 price = 0;
        bool read_state = false;
        if (address(pyth) == address(0)) {
            return (price, read_state, 0);
        }
        if (tokensInfo[_token].pythKey == bytes32(0)) {
            return (price, read_state, 1);
        }

        uint256 upd_time = 5;
        try pyth.getPriceUnsafe(tokensInfo[_token].pythKey) returns (PythStructs.Price memory _pyPrice ) {
            uint256 it_price = uint256(int256(_pyPrice.price));
            if (it_price < 1) {
                return (0, read_state, 2);
            }
            upd_time = uint256(_pyPrice.publishTime);
            if (upd_time < 1600000000) {
                return (0, read_state, 3);
            }
            int256 _expo= int256(_pyPrice.expo);
            if (_expo >= 0) {
                return (0, read_state, 4);
            }
            
            price = uint256(it_price).mul(PRICE_PRECISION).div(10 ** uint256(-_expo));
            if (price < MIN_PRICE_THRES) {
                return (0, read_state, 5);
            }
            else{
                read_state = true;
            }
        } catch {
            upd_time = 6;
        }    
        return (price, read_state, upd_time);
    }

    function getTokenInfo(address _token) public view returns (TokenInfo memory) {
        return tokensInfo[_token];
    }

    function tokenToUsdMeanUnsafe(address _token, uint256 _tokenAmount) public view override returns (uint256) {
        _validToken(_token);
        if (_tokenAmount == 0)  return 0;
        uint256 decimals = IMintable(_token).decimals();
        require(decimals > 0, "invalid decimal"); 
        (uint256 price, ) = _getOgPrice(_token);
        return _tokenAmount.mul(price).div(10**decimals);
    }

    function tokenToUsdUnsafe(address _token, uint256 _tokenAmount, bool _max) public view override returns (uint256) {
        _validToken(_token);
        if (_tokenAmount == 0)  return 0;
        uint256 decimals = IMintable(_token).decimals();
        require(decimals > 0, "invalid decimal"); 
        uint256 price = getPriceUnsafe(_token, _max, true, true);
        return _tokenAmount.mul(price).div(10**decimals);
    }

    function usdToTokenUnsafe( address _token, uint256 _usdAmount, bool _max ) public view override returns (uint256) {
        _validToken(_token);
        if (_usdAmount == 0)  return 0;
        uint256 decimals = IMintable(_token).decimals();
        require(decimals > 0, "invalid decimal");
        uint256 price = getPriceUnsafe(_token, _max, true, true);
        return _usdAmount.mul(10**decimals).div(price);
    }


    function tokenToUsd(address _token, uint256 _tokenAmount, bool _max) public view override returns (uint256) {
        _validToken(_token);
        if (_tokenAmount == 0)  return 0;
        uint256 decimals = IMintable(_token).decimals();
        require(decimals > 0, "invalid decimal"); 
        uint256 price = getPrice(_token, _max, true, true);
        return _tokenAmount.mul(price).div(10**decimals);
    }

    function usdToToken( address _token, uint256 _usdAmount, bool _max ) public view override returns (uint256) {
        _validToken(_token);
        if (_usdAmount == 0)  return 0;
        uint256 decimals = IMintable(_token).decimals();
        require(decimals > 0, "invalid decimal");
        uint256 price = getPrice(_token, _max, true, true);
        return _usdAmount.mul(10**decimals).div(price);
    }


    function _validUpdateFee(bytes[] memory _data) internal view returns (uint256){
        uint256 _updateFee = getUpdateFee(_data);
        // require(address(this).balance >= _updateFee, "insufficient update fee in oracle Contract");
        return _updateFee;
    }

    function getUpdateFee(bytes[] memory _data) public override view returns(uint256) {
        return pyth.getUpdateFee(_data);
    }

    function _validToken(address _token) private view{
        require(isSupportToken(_token), "Unsupported token");
    }
}
