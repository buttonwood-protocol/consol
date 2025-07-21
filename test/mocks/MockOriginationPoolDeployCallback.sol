// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IOriginationPoolDeployCallback} from "../../src/interfaces/IOriginationPoolDeployCallback.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockOriginationPoolDeployCallback
 * @author SocksNFlops
 * @notice Mocks an implementer of IOriginationPoolDeployCallback
 */
contract MockOriginationPoolDeployCallback is IOriginationPoolDeployCallback {
  using SafeERC20 for IERC20;

  IERC20 consol;

  constructor(address consol_) {
    consol = IERC20(consol_);
  }

  function deploy(IOriginationPool originationPool, uint256 amount, bytes calldata data) public {
    originationPool.deploy(amount, data);
  }

  function originationPoolDeployCallback(uint256, uint256, bytes calldata) external override {
    // Send the return amount to the caller
    uint256 consolBalance = IERC20(consol).balanceOf(address(this));
    IERC20(consol).safeTransfer(msg.sender, consolBalance);
  }
}
