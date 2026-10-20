// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {GenesisPoolBase} from "./GenesisPoolBase.s.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {OriginationPoolConfig} from "../../src/types/OriginationPoolConfig.sol";
import {OPoolConfigId, OPoolConfigIdLibrary} from "../../src/types/OPoolConfigId.sol";
import {OriginationPoolPhase} from "../../src/types/enums/OriginationPoolPhase.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/**
 * @title GenesisPoolVerify
 * @notice Read-only check of the genesis pool against the live chain. Never broadcasts.
 * @dev Run against the real RPC right after each launch or reopen broadcast, with GENESIS_POOL_ADDRESS set.
 *      configLength() == 0 is verified as the post-launch state (pool in DEPOSIT), or, once the pool is
 *      deregistered, as the post-deregistration state (any phase);
 *      configLength() == 1 as the post-reopen state (the daily config, pool past DEPOSIT).
 *      Registration is reported, not required: a deregistered pool passes the other checks unchanged.
 */
contract GenesisPoolVerify is GenesisPoolBase {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  uint256 public constant LATE_LAUNCH_WARNING = 1 hours;

  /// @return registered Whether the genesis pool is registered on the scheduler.
  /// @return state The verified state: "after launch", "after deregistration" or "after reopen".
  function run() public view returns (bool registered, string memory state) {
    OriginationPoolConfig memory genesis = genesisConfig();

    IOriginationPool pool = _requireGenesisPool();
    address poolAddress = address(pool);

    uint256 depositTs = pool.depositPhaseTimestamp();
    uint256 deployTs = pool.deployPhaseTimestamp();
    uint256 redemptionTs = pool.redemptionPhaseTimestamp();
    require(deployTs >= genesis.depositPhaseDuration, "deployPhaseTimestamp below depositPhaseDuration");
    uint256 epochStart = deployTs - genesis.depositPhaseDuration;
    require(
      epochStart >= Constants.EPOCH_OFFSET && (epochStart - Constants.EPOCH_OFFSET) % Constants.EPOCH_DURATION == 0,
      "deployPhaseTimestamp - depositPhaseDuration is not a 12:00 UTC epoch boundary"
    );
    require(
      depositTs >= epochStart && depositTs < epochStart + Constants.EPOCH_DURATION,
      "depositPhaseTimestamp is outside the launch epoch"
    );
    require(redemptionTs == deployTs + genesis.deployPhaseDuration, "redemptionPhaseTimestamp - deployPhaseTimestamp");
    require(pool.poolLimit() == genesis.defaultPoolLimit, "unexpected poolLimit");
    require(pool.poolMultiplierBps() == genesis.poolMultiplierBps, "unexpected poolMultiplierBps");
    require(pool.consol() == genesis.consol && pool.usdx() == genesis.usdx, "unexpected consol/usdx");

    address gm = scheduler.generalManager();
    require(IAccessControl(poolAddress).hasRole(Roles.DEPLOY_ROLE, gm), "GeneralManager lacks DEPLOY_ROLE on the pool");

    OriginationPoolPhase phase = pool.currentPhase();
    registered = scheduler.isRegistered(poolAddress);
    uint256 length;
    (state, length) = _checkConfigState(phase, registered);

    address poolAdmin = scheduler.oPoolAdmin();
    uint256 lateBy = depositTs - epochStart;

    console.log("Genesis pool:", poolAddress);
    console.log("  name:", IERC20Metadata(poolAddress).name());
    console.log("  symbol:", IERC20Metadata(poolAddress).symbol());
    _logRegistration(registered, phase);
    console.log("  phase:", _phaseName(phase));
    console.log("  depositPhaseTimestamp:", depositTs);
    console.log("  deployPhaseTimestamp:", deployTs);
    console.log("  redemptionPhaseTimestamp:", redemptionTs);
    console.log("  launch epoch start:", epochStart);
    console.log("  seconds after the boundary at deployment:", lateBy);
    if (lateBy > LATE_LAUNCH_WARNING) {
      console.log("WARNING: deployed more than 1 hour after the boundary; the deposit phase is shorter");
    }
    console.log("  deposit phase length (s):", deployTs - depositTs);
    console.log("  poolLimit:", pool.poolLimit());
    console.log("Scheduler configLength:", length);
    console.log("GeneralManager (scheduler):", gm);
    console.log("GeneralManager (address book):", generalManagerFromAddressBook);
    console.log("GeneralManager matches address book:", gm == generalManagerFromAddressBook);
    console.log("Pool DEFAULT_ADMIN_ROLE holder (scheduler oPoolAdmin):", poolAdmin);
    console.log("  holds DEFAULT_ADMIN_ROLE:", IAccessControl(poolAddress).hasRole(Roles.DEFAULT_ADMIN_ROLE, poolAdmin));
    console.log("  holds PAUSE_ROLE:", IAccessControl(poolAddress).hasRole(Roles.PAUSE_ROLE, poolAdmin));
    console.log(
      "Scheduler holds DEFAULT_ADMIN_ROLE on the pool:",
      IAccessControl(poolAddress).hasRole(Roles.DEFAULT_ADMIN_ROLE, address(scheduler))
    );
    console.log("Verified:", state);
  }

  /// @dev Checks the scheduler's configs against the pool's phase and registration.
  function _checkConfigState(OriginationPoolPhase phase, bool registered)
    internal
    view
    returns (string memory state, uint256 length)
  {
    length = scheduler.configLength();
    if (length == 0 && registered) {
      require(phase == OriginationPoolPhase.DEPOSIT, "after launch: genesis pool is not in DEPOSIT");
      return ("after launch", length);
    }
    if (length == 0) {
      return ("after deregistration", length);
    }
    require(length == 1, "expected zero (after launch) or one (after reopen) configs");
    require(
      OPoolConfigId.unwrap(scheduler.configIdAt(0)) == OPoolConfigId.unwrap(dailyConfigId()),
      "after reopen: the remaining config is not the daily config"
    );
    require(phase != OriginationPoolPhase.DEPOSIT, "after reopen: genesis pool is still in DEPOSIT");
    return ("after reopen", length);
  }

  function _logRegistration(bool registered, OriginationPoolPhase phase) internal pure {
    console.log("  registration:", _registrationName(registered));
    if (!registered) {
      console.log("WARNING: the pool is deregistered: the GeneralManager and RolloverVault reject it");
      if (phase == OriginationPoolPhase.DEPOSIT) {
        console.log("WARNING: deregistered while still in DEPOSIT");
      }
    }
  }
}
