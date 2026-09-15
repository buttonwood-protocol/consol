// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {AggregatorV3Interface} from "./external/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ChainlinkPriceOracle
 * @author SocksNFlops
 * @notice The ChainlinkPriceOracle contract tracks the price of a given asset by reading a Chainlink
 * AggregatorV3Interface feed, to determine the trigger price for conversions.
 * @dev Equity feeds freeze outside market hours with no heartbeat, so readings well over a day old are normal on
 * weekends and holidays; size maxAge accordingly.
 */
contract ChainlinkPriceOracle is IPriceOracle {
  /**
   * @notice The number of decimals for USD
   * @return USD_DECIMALS The number of decimals for USD
   */
  uint8 public constant USD_DECIMALS = 18;

  /**
   * @notice The Chainlink aggregator feed
   * @return aggregator The Chainlink aggregator feed
   */
  AggregatorV3Interface public immutable aggregator;
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
   * @notice The number of decimals the feed reports for its prices
   * @return feedDecimals The number of decimals the feed reports for its prices
   */
  uint8 public immutable feedDecimals;
  /**
   * @notice The multiplier that scales a feed price to USD (18 decimals)
   * @return priceScale The multiplier that scales a feed price to USD (18 decimals)
   */
  uint256 public immutable priceScale;

  /**
   * @notice The error thrown when the feed reports more than USD_DECIMALS decimals
   * @param decimals The decimals reported by the feed
   */
  error InvalidDecimals(uint8 decimals);
  /**
   * @notice The error thrown when the latest round has not been completed
   * @param roundId The id of the incomplete round
   */
  error IncompleteRound(uint80 roundId);
  /**
   * @notice The error thrown when the age of a price is greater than the maximum age
   * @param age The age of the price
   * @param maxAge The maximum age
   */
  error StalePrice(uint256 age, uint256 maxAge);
  /**
   * @notice The error thrown when the feed price is not positive
   * @param answer The feed price
   */
  error InvalidAnswer(int256 answer);

  /**
   * @notice Constructor
   * @param aggregator_ The address of the Chainlink aggregator feed
   * @param collateralDecimals_ The number of decimals for the collateral
   * @param maxAge_ The maximum age of a price in seconds
   */
  constructor(address aggregator_, uint8 collateralDecimals_, uint256 maxAge_) {
    AggregatorV3Interface feed = AggregatorV3Interface(aggregator_);
    uint8 decimals = feed.decimals();
    if (decimals > USD_DECIMALS) {
      revert InvalidDecimals(decimals);
    }
    aggregator = feed;
    collateralDecimals = collateralDecimals_;
    maxAge = maxAge_;
    feedDecimals = decimals;
    priceScale = 10 ** (USD_DECIMALS - decimals);
  }

  /**
   * @inheritdoc IPriceOracle
   */
  function price() public view override returns (uint256 assetPrice) {
    (uint80 roundId, int256 answer,, uint256 updatedAt,) = aggregator.latestRoundData();

    // Validate the round is complete
    if (updatedAt == 0) {
      revert IncompleteRound(roundId);
    }
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
