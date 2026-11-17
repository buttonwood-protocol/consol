// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IGeneralManagerErrors} from "../interfaces/IGeneralManager/IGeneralManagerErrors.sol";
import {IGeneralManagerEvents} from "../interfaces/IGeneralManager/IGeneralManagerEvents.sol";
import {IOrderFulfillmentCallback} from "../interfaces/IOrderFulfillmentCallback.sol";
import {OriginationParameters} from "../types/orders/OriginationParameters.sol";
import {Constants} from "./Constants.sol";

/**
 * @title OriginationLogic
 * @author SocksNFlops
 * @notice Externally linked library holding the USDX payout logic of GeneralManager originations. Every function executes in the context of the GeneralManager.
 */
library OriginationLogic {
  using SafeERC20 for IERC20;

  /**
   * @notice Calculates the amount of USDX withheld from a fulfiller's advance until the end of the origination
   * @dev Leaves the GeneralManager the dust it spends rounding up each origination pool's Consol repayment
   * @param purchaseAmount The amount of USDX the fulfiller is paid for the order
   * @param originationPoolCount The number of origination pools the order borrows from
   * @return The amount of USDX withheld from the advance
   */
  function holdback(uint256 purchaseAmount, uint256 originationPoolCount) internal pure returns (uint256) {
    return Math.min(purchaseAmount, originationPoolCount * Constants.FULFILLMENT_HOLDBACK_PER_POOL);
  }

  /**
   * @notice Advances the fulfiller the order's purchase amount (less the holdback), calls back into the fulfiller, and validates that the requested collateral was delivered
   * @param usdx The address of the USDX token
   * @param data The origination callback data: abi.encode(OriginationParameters, uint256 index, bytes fulfillment), where fulfillment is abi.encode(uint256 collateralRequested, bytes fulfillerData)
   */
  function advance(address usdx, bytes calldata data) external {
    (OriginationParameters memory originationParameters,, bytes memory fulfillment) =
      abi.decode(data, (OriginationParameters, uint256, bytes));
    (uint256 collateralRequested, bytes memory fulfillerData) = abi.decode(fulfillment, (uint256, bytes));

    address collateral = originationParameters.mortgageParams.collateral;
    uint256 usdxAmount = originationParameters.purchaseAmount
      - holdback(originationParameters.purchaseAmount, originationParameters.originationPools.length);

    // Record the collateral balance before any USDX leaves, so the advance itself can never count as a delivery
    uint256 collateralBefore = IERC20(collateral).balanceOf(address(this));

    IERC20(usdx).safeTransfer(originationParameters.fulfiller, usdxAmount);

    IOrderFulfillmentCallback(originationParameters.fulfiller)
      .orderFulfillmentCallback(
        originationParameters.mortgageParams.tokenId, collateral, collateralRequested, usdxAmount, fulfillerData
      );

    uint256 collateralAfter = IERC20(collateral).balanceOf(address(this));
    if (collateralAfter < collateralBefore + collateralRequested) {
      revert IGeneralManagerErrors.InsufficientCollateralDelivered(
        collateralRequested, collateralAfter > collateralBefore ? collateralAfter - collateralBefore : 0
      );
    }
  }

  /**
   * @notice Sends the USDX left in the GeneralManager after an origination to the fulfiller and the fee recipient
   * @dev With no fee recipient set, the full balance goes to the fulfiller. Otherwise the fulfiller receives what it is still owed and the surplus (origination fee + rounding dust) goes to the fee recipient.
   * @param usdx The address of the USDX token
   * @param feeRecipient The address receiving protocol fees
   * @param fulfiller The address of the fulfiller
   * @param purchaseAmount The amount of USDX the fulfiller is paid for the order
   * @param advancedPoolCount Zero when the fulfiller has not been paid yet. Otherwise the number of origination pools of the order, whose fulfiller was advanced everything but the holdback.
   * @param tokenId The tokenId of the mortgage position being originated
   */
  function settle(
    address usdx,
    address feeRecipient,
    address fulfiller,
    uint256 purchaseAmount,
    uint256 advancedPoolCount,
    uint256 tokenId
  ) external {
    uint256 usdxBalance = IERC20(usdx).balanceOf(address(this));
    if (feeRecipient == address(0)) {
      IERC20(usdx).safeTransfer(fulfiller, usdxBalance);
    } else {
      uint256 fulfillerAmount =
        Math.min(usdxBalance, advancedPoolCount == 0 ? purchaseAmount : holdback(purchaseAmount, advancedPoolCount));
      IERC20(usdx).safeTransfer(fulfiller, fulfillerAmount);
      uint256 surplus = usdxBalance - fulfillerAmount;
      if (surplus > 0) {
        IERC20(usdx).safeTransfer(feeRecipient, surplus);
        emit IGeneralManagerEvents.OriginationFeeCollected(tokenId, feeRecipient, surplus);
      }
    }
  }
}
