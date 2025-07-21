// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OriginationPoolPhase} from "../../types/enums/OriginationPoolPhase.sol";

/**
 * @title IOriginationPoolErrors
 * @author SocksNFlops
 * @notice Errors for the OriginationPool contract
 */
interface IOriginationPoolErrors {
  /**
   * @notice Error for incorrect phase
   * @param requiredPhase The required phase
   * @param currentPhase The current phase
   */
  error IncorrectPhase(OriginationPoolPhase requiredPhase, OriginationPoolPhase currentPhase);

  /**
   * @notice Error for pool limit exceeded
   * @param poolLimit The pool limit
   * @param amount The amount
   */
  error PoolLimitExceeded(uint256 poolLimit, uint256 amount);

  /**
   * @notice Error for insufficient consol returned
   * @param requiredAmount The required amount
   * @param amountReturned The amount returned
   */
  error InsufficientConsolReturned(uint256 requiredAmount, uint256 amountReturned);

  /**
   * @notice Error for insufficient amount passed to a function
   * @param amount The amount
   * @param minimumAmount The minimum amount
   */
  error InsufficientAmount(uint256 amount, uint256 minimumAmount);
}
