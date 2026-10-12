// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {VmSafe} from "forge-std/Vm.sol";
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
 * @dev Resumable: the scheduler state is classified first and only the missing steps are sent.
 *        DAILY            {daily}                              -> all four steps
 *        EMPTY            {}, no genesis pool this epoch       -> add genesis, deploy, remove genesis
 *        GENESIS          {genesis}, not deployed              -> deploy, remove genesis
 *        GENESIS_DEPLOYED {genesis}, deployed this epoch       -> remove genesis
 *        GENESIS_LATE     {genesis}, not deployed, past window -> remove genesis; re-run after 12:00 UTC
 *        DONE             {}, genesis pool deployed this epoch -> nothing
 *      Phase timestamps anchor to the start of the current epoch (12:00 UTC), not to the broadcast time,
 *      so every second past the boundary shortens the deposit phase. A run that deploys refuses when more
 *      than GENESIS_MAX_EPOCH_ELAPSED seconds (default 1 hour, never above 1 hour when broadcasting)
 *      have passed since the boundary. When GENESIS_POOL_ADDRESS is a registered pool the run refuses:
 *      the genesis pool was already launched.
 *      Removing the genesis config leaves the pool registered, so the GeneralManager and RolloverVault
 *      keep accepting it. The checks after the broadcast run against the local simulation only;
 *      GenesisPoolVerify checks the mined chain.
 *      See script/ops/README.md for dry-run and broadcast commands.
 */
contract GenesisPoolLaunch is GenesisPoolBase {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  enum LaunchState {
    DAILY,
    EMPTY,
    GENESIS,
    GENESIS_DEPLOYED,
    GENESIS_LATE,
    DONE
  }

  uint256 public constant DEFAULT_MAX_EPOCH_ELAPSED = 1 hours;

  uint256 public maxEpochElapsed;
  IOriginationPool public genesisPool;
  address public predictedPool;
  LaunchState public launchState;

  function setUp() public virtual override {
    super.setUp();
    maxEpochElapsed = _envUintOr("GENESIS_MAX_EPOCH_ELAPSED", DEFAULT_MAX_EPOCH_ELAPSED);
  }

  /// @notice Overrides GENESIS_MAX_EPOCH_ELAPSED after setUp.
  function setMaxEpochElapsed(uint256 maxElapsed) external {
    maxEpochElapsed = maxElapsed;
  }

  /// @notice Reverts when an elapsed-time override above the default would apply to a broadcast.
  function checkMaxEpochElapsed(uint256 maxElapsed, bool broadcasting) public pure {
    require(
      !broadcasting || maxElapsed <= DEFAULT_MAX_EPOCH_ELAPSED,
      "GENESIS_MAX_EPOCH_ELAPSED above 1 hour is refused when broadcasting"
    );
  }

  function run() public {
    OriginationPoolConfig memory daily = dailyConfig();
    OriginationPoolConfig memory genesis = genesisConfig();
    OPoolConfigId dailyId = daily.toId();
    OPoolConfigId genesisId = genesis.toId();

    _logConfig("Daily config:", daily);
    _logConfig("Genesis config:", genesis);

    // Preconditions
    checkMaxEpochElapsed(maxEpochElapsed, vm.isContext(VmSafe.ForgeContext.ScriptBroadcast));
    if (maxEpochElapsed != DEFAULT_MAX_EPOCH_ELAPSED) {
      console.log("WARNING: GENESIS_MAX_EPOCH_ELAPSED override active:", maxEpochElapsed);
    }
    _requireAdmin();
    require(OPoolConfigId.unwrap(dailyId) != OPoolConfigId.unwrap(genesisId), "genesis config equals daily config");
    require(!_genesisPoolLaunched(), "genesis already launched: GENESIS_POOL_ADDRESS is a registered pool");

    uint256 epoch = scheduler.currentEpoch();
    uint256 epochStart = currentEpochStart();
    predictedPool = _predictGenesisPool(genesis, genesisId);
    launchState = _classify(dailyId, genesisId, epoch);
    uint256 elapsed = block.timestamp - epochStart;
    if (launchState == LaunchState.GENESIS && elapsed > maxEpochElapsed) {
      launchState = LaunchState.GENESIS_LATE;
    }
    console.log("Current epoch:", epoch);
    console.log("Block timestamp:", block.timestamp);
    console.log("Epoch start (12:00 UTC):", epochStart);
    console.log("Seconds since epoch start:", elapsed);
    console.log("Launch state:", _stateName(launchState));
    console.log("Genesis pool (predicted):", predictedPool);

    if (launchState == LaunchState.DONE) {
      genesisPool = IOriginationPool(predictedPool);
      console.log("Nothing to do: the genesis pool is deployed this epoch and no configs remain");
      _checkPostconditions(genesis, epochStart);
      _logResult(dailyId, epoch);
      return;
    }

    bool deploys =
      launchState == LaunchState.DAILY || launchState == LaunchState.EMPTY || launchState == LaunchState.GENESIS;
    if (deploys) {
      require(!scheduler.paused(), "scheduler is paused");
      require(elapsed <= maxEpochElapsed, "too long after the 12:00 UTC epoch boundary; see GENESIS_MAX_EPOCH_ELAPSED");
    }

    if (launchState == LaunchState.DAILY) {
      LastDeploymentRecord memory lastDaily = scheduler.lastConfigDeployment(dailyId);
      console.log("Daily pool already deployed this epoch:", lastDaily.epoch == epoch);
      if (lastDaily.epoch == epoch) {
        console.log("  daily pool this epoch:", lastDaily.deploymentAddress);
      }
    }

    vm.startBroadcast(admin);
    if (launchState == LaunchState.DAILY) {
      scheduler.removeConfig(daily);
    }
    if (launchState == LaunchState.DAILY || launchState == LaunchState.EMPTY) {
      scheduler.addConfig(genesis);
    }
    if (deploys) {
      if (predictedPool.code.length == 0) {
        require(scheduler.deployOriginationPool(genesisId) == predictedPool, "pool address differs from prediction");
      } else {
        console.log("Skipping deployOriginationPool: the predicted address already has code");
      }
    }
    scheduler.removeConfig(genesis);
    vm.stopBroadcast();

    if (launchState == LaunchState.GENESIS_LATE) {
      require(scheduler.configLength() == 0, "scheduler still has configs");
      console.log("Genesis config removed without deploying; no pools until the launch is re-run after 12:00 UTC");
      return;
    }

    genesisPool = IOriginationPool(predictedPool);
    _checkPostconditions(genesis, epochStart);
    _logResult(dailyId, epoch);
  }

  /// @dev The scheduler's own prediction; when the genesis config is absent it is added and removed in a reverted snapshot.
  function _predictGenesisPool(OriginationPoolConfig memory genesis, OPoolConfigId genesisId)
    internal
    returns (address pool)
  {
    if (_hasConfig(genesisId)) {
      return scheduler.predictOriginationPool(genesisId);
    }
    uint256 snapshot = vm.snapshotState();
    vm.prank(admin);
    scheduler.addConfig(genesis);
    pool = scheduler.predictOriginationPool(genesisId);
    require(vm.revertToStateAndDelete(snapshot), "snapshot revert failed");
  }

  function _classify(OPoolConfigId dailyId, OPoolConfigId genesisId, uint256 epoch)
    internal
    view
    returns (LaunchState)
  {
    uint256 length = scheduler.configLength();
    bool deployed = predictedPool.code.length != 0;
    if (length == 0) {
      return deployed ? LaunchState.DONE : LaunchState.EMPTY;
    }
    require(length == 1, "expected at most one config on the scheduler");
    OPoolConfigId onChain = scheduler.configIdAt(0);
    if (OPoolConfigId.unwrap(onChain) == OPoolConfigId.unwrap(dailyId)) {
      require(!deployed, "genesis pool already deployed this epoch while the daily config is present");
      return LaunchState.DAILY;
    }
    require(
      OPoolConfigId.unwrap(onChain) == OPoolConfigId.unwrap(genesisId),
      "on-chain config matches neither INITIAL_ORIGINATION_POOL_0_* nor the genesis config"
    );
    LastDeploymentRecord memory record = scheduler.lastConfigDeployment(genesisId);
    require(
      record.epoch == 0 || record.epoch == epoch,
      "genesis config has a deployment from a previous epoch; remove it manually"
    );
    return deployed ? LaunchState.GENESIS_DEPLOYED : LaunchState.GENESIS;
  }

  function _checkPostconditions(OriginationPoolConfig memory genesis, uint256 epochStart) internal view {
    address pool = address(genesisPool);
    require(pool.code.length != 0, "genesis pool has no code");
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
  }

  function _logResult(OPoolConfigId dailyId, uint256 epoch) internal view {
    address pool = address(genesisPool);
    console.log("Genesis pool:", pool);
    console.log("  name:", IERC20Metadata(pool).name());
    console.log("  symbol:", IERC20Metadata(pool).symbol());
    console.log("  epoch:", epoch);
    console.log("  poolLimit:", genesisPool.poolLimit());
    console.log("  depositPhaseTimestamp:", genesisPool.depositPhaseTimestamp());
    console.log("  deployPhaseTimestamp:", genesisPool.deployPhaseTimestamp());
    console.log("  redemptionPhaseTimestamp:", genesisPool.redemptionPhaseTimestamp());
    console.log("Scheduler configLength:", scheduler.configLength());
    console.log("Simulated values; confirm on-chain with GenesisPoolVerify before recording:");
    console.log("  GENESIS_POOL_ADDRESS=%s", pool);
    console.log("  GENESIS_EXPECTED_DAILY_CONFIG_ID=%s", vm.toString(OPoolConfigId.unwrap(dailyId)));
  }

  function _stateName(LaunchState state) internal pure returns (string memory) {
    if (state == LaunchState.DAILY) return "DAILY: remove daily, add genesis, deploy, remove genesis";
    if (state == LaunchState.EMPTY) return "EMPTY: add genesis, deploy, remove genesis";
    if (state == LaunchState.GENESIS) return "GENESIS: deploy, remove genesis";
    if (state == LaunchState.GENESIS_DEPLOYED) return "GENESIS_DEPLOYED: remove genesis";
    if (state == LaunchState.GENESIS_LATE) return "GENESIS_LATE: remove genesis without deploying (past the window)";
    return "DONE: nothing to send";
  }
}
