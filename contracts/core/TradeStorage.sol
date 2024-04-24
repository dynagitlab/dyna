// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITradeStorage.sol";
import "../DID/interfaces/IPID.sol";


contract TradeStorage is Ownable, ITradeStorage{
    using SafeMath for uint256;

    bool public recordFlag;
    IPID public sToken;
    mapping(address => bool) public recorders;

    mapping(address => mapping(uint256 => uint256)) public override tradeVol;
    mapping(address => mapping(uint256 => uint256)) public override swapVol;
    mapping(uint256 => uint256) public override totalTradeVol;
    mapping(uint256 => uint256) public override totalSwapVol;


    event UpdateTrade(address account, uint256 volUsd, uint256 boostUsd, uint256 day);
    event UpdateSwap(address account, uint256 volUsd, uint256 boostUsd, uint256 day);
    event SetRecorder(address rec, bool status);

    modifier onlyRecorder() {
        require(recorders[msg.sender], "[TradeRec] only recorder");
        _;
    }

    constructor (address _sToken){
        recordFlag = true;
        sToken = IPID(_sToken);
    }
    

    // ---------- owner setting part ----------
    function setSToken(address _sToken) external onlyOwner{
        sToken = IPID(_sToken);
    }

    function setRecorder(address _rec, bool _status) external onlyOwner{
        recorders[_rec] = _status;
        emit SetRecorder(_rec, _status);
    }

    function startRec() external onlyOwner{
        recordFlag = true;
    }

    function stopRec() external onlyOwner{
        recordFlag = false;
    }

    function updateTrade(address _account, uint256 _volUsd) external override onlyRecorder{
        if (!recordFlag)
            return;
        (uint256 _boost, uint256 _boostPrec) = sToken.boost(_account);
        uint256 boostedVol = _volUsd.mul(_boost).div(_boostPrec);
        uint256 _day = block.timestamp.div(86400);
        tradeVol[_account][_day] = tradeVol[_account][_day].add(boostedVol);
        totalTradeVol[_day] = totalTradeVol[_day].add(boostedVol);
        emit UpdateTrade(_account, _volUsd, boostedVol, _day);
    }

    function updateSwap(address _account, uint256 _volUsd) external override onlyRecorder{
        if (!recordFlag)
            return;
        (uint256 _boost, uint256 _boostPrec) = sToken.boost(_account);
        uint256 boostedVol = _volUsd.mul(_boost).div(_boostPrec);
        uint256 _day = block.timestamp.div(86400);
        swapVol[_account][_day] = swapVol[_account][_day].add(boostedVol);
        totalSwapVol[_day] = totalSwapVol[_day].add(boostedVol);
        emit UpdateSwap(_account, _volUsd, boostedVol, _day);
    }
}
