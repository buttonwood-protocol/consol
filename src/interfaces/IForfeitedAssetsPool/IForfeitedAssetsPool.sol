// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IForfeitedAssetsPoolEvents} from "./IForfeitedAssetsPoolEvents.sol";
import {IForfeitedAssetsPoolErrors} from "./IForfeitedAssetsPoolErrors.sol";
import {IPausable} from "../IPausable/IPausable.sol";

/**
 * @title IForfeitedAssetsPool
 * @author @SocksNFlops
 * @notice Interface for the Forfeited Assets Pool contract, a contract that holds assets seized from foreclosed mortgages. They can be purchased for Consol that is burned in exchange.
 */
interface IForfeitedAssetsPool is IERC20, IPausable, IForfeitedAssetsPoolEvents, IForfeitedAssetsPoolErrors {
  /**
   * @notice Add an asset to the forfeited assets pool. Only callable by admin role.
   * @param asset The address of the asset to add
   */
  function addAsset(address asset) external;

  /**
   * @notice Remove an asset from the forfeited assets pool. Only callable by admin role.
   * @param asset The address of the asset to remove
   */
  function removeAsset(address asset) external;

  /**
   * @notice Get the list of assets in the forfeited assets pool
   * @param index The index of the asset to get
   * @return The address of the asset at the given index
   */
  function getAsset(uint256 index) external view returns (address);

  /**
   * @notice Get the total amount of assets in the forfeited assets pool
   * @return The total amount of assets in the forfeited assets pool
   */
  function totalAssets() external view returns (uint256);

  /**
   * @notice Deposits an asset into the forfeited assets pool and updates the foreclosed liabilities. Only callable by permissioned depositors.
   * @param asset The address of the asset to deposit
   * @param amount The amount of the asset to deposit
   * @param liability The liability to add to the foreclosed liabilities
   */
  function depositAsset(address asset, uint256 amount, uint256 liability) external;

  /**
   * @notice Purchase assets from the forfeited assets pool in proportion to the amount of Consol burned. redemptionPercentage = (amount / foreclosedLiabilities)
   * @param receiver The address to send the assets to
   * @param liability The amount of liabilities to burn in order to purchase assets from the forfeited assets pool.
   * @return redeemedAssets The list of assets purchased
   * @return redeemedAmounts The amount of assets purchased
   */
  function burn(address receiver, uint256 liability)
    external
    returns (address[] memory redeemedAssets, uint256[] memory redeemedAmounts);
}
