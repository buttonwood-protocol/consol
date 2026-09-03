// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SimpleOracle} from "../src/SimpleOracle.sol";
import {SimpleOraclePriceOracle} from "../src/SimpleOraclePriceOracle.sol";
import {ISimpleOracle} from "../src/interfaces/ISimpleOracle.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// A store whose readings and decimals are set directly, to drive the adapter into states the real store rejects
contract MockSimpleOracleStore {
  uint8 public decimals;
  int256 public answer;
  uint256 public updatedAt;

  constructor(uint8 decimals_) {
    decimals = decimals_;
  }

  function set(int256 answer_, uint256 updatedAt_) external {
    answer = answer_;
    updatedAt = updatedAt_;
  }

  function latestRoundData(bytes32) external view returns (int256, uint256) {
    return (answer, updatedAt);
  }
}

contract SimpleOraclePriceOracleTest is Test {
  // Constants
  bytes32 public constant PRICE_UPDATE_TYPEHASH = keccak256("PriceUpdate(bytes32 id,int256 price,uint256 timestamp)");
  bytes32 public constant FEED_ID = keccak256("MOCK_PYTH:46630:AAPL");
  int256 public constant FEED_PRICE = 81_07600000;
  uint256 public constant MAX_AGE = 60 seconds;
  uint256 public constant START_TIME = 1_700_000_000;

  // Actors
  address public admin;
  address public signer;
  uint256 public signerPrivateKey;

  // Contracts
  SimpleOracle public store;
  SimpleOraclePriceOracle public oracle;

  function setUp() public virtual {
    vm.warp(START_TIME);
    admin = makeAddr("admin");
    (signer, signerPrivateKey) = makeAddrAndKey("signer");
    store = new SimpleOracle(admin, signer);
    _push(FEED_ID, FEED_PRICE, START_TIME);
    oracle = new SimpleOraclePriceOracle(address(store), FEED_ID, 8, MAX_AGE);
  }

  function test_constructor() public view {
    assertEq(address(oracle.simpleOracle()), address(store), "Store mismatch");
    assertEq(oracle.feedId(), FEED_ID, "Feed id mismatch");
    assertEq(oracle.collateralDecimals(), 8, "Collateral decimals mismatch");
    assertEq(oracle.maxAge(), MAX_AGE, "Max age mismatch");
    assertEq(oracle.priceScale(), 1e10, "Price scale mismatch");
  }

  function test_constructor_invalidDecimals(uint8 decimals) public {
    vm.assume(decimals != 8);
    MockSimpleOracleStore badStore = new MockSimpleOracleStore(decimals);
    vm.expectRevert(abi.encodeWithSelector(SimpleOraclePriceOracle.InvalidDecimals.selector, decimals));
    new SimpleOraclePriceOracle(address(badStore), FEED_ID, 8, MAX_AGE);
  }

  function test_price() public view {
    // 8 decimals means 8107600000 is $81.076
    assertEq(oracle.price(), 81_076e15, "Price mismatch");
  }

  function test_price_scaling(int256 answer) public {
    answer = bound(answer, 1, type(int256).max / 1e10);
    vm.warp(START_TIME + 1);
    _push(FEED_ID, answer, START_TIME + 1);
    assertEq(oracle.price(), uint256(answer) * 1e10, "Price mismatch");
  }

  function test_price_followsLatestReading() public {
    vm.warp(START_TIME + 30);
    _push(FEED_ID, 82_00000000, START_TIME + 30);
    assertEq(oracle.price(), 82e18, "Price mismatch");
  }

  function test_price_maxAgeBoundary() public {
    // A price aged exactly maxAge is still fresh
    vm.warp(START_TIME + MAX_AGE);
    assertEq(oracle.price(), 81_076e15, "Price mismatch");

    // One second older is stale
    vm.warp(START_TIME + MAX_AGE + 1);
    vm.expectRevert(abi.encodeWithSelector(SimpleOraclePriceOracle.StalePrice.selector, MAX_AGE + 1, MAX_AGE));
    oracle.price();
  }

  function test_price_stale(uint256 age) public {
    age = bound(age, MAX_AGE + 1, type(uint64).max);
    vm.warp(START_TIME + age);
    vm.expectRevert(abi.encodeWithSelector(SimpleOraclePriceOracle.StalePrice.selector, age, MAX_AGE));
    oracle.price();
  }

  function test_price_unknownFeed(bytes32 feedId) public {
    vm.assume(feedId != FEED_ID);
    SimpleOraclePriceOracle unknownOracle = new SimpleOraclePriceOracle(address(store), feedId, 8, MAX_AGE);
    vm.expectRevert(abi.encodeWithSelector(ISimpleOracle.UnknownFeed.selector, feedId));
    unknownOracle.price();
  }

  function test_price_nonPositiveAnswer(int256 answer) public {
    answer = bound(answer, type(int256).min, 0);
    MockSimpleOracleStore badStore = new MockSimpleOracleStore(8);
    badStore.set(answer, START_TIME);
    SimpleOraclePriceOracle badOracle = new SimpleOraclePriceOracle(address(badStore), FEED_ID, 8, MAX_AGE);
    vm.expectRevert(abi.encodeWithSelector(SimpleOraclePriceOracle.InvalidAnswer.selector, answer));
    badOracle.price();
  }

  // Staleness is checked before the answer
  function test_price_staleBeforeAnswer() public {
    MockSimpleOracleStore badStore = new MockSimpleOracleStore(8);
    badStore.set(0, START_TIME - MAX_AGE - 1);
    SimpleOraclePriceOracle badOracle = new SimpleOraclePriceOracle(address(badStore), FEED_ID, 8, MAX_AGE);
    vm.expectRevert(abi.encodeWithSelector(SimpleOraclePriceOracle.StalePrice.selector, MAX_AGE + 1, MAX_AGE));
    badOracle.price();
  }

  function test_cost() public view {
    // 3.47 units at $81.076 is $281.33372
    (uint256 totalCost, uint8 collateralDecimals) = oracle.cost(347e6);
    assertEq(totalCost, 28133372e13, "Cost mismatch");
    assertEq(collateralDecimals, 8, "Collateral decimals mismatch");
  }

  function test_cost_18Decimals() public {
    SimpleOraclePriceOracle oracle18 = new SimpleOraclePriceOracle(address(store), FEED_ID, 18, MAX_AGE);
    // 2.5 units at $81.076 is $202.69
    (uint256 totalCost, uint8 collateralDecimals) = oracle18.cost(25e17);
    assertEq(totalCost, 20269e16, "Cost mismatch");
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
    vm.expectRevert(abi.encodeWithSelector(SimpleOraclePriceOracle.StalePrice.selector, MAX_AGE + 1, MAX_AGE));
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

    vm.warp(START_TIME + 1);
    _push(FEED_ID, answer, START_TIME + 1);
    SimpleOraclePriceOracle sampleOracle =
      new SimpleOraclePriceOracle(address(store), FEED_ID, collateralDecimals, MAX_AGE);

    // Both oracles must report the same price and cost for the same inputs
    assertEq(sampleOracle.price(), pythOracle.price(), "Price mismatch");
    (uint256 totalCost, uint8 _collateralDecimals) = sampleOracle.cost(collateralAmount);
    (uint256 pythTotalCost, uint8 pythCollateralDecimals) = pythOracle.cost(collateralAmount);
    assertEq(totalCost, pythTotalCost, "Cost parity mismatch");
    assertEq(_collateralDecimals, pythCollateralDecimals, "Collateral decimals parity mismatch");
  }

  function _push(bytes32 id, int256 price, uint256 timestamp) internal {
    (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) = store.eip712Domain();
    bytes32 domainSeparator = keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes(name)),
        keccak256(bytes(version)),
        chainId,
        verifyingContract
      )
    );
    bytes32 structHash = keccak256(abi.encode(PRICE_UPDATE_TYPEHASH, id, price, timestamp));
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
    store.updatePrice(id, price, timestamp, abi.encodePacked(r, s, v));
  }
}
