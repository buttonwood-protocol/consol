// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IMultiTokenVault} from "../IMultiTokenVault/IMultiTokenVault.sol";
import {IConsolErrors} from "./IConsolErrors.sol";
import {IConsolEvents} from "./IConsolEvents.sol";

/**
 * @title IConsol
 * @author SocksNFlops
 * @notice Interface for the Consol contract. A wrapper token for USDX and SubConsol tokens.
 */
interface IConsol is IMultiTokenVault, IConsolErrors, IConsolEvents {
  /**
   * @notice Get the address of the forfeited assets pool.
   * @return The address of the forfeited assets pool
   */
  function forfeitedAssetsPool() external view returns (address);

  /**
   * @notice Set the address of the forfeited assets pool.
   * @param forfeitedAssetsPool_ The address of the forfeited assets pool
   */
  function setForfeitedAssetsPool(address forfeitedAssetsPool_) external;

  /**
   * @notice Flash swap tokens. Caller must implement the IConsolFlashSwap interface.
   * @param inputToken The address of the input token
   * @param outputToken The address of the output token
   * @param amount The amount of tokens to swap
   * @param data The data to pass into the callback
   */
  function flashSwap(address inputToken, address outputToken, uint256 amount, bytes calldata data) external;
}
