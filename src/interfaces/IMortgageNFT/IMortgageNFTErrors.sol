// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IMortgageNFTErrors
 * @author Socks&Flops
 */
interface IMortgageNFTErrors {
  /**
   * @notice Emitted when a mortgageId is already taken
   * @param tokenId The ID of the mortgage NFT with the taken mortgageId
   * @param mortgageId The mortageId of the mortgage
   */
  error MortgageIdAlreadyTaken(uint256 tokenId, string mortgageId);

  /**
   * @notice Emitted when a non-owner attempts to update a mortgageId
   * @param owner The owner of the mortgage NFT
   * @param caller The caller of the function
   */
  error OnlyOwner(address owner, address caller);

  /**
   * @notice Emitted when a non-general manager attempts to update a mortgage NFT
   * @param generalManager The general manager address
   * @param caller The caller of the function
   */
  error OnlyGeneralManager(address generalManager, address caller);
}
