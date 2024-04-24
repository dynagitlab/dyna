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
}



contract PID is Ownable, IPID{
    using SafeMath for uint256;
    using Strings for uint256;

    string public refPrefix;

    uint256 public constant GTOKEN_PRICEISION = 1e18; //must be 18 decimals
    uint256 public constant PRICE_PRECISION = 1e30;
    uint256 public constant USD_TO_SCORE_PRECISION = 1e24;
    uint256 public constant COM_PRECISION = 1e6;
    uint256 public constant MAX_BOOST = 100 * COM_PRECISION;//100 Times max   
    
    
    struct RankInfo{
        uint64 minPoints;
        uint32 multiplier;
        uint32 rebates;
        uint64 points;
        uint32 iBoost;
    }
    mapping(uint256 => RankInfo) public rankMap;

    event ScoreUpdate(address _account, address _fromAccount, uint256 _addition, uint256 _reasonCode);
    event ScoreDecrease(address _account, uint256 _amount, uint256 _timegap);
    event RankUpdate(address _account, uint256 _rankP, uint256 _rankA);
    event UpdateFee(address _account, uint256 _origFee, uint256 _discountedFee, address _parent, uint256 _rebateFee);
    event Mint(address newAccount, uint256 userId, string newRefCode, address inviter);

    address public activity;
    address public gStaking;
    uint256 public defaultCodeIdx = 1;

    struct STStr {
        uint8 rank;
        uint32 nomNumber;
        uint64 inviterId;
        uint64 indPoints;
        uint64 rebPoints;
    }
    mapping(uint256 => STStr) public tokens; 

    uint256 public totalAccountsCount;

    mapping(uint256 => address) public idToAccount; 
    mapping(address => uint256) public accountToId; 
   
    mapping(string => uint256) public refCodeId;
    mapping(uint256 => string) public idNickName;
    mapping(uint256 => string) public refCode;

    constructor(string memory _refPref) {
        refPrefix = _refPref;
        string memory defRC = genReferralCode(0);
        refCodeId[defRC] = 1;
        _mint(address(this), defRC, "PROJECT");
    }

    ///--------------------- Owner setting
    function setScorePara(
        uint256 _rankId, 
        uint64 _minPoints,
        uint32 _multiplier,
        uint32 _iBoost,
        uint32 _rebates ) external onlyOwner {
        // require(_value < 1000, "invalid value");
        require(_multiplier <= MAX_BOOST, "max boost");
        require(_multiplier >= COM_PRECISION, "max boost");
        require(_rebates <= COM_PRECISION, "max rebates");
        require(_iBoost <= MAX_BOOST, "max boost");
        
        rankMap[_rankId] = RankInfo({
            minPoints : _minPoints,
            multiplier: _multiplier,
            rebates : _rebates,
            points : 0,
            iBoost : _iBoost
            });
    }

    function setDefaultCodeIdx(uint256 _id) external onlyOwner{
        defaultCodeIdx = _id;
    }
    
    function setAddress(address _gStaking, address _activity) public onlyOwner {
        gStaking = _gStaking;
        activity = _activity;
    }


    // ================= update =================
    // execute when invest accounts or staking balance
    function updateRank(address _account) public override {
        _updateRank(_account, accountToId[_account]);
    }

    function _updateRank(address _account, uint256 _id) public {
        if (_id < 1 || gStaking == address(0))
            return;
            
        STStr memory _accountToken = tokens[_id];
        STStr memory _inviterToken = tokens[_accountToken.inviterId];
        
        _inviterToken.rebPoints = _inviterToken.rebPoints > _accountToken.indPoints 
                                    ?
                                    _inviterToken.rebPoints - _accountToken.indPoints 
                                    :
                                    0;
        
        _accountToken.indPoints = uint64(IAcitivity(gStaking).balanceOf(_account).div(GTOKEN_PRICEISION));
        _inviterToken.rebPoints += _accountToken.indPoints;
        
        // update account rank
        {
            _accountToken.rank = 0;
            uint64 _combPoints = _accountToken.indPoints + _accountToken.rebPoints;
            for(; _accountToken.rank < 10; _accountToken.rank++) {
                RankInfo memory _nextRkInfo = rankMap[_accountToken.rank + 1];
                if (_nextRkInfo.minPoints < 1)
                    break;
                if (_combPoints < _nextRkInfo.minPoints){
                    break;
                }
            }
        }
        {
            _inviterToken.rank = 0;
            uint64 _combPoints = _inviterToken.indPoints + _inviterToken.rebPoints;
            for(; _inviterToken.rank < 10; _inviterToken.rank++) {
                RankInfo memory _nextRkInfo = rankMap[_inviterToken.rank + 1];
                if (_nextRkInfo.minPoints < 1)
                    break;
                if (_combPoints < _nextRkInfo.minPoints){
                    break;
                }
            }
        }
        // update account rank

 
        //sWrite to update
        tokens[_id] = _accountToken;
        tokens[_accountToken.inviterId] = _inviterToken;

        if (activity != address(0)){
            IAcitivity(activity).update(_account);
            IAcitivity(activity).update(idToAccount[_accountToken.inviterId]);
        }
    }

    
    function boost(address _account) public override view returns (uint256, uint256){
        return boostById( accountToId[_account]);
    }

    function boostById(uint256 _accountId) public view returns (uint256, uint256){
        if (_accountId < 1)
            return (COM_PRECISION, COM_PRECISION);
        uint256 _inviterId = tokens[_accountId].inviterId;
        if (_inviterId < 1)
            return (COM_PRECISION, COM_PRECISION);
        uint256 _rankBoost = uint256(
                    rankMap[tokens[_accountId].rank].multiplier
                    +
                    rankMap[tokens[_inviterId].rank].iBoost
                );

        return (_rankBoost < COM_PRECISION ? COM_PRECISION : _rankBoost, COM_PRECISION);
    }

    function estimatePointsDelta(address _account, uint256 _tokenDelta, bool _isIncrease) public view returns(uint256, uint256, uint256){
        uint256 _id = accountToId[_account];
        if (gStaking == address(0))
            return(0, COM_PRECISION, 0);
            
        STStr memory _accountToken = tokens[_id];
        STStr memory _inviterToken = tokens[_accountToken.inviterId];
    
        _inviterToken.rebPoints = _inviterToken.rebPoints > _accountToken.indPoints 
                                ?
                                _inviterToken.rebPoints - _accountToken.indPoints 
                                :
                                0;
        
        _accountToken.indPoints = uint64(IAcitivity(gStaking).balanceOf(_account).div(GTOKEN_PRICEISION));
        uint64 _pointsDelta = uint64(_tokenDelta.div(GTOKEN_PRICEISION));
        if (_isIncrease)
            _accountToken.indPoints += _pointsDelta;
        else
            _accountToken.indPoints = _accountToken.indPoints > _pointsDelta ? 
                                        _accountToken.indPoints - _pointsDelta : 0;
        _inviterToken.rebPoints += _accountToken.indPoints;
        

        // update account rank
        {
            _accountToken.rank = 0;
            uint64 _combPoints = _accountToken.indPoints + _accountToken.rebPoints;
            for(; _accountToken.rank < 10; _accountToken.rank++) {
                RankInfo memory _nextRkInfo = rankMap[_accountToken.rank + 1];
                if (_nextRkInfo.minPoints < 1)
                    break;
                if (_combPoints < _nextRkInfo.minPoints){
                    break;
                }
            }
        }

        {
            _inviterToken.rank = 0;
            uint64 _combPoints = _inviterToken.indPoints + _inviterToken.rebPoints;
            for(; _inviterToken.rank < 10; _inviterToken.rank++) {
                RankInfo memory _nextRkInfo = rankMap[_inviterToken.rank + 1];
                if (_nextRkInfo.minPoints < 1)
                    break;
                if (_combPoints < _nextRkInfo.minPoints){
                    break;
                }
            }
        }


        uint256 _rankBoost = uint256(
                    rankMap[_accountToken.rank].multiplier
                    +
                    rankMap[_inviterToken.rank].iBoost
                );

        return (_accountToken.rank, _rankBoost, _inviterToken.rank);
    }




    //================= creation =================
    function safeMint(string memory _refCode) external returns (string memory) {
        // require(tx.origin == msg.sender && !msg.sender.isContract(), "onlyEOA");
        return _mint(msg.sender, _refCode, "Default");
    }

    function mintWithName(string memory _refCode, string memory _nickName) external returns (string memory) {
        // require(tx.origin == msg.sender && !msg.sender.isContract(), "onlyEOA");
        return _mint(msg.sender, _refCode, _nickName);
    }

    function mintDefault( ) external returns (string memory) {
        // require(tx.origin == msg.sender && !msg.sender.isContract(), "onlyEOA");
        return _mint(msg.sender, defaultRefCode(), "DefaultName");
    }


    function _mint(address _newAccount, string memory _refCode, string memory _nickName) internal returns (string memory _newRefCode) {
        require(accountToId[_newAccount] < 1, "already minted.");
        uint64 _referalId = uint64(refCodeId[_refCode]);
        require(_referalId > 0, "Invalid referal Code");
        
        totalAccountsCount += 1;
        require(totalAccountsCount < 1844674407370955161, "max");
        uint256 _userId = totalAccountsCount;

        _newRefCode = genReferralCode(_userId);
        refCode[_userId] =  _newRefCode;
        refCodeId[_newRefCode] = _userId;
        idNickName[_userId] = _nickName;
        accountToId[_newAccount] = _userId;
        idToAccount[_userId] = _newAccount;

        tokens[_userId] = STStr({
                    rank : 0,//200
                    inviterId : uint64(_referalId),
                    nomNumber : 0,
                    indPoints : 0,
                    rebPoints : 0
                });

        tokens[_referalId].nomNumber += 1;
        emit Mint(_newAccount, _userId, _newRefCode, idToAccount[_referalId]);
        _updateRank(_newAccount, _userId);
    }


    function setNickName(string memory _setNN) external {
        uint256 _userId = accountToId[msg.sender];
        require(_userId > 0, "invald holder");
        idNickName[_userId] = _setNN;
    }


    function rank(address _account) public override view returns (uint256){
        return tokens[accountToId[_account]].rank;
    }

    function inviterRebatesValue(address _account, uint256 _value) public override view returns (address, uint256){
        uint256 _accountId = accountToId[_account];
        if (_accountId < 1)
            return (address(0), 0);

        uint256 _rbVal = 0;
        STStr memory _accountToken = tokens[_accountId];

        address _inviter = idToAccount[_accountToken.inviterId];
        {
            (uint256 boostedV, uint256 boostPrec) = boostById(_accountToken.inviterId);
            _rbVal = _value.mul(boostedV).div(boostPrec);
        }

        _rbVal = _rbVal.mul(rankMap[_accountToken.rank].rebates).div(COM_PRECISION);
        return (_inviter, _rbVal);
    }




    function getBasicInfo(address _account) public view returns (PidDispInfo memory disp) {
        disp.id = uint64(accountToId[_account]);
        STStr memory _st = tokens[disp.id];
        disp.rank = _st.rank;
        disp.nomNumber = _st.nomNumber;
        disp.idvPoints = _st.indPoints;
        disp.rebPoints = _st.rebPoints;
        disp.inviter = idToAccount[_st.inviterId];
        disp.nickName = nickName(_account);
        disp.refCode = getRefCode(_account);
        (disp.boost, ) = boost(_account);
        disp.account = _account;
        disp.stakedBalance = IAcitivity(gStaking).balanceOf(_account);
    }


    function getRefCode(address _account) public override view returns (string memory) {
        return refCode[accountToId[_account]];
    }

    function getRefCodeOwner(string memory _refCode) public view returns (PidDispInfo memory disp) {
        address _owner = idToAccount[refCodeId[_refCode]];
        return (getBasicInfo(_owner));
    }

    function getRefCodeOwnerInfo(string memory _refCode) public view returns (address) {
        return idToAccount[refCodeId[_refCode]];
    }


    function defaultRefCode() public view returns (string memory){
        return refCode[defaultCodeIdx];//
    }
    
    function nickName(address _account) public override view returns (string memory){
        return idNickName[accountToId[_account]];
    }

    function balanceOf(address owner) public view returns (uint256) {
        return accountToId[owner] > 0 ? 1 : 0;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        return idToAccount[tokenId];
    }

    function isOwnerOf(address account, uint256 id) public view returns (bool) {
        address owner = ownerOf(id);
        return owner == account;
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return tokenId > 0 && tokenId <= totalAccountsCount;
    }

    function inviter(address _account) public override view returns (address) {
        return idToAccount[tokens[accountToId[_account]].inviterId];
    }
    
    function genReferralCode(uint256 _accountId) public view returns (string memory) {
        bytes memory _orgCode = bytes(toHexString(_accountId));
        // // uint8 rType = uint8(_accountId % 10);
        // if ()
        // bytes memory rtnV = new bytes( (_orgCode.length > 5 ? _orgCode.length : 5) + 1);//abi.encodePacked(rType);
        // // rtnV[0] = toChar(rType);
        // // for(uint i = 0; i < 5; i++){
        // //     uint use_digit = rType > 4 ? (i + rType ) % 5 : (5 - i + rType) % 5;
        // //     rtnV[i+1] = use_digit >= _orgCode.length ? bytes1("0"): _orgCode[use_digit];
        // // }

        // for(uint i = 5; i < _orgCode.length; i++){
        //     rtnV[i+1] =  _orgCode[i];
        // }
        return string.concat(refPrefix, string(_orgCode));
    }

    function toHexString(uint a) public pure returns (string memory) {
        uint _count = 0;
        uint b = a;
        while (b != 0) {
            _count++;
            b /= 16;
        }
        bytes memory res = new bytes(_count);
        for (uint i=0; i<_count; ++i) {
            b = a % 36;
            res[_count - i - 1] = toChar(uint8(b));
            a /= 16;
        }
        return string(res);
    }
    function toChar(uint8 d) public pure returns (bytes1) {
        if (0 <= d && d <= 9) {
            return bytes1(uint8(bytes1('0')) + d);
        } else if (10 <= uint8(d) && uint8(d) <= 35) {
            return bytes1(uint8(bytes1('a')) + d - 10);
        }
        // revert("Invalid hex digit");
        revert();
    }
}


