// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @notice The parameters for creating a mortgage position
 * @param owner The address of the owner of the mortgage
 * @param tokenId The tokenId of the mortgage NFT
 * @param collateral The address of the collateral token
 * @param collateralDecimals The decimals of the collateral token
 * @param collateralAmount The amount of collateral escrowed in the Consol contract
 * @param subConsol The address of the SubConsol contract holding the collateral
 * @param interestRate The interest rate of the mortgage
 * @param amountBorrowed The amount being borrowed
 * @param totalPeriods The total umber of periods that the mortgage will last
 * @param hasPaymentPlan Whether the mortgage is hasPaymentPlan (periodic payment plan vs single payment)
 */
struct MortgageParams {
  address owner;
  uint256 tokenId;
  address collateral;
  uint8 collateralDecimals;
  uint256 collateralAmount;
  address subConsol;
  uint16 interestRate;
  uint256 amountBorrowed;
  uint8 totalPeriods;
  bool hasPaymentPlan;
}
