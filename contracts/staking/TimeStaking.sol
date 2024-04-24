// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../DID/interfaces/IPID.sol";
import "../tokens/interfaces/IMintable.sol";
import "../core/FullMath.sol";

contract TimeStaking is Ownable { //IERC20,
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    uint256 public constant REWARD_PRECISION = 10 ** 20;
    uint256 public constant FEE_PRECISION = 10000;

    address immutable public extDepositToken;
    address immutable public depositToken;
    address immutable public rewardToken;
    address public pid;
    uint256 public feeRatio;

    // reward parameters
    uint256 public baseRewardPerSec_PREC; // = totalRewardPerDay * REWARD_PRECISION / (24day seconds)
    uint256 public boostedRewardPerSec_PREC;

    // reward record
    uint256 public cumulativeRewardPerBoosted;
    uint256 public lastDistributionTime;
    uint256 public totalDepositToken;
    uint256 public totalBoostedSupply;

    uint256 private cumulativeReward;
    uint256 public  claimedRewards;


    mapping (address => uint256) public stakedToken;
    mapping (address => uint256) public stakedBoosted;
    mapping (address => uint256) public claimableReward;
    mapping (address => uint256) public entryCumulatedRewardPerBoosted;



    event Claim(address account, uint256 amount, address _receiver);
    event Stake(address account, uint256 amount, uint256 latestAmount);
    event Unstake(address account, uint256 amount, uint256 latestAmount);
    event UpdateRate(uint256 rate, uint256 totalSupply);

    constructor (address _depositToken, address _rewardToken, address _extDepositToken){
        depositToken = _depositToken;
        rewardToken = _rewardToken;
        extDepositToken = _extDepositToken;
    }  


    function setAddress(address _pid) external onlyOwner{
        pid = _pid;
    }

    function updatePoolRewardRate(uint256 _totalRewardPerDay) external onlyOwner {
        _updateRewards(address(0));
        baseRewardPerSec_PREC = FullMath.mulDiv(_totalRewardPerDay, REWARD_PRECISION, 86400);
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }
    
    function setFeeRatio(uint256 _ratio) external onlyOwner{
        require(_ratio <= FEE_PRECISION, "exceeds");
        feeRatio = _ratio;
    }

    //--- Func. for user
    function extStake(uint256 _amount) external {
        address _account = msg.sender;
        require(_amount > 0, "zero amount in");
        IERC20(extDepositToken).safeTransferFrom(_account, address(this), _amount);
        IMintable(extDepositToken).burn(_amount);
        IMintable(depositToken).mint(address(this), _amount);
        _stake(_account, _amount);
    }


    function stake(uint256 _amount) external {
        address _account = msg.sender;
        require(_amount > 0, "zero amount in");
        IERC20(depositToken).safeTransferFrom(_account, address(this), _amount);
        _stake(_account, _amount);
    }



    function unstake(uint256 _amount) external {
        _unstake(msg.sender, _amount, msg.sender);
    }

    function claim(address _receiver) external returns (uint256) {
        return _claim(msg.sender, _receiver);
    }

    function updateRewardsForUser(address _account) external {
        _updateRewards(_account);
    }

    function claimable(address _account) external view returns (uint256) {
        // latest cum reward
        uint256 boolstedAmount = stakedBoosted[_account];
        if (boolstedAmount < 1)
            return 0;

        uint256 latest_cumulativeRewardPerBoosted = cumulativeRewardPerBoosted.add(_pendingRewardsPerBoosted());

        uint256 accountReward = FullMath.mulDiv(
                    boolstedAmount, 
                    latest_cumulativeRewardPerBoosted.sub(entryCumulatedRewardPerBoosted[_account]),
                    REWARD_PRECISION);

        return claimableReward[_account].add(accountReward);
    }

    function totalReward() external view returns (uint256) {
        return cumulativeReward.add(FullMath.mulDiv(_pendingRewardsPerBoosted(), totalBoostedSupply, REWARD_PRECISION));
    }


    // internal func.
    function _pendingRewardsPerBoosted() private view returns (uint256) {
        uint256 timeDiff = block.timestamp.sub(lastDistributionTime);
        return timeDiff > 0 ? boostedRewardPerSec_PREC.mul(timeDiff) : 0;
    }

    function _updateRewards(address _account) private {
        uint256 blockRewardPerBoosted = _pendingRewardsPerBoosted();
        lastDistributionTime = block.timestamp;
       
        if (totalBoostedSupply > 0)
            cumulativeReward = cumulativeReward.add(FullMath.mulDiv(blockRewardPerBoosted, totalBoostedSupply, REWARD_PRECISION) ); 
        
        if (blockRewardPerBoosted > 0)
            cumulativeRewardPerBoosted = cumulativeRewardPerBoosted.add(blockRewardPerBoosted);

        if (_account != address(0) ) {
            if (stakedBoosted[_account] > 0){
                uint256 accountReward = stakedBoosted[_account].mul(cumulativeRewardPerBoosted.sub(entryCumulatedRewardPerBoosted[_account])).div(REWARD_PRECISION);
                claimableReward[_account] = claimableReward[_account].add(accountReward);
            }
            entryCumulatedRewardPerBoosted[_account] = cumulativeRewardPerBoosted;
        }
    }


    function _claim(address _account, address _receiver) private returns (uint256) {
        _updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        if (tokenAmount > 0) {
            // IERC20(rewardToken).safeTransfer(_receiver, tokenAmount);
            IMintable(rewardToken).mint(_receiver, tokenAmount);
            claimedRewards += tokenAmount;
            emit Claim(_account, tokenAmount, _receiver);
        }
        return tokenAmount;
    }


    function _stake(address _account,  uint256 _amount) private {
        address _inviter = IPID(pid).inviter(_account);
        _updateRewards(_account);
        _updateRewards(_inviter);

        if (feeRatio > 0){
            uint256 fee = _amount.mul(feeRatio).div(FEE_PRECISION);
            IMintable(depositToken).burn(fee);
            _amount = _amount.sub(fee);
        }
        totalBoostedSupply = totalBoostedSupply.sub(stakedBoosted[_inviter]).sub(stakedBoosted[_account]);
        stakedToken[_account] = stakedToken[_account].add(_amount);
        
        IPID(pid).updateRank(_account);//inviter updated simultaneously
        {
            (uint256 _boost, uint256 _boostPrec) = IPID(pid).boost(_account);
            uint256 _boostedToken = FullMath.mulDiv(stakedToken[_account], _boost, _boostPrec);
            stakedBoosted[_account] = _boostedToken;
            totalBoostedSupply += _boostedToken;
            emit Stake(_account, stakedToken[_account], _boostedToken);
        }

        {
            (uint256 _boost, uint256 _boostPrec) = IPID(pid).boost(_inviter);
            uint256 _boostedToken = FullMath.mulDiv(stakedToken[_inviter], _boost, _boostPrec);
            stakedBoosted[_inviter] = _boostedToken;
            totalBoostedSupply += _boostedToken;
            emit Stake(_inviter, stakedToken[_inviter], _boostedToken);
        }

        // Update Rate
        totalDepositToken = totalDepositToken.add(stakedToken[_account]);
        boostedRewardPerSec_PREC = totalBoostedSupply > 0 ? baseRewardPerSec_PREC.div(totalBoostedSupply) : 0;
        emit UpdateRate(boostedRewardPerSec_PREC, totalBoostedSupply);
    }

    function _unstake(address _account, uint256 _amount, address _receiver) private {
        require(_amount > 0, "invalid _amount");
        require(stakedToken[_account] >= _amount, "amount exceeds stakedAmount");

        address _inviter = IPID(pid).inviter(_account);
        _claim(_account, _receiver);
        _updateRewards(_inviter);

        totalBoostedSupply = totalBoostedSupply.sub(stakedBoosted[_inviter]).sub(stakedBoosted[_account]);
        stakedToken[_account] = stakedToken[_account].sub(_amount);
        totalDepositToken = totalDepositToken.sub(_amount);
        IPID(pid).updateRank(_account);//inviter updated simultaneously in pid update rank

        {
            (uint256 _boost, uint256 _boostPrec) = IPID(pid).boost(_account);
            uint256 _boostedToken = FullMath.mulDiv(stakedToken[_account], _boost, _boostPrec);
            stakedBoosted[_account] = _boostedToken;
            totalBoostedSupply += _boostedToken;
            emit Unstake(_account, stakedToken[_account], _boostedToken);
        }

        {
            (uint256 _boost, uint256 _boostPrec) = IPID(pid).boost(_inviter);
            uint256 _boostedToken = FullMath.mulDiv(stakedToken[_inviter], _boost, _boostPrec);
            stakedBoosted[_inviter] = _boostedToken;
            totalBoostedSupply += _boostedToken;
            emit Unstake(_inviter, stakedToken[_inviter], _boostedToken);
        }

        boostedRewardPerSec_PREC = totalBoostedSupply > 0 ? baseRewardPerSec_PREC.div(totalBoostedSupply) : 0;
        emit UpdateRate(boostedRewardPerSec_PREC, totalBoostedSupply);

        IERC20(depositToken).safeTransfer(_receiver, _amount);
    }


    // Func. for public view
    function balanceOf(address _account) external view returns (uint256) {
        return stakedToken[_account];
    }

}
