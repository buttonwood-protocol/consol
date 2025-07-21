// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {OPoolConfigIdLibrary} from "./OPoolConfigId.sol";

using OPoolConfigIdLibrary for OriginationPoolConfig global;

/**
 * @notice The configuration for a recurring origination pool deployment
 * @param namePrefix The prefix for the name of the pool
 * @param symbolPrefix The prefix for the symbol of the pool
 * @param consol The consol token for the pool
 * @param usdx The USDX token for the pool
 * @param depositPhaseDuration The duration of the deposit phase
 * @param deployPhaseDuration The duration of the deploy phase
 * @param defaultPoolLimit The starting pool limit (for first deployment)
 * @param poolLimitGrowthRateBps The rate at which the pool limit grows each epoch if the previous pool limit was reached
 * @param poolMultiplierBps The pool multiplier in basis points
 */
struct OriginationPoolConfig {
  string namePrefix;
  string symbolPrefix;
  address consol;
  address usdx;
  uint32 depositPhaseDuration;
  uint32 deployPhaseDuration;
  uint256 defaultPoolLimit;
  uint16 poolLimitGrowthRateBps;
  uint16 poolMultiplierBps;
}
