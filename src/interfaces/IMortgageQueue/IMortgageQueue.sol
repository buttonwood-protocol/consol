// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IMortgageQueueEvents} from "./IMortgageQueueEvents.sol";
import {IMortgageQueueErrors} from "./IMortgageQueueErrors.sol";
import {MortgageNode} from "../../types/MortgageNode.sol";

/**
 * @title IMortgageQueue
 * @author @SocksNFlops
 * @notice Interface for the Mortgage Queue contract. Maintains a priority queue of MortgagePositions sorted by trigger price.
 * @dev The Mortgage Queue is ordered in ascending order by trigger price.
 */
interface IMortgageQueue is IMortgageQueueEvents, IMortgageQueueErrors {
  /**
   * @notice The node for the corresponding tokenId (if it exists).
   * @param tokenId The tokenId of the MortgagePosition to get the node for.
   * @return mortgageNode The node for the corresponding tokenId.
   */
  function mortgageNodes(uint256 tokenId) external view returns (MortgageNode memory mortgageNode);

  /**
   * @notice The tokenId of the MortgagePosition at the head of the queue.
   * @return The tokenId of the MortgagePosition at the head of the queue.
   */
  function mortgageHead() external view returns (uint256);

  /**
   * @notice The tokenId of the MortgagePosition at the tail of the queue.
   * @return The tokenId of the MortgagePosition at the tail of the queue.
   */
  function mortgageTail() external view returns (uint256);

  /**
   * @notice The number of nodes in the queue.
   * @return The number of nodes in the queue.
   */
  function mortgageSize() external view returns (uint256);

  /**
   * @notice The gas fee for enqueueing a mortgage into the queue.
   * @return The gas fee for enqueueing a mortgage into the queue.
   */
  function mortgageGasFee() external view returns (uint256);

  /**
   * @notice Sets the gas fee for enqueueing a mortgage into the queue.
   * @param mortgageGasFee_ The gas fee for enqueueing a mortgage into the queue.
   */
  function setMortgageGasFee(uint256 mortgageGasFee_) external;
}
