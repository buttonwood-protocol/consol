// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title MortgageNode
 * @author SocksNFlops
 * @notice A struct that represents a mortgage in the MortgageQueue
 * @param previous The previous node in the queue
 * @param next The next node in the queue
 * @param triggerPrice The trigger price of the mortgage
 * @param tokenId The tokenId of the mortgage
 * @param gasFee The gas fee paid for the request
 */
struct MortgageNode {
  uint256 previous;
  uint256 next;
  uint256 triggerPrice;
  uint256 tokenId;
  uint256 gasFee;
}
