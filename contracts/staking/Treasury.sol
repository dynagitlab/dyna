// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/Handler.sol";
import "../tokens/interfaces/IWETH.sol";


interface IStakingPool {
    function totalReward() external view returns (uint256);
    function claimedRewards() external view returns (uint256);
}


contract Treasury is Ownable, Handler, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address payable;

    address public stakingPool;

    address public immutable weth;
    address public immutable treasuryToken;

    address[] public rewardTokens;


    event Receive(address sender, uint256 amount);
    event Redeem(address sender, uint256 redeemAmount, uint256 ciculation, address token, uint256 reward);

    constructor(address _weth, address _treasuryToken) {
        weth = _weth;
        treasuryToken = _treasuryToken;
    }

    receive() external payable {
        emit Receive(msg.sender, msg.value);
    }
    
    function approve(address _token, address _spender, uint256 _amount) external onlyOwner {
        IERC20(_token).approve(_spender, _amount);
    }

    function setAddress(address _stakingPool) external onlyOwner{
        stakingPool = _stakingPool;
    }

    function setRewardTokenList(address[] memory _list) external onlyOwner{
        rewardTokens = _list;
    }

    function withdrawToken(address _token, uint256 _amount, address _dest) external onlyOwner {
        IERC20(_token).safeTransfer(_dest, _amount);
    }

    function DepositETH(uint256 _value) external onlyOwner {
        IWETH(weth).deposit{value: _value}();
    }

    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }

   function redeem(uint256 _amount) external onlyManager nonReentrant returns (address[] memory tokens, uint256[] memory rewards){
        require(_amount > 0);
        address _manager = _msgSender();
        uint256 _circulation = treasuryTokenCirculation();
        require(_circulation > 0, "zero treasury token circulation");
        tokens = rewardTokens;
        IERC20(treasuryToken).safeTransferFrom(_manager, address(this), _amount);
        rewards = new uint256[](rewardTokens.length);
        for (uint8 i = 0; i < rewardTokens.length; i++){
            address _token = rewardTokens[i];
            uint256 _rdmAmount = IERC20(_token).balanceOf(address(this)).mul(_amount).div(_circulation);
            rewards[i] = _rdmAmount;
            IERC20(_token).safeTransfer(_manager, _rdmAmount);
            emit Redeem(_manager, _amount, _circulation, _token, _rdmAmount);
        }
    }

   function estimateRedeem(uint256 _amount) public view returns (uint256[] memory rewards){
        uint256 _circulation = treasuryTokenCirculation();
        if (_amount < 1 || _circulation < 1)
            return rewards;

        rewards = new uint256[](rewardTokens.length);
        for (uint8 i = 0; i < rewardTokens.length; i++){
            address _token = rewardTokens[i];
            uint256 _rdmAmount = IERC20(_token).balanceOf(address(this)).mul(_amount).div(_circulation);
            rewards[i] = _rdmAmount;
        }
    }


    function treasuryTokenCirculation() public view returns (uint256) {
        require(stakingPool != address(0), "staking pool not set");
        // return IStakingPool(stakingPool).totalReward().sub(IERC20(treasuryToken).balanceOf(treasury));
        uint256 _rewards = IStakingPool(stakingPool).totalReward() ;
        uint256 _rewardClaimed = IStakingPool(stakingPool).claimedRewards() ;
        require(_rewards >= _rewardClaimed, "invalid staking pool rewards");
        return  
                _rewards 
                - _rewardClaimed
                + IERC20(treasuryToken).totalSupply()
                - IERC20(treasuryToken).balanceOf(address(this));
    }  

}