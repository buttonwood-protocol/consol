// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IForfeitedAssetsPoolErrors
 * @author @SocksNFlops
 * @notice Errors for the Forfeited Assets Pool
 */
interface IForfeitedAssetsPoolErrors {
  /**
   * @notice The asset is already supported.
   * @param asset The address of the asset that is already supported
   */
  error AssetAlreadySupported(address asset);

  /**
   * @notice The asset is not supported.
   * @param asset The address of the asset that is not supported
   */
  error AssetNotSupported(address asset);

  /**
   * @notice The redemption amount is greater than the foreclosed liabilities.
   * @param redemptionAmount The amount of assets that were redeemed
   * @param foreclosedLiabilities The value of the foreclosed liabilities
   */
  error RedemptionAmountGreaterThanForeclosedLiabilities(uint256 redemptionAmount, uint256 foreclosedLiabilities);
}
