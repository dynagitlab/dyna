// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../utils/EnumerableValues.sol";

library VaultMSData {
    // bytes32 public constant opeProtectIdx = keccak256("opeProtectIdx");
    // using EnumerableSet for EnumerableSet.UintSet;
    // using EnumerableValues for EnumerableSet.UintSet;

    uint256 constant COM_RATE_PRECISION = 10**4; //for common rate(leverage, etc.) and hourly rate
    uint256 constant HOUR_RATE_PRECISION = 10**6; //for common rate(leverage, etc.) and hourly rate
    uint256 constant PRC_RATE_PRECISION = 10**10;   //for precise rate  secondly rate
    uint256 constant PRICE_PRECISION = 10**30;

    struct Position {
        address account;
        address collateralToken;
        address indexToken;

        uint256 sizeUSD;           //in USD
        uint256 collateralUSD;     // in USD

        uint128 reserveAmount;
        uint128 colInAmount;

        uint128 entryFundingRateSec;
        uint32 aveIncreaseTime;
        bool isLong;

        int256 realisedPnl;
        uint256 averagePrice;

    }


    struct TokenBase {
        //Setable parts
        bool isSwappable;
        bool isFundable;
        bool isStable;
        bool isTradable;
        uint8 decimal;
        uint16 weight;  //tokenWeights allows customisation of index composition
        // uint128 maxUSDAmounts;  // maxUSDAmounts allows setting a max amount of USDX debt for a token

        uint32 latestUpdateTime;
        uint64 fundingRatePerSec; //borrow fee & token util
        
        uint128 accumulativefundingRateSec;
    }


    // struct TradingFee {
    //     uint256 fundingRatePerSec; //borrow fee & token util

    //     uint256 accumulativefundingRateSec;

    //     // int256 longRatePerSec;  //according to position
    //     // int256 shortRatePerSec; //according to position
    //     // int256 accumulativeLongRateSec;
    //     // int256 accumulativeShortRateSec;

    //     // uint256 lastFundingTimes;     // lastFundingTimes tracks the last time funding was updated for a token
    //     // uint256 cumulativeFundingRates;// cumulativeFundingRates tracks the funding rates based on utilization
    //     // uint256 cumulativeLongFundingRates;
    //     // uint256 cumulativeShortFundingRates;
    // }

    struct TradingTax {
        uint256 taxMax;
        uint256 taxDuration;
        uint256 k;
    }

    struct TradingLimit {
        uint256 maxShortSize;
        uint256 maxLongSize;
        uint256 maxTradingSize;

        uint256 maxRatio;
        uint256 countMinSize;
        //Price Impact
    }


    struct TradingRec {
        uint256 shortSize;
        uint256 shortAveragePrice;
        uint256 longSize;
        uint256 longAveragePrice;
    }

}