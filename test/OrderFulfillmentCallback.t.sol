// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGeneralManagerErrors} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IGeneralManagerEvents} from "../src/interfaces/IGeneralManager/IGeneralManagerEvents.sol";
import {IOrderPoolErrors} from "../src/interfaces/IOrderPool/IOrderPoolErrors.sol";
import {IOrderPoolEvents} from "../src/interfaces/IOrderPool/IOrderPoolEvents.sol";
import {IOriginationPool} from "../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IOriginationPoolDeployCallback} from "../src/interfaces/IOriginationPoolDeployCallback.sol";
import {IOrderFulfillmentCallback} from "../src/interfaces/IOrderFulfillmentCallback.sol";
import {OriginationPoolConfig} from "../src/types/OriginationPoolConfig.sol";
import {OPoolConfigIdLibrary} from "../src/types/OPoolConfigId.sol";
import {MortgagePosition} from "../src/types/MortgagePosition.sol";
import {PurchaseOrder} from "../src/types/orders/PurchaseOrder.sol";
import {OriginationParameters} from "../src/types/orders/OriginationParameters.sol";
import {CreationRequest, ExpansionRequest, BaseRequest} from "../src/types/orders/OrderRequests.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {Constants} from "../src/libraries/Constants.sol";
import {OrderPool} from "../src/OrderPool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockCallbackFulfiller} from "./mocks/MockCallbackFulfiller.sol";

contract OrderFulfillmentCallbackTest is BaseTest {
  using OPoolConfigIdLibrary for OriginationPoolConfig;

  MockCallbackFulfiller public callbackFulfiller;
  IOriginationPool public secondOriginationPool;
  address public protocolFeeRecipient = makeAddr("protocolFeeRecipient");
  address public market = makeAddr("market");

  uint16 public constant ORIGINATION_FEE_RATE = 100;

  // Everything an origination moves, for comparing the two delivery paths
  struct Outcome {
    uint256 fulfillerUsdx;
    uint256 feeRecipientUsdx;
    uint256 generalManagerUsdx;
    uint256 generalManagerConsol;
    uint256 generalManagerCollateral;
    uint256 firstPoolConsol;
    uint256 secondPoolConsol;
    uint256 firstPoolUsdx;
    uint256 secondPoolUsdx;
    uint256 consolTotalSupply;
    uint256 subConsolCollateral;
    uint256 amountBorrowed;
    uint256 collateralAmount;
    uint256 termBalance;
    address mortgageOwner;
  }

  function setUp() public override {
    super.setUp();

    // The callback fulfiller holds the fulfillment role but no USDX and no collateral
    callbackFulfiller = new MockCallbackFulfiller(orderPool, IERC20(address(usdx)), market);
    vm.startPrank(admin);
    orderPool.grantRole(Roles.FULFILLMENT_ROLE, address(callbackFulfiller));
    vm.stopPrank();

    // A second origination pool with a different multiplier
    OriginationPoolConfig memory secondConfig = originationPoolConfig;
    secondConfig.namePrefix = "Second Origination Pool";
    secondConfig.symbolPrefix = "SOP";
    secondConfig.poolMultiplierBps = 137;
    vm.startPrank(admin);
    originationPoolScheduler.addConfig(secondConfig);
    vm.stopPrank();
    secondOriginationPool = IOriginationPool(originationPoolScheduler.deployOriginationPool(secondConfig.toId()));

    // Fund both pools and move into the deploy phase
    _mintUsdx(lender, 1_212_000e18);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 606_000e18);
    originationPool.deposit(606_000e18);
    usdx.approve(address(secondOriginationPool), 606_000e18);
    secondOriginationPool.deposit(606_000e18);
    vm.stopPrank();
    vm.warp(originationPool.deployPhaseTimestamp());

    // The borrower can cover any request made in these tests
    _mintUsdx(borrower, 5_000_000e18);
    MockERC20(address(wbtc)).mint(borrower, 1_000e8);
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), type(uint256).max);
    wbtc.approve(address(generalManager), type(uint256).max);
    vm.stopPrank();

    _setPrice(100_000e8);
  }

  function _setPrice(uint256 price) internal {
    _setPythPrice(BTC_PRICE_ID, int64(uint64(price)), 100e8, -8, block.timestamp);
  }

  function _enableFee() internal {
    vm.startPrank(admin);
    generalManager.setOriginationFeeRate(ORIGINATION_FEE_RATE);
    generalManager.setFeeRecipient(protocolFeeRecipient);
    vm.stopPrank();
  }

  function _buildRequest(uint256 collateralAmount, bool compounding, bool twoPools, string memory mortgageId)
    internal
    view
    returns (CreationRequest memory creationRequest)
  {
    uint256[] memory collateralAmounts;
    address[] memory originationPools;
    if (twoPools) {
      collateralAmounts = new uint256[](2);
      collateralAmounts[0] = collateralAmount / 3;
      collateralAmounts[1] = collateralAmount - collateralAmounts[0];
      originationPools = new address[](2);
      originationPools[0] = address(originationPool);
      originationPools[1] = address(secondOriginationPool);
    } else {
      collateralAmounts = new uint256[](1);
      collateralAmounts[0] = collateralAmount;
      originationPools = new address[](1);
      originationPools[0] = address(originationPool);
    }
    address[] memory conversionQueueList;
    if (compounding) {
      conversionQueueList = new address[](1);
      conversionQueueList[0] = address(conversionQueue);
    }
    creationRequest = CreationRequest({
      base: BaseRequest({
        collateralAmounts: collateralAmounts,
        totalPeriods: DEFAULT_MORTGAGE_PERIODS,
        originationPools: originationPools,
        isCompounding: compounding,
        expiration: block.timestamp + 1 minutes
      }),
      mortgageId: mortgageId,
      collateral: address(wbtc),
      subConsol: address(subConsol),
      conversionQueues: conversionQueueList,
      hasPaymentPlan: true
    });
  }

  function _request(uint256 collateralAmount, bool compounding, bool twoPools)
    internal
    returns (uint256 orderId, uint256 tokenId)
  {
    orderId = orderPool.orderCount();
    vm.startPrank(borrower);
    tokenId = generalManager.requestMortgageCreation(
      _buildRequest(collateralAmount, compounding, twoPools, vm.toString(orderId))
    );
    vm.stopPrank();
  }

  function _collateralRequested(uint256 orderId) internal view returns (uint256) {
    PurchaseOrder memory order = orderPool.orders(orderId);
    return order.mortgageParams.collateralAmount - order.orderAmounts.collateralCollected;
  }

  function _fillArgs(uint256 orderId, uint256 usdxSpend)
    internal
    view
    returns (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList)
  {
    indices = new uint256[](1);
    indices[0] = orderId;
    hintPrevIdsList = new uint256[][](1);
    hintPrevIdsList[0] = new uint256[](orderPool.orders(orderId).conversionQueues.length);
    fulfillerDataList = new bytes[](1);
    fulfillerDataList[0] = abi.encode(usdxSpend);
  }

  function _fillWithCallback(uint256 orderId, uint256 usdxSpend) internal {
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, usdxSpend);
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  function _fillUpfront(uint256 orderId) internal {
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList,) = _fillArgs(orderId, 0);
    uint256 collateralRequested = _collateralRequested(orderId);
    MockERC20(address(wbtc)).mint(fulfiller, collateralRequested);
    vm.startPrank(fulfiller);
    wbtc.approve(address(orderPool), collateralRequested);
    orderPool.processOrders(indices, hintPrevIdsList);
    vm.stopPrank();
  }

  function _outcome(address fulfiller_, uint256 tokenId) internal view returns (Outcome memory outcome) {
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(tokenId);
    outcome = Outcome({
      fulfillerUsdx: usdx.balanceOf(fulfiller_),
      feeRecipientUsdx: usdx.balanceOf(protocolFeeRecipient),
      generalManagerUsdx: usdx.balanceOf(address(generalManager)),
      generalManagerConsol: consol.balanceOf(address(generalManager)),
      generalManagerCollateral: wbtc.balanceOf(address(generalManager)),
      firstPoolConsol: consol.balanceOf(address(originationPool)),
      secondPoolConsol: consol.balanceOf(address(secondOriginationPool)),
      firstPoolUsdx: usdx.balanceOf(address(originationPool)),
      secondPoolUsdx: usdx.balanceOf(address(secondOriginationPool)),
      consolTotalSupply: consol.totalSupply(),
      subConsolCollateral: wbtc.balanceOf(address(subConsol)),
      amountBorrowed: mortgagePosition.amountBorrowed,
      collateralAmount: mortgagePosition.collateralAmount,
      termBalance: mortgagePosition.termBalance,
      mortgageOwner: mortgageNFT.ownerOf(tokenId)
    });
  }

  function _assertSameOutcome(Outcome memory a, Outcome memory b) internal pure {
    assertEq(a.fulfillerUsdx, b.fulfillerUsdx, "fulfiller USDX");
    assertEq(a.feeRecipientUsdx, b.feeRecipientUsdx, "fee recipient USDX");
    assertEq(a.generalManagerUsdx, b.generalManagerUsdx, "GeneralManager USDX");
    assertEq(a.generalManagerConsol, b.generalManagerConsol, "GeneralManager Consol");
    assertEq(a.generalManagerCollateral, b.generalManagerCollateral, "GeneralManager collateral");
    assertEq(a.firstPoolConsol, b.firstPoolConsol, "first pool Consol");
    assertEq(a.secondPoolConsol, b.secondPoolConsol, "second pool Consol");
    assertEq(a.firstPoolUsdx, b.firstPoolUsdx, "first pool USDX");
    assertEq(a.secondPoolUsdx, b.secondPoolUsdx, "second pool USDX");
    assertEq(a.consolTotalSupply, b.consolTotalSupply, "Consol total supply");
    assertEq(a.subConsolCollateral, b.subConsolCollateral, "SubConsol collateral");
    assertEq(a.amountBorrowed, b.amountBorrowed, "amount borrowed");
    assertEq(a.collateralAmount, b.collateralAmount, "collateral amount");
    assertEq(a.termBalance, b.termBalance, "term balance");
    assertEq(a.mortgageOwner, b.mortgageOwner, "mortgage owner");
  }

  // ---------------------------------------------------------------------------------------------
  // Happy paths
  // ---------------------------------------------------------------------------------------------

  function test_callback_fillsWithNoFulfillerCapital_nonCompounding() public {
    (uint256 orderId, uint256 tokenId) = _request(2e8, false, false);
    PurchaseOrder memory order = orderPool.orders(orderId);
    uint256 purchaseAmount = order.orderAmounts.purchaseAmount;
    uint256 holdback = Constants.FULFILLMENT_HOLDBACK_PER_POOL;
    uint256 usdxSpend = purchaseAmount - 1_000e18;

    assertEq(usdx.balanceOf(address(callbackFulfiller)), 0, "fulfiller starts with no USDX");
    assertEq(wbtc.balanceOf(address(callbackFulfiller)), 0, "fulfiller starts with no collateral");

    vm.expectEmit(true, true, true, true, address(orderPool));
    emit IOrderPoolEvents.PurchaseOrderFilled(orderId);
    _fillWithCallback(orderId, usdxSpend);

    // The callback saw the order's terms and already held the advance
    assertEq(callbackFulfiller.callbackCount(), 1, "one callback");
    assertEq(callbackFulfiller.lastCaller(), address(generalManager), "called by the GeneralManager");
    assertEq(callbackFulfiller.lastTokenId(), tokenId, "tokenId");
    assertEq(callbackFulfiller.lastCollateral(), address(wbtc), "collateral");
    assertEq(callbackFulfiller.lastCollateralAmount(), 2e8, "collateral requested");
    assertEq(callbackFulfiller.lastUsdxAmount(), purchaseAmount - holdback, "advance");
    assertEq(callbackFulfiller.lastUsdxBalance(), purchaseAmount - holdback, "advance held during the callback");
    assertEq(callbackFulfiller.lastData(), abi.encode(usdxSpend), "fulfiller data");
    assertTrue(callbackFulfiller.lastGuardEntered(), "guard reported as entered during the callback");
    assertFalse(generalManager.reentrancyGuardEntered(), "guard released after the fill");

    // The market was paid out of the advance and the fulfiller kept the rest
    assertEq(usdx.balanceOf(market), usdxSpend, "market paid");
    assertApproxEqAbs(usdx.balanceOf(address(callbackFulfiller)), 1_000e18, 2, "fulfiller keeps the spread");
    assertEq(wbtc.balanceOf(address(callbackFulfiller)), 0, "fulfiller holds no collateral");

    // The mortgage exists and nothing is stranded in the GeneralManager
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(tokenId);
    assertEq(mortgagePosition.collateralAmount, 2e8, "collateral amount");
    assertEq(mortgagePosition.amountBorrowed, order.mortgageParams.amountBorrowed, "amount borrowed");
    assertEq(mortgageNFT.ownerOf(tokenId), borrower, "mortgage owner");
    assertEq(usdx.balanceOf(address(generalManager)), 0, "GeneralManager USDX");
    assertEq(wbtc.balanceOf(address(generalManager)), 0, "GeneralManager collateral");
    assertEq(orderPool.orders(orderId).mortgageParams.collateral, address(0), "order deleted");
  }

  function test_reentrancyGuardEntered_isFalseOutsideACall() public view {
    assertFalse(generalManager.reentrancyGuardEntered(), "guard not entered at rest");
  }

  function test_callback_fillsWithNoFulfillerCapital_compounding() public {
    _enableFee();
    (uint256 orderId, uint256 tokenId) = _request(2e8, true, true);
    PurchaseOrder memory order = orderPool.orders(orderId);
    uint256 collateralRequested = _collateralRequested(orderId);
    assertGt(collateralRequested, 0, "collateral requested");
    assertLt(collateralRequested, 2e8, "borrower supplied part of the collateral");

    _fillWithCallback(orderId, 0);

    assertEq(callbackFulfiller.lastCollateralAmount(), collateralRequested, "collateral requested");
    assertEq(
      callbackFulfiller.lastUsdxAmount(),
      order.orderAmounts.purchaseAmount - 2 * Constants.FULFILLMENT_HOLDBACK_PER_POOL,
      "advance"
    );
    assertEq(usdx.balanceOf(address(callbackFulfiller)), order.orderAmounts.purchaseAmount, "fulfiller paid in full");
    assertGt(usdx.balanceOf(protocolFeeRecipient), 0, "fee collected");
    assertEq(loanManager.getMortgagePosition(tokenId).collateralAmount, 2e8, "collateral amount");
    assertEq(usdx.balanceOf(address(generalManager)), 0, "GeneralManager USDX");
    assertEq(wbtc.balanceOf(address(generalManager)), 0, "GeneralManager collateral");
  }

  function test_callback_feeRecipientReceivesSurplus() public {
    _enableFee();
    (uint256 orderId, uint256 tokenId) = _request(2e8, false, false);
    uint256 purchaseAmount = orderPool.orders(orderId).orderAmounts.purchaseAmount;

    vm.expectEmit(true, true, false, false, address(generalManager));
    emit IGeneralManagerEvents.OriginationFeeCollected(tokenId, protocolFeeRecipient, 0);
    _fillWithCallback(orderId, 0);

    assertEq(usdx.balanceOf(address(callbackFulfiller)), purchaseAmount, "fulfiller paid exactly the purchase amount");
    assertApproxEqAbs(
      usdx.balanceOf(protocolFeeRecipient), purchaseAmount * ORIGINATION_FEE_RATE / Constants.BPS, 4, "fee"
    );
  }

  function test_callback_expansion() public {
    // Create a mortgage owned by the balance sheet expander through the upfront path
    _requestNoncompoundingPaymentPlanMortgage(balanceSheetExpander, "expandable", 100_000e18, 2e8, address(0));
    uint256 tokenId = 1;
    uint256 amountBorrowedBefore = loanManager.getMortgagePosition(tokenId).amountBorrowed;
    _setPrice(100_000e8);

    _mintUsdx(balanceSheetExpander, 1_000_000e18);
    vm.startPrank(balanceSheetExpander);
    usdx.approve(address(generalManager), type(uint256).max);
    uint256 orderId = orderPool.orderCount();
    generalManager.requestBalanceSheetExpansion(
      ExpansionRequest({base: _buildRequest(1e8, false, false, "").base, tokenId: tokenId})
    );
    vm.stopPrank();
    PurchaseOrder memory order = orderPool.orders(orderId);

    _fillWithCallback(orderId, 0);

    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(tokenId);
    assertEq(mortgagePosition.amountBorrowed, amountBorrowedBefore + order.mortgageParams.amountBorrowed, "borrowed");
    assertEq(mortgagePosition.collateralAmount, 3e8, "collateral amount");
    assertEq(callbackFulfiller.lastTokenId(), tokenId, "tokenId");
    assertEq(wbtc.balanceOf(address(generalManager)), 0, "GeneralManager collateral");
  }

  function test_callback_multipleOrdersInOneCall() public {
    (uint256 firstOrderId, uint256 firstTokenId) = _request(1e8, false, false);
    (uint256 secondOrderId, uint256 secondTokenId) = _request(2e8, true, true);
    uint256 totalPurchaseAmount = orderPool.orders(firstOrderId).orderAmounts.purchaseAmount
      + orderPool.orders(secondOrderId).orderAmounts.purchaseAmount;

    uint256[] memory indices = new uint256[](2);
    indices[0] = firstOrderId;
    indices[1] = secondOrderId;
    uint256[][] memory hintPrevIdsList = new uint256[][](2);
    hintPrevIdsList[0] = new uint256[](0);
    hintPrevIdsList[1] = new uint256[](1);
    bytes[] memory fulfillerDataList = new bytes[](2);
    fulfillerDataList[0] = abi.encode(uint256(0));
    fulfillerDataList[1] = abi.encode(uint256(0));
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);

    assertEq(callbackFulfiller.callbackCount(), 2, "two callbacks");
    assertEq(loanManager.getMortgagePosition(firstTokenId).collateralAmount, 1e8, "first mortgage");
    assertEq(loanManager.getMortgagePosition(secondTokenId).collateralAmount, 2e8, "second mortgage");
    assertApproxEqAbs(usdx.balanceOf(address(callbackFulfiller)), totalPurchaseAmount, 8, "paid for both");
  }

  function test_callback_collectsOrderGasFee() public {
    vm.startPrank(admin);
    orderPool.setGasFee(0.01 ether);
    vm.stopPrank();
    vm.deal(borrower, 1 ether);

    uint256 orderId = orderPool.orderCount();
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation{value: 0.01 ether}(_buildRequest(1e8, false, false, "mortgage"));
    vm.stopPrank();

    _fillWithCallback(orderId, 0);

    assertEq(address(callbackFulfiller).balance, 0.01 ether, "fulfiller collects the order gas fee");
  }

  function test_callback_expiredOrderIsRefundedWithoutCallback() public {
    (uint256 orderId, uint256 tokenId) = _request(2e8, false, false);
    PurchaseOrder memory order = orderPool.orders(orderId);
    uint256 borrowerUsdxBefore = usdx.balanceOf(borrower);

    vm.warp(order.expiration + 1);
    vm.expectEmit(true, true, true, true, address(orderPool));
    emit IOrderPoolEvents.PurchaseOrderExpired(orderId);
    _fillWithCallback(orderId, 0);

    assertEq(callbackFulfiller.callbackCount(), 0, "no callback for an expired order");
    assertEq(usdx.balanceOf(address(callbackFulfiller)), 0, "nothing advanced");
    assertEq(usdx.balanceOf(borrower), borrowerUsdxBefore + order.orderAmounts.usdxCollected, "borrower refunded");
    vm.expectRevert();
    mortgageNFT.ownerOf(tokenId);
  }

  function test_callback_zeroCollateralRequestedStillPaysTheFulfiller() public {
    // An order pool that hands the GeneralManager an origination nothing is requested for
    (uint256 orderId,) = _request(2e8, false, false);
    PurchaseOrder memory order = orderPool.orders(orderId);
    uint256[] memory hintPrevIds = new uint256[](0);
    OriginationParameters memory originationParameters = OriginationParameters({
      mortgageParams: order.mortgageParams,
      fulfiller: address(callbackFulfiller),
      originationPools: order.originationPools,
      borrowAmounts: order.borrowAmounts,
      conversionQueues: order.conversionQueues,
      hintPrevIds: hintPrevIds,
      expansion: false,
      purchaseAmount: order.orderAmounts.purchaseAmount
    });
    callbackFulfiller.setDelivery(MockCallbackFulfiller.Delivery.Nothing);

    // The order pool forwards the escrow and the full collateral itself
    vm.startPrank(address(orderPool));
    usdx.transfer(address(generalManager), order.orderAmounts.usdxCollected);
    vm.stopPrank();
    MockERC20(address(wbtc)).mint(address(generalManager), 2e8);
    vm.startPrank(address(orderPool));
    generalManager.originateWithCallback(originationParameters, 0, abi.encode(uint256(0)));
    vm.stopPrank();

    assertEq(callbackFulfiller.callbackCount(), 1, "callback still runs");
    assertEq(callbackFulfiller.lastCollateralAmount(), 0, "nothing requested");
    assertApproxEqAbs(
      usdx.balanceOf(address(callbackFulfiller)), order.orderAmounts.purchaseAmount, 2, "fulfiller paid"
    );
  }

  // ---------------------------------------------------------------------------------------------
  // Equivalence with upfront delivery
  // ---------------------------------------------------------------------------------------------

  function testFuzz_callback_matchesUpfrontDelivery(
    uint256 collateralAmount,
    uint256 price,
    bool compounding,
    bool feeEnabled,
    bool twoPools,
    uint256 consolSupply,
    uint256 consolYield
  ) public {
    collateralAmount = bound(collateralAmount, 1e5, 5e8);
    price = bound(price, 20_000e8, 120_000e8);
    // Either an empty Consol or one with a real supply whose share price has at most doubled
    consolSupply = bound(consolSupply, 0, 10_000_000e18);
    if (consolSupply < 1e18) {
      consolSupply = 0;
    }
    consolYield = bound(consolYield, 0, consolSupply);

    _mintConsolViaUsdx(lender, consolSupply);
    if (consolYield > 0) {
      _mintUsdx(address(this), consolYield);
      usdx.transfer(address(consol), consolYield);
    }
    if (feeEnabled) {
      _enableFee();
    }
    _setPrice(price);

    (uint256 orderId, uint256 tokenId) = _request(collateralAmount, compounding, twoPools);
    uint256 purchaseAmount = orderPool.orders(orderId).orderAmounts.purchaseAmount;

    uint256 snapshot = vm.snapshotState();
    _fillUpfront(orderId);
    Outcome memory upfront = _outcome(fulfiller, tokenId);
    vm.revertToState(snapshot);

    _fillWithCallback(orderId, 0);
    Outcome memory viaCallback = _outcome(address(callbackFulfiller), tokenId);

    _assertSameOutcome(upfront, viaCallback);
    assertLe(purchaseAmount - viaCallback.fulfillerUsdx, 2 * Constants.FULFILLMENT_HOLDBACK_PER_POOL, "within holdback");
  }

  // ---------------------------------------------------------------------------------------------
  // Failure paths
  // ---------------------------------------------------------------------------------------------

  function test_callback_revertsIfCollateralUnderDelivered() public {
    (uint256 orderId,) = _request(2e8, false, false);
    callbackFulfiller.setDelivery(MockCallbackFulfiller.Delivery.OneShort);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    vm.expectRevert(
      abi.encodeWithSelector(IGeneralManagerErrors.InsufficientCollateralDelivered.selector, 2e8, 2e8 - 1)
    );
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  function test_callback_revertsIfNothingDelivered() public {
    (uint256 orderId,) = _request(2e8, false, false);
    callbackFulfiller.setDelivery(MockCallbackFulfiller.Delivery.Nothing);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.InsufficientCollateralDelivered.selector, 2e8, 0));
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);

    // The whole fill unwound: the order is intact and the fulfiller kept nothing
    assertEq(orderPool.orders(orderId).mortgageParams.collateral, address(wbtc), "order intact");
    assertEq(usdx.balanceOf(address(callbackFulfiller)), 0, "advance returned");
  }

  function test_callback_collateralAlreadyInGeneralManagerDoesNotCount() public {
    (uint256 orderId,) = _request(2e8, false, false);
    // Collateral donated to the GeneralManager before the fill is not a delivery
    MockERC20(address(wbtc)).mint(address(generalManager), 2e8);
    callbackFulfiller.setDelivery(MockCallbackFulfiller.Delivery.Nothing);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.InsufficientCollateralDelivered.selector, 2e8, 0));
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  function test_callback_revertsIfFulfillerSpendsMoreThanTheAdvance() public {
    (uint256 orderId,) = _request(2e8, false, false);
    uint256 advance = orderPool.orders(orderId).orderAmounts.purchaseAmount - Constants.FULFILLMENT_HOLDBACK_PER_POOL;
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, advance + 1);

    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientBalance.selector, address(callbackFulfiller), advance, advance + 1
      )
    );
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  function test_callback_revertsIfCollateralTransferIsBlocked() public {
    (uint256 orderId,) = _request(2e8, false, false);
    MockERC20(address(wbtc)).mint(address(callbackFulfiller), 2e8);
    callbackFulfiller.setDelivery(MockCallbackFulfiller.Delivery.FromInventory);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    // The collateral token refuses transfers, as a paused token would
    vm.mockCallRevert(
      address(wbtc),
      abi.encodeWithSelector(IERC20.transfer.selector, address(generalManager), 2e8),
      abi.encodeWithSignature("EnforcedPause()")
    );
    vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
    vm.clearMockedCalls();

    // The same fill succeeds once transfers resume
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
    assertEq(wbtc.balanceOf(address(callbackFulfiller)), 0, "inventory delivered");
  }

  function test_callback_revertsIfUsdxAdvanceIsBlocked() public {
    (uint256 orderId,) = _request(2e8, false, false);
    uint256 advance = orderPool.orders(orderId).orderAmounts.purchaseAmount - Constants.FULFILLMENT_HOLDBACK_PER_POOL;
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    vm.mockCallRevert(
      address(usdx),
      abi.encodeWithSelector(IERC20.transfer.selector, address(callbackFulfiller), advance),
      abi.encodeWithSignature("EnforcedPause()")
    );
    vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  function test_callback_revertsIfGeneralManagerPaused() public {
    (uint256 orderId,) = _request(2e8, false, false);
    vm.startPrank(admin);
    IAccessControl(address(generalManager)).grantRole(Roles.PAUSE_ROLE, pauser);
    vm.stopPrank();
    vm.startPrank(pauser);
    generalManager.setPaused(true);
    vm.stopPrank();
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    vm.expectRevert(abi.encodeWithSignature("Paused()"));
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  function test_callback_revertsIfHintsDoNotMatchConversionQueues() public {
    (uint256 orderId,) = _request(2e8, true, false);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);
    hintPrevIdsList[0] = new uint256[](0);

    vm.expectRevert(abi.encodeWithSelector(IOrderPoolErrors.HintPrevIdsListLengthMismatch.selector, orderId, 0, 1));
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  function test_callback_revertsIfFulfillerDataListIsShort() public {
    (uint256 orderId,) = _request(2e8, false, false);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList,) = _fillArgs(orderId, 0);

    vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x32));
    callbackFulfiller.fill(indices, hintPrevIdsList, new bytes[](0));
  }

  function test_callback_revertsIfFulfillerHasNoCallback() public {
    (uint256 orderId,) = _request(2e8, false, false);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    // An externally owned fulfiller cannot answer the callback
    vm.startPrank(fulfiller);
    vm.expectRevert();
    orderPool.processOrdersWithCallback(indices, hintPrevIdsList, fulfillerDataList);
    vm.stopPrank();
  }

  function test_callback_revertsIfOrderAlreadyProcessed() public {
    (uint256 orderId,) = _request(2e8, false, false);
    _fillWithCallback(orderId, 0);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    vm.expectRevert();
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  function test_processOrdersWithCallback_revertsIfCallerLacksFulfillmentRole(address caller) public {
    vm.assume(!orderPool.hasRole(Roles.FULFILLMENT_ROLE, caller));
    (uint256 orderId,) = _request(2e8, false, false);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.FULFILLMENT_ROLE)
    );
    orderPool.processOrdersWithCallback(indices, hintPrevIdsList, fulfillerDataList);
    vm.stopPrank();
  }

  function test_originateWithCallback_revertsIfCallerIsNotOrderPool(address caller) public {
    vm.assume(caller != address(orderPool));
    OriginationParameters memory originationParameters;

    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.OnlyOrderPool.selector, caller, address(orderPool)));
    generalManager.originateWithCallback(originationParameters, 0, "");
    vm.stopPrank();
  }

  function test_orderFulfillmentCallback_isOnlyReachableThroughAnOrder() public {
    // Nothing but the GeneralManager's own origination ever calls the fulfiller with an advance
    vm.expectRevert();
    callbackFulfiller.orderFulfillmentCallback(1, address(wbtc), 1e8, 0, abi.encode(uint256(1)));
  }

  // ---------------------------------------------------------------------------------------------
  // Reentrancy
  // ---------------------------------------------------------------------------------------------

  function _expectReentryReverts(address target, bytes memory data, bytes memory expectedRevert) internal {
    (uint256 orderId, uint256 tokenId) = _request(2e8, false, false);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    // A reentrant call that bubbles its failure unwinds the fill
    uint256 snapshot = vm.snapshotState();
    callbackFulfiller.setReentry(target, data, false);
    vm.expectRevert(expectedRevert);
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
    vm.revertToState(snapshot);

    // A fulfiller that swallows the failure gets exactly the outcome of a fill that never reentered
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
    Outcome memory clean = _outcome(address(callbackFulfiller), tokenId);
    vm.revertToState(snapshot);

    callbackFulfiller.setReentry(target, data, true);
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
    assertTrue(callbackFulfiller.reentryFailed(), "reentrant call failed");
    _assertSameOutcome(clean, _outcome(address(callbackFulfiller), tokenId));
  }

  function test_callback_cannotReenterProcessOrders() public {
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList) = (new uint256[](0), new uint256[][](0));
    _expectReentryReverts(
      address(orderPool),
      abi.encodeCall(OrderPool.processOrders, (indices, hintPrevIdsList)),
      abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
    );
  }

  function test_callback_cannotReenterProcessOrdersWithCallback() public {
    _expectReentryReverts(
      address(orderPool),
      abi.encodeCall(OrderPool.processOrdersWithCallback, (new uint256[](0), new uint256[][](0), new bytes[](0))),
      abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
    );
  }

  function test_callback_cannotReenterOriginate() public {
    OriginationParameters memory originationParameters;
    _expectReentryReverts(
      address(generalManager),
      abi.encodeCall(generalManager.originate, (originationParameters)),
      abi.encodeWithSelector(
        IGeneralManagerErrors.OnlyOrderPool.selector, address(callbackFulfiller), address(orderPool)
      )
    );
  }

  function test_callback_cannotReenterOriginateWithCallback() public {
    OriginationParameters memory originationParameters;
    _expectReentryReverts(
      address(generalManager),
      abi.encodeCall(generalManager.originateWithCallback, (originationParameters, 0, "")),
      abi.encodeWithSelector(
        IGeneralManagerErrors.OnlyOrderPool.selector, address(callbackFulfiller), address(orderPool)
      )
    );
  }

  function test_callback_cannotReenterRequestMortgageCreation() public {
    _expectReentryReverts(
      address(generalManager),
      abi.encodeCall(generalManager.requestMortgageCreation, (_buildRequest(1e8, false, false, "reentrant"))),
      abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
    );
  }

  function test_callback_cannotReenterOriginationPoolDeployCallback() public {
    _expectReentryReverts(
      address(generalManager),
      abi.encodeCall(IOriginationPoolDeployCallback.originationPoolDeployCallback, (0, 0, "")),
      abi.encodeWithSelector(IGeneralManagerErrors.InvalidOriginationPool.selector, address(callbackFulfiller))
    );
  }

  function test_callback_cannotReenterOriginationPoolDeploy() public {
    _expectReentryReverts(
      address(originationPool),
      abi.encodeCall(IOriginationPool.deploy, (1e18, "")),
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, address(callbackFulfiller), Roles.DEPLOY_ROLE
      )
    );
  }

  function test_callback_cannotCallAnotherFulfillersCallback() public {
    // A second fulfiller cannot be made to deliver for an order it is not filling
    MockCallbackFulfiller victim = new MockCallbackFulfiller(orderPool, IERC20(address(usdx)), market);
    MockERC20(address(wbtc)).mint(address(victim), 2e8);
    victim.setDelivery(MockCallbackFulfiller.Delivery.FromInventory);
    (uint256 orderId,) = _request(2e8, false, false);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList) =
      _fillArgs(orderId, 0);

    // The victim's delivery lands on the calling fulfiller, never on the GeneralManager
    callbackFulfiller.setDelivery(MockCallbackFulfiller.Delivery.Nothing);
    callbackFulfiller.setReentry(
      address(victim),
      abi.encodeCall(
        IOrderFulfillmentCallback.orderFulfillmentCallback, (1, address(wbtc), 2e8, 0, abi.encode(uint256(0)))
      ),
      false
    );
    vm.expectRevert(abi.encodeWithSelector(IGeneralManagerErrors.InsufficientCollateralDelivered.selector, 2e8, 0));
    callbackFulfiller.fill(indices, hintPrevIdsList, fulfillerDataList);
  }

  // ---------------------------------------------------------------------------------------------
  // Upfront delivery is unchanged
  // ---------------------------------------------------------------------------------------------

  function test_upfront_stillPullsCollateralAndNeverCallsBack() public {
    (uint256 orderId, uint256 tokenId) = _request(2e8, false, false);
    uint256 purchaseAmount = orderPool.orders(orderId).orderAmounts.purchaseAmount;
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList,) = _fillArgs(orderId, 0);

    MockERC20(address(wbtc)).mint(address(callbackFulfiller), 2e8);
    callbackFulfiller.approve(address(wbtc), address(orderPool), 2e8);
    callbackFulfiller.fillUpfront(indices, hintPrevIdsList);

    assertEq(callbackFulfiller.callbackCount(), 0, "no callback on the upfront path");
    assertEq(wbtc.balanceOf(address(callbackFulfiller)), 0, "collateral pulled");
    assertApproxEqAbs(usdx.balanceOf(address(callbackFulfiller)), purchaseAmount, 2, "paid at the end");
    assertEq(loanManager.getMortgagePosition(tokenId).collateralAmount, 2e8, "mortgage created");
  }

  function test_upfront_revertsWithoutInventory() public {
    (uint256 orderId,) = _request(2e8, false, false);
    (uint256[] memory indices, uint256[][] memory hintPrevIdsList,) = _fillArgs(orderId, 0);

    vm.expectRevert(
      abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(orderPool), 0, 2e8)
    );
    callbackFulfiller.fillUpfront(indices, hintPrevIdsList);
  }
}
