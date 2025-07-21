// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @notice The phases of the Origination Pool
 */
enum OriginationPoolPhase {
  /// @notice Lenders can deposit funds into the pool to provide liquidity for mortgage origination
  DEPOSIT,
  /// @notice Pool funds are actively deployed for mortgage origination and new deposits/withdrawals are disabled
  DEPLOY,
  /// @notice Lenders can redeem their funds from the pool along with earned fees from mortgage originations
  REDEMPTION
}
