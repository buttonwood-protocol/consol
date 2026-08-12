// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DeployAllTest} from "./DeployAll.t.sol";
import {DeployAll} from "../../script/DeployAll.s.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/**
 * @notice Shared scaffolding for the renounce-guard regression tests. Rebuilds the DeployAll script
 * with specific env overrides and verifies the script actually read the intended configuration.
 * @dev vm.setEnv writes process-global state and forge runs tests in parallel, so env overrides here
 * are visible to every other suite mid-run. Two rules keep that sound:
 * 1. Never write a divergent value for a variable another suite depends on (ADMIN_ADDRESS_0/1 stay
 *    untouched; the deployer is added as an EXTRA admin via ADMIN_LENGTH=3 + ADMIN_ADDRESS_2, and a
 *    suite that happens to read ADMIN_LENGTH=3 deploys with [admin1, admin2, deployer], which keeps
 *    every existing assumption intact).
 * 2. Verify what the script actually read and retry, because parallel suites rewrite these variables
 *    between our setEnv and the script's env read.
 */
abstract contract DeployAllRoleInvariantsBase is DeployAllTest {
  /**
   * @param deployerInAdmins Whether the deployer address should be part of the configured admins
   */
  function rebuildDeployAll(bool deployerInAdmins) internal {
    // ADMIN_ADDRESS_2 must be set BEFORE ADMIN_LENGTH can ever read as 3, so any parallel suite that
    // observes the transient ADMIN_LENGTH=3 always finds ADMIN_ADDRESS_2 defined. It is never unset.
    vm.setEnv("ADMIN_ADDRESS_2", vm.toString(deployerAddress));
    for (uint256 attempt = 0; attempt < 20; attempt++) {
      deployAll = new DeployAll();
      deployAll.setTestAddressesFileSuffix(testId());
      vm.setEnv("ADMIN_LENGTH", deployerInAdmins ? "3" : "2");
      deployAll.setUp();
      // Restore the scaffolding default so parallel suites read their expected configuration
      vm.setEnv("ADMIN_LENGTH", "2");
      if (
        deployAll.admins(0) == admin1 && deployAll.admins(1) == admin2
          && deployAll.deployerIsAdmin() == deployerInAdmins
      ) {
        return;
      }
    }
    revert("Failed to build DeployAll with the intended env configuration");
  }

  function accessControlledTargets() internal view returns (address[4] memory targets) {
    targets = [
      address(deployAll.usdx()),
      address(deployAll.consol()),
      address(deployAll.generalManager()),
      address(deployAll.originationPoolScheduler())
    ];
  }

  function targetLabels() internal pure returns (string[4] memory labels) {
    labels = ["USDX", "Consol", "GeneralManager", "OriginationPoolScheduler"];
  }
}

/**
 * @notice Regression test for the deploy-script renounce guard: a deployer that is also a configured
 * admin must NOT strip itself of DEFAULT_ADMIN_ROLE at the end of the deploy. The unconditional
 * renounce previously removed the intended admin and permanently locked the admin functions
 * (including UUPS upgrades of the GeneralManager proxy) of every deployed contract.
 */
contract DeployAllDeployerIsAdminTest is DeployAllRoleInvariantsBase {
  function testId() public pure override returns (string memory) {
    return type(DeployAllDeployerIsAdminTest).name;
  }

  function setUp() public override {
    super.setUp();
    // Reconfigure the environment so the deployer is also a configured admin
    rebuildDeployAll(true);
  }

  function test_deployerKeepsAdminRoleWhenConfiguredAsAdmin() public {
    // Use a dedicated addresses file so this test never races the inherited test_run on the same path
    deployAll.setTestAddressesFileSuffix(string.concat(testId(), "Roles"));
    run();

    address[4] memory targets = accessControlledTargets();
    string[4] memory labels = targetLabels();

    for (uint256 i = 0; i < targets.length; i++) {
      assertTrue(
        IAccessControl(targets[i]).hasRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress),
        string.concat(labels[i], ": deployer (configured as admin) lost DEFAULT_ADMIN_ROLE")
      );
      assertTrue(
        IAccessControl(targets[i]).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin1),
        string.concat(labels[i], ": first admin missing DEFAULT_ADMIN_ROLE")
      );
      assertTrue(
        IAccessControl(targets[i]).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin2),
        string.concat(labels[i], ": second admin missing DEFAULT_ADMIN_ROLE")
      );
    }

    // Remove the file that was created by the deployAll script
    vm.removeFile(deployAll.getPath());
  }
}

/**
 * @notice Verifies the production semantics: with a deployer that is NOT a
 * configured admin, the deployer walks away holding no roles while the configured admins hold
 * DEFAULT_ADMIN_ROLE everywhere.
 */
contract DeployAllRenounceDeployerTest is DeployAllRoleInvariantsBase {
  function testId() public pure override returns (string memory) {
    return type(DeployAllRenounceDeployerTest).name;
  }

  function setUp() public override {
    super.setUp();
    // Deployer is NOT an admin, so the deploy renounces its roles
    rebuildDeployAll(false);
  }

  function test_deployerHoldsNoRolesAfterRenounce() public {
    // Use a dedicated addresses file so this test never races the inherited test_run on the same path
    deployAll.setTestAddressesFileSuffix(string.concat(testId(), "Roles"));
    run();

    address[4] memory targets = accessControlledTargets();
    string[4] memory labels = targetLabels();

    for (uint256 i = 0; i < targets.length; i++) {
      assertFalse(
        IAccessControl(targets[i]).hasRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress),
        string.concat(labels[i], ": deployer still holds DEFAULT_ADMIN_ROLE")
      );
      assertTrue(
        IAccessControl(targets[i]).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin1),
        string.concat(labels[i], ": first admin missing DEFAULT_ADMIN_ROLE")
      );
      assertTrue(
        IAccessControl(targets[i]).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin2),
        string.concat(labels[i], ": second admin missing DEFAULT_ADMIN_ROLE")
      );
    }

    // The temporary SUPPORTED_TOKEN_ROLE grants must be renounced as well
    assertFalse(
      IAccessControl(address(deployAll.usdx())).hasRole(Roles.SUPPORTED_TOKEN_ROLE, deployerAddress),
      "USDX: deployer still holds SUPPORTED_TOKEN_ROLE"
    );
    assertFalse(
      IAccessControl(address(deployAll.consol())).hasRole(Roles.SUPPORTED_TOKEN_ROLE, deployerAddress),
      "Consol: deployer still holds SUPPORTED_TOKEN_ROLE"
    );

    // Remove the file that was created by the deployAll script
    vm.removeFile(deployAll.getPath());
  }
}
