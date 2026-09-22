// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {NFTMetadataGenerator} from "../../src/NFTMetadataGenerator.sol";

/**
 * @title MockNFTMetadataGeneratorUpgraded
 * @author SocksNFlops
 * @notice Just a mock to test the upgrade of the NFTMetadataGenerator
 */
contract MockNFTMetadataGeneratorUpgraded is NFTMetadataGenerator {
  function newFunction() public pure returns (bool) {
    return true;
  }
}
