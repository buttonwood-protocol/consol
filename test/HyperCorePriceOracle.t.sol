// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {HyperCorePriceOracle} from "../src/HyperCorePriceOracle.sol";
import {PythPriceOracle} from "../src/PythPriceOracle.sol";
import {MockHyperCorePrecompile} from "./mocks/MockHyperCorePrecompile.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract HyperCorePriceOracleTest is Test {
  // Mirrors the head layout returned by the perp asset info precompile
  struct PerpAssetInfo {
    string coin;
    uint32 marginTableId;
    uint8 szDecimals;
    uint8 maxLeverage;
    bool onlyIsolated;
  }

  // Constants
  uint32 public constant HYPE_PERP_INDEX = 159;
  uint8 public constant HYPE_SZ_DECIMALS = 2;
  address public constant MARK_PX_PRECOMPILE = 0x0000000000000000000000000000000000000806;
  address public constant ORACLE_PX_PRECOMPILE = 0x0000000000000000000000000000000000000807;
  address public constant PERP_ASSET_INFO_PRECOMPILE = 0x000000000000000000000000000000000000080a;

  // Contracts
  HyperCorePriceOracle public oracle;

  function setUp() public virtual {
    // Etch the mock precompile code at the precompile addresses
    MockHyperCorePrecompile mockPrecompile = new MockHyperCorePrecompile();
    vm.etch(MARK_PX_PRECOMPILE, address(mockPrecompile).code);
    vm.etch(ORACLE_PX_PRECOMPILE, address(mockPrecompile).code);
    vm.etch(PERP_ASSET_INFO_PRECOMPILE, address(mockPrecompile).code);

    // Set default responses for HYPE and deploy the oracle without a deviation guard
    _setPerpAssetInfo(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS);
    _setOraclePx(HYPE_PERP_INDEX, 810760);
    _setMarkPx(HYPE_PERP_INDEX, 810320);
    oracle = new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 8, 0, "HYPE");
  }

  function test_constructor() public view {
    assertEq(oracle.perpIndex(), HYPE_PERP_INDEX, "Perp index mismatch");
    assertEq(oracle.szDecimals(), HYPE_SZ_DECIMALS, "Size decimals mismatch");
    assertEq(oracle.collateralDecimals(), 8, "Collateral decimals mismatch");
    assertEq(oracle.maxDeviationBps(), 0, "Max deviation mismatch");
    assertEq(oracle.priceScale(), 1e14, "Price scale mismatch");
  }

  function test_constructor_invalidSzDecimals(uint8 szDecimals) public {
    szDecimals = uint8(bound(szDecimals, 7, type(uint8).max));
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.InvalidSzDecimals.selector, szDecimals));
    new HyperCorePriceOracle(HYPE_PERP_INDEX, szDecimals, 8, 0, "HYPE");
  }

  function test_constructor_szDecimalsMismatch() public {
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.SzDecimalsMismatch.selector, 3, HYPE_SZ_DECIMALS));
    new HyperCorePriceOracle(HYPE_PERP_INDEX, 3, 8, 0, "HYPE");
  }

  function test_constructor_coinMismatch() public {
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.CoinMismatch.selector, "BTC", "HYPE"));
    new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 8, 0, "BTC");
  }

  // A mistyped index that happens to share size decimals must still be rejected
  function test_constructor_coinMismatch_sameSzDecimals() public {
    uint32 wrongIndex = 132;
    _setPerpAssetInfoCoin(wrongIndex, "ICP", HYPE_SZ_DECIMALS);
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.CoinMismatch.selector, "HYPE", "ICP"));
    new HyperCorePriceOracle(wrongIndex, HYPE_SZ_DECIMALS, 8, 0, "HYPE");
  }

  function test_constructor_perpAssetInfoFailure(uint32 perpIndex) public {
    // No perp asset info response is configured for this index, so the mock consumes all forwarded gas
    vm.assume(perpIndex != HYPE_PERP_INDEX);
    vm.expectRevert(
      abi.encodeWithSelector(HyperCorePriceOracle.PrecompileCallFailed.selector, PERP_ASSET_INFO_PRECOMPILE)
    );
    new HyperCorePriceOracle(perpIndex, 2, 8, 0, "HYPE");
  }

  function test_constructor_nonBooleanOnlyIsolated() public {
    // HyperCore encodes onlyIsolated as a non-boolean word for some assets; the constructor must tolerate it
    uint32 perpIndex = 135;
    bytes memory response = abi.encode(PerpAssetInfo("HYPE", 10, 2, 10, false));
    // The onlyIsolated field is the fifth head word (bytes 160-191); set its low byte to a non-boolean value
    response[191] = 0x10;
    MockHyperCorePrecompile(PERP_ASSET_INFO_PRECOMPILE).setResponse(perpIndex, response);
    _setOraclePx(perpIndex, 360960);
    HyperCorePriceOracle testnetOracle = new HyperCorePriceOracle(perpIndex, 2, 18, 0, "HYPE");
    assertEq(testnetOracle.price(), 360960e14, "Price mismatch");
  }

  function test_price_szDecimals0() public {
    uint32 perpIndex = 1;
    _setPerpAssetInfo(perpIndex, 0);
    // 0 size decimals means the raw price has 6 decimals: 81076000 is $81.076
    _setOraclePx(perpIndex, 81076000);
    HyperCorePriceOracle sampleOracle = new HyperCorePriceOracle(perpIndex, 0, 8, 0, "HYPE");
    assertEq(sampleOracle.priceScale(), 1e12, "Price scale mismatch");
    assertEq(sampleOracle.price(), 81_076e15, "Price mismatch");
  }

  function test_price_szDecimals2() public view {
    // 2 size decimals means the raw price has 4 decimals: 810760 is $81.076
    assertEq(oracle.price(), 81_076e15, "Price mismatch");
  }

  function test_price_szDecimals5() public {
    uint32 perpIndex = 2;
    _setPerpAssetInfo(perpIndex, 5);
    // 5 size decimals means the raw price has 1 decimal: 8110 is $811.0
    _setOraclePx(perpIndex, 8110);
    HyperCorePriceOracle sampleOracle = new HyperCorePriceOracle(perpIndex, 5, 18, 0, "HYPE");
    assertEq(sampleOracle.priceScale(), 1e17, "Price scale mismatch");
    assertEq(sampleOracle.price(), 811e18, "Price mismatch");
  }

  function test_price_zeroPrice() public {
    _setOraclePx(HYPE_PERP_INDEX, 0);
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.ZeroPrice.selector));
    oracle.price();
  }

  function test_price_deviationGuard_withinBand() public {
    HyperCorePriceOracle guardedOracle = new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 8, 50, "HYPE");
    _setOraclePx(HYPE_PERP_INDEX, 1000000);

    // A deviation of exactly the maximum (50 bps) is allowed
    _setMarkPx(HYPE_PERP_INDEX, 1005000);
    assertEq(guardedOracle.price(), 1000000e14, "Price mismatch");
    _setMarkPx(HYPE_PERP_INDEX, 995000);
    assertEq(guardedOracle.price(), 1000000e14, "Price mismatch");
  }

  function test_price_deviationGuard_markAbove() public {
    HyperCorePriceOracle guardedOracle = new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 8, 50, "HYPE");
    _setOraclePx(HYPE_PERP_INDEX, 1000000);
    _setMarkPx(HYPE_PERP_INDEX, 1005100);
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.MaxDeviationExceeded.selector, 51, 50));
    guardedOracle.price();
  }

  function test_price_deviationGuard_markBelow() public {
    HyperCorePriceOracle guardedOracle = new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 8, 50, "HYPE");
    _setOraclePx(HYPE_PERP_INDEX, 1000000);
    _setMarkPx(HYPE_PERP_INDEX, 994900);
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.MaxDeviationExceeded.selector, 51, 50));
    guardedOracle.price();
  }

  function test_price_deviationGuard_disabled() public {
    // The mark price is wildly off and its precompile is set to consume all forwarded gas, but with the guard
    // disabled the mark price precompile is never called
    _setMarkPx(HYPE_PERP_INDEX, 8107600);
    MockHyperCorePrecompile(MARK_PX_PRECOMPILE).setConsumeAllGas(true);
    assertEq(oracle.price(), 81_076e15, "Price mismatch");
  }

  function test_price_deviationGuard_markPxFailure() public {
    HyperCorePriceOracle guardedOracle = new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 8, 50, "HYPE");
    MockHyperCorePrecompile(MARK_PX_PRECOMPILE).setConsumeAllGas(true);
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.PrecompileCallFailed.selector, MARK_PX_PRECOMPILE));
    guardedOracle.price();
  }

  function test_price_precompileFailure() public {
    MockHyperCorePrecompile(ORACLE_PX_PRECOMPILE).setConsumeAllGas(true);
    vm.expectRevert(abi.encodeWithSelector(HyperCorePriceOracle.PrecompileCallFailed.selector, ORACLE_PX_PRECOMPILE));
    oracle.price();
  }

  function test_price_precompileFailureBoundedGas() public {
    // The mock consumes all gas forwarded into the precompile call, so a bounded failure proves the oracle caps
    // the gas it forwards
    MockHyperCorePrecompile(ORACLE_PX_PRECOMPILE).setConsumeAllGas(true);
    uint256 gasBefore = gasleft();
    try oracle.price() returns (uint256) {
      fail();
    } catch {}
    uint256 gasUsed = gasBefore - gasleft();
    assertLt(gasUsed, 150_000, "Precompile failure consumed unbounded gas");
  }

  function test_cost_parityWithPythPriceOracle() public {
    // Configure a Pyth oracle reporting the same price ($81.076) for the same 8-decimal collateral
    MockPyth pyth = new MockPyth(60, 0);
    bytes32 priceId = bytes32(uint256(1));
    bytes[] memory updateData = new bytes[](1);
    updateData[0] = pyth.createPriceFeedUpdateData(
      priceId, 81_07600000, 0, -8, 81_07600000, 0, uint64(block.timestamp), uint64(block.timestamp)
    );
    pyth.updatePriceFeeds(updateData);
    PythPriceOracle pythOracle = new PythPriceOracle(address(pyth), priceId, 1e18, 8);

    // Both oracles must report the same price and cost for the same inputs
    assertEq(oracle.price(), pythOracle.price(), "Price mismatch");
    (uint256 totalCost, uint8 collateralDecimals) = oracle.cost(347e6);
    (uint256 pythTotalCost, uint8 pythCollateralDecimals) = pythOracle.cost(347e6);
    assertEq(totalCost, 28133372e13, "Cost mismatch");
    assertEq(totalCost, pythTotalCost, "Cost parity mismatch");
    assertEq(collateralDecimals, pythCollateralDecimals, "Collateral decimals parity mismatch");
  }

  function test_cost(uint256 collateralAmount) public view {
    collateralAmount = bound(collateralAmount, 0, 1e40);
    (uint256 totalCost, uint8 collateralDecimals) = oracle.cost(collateralAmount);
    assertEq(totalCost, Math.mulDiv(collateralAmount, oracle.price(), 1e8), "Cost mismatch");
    assertEq(collateralDecimals, 8, "Collateral decimals mismatch");
  }

  function _setOraclePx(uint32 perpIndex, uint64 px) internal {
    MockHyperCorePrecompile(ORACLE_PX_PRECOMPILE).setResponse(perpIndex, abi.encode(px));
  }

  function _setMarkPx(uint32 perpIndex, uint64 px) internal {
    MockHyperCorePrecompile(MARK_PX_PRECOMPILE).setResponse(perpIndex, abi.encode(px));
  }

  function _setPerpAssetInfo(uint32 perpIndex, uint8 szDecimals) internal {
    _setPerpAssetInfoCoin(perpIndex, "HYPE", szDecimals);
  }

  function _setPerpAssetInfoCoin(uint32 perpIndex, string memory coin, uint8 szDecimals) internal {
    bytes memory response = abi.encode(PerpAssetInfo(coin, 52, szDecimals, 10, false));
    MockHyperCorePrecompile(PERP_ASSET_INFO_PRECOMPILE).setResponse(perpIndex, response);
  }
}

contract HyperCorePriceOracleForkTest is Test {
  // HYPE perp index and size decimals on HyperEVM mainnet (chain 999)
  uint32 public constant HYPE_PERP_INDEX = 159;
  uint8 public constant HYPE_SZ_DECIMALS = 2;

  function _forkOrSkip() internal returns (bool forked) {
    string memory rpc = vm.envOr("HYPERLIQUID_RPC", string(""));
    if (bytes(rpc).length == 0) {
      vm.skip(true);
      return false;
    }
    vm.createSelectFork(rpc);

    // The HyperCore precompiles are implemented by the node rather than as EVM bytecode, so the forked EVM cannot
    // execute them directly. Fetch the real responses over RPC and serve them from the mock at the precompile
    // addresses instead
    MockHyperCorePrecompile mockPrecompile = new MockHyperCorePrecompile();
    _mirrorPrecompile(0x0000000000000000000000000000000000000806, address(mockPrecompile).code);
    _mirrorPrecompile(0x0000000000000000000000000000000000000807, address(mockPrecompile).code);
    _mirrorPrecompile(0x000000000000000000000000000000000000080a, address(mockPrecompile).code);
    return true;
  }

  function _mirrorPrecompile(address precompile, bytes memory mockCode) internal {
    bytes memory response = vm.rpc(
      "eth_call",
      string.concat(
        '[{"to":"', vm.toString(precompile), '","data":"', vm.toString(abi.encode(HYPE_PERP_INDEX)), '"},"latest"]'
      )
    );
    vm.etch(precompile, mockCode);
    MockHyperCorePrecompile(precompile).setResponse(HYPE_PERP_INDEX, response);
  }

  function test_fork_price() public {
    if (!_forkOrSkip()) return;

    // The constructor validates the size decimals against the real perp asset info precompile
    HyperCorePriceOracle oracle = new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 18, 0, "HYPE");
    uint256 price = oracle.price();

    // Sanity bounds for HYPE in USD (18 decimals)
    assertGt(price, 1e18, "Price implausibly low");
    assertLt(price, 100_000e18, "Price implausibly high");

    (uint256 totalCost, uint8 collateralDecimals) = oracle.cost(25e17);
    assertEq(totalCost, Math.mulDiv(25e17, price, 1e18), "Cost mismatch");
    assertEq(collateralDecimals, 18, "Collateral decimals mismatch");
  }

  function test_fork_price_deviationGuard() public {
    if (!_forkOrSkip()) return;

    // A 100% band should never trip under normal market conditions
    HyperCorePriceOracle guardedOracle = new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 18, 10_000, "HYPE");
    HyperCorePriceOracle unguardedOracle = new HyperCorePriceOracle(HYPE_PERP_INDEX, HYPE_SZ_DECIMALS, 18, 0, "HYPE");
    assertEq(guardedOracle.price(), unguardedOracle.price(), "Price mismatch");
  }
}
