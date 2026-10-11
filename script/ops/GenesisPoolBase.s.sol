// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IOriginationPoolScheduler} from "../../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {OriginationPoolConfig} from "../../src/types/OriginationPoolConfig.sol";
import {OPoolConfigId, OPoolConfigIdLibrary} from "../../src/types/OPoolConfigId.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/**
 * @title GenesisPoolBase
 * @notice Shared configuration for the genesis origination pool ops scripts.
 * @dev Addresses come from the chain's address book (addresses/addresses-<chainId>.json).
 *      The daily config is rebuilt from the INITIAL_ORIGINATION_POOL_0_* vars DeployAll added it with.
 *      The genesis config reads GENESIS_ORIGINATION_POOL_* and defaults to the launch parameters.
 *      The signer is ADMIN_ADDRESS_0, which must hold DEFAULT_ADMIN_ROLE on the scheduler.
 */
abstract contract GenesisPoolBase is Script {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  IOriginationPoolScheduler public scheduler;
  address public admin;
  string internal _addressBookJson;

  OriginationPoolConfig internal _dailyConfig;
  OriginationPoolConfig internal _genesisConfig;

  /// @notice Supplies the address book JSON directly instead of reading the chain's file.
  function setAddressBookJson(string memory json) external {
    _addressBookJson = json;
  }

  function setUp() public virtual {
    string memory json = bytes(_addressBookJson).length != 0
      ? _addressBookJson
      : vm.readFile(string.concat(vm.projectRoot(), "/addresses/addresses-", vm.toString(block.chainid), ".json"));
    scheduler = IOriginationPoolScheduler(vm.parseJsonAddress(json, ".originationPoolSchedulerAddress"));
    address consol = vm.parseJsonAddress(json, ".consolAddress");
    address usdx = vm.parseJsonAddress(json, ".usdxAddress");
    admin = vm.envAddress("ADMIN_ADDRESS_0");

    _dailyConfig = OriginationPoolConfig({
      namePrefix: vm.envString("INITIAL_ORIGINATION_POOL_0_NAME_PREFIX"),
      symbolPrefix: vm.envString("INITIAL_ORIGINATION_POOL_0_SYMBOL_PREFIX"),
      consol: consol,
      usdx: usdx,
      depositPhaseDuration: SafeCast.toUint32(vm.envUint("INITIAL_ORIGINATION_POOL_0_DEPOSIT_PHASE_DURATION")),
      deployPhaseDuration: SafeCast.toUint32(vm.envUint("INITIAL_ORIGINATION_POOL_0_DEPLOY_PHASE_DURATION")),
      defaultPoolLimit: vm.envUint("INITIAL_ORIGINATION_POOL_0_DEFAULT_POOL_LIMIT"),
      poolLimitGrowthRateBps: SafeCast.toUint16(vm.envUint("INITIAL_ORIGINATION_POOL_0_POOL_LIMIT_GROWTH_RATE_BPS")),
      poolMultiplierBps: SafeCast.toUint16(vm.envUint("INITIAL_ORIGINATION_POOL_0_POOL_MULTIPLIER_BPS"))
    });

    _genesisConfig = OriginationPoolConfig({
      namePrefix: vm.envOr("GENESIS_ORIGINATION_POOL_NAME_PREFIX", string("Genesis Origination Pool")),
      symbolPrefix: vm.envOr("GENESIS_ORIGINATION_POOL_SYMBOL_PREFIX", string("GEN-OP")),
      consol: consol,
      usdx: usdx,
      depositPhaseDuration: SafeCast.toUint32(
        vm.envOr("GENESIS_ORIGINATION_POOL_DEPOSIT_PHASE_DURATION", uint256(21 days))
      ),
      deployPhaseDuration: SafeCast.toUint32(
        vm.envOr("GENESIS_ORIGINATION_POOL_DEPLOY_PHASE_DURATION", uint256(14 days))
      ),
      defaultPoolLimit: vm.envOr("GENESIS_ORIGINATION_POOL_DEFAULT_POOL_LIMIT", uint256(1_000_000_000e18)),
      poolLimitGrowthRateBps: SafeCast.toUint16(
        vm.envOr("GENESIS_ORIGINATION_POOL_POOL_LIMIT_GROWTH_RATE_BPS", uint256(0))
      ),
      poolMultiplierBps: SafeCast.toUint16(vm.envOr("GENESIS_ORIGINATION_POOL_POOL_MULTIPLIER_BPS", uint256(0)))
    });
  }

  function dailyConfig() public view returns (OriginationPoolConfig memory) {
    return _dailyConfig;
  }

  function genesisConfig() public view returns (OriginationPoolConfig memory) {
    return _genesisConfig;
  }

  function dailyConfigId() public view returns (OPoolConfigId) {
    return dailyConfig().toId();
  }

  function genesisConfigId() public view returns (OPoolConfigId) {
    return genesisConfig().toId();
  }

  /// @notice Start of the current scheduler epoch (the most recent 12:00 UTC boundary).
  function currentEpochStart() public view returns (uint256) {
    return block.timestamp - ((block.timestamp - Constants.EPOCH_OFFSET) % Constants.EPOCH_DURATION);
  }

  function _hasConfig(OPoolConfigId id) internal view returns (bool) {
    uint256 length = scheduler.configLength();
    for (uint256 i = 0; i < length; i++) {
      if (OPoolConfigId.unwrap(scheduler.configIdAt(i)) == OPoolConfigId.unwrap(id)) {
        return true;
      }
    }
    return false;
  }

  function _requireAdmin() internal view {
    require(
      IAccessControl(address(scheduler)).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin),
      "ADMIN_ADDRESS_0 lacks DEFAULT_ADMIN_ROLE on the scheduler"
    );
  }

  function _logConfig(string memory label, OriginationPoolConfig memory config) internal pure {
    console.log(label);
    console.log("  id:", vm.toString(OPoolConfigId.unwrap(config.toId())));
    console.log("  namePrefix:", config.namePrefix);
    console.log("  symbolPrefix:", config.symbolPrefix);
    console.log("  consol:", config.consol);
    console.log("  usdx:", config.usdx);
    console.log("  depositPhaseDuration:", config.depositPhaseDuration);
    console.log("  deployPhaseDuration:", config.deployPhaseDuration);
    console.log("  defaultPoolLimit:", config.defaultPoolLimit);
    console.log("  poolLimitGrowthRateBps:", config.poolLimitGrowthRateBps);
    console.log("  poolMultiplierBps:", config.poolMultiplierBps);
  }
}
