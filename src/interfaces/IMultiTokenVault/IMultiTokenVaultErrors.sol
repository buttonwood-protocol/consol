// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMultiTokenVaultErrors {
  /**
   * @notice Thrown when a token is the zero address
   */
  error TokenIsZeroAddress();

  /**
   * @notice Thrown when a token is already supported by the MultiTokenVault
   * @param token The address of the token that is already supported
   */
  error TokenAlreadySupported(address token);

  /**
   * @notice Thrown when a token is not supported by the MultiTokenVault
   * @param token The address of the token that is not supported
   */
  error TokenNotSupported(address token);

  /**
   * @notice Thrown when a deposit/withdraw is too small that no tokens will be minted/burned
   * @param amount The amount of tokens being deposited/withdrawn
   */
  error AmountTooSmall(uint256 amount);

  /**
   * @notice Thrown during burnExcessShares when the amount of shares being minted is larger than the amount of tokens being burned
   * @param sharesBurned The amount of shares being burned
   * @param sharesMinted The amount of shares being minted
   */
  error SharesMintedExceedsBurned(uint256 sharesBurned, uint256 sharesMinted);

  /**
   * @notice Thrown when a cap is set to an invalid amount (not between 0 and 10000)
   * @param capBps The cap in basis points
   */
  error InvalidCap(uint16 capBps);

  /**
   * @notice Thrown when a token's relative cap is exceeded
   * @param token The address of the token that exceeded its cap
   * @param proportion The proportion that would have resulted from the deposit
   * @param cap The maximum allowed proportion for this token in basis points
   */
  error CapExceeded(address token, uint256 proportion, uint256 cap);
}
