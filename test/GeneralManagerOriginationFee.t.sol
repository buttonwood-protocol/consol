// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {
  IGeneralManager,
  IGeneralManagerEvents,
  IGeneralManagerErrors
} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {GeneralManager} from "../src/GeneralManager.sol";
import {MortgagePosition} from "../src/types/MortgagePosition.sol";
import {CreationRequest, ExpansionRequest, BaseRequest} from "../src/types/orders/OrderRequests.sol";
import {Roles} from "../src/libraries/Roles.sol";
import {Constants} from "../src/libraries/Constants.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract GeneralManagerOriginationFeeTest is BaseTest {
  // The address receiving protocol fees in these tests
  address public protocolFeeRecipient = makeAddr("protocolFeeRecipient");

  // The origination fee rate used in the flow tests
  uint16 public constant ORIGINATION_FEE_RATE = 100; // 1%

  // Rounding dust tolerance for surplus assertions, in wei of USDX
  uint256 public constant DUST = 4;

  function _enableFee() internal {
    vm.startPrank(admin);
    generalManager.setOriginationFeeRate(ORIGINATION_FEE_RATE);
    generalManager.setFeeRecipient(protocolFeeRecipient);
    vm.stopPrank();
  }

  function _fundPoolAndWarpToDeployPhase() internal {
    // Deal 606k of usdx to the lender and have them deposit it into the origination pool
    _mintUsdx(lender, 606_000e18);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 606_000e18);
    originationPool.deposit(606_000e18);
    vm.stopPrank();

    // Move time forward into the deployment phase
    vm.warp(originationPool.deployPhaseTimestamp());
  }

  /**
   * @dev Sets the BTC price such that the oracle cost of collateralAmount equals 2 * amountBorrowed
   */
  function _setPrice(uint256 amountBorrowed, uint256 collateralAmount) internal {
    _setPythPrice(
      BTC_PRICE_ID, int64(uint64((2 * amountBorrowed * 1e8) / (collateralAmount * 1e10))), 100e8, -8, block.timestamp
    );
  }

  /**
   * @dev The spread-adjusted cost of a collateral amount, mirroring GeneralManager._calculateCost
   */
  function _costWithSpread(uint256 collateralAmount) internal view returns (uint256) {
    (uint256 oracleCost,) = priceOracle.cost(collateralAmount);
    return Math.mulDiv(oracleCost, Constants.BPS + generalManager.priceSpread(), Constants.BPS);
  }

  function _buildNoncompoundingRequest(uint256 collateralAmount, string memory mortgageId)
    internal
    view
    returns (CreationRequest memory)
  {
    uint256[] memory collateralAmounts = new uint256[](1);
    collateralAmounts[0] = collateralAmount;
    address[] memory originationPools = new address[](1);
    originationPools[0] = address(originationPool);
    address[] memory emptyConversionQueues;

    return CreationRequest({
      base: BaseRequest({
        collateralAmounts: collateralAmounts,
        totalPeriods: DEFAULT_MORTGAGE_PERIODS,
        originationPools: originationPools,
        isCompounding: false,
        expiration: block.timestamp + 1 minutes
      }),
      mortgageId: mortgageId,
      collateral: address(wbtc),
      subConsol: address(subConsol),
      conversionQueues: emptyConversionQueues,
      hasPaymentPlan: true
    });
  }

  function _processOrder(uint256 orderId, uint256 conversionQueueCount) internal {
    uint256[] memory indices = new uint256[](1);
    uint256[][] memory hintPrevIdsList = new uint256[][](1);
    indices[0] = orderId;
    hintPrevIdsList[0] = new uint256[](conversionQueueCount);
    vm.startPrank(fulfiller);
    orderPool.processOrders(indices, hintPrevIdsList);
    vm.stopPrank();
  }

  function test_setOriginationFeeRate_shouldRevertIfNotAdmin(address caller, uint16 newOriginationFeeRate) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(payable(address(generalManager))).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the origination fee rate without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setOriginationFeeRate(newOriginationFeeRate);
    vm.stopPrank();
  }

  function test_setOriginationFeeRate_shouldRevertIfAboveMaximum(uint16 newOriginationFeeRate) public {
    // Ensure the rate exceeds the maximum
    vm.assume(newOriginationFeeRate > Constants.MAX_ORIGINATION_FEE_RATE);

    // Attempt to set an origination fee rate above the maximum
    vm.startPrank(admin);
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.OriginationFeeRateTooHigh.selector,
        newOriginationFeeRate,
        Constants.MAX_ORIGINATION_FEE_RATE
      )
    );
    generalManager.setOriginationFeeRate(newOriginationFeeRate);
    vm.stopPrank();
  }

  function test_setOriginationFeeRate(uint16 newOriginationFeeRate) public {
    // Ensure the rate does not exceed the maximum
    vm.assume(newOriginationFeeRate <= Constants.MAX_ORIGINATION_FEE_RATE);

    // Set the origination fee rate as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.OriginationFeeRateSet(0, newOriginationFeeRate);
    generalManager.setOriginationFeeRate(newOriginationFeeRate);
    vm.stopPrank();

    // Validate the origination fee rate was set correctly
    assertEq(generalManager.originationFeeRate(), newOriginationFeeRate, "Origination fee rate should be set correctly");
  }

  function test_setFeeRecipient_shouldRevertIfNotAdmin(address caller, address newFeeRecipient) public {
    // Ensure the caller doesn't have the admin role
    vm.assume(!GeneralManager(payable(address(generalManager))).hasRole(Roles.DEFAULT_ADMIN_ROLE, caller));

    // Attempt to set the fee recipient without the admin role
    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generalManager.setFeeRecipient(newFeeRecipient);
    vm.stopPrank();
  }

  function test_setFeeRecipient(address newFeeRecipient) public {
    // Set the fee recipient as admin
    vm.startPrank(admin);
    vm.expectEmit(true, true, true, true);
    emit IGeneralManagerEvents.FeeRecipientSet(address(0), newFeeRecipient);
    generalManager.setFeeRecipient(newFeeRecipient);
    vm.stopPrank();

    // Validate the fee recipient was set correctly
    assertEq(generalManager.feeRecipient(), newFeeRecipient, "Fee recipient should be set correctly");
  }

  function test_noFeeChargedWhileRecipientUnset() public {
    // Set a fee rate but leave the recipient unset
    vm.startPrank(admin);
    generalManager.setOriginationFeeRate(ORIGINATION_FEE_RATE);
    vm.stopPrank();

    _fundPoolAndWarpToDeployPhase();

    // The stock helper mints and approves exactly the legacy (fee-less) amounts, so the request only succeeds if no fee is charged
    _requestNoncompoundingPaymentPlanMortgage(borrower, "mortgage1", 100_000e18, 2e8, address(0));

    // Validate the mortgage was created and no fee was collected
    assertEq(mortgageNFT.ownerOf(1), borrower, "Mortgage should be created");
    assertEq(usdx.balanceOf(address(generalManager)), 0, "GeneralManager should hold no USDX");
  }

  function test_originationFeeCollected_nonCompounding() public {
    uint256 amountBorrowed = 100_000e18;
    uint256 collateralAmount = 2e8;

    _enableFee();
    _fundPoolAndWarpToDeployPhase();
    _setPrice(amountBorrowed, collateralAmount);

    // Calculate the expected amounts
    uint256 cost = _costWithSpread(collateralAmount);
    uint256 expectedFee = Math.mulDiv(cost, ORIGINATION_FEE_RATE, Constants.BPS, Math.Rounding.Ceil);
    uint256 usdxToCollect = originationPool.calculateReturnAmount(cost / 2) + (cost % 2) + expectedFee;

    // Fund the borrower with the exact USDX to collect (including the fee)
    _mintUsdx(borrower, usdxToCollect);
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), usdxToCollect);
    vm.stopPrank();

    // Fund the fulfiller with the collateral to deliver
    vm.startPrank(fulfiller);
    MockERC20(address(wbtc)).mint(fulfiller, collateralAmount);
    wbtc.approve(address(orderPool), collateralAmount);
    vm.stopPrank();

    // Request the mortgage
    uint256 orderId = orderPool.orderCount();
    vm.startPrank(borrower);
    uint256 tokenId = generalManager.requestMortgageCreation(_buildNoncompoundingRequest(collateralAmount, "mortgage1"));
    vm.stopPrank();

    // The borrower should be charged the full amount including the fee
    assertEq(usdx.balanceOf(borrower), 0, "Borrower should be charged the fee on top of the legacy amounts");

    // Process the order
    _processOrder(orderId, 0);

    // The fulfiller should receive exactly the purchase amount, unchanged by the fee
    assertEq(usdx.balanceOf(fulfiller), cost, "Fulfiller should receive exactly the purchaseAmount");

    // The fee recipient should receive the fee (plus at most rounding dust)
    assertApproxEqAbs(usdx.balanceOf(protocolFeeRecipient), expectedFee, DUST, "Fee recipient should receive the fee");

    // The GeneralManager should hold no residual balances
    assertEq(usdx.balanceOf(address(generalManager)), 0, "GeneralManager should hold no USDX");
    assertEq(wbtc.balanceOf(address(generalManager)), 0, "GeneralManager should hold no collateral");

    // The mortgage terms should be unchanged by the fee
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(tokenId);
    assertEq(mortgagePosition.collateralAmount, collateralAmount, "Collateral amount should be unchanged by the fee");
    assertEq(mortgagePosition.amountBorrowed, cost / 2, "Amount borrowed should be unchanged by the fee");
  }

  function test_originationFeeCollected_compounding() public {
    uint256 amountBorrowed = 100_000e18;
    uint256 collateralAmount = 2e8;

    _enableFee();
    _fundPoolAndWarpToDeployPhase();
    _setPrice(amountBorrowed, collateralAmount);

    // Calculate the expected amounts
    uint256 costHalf = _costWithSpread(collateralAmount / 2);
    uint256 legacyCollateralCollected = originationPool.calculateReturnAmount((collateralAmount + 1) / 2);
    uint256 feeCollateral = Math.mulDiv(collateralAmount, ORIGINATION_FEE_RATE, Constants.BPS, Math.Rounding.Ceil);
    uint256 expectedFee = _costWithSpread(feeCollateral);
    uint256 legacyPurchaseAmount = (2 * costHalf) - originationPool.calculateReturnAmount(costHalf);
    uint256 collateralRequested = collateralAmount - legacyCollateralCollected - feeCollateral;

    // Fund the borrower with the exact collateral to collect (including the fee)
    MockERC20(address(wbtc)).mint(borrower, legacyCollateralCollected + feeCollateral);
    vm.startPrank(borrower);
    wbtc.approve(address(generalManager), legacyCollateralCollected + feeCollateral);
    vm.stopPrank();

    // Fund the fulfiller with the collateral to deliver
    vm.startPrank(fulfiller);
    MockERC20(address(wbtc)).mint(fulfiller, collateralRequested);
    wbtc.approve(address(orderPool), collateralRequested);
    vm.stopPrank();

    // Build the compounding request
    CreationRequest memory creationRequest = _buildNoncompoundingRequest(collateralAmount, "mortgage1");
    creationRequest.base.isCompounding = true;
    address[] memory conversionQueueList = new address[](1);
    conversionQueueList[0] = address(conversionQueue);
    creationRequest.conversionQueues = conversionQueueList;

    // Request the mortgage
    uint256 orderId = orderPool.orderCount();
    vm.startPrank(borrower);
    uint256 tokenId = generalManager.requestMortgageCreation(creationRequest);
    vm.stopPrank();

    // The borrower should be charged the fee collateral on top of the legacy collateral
    assertEq(wbtc.balanceOf(borrower), 0, "Borrower should be charged the fee on top of the legacy amounts");

    // Process the order
    _processOrder(orderId, 1);

    // The fulfiller should receive the purchase amount reduced by the fee collateral's cost
    assertEq(
      usdx.balanceOf(fulfiller),
      legacyPurchaseAmount - expectedFee,
      "Fulfiller should receive the purchaseAmount net of the fee collateral's cost"
    );
    assertEq(wbtc.balanceOf(fulfiller), 0, "Fulfiller should deliver less collateral by the fee collateral");

    // The fee recipient should receive the fee (plus at most rounding dust)
    assertApproxEqAbs(usdx.balanceOf(protocolFeeRecipient), expectedFee, DUST, "Fee recipient should receive the fee");

    // The GeneralManager should hold no residual balances
    assertEq(usdx.balanceOf(address(generalManager)), 0, "GeneralManager should hold no USDX");
    assertEq(wbtc.balanceOf(address(generalManager)), 0, "GeneralManager should hold no collateral");

    // The mortgage terms should be unchanged by the fee
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(tokenId);
    assertEq(mortgagePosition.collateralAmount, collateralAmount, "Collateral amount should be unchanged by the fee");
    assertEq(mortgagePosition.amountBorrowed, costHalf, "Amount borrowed should be unchanged by the fee");
  }

  function test_originationFeeRefundedOnExpiredOrder() public {
    uint256 amountBorrowed = 100_000e18;
    uint256 collateralAmount = 2e8;

    _enableFee();
    _fundPoolAndWarpToDeployPhase();
    _setPrice(amountBorrowed, collateralAmount);

    // Calculate the expected amounts
    uint256 cost = _costWithSpread(collateralAmount);
    uint256 expectedFee = Math.mulDiv(cost, ORIGINATION_FEE_RATE, Constants.BPS, Math.Rounding.Ceil);
    uint256 usdxToCollect = originationPool.calculateReturnAmount(cost / 2) + (cost % 2) + expectedFee;

    // Fund the borrower with the exact USDX to collect (including the fee)
    _mintUsdx(borrower, usdxToCollect);
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), usdxToCollect);
    vm.stopPrank();

    // Request the mortgage
    uint256 orderId = orderPool.orderCount();
    vm.startPrank(borrower);
    generalManager.requestMortgageCreation(_buildNoncompoundingRequest(collateralAmount, "mortgage1"));
    vm.stopPrank();
    assertEq(usdx.balanceOf(borrower), 0, "Borrower should be charged the fee on top of the legacy amounts");

    // Let the order expire, then process it
    vm.warp(block.timestamp + 2 minutes);
    _processOrder(orderId, 0);

    // The full escrow, including the fee, should be refunded to the borrower
    assertEq(usdx.balanceOf(borrower), usdxToCollect, "Borrower should be refunded the full escrow including the fee");
    assertEq(usdx.balanceOf(protocolFeeRecipient), 0, "No fee should be collected for an expired order");
  }

  function test_originationFeeCollected_expansion() public {
    uint256 amountBorrowed = 100_000e18;
    uint256 collateralAmount = 2e8;

    _fundPoolAndWarpToDeployPhase();

    // Create a fee-less mortgage owned by the balance sheet expander
    _requestNoncompoundingPaymentPlanMortgage(
      balanceSheetExpander, "mortgage1", amountBorrowed, collateralAmount, address(0)
    );
    uint256 tokenId = 1;
    uint256 amountBorrowedBefore = loanManager.getMortgagePosition(tokenId).amountBorrowed;

    // Enable the fee for the expansion
    _enableFee();
    _setPrice(amountBorrowed, collateralAmount);

    // Calculate the expected amounts for the expansion
    uint256 cost = _costWithSpread(collateralAmount);
    uint256 expectedFee = Math.mulDiv(cost, ORIGINATION_FEE_RATE, Constants.BPS, Math.Rounding.Ceil);
    uint256 usdxToCollect = originationPool.calculateReturnAmount(cost / 2) + (cost % 2) + expectedFee;

    // Fund the expander with the exact USDX to collect (including the fee)
    _mintUsdx(balanceSheetExpander, usdxToCollect);
    vm.startPrank(balanceSheetExpander);
    usdx.approve(address(generalManager), usdxToCollect);
    vm.stopPrank();

    // Fund the fulfiller with the collateral to deliver
    vm.startPrank(fulfiller);
    MockERC20(address(wbtc)).mint(fulfiller, collateralAmount);
    wbtc.approve(address(orderPool), collateralAmount);
    vm.stopPrank();

    // Request the balance sheet expansion
    CreationRequest memory template = _buildNoncompoundingRequest(collateralAmount, "");
    uint256 orderId = orderPool.orderCount();
    vm.startPrank(balanceSheetExpander);
    generalManager.requestBalanceSheetExpansion(ExpansionRequest({base: template.base, tokenId: tokenId}));
    vm.stopPrank();

    // Process the order
    _processOrder(orderId, 0);

    // The fee recipient should receive the fee (plus at most rounding dust)
    assertApproxEqAbs(usdx.balanceOf(protocolFeeRecipient), expectedFee, DUST, "Fee recipient should receive the fee");

    // The expansion should be applied with terms unchanged by the fee
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(tokenId);
    assertEq(
      mortgagePosition.amountBorrowed,
      amountBorrowedBefore + cost / 2,
      "Amount borrowed should grow by the expansion amount, unchanged by the fee"
    );
  }
}
