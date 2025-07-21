// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MortgageQueue} from "../../src/MortgageQueue.sol";

/**
 * @title MockMortgageQueue
 * @author SocksNFlops
 * @notice A mock implementation of the MortgageQueue contract for simple testing
 */
contract MockMortgageQueue is MortgageQueue {
  constructor() MortgageQueue() {}

  function insertMortgage(uint256 tokenId, uint256 triggerPrice, uint256 hintPrevId) external payable {
    _insertMortgage(tokenId, triggerPrice, hintPrevId);
  }

  function removeMortgage(uint256 tokenId) external {
    _removeMortgage(tokenId);
  }

  function findFirstTriggered(uint256 triggerPrice) external view returns (uint256 tokenId) {
    return _findFirstTriggered(triggerPrice);
  }
}
