// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFeeRouter.sol";
import "../core/interfaces/ILpManager.sol";


interface IUniswapV2Router01 {
  function factory() external pure returns (address);
  function WETH() external pure returns (address);

  function addLiquidity(
      address tokenA,
      address tokenB,
      uint amountADesired,
      uint amountBDesired,
      uint amountAMin,
      uint amountBMin,
      address to,
      uint deadline
  ) external returns (uint amountA, uint amountB, uint liquidity);
  function swapExactTokensForTokens(
      uint amountIn,
      uint amountOutMin,
      address[] memory path,
      address to,
      uint deadline
  ) external returns (uint[] memory amounts);
  function swapTokensForExactTokens(
      uint amountOut,
      uint amountInMax,
      address[] memory path,
      address to,
      uint deadline
  ) external returns (uint[] memory amounts);
}


contract FeeRouter is Ownable, IFeeRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;


    struct Distribution {
        uint64 addLiq;
        uint64 buyPLP;
        uint64 toStakingPool;
        uint64 totalWeight;
    }
    Distribution public distWeights;
    uint256 public totalDestNum;
    uint256 public trigThres;
    
    address public treasury;
    address public univ2Router;
    address public LpManager;
    address public plp;
    address public treStaking;
    address public feeToken;
    address public immutable dyna;


    event Distribute(Distribution, uint256 amountsBuyDyna);

    constructor(address _dyna){
        dyna = _dyna;
    }
    
    function setToken(address _feeToken) external onlyOwner{
        feeToken = _feeToken;
    }

    function set(address _univ2Router, address _lpManager, address _treasury, address _plp, address _treStaking) external onlyOwner {
        univ2Router = _univ2Router;
        LpManager = _lpManager;
        treasury = _treasury;
        plp = _plp;
        treStaking = _treStaking;
    }

    function setTrigThres(uint256 _trigThres) external onlyOwner{
        trigThres = _trigThres;
    }

    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function setDistribution(uint64 _addLiq, uint64 _buyPLP, uint64 _toStakingPool) external onlyOwner{
        distWeights = Distribution({
                addLiq : _addLiq,
                buyPLP : _buyPLP,
                toStakingPool : _toStakingPool,
                totalWeight : _addLiq + _buyPLP + _toStakingPool
            });
    }


    function distribute() external override {
        _distribute();
    }

    function _distribute() private {
        uint256 cur_balance = IERC20(feeToken).balanceOf(address(this));
        Distribution memory _dist = distWeights;
        if (cur_balance <= trigThres)
            return ;
        if (_dist.totalWeight < 1)
            return;
        if (treasury == address(0))
            return;

        {
            address[] memory _path =  new address[](2);
            _path[0] = feeToken;
            _path[1] = dyna;

            uint256 amountsBuyDyna = cur_balance.mul(uint256(_dist.addLiq)).div(_dist.totalWeight)/2;
            IERC20(feeToken).approve(univ2Router, amountsBuyDyna);
            
            IUniswapV2Router01(univ2Router).swapExactTokensForTokens(
                amountsBuyDyna,
                0,
                _path,
                address(this),
                block.timestamp+15
            );


            uint256 _DynaBalance = IERC20(dyna).balanceOf(address(this)) ;
            IERC20(dyna).approve(univ2Router, _DynaBalance);
            IERC20(feeToken).approve(univ2Router, amountsBuyDyna * 3);
            IUniswapV2Router01(univ2Router).addLiquidity(
                feeToken,
                dyna,
                amountsBuyDyna,
                _DynaBalance,
                0,
                0,
                treasury,
                block.timestamp+15
            );

            // emit AddLiquidity(_DynaBalance, amountsBuyDyna);

        }

        {
            uint256 amountsBuyPlp = cur_balance.mul(uint256(_dist.buyPLP)).div(_dist.totalWeight);
            IERC20(feeToken).approve(LpManager, amountsBuyPlp);
            ILpManager(LpManager).addLiquidityNoUpdate(feeToken, amountsBuyPlp, 0, treasury);
            // emit BuyPLP(amountsBuyPlp);
        }

        {
            uint256 shareAmount = IERC20(feeToken).balanceOf(address(this));
            IERC20(feeToken).transfer(treStaking,  shareAmount);
            // emit StakingShare(treStaking, shareAmount);
        }
        emit Distribute(_dist, cur_balance);
    }

 
    
}