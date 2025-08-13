// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IntegrationBaseTest} from "./IntegrationBase.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IOriginationPool} from "../../src/interfaces/IOriginationPool/IOriginationPool.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {MockPyth} from "../mocks/MockPyth.sol";
import {BaseRequest, CreationRequest} from "../../src/types/orders/OrderRequests.sol";
import {MortgagePosition} from "../../src/types/MortgagePosition.sol";
import {MortgageStatus} from "../../src/types/enums/MortgageStatus.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MortgageMath} from "../../src/libraries/MortgageMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Integration_27_TwoOriginationPoolsTest
 * @author @SocksNFlops
 * @notice Borrower creates a mortgage from two origination pools
 */
contract Integration_27_TwoOriginationPoolsTest is IntegrationBaseTest {
  using MortgageMath for MortgagePosition;

  address lender1 = makeAddr("lender1");
  address lender2 = makeAddr("lender2");
  IOriginationPool originationPool1;
  IOriginationPool originationPool2;

  function integrationTestId() public pure override returns (string memory) {
    return type(Integration_27_TwoOriginationPoolsTest).name;
  }

  function setUp() public virtual override(IntegrationBaseTest) {
    super.setUp();
  }

  function lender1DepositsIntoOgPool1() internal {
    // Mint 75k usdt to lender1
    MockERC20(address(usdt)).mint(address(lender1), 75_000e6);

    // Lender1 deposits the 75k usdt into USDX
    vm.startPrank(lender1);
    usdt.approve(address(usdx), 75_000e6);
    usdx.deposit(address(usdt), 75_000e6);
    vm.stopPrank();

    // Lender1 deploys originationPool1
    vm.startPrank(lender1);
    originationPool1 =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(1)));
    vm.stopPrank();

    // Confirm the originationPool1 has a poolMultiplierBps of 100
    assertEq(originationPool1.poolMultiplierBps(), 100, "originationPool1.poolMultiplierBps()");

    // Lender1 deposits USDX into originationPool1
    vm.startPrank(lender1);
    usdx.approve(address(originationPool1), 75_000e18);
    originationPool1.deposit(75_000e18);
    vm.stopPrank();
  }

  function lender2DepositsIntoOgPool2() internal {
    // Mint 25k usdt to lender2
    MockERC20(address(usdt)).mint(address(lender2), 25_000e6);

    // Lender2 deposits the 25k usdt into USDX
    vm.startPrank(lender2);
    usdt.approve(address(usdx), 25_000e6);
    usdx.deposit(address(usdt), 25_000e6);
    vm.stopPrank();

    // Lender2 deploys originationPool2
    vm.startPrank(lender2);
    originationPool2 =
      IOriginationPool(originationPoolScheduler.deployOriginationPool(originationPoolScheduler.configIdAt(2)));
    vm.stopPrank();

    // Confirm the originationPool2 has a poolMultiplierBps of 200
    assertEq(originationPool2.poolMultiplierBps(), 200, "originationPool2.poolMultiplierBps()");

    // Lender2 deposits USDX into originationPool2
    vm.startPrank(lender2);
    usdx.approve(address(originationPool2), 25_000e18);
    originationPool2.deposit(25_000e18);
    vm.stopPrank();
  }

  function run() public virtual override {
    // Lender1 deposits into originationPool1
    lender1DepositsIntoOgPool1();

    // Lender2 deposits into originationPool2
    lender2DepositsIntoOgPool2();

    // Skip time ahead to the deployPhase of the origination pools
    vm.warp(Math.max(originationPool1.deployPhaseTimestamp(), originationPool2.deployPhaseTimestamp()));

    // Mint the fulfiller 2 BTC that he is willing to sell for $200k
    MockERC20(address(btc)).mint(address(fulfiller), 2e8);
    btc.approve(address(orderPool), 2e8);

    // Total commission paid to origination pools is [(75k * 1%) + (25k * 2%)] / 100k = 1.25%
    // 100k + 1.25% = 101_250
    // Mint 101_250 usdt to the borrower
    MockERC20(address(usdt)).mint(address(borrower), 101_250e6);

    // Borrower deposits the 101_250 usdt into USDX
    vm.startPrank(borrower);
    usdt.approve(address(usdx), 101_250e6);
    usdx.deposit(address(usdt), 101_250e6);
    vm.stopPrank();

    // Update the interest rate oracle to 7.69%
    _updateInterestRateOracle(769);

    // Borrower sets the btc price to $100k
    vm.startPrank(borrower);
    MockPyth(address(pyth)).setPrice(pythPriceIdBTC, 100_000e8, 4349253107, -8, block.timestamp);
    vm.stopPrank();

    // Borrower approves the general manager to take the down payment of 101_250 usdx
    vm.startPrank(borrower);
    usdx.approve(address(generalManager), 101_250e18);
    vm.stopPrank();

    // Deal 0.01 native tokens to the borrow to pay for the gas fee (not enqueuing into a conversion queue)
    vm.deal(address(borrower), 0.01e18);

    // Borrower requests a non-compounding mortgage
    {
      uint256[] memory collateralAmounts = new uint256[](2);
      collateralAmounts[0] = 1.5e8;
      collateralAmounts[1] = 0.5e8;
      address[] memory originationPools = new address[](2);
      originationPools[0] = address(originationPool1);
      originationPools[1] = address(originationPool2);
      vm.startPrank(borrower);
      generalManager.requestMortgageCreation{value: 0.01e18}(
        CreationRequest({
          base: BaseRequest({
            collateralAmounts: collateralAmounts,
            totalPeriods: 36,
            originationPools: originationPools,
            conversionQueue: address(0),
            isCompounding: false,
            expiration: block.timestamp
          }),
          mortgageId: mortgageId,
          collateral: address(btc),
          subConsol: address(btcSubConsol),
          hasPaymentPlan: true
        })
      );
      vm.stopPrank();
    }

    // Validate that the borrower has spent 101_250 USDX
    assertEq(usdx.balanceOf(address(borrower)), 0, "usdx.balanceOf(borrower)");

    // Validate that originationPool1 has 75k USDX and originationPool2 has 25k USDX
    assertEq(usdx.balanceOf(address(originationPool1)), 75_000e18, "usdx.balanceOf(originationPool1)");
    assertEq(usdx.balanceOf(address(originationPool2)), 25_000e18, "usdx.balanceOf(originationPool2)");

    // Fulfiller approves the order pool to take his 2 btc that he's selling
    vm.startPrank(fulfiller);
    btc.approve(address(orderPool), 2 * 1e8);
    vm.stopPrank();

    // Fulfiller fulfills the order on the order pool
    vm.startPrank(fulfiller);
    orderPool.processOrders(new uint256[](1), new uint256[](1));
    vm.stopPrank();

    // Validate that originationPool1 has 75_750 Consol
    assertEq(consol.balanceOf(address(originationPool1)), 75_750e18, "consol.balanceOf(originationPool1)");
    // Validate that originationPool2 has 25_500 Consol
    assertEq(consol.balanceOf(address(originationPool2)), 25_500e18, "consol.balanceOf(originationPool2)");

    // Validate that the borrower has the mortgageNFT
    assertEq(mortgageNFT.ownerOf(1), address(borrower));

    // Validate the mortgagePosition is active and correct
    MortgagePosition memory mortgagePosition = loanManager.getMortgagePosition(1);
    assertEq(mortgagePosition.tokenId, 1, "tokenId");
    assertEq(mortgagePosition.collateral, address(btc), "collateral");
    assertEq(mortgagePosition.collateralDecimals, 8, "collateralDecimals");
    assertEq(mortgagePosition.collateralAmount, 2e8, "collateralAmount");
    assertEq(mortgagePosition.collateralConverted, 0, "collateralConverted");
    assertEq(mortgagePosition.subConsol, address(btcSubConsol), "subConsol");
    assertEq(mortgagePosition.interestRate, 869, "interestRate");
    assertEq(mortgagePosition.dateOriginated, block.timestamp, "dateOriginated");
    assertEq(mortgagePosition.termOriginated, block.timestamp, "termOriginated");
    assertEq(mortgagePosition.termBalance, 126070000000000000000020, "termBalance");
    assertEq(mortgagePosition.amountBorrowed, 100_000e18, "amountBorrowed");
    assertEq(mortgagePosition.amountPrior, 0, "amountPrior");
    assertEq(mortgagePosition.termPaid, 0, "termPaid");
    assertEq(mortgagePosition.amountConverted, 0, "amountConverted");
    assertEq(mortgagePosition.penaltyAccrued, 0, "penaltyAccrued");
    assertEq(mortgagePosition.penaltyPaid, 0, "penaltyPaid");
    assertEq(mortgagePosition.paymentsMissed, 0, "paymentsMissed");
    assertEq(mortgagePosition.periodDuration, 30 days, "periodDuration");
    assertEq(mortgagePosition.totalPeriods, 36, "totalPeriods");
    assertEq(mortgagePosition.hasPaymentPlan, true, "hasPaymentPlan");
    assertEq(uint8(mortgagePosition.status), uint8(MortgageStatus.ACTIVE), "status");
  }
}
