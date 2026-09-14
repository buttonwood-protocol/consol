// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IGeneralManagerErrors} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {ConversionQueue} from "../src/ConversionQueue.sol";
import {MortgagePosition} from "../src/types/MortgagePosition.sol";
import {CreationRequest, ExpansionRequest, BaseRequest} from "../src/types/orders/OrderRequests.sol";
import {Constants} from "../src/libraries/Constants.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract GeneralManagerGuardsTest is BaseTest {
  // A conversion queue for a different asset than the mortgage collateral
  MockERC20 public weth;
  ConversionQueue public wethConversionQueue;

  function setUp() public override {
    super.setUp();
    weth = new MockERC20("Wrapped Ether", "WETH", 18);
    wethConversionQueue =
      new ConversionQueue(address(weth), 18, address(consol), address(whype), address(generalManager), admin);
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

  function _buildRequest(uint256 collateralAmount, address conversionQueueAddress)
    internal
    view
    returns (CreationRequest memory)
  {
    uint256[] memory collateralAmounts = new uint256[](1);
    collateralAmounts[0] = collateralAmount;
    address[] memory originationPools = new address[](1);
    originationPools[0] = address(originationPool);
    address[] memory conversionQueueList;
    if (conversionQueueAddress != address(0)) {
      conversionQueueList = new address[](1);
      conversionQueueList[0] = conversionQueueAddress;
    }

    return CreationRequest({
      base: BaseRequest({
        collateralAmounts: collateralAmounts,
        totalPeriods: DEFAULT_MORTGAGE_PERIODS,
        originationPools: originationPools,
        isCompounding: false,
        expiration: block.timestamp + 1 minutes
      }),
      mortgageId: "mortgage1",
      collateral: address(wbtc),
      subConsol: address(subConsol),
      conversionQueues: conversionQueueList,
      hasPaymentPlan: true
    });
  }

  function _processOrder(uint256 orderId) internal {
    uint256[] memory indices = new uint256[](1);
    uint256[][] memory hintPrevIdsList = new uint256[][](1);
    indices[0] = orderId;
    vm.startPrank(fulfiller);
    orderPool.processOrders(indices, hintPrevIdsList);
    vm.stopPrank();
  }

  function test_requestMortgageCreation_shouldRevertOnConversionQueueAssetMismatch() public {
    // Attempt a creation request routed at a conversion queue for a different asset
    vm.startPrank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.ConversionQueueAssetMismatch.selector,
        address(wethConversionQueue),
        address(weth),
        address(wbtc)
      )
    );
    generalManager.requestMortgageCreation(_buildRequest(2e8, address(wethConversionQueue)));
    vm.stopPrank();
  }

  function test_enqueueMortgage_shouldRevertOnConversionQueueAssetMismatch() public {
    _fundPoolAndWarpToDeployPhase();

    // Create a wbtc mortgage without a conversion queue
    _requestNoncompoundingPaymentPlanMortgage(borrower, "mortgage1", 100_000e18, 2e8, address(0));

    // Attempt to enqueue it into the weth conversion queue
    address[] memory conversionQueueList = new address[](1);
    conversionQueueList[0] = address(wethConversionQueue);
    uint256[] memory hintPrevIds = new uint256[](1);
    vm.startPrank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        IGeneralManagerErrors.ConversionQueueAssetMismatch.selector,
        address(wethConversionQueue),
        address(weth),
        address(wbtc)
      )
    );
    generalManager.enqueueMortgage(1, conversionQueueList, hintPrevIds);
    vm.stopPrank();
  }

  function test_enqueueMortgage_matchingQueueStillWorks() public {
    _fundPoolAndWarpToDeployPhase();

    // Create a wbtc mortgage without a conversion queue
    _requestNoncompoundingPaymentPlanMortgage(borrower, "mortgage1", 100_000e18, 2e8, address(0));

    // Enqueue it into the matching wbtc conversion queue
    address[] memory conversionQueueList = new address[](1);
    conversionQueueList[0] = address(conversionQueue);
    uint256[] memory hintPrevIds = new uint256[](1);
    vm.startPrank(borrower);
    generalManager.enqueueMortgage(1, conversionQueueList, hintPrevIds);
    vm.stopPrank();

    // Validate the queue was registered for the mortgage
    assertEq(generalManager.conversionQueues(1)[0], address(conversionQueue), "Queue should be registered");
  }

  function test_burnMortgageNFT_skipsLivePositionOnExpiredExpansion() public {
    _fundPoolAndWarpToDeployPhase();

    // Create a mortgage owned by the balance sheet expander
    _requestNoncompoundingPaymentPlanMortgage(balanceSheetExpander, "mortgage1", 100_000e18, 2e8, address(0));
    uint256 tokenId = 1;

    // Fund the expander with the USDX the expansion escrows
    uint256 cost = Math.mulDiv(2 * 100_000e18, Constants.BPS + generalManager.priceSpread(), Constants.BPS);
    uint256 usdxToCollect = originationPool.calculateReturnAmount(cost / 2) + (cost % 2);
    _mintUsdx(balanceSheetExpander, usdxToCollect);
    vm.startPrank(balanceSheetExpander);
    usdx.approve(address(generalManager), usdxToCollect);
    vm.stopPrank();

    // Request a balance sheet expansion and let the order expire
    CreationRequest memory template = _buildRequest(2e8, address(0));
    uint256 orderId = orderPool.orderCount();
    vm.startPrank(balanceSheetExpander);
    generalManager.requestBalanceSheetExpansion(ExpansionRequest({base: template.base, tokenId: tokenId}));
    vm.stopPrank();
    vm.warp(block.timestamp + 2 minutes);
    _processOrder(orderId);

    // The live mortgage NFT must survive the expired expansion order's cleanup
    assertEq(mortgageNFT.ownerOf(tokenId), balanceSheetExpander, "Live mortgage NFT should not be burned");
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(tokenId);
    assertEq(mortgagePosition.tokenId, tokenId, "Mortgage position should remain intact");

    // The escrowed USDX must be refunded to the expander
    assertEq(usdx.balanceOf(balanceSheetExpander), usdxToCollect, "Escrow should be refunded on expiry");
  }

  function test_burnMortgageNFT_stillBurnsExpiredCreationReceipt() public {
    _fundPoolAndWarpToDeployPhase();

    // Set the price and fund the borrower for a creation request
    _setPythPrice(BTC_PRICE_ID, int64(uint64((2 * 100_000e18 * 1e8) / (2e8 * 1e10))), 100e8, -8, block.timestamp);
    uint256 cost = Math.mulDiv(2 * 100_000e18, Constants.BPS + generalManager.priceSpread(), Constants.BPS);
    uint256 usdxToCollect = originationPool.calculateReturnAmount(cost / 2) + (cost % 2);
    _mintUsdx(borrower, usdxToCollect);
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), usdxToCollect);
    vm.stopPrank();

    // Request a mortgage and let the order expire
    uint256 orderId = orderPool.orderCount();
    vm.startPrank(borrower);
    uint256 tokenId = generalManager.requestMortgageCreation(_buildRequest(2e8, address(0)));
    vm.stopPrank();
    vm.warp(block.timestamp + 2 minutes);
    _processOrder(orderId);

    // The receipt NFT of the unfulfilled creation must be burned
    vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
    mortgageNFT.ownerOf(tokenId);
  }
}
