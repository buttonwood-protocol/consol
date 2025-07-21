// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title WithdrawalRequest
 * @author SocksNFlops
 * @notice A struct that represents a request to withdraw from the Consol contract
 * @param account The account that made the request
 * @param shares The amount of shares to withdraw
 * @param amount The amount to withdraw
 * @param timestamp The timestamp of the request
 * @param gasFee The gas fee paid for the request
 */
struct WithdrawalRequest {
  address account;
  uint256 shares;
  uint256 amount;
  uint256 timestamp;
  uint256 gasFee;
}
