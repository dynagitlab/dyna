// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IgToken} from "./interfaces/IgToken.sol";

import "../DID/interfaces/IPID.sol";
import "../core/FullMath.sol";
import "../tokens/interfaces/IMintable.sol";

contract TokenVesting is Ownable {
    using SafeERC20 for ERC20;
    using SafeMath for uint;

    /* ======== STATE VARIABLES ======== */

    address immutable public payoutToken;
    address immutable public principalToken;
    IPID public pid;
    // IgToken public totalVe;

    mapping(address => bool) public blacklist;


    uint public totalPrincipalVesting;
    uint public totalPayoutGiven;

    uint public price = 10000;
    uint public pricePrecision = 1e4;
    uint256 public calPrecision = 1e7;
    bool public depositStarted = true;

    // uint256[] public rankVestingDurationList = [30 days, 30 days, 30 days, 30 days, 30 days, 30 days, 30 days, 30 days, 30 days, 30 days];
    uint256 public baseDuration = 30 days;

    mapping(address => Vesting) public vestingInfo; // stores bond information for depositors
    mapping(address => uint256) public currentVestingDuration;

    event Quit(address account, uint256 payout, uint256 fee);
    event StopVesting(address depositor, uint256 remainPayout);

    struct Vesting {
        uint payout; // payout token remaining to be paid
        uint vesting; // seconds left to vest
        uint lastBlockTimestamp; // Last interaction
    }

    constructor(
        address _principalToken,
        address _payOutToken,
        address _pid
        // address _totalVe
    ) {
        require(ERC20(_payOutToken).decimals() == ERC20(_principalToken).decimals(), "decimals mismatch");
        payoutToken = _payOutToken;
        principalToken = _principalToken;
        pid = IPID(_pid);
        // totalVe = IgToken(_totalVe);
    }

    function reverseDeposit(uint _amount) external {
        address _depositor = msg.sender;
        // require(principalToken.balanceOf(address(this)) >= _amount, "not enough token" );
        ERC20(payoutToken).safeTransferFrom(_depositor, address(this), _amount);
        IMintable(payoutToken).burn(_amount);
        IMintable(principalToken).mint(_depositor, _amount);        
    }

    function setPID(address _pid) external onlyOwner {
        pid = IPID(_pid);
    }

    function setDuration(uint256 _durationDays) external onlyOwner{
        require(_durationDays < 366, "max days");
        baseDuration = _durationDays * 86400;
    }

    //set rankVestingDurationList
    // function setRankVestingDurationList(uint256[] memory _rankVestingDurationList) external onlyOwner() {
    //     rankVestingDurationList = _rankVestingDurationList;
    // }


    function payOutOfTokenAmount(uint256 _amount) public view returns (uint256){
        return _amount.mul(price).div(pricePrecision);
    }


    function setStart() external onlyOwner returns (bool) {
        depositStarted = !depositStarted;
        return depositStarted;
    }

    function deposit(uint _amount) external returns (uint) {
        require(depositStarted, "Unlock is not available now");
        // uint256 rank = pid.rank(msg.sender);
        // require(rank > 0, "You need to mint a PID before unlocking");
        address _depositor = msg.sender;
        ERC20(principalToken).safeTransferFrom(_depositor, address(this), _amount);
        IMintable(principalToken).burn(_amount);

        _redeem(_depositor);

        uint payout = payOutOfTokenAmount(_amount);

        uint256 _lockDuration = baseDuration;
        {
            (uint256 boostVal, uint256 boostPrec) = pid.boost(_depositor);
            _lockDuration = _lockDuration.mul(boostPrec).div(boostVal);
        }

        // depositor info is stored
        vestingInfo[_depositor] = Vesting({
            payout: vestingInfo[_depositor].payout.add(payout),
            vesting: _lockDuration,
            lastBlockTimestamp: block.timestamp
        });

        // require(totalVe.balanceOf(_depositor) >= (vestingInfo[_depositor].payout), "veToken not enough");

        //store currentVestingDuration
        currentVestingDuration[_depositor] = _lockDuration;

        // total vesting increased
        totalPrincipalVesting = totalPrincipalVesting.add(_amount);
        // total payout increased
        totalPayoutGiven = totalPayoutGiven.add(payout);
        return payout;
    }

    function stopVesting( ) external returns (uint){
        address _depositor = msg.sender;
        _redeem(_depositor);
        uint256 remainPayout = vestingInfo[_depositor].payout;
        delete vestingInfo[_depositor];

        if (remainPayout > 0){
            IMintable(principalToken).mint(_depositor, remainPayout);
        }
        emit StopVesting(_depositor, remainPayout); 
        return remainPayout;
    }

    function quit( ) external returns (uint) {
        address _depositor = msg.sender;
        _redeem(_depositor);
        uint256 remainDuration = vestingInfo[_depositor].vesting;
        uint256 remainPayout = vestingInfo[_depositor].payout;
        delete vestingInfo[_depositor];

        uint256 payout = 0;
        if (remainPayout > 0 &&  remainDuration > 0){
            uint256 fee = FullMath.mulDiv(remainDuration, remainPayout, 4320000); //2% per day, * 2% / 86400 = /4320000
            payout = remainPayout > fee ? remainPayout - fee : 0;
            if (payout > 0){
                // payoutToken.safeTransfer(_depositor, payout);
                IMintable(payoutToken).mint(_depositor, payout);
            }
            emit Quit(_depositor, remainPayout, fee);
        }
        
        return payout;
    }



    function redeem(address _depositor) public returns (uint) {
        require(!blacklist[_depositor], "Not allowed to claim.");
        return _redeem(_depositor);
    }

     /**
     *  @notice redeem for user
     *  @return uint
     */
    function _redeem(address _depositor) internal returns (uint) {

        Vesting memory info = vestingInfo[_depositor];
        uint percentVested = percentVestedFor(_depositor);

        if (percentVested == 0) {
            return 0;
        }
        // (seconds since last interaction / vesting term remaining)

        if (percentVested >= calPrecision) {// if fully vested
            delete vestingInfo[_depositor];
            // delete user info
            // payoutToken.safeTransfer(_depositor, info.payout);
            IMintable(payoutToken).mint(_depositor, info.payout);
            return info.payout;

        } else {// if unfinished
            // calculate payout vested
            uint payout = info.payout.mul(percentVested).div(calPrecision);

            // store updated deposit info

            vestingInfo[_depositor] = Vesting({
                payout: info.payout.sub(payout),
                vesting: info.vesting.sub(block.timestamp.sub(info.lastBlockTimestamp)),
                lastBlockTimestamp: block.timestamp
            });
            // payoutToken.safeTransfer(_depositor, payout);
            IMintable(payoutToken).mint(_depositor, payout);
            return payout;
        }

    }

    // redeem and transferTo

    function redeemAndTransferTo(address _transferTo) public returns (uint) {
        address _depositor = msg.sender;
        Vesting memory info = vestingInfo[_depositor];
        uint percentVested = percentVestedFor(_depositor);

        if (percentVested == 0) {
            return 0;
        }
        // (seconds since last interaction / vesting term remaining)


        if (percentVested >= calPrecision) {// if fully vested
            delete vestingInfo[_depositor];
            // delete user info

            // payoutToken.safeTransfer(_depositor, info.payout);
            IMintable(payoutToken).mint(_depositor, info.payout);
            return info.payout;

        } else {// if unfinished
            // calculate payout vested
            uint payout = info.payout.mul(percentVested).div(calPrecision);
            // store updated deposit info
            vestingInfo[_depositor] = Vesting({
                payout: info.payout.sub(payout),
                vesting: info.vesting.sub(block.timestamp.sub(info.lastBlockTimestamp)),
                lastBlockTimestamp: block.timestamp
            });
            // payoutToken.safeTransfer(_transferTo, payout);
            IMintable(payoutToken).mint(_transferTo, info.payout);
            return payout;
        }
    }

    /**
     *  @notice calculate how far into vesting a depositor is
     *  @param _depositor address
     *  @return percentVested_ uint
     */
    function percentVestedFor(address _depositor) public view returns (uint percentVested_) {
        Vesting memory vest = vestingInfo[_depositor];
        uint timestampSinceLast = block.timestamp.sub(vest.lastBlockTimestamp);
        uint vesting = vest.vesting;

        if (vesting > 0) {
            percentVested_ = timestampSinceLast.mul(calPrecision).div(vesting);
        } else {
            percentVested_ = 0;
        }
    }

    /**
     *  @notice calculate amount of payout token available for claim by depositor
     *  @param _depositor address
     *  @return pendingPayout_ uint
     */
    function pendingPayoutFor(address _depositor) external view returns (uint pendingPayout_) {
        uint percentVested = percentVestedFor(_depositor);
        uint payout = vestingInfo[_depositor].payout;

        if (percentVested >= calPrecision) {
            pendingPayout_ = payout;
        } else {
            pendingPayout_ = payout.mul(percentVested).div(calPrecision);
        }
    }

    //set address to  blacklist
    function setBlacklist(address _address, bool _isBlacklist) external onlyOwner() {
        blacklist[_address] = _isBlacklist;
    }
    //set price
    function setPrice(uint _price) external onlyOwner() {
        price = _price;
    }

    //set price precision
    function setPricePrecision(uint _pricePrecision) external onlyOwner() {
        pricePrecision = _pricePrecision;
    }

    function withdraw(
        address _erc20,
        address _to,
        uint256 _val
    ) external onlyOwner returns (bool) {
        ERC20(_erc20).safeTransfer(_to, _val);
        return true;
    }

}