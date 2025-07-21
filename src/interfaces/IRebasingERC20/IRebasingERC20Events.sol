// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRebasingERC20Events is IERC20 {
  /**
   * @notice Emitted when shares/balances are transferred
   * @param from The address of the sender
   * @param to The address of the recipient
   * @param amount The amount of shares transferred
   * @param shares The amount of shares transferred
   */
  event TransferShares(address indexed from, address indexed to, uint256 amount, uint256 shares);
}
