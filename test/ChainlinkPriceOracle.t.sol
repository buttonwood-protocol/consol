// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract ChainlinkPriceOracleTest is Test {
  // Constants
  bytes32 public constant FEED_ID = keccak256("CHAINLINK:4663:AAPL");
  int256 public constant FEED_PRICE = 211_92000000;
  uint8 public constant FEED_DECIMALS = 8;
  uint256 public constant MAX_AGE = 7 days;
  uint256 public constant START_TIME = 1_700_000_000;

  // Contracts
  MockAggregatorV3 public feed;
  ChainlinkPriceOracle public oracle;

  function setUp() public virtual {
    vm.warp(START_TIME);
    feed = new MockAggregatorV3(FEED_DECIMALS);
    feed.set(FEED_PRICE, START_TIME);
    oracle = new ChainlinkPriceOracle(address(feed), 8, MAX_AGE);
  }

  function test_constructor() public view {
    assertEq(address(oracle.aggregator()), address(feed), "Aggregator mismatch");
    assertEq(oracle.collateralDecimals(), 8, "Collateral decimals mismatch");
    assertEq(oracle.maxAge(), MAX_AGE, "Max age mismatch");
    assertEq(oracle.feedDecimals(), FEED_DECIMALS, "Feed decimals mismatch");
    assertEq(oracle.priceScale(), 1e10, "Price scale mismatch");
  }

  function test_constructor_invalidDecimals(uint8 decimals) public {
    decimals = uint8(bound(decimals, 19, type(uint8).max));
    MockAggregatorV3 badFeed = new MockAggregatorV3(decimals);
    vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.InvalidDecimals.selector, decimals));
    new ChainlinkPriceOracle(address(badFeed), 8, MAX_AGE);
  }

  function test_price() public view {
    // 8 decimals means 21192000000 is $211.92
    assertEq(oracle.price(), 211_92e16, "Price mismatch");
  }

  function test_price_scaling(int256 answer) public {
    answer = bound(answer, 1, type(int256).max / 1e10);
    feed.set(answer, START_TIME);
    assertEq(oracle.price(), uint256(answer) * 1e10, "Price mismatch");
  }

  function test_price_followsLatestReading() public {
    vm.warp(START_TIME + 30);
    feed.set(212_00000000, START_TIME + 30);
    assertEq(oracle.price(), 212e18, "Price mismatch");
  }

  function test_price_feedDecimals(uint8 decimals) public {
    decimals = uint8(bound(decimals, 0, 18));
    MockAggregatorV3 scaledFeed = new MockAggregatorV3(decimals);
    // $212 expressed with the feed's decimals
    scaledFeed.set(int256(212 * 10 ** uint256(decimals)), START_TIME);
    ChainlinkPriceOracle scaledOracle = new ChainlinkPriceOracle(address(scaledFeed), 8, MAX_AGE);
    assertEq(scaledOracle.feedDecimals(), decimals, "Feed decimals mismatch");
    assertEq(scaledOracle.priceScale(), 10 ** (18 - uint256(decimals)), "Price scale mismatch");
    assertEq(scaledOracle.price(), 212e18, "Price mismatch");
  }

  function test_price_maxAgeBoundary() public {
    // A price aged exactly maxAge is still fresh
    vm.warp(START_TIME + MAX_AGE);
    assertEq(oracle.price(), 211_92e16, "Price mismatch");

    // One second older is stale
    vm.warp(START_TIME + MAX_AGE + 1);
    vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.StalePrice.selector, MAX_AGE + 1, MAX_AGE));
    oracle.price();
  }

  function test_price_stale(uint256 age) public {
    age = bound(age, MAX_AGE + 1, type(uint64).max);
    vm.warp(START_TIME + age);
    vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.StalePrice.selector, age, MAX_AGE));
    oracle.price();
  }

  // Equity feeds freeze over weekends and holidays with no heartbeat, so ~29-36h old readings are normal on
  // Sundays. A weekend-sized maxAge tolerates them; a naive one-day bound reverts.
  function test_price_weekendStaleness() public {
    uint256 age = 35 hours;
    ChainlinkPriceOracle naiveOracle = new ChainlinkPriceOracle(address(feed), 8, 86400);
    vm.warp(START_TIME + age);

    assertEq(oracle.price(), 211_92e16, "Price mismatch");
    vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.StalePrice.selector, age, 86400));
    naiveOracle.price();
  }

  function test_price_nonPositiveAnswer(int256 answer) public {
    answer = bound(answer, type(int256).min, 0);
    feed.set(answer, START_TIME);
    vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.InvalidAnswer.selector, answer));
    oracle.price();
  }

  function test_price_incompleteRound() public {
    feed.setRoundData(2, FEED_PRICE, 0, 0);
    vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.IncompleteRound.selector, 2));
    oracle.price();
  }

  // Staleness is checked before the answer
  function test_price_staleBeforeAnswer() public {
    feed.set(0, START_TIME - MAX_AGE - 1);
    vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.StalePrice.selector, MAX_AGE + 1, MAX_AGE));
    oracle.price();
  }

  function test_cost() public view {
    // 3.47 units at $211.92 is $735.3624
    (uint256 totalCost, uint8 collateralDecimals) = oracle.cost(347e6);
    assertEq(totalCost, 7353624e14, "Cost mismatch");
    assertEq(collateralDecimals, 8, "Collateral decimals mismatch");
  }

  function test_cost_18Decimals() public {
    ChainlinkPriceOracle oracle18 = new ChainlinkPriceOracle(address(feed), 18, MAX_AGE);
    // 2.5 units at $211.92 is $529.80
    (uint256 totalCost, uint8 collateralDecimals) = oracle18.cost(25e17);
    assertEq(totalCost, 5298e17, "Cost mismatch");
    assertEq(collateralDecimals, 18, "Collateral decimals mismatch");
  }

  function test_cost_fuzz(uint256 collateralAmount) public view {
    collateralAmount = bound(collateralAmount, 0, 1e40);
    (uint256 totalCost, uint8 collateralDecimals) = oracle.cost(collateralAmount);
    assertEq(totalCost, Math.mulDiv(collateralAmount, oracle.price(), 1e8), "Cost mismatch");
    assertEq(collateralDecimals, 8, "Collateral decimals mismatch");
  }

  function test_cost_stale() public {
    vm.warp(START_TIME + MAX_AGE + 1);
    vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.StalePrice.selector, MAX_AGE + 1, MAX_AGE));
    oracle.cost(1e8);
  }

  function test_cost_parityWithPythPriceOracle(int64 answer, uint8 collateralDecimals, uint256 collateralAmount)
    public
  {
    answer = int64(bound(answer, 1, type(int64).max));
    collateralDecimals = uint8(bound(collateralDecimals, 0, 30));
    collateralAmount = bound(collateralAmount, 0, 1e40);

    // Configure a Pyth oracle reporting the same 8-decimal price for the same collateral
    MockPyth pyth = new MockPyth(60, 0);
    bytes[] memory updateData = new bytes[](1);
    updateData[0] = pyth.createPriceFeedUpdateData(
      FEED_ID, answer, 0, -8, answer, 0, uint64(block.timestamp), uint64(block.timestamp)
    );
    pyth.updatePriceFeeds(updateData);
    PythPriceOracle pythOracle = new PythPriceOracle(address(pyth), FEED_ID, 1e18, collateralDecimals);

    feed.set(answer, START_TIME);
    ChainlinkPriceOracle sampleOracle = new ChainlinkPriceOracle(address(feed), collateralDecimals, MAX_AGE);

    // Both oracles must report the same price and cost for the same inputs
    assertEq(sampleOracle.price(), pythOracle.price(), "Price mismatch");
    (uint256 totalCost, uint8 _collateralDecimals) = sampleOracle.cost(collateralAmount);
    (uint256 pythTotalCost, uint8 pythCollateralDecimals) = pythOracle.cost(collateralAmount);
    assertEq(totalCost, pythTotalCost, "Cost parity mismatch");
    assertEq(_collateralDecimals, pythCollateralDecimals, "Collateral decimals parity mismatch");
  }
}
