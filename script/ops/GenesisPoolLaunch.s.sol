// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {GenesisPoolBase} from "./GenesisPoolBase.s.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {LastDeploymentRecord} from "../../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {OriginationPoolConfig} from "../../src/types/OriginationPoolConfig.sol";
import {OPoolConfigId, OPoolConfigIdLibrary} from "../../src/types/OPoolConfigId.sol";
import {OriginationPoolPhase} from "../../src/types/enums/OriginationPoolPhase.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/**
 * @title GenesisPoolLaunch
 * @notice Replaces the daily origination pool with a single genesis pool, signed by ADMIN_ADDRESS_0:
 *         removeConfig(daily) -> addConfig(genesis) -> deployOriginationPool(genesis) -> removeConfig(genesis).
 * @dev Phase timestamps anchor to the start of the current epoch (12:00 UTC), not to the broadcast time,
 *      so every second past the boundary shortens the deposit phase. The run refuses to proceed when more
 *      than GENESIS_MAX_EPOCH_ELAPSED seconds (default 1 hour) have passed since the boundary.
 *      Removing the genesis config leaves the pool registered, so the GeneralManager and RolloverVault
 *      keep accepting it, while no second genesis pool can be deployed.
 *      See script/ops/README.md for dry-run and broadcast commands.
 */
contract GenesisPoolLaunch is GenesisPoolBase {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  uint256 public constant DEFAULT_MAX_EPOCH_ELAPSED = 1 hours;

  IOriginationPool public genesisPool;
  address public predictedPool;

  function run() public {
    OriginationPoolConfig memory daily = dailyConfig();
    OriginationPoolConfig memory genesis = genesisConfig();
    OPoolConfigId dailyId = daily.toId();
    OPoolConfigId genesisId = genesis.toId();

    _logConfig("Daily config (to remove):", daily);
    _logConfig("Genesis config:", genesis);

    // Preconditions
    _requireAdmin();
    require(!scheduler.paused(), "scheduler is paused");
    require(scheduler.configLength() == 1, "expected exactly one config on the scheduler");
    require(
      OPoolConfigId.unwrap(scheduler.configIdAt(0)) == OPoolConfigId.unwrap(dailyId),
      "on-chain config does not match INITIAL_ORIGINATION_POOL_0_*"
    );
    require(OPoolConfigId.unwrap(dailyId) != OPoolConfigId.unwrap(genesisId), "genesis config equals daily config");

    uint256 epochStart = currentEpochStart();
    uint256 elapsed = block.timestamp - epochStart;
    uint256 maxElapsed = vm.envOr("GENESIS_MAX_EPOCH_ELAPSED", DEFAULT_MAX_EPOCH_ELAPSED);
    console.log("Block timestamp:", block.timestamp);
    console.log("Epoch start (12:00 UTC):", epochStart);
    console.log("Seconds since epoch start:", elapsed);
    require(elapsed <= maxElapsed, "too long after the 12:00 UTC epoch boundary; see GENESIS_MAX_EPOCH_ELAPSED");

    uint256 epoch = scheduler.currentEpoch();
    LastDeploymentRecord memory lastDaily = scheduler.lastConfigDeployment(dailyId);
    console.log("Current epoch:", epoch);
    console.log("Daily pool already deployed this epoch:", lastDaily.epoch == epoch);
    if (lastDaily.epoch == epoch) {
      console.log("  daily pool this epoch:", lastDaily.deploymentAddress);
    }

    vm.startBroadcast(admin);
    scheduler.removeConfig(daily);
    scheduler.addConfig(genesis);
    predictedPool = scheduler.predictOriginationPool(genesisId);
    genesisPool = IOriginationPool(scheduler.deployOriginationPool(genesisId));
    scheduler.removeConfig(genesis);
    vm.stopBroadcast();

    // Postconditions
    address pool = address(genesisPool);
    require(pool == predictedPool, "pool address differs from prediction");
    require(scheduler.isRegistered(pool), "genesis pool is not registered");
    require(genesisPool.currentPhase() == OriginationPoolPhase.DEPOSIT, "genesis pool is not in DEPOSIT");
    require(scheduler.configLength() == 0, "scheduler still has configs");
    require(
      genesisPool.deployPhaseTimestamp() == epochStart + genesis.depositPhaseDuration, "unexpected deployPhaseTimestamp"
    );
    require(
      genesisPool.redemptionPhaseTimestamp() == genesisPool.deployPhaseTimestamp() + genesis.deployPhaseDuration,
      "unexpected redemptionPhaseTimestamp"
    );
    require(genesisPool.poolLimit() == genesis.defaultPoolLimit, "unexpected poolLimit");
    require(genesisPool.poolMultiplierBps() == genesis.poolMultiplierBps, "unexpected poolMultiplierBps");
    require(genesisPool.consol() == genesis.consol && genesisPool.usdx() == genesis.usdx, "unexpected consol/usdx");
    require(
      IAccessControl(pool).hasRole(Roles.DEPLOY_ROLE, scheduler.generalManager()),
      "GeneralManager lacks DEPLOY_ROLE on the genesis pool"
    );

    console.log("Genesis pool (predicted):", predictedPool);
    console.log("Genesis pool (deployed): ", pool);
    console.log("  name:", IERC20Metadata(pool).name());
    console.log("  symbol:", IERC20Metadata(pool).symbol());
    console.log("  epoch:", epoch);
    console.log("  poolLimit:", genesisPool.poolLimit());
    console.log("  depositPhaseTimestamp:", genesisPool.depositPhaseTimestamp());
    console.log("  deployPhaseTimestamp:", genesisPool.deployPhaseTimestamp());
    console.log("  redemptionPhaseTimestamp:", genesisPool.redemptionPhaseTimestamp());
    console.log("Scheduler configLength:", scheduler.configLength());
  }
}
