// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IInterestRateOracle
 * @author @SocksNFlops
 * @notice Interface for the interest rate oracle.
 */
interface IInterestRateOracle {
  /**
   * @notice Returns the interest rate (in basis points) for a given total periods and amortization status
   * @param totalPeriods The total number of periods for the mortgage
   * @param hasPaymentPlan Whether the mortgage has a payment plan
   * @return The interest rate
   */
  function interestRate(uint8 totalPeriods, bool hasPaymentPlan) external view returns (uint16);
}
