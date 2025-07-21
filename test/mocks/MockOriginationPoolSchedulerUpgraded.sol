// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OriginationPoolScheduler} from "../../src/OriginationPoolScheduler.sol";

/**
 * @title OriginationPoolScheduler
 * @author SocksNFlops
 * @notice Just a mock to test the upgrade of the OriginationPoolScheduler
 */
contract MockOriginationPoolSchedulerUpgraded is OriginationPoolScheduler {
  function newFunction() public pure returns (bool) {
    return true;
  }
}
