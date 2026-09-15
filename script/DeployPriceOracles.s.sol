// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {DeployInterestOracle} from "./DeployInterestOracle.s.sol";
import {CollateralSetup} from "./CollateralSetup.s.sol";
import {IPyth} from "@pythnetwork/IPyth.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
import {MockAggregatorV3} from "../test/mocks/MockAggregatorV3.sol";

contract DeployPriceOracles is DeployInterestOracle, CollateralSetup {
  IPyth public pyth;
  IPriceOracle[] public priceOracles;
  string public priceOracleType;

  function setUp() public virtual override(DeployInterestOracle, CollateralSetup) {
    super.setUp();
    setPriceOracleType(vm.envOr("PRICE_ORACLE_TYPE", string("pyth")));
  }

  function run() public virtual override(DeployInterestOracle, CollateralSetup) {
    super.run();
    startDeployerBroadcast();
    if (!usesChainlinkPriceOracles()) {
      pyth = getOrCreatePyth();
    }
    deployPriceOracles();
    vm.stopBroadcast();
  }

  /// @dev Also callable from tests to select the oracle type without touching process-global env vars
  function setPriceOracleType(string memory priceOracleType_) public {
    bytes32 typeHash = keccak256(bytes(priceOracleType_));
    require(
      typeHash == keccak256(bytes("pyth")) || typeHash == keccak256(bytes("chainlink")),
      string.concat("Unknown PRICE_ORACLE_TYPE: ", priceOracleType_)
    );
    priceOracleType = priceOracleType_;
  }

  function usesChainlinkPriceOracles() public view returns (bool) {
    return keccak256(bytes(priceOracleType)) == keccak256(bytes("chainlink"));
  }

  function getOrCreatePyth() public returns (IPyth) {
    if (isTest || isTestnet) {
      pyth = IPyth(address(new MockPyth(120, 0))); // Hardcoded to 2 minutes and 0 update fee during testing
    } else {
      pyth = IPyth(vm.envAddress("PYTH_ADDRESS"));
    }
    return pyth;
  }

  function getOrCreateAggregator(uint256 i) public returns (address aggregator) {
    if (isTest || isTestnet) {
      // Hardcoded to an 8-decimal $1.00 reading during testing
      MockAggregatorV3 mockAggregator = new MockAggregatorV3(8);
      mockAggregator.set(1e8, block.timestamp);
      aggregator = address(mockAggregator);
    } else {
      aggregator = vm.envAddress(string.concat("CHAINLINK_FEED_", vm.toString(i)));
    }
  }

  function logPyth(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "pythAddress", address(pyth));
  }

  function deployPriceOracles() public {
    if (usesChainlinkPriceOracles()) {
      deployChainlinkPriceOracles();
      return;
    }

    // Get the Pyth contract
    pyth = getOrCreatePyth();

    // Deploy the price oracles for each collateral token
    for (uint256 i = 0; i < collateralTokens.length; i++) {
      bytes32 priceId = vm.envBytes32(string.concat("PYTH_PRICE_ID_", vm.toString(i)));
      uint256 maxConfidence = vm.envUint(string.concat("PYTH_PRICE_MAX_CONFIDENCE_", vm.toString(i)));
      uint8 collateralDecimals = uint8(vm.envUint(string.concat("COLLATERAL_DECIMALS_", vm.toString(i))));
      priceOracles.push(new PythPriceOracle(address(pyth), priceId, maxConfidence, collateralDecimals));
    }
  }

  function deployChainlinkPriceOracles() public {
    // Equity feeds freeze over weekends and holidays with no heartbeat, so the bound must span the longest gap
    uint256 maxPriceAge = vm.envUint("CHAINLINK_MAX_PRICE_AGE");

    // Deploy the price oracles for each collateral token
    for (uint256 i = 0; i < collateralTokens.length; i++) {
      uint8 collateralDecimals = uint8(vm.envUint(string.concat("COLLATERAL_DECIMALS_", vm.toString(i))));
      address aggregator = getOrCreateAggregator(i);
      priceOracles.push(new ChainlinkPriceOracle(aggregator, collateralDecimals, maxPriceAge));
    }
  }

  function logPriceOracles(string memory objectKey) public returns (string memory json) {
    address[] memory addressList = new address[](priceOracles.length);
    for (uint256 i = 0; i < priceOracles.length; i++) {
      addressList[i] = address(priceOracles[i]);
    }
    json = vm.serializeAddress(objectKey, "priceOracles", addressList);
  }
}
