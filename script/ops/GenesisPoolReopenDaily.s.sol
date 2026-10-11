// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {GenesisPoolBase} from "./GenesisPoolBase.s.sol";
import {OriginationPoolConfig} from "../../src/types/OriginationPoolConfig.sol";
import {OPoolConfigId, OPoolConfigIdLibrary} from "../../src/types/OPoolConfigId.sol";

/**
 * @title GenesisPoolReopenDaily
 * @notice Re-adds the daily origination pool config once the genesis pool leaves its deposit phase,
 *         signed by ADMIN_ADDRESS_0.
 * @dev The config is rebuilt from the same INITIAL_ORIGINATION_POOL_0_* vars, so it gets the same config id.
 *      removeConfig deleted that id's last-deployment record, so the first daily pool after reopening is
 *      sized at defaultPoolLimit: the poolLimitGrowthRateBps history restarts from scratch.
 *      Pools are then deployed per epoch as before (permissionless deployOriginationPool, usually the roller).
 */
contract GenesisPoolReopenDaily is GenesisPoolBase {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  function run() public {
    OriginationPoolConfig memory daily = dailyConfig();
    OPoolConfigId dailyId = daily.toId();

    _logConfig("Daily config (to add):", daily);

    _requireAdmin();
    require(!_hasConfig(dailyId), "daily config is already on the scheduler");

    vm.startBroadcast(admin);
    scheduler.addConfig(daily);
    vm.stopBroadcast();

    require(_hasConfig(dailyId), "daily config was not added");
    require(scheduler.lastConfigDeployment(dailyId).epoch == 0, "daily config has a stale deployment record");

    console.log("Current epoch:", scheduler.currentEpoch());
    console.log("Next daily pool (predicted):", scheduler.predictOriginationPool(dailyId));
    console.log("Next daily pool limit (defaultPoolLimit):", daily.defaultPoolLimit);
    console.log("Scheduler configLength:", scheduler.configLength());
  }
}
