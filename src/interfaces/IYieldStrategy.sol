// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IYieldStrategy
 * @author @SocksNFlops
 * @notice Interface for the yield strategy used inside of SubConsol
 */
interface IYieldStrategy {
  /**
   * @notice Get the associated SubConsol contract address
   * @return The address of the SubConsol contract
   */
  function subConsol() external view returns (address);

  /**
   * @notice Deposit collateral into the yield strategy
   * @param from The address to send the collateral from
   * @param amount The amount of collateral to deposit
   */
  function deposit(address from, uint256 amount) external;

  /**
   * @notice Withdraw yield from the yield strategy. May happen asynchronously.
   * @param to The address to send the yield to
   * @param amount The amount of yield to withdraw
   */
  function withdraw(address to, uint256 amount) external;
}
