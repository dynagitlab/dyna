// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/FullMath.sol";
import "../DID/interfaces/IPID.sol";

interface IFeeRouter {
    function distribute() external;
}

contract InstStaking is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct RewardInfo {
        address token;
        uint256 balance;
        uint256 cumulatedRewardPerToken_PREC;
    }
    mapping (address => RewardInfo) rewardInfo;
    address[] public rewardTokens;

    address public pid;
    address public feeRouter;
    uint256 public totalDepositToken;
    uint256 public totalDepositBoosted;

    uint256 public constant REWARD_PRECISION = 10 ** 20;
   
    //record for accounts
    mapping(address => uint256) public userDepositToken;
    mapping(address => uint256) public userDepositBoosted;

    mapping(address => mapping(address => uint256)) public entryCumulatedReward_PREC;
    mapping(address => mapping(address => uint256)) public unclaimedReward;
    mapping(address => mapping(uint256 => uint256)) public rewardRecord;

    event UpdateBalance(address account, uint256 tokenBalance, uint256 boostedBalance);

    address public immutable depositToken;
    constructor(address _depositToken) {
        depositToken = _depositToken;
    }
    
    //-- owner 
    function setRewards(address[] memory _rewardTokens) external onlyOwner {
        rewardTokens = _rewardTokens;
    }

    function setAddress(address _feeRouter, address _pid) external onlyOwner {
        feeRouter = _feeRouter;
        pid = _pid;
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }


    //-- public view func.
    function userDeposit(address _account) public view returns (uint256, uint256) {
        return (userDepositToken[_account], userDepositBoosted[_account]);
    }
    function totalDeposit() public virtual view returns (uint256, uint256) {
        return (totalDepositToken, totalDepositBoosted);
    }

    function getRewardInfo(address _token) public view returns (RewardInfo memory){
        return rewardInfo[_token];
    }

    function getRewardTokens() public view returns (address[] memory) {
        return rewardTokens;
    }

    function pendingReward(address _token) public view returns (uint256) {
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        return currentBalance > rewardInfo[_token].balance ? currentBalance.sub(rewardInfo[_token].balance) : 0;
    }

    function claimable(address _account) public view returns (address[] memory, uint256[] memory){
        uint256[] memory claimable_list = new uint256[](rewardTokens.length);
        uint256 _totalDepositBoosted = totalDepositBoosted;
        uint256 _userDepositBoosted = userDepositBoosted[_account];

        for(uint8 i = 0; i < rewardTokens.length; i++){
            address _tk = rewardTokens[i];
            claimable_list[i] = unclaimedReward[_account][_tk];

            if (_userDepositBoosted > 0 && _totalDepositBoosted > 0){
                uint256 pending_reward = pendingReward(_tk);

                claimable_list[i] = claimable_list[i]
                    .add( FullMath.mulDiv(_userDepositBoosted, pending_reward, _totalDepositBoosted)  )
                    .add( FullMath.mulDiv(_userDepositBoosted, rewardInfo[_tk].cumulatedRewardPerToken_PREC.sub(entryCumulatedReward_PREC[_account][_tk]), REWARD_PRECISION));
            }
        }
        return (rewardTokens, claimable_list);
    }


    function aprRecord(address _token) public view returns (uint256, uint256, uint256) {
        uint256 total_reward = 0;
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        if (currentBalance > rewardInfo[_token].balance) 
            total_reward = currentBalance.sub(rewardInfo[_token].balance);   
        uint256 _cur_hour = block.timestamp.div(3600);
        for(uint i = 0; i < 24; i++){
            total_reward = total_reward.add(rewardRecord[_token][_cur_hour-i]);
        }
        return (total_reward, totalDepositBoosted, totalDepositToken);
    }

    function _distributeReward(address _token) private {
        uint256 currentBalance = IERC20(_token).balanceOf(address(this));
        if (currentBalance <= rewardInfo[_token].balance) 
            return;

        uint256 rewardToDistribute = currentBalance.sub(rewardInfo[_token].balance);
        uint256 _hour = block.timestamp.div(3600);
        rewardRecord[_token][_hour] = rewardRecord[_token][_hour].add(rewardToDistribute);
        // calculate cumulated reward
        uint256 _totalDepositBoosted = totalDepositBoosted;
        if (_totalDepositBoosted > 0){
            rewardInfo[_token].cumulatedRewardPerToken_PREC = 
                rewardInfo[_token].cumulatedRewardPerToken_PREC.add(
                        FullMath.mulDiv(rewardToDistribute, REWARD_PRECISION, _totalDepositBoosted)
                    );
        }
        //update balance
        rewardInfo[_token].balance = currentBalance;
    }

    function updateRewards(address _account) public {
        for(uint8 i = 0; i < rewardTokens.length; i++){
            _distributeReward(rewardTokens[i]);
        }

        if (_account != address(0) && _account != address(this)){
            uint256 _userDepositBoosted = userDepositBoosted[_account];
            
            if (_userDepositBoosted > 0){
                for(uint8 i = 0; i < rewardTokens.length; i++){
                    unclaimedReward[_account][rewardTokens[i]] = 
                        unclaimedReward[_account][rewardTokens[i]].add(
                                FullMath.mulDiv(
                                    _userDepositBoosted, 
                                    rewardInfo[rewardTokens[i]].cumulatedRewardPerToken_PREC.sub(entryCumulatedReward_PREC[_account][rewardTokens[i]]),
                                    REWARD_PRECISION)
                            );
                }
            }
            
            for(uint8 i = 0; i < rewardTokens.length; i++){
                entryCumulatedReward_PREC[_account][rewardTokens[i]] = rewardInfo[rewardTokens[i]].cumulatedRewardPerToken_PREC;
            }
        }
    }

    function update(address _account) external {
        _update(_account, 0, false);
    }

    function _update(address _account, uint256 _tokenDelta, bool _isIncrease) private {
        updateRewards(_account); 
        uint256 _userDepositBoosted = userDepositBoosted[_account];
        uint256 _userDepositToken = userDepositToken[_account];
        if (_userDepositBoosted > 0)
            totalDepositBoosted = totalDepositBoosted.sub(_userDepositBoosted);

        if (_tokenDelta > 0){
            if (_isIncrease){
                _userDepositToken = _userDepositToken.add(_tokenDelta);
                totalDepositToken = totalDepositToken.add(_tokenDelta);
            }
            else{
                require(_userDepositToken >= _tokenDelta, "insufficient deposit balance");
                _userDepositToken = _userDepositToken.sub(_tokenDelta);
                totalDepositToken = totalDepositToken.sub(_tokenDelta);
            }
        }

        userDepositToken[_account] = _userDepositToken;

        (uint256 _boost, uint256 _boostPrec) = IPID(pid).boost(_account);
        uint256 _boostedAmount = FullMath.mulDiv(_boost, _userDepositToken, _boostPrec);

        totalDepositBoosted = totalDepositBoosted.add(_boostedAmount);
        userDepositBoosted[_account] = _boostedAmount;

        emit UpdateBalance(_account, _userDepositToken, _boostedAmount);
    }


    function _transferOut(address _receiver, address _token, uint256 _amount) private {
        if (_amount == 0) return;
        require(rewardInfo[_token].balance >= _amount, "Insufficient token balance");
        rewardInfo[_token].balance = rewardInfo[_token].balance.sub(_amount);
        IERC20(_token).safeTransfer(_receiver, _amount);
    }

    function stake(uint256 _amount) public {
        if (feeRouter != address(0))
            IFeeRouter(feeRouter).distribute();

        address _account = msg.sender;
        IERC20(depositToken).safeTransferFrom(_account, address(this), _amount);
        _update(_account, _amount, true);
    }   
    
    
    function unstake(uint256 _amount) public returns (address[] memory, uint256[] memory ) {
        if (feeRouter != address(0))
            IFeeRouter(feeRouter).distribute();

        address _account = msg.sender;
        uint256[] memory claim_res = _claim(_account);
        _update(_account, _amount, false);
        IERC20(depositToken).safeTransfer(_account, _amount);
        return (rewardTokens, claim_res);
    }

    function claim() public returns (address[] memory, uint256[] memory ) {  
        if (feeRouter != address(0))
            IFeeRouter(feeRouter).distribute();

        return (rewardTokens, _claim(msg.sender));
    }

    function claimForAccount(address _account) public returns (address[] memory, uint256[] memory){
        if (feeRouter != address(0))
            IFeeRouter(feeRouter).distribute();

        return (rewardTokens, _claim(_account));
    }

    function _claim(address _account) private returns (uint256[] memory ) {
        uint256[] memory claim_res = new uint256[](rewardTokens.length);  
        updateRewards(_account);    
        for(uint8 i = 0; i < rewardTokens.length; i++){
            _transferOut(_account,rewardTokens[i], unclaimedReward[_account][rewardTokens[i]]);
            claim_res[i] = unclaimedReward[_account][rewardTokens[i]] ;
            unclaimedReward[_account][rewardTokens[i]] = 0;
        }
        return claim_res;
    }


}
