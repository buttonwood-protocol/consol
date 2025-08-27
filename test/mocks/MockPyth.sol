// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PythStructs} from "@pythnetwork/PythStructs.sol";

/**
 * @title MockPyth
 * @author SocksNFlops
 * @notice A mock implementation of the Pyth interface (only getPriceNoOlderThan is implemented)
 */
contract MockPyth {
  /// @notice A mapping of price ids to prices
  mapping(bytes32 => PythStructs.Price) prices;

  /**
   * @notice Set the price for a given price id
   * @param priceId The price id to set the price for
   * @param price The price to set
   * @param conf The confidence interval around the price
   * @param expo The price exponent
   * @param publishTime The unix timestamp describing when the price was published
   */
  function setPrice(bytes32 priceId, int64 price, uint64 conf, int32 expo, uint256 publishTime) external {
    prices[priceId] = PythStructs.Price({price: price, conf: conf, expo: expo, publishTime: publishTime});
  }

  function getPriceNoOlderThan(bytes32 priceId, uint256) external view returns (PythStructs.Price memory price) {
    price = prices[priceId];
  }

  /// @notice Returns the required fee to update an array of price updates.
  /// @param updateData Array of price update data.
  /// @return feeAmount The required fee in Wei.
  function getUpdateFee(bytes[] calldata updateData) external view returns (uint256 feeAmount) {
    return 0.01e18;
  }
}
