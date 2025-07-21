// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IConsolEvents
 * @author SocksNFlops
 * @notice Interface for the Consol contract events.
 */
interface IConsolEvents {
  /**
   * @notice Emitted when a flash swap is made.
   * @param inputToken The input token
   * @param outputToken The output token
   * @param amount The amount of tokens swapped
   * @param actualAmount The amount of tokens returned
   */
  event FlashSwap(address indexed inputToken, address indexed outputToken, uint256 amount, uint256 actualAmount);
}
