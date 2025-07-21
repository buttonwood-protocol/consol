// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPausableErrors} from "./IPausableErrors.sol";

/**
 * @title IPausable
 * @author @SocksNFlops
 * @notice Interface for the pausable contract
 */
interface IPausable is IPausableErrors {
  /**
   * @notice Pause or unpause the contract
   * @param pause The new paused state
   */
  function setPaused(bool pause) external;

  /**
   * @notice Get the paused state of the contract
   * @return The paused state of the contract
   */
  function paused() external view returns (bool);
}
