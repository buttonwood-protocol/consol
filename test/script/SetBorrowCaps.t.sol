// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {DeployAllTest} from "./DeployAll.t.sol";
import {SetBorrowCaps} from "../../script/ops/SetBorrowCaps.s.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IGeneralManagerEvents} from "../../src/interfaces/IGeneralManager/IGeneralManagerEvents.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../../src/libraries/Roles.sol";

contract SetBorrowCapsTest is DeployAllTest {
  uint256 internal constant INITIAL_MIN = 100e18;
  uint256 internal constant INITIAL_MAX = 1_000_000e18;
  uint256 internal constant TARGET_MAX = 10_000e18;

  IGeneralManager public gm;
  address public collateral0;
  address public collateral1;

  function testId() public pure override(DeployAllTest) returns (string memory) {
    return type(SetBorrowCapsTest).name;
  }

  function setUp() public override(DeployAllTest) {
    DeployAllTest.setUp();
    deployAll.run();
    gm = deployAll.generalManager();
    collateral0 = address(deployAll.collateralTokens(0));
    collateral1 = address(deployAll.collateralTokens(1));
    assertEq(gm.maximumCap(collateral0), INITIAL_MAX, "setup: max 0");
    assertEq(gm.maximumCap(collateral1), INITIAL_MAX, "setup: max 1");
    assertEq(gm.minimumCap(collateral0), INITIAL_MIN, "setup: min 0");
  }

  // ---------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------

  /// @dev Address book JSON built in memory: the on-disk file is shared with parallel tests in this suite.
  function _addressBookJson(address[] memory list) internal view returns (string memory json) {
    json = string.concat('{"generalManagerAddress":"', vm.toString(address(gm)), '","collateralAddresses":[');
    for (uint256 i = 0; i < list.length; i++) {
      json = string.concat(json, i == 0 ? '"' : ',"', vm.toString(list[i]), '"');
    }
    json = string.concat(json, "]}");
  }

  function _book() internal view returns (address[] memory list) {
    list = new address[](2);
    list[0] = collateral0;
    list[1] = collateral1;
  }

  function _none() internal pure returns (address[] memory) {
    return new address[](0);
  }

  function _one(address a) internal pure returns (address[] memory list) {
    list = new address[](1);
    list[0] = a;
  }

  /// @dev Inputs are pinned through setInputs: vm.setEnv is process-wide across parallel tests.
  function _newScript(address[] memory book, uint256 maxCap, bool applyMin, uint256 minCap, address[] memory filter)
    internal
    returns (SetBorrowCaps script)
  {
    script = new SetBorrowCaps();
    script.setAddressBookJson(_addressBookJson(book));
    script.setInputs(maxCap, applyMin, minCap, filter);
    script.setUp();
  }

  function _newScript(uint256 maxCap) internal returns (SetBorrowCaps) {
    return _newScript(_book(), maxCap, false, 0, _none());
  }

  function _countCapEvents(Vm.Log[] memory logs) internal view returns (uint256 count) {
    for (uint256 i = 0; i < logs.length; i++) {
      if (
        logs[i].emitter == address(gm)
          && (logs[i].topics[0] == IGeneralManagerEvents.MaximumCapSet.selector
            || logs[i].topics[0] == IGeneralManagerEvents.MinimumCapSet.selector)
      ) {
        count++;
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // Happy path
  // ---------------------------------------------------------------------------------------------

  function run() public override(DeployAllTest) {
    SetBorrowCaps script = _newScript(TARGET_MAX);
    assertEq(script.collateralCount(), 2, "collateral count");

    vm.expectEmit(true, false, false, true, address(gm));
    emit IGeneralManagerEvents.MaximumCapSet(collateral0, TARGET_MAX);
    vm.expectEmit(true, false, false, true, address(gm));
    emit IGeneralManagerEvents.MaximumCapSet(collateral1, TARGET_MAX);
    script.run();

    assertEq(script.sentCount(), 2, "sent");
    assertEq(gm.maximumCap(collateral0), TARGET_MAX, "max 0");
    assertEq(gm.maximumCap(collateral1), TARGET_MAX, "max 1");
    assertEq(gm.minimumCap(collateral0), INITIAL_MIN, "min 0 untouched");
    assertEq(gm.minimumCap(collateral1), INITIAL_MIN, "min 1 untouched");
    script.verify();
  }

  function test_rerunIsNoop() public {
    _newScript(TARGET_MAX).run();

    SetBorrowCaps again = _newScript(TARGET_MAX);
    vm.recordLogs();
    again.run();
    assertEq(_countCapEvents(vm.getRecordedLogs()), 0, "cap events on re-run");
    assertEq(again.sentCount(), 0, "sent on re-run");
    again.verify();
  }

  function test_resumesAfterPartialBroadcast() public {
    vm.prank(admin1);
    gm.setMaximumCap(collateral0, TARGET_MAX);

    SetBorrowCaps script = _newScript(TARGET_MAX);
    vm.recordLogs();
    script.run();
    assertEq(_countCapEvents(vm.getRecordedLogs()), 1, "cap events");
    assertEq(script.sentCount(), 1, "sent");
    assertEq(gm.maximumCap(collateral1), TARGET_MAX, "max 1");
  }

  function test_appliesMinimumCap() public {
    SetBorrowCaps script = _newScript(_book(), TARGET_MAX, true, 250e18, _none());
    script.run();
    assertEq(script.sentCount(), 4, "sent");
    assertEq(gm.minimumCap(collateral0), 250e18, "min 0");
    assertEq(gm.minimumCap(collateral1), 250e18, "min 1");
    assertEq(gm.maximumCap(collateral0), TARGET_MAX, "max 0");

    // Only the minimum differs on the second run
    SetBorrowCaps again = _newScript(_book(), TARGET_MAX, true, 300e18, _none());
    again.run();
    assertEq(again.sentCount(), 2, "sent on second run");
    assertEq(gm.minimumCap(collateral1), 300e18, "min 1 second run");
  }

  function test_minimumCapEqualToCurrentIsUnchanged() public {
    SetBorrowCaps script = _newScript(_book(), TARGET_MAX, true, INITIAL_MIN, _none());
    script.run();
    assertEq(script.sentCount(), 2, "only the maximums are sent");
  }

  function test_filterRestrictsCollaterals() public {
    SetBorrowCaps script = _newScript(_book(), TARGET_MAX, false, 0, _one(collateral1));
    assertEq(script.collateralCount(), 1, "collateral count");
    script.run();
    assertEq(script.sentCount(), 1, "sent");
    assertEq(gm.maximumCap(collateral0), INITIAL_MAX, "max 0 untouched");
    assertEq(gm.maximumCap(collateral1), TARGET_MAX, "max 1");
  }

  // ---------------------------------------------------------------------------------------------
  // Guards
  // ---------------------------------------------------------------------------------------------

  function test_validateCaps_bounds() public {
    SetBorrowCaps script = new SetBorrowCaps();
    script.validateCaps(100e18, false, 0);
    script.validateCaps(1_000_000e18, true, 1_000_000e18 - 1);

    vm.expectRevert(bytes("BORROW_MAX_CAP out of bounds [100e18, 1_000_000e18]"));
    script.validateCaps(100e18 - 1, false, 0);
    vm.expectRevert(bytes("BORROW_MAX_CAP out of bounds [100e18, 1_000_000e18]"));
    script.validateCaps(1_000_000e18 + 1, false, 0);
    vm.expectRevert(bytes("BORROW_MAX_CAP out of bounds [100e18, 1_000_000e18]"));
    script.validateCaps(10_000, false, 0);
    vm.expectRevert(bytes("BORROW_MIN_CAP must be below BORROW_MAX_CAP"));
    script.validateCaps(TARGET_MAX, true, TARGET_MAX);
  }

  function test_setUp_revertsOutOfBounds() public {
    SetBorrowCaps script = new SetBorrowCaps();
    script.setAddressBookJson(_addressBookJson(_book()));
    script.setInputs(2_000_000e18, false, 0, _none());
    vm.expectRevert(bytes("BORROW_MAX_CAP out of bounds [100e18, 1_000_000e18]"));
    script.setUp();

    script.setInputs(TARGET_MAX, true, TARGET_MAX + 1, _none());
    vm.expectRevert(bytes("BORROW_MIN_CAP must be below BORROW_MAX_CAP"));
    script.setUp();
  }

  function test_revertsWhenOnChainMinimumIsNotBelowTarget() public {
    SetBorrowCaps script = _newScript(INITIAL_MIN);
    vm.expectRevert(bytes("on-chain minimumCap is not below BORROW_MAX_CAP; set BORROW_MIN_CAP"));
    script.run();
  }

  function test_revertsForNonAdmin() public {
    vm.prank(admin1);
    IAccessControl(address(gm)).renounceRole(Roles.DEFAULT_ADMIN_ROLE, admin1);

    SetBorrowCaps script = _newScript(TARGET_MAX);
    vm.expectRevert(bytes("ADMIN_ADDRESS_0 lacks DEFAULT_ADMIN_ROLE on the GeneralManager"));
    script.run();
    vm.expectRevert(bytes("ADMIN_ADDRESS_0 lacks DEFAULT_ADMIN_ROLE on the GeneralManager"));
    script.verify();
    assertEq(gm.maximumCap(collateral0), INITIAL_MAX, "max 0 untouched");
  }

  function test_revertsForUnregisteredCollateral() public {
    address[] memory book = new address[](3);
    book[0] = collateral0;
    book[1] = makeAddr("not a collateral");
    book[2] = collateral1;
    SetBorrowCaps script = _newScript(book, TARGET_MAX, false, 0, _none());
    vm.expectRevert(bytes("collateral has no price oracle on the GeneralManager"));
    script.run();
    assertEq(gm.maximumCap(collateral0), INITIAL_MAX, "max 0 untouched");
  }

  function test_revertsForEmptyAddressBook() public {
    SetBorrowCaps script = new SetBorrowCaps();
    script.setAddressBookJson(_addressBookJson(_none()));
    script.setInputs(TARGET_MAX, false, 0, _none());
    vm.expectRevert(bytes("address book has no collateralAddresses"));
    script.setUp();
  }

  function test_filterRevertsForUnknownAddress() public {
    SetBorrowCaps script = new SetBorrowCaps();
    script.setAddressBookJson(_addressBookJson(_book()));
    script.setInputs(TARGET_MAX, false, 0, _one(makeAddr("stranger")));
    vm.expectRevert(bytes("COLLATERAL_FILTER has an address not in collateralAddresses"));
    script.setUp();
  }

  function test_filterRevertsForDuplicate() public {
    address[] memory filter = new address[](2);
    filter[0] = collateral0;
    filter[1] = collateral0;
    SetBorrowCaps script = new SetBorrowCaps();
    script.setAddressBookJson(_addressBookJson(_book()));
    script.setInputs(TARGET_MAX, false, 0, filter);
    vm.expectRevert(bytes("COLLATERAL_FILTER has a duplicate address"));
    script.setUp();
  }

  function test_verifyRevertsBeforeRun() public {
    SetBorrowCaps script = _newScript(TARGET_MAX);
    vm.expectRevert(bytes("maximumCap differs from BORROW_MAX_CAP"));
    script.verify();
  }

  // ---------------------------------------------------------------------------------------------
  // Env parsing (the only test in this suite that writes these variables)
  // ---------------------------------------------------------------------------------------------

  function test_readsInputsFromEnv() public {
    vm.setEnv("BORROW_MAX_CAP", "10000000000000000000000");
    vm.setEnv("BORROW_MIN_CAP", "200000000000000000000");
    vm.setEnv("COLLATERAL_FILTER", string.concat(vm.toString(collateral1), ",", vm.toString(collateral0)));
    SetBorrowCaps script = new SetBorrowCaps();
    script.setAddressBookJson(_addressBookJson(_book()));
    script.setUp();
    assertEq(script.maxCap(), TARGET_MAX, "maxCap");
    assertTrue(script.applyMin(), "applyMin");
    assertEq(script.minCap(), 200e18, "minCap");
    assertEq(script.collateralCount(), 2, "collateral count");
    assertEq(script.collaterals(0), collateral1, "filter order");
    script.run();
    assertEq(gm.maximumCap(collateral0), TARGET_MAX, "max 0");
    assertEq(gm.minimumCap(collateral1), 200e18, "min 1");
  }
}
