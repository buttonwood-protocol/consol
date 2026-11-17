// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployAllTest} from "./DeployAll.t.sol";
import {PayFirstUpgrade} from "../../script/ops/PayFirstUpgrade.s.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {GeneralManager} from "../../src/GeneralManager.sol";
import {OrderPool} from "../../src/OrderPool.sol";
import {MortgageParams} from "../../src/types/orders/MortgageParams.sol";
import {OrderAmounts} from "../../src/types/orders/OrderAmounts.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/// @dev The coverage profile compiles without the optimizer, so no GeneralManager build fits EIP-170 there
contract PayFirstUpgradeUnoptimized is PayFirstUpgrade {
  function maxRuntimeSize() public pure override returns (uint256) {
    return type(uint256).max;
  }
}

contract PayFirstUpgradeTest is DeployAllTest {
  bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  IGeneralManager public gm;
  IOrderPool public previousPool;
  address public previousImplementation;

  function testId() public pure override(DeployAllTest) returns (string memory) {
    return type(PayFirstUpgradeTest).name;
  }

  function setUp() public override(DeployAllTest) {
    DeployAllTest.setUp();
    deployAll.run();
    gm = deployAll.generalManager();
    previousPool = deployAll.orderPool();
    previousImplementation = _implementation();
    vm.prank(admin1);
    IAccessControl(address(gm)).grantRole(Roles.PAUSE_ROLE, admin1);
  }

  // ---------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------

  function _implementation() internal view returns (address) {
    return address(uint160(uint256(vm.load(address(gm), IMPLEMENTATION_SLOT))));
  }

  /// @dev Address book JSON built in memory: the on-disk file is shared with parallel tests in this suite.
  function _addressBookJson() internal view returns (string memory) {
    return string.concat(
      '{"generalManagerAddress":"',
      vm.toString(address(gm)),
      '","orderPoolAddress":"',
      vm.toString(address(previousPool)),
      '"}'
    );
  }

  function _fulfillers() internal view returns (address[] memory list) {
    list = new address[](2);
    list[0] = admin1;
    list[1] = admin2;
  }

  function _unoptimizedBuild() internal view returns (bool) {
    return keccak256(bytes(vm.envOr("FOUNDRY_PROFILE", string("")))) == keccak256("coverage");
  }

  /// @dev The script as shipped, except under the coverage profile where its size check cannot hold
  function _instance() internal returns (PayFirstUpgrade) {
    return _unoptimizedBuild() ? new PayFirstUpgradeUnoptimized() : new PayFirstUpgrade();
  }

  /// @dev Inputs are pinned through setters: vm.setEnv is process-wide across parallel tests.
  function _newScript(address[] memory fulfillers) internal returns (PayFirstUpgrade script) {
    script = _instance();
    script.setAddressBookJson(_addressBookJson());
    script.setFulfillers(fulfillers);
    script.setDeployment(address(0), address(0), address(0), false);
    script.setUp();
  }

  /// @dev A script instance for a later invocation, carrying what the deploy run logged
  function _continue(PayFirstUpgrade deployed, bool rollbackImplementation) internal returns (PayFirstUpgrade script) {
    script = _instance();
    script.setAddressBookJson(_addressBookJson());
    script.setFulfillers(_fulfillers());
    script.setDeployment(
      deployed.newImplementation(),
      address(deployed.newOrderPool()),
      deployed.previousImplementation(),
      rollbackImplementation
    );
    script.setUp();
  }

  function _deployed() internal returns (PayFirstUpgrade script) {
    script = _newScript(_fulfillers());
    script.run();
  }

  function _cutOver() internal returns (PayFirstUpgrade deployed) {
    deployed = _deployed();
    _continue(deployed, false).pause();
    _continue(deployed, false).cutover();
  }

  /// @dev Leaves an open order in a pool, as the GeneralManager would
  function _openOrder(IOrderPool pool) internal {
    MortgageParams memory mortgageParams;
    mortgageParams.collateral = address(deployAll.collateralTokens(0));
    OrderAmounts memory orderAmounts;
    uint256 gasFee = pool.gasFee();
    vm.deal(address(gm), gasFee);
    vm.prank(address(gm));
    pool.sendOrder{value: gasFee}(
      new address[](0), new uint256[](0), new address[](0), orderAmounts, mortgageParams, block.timestamp, false
    );
  }

  // ---------------------------------------------------------------------------------------------
  // Happy path
  // ---------------------------------------------------------------------------------------------

  function run() public override(DeployAllTest) {
    PayFirstUpgrade deployed = _deployed();
    IOrderPool newPool = deployed.newOrderPool();

    // The deploy run leaves the live stack untouched
    assertEq(gm.orderPool(), address(previousPool), "order pool untouched by the deploy run");
    assertEq(_implementation(), previousImplementation, "implementation untouched by the deploy run");
    assertEq(deployed.previousImplementation(), previousImplementation, "previous implementation recorded");
    assertFalse(gm.paused(), "not paused by the deploy run");

    // The new pool mirrors the previous one
    assertEq(newPool.generalManager(), address(gm), "general manager");
    assertEq(newPool.nativeWrapper(), previousPool.nativeWrapper(), "native wrapper");
    assertEq(newPool.gasFee(), previousPool.gasFee(), "gas fee");
    assertEq(newPool.maximumOrderDuration(), previousPool.maximumOrderDuration(), "maximum order duration");
    assertTrue(IAccessControl(address(newPool)).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin1), "admin");
    assertTrue(IAccessControl(address(newPool)).hasRole(Roles.FULFILLMENT_ROLE, admin1), "fulfiller 0");
    assertTrue(IAccessControl(address(newPool)).hasRole(Roles.FULFILLMENT_ROLE, admin2), "fulfiller 1");
    assertFalse(IAccessControl(address(newPool)).hasRole(Roles.FULFILLMENT_ROLE, deployerAddress), "only those listed");

    _continue(deployed, false).pause();
    assertTrue(gm.paused(), "paused");

    _continue(deployed, false).cutover();
    assertEq(_implementation(), deployed.newImplementation(), "implementation");
    assertEq(gm.orderPool(), address(newPool), "order pool");
    assertTrue(IAccessControl(address(gm)).hasRole(Roles.NFT_ROLE, address(newPool)), "new pool NFT_ROLE");
    assertFalse(IAccessControl(address(gm)).hasRole(Roles.NFT_ROLE, address(previousPool)), "previous pool NFT_ROLE");
    assertTrue(IAccessControl(address(gm)).hasRole(Roles.NFT_ROLE, gm.loanManager()), "loan manager NFT_ROLE");
    assertFalse(gm.paused(), "unpaused");

    _continue(deployed, false).verify();
  }

  function test_pauseIsNoopWhenAlreadyPaused() public {
    PayFirstUpgrade deployed = _deployed();
    _continue(deployed, false).pause();
    _continue(deployed, false).pause();
    assertTrue(gm.paused(), "still paused");
  }

  // ---------------------------------------------------------------------------------------------
  // Rollback
  // ---------------------------------------------------------------------------------------------

  function test_rollback_restoresThePreviousOrderPool() public {
    PayFirstUpgrade deployed = _cutOver();
    _continue(deployed, false).pause();
    _continue(deployed, false).rollback();

    assertEq(gm.orderPool(), address(previousPool), "order pool");
    assertTrue(IAccessControl(address(gm)).hasRole(Roles.NFT_ROLE, address(previousPool)), "previous pool NFT_ROLE");
    assertFalse(
      IAccessControl(address(gm)).hasRole(Roles.NFT_ROLE, address(deployed.newOrderPool())), "new pool NFT_ROLE"
    );
    assertEq(_implementation(), deployed.newImplementation(), "implementation kept");
    assertFalse(gm.paused(), "unpaused");
  }

  function test_rollback_alsoRestoresThePreviousImplementation() public {
    PayFirstUpgrade deployed = _cutOver();
    _continue(deployed, true).pause();
    _continue(deployed, true).rollback();

    assertEq(gm.orderPool(), address(previousPool), "order pool");
    assertEq(_implementation(), previousImplementation, "implementation restored");
    assertFalse(gm.paused(), "unpaused");
  }

  function test_rollback_revertsWhenNotPaused() public {
    PayFirstUpgrade deployed = _cutOver();
    PayFirstUpgrade script = _continue(deployed, false);
    vm.expectRevert("GeneralManager is not paused; run pause() first");
    script.rollback();
  }

  function test_rollback_revertsWithAnOpenOrderInTheNewPool() public {
    PayFirstUpgrade deployed = _cutOver();
    _openOrder(deployed.newOrderPool());
    _continue(deployed, false).pause();
    PayFirstUpgrade script = _continue(deployed, false);
    vm.expectRevert("an OrderPool being left still holds an open order");
    script.rollback();
  }

  // ---------------------------------------------------------------------------------------------
  // Guards
  // ---------------------------------------------------------------------------------------------

  function test_run_revertsWithoutFulfillers() public {
    PayFirstUpgrade script = _newScript(new address[](0));
    vm.expectRevert("PAY_FIRST_FULFILLERS is empty");
    script.run();
  }

  function test_run_revertsForAFulfillerWithoutTheRoleToday() public {
    address[] memory list = new address[](1);
    list[0] = makeAddr("stranger");
    PayFirstUpgrade script = _newScript(list);
    vm.expectRevert("PAY_FIRST_FULFILLERS has an address without FULFILLMENT_ROLE on the current OrderPool");
    script.run();
  }

  function test_run_revertsOnADuplicateFulfiller() public {
    address[] memory list = new address[](2);
    list[0] = admin1;
    list[1] = admin1;
    PayFirstUpgrade script = _newScript(list);
    vm.expectRevert("PAY_FIRST_FULFILLERS has a duplicate address");
    script.run();
  }

  function test_run_revertsWhenTheAdminLacksPauseRole() public {
    vm.prank(admin1);
    IAccessControl(address(gm)).revokeRole(Roles.PAUSE_ROLE, admin1);
    PayFirstUpgrade script = _newScript(_fulfillers());
    vm.expectRevert("ADMIN_ADDRESS_0 lacks PAUSE_ROLE on the GeneralManager");
    script.run();
  }

  function test_cutover_revertsWhenNotPaused() public {
    PayFirstUpgrade deployed = _deployed();
    PayFirstUpgrade script = _continue(deployed, false);
    vm.expectRevert("GeneralManager is not paused; run pause() first");
    script.cutover();
  }

  function test_cutover_revertsWithAnOpenOrderInThePreviousPool() public {
    PayFirstUpgrade deployed = _deployed();
    _openOrder(previousPool);
    _continue(deployed, false).pause();
    PayFirstUpgrade script = _continue(deployed, false);
    vm.expectRevert("an OrderPool being left still holds an open order");
    script.cutover();
  }

  function test_cutover_revertsWithoutADeployment() public {
    _newScript(_fulfillers()).pause();
    PayFirstUpgrade script = _newScript(_fulfillers());
    vm.expectRevert("PAY_FIRST_GENERAL_MANAGER_IMPLEMENTATION has no code");
    script.cutover();
  }

  function test_cutover_revertsWhenTheNewPoolIsConfiguredDifferently() public {
    PayFirstUpgrade deployed = _deployed();
    IOrderPool newPool = deployed.newOrderPool();
    uint256 gasFee = previousPool.gasFee() + 1;
    vm.prank(admin1);
    newPool.setGasFee(gasFee);
    _continue(deployed, false).pause();
    PayFirstUpgrade script = _continue(deployed, false);
    vm.expectRevert("new OrderPool gasFee differs");
    script.cutover();
  }

  function test_cutover_revertsWhenPointedAtThePreviousPool() public {
    PayFirstUpgrade deployed = _deployed();
    _continue(deployed, false).pause();

    PayFirstUpgrade script = _instance();
    script.setAddressBookJson(_addressBookJson());
    script.setFulfillers(_fulfillers());
    script.setDeployment(deployed.newImplementation(), address(previousPool), previousImplementation, false);
    script.setUp();
    vm.expectRevert("PAY_FIRST_ORDER_POOL is the previous OrderPool");
    script.cutover();
  }

  function test_cutover_revertsForANonUupsImplementation() public {
    PayFirstUpgrade deployed = _deployed();
    _continue(deployed, false).pause();

    PayFirstUpgrade script = _instance();
    script.setAddressBookJson(_addressBookJson());
    script.setFulfillers(_fulfillers());
    script.setDeployment(address(previousPool), address(deployed.newOrderPool()), previousImplementation, false);
    script.setUp();
    vm.expectRevert();
    script.cutover();
  }

  function test_verify_revertsBeforeTheCutover() public {
    PayFirstUpgrade deployed = _deployed();
    PayFirstUpgrade script = _continue(deployed, false);
    vm.expectRevert("GeneralManager is not on the new implementation");
    script.verify();
  }

  function test_verify_revertsAfterARollback() public {
    PayFirstUpgrade deployed = _cutOver();
    _continue(deployed, false).pause();
    _continue(deployed, false).rollback();
    PayFirstUpgrade script = _continue(deployed, false);
    vm.expectRevert("GeneralManager is not on the new OrderPool");
    script.verify();
  }

  function test_deployedImplementationFitsTheSizeLimit() public {
    PayFirstUpgrade deployed = _deployed();
    assertLe(deployed.newImplementation().code.length, deployed.maxRuntimeSize(), "EIP-170");
    assertEq(deployed.maxRuntimeSize(), _unoptimizedBuild() ? type(uint256).max : 24_576, "limit");
    assertGt(address(new GeneralManager()).code.length, 0, "deployable");
    assertGt(address(new OrderPool(previousPool.nativeWrapper(), address(gm), admin1)).code.length, 0, "deployable");
  }
}
