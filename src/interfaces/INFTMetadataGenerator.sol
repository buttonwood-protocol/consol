// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MortgagePosition} from "../types/MortgagePosition.sol";

/**
 * @title Interface for the NFT Metadata Generator contract
 * @author SocksNFlops
 * @notice The NFT Metadata Generator contract is responsible for generating the metadata for a mortgage NFT
 */
interface INFTMetadataGenerator {
  /**
   * @notice Generates the metadata for a mortgage NFT
   * @param mortgagePosition The position of the mortgage
   * @return metadata The metadata for the mortgage NFT
   */
  function generateMetadata(MortgagePosition memory mortgagePosition) external view returns (string memory metadata);
}
