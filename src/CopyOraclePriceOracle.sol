// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ICopyOracle} from "./interfaces/ICopyOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title CopyOraclePriceOracle
 * @author SocksNFlops
 * @notice The CopyOraclePriceOracle contract tracks the price of a given asset by reading a feed from a CopyOracle
 * store, to determine the trigger price for conversions.
 */
contract CopyOraclePriceOracle is IPriceOracle {
  /**
   * @notice The number of decimals for USD
   * @return USD_DECIMALS The number of decimals for USD
   */
  uint8 public constant USD_DECIMALS = 18;
  /**
   * @notice The number of decimals the store must report for its prices
   * @return PRICE_DECIMALS The number of decimals the store must report for its prices
   */
  uint8 public constant PRICE_DECIMALS = 8;

  /**
   * @notice The CopyOracle store
   * @return copyOracle The CopyOracle store
   */
  ICopyOracle public immutable copyOracle;
  /**
   * @notice The id of the tracked feed
   * @return feedId The id of the tracked feed
   */
  bytes32 public immutable feedId;
  /**
   * @notice The maximum age of a price in seconds
   * @return maxAge The maximum age of a price in seconds
   */
  uint256 public immutable maxAge;
  /**
   * @inheritdoc IPriceOracle
   */
  uint8 public immutable collateralDecimals;
  /**
   * @notice The multiplier that scales a stored price to USD (18 decimals)
   * @return priceScale The multiplier that scales a stored price to USD (18 decimals)
   */
  uint256 public immutable priceScale;

  /**
   * @notice The error thrown when the store does not report PRICE_DECIMALS decimals
   * @param decimals The decimals reported by the store
   */
  error InvalidDecimals(uint8 decimals);
  /**
   * @notice The error thrown when the age of a price is greater than the maximum age
   * @param age The age of the price
   * @param maxAge The maximum age
   */
  error StalePrice(uint256 age, uint256 maxAge);
  /**
   * @notice The error thrown when the stored price is not positive
   * @param answer The stored price
   */
  error InvalidAnswer(int256 answer);

  /**
   * @notice Constructor
   * @param copyOracle_ The address of the CopyOracle store
   * @param feedId_ The id of the tracked feed
   * @param collateralDecimals_ The number of decimals for the collateral
   * @param maxAge_ The maximum age of a price in seconds
   */
  constructor(address copyOracle_, bytes32 feedId_, uint8 collateralDecimals_, uint256 maxAge_) {
    ICopyOracle store = ICopyOracle(copyOracle_);
    uint8 decimals = store.decimals();
    if (decimals != PRICE_DECIMALS) {
      revert InvalidDecimals(decimals);
    }
    copyOracle = store;
    feedId = feedId_;
    collateralDecimals = collateralDecimals_;
    maxAge = maxAge_;
    priceScale = 10 ** (USD_DECIMALS - PRICE_DECIMALS);
  }

  /**
   * @inheritdoc IPriceOracle
   */
  function price() public view override returns (uint256 assetPrice) {
    (int256 answer, uint256 updatedAt) = copyOracle.latestRoundData(feedId);

    // Validate the price is recent
    uint256 age = block.timestamp - updatedAt;
    if (age > maxAge) {
      revert StalePrice(age, maxAge);
    }
    if (answer <= 0) {
      revert InvalidAnswer(answer);
    }
    assetPrice = uint256(answer) * priceScale;
  }

  /**
   * @inheritdoc IPriceOracle
   */
  function cost(uint256 collateralAmount) public view override returns (uint256 totalCost, uint8 _collateralDecimals) {
    totalCost = Math.mulDiv(collateralAmount, price(), (10 ** collateralDecimals));
    _collateralDecimals = collateralDecimals;
  }
}
