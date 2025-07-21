// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IConsolFlashSwap
 * @author SocksNFlops
 * @notice Any contract that calls IConsol#flashSwap must implement this interface
 */
interface IConsolFlashSwap {
  /**
   * @notice Thrown when a non-Consol contract attempts to call IConsolFlashSwap#flashSwapCallback
   * @param caller The address of the caller
   * @param consol The address of the Consol contract
   */
  error OnlyConsol(address caller, address consol);

  /**
   * @notice Called to `msg.sender` after transferring to the recipient from IConsol#flashSwap.
   * @dev In the implementation you must repay the inputTokens sent in the outputToken currency
   * @param inputToken The address of the input token
   * @param outputToken The address of the output token
   * @param amount The amount of tokens to swap
   * @param data The data to pass into the callback
   */
  function flashSwapCallback(address inputToken, address outputToken, uint256 amount, bytes calldata data) external;
}
