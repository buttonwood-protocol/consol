// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OPoolConfigId} from "../../types/OPoolConfigId.sol";
import {OriginationPoolConfig} from "../../types/OriginationPoolConfig.sol";

interface IOriginationPoolSchedulerEvents {
  /**
   * @notice Emitted when a new origination pool config is added
   * @param oPoolConfigId The ID of the origination pool config
   * @param oPoolConfig The origination pool config
   */
  event OriginationPoolConfigAdded(OPoolConfigId oPoolConfigId, OriginationPoolConfig oPoolConfig);

  /**
   * @notice Emitted when an origination pool config is removed
   * @param oPoolConfigId The ID of the origination pool config
   * @param oPoolConfig The origination pool config
   */
  event OriginationPoolConfigRemoved(OPoolConfigId oPoolConfigId, OriginationPoolConfig oPoolConfig);

  /**
   * @notice Emitted when an origination pool is deployed
   * @param oPoolConfigId The ID of the origination pool config
   * @param oPoolConfig The origination pool config
   * @param deploymentAddress The address of the deployment
   * @param deploymentEpoch The epoch of the deployment
   * @param deploymentTimestamp The timestamp of the deployment
   */
  event OriginationPoolDeployed(
    OPoolConfigId indexed oPoolConfigId,
    OriginationPoolConfig indexed oPoolConfig,
    address indexed deploymentAddress,
    uint256 deploymentEpoch,
    uint256 deploymentTimestamp
  );

  /**
   * @notice Emitted when an origination pool is updated
   * @param originationPool The address of the origination pool
   * @param registered Whether the origination pool is registered
   */
  event OriginationPoolRegistryUpdated(address indexed originationPool, bool registered);
}
