// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPID.sol";


interface IAcitivity {
    function balanceOf(address _account) external view returns (uint256);
    function update(address _account) external;

    function inviterRebates(address) external view returns (uint256);

    function claimRebates(address _account) external;
    function claimBondRebates(address _account) external;

    
}



contract PIDHelper is Ownable {
    using SafeMath for uint256;
    using Strings for uint256;

    uint256 public constant GTOKEN_PRICEISION = 1e18; //must be 18 decimals
    uint256 public constant PRICE_PRECISION = 1e30;
    uint256 public constant USD_TO_SCORE_PRECISION = 1e24;
    uint256 public constant COM_PRECISION = 1e6;
    uint256 public constant MAX_BOOST = 100 * COM_PRECISION;//100 Times max   
    
    address public immutable pid;

    address public gBond;
    address public tradeRebate;


    constructor(address _pid) {
        pid = _pid;
    }

    function setAddress(address _gBond, address _tradeRebate) external onlyOwner{
        gBond = _gBond;
        tradeRebate = _tradeRebate;
    }

    //=================Public data reading =================
    struct PidDispInfoFull{
        uint64 id;
        string refCode;
        string nickName;
        uint8 rank;
        uint64 nomNumber;
        uint64 idvPoints;
        uint64 rebPoints;
        address inviter;
        uint256 boost;
        address account;
        uint256 stakedBalance;
        uint256 tradeVolume;

        uint256 bondRebateClaimable;
        uint256 tradeRebateClaimable;
    }



    function getBasicInfo(address _account) public view returns (PidDispInfoFull memory df) {
        IPID.PidDispInfo memory disp = IPID(pid).getBasicInfo(_account);
        df.id = disp.id;
        df.refCode = disp.refCode;
        df.nickName = disp.nickName;
        df.rank = disp.rank;
        df.nomNumber = disp.nomNumber;
        df.idvPoints = disp.idvPoints;
        df.rebPoints = disp.rebPoints;
        df.inviter = disp.inviter;
        df.boost = disp.boost;
        df.account = disp.account;
        df.stakedBalance = disp.stakedBalance;
        df.tradeVolume = disp.tradeVolume;

        df.bondRebateClaimable = IAcitivity(gBond).inviterRebates(_account);
        df.tradeRebateClaimable = IAcitivity(tradeRebate).inviterRebates(_account);
    }

    function claimRebates(address _account) public{
        IAcitivity(gBond).claimBondRebates(_account);
        IAcitivity(tradeRebate).claimRebates(_account);
    }


}


