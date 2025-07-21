// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title ISubConsolEvents
 * @author Socks&Flops
 * @notice Interface for the SubConsolEvents.
 */
interface ISubConsolEvents {
  /**
   * @notice Emitted when collateral is deposited into the SubConsol contract
   * @param account The address of the account that deposited
   * @param collateralAmount The amount of collateral deposited
   * @param mintAmount The amount of subconsol minted
   */
  event Deposit(address indexed account, uint256 collateralAmount, uint256 mintAmount);

  /**
   * @notice Emitted when collateral is withdrawn from the SubConsol contract
   * @param account The address of the account that withdrew
   * @param collateralAmount The amount of collateral withdrawn
   * @param burnAmount The amount of subconsol burned
   */
  event Withdraw(address indexed account, uint256 collateralAmount, uint256 burnAmount);

  /**
   * @notice Emitted when the yield strategy is set
   * @param yieldStrategy The address of the yield strategy
   */
  event YieldStrategySet(address indexed yieldStrategy);

  /**
   * @notice Emitted when the yield amount is updated
   * @param yieldAmount The amount of yield in the yield strategy
   */
  event YieldAmountUpdated(uint256 yieldAmount);
}
