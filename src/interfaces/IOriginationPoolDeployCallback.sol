// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IOriginationPoolDeployCallback
 * @author SocksNFlops
 * @notice Any contract that calls IOriginationPool#deploy must implement this interface
 */
interface IOriginationPoolDeployCallback {
  /**
   * @notice Called to `msg.sender` after transferring to the recipient from IOriginationPool#deploy.
   * @dev In the implementation you must repay the pool the tokens sent by flash after the pool multiplier has been applied.
   * @param amount The amount of consol sent to the callback
   * @param returnAmount The amount of consol to return to the origination pool
   * @param data Any data passed through by the caller via the IOriginationPool#deploy call
   */
  function originationPoolDeployCallback(uint256 amount, uint256 returnAmount, bytes calldata data) external;
}
