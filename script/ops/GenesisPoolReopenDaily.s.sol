// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {GenesisPoolBase} from "./GenesisPoolBase.s.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {OriginationPoolConfig} from "../../src/types/OriginationPoolConfig.sol";
import {OPoolConfigId, OPoolConfigIdLibrary} from "../../src/types/OPoolConfigId.sol";
import {OriginationPoolPhase} from "../../src/types/enums/OriginationPoolPhase.sol";

/**
 * @title GenesisPoolReopenDaily
 * @notice Re-adds the daily origination pool config once the genesis pool leaves its deposit phase,
 *         signed by ADMIN_ADDRESS_0.
 * @dev Refuses unless the scheduler holds no configs, GENESIS_POOL_ADDRESS is a deployed pool past
 *      DEPOSIT, and the daily config rebuilt from INITIAL_ORIGINATION_POOL_0_* has the id recorded at
 *      launch (GENESIS_EXPECTED_DAILY_CONFIG_ID). The genesis pool may be deregistered (the miss path);
 *      its registration is logged and left unchanged.
 *      removeConfig deleted that id's last-deployment record, so the first daily pool after reopening is
 *      sized at defaultPoolLimit: the poolLimitGrowthRateBps history restarts from scratch.
 *      Pools are then deployed per epoch as before (permissionless deployOriginationPool, usually the roller).
 */
contract GenesisPoolReopenDaily is GenesisPoolBase {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  bytes32 public expectedDailyConfigId;

  function setUp() public virtual override {
    super.setUp();
    expectedDailyConfigId =
      vm.envExists("GENESIS_EXPECTED_DAILY_CONFIG_ID") ? vm.envBytes32("GENESIS_EXPECTED_DAILY_CONFIG_ID") : bytes32(0);
  }

  /// @notice Overrides GENESIS_EXPECTED_DAILY_CONFIG_ID after setUp.
  function setExpectedDailyConfigId(bytes32 id) external {
    expectedDailyConfigId = id;
  }

  function run() public {
    OriginationPoolConfig memory daily = dailyConfig();
    OPoolConfigId dailyId = daily.toId();

    _logConfig("Daily config (to add):", daily);

    // Preconditions
    _requireAdmin();
    require(scheduler.configLength() == 0, "expected no configs on the scheduler");
    IOriginationPool genesisPool = _requireGenesisPool();
    OriginationPoolPhase phase;
    try genesisPool.currentPhase() returns (OriginationPoolPhase p) {
      phase = p;
    } catch {
      revert("GENESIS_POOL_ADDRESS is not an origination pool");
    }
    bool registered = scheduler.isRegistered(address(genesisPool));
    console.log("Genesis pool:", address(genesisPool));
    console.log("  phase:", _phaseName(phase));
    console.log("  registration:", _registrationName(registered));
    if (!registered) {
      console.log("  the genesis pool stays deregistered; reopening only adds the daily config");
    }
    require(phase != OriginationPoolPhase.DEPOSIT, "genesis pool is still in DEPOSIT");
    require(expectedDailyConfigId != bytes32(0), "GENESIS_EXPECTED_DAILY_CONFIG_ID is not set");
    require(
      OPoolConfigId.unwrap(dailyId) == expectedDailyConfigId,
      "daily config id does not match GENESIS_EXPECTED_DAILY_CONFIG_ID"
    );
    require(
      scheduler.lastConfigDeployment(dailyId).deploymentAddress == address(0),
      "daily config has a stale deployment record"
    );

    vm.startBroadcast(admin);
    scheduler.addConfig(daily);
    vm.stopBroadcast();

    require(scheduler.configLength() == 1, "expected exactly one config after reopening");
    require(
      OPoolConfigId.unwrap(scheduler.configIdAt(0)) == OPoolConfigId.unwrap(dailyId), "daily config was not added"
    );

    console.log("Current epoch:", scheduler.currentEpoch());
    console.log("Next daily pool (predicted):", scheduler.predictOriginationPool(dailyId));
    console.log("Next daily pool limit (defaultPoolLimit):", daily.defaultPoolLimit);
    console.log("Scheduler configLength:", scheduler.configLength());
  }
}
