// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IYieldStrategy} from "../../src/interfaces/IYieldStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISubConsol} from "../../src/interfaces/ISubConsol/ISubConsol.sol";

contract MockYieldStrategy is IYieldStrategy {
  using SafeERC20 for IERC20;

  /// @inheritdoc IYieldStrategy
  address public immutable subConsol;

  constructor(address subConsol_) {
    subConsol = subConsol_;
  }

  /**
   * @inheritdoc IYieldStrategy
   */
  function deposit(address from, uint256 amount) external {
    if (msg.sender != subConsol) {
      revert("MockYieldStrategy: Only subConsol can call this function");
    }
    IERC20(ISubConsol(subConsol).collateral()).safeTransferFrom(from, address(this), amount);
  }

  /**
   * @inheritdoc IYieldStrategy
   */
  function withdraw(address to, uint256 amount) external {
    if (msg.sender != subConsol) {
      revert("MockYieldStrategy: Only subConsol can call this function");
    }
    IERC20(ISubConsol(subConsol).collateral()).safeTransfer(to, amount);
  }
}
