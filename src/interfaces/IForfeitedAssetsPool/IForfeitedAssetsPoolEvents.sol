// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IForfeitedAssetsPoolEvents
 * @author @SocksNFlops
 * @notice Events for the Forfeited Assets Pool
 */
interface IForfeitedAssetsPoolEvents {
  /**
   * @notice An asset was added to the forfeited assets pool.
   * @param asset The address of the asset that was added
   */
  event AssetAdded(address asset);

  /**
   * @notice An asset was removed from the forfeited assets pool.
   * @param asset The address of the asset that was removed
   */
  event AssetRemoved(address asset);

  /**
   * @notice An asset was deposited into the forfeited assets pool.
   * @param asset The address of the asset that was deposited
   * @param amount The amount of the asset that was deposited
   * @param liability The liability to add to the foreclosed liabilities
   * @param foreclosedLiabilities The new value of the foreclosed liabilities
   */
  event AssetDeposited(address asset, uint256 amount, uint256 liability, uint256 foreclosedLiabilities);

  /**
   * @notice Assets were redeemed from the forfeited assets pool.
   * @param assets The addresses of the assets that were redeemed
   * @param amounts The amounts of the assets that were redeemed
   * @param liability The liability that was burned to redeem the assets
   * @param foreclosedLiabilities The new value of the foreclosed liabilities
   */
  event AssetsRedeemed(address[] assets, uint256[] amounts, uint256 liability, uint256 foreclosedLiabilities);
}
