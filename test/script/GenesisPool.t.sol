// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployAllTest} from "./DeployAll.t.sol";
import {GenesisPoolLaunch} from "../../script/ops/GenesisPoolLaunch.s.sol";
import {GenesisPoolReopenDaily} from "../../script/ops/GenesisPoolReopenDaily.s.sol";
import {GenesisPoolVerify} from "../../script/ops/GenesisPoolVerify.s.sol";
import {GenesisPoolBase} from "../../script/ops/GenesisPoolBase.s.sol";
import {OriginationPool} from "../../src/OriginationPool.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {
  IOriginationPoolScheduler,
  IOriginationPoolSchedulerErrors
} from "../../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IUSDX} from "../../src/interfaces/IUSDX/IUSDX.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {OriginationPoolConfig} from "../../src/types/OriginationPoolConfig.sol";
import {OPoolConfigId, OPoolConfigIdLibrary} from "../../src/types/OPoolConfigId.sol";
import {OriginationPoolPhase} from "../../src/types/enums/OriginationPoolPhase.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/// @dev Mirrors RolloverVault.depositOriginationPool: registry check, approve, deposit.
contract RolloverStyleDepositor {
  error OriginationPoolNotRegistered(address originationPool);

  function depositOriginationPool(IOriginationPoolScheduler scheduler, IERC20 usdx, address pool, uint256 amount)
    external
  {
    if (!scheduler.isRegistered(pool)) {
      revert OriginationPoolNotRegistered(pool);
    }
    usdx.approve(pool, amount);
    IOriginationPool(pool).deposit(amount);
  }
}

contract GenesisPoolTest is DeployAllTest {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  string internal constant RELAUNCH_REVERT =
    "genesis already launched: GENESIS_POOL_ADDRESS is a deployed pool; see GENESIS_FORCE_RELAUNCH";

  GenesisPoolLaunch public launch;
  IOriginationPoolScheduler public scheduler;
  uint256 public epochStart;
  OriginationPoolConfig internal _otherConfig;

  function testId() public pure override(DeployAllTest) returns (string memory) {
    return type(GenesisPoolTest).name;
  }

  function setUp() public override(DeployAllTest) {
    DeployAllTest.setUp();
    deployAll.run();
    scheduler = deployAll.originationPoolScheduler();

    // Mirror the live chain: the daily config (config 0) is the only config
    OriginationPoolConfig memory config2 = scheduler.configAt(2);
    _otherConfig = scheduler.configAt(1);
    vm.startPrank(admin1);
    scheduler.removeConfig(config2);
    scheduler.removeConfig(_otherConfig);
    vm.stopPrank();
    assertEq(scheduler.configLength(), 1, "setup: expected only the daily config");

    // Five minutes past the next 12:00 UTC epoch boundary
    epochStart = block.timestamp - ((block.timestamp - Constants.EPOCH_OFFSET) % Constants.EPOCH_DURATION)
      + Constants.EPOCH_DURATION;
    vm.warp(epochStart + 5 minutes);

    launch = _newLaunch();
  }

  // ---------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------

  /// @dev Address book JSON built in memory: the on-disk file is shared with parallel tests in this suite.
  function _addressBookJson() internal view returns (string memory) {
    return string.concat(
      '{"consolAddress":"',
      vm.toString(address(deployAll.consol())),
      '","generalManagerAddress":"',
      vm.toString(address(deployAll.generalManager())),
      '","originationPoolSchedulerAddress":"',
      vm.toString(address(scheduler)),
      '","usdxAddress":"',
      vm.toString(address(deployAll.usdx())),
      '"}'
    );
  }

  /// @dev Optional env inputs are pinned through setters: vm.setEnv is process-wide across parallel tests.
  function _configure(GenesisPoolBase script, address genesisPool) internal {
    script.setAddressBookJson(_addressBookJson());
    script.setUp();
    script.setGenesisPoolAddress(genesisPool);
  }

  function _newLaunch() internal returns (GenesisPoolLaunch script) {
    script = new GenesisPoolLaunch();
    _configure(script, address(0));
    script.setMaxEpochElapsed(script.DEFAULT_MAX_EPOCH_ELAPSED());
  }

  function _newReopen(address genesisPool, bytes32 expectedDailyId) internal returns (GenesisPoolReopenDaily script) {
    script = new GenesisPoolReopenDaily();
    _configure(script, genesisPool);
    script.setExpectedDailyConfigId(expectedDailyId);
  }

  function _newVerify(address genesisPool) internal returns (GenesisPoolVerify script) {
    script = new GenesisPoolVerify();
    _configure(script, genesisPool);
  }

  function _dailyIdRaw() internal view returns (bytes32) {
    return OPoolConfigId.unwrap(launch.dailyConfigId());
  }

  /// @dev The scheduler's own prediction for the genesis config, taken before any launch transaction.
  function _schedulerPrediction() internal returns (address predicted) {
    OPoolConfigId genesisId = launch.genesisConfigId();
    uint256 snapshot = vm.snapshotState();
    if (scheduler.lastConfigDeployment(genesisId).epoch == 0 && !_hasGenesisConfig()) {
      OriginationPoolConfig memory genesis = launch.genesisConfig();
      vm.prank(admin1);
      scheduler.addConfig(genesis);
    }
    predicted = scheduler.predictOriginationPool(genesisId);
    vm.revertToStateAndDelete(snapshot);
  }

  /// @dev CREATE2 address computed from the pool's creation code and the launch parameters.
  function _expectedGenesisPool() internal view returns (address) {
    OriginationPoolConfig memory g = launch.genesisConfig();
    uint256 epoch = scheduler.currentEpoch();
    bytes memory initCode = abi.encodePacked(
      type(OriginationPool).creationCode,
      abi.encode(
        g.namePrefix,
        g.symbolPrefix,
        epoch,
        g.consol,
        g.usdx,
        epochStart + 21 days,
        epochStart + 35 days,
        uint256(1_000_000_000e18),
        uint16(0)
      )
    );
    return
      vm.computeCreate2Address(keccak256(abi.encodePacked(epoch, g.toId())), keccak256(initCode), address(scheduler));
  }

  function _hasGenesisConfig() internal view returns (bool) {
    return scheduler.configLength() != 0
      && OPoolConfigId.unwrap(scheduler.configIdAt(0)) == OPoolConfigId.unwrap(launch.genesisConfigId());
  }

  /// @dev A partial launch: removeConfig(daily) and, optionally, addConfig(genesis).
  function _partialLaunch(bool addGenesis) internal {
    OriginationPoolConfig memory daily = launch.dailyConfig();
    OriginationPoolConfig memory genesis = launch.genesisConfig();
    vm.startPrank(admin1);
    scheduler.removeConfig(daily);
    if (addGenesis) {
      scheduler.addConfig(genesis);
    }
    vm.stopPrank();
  }

  function _assertLaunched(address pool, address expected) internal view {
    assertEq(pool, expected, "pool address");
    assertGt(pool.code.length, 0, "pool has no code");
    assertTrue(scheduler.isRegistered(pool), "genesis pool not registered");
    assertEq(uint8(IOriginationPool(pool).currentPhase()), uint8(OriginationPoolPhase.DEPOSIT), "phase");
    assertEq(scheduler.configLength(), 0, "configs left on the scheduler");
    assertEq(IOriginationPool(pool).deployPhaseTimestamp(), epochStart + 21 days, "deployPhaseTimestamp");
    assertEq(IOriginationPool(pool).redemptionPhaseTimestamp(), epochStart + 35 days, "redemptionPhaseTimestamp");
  }

  function _launchAndReopen() internal returns (address pool) {
    launch.run();
    pool = address(launch.genesisPool());
    vm.warp(epochStart + 21 days + 5 minutes);
    _newReopen(pool, _dailyIdRaw()).run();
  }

  /// @dev The miss path: launch, then deregister the pool five minutes past the first boundary at or after its close.
  function _launchAndDeregister() internal returns (address pool) {
    launch.run();
    pool = address(launch.genesisPool());
    uint256 closeTs = IOriginationPool(pool).deployPhaseTimestamp();
    uint256 boundary = closeTs - ((closeTs - Constants.EPOCH_OFFSET) % Constants.EPOCH_DURATION);
    if (boundary < closeTs) {
      boundary += Constants.EPOCH_DURATION;
    }
    epochStart = boundary;
    vm.warp(epochStart + 5 minutes);
    vm.prank(admin1);
    scheduler.updateRegistration(pool, false);
    assertFalse(scheduler.isRegistered(pool), "setup: genesis pool still registered");
  }

  function _fundUsdx(address account, uint256 usdAmount) internal returns (uint256 usdxAmount) {
    MockERC20 usdToken = MockERC20(address(deployAll.usdTokens(0)));
    IUSDX usdx = deployAll.usdx();
    usdToken.mint(account, usdAmount);
    uint256 before = usdx.balanceOf(account);
    vm.startPrank(account);
    usdToken.approve(address(usdx), usdAmount);
    usdx.deposit(address(usdToken), usdAmount);
    vm.stopPrank();
    usdxAmount = usdx.balanceOf(account) - before;
  }

  // ---------------------------------------------------------------------------------------------
  // Launch: full sequence
  // ---------------------------------------------------------------------------------------------

  function run() public override(DeployAllTest) {
    OPoolConfigId dailyId = launch.dailyConfigId();
    assertEq(
      OPoolConfigId.unwrap(scheduler.configIdAt(0)),
      OPoolConfigId.unwrap(dailyId),
      "daily config rebuilt from env does not match the deployed config"
    );
    address predicted = _schedulerPrediction();
    assertEq(predicted, _expectedGenesisPool(), "scheduler prediction vs creation code");

    launch.run();
    IOriginationPool pool = launch.genesisPool();
    OriginationPoolConfig memory genesis = launch.genesisConfig();

    assertEq(uint8(launch.launchState()), uint8(GenesisPoolLaunch.LaunchState.DAILY), "launch state");
    _assertLaunched(address(pool), predicted);
    assertEq(pool.depositPhaseTimestamp(), epochStart + 5 minutes, "depositPhaseTimestamp");
    assertEq(pool.poolLimit(), 1_000_000_000e18, "poolLimit");
    assertEq(pool.poolMultiplierBps(), 0, "poolMultiplierBps");
    assertEq(genesis.depositPhaseDuration, 1_814_400, "genesis depositPhaseDuration");
    assertEq(genesis.deployPhaseDuration, 1_209_600, "genesis deployPhaseDuration");
    assertEq(genesis.poolLimitGrowthRateBps, 0, "genesis poolLimitGrowthRateBps");
    assertEq(genesis.namePrefix, "Genesis Origination Pool", "genesis namePrefix");
    assertEq(genesis.symbolPrefix, "GEN-OP", "genesis symbolPrefix");
    assertTrue(
      IAccessControl(address(pool)).hasRole(Roles.DEPLOY_ROLE, address(deployAll.generalManager())),
      "GeneralManager lacks DEPLOY_ROLE"
    );
    assertTrue(IAccessControl(address(pool)).hasRole(Roles.DEFAULT_ADMIN_ROLE, scheduler.oPoolAdmin()), "pool admin");
    assertFalse(IAccessControl(address(pool)).hasRole(Roles.DEFAULT_ADMIN_ROLE, address(scheduler)), "scheduler admin");
  }

  function test_launch_withDailyPoolDeployedThisEpoch() public {
    OPoolConfigId dailyId = launch.dailyConfigId();
    vm.prank(makeAddr("roller"));
    address dailyPool = scheduler.deployOriginationPool(dailyId);
    address predicted = _schedulerPrediction();

    launch.run();
    assertEq(uint8(launch.launchState()), uint8(GenesisPoolLaunch.LaunchState.DAILY), "launch state");
    _assertLaunched(address(launch.genesisPool()), predicted);
    assertTrue(scheduler.isRegistered(dailyPool), "daily pool deregistered");
    assertEq(uint8(IOriginationPool(dailyPool).currentPhase()), uint8(OriginationPoolPhase.DEPOSIT), "daily phase");
  }

  // ---------------------------------------------------------------------------------------------
  // Launch: resume
  // ---------------------------------------------------------------------------------------------

  function test_launch_resumesFromEmpty() public {
    _partialLaunch(false);
    assertEq(scheduler.configLength(), 0, "setup: configs");
    address predicted = _schedulerPrediction();

    launch.run();
    assertEq(uint8(launch.launchState()), uint8(GenesisPoolLaunch.LaunchState.EMPTY), "launch state");
    _assertLaunched(address(launch.genesisPool()), predicted);
    assertEq(predicted, _expectedGenesisPool(), "prediction vs creation code");
  }

  function test_launch_resumesFromGenesisConfig() public {
    _partialLaunch(true);
    address predicted = scheduler.predictOriginationPool(launch.genesisConfigId());
    assertEq(predicted.code.length, 0, "setup: pool already deployed");

    launch.run();
    assertEq(uint8(launch.launchState()), uint8(GenesisPoolLaunch.LaunchState.GENESIS), "launch state");
    _assertLaunched(address(launch.genesisPool()), predicted);
  }

  function test_launch_resumesAfterFrontRunDeploy() public {
    _partialLaunch(true);
    OPoolConfigId genesisId = launch.genesisConfigId();
    address predicted = scheduler.predictOriginationPool(genesisId);
    vm.prank(makeAddr("roller"));
    assertEq(scheduler.deployOriginationPool(genesisId), predicted, "front-run deploy address");

    // Only removeConfig(genesis) is left, so the elapsed-time guard does not apply
    vm.warp(epochStart + 3 hours);
    launch.run();
    assertEq(uint8(launch.launchState()), uint8(GenesisPoolLaunch.LaunchState.GENESIS_DEPLOYED), "launch state");
    _assertLaunched(address(launch.genesisPool()), predicted);
  }

  function test_launch_skipsDeployWhenPoolHasCodeWithoutRecord() public {
    launch.run();
    address pool = address(launch.genesisPool());
    // Re-adding the config in the same epoch clears the record but the CREATE2 address is taken
    OriginationPoolConfig memory genesis = launch.genesisConfig();
    vm.prank(admin1);
    scheduler.addConfig(genesis);

    GenesisPoolLaunch again = _newLaunch();
    again.run();
    assertEq(uint8(again.launchState()), uint8(GenesisPoolLaunch.LaunchState.GENESIS_DEPLOYED), "launch state");
    _assertLaunched(address(again.genesisPool()), pool);
  }

  function test_launch_doneIsNoop() public {
    launch.run();
    address pool = address(launch.genesisPool());

    GenesisPoolLaunch again = _newLaunch();
    again.run();
    assertEq(uint8(again.launchState()), uint8(GenesisPoolLaunch.LaunchState.DONE), "launch state");
    _assertLaunched(address(again.genesisPool()), pool);
  }

  // ---------------------------------------------------------------------------------------------
  // Launch: guards
  // ---------------------------------------------------------------------------------------------

  function test_launch_elapsedExactlyOneHourPasses() public {
    vm.warp(epochStart + 1 hours);
    launch.run();
    assertEq(IOriginationPool(address(launch.genesisPool())).depositPhaseTimestamp(), epochStart + 1 hours);
  }

  function test_launch_revertsLateInEpoch() public {
    vm.warp(epochStart + 1 hours + 1);
    vm.expectRevert(bytes("too long after the 12:00 UTC epoch boundary; see GENESIS_MAX_EPOCH_ELAPSED"));
    launch.run();
  }

  function test_launch_lateGenesisConfigIsRemovedWithoutDeploy() public {
    _partialLaunch(true);
    address predicted = scheduler.predictOriginationPool(launch.genesisConfigId());
    vm.warp(epochStart + 1 hours + 1);
    launch.run();
    assertEq(uint8(launch.launchState()), uint8(GenesisPoolLaunch.LaunchState.GENESIS_LATE), "launch state");
    assertEq(scheduler.configLength(), 0, "configs left on the scheduler");
    assertEq(predicted.code.length, 0, "pool deployed past the window");
    assertEq(address(launch.genesisPool()), address(0), "genesis pool set");

    // The next boundary resumes from {}
    epochStart += Constants.EPOCH_DURATION;
    vm.warp(epochStart + 5 minutes);
    address next = _schedulerPrediction();
    GenesisPoolLaunch again = _newLaunch();
    again.run();
    assertEq(uint8(again.launchState()), uint8(GenesisPoolLaunch.LaunchState.EMPTY), "launch state next day");
    _assertLaunched(address(again.genesisPool()), next);
  }

  function test_launch_revertsLateFromEmpty() public {
    _partialLaunch(false);
    vm.warp(epochStart + 1 hours + 1);
    vm.expectRevert(bytes("too long after the 12:00 UTC epoch boundary; see GENESIS_MAX_EPOCH_ELAPSED"));
    launch.run();
  }

  function test_launch_overrideAllowedOutsideBroadcast() public {
    launch.setMaxEpochElapsed(1 days);
    vm.warp(epochStart + 5 hours);
    launch.run();
    assertEq(scheduler.configLength(), 0, "configs left on the scheduler");
  }

  function test_checkMaxEpochElapsed() public {
    launch.checkMaxEpochElapsed(1 days, false);
    launch.checkMaxEpochElapsed(1 hours, true);
    launch.checkMaxEpochElapsed(0, true);
    vm.expectRevert(bytes("GENESIS_MAX_EPOCH_ELAPSED above 1 hour is refused when broadcasting"));
    launch.checkMaxEpochElapsed(1 hours + 1, true);
  }

  function test_launch_revertsWithTwoConfigs() public {
    OriginationPoolConfig memory genesis = launch.genesisConfig();
    vm.prank(admin1);
    scheduler.addConfig(genesis);
    vm.expectRevert(bytes("expected at most one config on the scheduler"));
    launch.run();
  }

  function test_launch_revertsWithUnknownConfig() public {
    _partialLaunch(false);
    vm.prank(admin1);
    scheduler.addConfig(_otherConfig);
    vm.expectRevert(bytes("on-chain config matches neither INITIAL_ORIGINATION_POOL_0_* nor the genesis config"));
    launch.run();
  }

  function test_launch_revertsWhenDailyReaddedAfterLaunchThisEpoch() public {
    launch.run();
    OriginationPoolConfig memory daily = launch.dailyConfig();
    vm.prank(admin1);
    scheduler.addConfig(daily);
    GenesisPoolLaunch again = _newLaunch();
    vm.expectRevert(bytes("genesis pool already deployed this epoch while the daily config is present"));
    again.run();
  }

  function test_launch_revertsWhenGenesisConfigSurvivedAnEpoch() public {
    _partialLaunch(true);
    scheduler.deployOriginationPool(launch.genesisConfigId());
    vm.warp(epochStart + 1 days + 5 minutes);
    vm.expectRevert(bytes("genesis config has a deployment from a previous epoch; remove it manually"));
    launch.run();
  }

  function test_launch_revertsAfterReopenWhenAlreadyLaunched() public {
    address pool = _launchAndReopen();
    // Day 21 is an epoch boundary: without the guard this would pass every other precondition
    vm.warp(epochStart + 21 days + 10 minutes);
    GenesisPoolLaunch again = _newLaunch();
    again.setGenesisPoolAddress(pool);
    vm.expectRevert(bytes(RELAUNCH_REVERT));
    again.run();
  }

  function test_launch_revertsAfterDeregistration() public {
    address pool = _launchAndDeregister();
    assertEq(scheduler.configLength(), 0, "setup: configs");
    GenesisPoolLaunch again = _newLaunch();
    again.setGenesisPoolAddress(pool);
    vm.expectRevert(bytes(RELAUNCH_REVERT));
    again.run();
  }

  function test_launch_revertsAfterDeregistrationAndReopen() public {
    address pool = _launchAndDeregister();
    _newReopen(pool, _dailyIdRaw()).run();
    GenesisPoolLaunch again = _newLaunch();
    again.setGenesisPoolAddress(pool);
    vm.expectRevert(bytes(RELAUNCH_REVERT));
    again.run();
  }

  function test_launch_forceRelaunchAfterDeregistration() public {
    address pool = _launchAndDeregister();
    address next = _schedulerPrediction();
    assertTrue(next != pool, "setup: same address as the first genesis pool");

    GenesisPoolLaunch again = _newLaunch();
    again.setGenesisPoolAddress(pool);
    again.setForceRelaunch(true);
    again.run();
    assertEq(uint8(again.launchState()), uint8(GenesisPoolLaunch.LaunchState.EMPTY), "launch state");
    _assertLaunched(address(again.genesisPool()), next);
    assertFalse(scheduler.isRegistered(pool), "first genesis pool re-registered");
  }

  function test_launch_resumesAfterFrontRunWithGenesisPoolAddressSet() public {
    _partialLaunch(true);
    OPoolConfigId genesisId = launch.genesisConfigId();
    address predicted = scheduler.predictOriginationPool(genesisId);
    vm.prank(makeAddr("roller"));
    scheduler.deployOriginationPool(genesisId);

    // This epoch's genesis pool is the one being resumed, not a relaunch
    launch.setGenesisPoolAddress(predicted);
    launch.run();
    assertEq(uint8(launch.launchState()), uint8(GenesisPoolLaunch.LaunchState.GENESIS_DEPLOYED), "launch state");
    _assertLaunched(address(launch.genesisPool()), predicted);
  }

  function test_launch_allowsUndeployedGenesisPoolAddress() public {
    address predicted = _schedulerPrediction();
    launch.setGenesisPoolAddress(predicted);
    launch.run();
    _assertLaunched(address(launch.genesisPool()), predicted);
  }

  function test_launch_revertsWhenSignerNotAdmin() public {
    vm.prank(admin2);
    IAccessControl(address(scheduler)).revokeRole(Roles.DEFAULT_ADMIN_ROLE, admin1);
    vm.expectRevert(bytes("ADMIN_ADDRESS_0 lacks DEFAULT_ADMIN_ROLE on the scheduler"));
    launch.run();
  }

  function test_launch_revertsWhenPaused() public {
    vm.startPrank(admin1);
    IAccessControl(address(scheduler)).grantRole(Roles.PAUSE_ROLE, admin1);
    scheduler.setPaused(true);
    vm.stopPrank();
    vm.expectRevert(bytes("scheduler is paused"));
    launch.run();
  }

  function test_launch_secondDeployReverts() public {
    launch.run();
    OPoolConfigId genesisId = launch.genesisConfigId();

    vm.expectRevert(
      abi.encodeWithSelector(IOriginationPoolSchedulerErrors.OriginationPoolConfigIdDoesNotExist.selector, genesisId)
    );
    scheduler.deployOriginationPool(genesisId);

    // Re-adding the genesis config in the same epoch hits the existing CREATE2 address
    OriginationPoolConfig memory genesis = launch.genesisConfig();
    vm.prank(admin1);
    scheduler.addConfig(genesis);
    vm.expectRevert(new bytes(0));
    scheduler.deployOriginationPool(genesisId);
  }

  function test_launch_poolAcceptsRolloverStyleDepositAfterConfigRemoved() public {
    launch.run();
    address pool = address(launch.genesisPool());
    assertEq(scheduler.configLength(), 0, "configs left on the scheduler");

    RolloverStyleDepositor depositor = new RolloverStyleDepositor();
    uint256 amount = _fundUsdx(address(depositor), 1_000e6);
    assertGt(amount, Constants.MINIMUM_ORIGINATION_DEPOSIT, "funding");

    // Late in the deposit phase, after the config is long gone
    vm.warp(epochStart + 21 days - 1);
    depositor.depositOriginationPool(scheduler, IERC20(address(deployAll.usdx())), pool, amount);
    assertEq(IERC20(pool).balanceOf(address(depositor)), amount, "receipt tokens");
    assertEq(IERC20(address(deployAll.usdx())).balanceOf(pool), amount, "pool USDX balance");

    vm.warp(epochStart + 21 days);
    assertEq(
      uint8(IOriginationPool(pool).currentPhase()), uint8(OriginationPoolPhase.DEPLOY), "pool not in DEPLOY at day 21"
    );
    assertTrue(scheduler.isRegistered(pool), "genesis pool deregistered");
  }

  // ---------------------------------------------------------------------------------------------
  // Genesis config bounds
  // ---------------------------------------------------------------------------------------------

  function _boundsRevert(OriginationPoolConfig memory config, string memory reason) internal {
    vm.expectRevert(bytes(reason));
    launch.validateGenesisConfig(config);
  }

  function test_validateGenesisConfig_edgesPass() public view {
    OriginationPoolConfig memory c = launch.genesisConfig();
    launch.validateGenesisConfig(c);
    c.depositPhaseDuration = 7 days;
    c.deployPhaseDuration = 1 days;
    c.defaultPoolLimit = 1_000_000e18;
    launch.validateGenesisConfig(c);
    c.depositPhaseDuration = 35 days;
    c.deployPhaseDuration = 30 days;
    c.defaultPoolLimit = 1e30;
    c.poolLimitGrowthRateBps = 10_000;
    c.poolMultiplierBps = 10_000;
    launch.validateGenesisConfig(c);
  }

  function test_validateGenesisConfig_outOfBoundsReverts() public {
    string memory deposit = "GENESIS_ORIGINATION_POOL_DEPOSIT_PHASE_DURATION out of bounds [7 days, 35 days]";
    string memory deploy = "GENESIS_ORIGINATION_POOL_DEPLOY_PHASE_DURATION out of bounds [1 day, 30 days]";
    string memory limit = "GENESIS_ORIGINATION_POOL_DEFAULT_POOL_LIMIT out of bounds [1_000_000e18, 1e30]";

    OriginationPoolConfig memory c = launch.genesisConfig();
    c.depositPhaseDuration = 7 days - 1;
    _boundsRevert(c, deposit);
    c.depositPhaseDuration = 35 days + 1;
    _boundsRevert(c, deposit);

    c = launch.genesisConfig();
    c.deployPhaseDuration = 1 days - 1;
    _boundsRevert(c, deploy);
    c.deployPhaseDuration = 30 days + 1;
    _boundsRevert(c, deploy);

    c = launch.genesisConfig();
    c.defaultPoolLimit = 1_000_000_000;
    _boundsRevert(c, limit);
    c.defaultPoolLimit = 1e30 + 1;
    _boundsRevert(c, limit);

    c = launch.genesisConfig();
    c.poolLimitGrowthRateBps = 10_001;
    _boundsRevert(c, "GENESIS_ORIGINATION_POOL_POOL_LIMIT_GROWTH_RATE_BPS above 10_000");

    c = launch.genesisConfig();
    c.poolMultiplierBps = 10_001;
    _boundsRevert(c, "GENESIS_ORIGINATION_POOL_POOL_MULTIPLIER_BPS above 10_000");
  }

  // ---------------------------------------------------------------------------------------------
  // Reopen
  // ---------------------------------------------------------------------------------------------

  function test_reopenDaily() public {
    address genesisPool = _launchAndReopen();
    OPoolConfigId dailyId = launch.dailyConfigId();
    OriginationPoolConfig memory daily = launch.dailyConfig();

    assertEq(scheduler.configLength(), 1, "configLength");
    assertEq(OPoolConfigId.unwrap(scheduler.configIdAt(0)), OPoolConfigId.unwrap(dailyId), "daily config id");
    assertTrue(scheduler.isRegistered(genesisPool), "genesis pool deregistered");

    // Growth history restarts: the first daily pool after reopening is sized at defaultPoolLimit
    IOriginationPool dailyPool = IOriginationPool(scheduler.deployOriginationPool(dailyId));
    assertEq(dailyPool.poolLimit(), daily.defaultPoolLimit, "daily pool limit");
    assertEq(uint8(dailyPool.currentPhase()), uint8(OriginationPoolPhase.DEPOSIT), "daily pool not in DEPOSIT");

    GenesisPoolReopenDaily again = _newReopen(genesisPool, _dailyIdRaw());
    vm.expectRevert(bytes("expected no configs on the scheduler"));
    again.run();
  }

  function test_reopen_revertsDuringDepositPhase() public {
    launch.run();
    address pool = address(launch.genesisPool());
    vm.warp(epochStart + 21 days - 1);
    GenesisPoolReopenDaily reopen = _newReopen(pool, _dailyIdRaw());
    vm.expectRevert(bytes("genesis pool is still in DEPOSIT"));
    reopen.run();
  }

  function test_reopen_revertsWithWrongExpectedId() public {
    launch.run();
    address pool = address(launch.genesisPool());
    vm.warp(epochStart + 21 days + 5 minutes);
    GenesisPoolReopenDaily reopen = _newReopen(pool, OPoolConfigId.unwrap(launch.genesisConfigId()));
    vm.expectRevert(bytes("daily config id does not match GENESIS_EXPECTED_DAILY_CONFIG_ID"));
    reopen.run();
  }

  function test_reopen_revertsWithoutExpectedId() public {
    launch.run();
    address pool = address(launch.genesisPool());
    vm.warp(epochStart + 21 days + 5 minutes);
    GenesisPoolReopenDaily reopen = _newReopen(pool, bytes32(0));
    vm.expectRevert(bytes("GENESIS_EXPECTED_DAILY_CONFIG_ID is not set"));
    reopen.run();
  }

  function test_reopen_revertsWhenConfigsPresent() public {
    launch.run();
    address pool = address(launch.genesisPool());
    vm.warp(epochStart + 21 days + 5 minutes);
    vm.prank(admin1);
    scheduler.addConfig(_otherConfig);
    GenesisPoolReopenDaily reopen = _newReopen(pool, _dailyIdRaw());
    vm.expectRevert(bytes("expected no configs on the scheduler"));
    reopen.run();
  }

  function test_reopen_revertsWithoutGenesisPoolAddress() public {
    launch.run();
    vm.warp(epochStart + 21 days + 5 minutes);
    GenesisPoolReopenDaily reopen = _newReopen(address(0), _dailyIdRaw());
    vm.expectRevert(bytes("GENESIS_POOL_ADDRESS is not set"));
    reopen.run();
  }

  function test_reopen_revertsWhenGenesisPoolAddressIsNotAPool() public {
    launch.run();
    vm.warp(epochStart + 21 days + 5 minutes);
    GenesisPoolReopenDaily reopen = _newReopen(address(scheduler), _dailyIdRaw());
    vm.expectRevert(bytes("GENESIS_POOL_ADDRESS is not an origination pool"));
    reopen.run();
  }

  function test_reopen_afterDeregistration() public {
    address pool = _launchAndDeregister();
    _newReopen(pool, _dailyIdRaw()).run();
    assertEq(scheduler.configLength(), 1, "configLength");
    assertEq(
      OPoolConfigId.unwrap(scheduler.configIdAt(0)), OPoolConfigId.unwrap(launch.dailyConfigId()), "daily config id"
    );
    assertFalse(scheduler.isRegistered(pool), "genesis pool re-registered");

    (bool registered, string memory state) = _newVerify(pool).run();
    assertFalse(registered, "verify registered");
    assertEq(state, "after reopen", "verify state");
  }

  // ---------------------------------------------------------------------------------------------
  // Verify
  // ---------------------------------------------------------------------------------------------

  function test_verify_afterLaunch() public {
    launch.run();
    (bool registered, string memory state) = _newVerify(address(launch.genesisPool())).run();
    assertTrue(registered, "verify registered");
    assertEq(state, "after launch", "verify state");
  }

  function test_verify_reportsDeregistered() public {
    address pool = _launchAndDeregister();
    (bool registered, string memory state) = _newVerify(pool).run();
    assertFalse(registered, "verify registered");
    assertEq(state, "after deregistration", "verify state");
  }

  function test_verify_reportsDeregisteredDuringDeposit() public {
    launch.run();
    address pool = address(launch.genesisPool());
    vm.prank(admin1);
    scheduler.updateRegistration(pool, false);
    (bool registered, string memory state) = _newVerify(pool).run();
    assertFalse(registered, "verify registered");
    assertEq(state, "after deregistration", "verify state");
  }

  function test_verify_afterReopen() public {
    address pool = _launchAndReopen();
    (bool registered, string memory state) = _newVerify(pool).run();
    assertTrue(registered, "verify registered");
    assertEq(state, "after reopen", "verify state");
  }

  function test_verify_revertsBeforeReopenWhenDepositOver() public {
    launch.run();
    address pool = address(launch.genesisPool());
    vm.warp(epochStart + 21 days + 5 minutes);
    GenesisPoolVerify verify = _newVerify(pool);
    vm.expectRevert(bytes("after launch: genesis pool is not in DEPOSIT"));
    verify.run();
  }

  function test_verify_revertsWithoutGenesisPoolAddress() public {
    launch.run();
    GenesisPoolVerify verify = _newVerify(address(0));
    vm.expectRevert(bytes("GENESIS_POOL_ADDRESS is not set"));
    verify.run();
  }

  function test_verify_revertsForDailyPool() public {
    address dailyPool = scheduler.deployOriginationPool(launch.dailyConfigId());
    launch.run();
    GenesisPoolVerify verify = _newVerify(dailyPool);
    vm.expectRevert(bytes("depositPhaseTimestamp is outside the launch epoch"));
    verify.run();
  }

  function test_verify_revertsWhenConfigsLeft() public {
    _partialLaunch(true);
    address pool = scheduler.deployOriginationPool(launch.genesisConfigId());
    GenesisPoolVerify verify = _newVerify(pool);
    vm.expectRevert(bytes("after reopen: the remaining config is not the daily config"));
    verify.run();
  }
}
