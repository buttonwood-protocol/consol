// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MortgageStatus} from "../../types/MortgagePosition.sol";

/**
 * @title ILoanManagerErrors
 * @author Socks&Flops
 * @notice Interface for all errors in the LoanManager contract
 */
interface ILoanManagerErrors {
  /**
   * @notice Thrown when a non-general manager attempts to call an operation that requires general manager access
   * @param caller The address of the caller
   * @param generalManager The address of the general manager
   */
  error OnlyGeneralManager(address caller, address generalManager);

  /**
   * @notice Thrown when the amount borrowed is below the minimum threshold
   * @param amountBorrowed The amount borrowed
   * @param minAmountBorrowed The minimum amount borrowed
   */
  error AmountBorrowedBelowMinimum(uint256 amountBorrowed, uint256 minAmountBorrowed);

  /**
   * @notice Thrown when a mortgage position does not exist
   * @param tokenId The tokenId of the mortgage
   */
  error MortgagePositionDoesNotExist(uint256 tokenId);

  /**
   * @notice Thrown when a mortgage position is not active
   * @param tokenId The tokenId of the mortgage
   * @param status The status of the mortgage
   */
  error MortgagePositionNotActive(uint256 tokenId, MortgageStatus status);

  /**
   * @notice Thrown when a non-mortgage owner attempts to call an operation that requires ownership
   * @param tokenId The tokenId of the mortgage
   * @param owner The owner of the mortgage
   * @param caller The caller of the function
   */
  error OnlyMortgageOwner(uint256 tokenId, address owner, address caller);
}
