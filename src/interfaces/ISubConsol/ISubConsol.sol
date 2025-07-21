// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISubConsolEvents} from "./ISubConsolEvents.sol";

/**
 * @title ISubConsol
 * @author Socks&Flops
 * @notice Interface for the SubConsol contract. This is meant to hold collateral and mint an input into Consol
 */
interface ISubConsol is IERC20, ISubConsolEvents {
  /**
   * @notice Get the collateral token
   * @return The address of the collateral token
   */
  function collateral() external view returns (address);

  /**
   * @notice Set the yield strategy
   * @param yieldStrategy_ The address of the yield strategy
   */
  function setYieldStrategy(address yieldStrategy_) external;

  /**
   * @notice Get the yield strategy
   * @return The address of the yield strategy
   */
  function yieldStrategy() external view returns (address);

  /**
   * @notice Deposit collateral into the Consol contract while minting a specified amount of SubConsol
   * @param collateralAmount The amount of collateral to deposit
   * @param mintAmount The amount of SubConsol to mint
   */
  function depositCollateral(uint256 collateralAmount, uint256 mintAmount) external;

  /**
   * @notice Withdraw collateral from the Consol contract while burning a specified amount of SubConsol
   * @param to The address to send the collateral to
   * @param collateralAmount The amount of collateral to withdraw
   * @param burnAmount The amount of SubConsol to burn
   */
  function withdrawCollateral(address to, uint256 collateralAmount, uint256 burnAmount) external;

  /**
   * @notice Withdraw collateral from the SubConsol contract asynchronously (from the yield strategy if necessary)
   * @param to The address to send the collateral to
   * @param collateralAmount The amount of collateral to withdraw
   * @param burnAmount The amount of SubConsol to burn
   */
  function withdrawCollateralAsync(address to, uint256 collateralAmount, uint256 burnAmount) external;

  /**
   * @notice Get the amount of yield in the yield strategy
   * @return The amount of yield in the yield strategy
   */
  function yieldAmount() external view returns (uint256);

  /**
   * @notice Deposit collateral into the yield strategy
   * @param collateralAmount The amount of collateral to deposit
   */
  function depositToYieldStrategy(uint256 collateralAmount) external;

  /**
   * @notice Withdraw collateral from the yield strategy
   * @param collateralAmount The amount of collateral to withdraw
   */
  function withdrawFromYieldStrategy(uint256 collateralAmount) external;
}
