// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IMortgageQueue} from "../IMortgageQueue/IMortgageQueue.sol";
import {ILenderQueue} from "../ILenderQueue/ILenderQueue.sol";
import {IConversionQueueEvents} from "./IConversionQueueEvents.sol";
import {IConversionQueueErrors} from "./IConversionQueueErrors.sol";
import {IPausable} from "../IPausable/IPausable.sol";

/**
 * @title IConversionQueue
 * @author @SocksNFlops
 * @notice Interface for the Conversion Queue contract. Maintains a priority queue of MortgagePositions sorted by trigger price, as well as a lender queue of withdrawals.
 */
interface IConversionQueue is IMortgageQueue, ILenderQueue, IPausable, IConversionQueueEvents, IConversionQueueErrors {
  /**
   * @notice Get the GeneralManager contract.
   * @return The address of the GeneralManager contract
   */
  function generalManager() external view returns (address);

  /**
   * @notice The number of decimals of the collateral
   * @return The number of decimals of the collateral
   */
  function decimals() external view returns (uint8);

  /**
   * @notice The address of the SubConsol contract
   * @return The address of the SubConsol contract
   */
  function subConsol() external view returns (address);

  /**
   * @notice The lump sum interest rate in basis points
   * @return The lump sum interest rate in basis points
   */
  function lumpSumInterestRateBps() external view returns (uint16);

  /**
   * @notice Sets the lump sum interest rate in basis points
   * @param lumpSumInterestRateBps_ The lump sum interest rate in basis points
   */
  function setLumpSumInterestRateBps(uint16 lumpSumInterestRateBps_) external;

  /**
   * @notice The lump sum interest rate in basis points for a mortgage with a payment plan
   * @return The lump sum interest rate in basis points for a mortgage with a payment plan
   */
  function paymentPlanLumpSumInterestRateBps() external view returns (uint16);

  /**
   * @notice Sets the lump sum interest rate in basis points for a mortgage with a payment plan
   * @param paymentPlanLumpSumInterestRateBps_ The lump sum interest rate in basis points for a mortgage with a payment plan
   */
  function setPaymentPlanLumpSumInterestRateBps(uint16 paymentPlanLumpSumInterestRateBps_) external;

  /**
   * @notice Sets the price multiplier for calculating the conversion price of a mortgage position in basis points
   * @param priceMultiplierBps_ The price multiplier in basis points
   */
  function setPriceMultiplierBps(uint256 priceMultiplierBps_) external;

  /**
   * @notice The price multiplier for calculating the conversion price of a mortgage position in basis points
   * @return The price multiplier in basis points
   */
  function priceMultiplierBps() external view returns (uint256);

  /**
   * @notice The current conversion price of the collateral in USD
   * @return The price of the collateral in USD
   */
  function conversionPrice() external view returns (uint256);

  /**
   * @notice Enqueues a mortgage position into the conversion queue
   * @param mortgageTokenId The tokenId of the mortgage position
   * @param hintPrevId The hintPrevId of the mortgage position
   * @param reenqueue If true, the mortgage position is already enqueued and the trigger price will be updated
   */
  function enqueueMortgage(uint256 mortgageTokenId, uint256 hintPrevId, bool reenqueue) external payable;

  /**
   * @notice Dequeues a mortgage position from the conversion queue. Only callable on an inactive mortgage position.
   * @param mortgageTokenId The tokenId of the mortgage position
   */
  function dequeueMortgage(uint256 mortgageTokenId) external;
}
