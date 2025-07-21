// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IMortgageNFTEvents
 * @author Socks&Flops
 */
interface IMortgageNFTEvents {
  /**
   * @notice Emitted when a mortgageId is updated
   * @param tokenId The numerical index of the mortgageNFT
   * @param mortgageId The new id of the mortgage
   */
  event MortgageIdUpdate(uint256 tokenId, string mortgageId);
}
