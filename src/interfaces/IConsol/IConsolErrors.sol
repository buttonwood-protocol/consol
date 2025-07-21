// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IConsolErrors
 * @author SocksNFlops
 * @notice Interface for the Consol errors.
 */
interface IConsolErrors {
  /**
   * @notice Forfeited assets pool is not set.
   */
  error ForfeitedAssetsPoolNotSet();

  /**
   * @notice Insufficient tokens returned.
   * @param amount The amount of tokens that were expected to be returned
   * @param actualAmount The amount of tokens that were returned
   */
  error InsufficientTokensReturned(uint256 amount, uint256 actualAmount);
}
