// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployAllTest} from "./DeployAll.t.sol";
import {GenesisPoolLaunch} from "../../script/ops/GenesisPoolLaunch.s.sol";
import {GenesisPoolReopenDaily} from "../../script/ops/GenesisPoolReopenDaily.s.sol";
import {GenesisPoolBase} from "../../script/ops/GenesisPoolBase.s.sol";
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
import {OPoolConfigId} from "../../src/types/OPoolConfigId.sol";
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
  GenesisPoolLaunch public launch;
  IOriginationPoolScheduler public scheduler;
  uint256 public epochStart;

  function testId() public pure override(DeployAllTest) returns (string memory) {
    return type(GenesisPoolTest).name;
  }

  function setUp() public override(DeployAllTest) {
    DeployAllTest.setUp();
    deployAll.run();
    scheduler = deployAll.originationPoolScheduler();

    // Mirror the live chain: the daily config (config 0) is the only config
    OriginationPoolConfig memory config2 = scheduler.configAt(2);
    OriginationPoolConfig memory config1 = scheduler.configAt(1);
    vm.startPrank(admin1);
    scheduler.removeConfig(config2);
    scheduler.removeConfig(config1);
    vm.stopPrank();
    assertEq(scheduler.configLength(), 1, "setup: expected only the daily config");

    // Five minutes past the next 12:00 UTC epoch boundary
    epochStart = block.timestamp - ((block.timestamp - Constants.EPOCH_OFFSET) % Constants.EPOCH_DURATION)
      + Constants.EPOCH_DURATION;
    vm.warp(epochStart + 5 minutes);

    launch = _newLaunch();
  }

  /// @dev Address book JSON built in memory: the on-disk file is shared with parallel tests in this suite.
  function _addressBookJson() internal view returns (string memory) {
    return string.concat(
      '{"consolAddress":"',
      vm.toString(address(deployAll.consol())),
      '","originationPoolSchedulerAddress":"',
      vm.toString(address(scheduler)),
      '","usdxAddress":"',
      vm.toString(address(deployAll.usdx())),
      '"}'
    );
  }

  function _configure(GenesisPoolBase script) internal {
    script.setAddressBookJson(_addressBookJson());
    script.setUp();
  }

  function _newLaunch() internal returns (GenesisPoolLaunch script) {
    script = new GenesisPoolLaunch();
    _configure(script);
  }

  function _newReopen() internal returns (GenesisPoolReopenDaily script) {
    script = new GenesisPoolReopenDaily();
    _configure(script);
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

  function run() public override(DeployAllTest) {
    OPoolConfigId dailyId = launch.dailyConfigId();
    assertEq(
      OPoolConfigId.unwrap(scheduler.configIdAt(0)),
      OPoolConfigId.unwrap(dailyId),
      "daily config rebuilt from env does not match the deployed config"
    );

    launch.run();
    IOriginationPool pool = launch.genesisPool();
    OriginationPoolConfig memory genesis = launch.genesisConfig();

    assertEq(address(pool), launch.predictedPool(), "pool address differs from prediction");
    assertTrue(scheduler.isRegistered(address(pool)), "genesis pool not registered");
    assertEq(uint8(pool.currentPhase()), uint8(OriginationPoolPhase.DEPOSIT), "genesis pool not in DEPOSIT");
    assertEq(scheduler.configLength(), 0, "configs left on the scheduler");

    assertEq(pool.depositPhaseTimestamp(), epochStart + 5 minutes, "depositPhaseTimestamp");
    assertEq(pool.deployPhaseTimestamp(), epochStart + 21 days, "deployPhaseTimestamp");
    assertEq(pool.redemptionPhaseTimestamp(), epochStart + 35 days, "redemptionPhaseTimestamp");
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
    assertEq(scheduler.lastConfigDeployment(launch.genesisConfigId()).epoch, 0, "genesis deployment record kept");
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

  function test_launch_revertsLateInEpoch() public {
    vm.warp(epochStart + 1 hours + 1);
    vm.expectRevert(bytes("too long after the 12:00 UTC epoch boundary; see GENESIS_MAX_EPOCH_ELAPSED"));
    launch.run();
  }

  function test_launch_revertsWithExtraConfig() public {
    OriginationPoolConfig memory genesis = launch.genesisConfig();
    vm.prank(admin1);
    scheduler.addConfig(genesis);
    vm.expectRevert(bytes("expected exactly one config on the scheduler"));
    launch.run();
  }

  function test_launch_revertsWhenSignerNotAdmin() public {
    vm.prank(admin2);
    IAccessControl(address(scheduler)).revokeRole(Roles.DEFAULT_ADMIN_ROLE, admin1);
    vm.expectRevert(bytes("ADMIN_ADDRESS_0 lacks DEFAULT_ADMIN_ROLE on the scheduler"));
    launch.run();
  }

  function test_reopenDaily() public {
    launch.run();
    address genesisPool = address(launch.genesisPool());
    OPoolConfigId dailyId = launch.dailyConfigId();
    OriginationPoolConfig memory daily = launch.dailyConfig();

    vm.warp(epochStart + 21 days + 5 minutes);
    GenesisPoolReopenDaily reopen = _newReopen();
    reopen.run();

    assertEq(scheduler.configLength(), 1, "configLength");
    assertEq(OPoolConfigId.unwrap(scheduler.configIdAt(0)), OPoolConfigId.unwrap(dailyId), "daily config id");
    assertTrue(scheduler.isRegistered(genesisPool), "genesis pool deregistered");

    // Growth history restarts: the first daily pool after reopening is sized at defaultPoolLimit
    IOriginationPool dailyPool = IOriginationPool(scheduler.deployOriginationPool(dailyId));
    assertEq(dailyPool.poolLimit(), daily.defaultPoolLimit, "daily pool limit");
    assertEq(uint8(dailyPool.currentPhase()), uint8(OriginationPoolPhase.DEPOSIT), "daily pool not in DEPOSIT");

    GenesisPoolReopenDaily again = _newReopen();
    vm.expectRevert(bytes("daily config is already on the scheduler"));
    again.run();
  }
}
