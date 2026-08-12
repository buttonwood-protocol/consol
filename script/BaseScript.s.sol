// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract BaseScript is Script {
  address public deployerAddress;
  uint256 public deployerPrivateKey;
  address[] public admins;
  bool public isTest;
  bool public isTestnet;
  /// @notice True when the deployer address is also one of the configured admin addresses.
  bool public deployerIsAdmin;

  function setUp() public virtual {
    deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
    deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    getAdmins();
    isTest = vm.envBool("IS_TEST");
    isTestnet = vm.envBool("IS_TESTNET");
    for (uint256 i = 0; i < admins.length; i++) {
      if (admins[i] == deployerAddress) {
        deployerIsAdmin = true;
        break;
      }
    }

    require(deployerAddress == vm.addr(deployerPrivateKey), "Deployer address and private key do not match");
  }

  function getAdmins() public {
    uint256 adminLength = vm.envUint("ADMIN_LENGTH");
    for (uint256 i = 0; i < adminLength; i++) {
      admins.push(vm.envAddress(string.concat("ADMIN_ADDRESS_", vm.toString(i))));
    }
  }

  /**
   * @notice Renounces `role` from the deployer on `target`, unless the deployer is a configured admin.
   * @dev Renouncing while the deployer is also in `admins[]` would silently remove an intended admin
   * (this is how the chain-998 stack was bricked). Skips are logged in the deploy output.
   * @param target The access-controlled contract to renounce the role on
   * @param role The role to renounce from the deployer
   */
  function renounceUnlessAdmin(address target, bytes32 role) internal {
    if (!deployerIsAdmin) {
      IAccessControl(target).renounceRole(role, deployerAddress);
    } else {
      console.log("Skipping renounce (deployer is a configured admin):", target);
    }
  }

  function run() public virtual {
    vm.startBroadcast(deployerPrivateKey);
    vm.stopBroadcast();
  }
}
