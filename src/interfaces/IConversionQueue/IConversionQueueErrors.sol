// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IConversionQueueErrors
 * @author @SocksNFlops
 * @notice Errors for the Conversion Queue.
 */
interface IConversionQueueErrors {
  /**
   * @notice Thrown when the caller is not the general manager
   * @param caller The caller of the function
   */
  error OnlyGeneralManager(address caller);

  /**
   * @notice Thrown when trying to dequeue an active mortgage position
   * @param mortgageTokenId The tokenId of the mortgage position
   */
  error OnlyInactiveMortgage(uint256 mortgageTokenId);
}
