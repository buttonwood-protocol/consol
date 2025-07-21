// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IUSDXEvents {
  /**
   * @notice Emitted when a new token is added to the MultiTokenVault
   * @param token The address of the token that was added
   * @param numerator The numerator for the token
   * @param denominator The denominator for the token
   */
  event TokenScalarsAdded(address indexed token, uint256 numerator, uint256 denominator);
}
