// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IOriginationPoolScheduler} from "../../src/interfaces/IOriginationPoolScheduler/IOriginationPoolScheduler.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {OriginationPoolConfig} from "../../src/types/OriginationPoolConfig.sol";
import {OPoolConfigId, OPoolConfigIdLibrary} from "../../src/types/OPoolConfigId.sol";
import {OriginationPoolPhase} from "../../src/types/enums/OriginationPoolPhase.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/**
 * @title GenesisPoolBase
 * @notice Shared configuration for the genesis origination pool ops scripts.
 * @dev Addresses come from the chain's address book (addresses/addresses-<chainId>.json).
 *      The daily config is rebuilt from the INITIAL_ORIGINATION_POOL_0_* vars DeployAll added it with.
 *      The genesis config reads GENESIS_ORIGINATION_POOL_* and defaults to the launch parameters;
 *      a set but malformed or out-of-bounds override reverts instead of falling back to the default.
 *      On Robinhood Testnet (chain id 46630) both phase floors are 1 hour, so a rehearsal runs in hours;
 *      every other chain keeps the 7-day deposit and 1-day deploy floors. The defaults are the same everywhere.
 *      GENESIS_POOL_ADDRESS (optional) is the deployed genesis pool, recorded after launch.
 *      The signer is ADMIN_ADDRESS_0, which must hold DEFAULT_ADMIN_ROLE on the scheduler.
 */
abstract contract GenesisPoolBase is Script {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  uint256 public constant DEFAULT_DEPOSIT_PHASE_DURATION = 7 days;
  uint256 public constant DEFAULT_DEPLOY_PHASE_DURATION = 7 days;
  uint256 public constant MIN_DEPOSIT_PHASE_DURATION = 7 days;
  uint256 public constant MAX_DEPOSIT_PHASE_DURATION = 35 days;
  uint256 public constant MIN_DEPLOY_PHASE_DURATION = 1 days;
  uint256 public constant MAX_DEPLOY_PHASE_DURATION = 30 days;
  uint256 public constant REHEARSAL_CHAIN_ID = 46_630;
  uint256 public constant REHEARSAL_MIN_PHASE_DURATION = 1 hours;
  uint256 public constant MIN_DEFAULT_POOL_LIMIT = 1_000_000e18;
  uint256 public constant MAX_DEFAULT_POOL_LIMIT = 1e30;
  uint256 public constant MAX_BPS = 10_000;

  IOriginationPoolScheduler public scheduler;
  address public admin;
  address public generalManagerFromAddressBook;
  address public genesisPoolAddress;
  string internal _addressBookJson;

  OriginationPoolConfig internal _dailyConfig;
  OriginationPoolConfig internal _genesisConfig;

  /// @notice Supplies the address book JSON directly instead of reading the chain's file.
  function setAddressBookJson(string memory json) external {
    _addressBookJson = json;
  }

  /// @notice Overrides GENESIS_POOL_ADDRESS after setUp.
  function setGenesisPoolAddress(address pool) external {
    genesisPoolAddress = pool;
  }

  /// @notice Overrides GENESIS_ORIGINATION_POOL_{DEPOSIT,DEPLOY}_PHASE_DURATION after setUp, within the same bounds.
  function setGenesisPhaseDurations(uint32 depositPhaseDuration, uint32 deployPhaseDuration) external {
    OriginationPoolConfig memory config = _genesisConfig;
    config.depositPhaseDuration = depositPhaseDuration;
    config.deployPhaseDuration = deployPhaseDuration;
    validateGenesisConfig(config);
    _genesisConfig = config;
  }

  function setUp() public virtual {
    string memory json = bytes(_addressBookJson).length != 0
      ? _addressBookJson
      : vm.readFile(string.concat(vm.projectRoot(), "/addresses/addresses-", vm.toString(block.chainid), ".json"));
    scheduler = IOriginationPoolScheduler(vm.parseJsonAddress(json, ".originationPoolSchedulerAddress"));
    address consol = vm.parseJsonAddress(json, ".consolAddress");
    address usdx = vm.parseJsonAddress(json, ".usdxAddress");
    generalManagerFromAddressBook = vm.parseJsonAddress(json, ".generalManagerAddress");
    admin = vm.envAddress("ADMIN_ADDRESS_0");
    genesisPoolAddress = vm.envExists("GENESIS_POOL_ADDRESS") ? vm.envAddress("GENESIS_POOL_ADDRESS") : address(0);

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
        _envUintOr("GENESIS_ORIGINATION_POOL_DEPOSIT_PHASE_DURATION", DEFAULT_DEPOSIT_PHASE_DURATION)
      ),
      deployPhaseDuration: SafeCast.toUint32(
        _envUintOr("GENESIS_ORIGINATION_POOL_DEPLOY_PHASE_DURATION", DEFAULT_DEPLOY_PHASE_DURATION)
      ),
      defaultPoolLimit: _envUintOr("GENESIS_ORIGINATION_POOL_DEFAULT_POOL_LIMIT", 1_000_000_000e18),
      poolLimitGrowthRateBps: SafeCast.toUint16(_envUintOr("GENESIS_ORIGINATION_POOL_POOL_LIMIT_GROWTH_RATE_BPS", 0)),
      poolMultiplierBps: SafeCast.toUint16(_envUintOr("GENESIS_ORIGINATION_POOL_POOL_MULTIPLIER_BPS", 0))
    });
    validateGenesisConfig(_genesisConfig);
  }

  /// @notice Reverts, naming the env var, when a genesis parameter is outside its sanity bounds.
  function validateGenesisConfig(OriginationPoolConfig memory config) public view {
    bool rehearsal = isRehearsalChain();
    require(
      config.depositPhaseDuration >= minDepositPhaseDuration()
        && config.depositPhaseDuration <= MAX_DEPOSIT_PHASE_DURATION,
      rehearsal
        ? "GENESIS_ORIGINATION_POOL_DEPOSIT_PHASE_DURATION out of bounds [1 hour, 35 days]"
        : "GENESIS_ORIGINATION_POOL_DEPOSIT_PHASE_DURATION out of bounds [7 days, 35 days]"
    );
    require(
      config.deployPhaseDuration >= minDeployPhaseDuration() && config.deployPhaseDuration <= MAX_DEPLOY_PHASE_DURATION,
      rehearsal
        ? "GENESIS_ORIGINATION_POOL_DEPLOY_PHASE_DURATION out of bounds [1 hour, 30 days]"
        : "GENESIS_ORIGINATION_POOL_DEPLOY_PHASE_DURATION out of bounds [1 day, 30 days]"
    );
    require(
      config.defaultPoolLimit >= MIN_DEFAULT_POOL_LIMIT && config.defaultPoolLimit <= MAX_DEFAULT_POOL_LIMIT,
      "GENESIS_ORIGINATION_POOL_DEFAULT_POOL_LIMIT out of bounds [1_000_000e18, 1e30]"
    );
    require(
      config.poolLimitGrowthRateBps <= MAX_BPS, "GENESIS_ORIGINATION_POOL_POOL_LIMIT_GROWTH_RATE_BPS above 10_000"
    );
    require(config.poolMultiplierBps <= MAX_BPS, "GENESIS_ORIGINATION_POOL_POOL_MULTIPLIER_BPS above 10_000");
  }

  /// @notice True on Robinhood Testnet, the only chain where the short rehearsal floors apply.
  function isRehearsalChain() public view returns (bool) {
    return block.chainid == REHEARSAL_CHAIN_ID;
  }

  /// @notice The deposit phase floor on this chain.
  function minDepositPhaseDuration() public view returns (uint256) {
    return isRehearsalChain() ? REHEARSAL_MIN_PHASE_DURATION : MIN_DEPOSIT_PHASE_DURATION;
  }

  /// @notice The deploy phase floor on this chain.
  function minDeployPhaseDuration() public view returns (uint256) {
    return isRehearsalChain() ? REHEARSAL_MIN_PHASE_DURATION : MIN_DEPLOY_PHASE_DURATION;
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

  /// @dev Unset uses the default; set but unparsable reverts.
  function _envUintOr(string memory name, uint256 defaultValue) internal view returns (uint256) {
    return vm.envExists(name) ? vm.envUint(name) : defaultValue;
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

  /// @dev True when GENESIS_POOL_ADDRESS points at deployed code, whether or not it is still registered.
  function _genesisPoolDeployed() internal view returns (bool) {
    return genesisPoolAddress != address(0) && genesisPoolAddress.code.length != 0;
  }

  /// @dev Requires a deployed GENESIS_POOL_ADDRESS; registration is reported by the callers, not required.
  function _requireGenesisPool() internal view returns (IOriginationPool) {
    require(genesisPoolAddress != address(0), "GENESIS_POOL_ADDRESS is not set");
    require(genesisPoolAddress.code.length != 0, "GENESIS_POOL_ADDRESS has no code");
    return IOriginationPool(genesisPoolAddress);
  }

  function _registrationName(bool registered) internal pure returns (string memory) {
    return registered ? "registered" : "deregistered";
  }

  function _phaseName(OriginationPoolPhase phase) internal pure returns (string memory) {
    if (phase == OriginationPoolPhase.DEPOSIT) return "DEPOSIT";
    if (phase == OriginationPoolPhase.DEPLOY) return "DEPLOY";
    return "REDEMPTION";
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
