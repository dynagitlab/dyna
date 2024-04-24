// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.2;

enum YieldMode {
    AUTOMATIC,
    VOID,
    CLAIMABLE
}


interface IBlast{
    // // configure
    // function configureContract(address contractAddress, YieldMode _yield, GasMode gasMode, address governor) external;
    // function configure(YieldMode _yield, GasMode gasMode, address governor) external;

    // // base configuration options
    // function configureClaimableYield() external;
    // function configureClaimableYieldOnBehalf(address contractAddress) external;
    // function configureAutomaticYield() external;
    // function configureAutomaticYieldOnBehalf(address contractAddress) external;
    // function configureVoidYield() external;
    // function configureVoidYieldOnBehalf(address contractAddress) external;
    function configureClaimableGas() external;
    // function configureClaimableGasOnBehalf(address contractAddress) external;
    // function configureVoidGas() external;
    // function configureVoidGasOnBehalf(address contractAddress) external;
    function configureGovernor(address _governor) external;
    // function configureGovernorOnBehalf(address _newGovernor, address contractAddress) external;

}

interface IWETHUSDBRebasing {
    function configure(YieldMode) external returns (uint256);
    function claim(address recipient, uint256 amount) external returns (uint256);
}


abstract contract BlastBase {
    
    address public yieldManager;
    IBlast public constant IBLAST = IBlast(0x4300000000000000000000000000000000000002);
    address public constant usdb = 0x4300000000000000000000000000000000000003;
    address public constant bweth = 0x4300000000000000000000000000000000000004;

    constructor() {
            // IWETHUSDBRebasing(usdb).configure(YieldMode.CLAIMABLE);
            // IWETHUSDBRebasing(bweth).configure(YieldMode.CLAIMABLE);
            // IBlast.configureClaimableGas();
		    // IBlast.configureGovernor(msg.sender);
            yieldManager = msg.sender;
    }
    function transManage(address _new) external{
        require(msg.sender == yieldManager);
        yieldManager = _new;
    }

    function claimUSDB(address _recipient, uint256 _amount) external {
        require(msg.sender == yieldManager);
        IWETHUSDBRebasing(usdb).claim(_recipient, _amount);
    }
    function claimWETH(address _recipient, uint256 _amount) external {
        require(msg.sender == yieldManager);
        IWETHUSDBRebasing(bweth).claim(_recipient, _amount);
    }
}