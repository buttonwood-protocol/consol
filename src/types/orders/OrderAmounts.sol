// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @notice The order amounts for a purchase order
 * @param purchaseAmount The amount of USDX to purchase
 * @param collateralCollected The amount of collateral collected
 * @param usdxCollected The amount of USDX collected
 */
struct OrderAmounts {
  uint256 purchaseAmount;
  uint256 collateralCollected;
  uint256 usdxCollected;
}
