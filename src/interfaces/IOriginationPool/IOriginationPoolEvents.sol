// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IOriginationPoolEvents
 * @author SocksNFlops
 * @notice Events for the OriginationPool contract
 */
interface IOriginationPoolEvents {
  /**
   * @notice Event for a deposit
   * @param user The user
   * @param token The token
   * @param amount The amount of USDTokens being deposited
   * @param mintAmount The amount of OriginationPool tokens being minted
   */
  event Deposit(address indexed user, address indexed token, uint256 amount, uint256 mintAmount);

  /**
   * @notice Event for a deploy
   * @param user The user
   * @param token The token
   * @param amount The amount of USDTokens being deployed
   * @param receiptAmount The amount of OriginationPool tokens being returned
   */
  event Deploy(address indexed user, address indexed token, uint256 amount, uint256 receiptAmount);

  /**
   * @notice Event for a redeem
   * @param user The user
   * @param amount The amount of OriginationPool tokens being redeemed
   */
  event Redeem(address indexed user, uint256 amount);
}
