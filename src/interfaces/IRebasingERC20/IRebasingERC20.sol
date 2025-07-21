// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRebasingERC20Events} from "./IRebasingERC20Events.sol";

interface IRebasingERC20 is IERC20, IRebasingERC20Events {
  /**
   * @notice The total amount of the shares token
   * @return The total amount of the shares token
   */
  function totalShares() external view returns (uint256);

  /**
   * @notice Converts the amount of underlying token to the corresponding amount of shares
   * @param assets The amount of underlying token
   * @return The corresponding amount of shares
   */
  function convertToShares(uint256 assets) external view returns (uint256);

  /**
   * @notice Converts the amount of shares to the corresponding amount of underlying token
   * @param shares The amount of shares
   * @return The corresponding amount of underlying token
   */
  function convertToAssets(uint256 shares) external view returns (uint256);

  /**
   * @notice The amount of shares that the account has
   * @param account The address of the account
   * @return The amount of shares that the account has
   */
  function sharesOf(address account) external view returns (uint256);

  /**
   * @notice The decimals offset. The number of decimals to offset the shares by. Used to protect against inflation attacks.
   * @return The decimals offset
   */
  function decimalsOffset() external view returns (uint8);
}
