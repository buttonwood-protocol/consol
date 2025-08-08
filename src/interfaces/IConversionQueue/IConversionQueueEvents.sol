// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IConversionQueueEvents
 * @author @SocksNFlops
 * @notice Events for the Conversion Queue contract
 */
interface IConversionQueueEvents {
  /**
   * @notice Emitted when the price multiplier in basis points is set
   * @param priceMultiplierBps The new price multiplier in basis points
   */
  event PriceMultiplierBpsSet(uint256 priceMultiplierBps);
  /**
   * @notice Emitted when a mortgage is enqueued into the conversion queue
   * @param tokenId The tokenId of the mortgage
   * @param isCompounding Whether the mortgage is a compounding mortgage
   */
  event MortgageEnqueued(uint256 tokenId, bool isCompounding);
}
