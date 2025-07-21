// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @notice The status of a mortgage position
 */
enum MortgageStatus {
  /// @notice Mortgage is active and operational, with payments being made according to the payment plan
  ACTIVE,
  /// @notice Mortgage has been foreclosed due to excessive missed payments
  FORECLOSED,
  /// @notice Mortgage has been fully paid off and redeemed by the borrower, with collateral returned
  REDEEMED
}
