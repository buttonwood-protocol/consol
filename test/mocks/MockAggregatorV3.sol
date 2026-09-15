// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "../../src/external/AggregatorV3Interface.sol";

contract MockAggregatorV3 is AggregatorV3Interface {
  uint8 public immutable decimals;
  uint80 private roundId_;
  int256 private answer_;
  uint256 private startedAt_;
  uint256 private updatedAt_;

  constructor(uint8 _decimals) {
    decimals = _decimals;
  }

  function set(int256 answer, uint256 updatedAt) external {
    roundId_++;
    answer_ = answer;
    startedAt_ = updatedAt;
    updatedAt_ = updatedAt;
  }

  function setRoundData(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt) external {
    roundId_ = roundId;
    answer_ = answer;
    startedAt_ = startedAt;
    updatedAt_ = updatedAt;
  }

  function description() external pure returns (string memory) {
    return "MockAggregatorV3";
  }

  function version() external pure returns (uint256) {
    return 1;
  }

  function getRoundData(uint80)
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return (roundId_, answer_, startedAt_, updatedAt_, roundId_);
  }

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
  {
    return (roundId_, answer_, startedAt_, updatedAt_, roundId_);
  }
}
