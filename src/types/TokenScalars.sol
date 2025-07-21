// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @notice Scalar information for a token
 * @param numerator The numerator for the token
 * @param denominator The denominator for the token
 */
struct TokenScalars {
  uint256 numerator;
  uint256 denominator;
}
