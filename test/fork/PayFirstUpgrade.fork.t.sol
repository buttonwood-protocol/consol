// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PayFirstUpgrade} from "../../script/ops/PayFirstUpgrade.s.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {ILoanManager} from "../../src/interfaces/ILoanManager/ILoanManager.sol";
import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";
import {IUSDX} from "../../src/interfaces/IUSDX/IUSDX.sol";
import {ChainlinkPriceOracle} from "../../src/ChainlinkPriceOracle.sol";
import {AggregatorV3Interface} from "../../src/external/AggregatorV3Interface.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {PurchaseOrder} from "../../src/types/orders/PurchaseOrder.sol";
import {CreationRequest, BaseRequest} from "../../src/types/orders/OrderRequests.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {MockCallbackFulfiller} from "../mocks/MockCallbackFulfiller.sol";

/**
 * @title PayFirstUpgradeForkTest
 * @notice Rehearses PayFirstUpgrade against the live Robinhood Chain (4663) stack with this repo's own
 *         bytecode: deploy, pause, cut over, verify, fill one order through the fulfillment callback and one
 *         with collateral delivered up front, then pause and roll back and fill through the previous pool.
 * @dev Network-gated: the default suite skips it. Run with
 *      `RUN_FORK_TESTS=true forge test --match-path test/fork/PayFirstUpgrade.fork.t.sol -vv`.
 *      Forks the latest block unless PAY_FIRST_FORK_BLOCK is set; the public endpoint keeps little history.
 *      The origination pool only opens for deployment later, so the test warps to its deploy phase and
 *      re-stamps the collateral's Chainlink round, leaving the price itself untouched.
 */
contract PayFirstUpgradeForkTest is Test {
  string internal constant FORK_URL = "https://rpc.mainnet.chain.robinhood.com";
  bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  // Live 4663 addresses that the address book does not carry
  address internal constant ADMIN = 0xd7e86Bd77784217324b4E94AEDc68E5C8227EC2B;
  address internal constant VAULT = 0x5DAaF4cacd8b1EE5Db0715C790c58124c2Dc006f;
  address internal constant GENESIS_POOL = 0x2c331A3c4A38E4EF36d4Ff49Ec977D22E5385e4d;
  address internal constant NVDA_USDG_V3_POOL = 0xd4EB21209C4D6093f80B5b84f5C45cc093EA14a3;
  uint256 internal constant NVDA_INDEX = 6;

  address internal lender = makeAddr("lender");
  address internal borrower = makeAddr("borrower");
  address internal market = makeAddr("market");

  bool internal forkEnabled;
  string internal addressBook;
  IGeneralManager internal generalManager;
  IOrderPool internal previousPool;
  IUSDX internal usdx;
  IERC20 internal usdg;
  IERC20 internal nvda;
  address internal nvdaSubConsol;
  uint256 internal mortgageCount;

  function setUp() public {
    forkEnabled = vm.envOr("RUN_FORK_TESTS", false);
    if (!forkEnabled) {
      return;
    }
    uint256 forkBlock = vm.envOr("PAY_FIRST_FORK_BLOCK", uint256(0));
    if (forkBlock == 0) {
      vm.createSelectFork(FORK_URL);
    } else {
      vm.createSelectFork(FORK_URL, forkBlock);
    }

    addressBook = vm.readFile(string.concat(vm.projectRoot(), "/addresses/addresses-4663.json"));
    generalManager = IGeneralManager(vm.parseJsonAddress(addressBook, ".generalManagerAddress"));
    previousPool = IOrderPool(vm.parseJsonAddress(addressBook, ".orderPoolAddress"));
    usdx = IUSDX(vm.parseJsonAddress(addressBook, ".usdxAddress"));
    usdg = IERC20(vm.parseJsonAddressArray(addressBook, ".usdAddresses")[0]);
    nvda = IERC20(vm.parseJsonAddressArray(addressBook, ".collateralAddresses")[NVDA_INDEX]);
    nvdaSubConsol = vm.parseJsonAddressArray(addressBook, ".subConsolAddresses")[NVDA_INDEX];
  }

  // ---------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------

  function _implementation() internal view returns (address) {
    return address(uint160(uint256(vm.load(address(generalManager), IMPLEMENTATION_SLOT))));
  }

  function _fulfillers() internal pure returns (address[] memory list) {
    list = new address[](2);
    list[0] = VAULT;
    list[1] = ADMIN;
  }

  /// @dev A script instance as one `forge script` invocation would build it
  function _script(address implementation, address pool, address previousImplementation, bool rollbackImplementation)
    internal
    returns (PayFirstUpgrade script)
  {
    script = new PayFirstUpgrade();
    script.setAddressBookJson(addressBook);
    script.setAdmin(ADMIN);
    script.setFulfillers(_fulfillers());
    script.setDeployment(implementation, pool, previousImplementation, rollbackImplementation);
    script.setUp();
  }

  /// @dev USDG cannot be minted, so borrow it from the deep NVDA/USDG v3 pool's balance
  function _dealUsdx(address to, uint256 usdxAmount) internal {
    uint256 usdgAmount = usdx.convertUnderlying(address(usdg), usdxAmount);
    vm.prank(NVDA_USDG_V3_POOL);
    usdg.transfer(to, usdgAmount);
    vm.startPrank(to);
    usdg.approve(address(usdx), usdgAmount);
    usdx.deposit(address(usdg), usdgAmount);
    vm.stopPrank();
  }

  function _dealNvda(address to, uint256 amount) internal {
    vm.prank(NVDA_USDG_V3_POOL);
    nvda.transfer(to, amount);
  }

  /// @dev Funds the genesis pool while it still takes deposits, then moves into its deploy phase and
  ///      re-stamps the NVDA round at the new timestamp with its price unchanged
  function _openBorrowing() internal {
    _dealUsdx(lender, 1_000e18);
    vm.startPrank(lender);
    IERC20(address(usdx)).approve(GENESIS_POOL, 1_000e18);
    IOriginationPool(GENESIS_POOL).deposit(1_000e18);
    vm.stopPrank();

    AggregatorV3Interface aggregator = ChainlinkPriceOracle(generalManager.priceOracles(address(nvda))).aggregator();
    (uint80 roundId, int256 answer, uint256 startedAt,, uint80 answeredInRound) = aggregator.latestRoundData();
    vm.warp(IOriginationPool(GENESIS_POOL).deployPhaseTimestamp());
    vm.mockCall(
      address(aggregator),
      abi.encodeWithSelector(AggregatorV3Interface.latestRoundData.selector),
      abi.encode(roundId, answer, startedAt, block.timestamp, answeredInRound)
    );
  }

  /// @dev The amount of NVDA that costs about `usdValue` at the oracle price
  function _nvdaWorth(uint256 usdValue) internal view returns (uint256) {
    (uint256 costOfOne,) = IPriceOracle(generalManager.priceOracles(address(nvda))).cost(1e18);
    return usdValue * 1e18 / costOfOne;
  }

  /// @dev A borrower requests a non-compounding NVDA mortgage on the live GeneralManager
  function _request(IOrderPool pool) internal returns (uint256 orderId, uint256 tokenId) {
    uint256[] memory collateralAmounts = new uint256[](1);
    collateralAmounts[0] = _nvdaWorth(60e18);
    address[] memory originationPools = new address[](1);
    originationPools[0] = GENESIS_POOL;

    _dealUsdx(borrower, 100e18);
    uint256 gasFee = pool.gasFee();
    vm.deal(borrower, gasFee);
    orderId = pool.orderCount();
    vm.startPrank(borrower);
    IERC20(address(usdx)).approve(address(generalManager), type(uint256).max);
    tokenId = generalManager.requestMortgageCreation{value: gasFee}(
      CreationRequest({
        base: BaseRequest({
          collateralAmounts: collateralAmounts,
          totalPeriods: 36,
          originationPools: originationPools,
          isCompounding: false,
          expiration: block.timestamp + 1 minutes
        }),
        mortgageId: string.concat("rehearsal-", vm.toString(mortgageCount++)),
        collateral: address(nvda),
        subConsol: nvdaSubConsol,
        conversionQueues: new address[](0),
        hasPaymentPlan: true
      })
    );
    vm.stopPrank();
  }

  function _fillArgs(uint256 orderId) internal pure returns (uint256[] memory indices, uint256[][] memory hints) {
    indices = new uint256[](1);
    indices[0] = orderId;
    hints = new uint256[][](1);
    hints[0] = new uint256[](0);
  }

  /// @dev The admin, which holds FULFILLMENT_ROLE, delivers the collateral up front
  function _fillUpfront(IOrderPool pool, uint256 orderId) internal {
    PurchaseOrder memory order = pool.orders(orderId);
    uint256 collateralRequested = order.mortgageParams.collateralAmount - order.orderAmounts.collateralCollected;
    _dealNvda(ADMIN, collateralRequested);
    (uint256[] memory indices, uint256[][] memory hints) = _fillArgs(orderId);
    vm.startPrank(ADMIN);
    nvda.approve(address(pool), collateralRequested);
    pool.processOrders(indices, hints);
    vm.stopPrank();
  }

  function _assertMortgage(uint256 tokenId, uint256 collateralAmount) internal view {
    MortgagePosition memory position = ILoanManager(generalManager.loanManager()).getMortgagePosition(tokenId);
    assertEq(position.collateral, address(nvda), "mortgage collateral");
    assertEq(position.collateralAmount, collateralAmount, "mortgage collateral amount");
    assertEq(IERC20(address(usdx)).balanceOf(address(generalManager)), 0, "GeneralManager USDX");
    assertEq(nvda.balanceOf(address(generalManager)), 0, "GeneralManager collateral");
  }

  // ---------------------------------------------------------------------------------------------
  // Rehearsal
  // ---------------------------------------------------------------------------------------------

  function test_fork_rehearsal() public {
    if (!forkEnabled) {
      vm.skip(true);
    }
    console.log("Fork block:", block.number);
    address implementationBefore = _implementation();
    assertEq(generalManager.orderPool(), address(previousPool), "live order pool matches the address book");
    assertEq(previousPool.orderCount(), 0, "no order was ever placed");

    // 1. Deploy: nothing live changes
    PayFirstUpgrade deployed = _script(address(0), address(0), address(0), false);
    deployed.run();
    address implementation = deployed.newImplementation();
    IOrderPool newPool = deployed.newOrderPool();
    assertEq(_implementation(), implementationBefore, "implementation untouched by the deploy run");
    assertEq(generalManager.orderPool(), address(previousPool), "order pool untouched by the deploy run");
    assertLe(implementation.code.length, 24_576, "implementation fits EIP-170");
    console.log("GeneralManager implementation runtime size:", implementation.code.length);

    // 2. Pause, 3. cut over, 4. verify
    _script(implementation, address(newPool), implementationBefore, false).pause();
    assertTrue(generalManager.paused(), "paused");
    _script(implementation, address(newPool), implementationBefore, false).cutover();
    _script(implementation, address(newPool), implementationBefore, false).verify();
    assertEq(_implementation(), implementation, "implementation");
    assertEq(generalManager.orderPool(), address(newPool), "order pool");
    assertEq(newPool.gasFee(), previousPool.gasFee(), "gas fee");
    assertEq(newPool.maximumOrderDuration(), previousPool.maximumOrderDuration(), "maximum order duration");
    assertTrue(IAccessControl(address(newPool)).hasRole(Roles.FULFILLMENT_ROLE, VAULT), "vault can fulfill");
    assertTrue(IAccessControl(address(newPool)).hasRole(Roles.FULFILLMENT_ROLE, ADMIN), "admin can fulfill");

    // 5. Fill through the callback: the fulfiller starts with no USDX and is paid before it delivers
    _openBorrowing();
    MockCallbackFulfiller fulfiller = new MockCallbackFulfiller(newPool, IERC20(address(usdx)), market);
    vm.prank(ADMIN);
    IAccessControl(address(newPool)).grantRole(Roles.FULFILLMENT_ROLE, address(fulfiller));
    fulfiller.setDelivery(MockCallbackFulfiller.Delivery.FromInventory);

    (uint256 orderId, uint256 tokenId) = _request(newPool);
    PurchaseOrder memory order = newPool.orders(orderId);
    uint256 collateralAmount = order.mortgageParams.collateralAmount;
    _dealNvda(address(fulfiller), collateralAmount);
    assertEq(IERC20(address(usdx)).balanceOf(address(fulfiller)), 0, "fulfiller starts with no USDX");
    {
      (uint256[] memory indices, uint256[][] memory hints) = _fillArgs(orderId);
      bytes[] memory data = new bytes[](1);
      data[0] = abi.encode(uint256(0));
      fulfiller.fill(indices, hints, data);
    }
    assertEq(
      fulfiller.lastUsdxAmount(), order.orderAmounts.purchaseAmount - Constants.FULFILLMENT_HOLDBACK_PER_POOL, "advance"
    );
    assertEq(fulfiller.lastUsdxBalance(), fulfiller.lastUsdxAmount(), "advance held during the callback");
    assertEq(IERC20(address(usdx)).balanceOf(address(fulfiller)), order.orderAmounts.purchaseAmount, "fulfiller paid");
    _assertMortgage(tokenId, collateralAmount);
    console.log("Callback fill: order", orderId, "purchase amount", order.orderAmounts.purchaseAmount);

    // 6. Upfront delivery still works on the new pool
    (orderId, tokenId) = _request(newPool);
    _fillUpfront(newPool, orderId);
    _assertMortgage(tokenId, collateralAmount);
    console.log("Upfront fill on the new pool: order", orderId);

    // 7. Roll back to the previous pool, keeping the new implementation, and fill through it
    _script(implementation, address(newPool), implementationBefore, false).pause();
    _script(implementation, address(newPool), implementationBefore, false).rollback();
    assertEq(generalManager.orderPool(), address(previousPool), "back on the previous order pool");
    assertEq(_implementation(), implementation, "new implementation kept");
    (orderId, tokenId) = _request(previousPool);
    _fillUpfront(previousPool, orderId);
    _assertMortgage(tokenId, collateralAmount);
    console.log("Upfront fill on the previous pool after rollback: order", orderId);
  }

  function test_fork_rollbackRestoresThePreviousImplementation() public {
    if (!forkEnabled) {
      vm.skip(true);
    }
    address implementationBefore = _implementation();
    PayFirstUpgrade deployed = _script(address(0), address(0), address(0), false);
    deployed.run();
    address implementation = deployed.newImplementation();
    address newPool = address(deployed.newOrderPool());
    _script(implementation, newPool, implementationBefore, false).pause();
    _script(implementation, newPool, implementationBefore, false).cutover();

    _script(implementation, newPool, implementationBefore, true).pause();
    _script(implementation, newPool, implementationBefore, true).rollback();
    assertEq(_implementation(), implementationBefore, "previous implementation restored");
    assertEq(generalManager.orderPool(), address(previousPool), "previous order pool restored");

    // The restored stack originates as before
    _openBorrowing();
    (uint256 orderId, uint256 tokenId) = _request(previousPool);
    uint256 collateralAmount = previousPool.orders(orderId).mortgageParams.collateralAmount;
    _fillUpfront(previousPool, orderId);
    _assertMortgage(tokenId, collateralAmount);
  }
}
