// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOriginationPoolEvents} from "./IOriginationPoolEvents.sol";
import {IOriginationPoolErrors} from "./IOriginationPoolErrors.sol";
import {IPausable} from "../IPausable/IPausable.sol";
import {OriginationPoolPhase} from "../../types/enums/OriginationPoolPhase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Interface for the OriginationPool contract
 */
interface IOriginationPool is IOriginationPoolEvents, IOriginationPoolErrors, IPausable, IERC20 {
  /**
   * @notice The USDX token address
   * @return The usdx address
   */
  function usdx() external view returns (address);

  /**
   * @notice The Consol token address
   * @return The consol address
   */
  function consol() external view returns (address);

  /**
   * @notice The deposit phase timestamp
   * @return The deposit phase timestamp
   */
  function depositPhaseTimestamp() external view returns (uint256);

  /**
   * @notice The deploy phase timestamp
   * @return The deploy phase timestamp
   */
  function deployPhaseTimestamp() external view returns (uint256);

  /**
   * @notice The redemption phase timestamp
   * @return The redemption phase timestamp
   */
  function redemptionPhaseTimestamp() external view returns (uint256);

  /**
   * @notice Fetches the current phase of the Origination Pool
   * @return The current phase
   */
  function currentPhase() external view returns (OriginationPoolPhase);

  /**
   * @notice Fetches the pool multiplier in basis points
   * @return The pool multiplier in basis points
   */
  function poolMultiplierBps() external view returns (uint16);

  /**
   * @notice Fetches the pool deposit limit
   * @return The pool deposit limit
   */
  function poolLimit() external view returns (uint256);

  /**
   * @notice Fetches the amount of USD tokens deployed from the pool
   * @return The amount of USD tokens deployed from the pool
   */
  function amountDeployed() external view returns (uint256);

  /**
   * @notice Calculates the return amount of Consol for a given amount of USDX by applying the pool multiplier
   * @param amount The amount of USDX to calculate the return amount for
   * @return returnAmount The return amount of Consol
   */
  function calculateReturnAmount(uint256 amount) external view returns (uint256 returnAmount);

  /**
   * @notice Deposit USDX into the pool
   * @param amount The amount of USDX to deposit
   * @return mintAmount The amount of receipt tokens minted to the user
   */
  function deposit(uint256 amount) external returns (uint256 mintAmount);

  /**
   * @notice Redeem USDX + Consol from the pool from receipt tokens
   * @param amount The amount of receipt tokens to burn in exchange for USDX + Consol
   */
  function redeem(uint256 amount) external;

  /**
   * @notice Deploy USDX in the pool and convert it to Consol. Only callable by contracts implementing IOriginationPoolDeployCallback
   * @param amount The amount of USDX to deploy
   * @param data The calldata to pass into the callback
   */
  function deploy(uint256 amount, bytes calldata data) external;
}
