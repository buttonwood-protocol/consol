// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IPausableErrors
 * @author @SocksNFlops
 * @notice Errors for the pausable contract
 */
interface IPausableErrors {
  /**
   * @notice Error for paused pool
   */
  error Paused();
}
