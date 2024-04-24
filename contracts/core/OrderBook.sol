// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";
import "./interfaces/IVault.sol";
import "../tokens/interfaces/IWETH.sol";
import "./Handler.sol";
import "../oracle/interfaces/IVaultPriceFeed.sol";
library OrderData {
    struct IncreaseOrder {
        address account;
        uint256 index;
        address vault;
        address purchaseToken;
        uint256 purchaseTokenAmount;
        address collateralToken;
        address indexToken;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
        uint256 executionFee;
        bytes32 key;
    }

    struct IncreaseOrderIntf {
        address vault;
        address indexToken;
        address collateralToken;
        uint256 amountIn;
        uint256 minOut;
        uint256 sizeDelta;
        uint256 triggerPrice;
        uint256 executionFee;
        bool isLong;
        bool triggerAboveThreshold;
        bool shouldWrap;
    }

    struct DecreaseOrder {
        address account;
        uint256 index;
        address vault;
        address collateralToken;
        uint256 collateralDelta;
        address indexToken;
        uint256 sizeDelta;
        bool isLong;
        uint256 triggerPrice;
        bool triggerAboveThreshold;
        uint256 executionFee;
        bytes32 key;
    }

    struct SwapOrder {
        address account;
        uint256 index;
        address vault;
        address[] path;
        uint256 amountIn;
        uint256 minOut;
        uint256 triggerRatio;
        bool triggerAboveThreshold;
        bool shouldUnwrap;
        uint256 executionFee;
        bytes32 key;
    }  

    uint256 constant PRICE_PRECISION = 1e30;

}




contract OrderBook is Ownable, Handler{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableValues for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableValues for EnumerableSet.AddressSet;

    // mapping (address => mapping(uint256 => bytes32)) public increaseOrderKeys;
    // mapping (address => uint256) public increaseOrdersIndex;
    uint256 public increaseOrdersIndex;
    mapping (address => EnumerableSet.Bytes32Set) internal increaseOrderKeysAlive;
    mapping (bytes32 => OrderData.IncreaseOrder) internal increaseOrders;

    // mapping (address => mapping(uint256 => bytes32)) public decreaseOrderKeys;
    // mapping (address => uint256) public decreaseOrdersIndex;
    uint256 public decreaseOrdersIndex;
    mapping (address => EnumerableSet.Bytes32Set) internal decreaseOrderKeysAlive;
    mapping (bytes32 => OrderData.DecreaseOrder) internal decreaseOrders;

    // mapping (address => mapping(uint256 => bytes32)) public swapOrderKeys;
    // mapping (address => uint256) public swapOrdersIndex;
    uint256 public swapOrdersIndex;
    mapping (bytes32 => OrderData.SwapOrder) internal swapOrders;
    mapping (address => EnumerableSet.Bytes32Set) internal swapOrderKeysAlive;


    address public priceFeed;
    address public weth;
    uint256 public minExecutionFee;

    event CreateIncreaseOrder(OrderData.IncreaseOrder);
    event UpdateIncreaseOrder(OrderData.IncreaseOrder);
    event CancelIncreaseOrder(OrderData.IncreaseOrder);
    event ExecuteDecreaseOrder(OrderData.DecreaseOrder, uint256 executePrice);
    event CreateDecreaseOrder(OrderData.DecreaseOrder);
    event UpdateDecreaseOrder(OrderData.DecreaseOrder);
    event CancelDecreaseOrder(OrderData.DecreaseOrder);
    event ExecuteIncreaseOrder(OrderData.IncreaseOrder, uint256 executePrice);
    event CreateSwapOrder(OrderData.SwapOrder);
    event UpdateSwapOrder(OrderData.SwapOrder);
    event CancelSwapOrder(OrderData.SwapOrder);
    event ExecuteSwapOrder(OrderData.SwapOrder);
    event Initialize(address pricefeed, address weth, uint256 minExecutionFee);
    event UpdateMinExecutionFee(uint256 minExecutionFee);

    receive() external payable {
        require(msg.sender == weth, "IS");
    }

    function initialize(address _pricefeed, address _weth, uint256 _minExecutionFee, uint256) external onlyOwner {
        priceFeed = _pricefeed;
        weth = _weth;
        minExecutionFee = _minExecutionFee;
        emit Initialize(priceFeed, _weth, _minExecutionFee);
    }
    
    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }
    function setMinExecutionFee(uint256 _minExecutionFee) external onlyOwner {
        minExecutionFee = _minExecutionFee;
        emit UpdateMinExecutionFee(_minExecutionFee);
    }

    //- Public View Functions
    function getSwapOrderByKey(bytes32 _swapKey) public view returns (OrderData.SwapOrder memory){
        return swapOrders[_swapKey];
    }
    function getPendingSwapOrdersKeys(address _account) public view returns (bytes32[] memory){
        return swapOrderKeysAlive[_account].valuesAt(0, swapOrderKeysAlive[_account].length());
    }
    function getPendingSwapOrders(address _account) public view returns (OrderData.SwapOrder[] memory){
        bytes32[] memory keys = getPendingSwapOrdersKeys(_account);
        OrderData.SwapOrder[] memory orders = new OrderData.SwapOrder[](keys.length);
        for(uint64 i = 0; i < orders.length; i++){
            orders[i] = swapOrders[keys[i]];
        }
        return orders;
    }
    // function pendingSwapOrdersNum(address _account) public view returns (uint256){
    //     return swapOrderKeysAlive[_account].length();
    // }
    function isSwapOrderKeyAlive(bytes32 _swapKey) public view returns (bool){
        return swapOrderKeysAlive[address(0)].contains(_swapKey);
    }


    function getIncreaseOrderByKey(bytes32 _increaseKey) public view returns (OrderData.IncreaseOrder memory){
        return increaseOrders[_increaseKey];
    }
    function getPendingIncreaseOrdersKeys(address _account) public view returns (bytes32[] memory){
        return increaseOrderKeysAlive[_account].valuesAt(0, increaseOrderKeysAlive[_account].length());
    }
    function getPendingIncreaseOrders(address _account) public view returns (OrderData.IncreaseOrder[] memory){
        bytes32[] memory keys = getPendingIncreaseOrdersKeys(_account);
        OrderData.IncreaseOrder[] memory orders = new OrderData.IncreaseOrder[](keys.length);
        for(uint64 i = 0; i < orders.length; i++){
            orders[i] = increaseOrders[keys[i]];
        }
        return orders;
    }
    function pendingIncreaseOrdersNum(address _account) public view returns (uint256){
        return increaseOrderKeysAlive[_account].length();
    }
    function isIncreaseOrderKeyAlive(bytes32 _increaseKey) public view returns (bool){
        return increaseOrderKeysAlive[address(0)].contains(_increaseKey);
    }

    function getDecreaseOrderByKey(bytes32 _decreaseKey) public view returns (OrderData.DecreaseOrder memory){
        return decreaseOrders[_decreaseKey];
    }
    function getPendingDecreaseOrdersKeys(address _account) public view returns (bytes32[] memory){
        return decreaseOrderKeysAlive[_account].valuesAt(0, decreaseOrderKeysAlive[_account].length());
    }    
    function getPendingDecreaseOrders(address _account) public view returns (OrderData.DecreaseOrder[] memory){
        bytes32[] memory keys = getPendingDecreaseOrdersKeys(_account);
        OrderData.DecreaseOrder[] memory orders = new OrderData.DecreaseOrder[](keys.length);
        for(uint64 i = 0; i < orders.length; i++){
            orders[i] = decreaseOrders[keys[i]];
        }
        return orders;
    }
    // function pendingDecreaseOrdersNum(address _account) public view returns (uint256){
    //     return decreaseOrderKeysAlive[_account].length();
    // }
    function isDecreaseOrderKeyAlive(bytes32 _decreaseKey) public view returns (bool){
        return decreaseOrderKeysAlive[address(0)].contains(_decreaseKey);
    }
    function getPendingOrders(address _account) public view returns (OrderData.IncreaseOrder[] memory, OrderData.DecreaseOrder[] memory, OrderData.SwapOrder[] memory){
        return (getPendingIncreaseOrders(_account), getPendingDecreaseOrders(_account), getPendingSwapOrders(_account));
    }




    //------ Increase Orders
    function createIncreaseOrder(
        OrderData.IncreaseOrderIntf calldata orderIt,
        address[] memory _path,
        bytes[] memory _updaterSignedMsg) external payable {
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);

        // always need this call because of mandatory executionFee user has to transfer in ETH
        _transferInETH();
        require(_path.length == 1 || _path.length == 2, "ip");
        require(orderIt.executionFee == minExecutionFee, "iFee");
        if (orderIt.shouldWrap) {
            require(_path[0] == weth, "p0");
            require(msg.value == orderIt.executionFee.add(orderIt.amountIn), "iVal");
        } else {
            require(msg.value == orderIt.executionFee, "iFee");
            IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), orderIt.amountIn);
        }

        address _purchaseToken = _path[_path.length - 1];
        uint256 _purchaseTokenAmount;
        if (_path.length > 1) {
            require(_path[0] != _purchaseToken, "ip0");
            IERC20(_path[0]).safeTransfer(orderIt.vault, orderIt.amountIn);
            _purchaseTokenAmount = _swap(orderIt.vault, _path, orderIt.minOut, address(this));
        } else {
            _purchaseTokenAmount = orderIt.amountIn;
        }
        // {
        //     uint256 _purchaseTokenAmountUsd = IVaultPriceFeed(priceFeed).tokenToUsdUnsafe(_purchaseToken, _purchaseTokenAmount, false);
        // }
        _createIncreaseOrder(orderIt, msg.sender, _purchaseToken, _purchaseTokenAmount);
    }

    function _createIncreaseOrder(
        OrderData.IncreaseOrderIntf calldata orderIt,
        address _account,
        address _purchaseToken,
        uint256 _purchaseTokenAmount
    ) private {
        uint256 _orderIndex = increaseOrdersIndex;
        increaseOrdersIndex = _orderIndex.add(1);//for next time
        bytes32 _key = getRequestKey(_account, _orderIndex, "increase");
        OrderData.IncreaseOrder memory order = OrderData.IncreaseOrder(
            _account, _orderIndex, orderIt.vault, _purchaseToken, _purchaseTokenAmount, orderIt.collateralToken,
            orderIt.indexToken, orderIt.sizeDelta, orderIt.isLong,
            orderIt.triggerPrice, orderIt.triggerAboveThreshold, orderIt.executionFee, _key);
        // increaseOrderKeys[_account][_orderIndex] = _key;
        increaseOrderKeysAlive[address(0)].add(_key);
        increaseOrderKeysAlive[_account].add(_key);
        increaseOrders[_key] = order;

        emit CreateIncreaseOrder(order);
    }
    function updateIncreaseOrderByKey(bytes32 _key, uint256 _sizeDelta, uint256 _triggerPrice, bool _triggerAboveThreshold) public {
        _updateIncreaseOrder(_key, _sizeDelta, _triggerPrice, _triggerAboveThreshold);
    }
    // function updateIncreaseOrder(uint256 _orderIndex, uint256 _sizeDelta, uint256 _triggerPrice, bool _triggerAboveThreshold) public {
    //     bytes32 _key = increaseOrderKeys[msg.sender][_orderIndex];
    //     _updateIncreaseOrder(_key, _sizeDelta, _triggerPrice, _triggerAboveThreshold);
    // }
    function _updateIncreaseOrder(bytes32 _key, uint256 _sizeDelta, uint256 _triggerPrice, bool _triggerAboveThreshold) public {
        require(isIncreaseOrderKeyAlive(_key), "no key");
        OrderData.IncreaseOrder storage order = increaseOrders[_key];
        require(msg.sender == order.account, "Forbiden");
        require(order.account != address(0), "no-order");
        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;
        emit UpdateIncreaseOrder(order);
    }
    // function cancelIncreaseOrder(uint256 _orderIndex) public {
    //     bytes32 _key = increaseOrderKeys[msg.sender][_orderIndex];
    //     _cancelIncreaseOrder(_key);
    // }
    function cancelIncreaseOrderByKey(bytes32 _key) public {
        _cancelIncreaseOrder(_key);
    }
    function _cancelIncreaseOrder(bytes32 _key) internal {
        require(isIncreaseOrderKeyAlive(_key), "no-order");
        OrderData.IncreaseOrder memory order = increaseOrders[_key];
        address _account = order.account;
        require(_account == msg.sender || isHandler(msg.sender), "forbiden");
        if(_account != address(0)){
            if (order.purchaseToken == weth) {
                _transferOutETH(order.executionFee.add(order.purchaseTokenAmount), payable(msg.sender)); 
            } else {
                IERC20(order.purchaseToken).safeTransfer(msg.sender, order.purchaseTokenAmount);
                _transferOutETH(order.executionFee,payable(msg.sender)); 
            }
            increaseOrderKeysAlive[_account].remove(_key);
        }
        increaseOrderKeysAlive[address(0)].remove(_key);
        // delete increaseOrderKeys[_account][order.index];
        delete increaseOrders[_key];
        emit CancelIncreaseOrder(order);
    }


    //------ Decrease Orders
    function createDecreaseOrder(
        address _vault,
        address _indexToken,
        uint256 _sizeDelta,
        address _collateralToken,
        uint256 _collateralDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        bytes[] memory _updaterSignedMsg) external payable{
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        _transferInETH();
        require(msg.value == minExecutionFee, "iFee");
        _createDecreaseOrder(
            _vault,
            msg.sender,
            _collateralToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold
        );
    }

    function _createDecreaseOrder(
        address _vault,
        address _account,
        address _collateralToken,
        uint256 _collateralDelta,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold
    ) private {
        uint256 _orderIndex = decreaseOrdersIndex;
        decreaseOrdersIndex += 1;
        bytes32 _key = getRequestKey(_account, _orderIndex, "decrease");

        OrderData.DecreaseOrder memory order = OrderData.DecreaseOrder(
            _account,
            _orderIndex,
            _vault,
            _collateralToken,
            _collateralDelta,
            _indexToken,
            _sizeDelta,
            _isLong,
            _triggerPrice,
            _triggerAboveThreshold,
            msg.value,
            _key
        );
        // decreaseOrderKeys[_account][_orderIndex] = _key;
        decreaseOrderKeysAlive[address(0)].add(_key);
        decreaseOrderKeysAlive[_account].add(_key);
        decreaseOrders[_key] = order;

        emit CreateDecreaseOrder(order);
    }

    // function cancelDecreaseOrder(uint256 _orderIndex) public {
    //     bytes32 _key = decreaseOrderKeys[msg.sender][_orderIndex];
    //     _cancelDecreaseOrder(_key);
    // }
    function cancelDecreaseOrderByKey(bytes32 _key) public {
        _cancelDecreaseOrder(_key);
    }
    function _cancelDecreaseOrder(bytes32 _key) internal {
        require(isDecreaseOrderKeyAlive(_key), "no order");
        OrderData.DecreaseOrder memory order = decreaseOrders[_key];
        address _account = order.account;
        require(_account == msg.sender || isHandler(msg.sender), "forbiden");
        if(_account != address(0)){
            _transferOutETH(order.executionFee, payable(msg.sender)); 
            decreaseOrderKeysAlive[_account].remove(_key);
        }
        decreaseOrderKeysAlive[address(0)].remove(_key);
        // delete decreaseOrderKeys[msg.sender][order.index];
        delete decreaseOrders[_key];
        emit CancelDecreaseOrder(order);
    }

    function updateDecreaseOrderByKey(bytes32 _key, uint256 _collateralDelta,  uint256 _sizeDelta, uint256 _triggerPrice, bool _triggerAboveThreshold) public {
        _updateDecreaseOrder(_key, _collateralDelta, _sizeDelta, _triggerPrice, _triggerAboveThreshold);
    }
    // function updateDecreaseOrder(uint256 _orderIndex, uint256 _collateralDelta, uint256 _sizeDelta, uint256 _triggerPrice, bool _triggerAboveThreshold) public {
    //     _updateDecreaseOrder(decreaseOrderKeys[msg.sender][_orderIndex], _collateralDelta, _sizeDelta, _triggerPrice, _triggerAboveThreshold);
    // }
    function _updateDecreaseOrder(bytes32 _key, uint256 _collateralDelta, uint256 _sizeDelta, uint256 _triggerPrice, bool _triggerAboveThreshold) public {
        require(isDecreaseOrderKeyAlive(_key), "no order");
        OrderData.DecreaseOrder storage order = decreaseOrders[_key];
        require(order.account == msg.sender, "forbiden");
        require(order.account != address(0), "no-order");
        order.triggerPrice = _triggerPrice;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        order.sizeDelta = _sizeDelta;
        order.collateralDelta = _collateralDelta;
        emit UpdateDecreaseOrder(order);
    }


    //------ Swap Order
    function createSwapOrder(
        address _vault,
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _triggerRatio, // tokenB / tokenA
        bool _triggerAboveThreshold,
        uint256 _executionFee,
        bool _shouldWrap,
        bool _shouldUnwrap,
        bytes[] memory _updaterSignedMsg) external payable{
        IVaultPriceFeed(priceFeed).updatePriceFeeds(_updaterSignedMsg);
        require(_path.length == 2 || _path.length == 3, "IPL");
        require(_path[0] != _path[_path.length - 1], "IP");
        require(_amountIn > 0, "IIN");
        require(_executionFee == minExecutionFee, "insufficient fee");
        for(uint i = 0; i < _path.length; i++){
            VaultMSData.TokenBase memory _tokenInBase = IVault(_vault).getTokenBase(_path[i]);
            require(_tokenInBase.isFundable && _tokenInBase.isSwappable, "iT");
        }
        // always need this call because of mandatory executionFee user has to transfer in ETH
        _transferInETH();

        if (_shouldWrap) {
            require(_path[0] == weth, "only weth");
            require(msg.value == _executionFee.add(_amountIn), "VT");
        } else {
            require(msg.value == _executionFee, "IEFEE");
            IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);
        }
        _createSwapOrder(_vault,msg.sender, _path, _amountIn, _minOut, _triggerRatio, _triggerAboveThreshold, _shouldUnwrap, _executionFee);
    }

    function _createSwapOrder(
        address _vault,
        address _account,
        address[] memory _path,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _triggerRatio,
        bool _triggerAboveThreshold,
        bool _shouldUnwrap,
        uint256 _executionFee
    ) private {
        uint256 _orderIndex = swapOrdersIndex;
        swapOrdersIndex += 1;
        bytes32 _key = getRequestKey(_account, _orderIndex, "swap");

        OrderData.SwapOrder memory order = OrderData.SwapOrder(
            _account,
            _orderIndex,
            _vault,
            _path,
            _amountIn,
            _minOut,
            _triggerRatio,
            _triggerAboveThreshold,
            _shouldUnwrap,
            _executionFee,
            _key
        );
        // swapOrderKeys[_account][_orderIndex] = _key;
        swapOrderKeysAlive[address(0)].add(_key);
        swapOrderKeysAlive[_account].add(_key);
        swapOrders[_key] = order;
        emit CreateSwapOrder(order);
    }

    function cancelSwapOrderByKey(bytes32 _key) public {
        require(isSwapOrderKeyAlive(_key), "no order");
        OrderData.SwapOrder memory order = swapOrders[_key];
        address _account = order.account;
        require(_account == msg.sender || isHandler(msg.sender), "forbiden");
        if(_account != address(0)){
            if (order.path[0] == weth) {
                _transferOutETH(order.executionFee.add(order.amountIn), payable(msg.sender)); //BLKMDF
            } else {
                IERC20(order.path[0]).safeTransfer(msg.sender, order.amountIn);
                _transferOutETH(order.executionFee, payable(msg.sender)); //BLKMDF
            }
            swapOrderKeysAlive[_account].remove(_key);
        }
        swapOrderKeysAlive[address(0)].remove(_key);
        // delete swapOrderKeys[_account][order.index];
        delete swapOrders[_key];
        emit CancelSwapOrder(order);
    }

    function updateSwapOrderByKey(bytes32 _key, uint256 _minOut, uint256 _triggerRatio, bool _triggerAboveThreshold) external {
        OrderData.SwapOrder memory order = swapOrders[_key];
        require(order.account != address(0), "no-order");
        address _account = order.account;
        require(_account == msg.sender, "forbiden");
        order.minOut = _minOut;
        order.triggerRatio = _triggerRatio;
        order.triggerAboveThreshold = _triggerAboveThreshold;
        emit UpdateSwapOrder(order);
    }




    function cancelMultiple(
        bytes32[] memory _swapOrderKeys,
        bytes32[] memory _increaseOrderKeys,
        bytes32[] memory _decreaseOrderKeys
    ) external {
        for (uint256 i = 0; i < _swapOrderKeys.length; i++) {
            cancelSwapOrderByKey(_swapOrderKeys[i]);
        }
        for (uint256 i = 0; i < _increaseOrderKeys.length; i++) {
            cancelIncreaseOrderByKey(_increaseOrderKeys[i]);
        }
        for (uint256 i = 0; i < _decreaseOrderKeys.length; i++) {
            cancelDecreaseOrderByKey(_decreaseOrderKeys[i]);
        }
    }




    function executeIncreaseOrder(bytes32 _key, address payable _feeReceiver) external onlyHandler {
        OrderData.IncreaseOrder memory order = increaseOrders[_key];
        require(isIncreaseOrderKeyAlive(_key) && order.account != address(0), "no order");

        // increase long should use max price
        // increase short should use min price
        (uint256 currentPrice, ) = validatePositionOrderPrice(
            order.vault,
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken,
            order.isLong,
            true
        );
        IERC20(order.purchaseToken).safeTransfer(order.vault, order.purchaseTokenAmount);
        if (order.purchaseToken != order.collateralToken) {
            address[] memory path = new address[](2);
            path[0] = order.purchaseToken;
            path[1] = order.collateralToken;
            uint256 amountOut = _swap(order.vault, path, 0, address(this));
            IERC20(order.collateralToken).safeTransfer(order.vault, amountOut);
        }

        _increasePosition(order.account, order.vault, order.collateralToken, order.indexToken, order.sizeDelta, order.isLong);
        // pay executor
        _transferOutETH(order.executionFee, _feeReceiver);
        emit ExecuteIncreaseOrder(order, currentPrice);

        increaseOrderKeysAlive[order.account].remove(_key);       
        increaseOrderKeysAlive[address(0)].remove(_key);
        delete increaseOrders[_key];
        // delete increaseOrderKeys[msg.sender][order.index];

    }


    function executeDecreaseOrder(bytes32 _key, address payable _feeReceiver) external onlyHandler {
        OrderData.DecreaseOrder memory order = decreaseOrders[_key];
        require(order.account != address(0), "no-order");

        // decrease long should use min price
        // decrease short should use max price
        (uint256 currentPrice, ) = validatePositionOrderPrice(
            order.vault,
            order.triggerAboveThreshold,
            order.triggerPrice,
            order.indexToken,
            !order.isLong,
            true
        );

        (uint256 amountOut, ) = _decreasePosition(
            order.account, order.vault, order.collateralToken, order.indexToken,
            order.collateralDelta, order.sizeDelta, order.isLong, address(this));

        // transfer released collateral to user
        if (order.collateralToken == weth) {
            _transferOutETH(amountOut, payable(order.account));
        } else {
            IERC20(order.collateralToken).safeTransfer(order.account, amountOut);
        }

        // pay executor
        _transferOutETH(order.executionFee, _feeReceiver);

        emit ExecuteDecreaseOrder(order, currentPrice);

        decreaseOrderKeysAlive[order.account].remove(_key);       
        decreaseOrderKeysAlive[address(0)].remove(_key);
        delete decreaseOrders[_key];
        // delete decreaseOrderKeys[msg.sender][order.index];
    }

    function executeSwapOrder(bytes32 _key, address payable _feeReceiver) external onlyHandler {
        OrderData.SwapOrder memory order = swapOrders[_key];
        require(order.account != address(0), "no-order");

        if (order.triggerAboveThreshold) {
            // gas optimisation
            // order.minAmount should prevent wrong price execution in case of simple limit order
            require(
                validateSwapOrderPriceWithTriggerAboveThreshold(order.vault, order.path, order.triggerRatio),
                "invalid price for execution"
            );
        }

        IERC20(order.path[0]).safeTransfer(order.vault, order.amountIn);
        uint256 _amountOut;
        if (order.path[order.path.length - 1] == weth && order.shouldUnwrap) {
            _amountOut = _swap(order.vault, order.path, order.minOut, address(this));
            _transferOutETH(_amountOut, payable(order.account));
        } else {
            _amountOut = _swap(order.vault, order.path, order.minOut, order.account);
        }

        // pay executor
        _transferOutETH(order.executionFee, _feeReceiver);

        emit ExecuteSwapOrder(order);
        swapOrderKeysAlive[order.account].remove(_key);       
        swapOrderKeysAlive[address(0)].remove(_key);
        delete swapOrders[_key];
        // delete swapOrderKeys[msg.sender][order.index];
    }


    function validateSwapOrderPriceWithTriggerAboveThreshold(
        address _vault,
        address[] memory _path,
        uint256 _triggerRatio
    ) public view returns (bool) {
        require(_path.length == 2 || _path.length == 3, "ip");

        // limit orders don't need this validation because minOut is enough
        // so this validation handles scenarios for stop orders only
        // when a user wants to swap when a price of tokenB increases relative to tokenA
        address tokenA = _path[0];
        address tokenB = _path[_path.length - 1];
        uint256 tokenAPrice;
        uint256 tokenBPrice;

        tokenAPrice = IVault(_vault).getMinPrice(tokenA);
        tokenBPrice = IVault(_vault).getMaxPrice(tokenB);

        uint256 currentRatio = tokenBPrice.mul(OrderData.PRICE_PRECISION).div(tokenAPrice);

        bool isValid = currentRatio > _triggerRatio;
        return isValid;
    }

    function validatePositionOrderPrice(
        address _vault,
        bool _triggerAboveThreshold,
        uint256 _triggerPrice,
        address _indexToken,
        bool _maximizePrice,
        bool _raise
    ) public view returns (uint256, bool) {
        uint256 currentPrice = _maximizePrice
            ? IVault(_vault).getMaxPrice(_indexToken) : IVault(_vault).getMinPrice(_indexToken);
        bool isPriceValid = _triggerAboveThreshold ? currentPrice > _triggerPrice : currentPrice < _triggerPrice;
        if (_raise) {
            require(isPriceValid, "price");
        }
        return (currentPrice, isPriceValid);
    }



    function _transferInETH() private {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    function _transferOutETH(uint256 _amountOut, address payable _receiver) private {
        IWETH(weth).withdraw(_amountOut);
        _receiver.sendValue(_amountOut);
    }

    function _swap(address _vault, address[] memory _path, uint256 _minOut, address _receiver) private returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_vault, _path[0], _path[1], _minOut, _receiver);
        }
        if (_path.length == 3) {
            uint256 midOut = _vaultSwap(_vault, _path[0], _path[1], 0, address(this));
            IERC20(_path[1]).safeTransfer(_vault, midOut);
            return _vaultSwap(_vault, _path[1], _path[2], _minOut, _receiver);
        }

        revert("invalid _path.length");
    }

    function _vaultSwap(address _vault, address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver) private returns (uint256) {
        uint256 amountOut;
        amountOut = IVault(_vault).swap(_tokenIn, _tokenOut, _receiver);
        require(amountOut >= _minOut, "i-amountOut");
        return amountOut;
    }

    function getRequestKey(address _account, uint256 _index, string memory _type) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_type, _account, _index));
    }

    //------------------------------ Private Functions ------------------------------
    function _increasePosition(address _account, address _vault, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) private {
        IVault(_vault).increasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong);
    }

    function _decreasePosition(address _account, address _vault,address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) private returns (uint256, bool) {
        return IVault(_vault).decreasePosition(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
    }
}
