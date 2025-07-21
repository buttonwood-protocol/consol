// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IOriginationPoolSchedulerEvents} from "./IOriginationPoolSchedulerEvents.sol";
import {IOriginationPoolSchedulerErrors} from "./IOriginationPoolSchedulerErrors.sol";
import {OriginationPoolConfig} from "../../types/OriginationPoolConfig.sol";
import {OPoolConfigId} from "../../types/OPoolConfigId.sol";
import {IPausable} from "../IPausable/IPausable.sol";

/**
 * @notice A record of the last deployment address, epoch, and timestamp for a given origination pool config
 * @param deploymentAddress The address of the last deployment
 * @param epoch The epoch number of the last deployment
 * @param timestamp The timestamp of the last deployment
 */
struct LastDeploymentRecord {
  address deploymentAddress;
  uint256 epoch;
  uint256 timestamp;
}

/**
 * @title Interface for the OriginationPoolFactory contract
 * @author SocksNFlops
 * @notice Interface for the OriginationPoolFactory contract
 */
interface IOriginationPoolScheduler is IOriginationPoolSchedulerEvents, IOriginationPoolSchedulerErrors, IPausable {
  /**
   * @notice Set the general manager address
   * @param newGeneralManager The address of the new general manager
   */
  function setGeneralManager(address newGeneralManager) external;

  /**
   * @notice Get the general manager address
   * @return The address of the general manager
   */
  function generalManager() external view returns (address);

  /**
   * @notice Set the admin address that is assigned to the origination pools on deployment
   * @param newOpoolAdmin The address of the new origination pool admin
   */
  function setOpoolAdmin(address newOpoolAdmin) external;

  /**
   * @notice Get the admin address that is assigned to the origination pools on deployment
   * @return The address of the origination pool admin
   */
  function oPoolAdmin() external view returns (address);

  /**
   * @notice Get the number of origination pool configs
   * @return The number of origination pool configs
   */
  function configLength() external view returns (uint256);

  /**
   * @notice Get the origination pool config ID at the given index
   * @param index The index of the origination pool config to get the ID for
   * @return oPoolConfigId The ID of the origination pool config
   */
  function configIdAt(uint256 index) external view returns (OPoolConfigId oPoolConfigId);

  /**
   * @notice Get the origination pool config at the given index
   * @param index The index of the origination pool config to get
   * @return config The origination pool config
   */
  function configAt(uint256 index) external view returns (OriginationPoolConfig memory);

  /**
   * @notice Get the last deployment address from the given config index
   * @param index The index of the origination pool config to get the last deployment address from
   * @return lastDeploymentRecord The last deployment record
   */
  function lastConfigDeployment(uint256 index) external view returns (LastDeploymentRecord memory lastDeploymentRecord);

  /**
   * @notice Get the last deployment address from the given config ID
   * @param oPoolConfigId The ID of the origination pool config to get the last deployment address from
   * @return lastDeploymentRecord The last deployment record
   */
  function lastConfigDeployment(OPoolConfigId oPoolConfigId)
    external
    view
    returns (LastDeploymentRecord memory lastDeploymentRecord);

  /**
   * @notice Add a new origination pool config
   * @param config The origination pool config to add
   */
  function addConfig(OriginationPoolConfig memory config) external;

  /**
   * @notice Remove an origination pool config
   * @param config The origination pool config to remove
   */
  function removeConfig(OriginationPoolConfig memory config) external;

  /**
   * @notice Get the current epoch. Indexed from 1
   * @return currentEpoch The current epoch
   */
  function currentEpoch() external view returns (uint256);

  /**
   * @notice Deploy a new origination pool
   * @param oPoolConfigId The ID of the origination pool config to deploy
   * @return deploymentAddress The address of the deployed origination pool
   */
  function deployOriginationPool(OPoolConfigId oPoolConfigId) external returns (address deploymentAddress);

  /**
   * @notice Predict the origination pool address for the given config ID and current epoch. If already deployed, will return the already deployed address.
   * @param oPoolConfigId The ID of the origination pool config to predict the address for
   * @return deploymentAddress The predicted deployment address
   */
  function predictOriginationPool(OPoolConfigId oPoolConfigId) external view returns (address deploymentAddress);

  /**
   * @notice Check if an origination pool is registered (deployed by the scheduler)
   * @param originationPool The address of the origination pool to check
   * @return registered Whether the origination pool is registered
   */
  function isRegistered(address originationPool) external view returns (bool registered);

  /**
   * @notice Update the registration of an origination pool
   * @param originationPool The address of the origination pool to update the registration for
   * @param registered Whether the origination pool is registered
   */
  function updateRegistration(address originationPool, bool registered) external;
}
