// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MintableToken is ERC20, Ownable {
    mapping (address => bool) public isMinter;

    mapping(address => uint256) public maxMintAmount;
    mapping(address => uint256) public minted;

    modifier onlyMinter() {
        require(isMinter[msg.sender], "forbidden");
        _;
    }

    event SetMinter(address minter, bool status);
    event SetMinterMax(address minter, uint256 max);
    event Clear(address minter);

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    }
    
    function setMinter(address _minter, bool _isActive) external onlyOwner {
        isMinter[_minter] = _isActive;
        emit SetMinter(_minter, _isActive);
    }

    function setMaxMintAmount(address _minter, uint256 _max) external onlyOwner {
        maxMintAmount[_minter] = _max;
        emit SetMinterMax(_minter, _max);
    }

    function clear(address _minter) external onlyOwner {
        minted[_minter] = 0;
        emit Clear(_minter);
    }

    function mint(address _account, uint256 _amount) external onlyMinter {
        _mint(_account, _amount);
        minted[_account] += _amount;
        if (maxMintAmount[_account] > 0){
            require(minted[_account] < maxMintAmount[_account], "max mint limit");
        }
    }

    function burn(uint256 _amount) external  {
        _burn(msg.sender, _amount);
    }
}
