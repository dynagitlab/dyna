// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../core/interfaces/ITradeStorage.sol";
import "../DID/interfaces/IPID.sol";


contract TradeRebateV2 is ReentrancyGuard, Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public rewardToken;
    address public tradeRecord;
    address public pid;


    mapping (uint256 => uint256) public roundRewards;
    mapping (address => bool) public bList;
    mapping (address => mapping(uint256 => uint256)) public userRoundClaimed;
    mapping (uint256 => uint256) public roundClaimed;

    mapping (address => uint256) public inviterRebates;


    event ClaimRound(address _account, uint256 _roundId, address  _rewardToken, uint256 _rewards);
    event SetRound(uint256[] rounds, uint256[] rewards);
    event RebateReward(address account, address inviter, uint256 rebateVal);
    event ClaimRebates(address account, uint256 value);
    function withdrawToken(address _account, address _token, uint256 _amount) external onlyOwner{
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function sendValue(address payable _receiver, uint256 _amount) external onlyOwner {
        _receiver.sendValue(_amount);
    }
    function setBlist(address[] memory _bList, bool _sta) external onlyOwner{
        for(uint256 i = 0; i < _bList.length; i++){
            bList[_bList[i]] = _sta;
        }
    }

    function setAddress(address _rewardToken, address _tradeRecord, address _pid) external onlyOwner{
        rewardToken = _rewardToken;
        tradeRecord = _tradeRecord;
        pid = _pid;
    }

    function setRound(uint256[] memory _rounds, uint256[] memory _rewards) external onlyOwner {
        for(uint256 i = 0; i < _rounds.length; i++){
            roundRewards[_rounds[i]] = _rewards[i];
        }
        emit SetRound(_rounds, _rewards);
    }

    function curRound() public view returns (uint256){
        return block.timestamp.div(86400);
    }

    function claimable(address _account, uint256 _roundId) public view returns (uint256){
        if (roundRewards[_roundId] == 0)
            return 0;

        uint256 totalVol = ITradeStorage(tradeRecord).totalTradeVol(_roundId).add(ITradeStorage(tradeRecord).totalSwapVol(_roundId));
        if (totalVol == 0)
            return 0;

        uint256 userVol = ITradeStorage(tradeRecord).tradeVol(_account, _roundId);
        userVol = userVol.add(ITradeStorage(tradeRecord).swapVol(_account, _roundId));
        require(userVol <= totalVol, "invalid trading volume");
      
        uint256 _userRewd = roundRewards[_roundId].mul(userVol).div(totalVol);
        return _userRewd > userRoundClaimed[_account][_roundId] ? _userRewd.sub(userRoundClaimed[_account][_roundId]) : 0;
    }

    function claimRebates(address _account) public{
        uint256 _rebatedReward = inviterRebates[_account];
        require(_rebatedReward > 0, "no rebated rewards");
        inviterRebates[_account] = 0;

        IERC20(rewardToken).safeTransfer(_account, _rebatedReward);
        emit ClaimRebates(_account, _rebatedReward);
    }

    function claimRound(uint256 _roundId) public returns (uint256){
        require(_roundId < curRound(), "Round not claimable.");
        address _account = msg.sender;

        if (bList[_account])
            return 0;

        uint256 claimableRew = claimable(_account, _roundId);
        if (claimableRew < 1)
            return 0;

        require(IERC20(rewardToken).balanceOf(address(this)) > claimableRew, "insufficient reward token");
        roundClaimed[_roundId] = roundClaimed[_roundId].add(claimableRew);
        require(roundClaimed[_roundId] <= roundRewards[_roundId], "insufficient round rewards");

        userRoundClaimed[_account][_roundId] = userRoundClaimed[_account][_roundId].add(claimableRew);

        IERC20(rewardToken).safeTransfer(_account, claimableRew);
        emit ClaimRound(_account, _roundId, rewardToken, claimableRew);

        // rebate
        {
            (address _inviter, uint256 _rebateVal) = IPID(pid).inviterRebatesValue(_account, claimableRew);
            if (_inviter != address(0))
                inviterRebates[_inviter] += _rebateVal;
            emit RebateReward(_account, _inviter, _rebateVal);
        }

        return claimableRew;
    }
    
    

    struct DispInfo{
        uint256 round;
        uint256 roundReward;
        uint256 totalPoints;

        uint256 userPoints;
        uint256 claimable;

        uint256 rebateReward;
    }

    function disp(uint256 _round, address _account) public view returns(DispInfo memory dispInfo){
        dispInfo.round = _round > 0 ? _round : curRound();
        dispInfo.roundReward = roundRewards[dispInfo.round];

        dispInfo.totalPoints = ITradeStorage(tradeRecord).totalTradeVol(dispInfo.round).add(ITradeStorage(tradeRecord).totalSwapVol(_round));

        if (_account != address(0)){
            dispInfo.userPoints = ITradeStorage(tradeRecord).tradeVol(_account, dispInfo.round) + 
                                ITradeStorage(tradeRecord).swapVol(_account, dispInfo.round);
            dispInfo.claimable = claimable(_account, dispInfo.round);
        }
        dispInfo.rebateReward = inviterRebates[_account];
    }


}