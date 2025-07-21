// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {OriginationPoolConfig} from "./OriginationPoolConfig.sol";

type OPoolConfigId is bytes32;

/**
 * @title OPoolConfigIdLibrary
 * @author SocksNFlops
 * @notice Library for computing the ID of a origination pool config
 */
library OPoolConfigIdLibrary {
  /**
   * @dev Returns value equal to keccak256(abi.encode(OPoolConfig))
   * @param oPoolConfig The origination pool config to compute the ID for
   * @return oPoolConfigId The ID of the origination pool config
   */
  function toId(OriginationPoolConfig memory oPoolConfig) internal pure returns (OPoolConfigId oPoolConfigId) {
    return OPoolConfigId.wrap(keccak256(abi.encode(oPoolConfig)));
  }
}
