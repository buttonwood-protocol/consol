// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";

/**
 * @title Integration_28_PartialConvertAndForeclosureTest
 * @author @SocksNFlops
 * @notice Borrower has 50% converted and is then foreclosed.
 */
contract Integration_28_PartialConvertAndForeclosureTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_28_PartialConvertAndForeclosureTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function run() public virtual override {
    // Lender mints 101k USDX via USDT0
    {
      MockERC20(address(usdt)).mint(address(lender), 101_000e6);
      vm.startPrank(lender);
      usdt.approve(address(usdx), 101_000e6);
      usdx.deposit(address(usdt), 101_000e6);
      vm.stopPrank();
    }

    // Lender deploys the origination pool
    vm.startPrank(lender);
    originationPool =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(1)));
    vm.stopPrank();

    // Confirm the originationPool has a poolMultiplierBps of 100
    assertEq(originationPool.poolMultiplierBps(), 100, "originationPool.poolMultiplierBps()");

    // Lender deposits USDX into the origination pool
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 101_000e18);
    originationPool.deposit(101_000e18);
    vm.stopPrank();

    // Skip time ahead to the deployPhase of the origination pool
    vm.warp(originationPool.deployPhaseTimestamp());

    // Mint the fulfiller 2 BTC that he is willing to sell for $202k
    MockERC20(address(btc)).mint(address(fulfiller), 2e8);
    btc.approve(address(orderPool), 2e8);

    // Borrower mints 102_010 USDX via USDT (1.01 * 1.01 * 100k)
    {
      MockERC20(address(usdt)).mint(address(borrower), 102_010e6);
      vm.startPrank(borrower);
      usdt.approve(address(usdx), 102_010e6);
      usdx.deposit(address(usdt), 102_010e6);
      vm.stopPrank();
    }

    // Update the interest rate oracle to 7.69%
    _updateInterestRateOracle(769);

    // Borrower sets the btc price to $100k (spread is 1% so cost will be $101k)
    vm.startPrank(borrower);
    _setPythPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 102_010 usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 102_010e18);
    vm.stopPrank();

    // Deal 0.01 native tokens to the borrow to pay for the gas fee (orderPool + conversionQueue)
    vm.deal(address(borrower), 0.02e18);

    // Borrower requests a non-compounding mortgage with a conversion queue
    {
      uint256[] memory collateralAmounts = new uint256[](1);
      collateralAmounts[0] = 2e8;
      address[] memory originationPools = new address[](1);
      originationPools[0] = address(originationPool);
      vm.startPrank(borrower);
      generalManager.requestMortgageCreation{value: 0.02e18}(
        CreationRequest({
          base: BaseRequest({
            collateralAmounts: collateralAmounts,
            totalPeriods: 36,
            originationPools: originationPools,
            isCompounding: false,
            expiration: block.timestamp
          }),
          mortgageId: mortgageId,
          collateral: address(btc),
          subConsol: address(btcSubConsol),
          conversionQueues: conversionQueues,
          hasPaymentPlan: true
        })
      );
      vm.stopPrank();
    }

    // Validate that the borrower has spent 102_010 USDX
    assertEq(usdx.balanceOf(address(borrower)), 0, "usdx.balanceOf(borrower)");

    // Validate that the origination pool has 101k USDX
    assertEq(usdx.balanceOf(address(originationPool)), 101_000e18, "usdx.balanceOf(originationPool)");

    // Fulfiller approves the order pool to take his 2 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 2 * 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), hintPrevIdsList);
    vm.stopPrank();

    // Validate all parties have correct final balances of Consol
    assertEq(consol.balanceOf(address(generalManager)), 0, "consol.balanceOf(generalManager)");
    assertGe(consol.balanceOf(address(originationPool)), 102_010e18, "consol.balanceOf(originationPool) >= 102_010e18");
    assertApproxEqAbs(
      consol.balanceOf(address(originationPool)), 102_010e18, 1, "consol.balanceOf(originationPool) ~ 102_010e18"
    );
    assertEq(consol.balanceOf(address(borrower)), 0, "consol.balanceOf(borrower)");
    assertEq(consol.balanceOf(address(fulfiller)), 0, "consol.balanceOf(fulfiller)");
    assertEq(consol.balanceOf(address(lender)), 0, "consol.balanceOf(lender)");

    // Validate all parties have correct final balances of USDX
    assertEq(usdx.balanceOf(address(generalManager)), 0, "usdx.balanceOf(generalManager)");
    assertEq(usdx.balanceOf(address(originationPool)), 0, "usdx.balanceOf(originationPool)");
    assertEq(usdx.balanceOf(address(borrower)), 0, "usdx.balanceOf(borrower)");
    assertApproxEqAbs(usdx.balanceOf(address(fulfiller)), 202_000e18, 1, "usdx.balanceOf(fulfiller) ~ 202_000e18");
    assertEq(usdx.balanceOf(address(lender)), 0, "usdx.balanceOf(lender)");
    assertGe(usdx.balanceOf(address(consol)), 1_010e18, "usdx.balanceOf(consol) >= 1_010e18");
    assertApproxEqAbs(usdx.balanceOf(address(consol)), 1_010e18, 1, "usdx.balanceOf(consol) ~ 1_010e18");

    // Validate that the borrower has the mortgageNFT
    assertEq(mortgageNFT.ownerOf(1), address(borrower));

    // Validate the mortgagePosition is active and correct
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "[1] tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "[1] collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "[1] collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "[1] collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "[1] collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "[1] subConsol");
    assertEq(mortgagePosition.interestRate, 869, "[1] interestRate");
    assertEq(mortgagePosition.conversionPremiumRate, 5000, "[1] conversionPremiumRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "[1] dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "[1] termOriginated");
    assertEq(mortgagePosition.termBalance, 127330700000000000000004, "[1] termBalance");
    assertEq(mortgagePosition.amountBorrowed, 101_000e18, "[1] amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "[1] amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "[1] termPaid");
    assertEq(mortgagePosition.termConverted, 0, "[1] termConverted");
    assertEq(mortgagePosition.amountConverted, 0, "[1] amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "[1] penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "[1] penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "[1] paymentsMissed");
    assertEq(mortgagePosition.totalPeriods, 36, "[1] totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "[1] hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "[1] status");

    // Confirm trigger price (101_000 * 150% = 151_500)
    assertEq(mortgagePosition.conversionTriggerPrice(), 151_500e18, "[1] conversionTriggerPrice");

    // Skip ahead to the origination pool's redemption phase
    vm.warp(originationPool.redemptionPhaseTimestamp());

    // Lender redeems all of the origination pool balance
    vm.startPrank(lender);
    originationPool.redeem(originationPool.balanceOf(address(lender)));
    vm.stopPrank();

    // Validatae that the lender has 102_010 Consol (101_000 * 1.01 = 102_010)
    assertGe(consol.balanceOf(address(lender)), 102_010e18, "consol.balanceOf(lender) >= 102_010e18");
    assertApproxEqAbs(consol.balanceOf(address(lender)), 102_010e18, 1, "consol.balanceOf(lender) ~ 102_010e18");

    // Have the lender deposit 1/2 of the principal worth of Consol into the conversion queue
    vm.deal(address(lender), 0.01e18);
    vm.startPrank(lender);
    consol.approve(address(conversionQueue), mortgagePosition.amountBorrowed / 2);
    conversionQueue.requestWithdrawal{value: 0.01e18}(mortgagePosition.amountBorrowed / 2);
    vm.stopPrank();

    // Set the price to the conversion trigger price: $151_500
    vm.startPrank(lender);
    _setPythPrice(pythPriceIdBTC, 151_500e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Have the rando process the conversion queue
    vm.startPrank(rando);
    processor.process(address(conversionQueue), 1);
    vm.stopPrank();

    // Update the mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Confirm that half of the term balance has been converted
    assertEq(mortgagePosition.termConverted, mortgagePosition.termBalance / 2, "[2] termConverted == termBalance / 2");

    // Skip 21 months ahead + 72 hours + 1 second (18 months have been paid off, so an addition 3 months is needed to be foreclosable)
    skip(21 * 30 days + 72 hours + 1 seconds);

    // Update the mortgage position
    mortgagePosition = loanManager.getMortgagePosition(1);

    // Validate the mortgagePosition has 3 payments missed
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.paymentsMissed, 3, "[3] paymentsMissed");

    // Have random address forcelose the position
    vm.startPrank(rando);
    loanManager.forecloseMortgage(1);
    vm.stopPrank();

    // Validate the mortgagePosition is foreclosed
    mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.FORECLOSED), "status");
    assertEq(mortgagePosition.amountForfeited(), 0, "[4] amountForfeited"); // Confirm that termConverted is not included
    assertEq(mortgagePosition.principalRemaining(), 50_500e18, "[4] principalRemaining");

    assertEq(mortgagePosition.amountPrior, 0, "[4] amountPrior");
    assertEq(mortgagePosition.termConverted, mortgagePosition.termBalance / 2, "[4] termConverted == termBalance / 2");
    assertEq(mortgagePosition.termPaid, 0, "[4] termPaid");
    assertEq(
      mortgagePosition.convertPaymentToPrincipal(mortgagePosition.termPaid + mortgagePosition.termConverted),
      50_500e18,
      "[4] convertPaymentToPrincipal(termPaid + termConverted) == 50_500"
    );
  }
}
