// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IMortgageQueueErrors
 * @author @SocksNFlops
 * @notice Errors for the Mortgage Queue contract.
 */
interface IMortgageQueueErrors {
  /**
   * @notice Thrown when trying to insert a tokenId that is 0.
   */
  error TokenIdIsZero();

  /**
   * @notice Thrown when trying to insert a tokenId that is already in the queue.
   * @param tokenId The tokenId that is already in the queue.
   */
  error TokenIdAlreadyInQueue(uint256 tokenId);

  /**
   * @notice Thrown when trying to insert with a hintPrevId that does not correspond to a mortgage position in the queue.
   * @param hintPrevId The hintPrevId that was not found in the queue.
   */
  error HintPrevIdNotFound(uint256 hintPrevId);

  /**
   * @notice Thrown when trying to insert with a hintPrevId that has a higher trigger price than the tokenId.
   * @param hintPrevId The hintPrevId that has a higher trigger price than the tokenId.
   */
  error HintPrevIdTooHigh(uint256 hintPrevId);

  /**
   * @notice Thrown when trying to remove a tokenId that is not in the queue.
   * @param tokenId The tokenId that is not in the queue.
   */
  error TokenIdNotInQueue(uint256 tokenId);

  /**
   * @notice Thrown when trying to insert with a gas fee that is less than the mortgage gas fee.
   * @param mortgageGasFee The mortgage gas fee.
   * @param gasFee The gas fee that was provided.
   */
  error InsufficientMortgageGasFee(uint256 mortgageGasFee, uint256 gasFee);
}
