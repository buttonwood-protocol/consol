// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MortgageParams} from "../orders/MortgageParams.sol";

/**
 * @notice The parameters for originating a mortgage creation or balance sheet expansion
 * @param mortgageParams The parameters for the mortgage
 * @param fulfiller The address of the fulfiller
 * @param originationPool The address of the origination pool
 * @param conversionQueue The address of the conversion queue
 * @param hintPrevId The hintPrevId of the mortgage
 * @param expansion Whether the mortgage is a balance sheet expansion of an existing position
 * @param purchaseAmount The amount of USDX to purchase
 */
struct OriginationParameters {
  MortgageParams mortgageParams;
  address fulfiller;
  address originationPool;
  address conversionQueue;
  uint256 hintPrevId;
  bool expansion;
  uint256 purchaseAmount;
}
