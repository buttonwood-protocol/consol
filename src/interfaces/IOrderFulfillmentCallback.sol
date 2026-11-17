// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IOrderFulfillmentCallback
 * @author SocksNFlops
 * @notice Any fulfiller that processes orders through IOrderPool#processOrdersWithCallback must implement this interface
 */
interface IOrderFulfillmentCallback {
  /**
   * @notice Called by the GeneralManager on the fulfiller after advancing it USDX for an order.
   * @dev The implementation must transfer at least `collateralAmount` of `collateral` to `msg.sender` before returning. Must validate that `msg.sender` is the GeneralManager.
   * @param tokenId The tokenId of the mortgage position being originated
   * @param collateral The address of the collateral token to deliver
   * @param collateralAmount The amount of collateral to deliver to the GeneralManager
   * @param usdxAmount The amount of USDX advanced to the fulfiller before this call
   * @param data Any data passed through by the fulfiller via the IOrderPool#processOrdersWithCallback call
   */
  function orderFulfillmentCallback(
    uint256 tokenId,
    address collateral,
    uint256 collateralAmount,
    uint256 usdxAmount,
    bytes calldata data
  ) external;
}
