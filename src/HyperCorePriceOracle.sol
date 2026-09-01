// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title HyperCorePriceOracle
 * @author SocksNFlops
 * @notice The HyperCorePriceOracle contract tracks the price of a given asset by reading the HyperCore oracle price
 * precompile on HyperEVM chains, to determine the trigger price for conversions.
 */
contract HyperCorePriceOracle is IPriceOracle {
  /**
   * @notice The precompile that returns the HyperCore mark price for a perp index
   * @return MARK_PX_PRECOMPILE The address of the mark price precompile
   */
  address public constant MARK_PX_PRECOMPILE = 0x0000000000000000000000000000000000000806;
  /**
   * @notice The precompile that returns the HyperCore oracle price for a perp index
   * @return ORACLE_PX_PRECOMPILE The address of the oracle price precompile
   */
  address public constant ORACLE_PX_PRECOMPILE = 0x0000000000000000000000000000000000000807;
  /**
   * @notice The precompile that returns the HyperCore perp asset info for a perp index
   * @return PERP_ASSET_INFO_PRECOMPILE The address of the perp asset info precompile
   */
  address public constant PERP_ASSET_INFO_PRECOMPILE = 0x000000000000000000000000000000000000080a;
  /**
   * @notice The maximum gas forwarded to a precompile call. The precompiles consume all forwarded gas on invalid
   * input, so the forwarded gas must be capped for failures to surface as errors instead of out-of-gas
   * @return PRECOMPILE_GAS_LIMIT The maximum gas forwarded to a precompile call
   */
  uint256 public constant PRECOMPILE_GAS_LIMIT = 30_000;
  /**
   * @notice The number of decimals for USD
   * @return USD_DECIMALS The number of decimals for USD
   */
  uint8 public constant USD_DECIMALS = 18;
  /**
   * @notice The maximum number of decimals of a HyperCore perp price. Perp prices are returned with
   * (MAX_PX_DECIMALS - szDecimals) decimals
   * @return MAX_PX_DECIMALS The maximum number of decimals of a HyperCore perp price
   */
  uint8 public constant MAX_PX_DECIMALS = 6;
  /**
   * @notice The basis points denominator
   * @return BPS The basis points denominator
   */
  uint256 public constant BPS = 10_000;
  /**
   * @notice The shortest valid perp asset info response: one word of struct offset, five words of struct head,
   * and one word of coin length
   * @return MIN_PERP_ASSET_INFO_LENGTH The shortest valid perp asset info response in bytes
   */
  uint256 public constant MIN_PERP_ASSET_INFO_LENGTH = 224;

  /**
   * @notice The HyperCore perp index of the tracked asset
   * @return perpIndex The HyperCore perp index of the tracked asset
   */
  uint32 public immutable perpIndex;
  /**
   * @notice The HyperCore size decimals of the tracked asset
   * @return szDecimals The HyperCore size decimals of the tracked asset
   */
  uint8 public immutable szDecimals;
  /**
   * @notice The maximum deviation between the mark price and the oracle price in basis points. A value of zero
   * disables the deviation guard
   * @return maxDeviationBps The maximum deviation between the mark price and the oracle price in basis points
   */
  uint16 public immutable maxDeviationBps;
  /**
   * @inheritdoc IPriceOracle
   */
  uint8 public immutable collateralDecimals;
  /**
   * @notice The multiplier that scales a raw HyperCore perp price to USD (18 decimals)
   * @return priceScale The multiplier that scales a raw HyperCore perp price to USD (18 decimals)
   */
  uint256 public immutable priceScale;

  /**
   * @notice The perp asset info reported by HyperCore. The numeric fields are declared as uint256 rather than
   * their narrow on-chain types so that decoding accepts any word HyperCore returns; a narrow type would reject a
   * word whose high bits are not cleared
   * @param coin The perp's coin symbol
   * @param marginTableId The perp's margin table id
   * @param szDecimals The perp's size decimals
   * @param maxLeverage The perp's maximum leverage
   * @param onlyIsolated Whether the perp is isolated-margin only
   */
  struct PerpAssetInfo {
    string coin;
    uint256 marginTableId;
    uint256 szDecimals;
    uint256 maxLeverage;
    uint256 onlyIsolated;
  }

  /**
   * @notice The error thrown when the size decimals exceed the maximum perp price decimals
   * @param szDecimals The size decimals
   */
  error InvalidSzDecimals(uint8 szDecimals);
  /**
   * @notice The error thrown when the size decimals do not match the perp asset info reported by HyperCore
   * @param szDecimals The size decimals passed to the constructor
   * @param reportedSzDecimals The size decimals reported by HyperCore
   */
  error SzDecimalsMismatch(uint8 szDecimals, uint256 reportedSzDecimals);
  /**
   * @notice The error thrown when the coin does not match the perp asset info reported by HyperCore
   * @param expectedCoin The coin passed to the constructor
   * @param reportedCoin The coin reported by HyperCore
   */
  error CoinMismatch(string expectedCoin, string reportedCoin);
  /**
   * @notice The error thrown when a precompile call fails or returns malformed data
   * @param precompile The address of the precompile
   */
  error PrecompileCallFailed(address precompile);
  /**
   * @notice The error thrown when the oracle price is zero
   */
  error ZeroPrice();
  /**
   * @notice The error thrown when the deviation between the mark price and the oracle price exceeds the maximum
   * deviation
   * @param deviationBps The deviation between the mark price and the oracle price in basis points
   * @param maxDeviationBps The maximum deviation in basis points
   */
  error MaxDeviationExceeded(uint256 deviationBps, uint256 maxDeviationBps);

  /**
   * @notice Constructor
   * @param perpIndex_ The HyperCore perp index of the tracked asset
   * @param szDecimals_ The HyperCore size decimals of the tracked asset
   * @param collateralDecimals_ The number of decimals for the collateral
   * @param maxDeviationBps_ The maximum deviation between the mark price and the oracle price in basis points. A
   * value of zero disables the deviation guard
   * @param expectedCoin_ The coin symbol the perp index must report. Validated against the perp asset info and
   * then discarded
   */
  constructor(
    uint32 perpIndex_,
    uint8 szDecimals_,
    uint8 collateralDecimals_,
    uint16 maxDeviationBps_,
    string memory expectedCoin_
  ) {
    if (szDecimals_ > MAX_PX_DECIMALS) {
      revert InvalidSzDecimals(szDecimals_);
    }
    perpIndex = perpIndex_;
    szDecimals = szDecimals_;
    collateralDecimals = collateralDecimals_;
    maxDeviationBps = maxDeviationBps_;
    // A raw perp price has (MAX_PX_DECIMALS - szDecimals) decimals, so scaling it to USD decimals requires
    // multiplying by 10^(USD_DECIMALS - (MAX_PX_DECIMALS - szDecimals))
    priceScale = 10 ** (USD_DECIMALS - MAX_PX_DECIMALS + szDecimals_);

    // Validate the configured perp against the perp asset info reported by HyperCore. The response is
    // abi.encode(PerpAssetInfo): one word of struct offset, then the struct itself
    (bool success, bytes memory data) =
      PERP_ASSET_INFO_PRECOMPILE.staticcall{gas: PRECOMPILE_GAS_LIMIT}(abi.encode(perpIndex_));
    if (!success || data.length < MIN_PERP_ASSET_INFO_LENGTH) {
      revert PrecompileCallFailed(PERP_ASSET_INFO_PRECOMPILE);
    }
    PerpAssetInfo memory assetInfo = abi.decode(data, (PerpAssetInfo));
    if (assetInfo.szDecimals != szDecimals_) {
      revert SzDecimalsMismatch(szDecimals_, assetInfo.szDecimals);
    }
    // Size decimals alone do not identify a perp: many perps share a value, so a mistyped index can match on
    // decimals and price a different asset. The coin symbol pins the index to one asset
    if (keccak256(bytes(assetInfo.coin)) != keccak256(bytes(expectedCoin_))) {
      revert CoinMismatch(expectedCoin_, assetInfo.coin);
    }
  }

  /**
   * @inheritdoc IPriceOracle
   */
  function price() public view override returns (uint256 assetPrice) {
    uint256 oraclePx = _readPx(ORACLE_PX_PRECOMPILE);
    if (oraclePx == 0) {
      revert ZeroPrice();
    }
    assetPrice = oraclePx * priceScale;

    // Validate the oracle price against the mark price
    if (maxDeviationBps > 0) {
      uint256 markPx = _readPx(MARK_PX_PRECOMPILE);
      uint256 deviation = markPx > oraclePx ? markPx - oraclePx : oraclePx - markPx;
      uint256 deviationBps = Math.mulDiv(deviation, BPS, oraclePx);
      if (deviationBps > maxDeviationBps) {
        revert MaxDeviationExceeded(deviationBps, maxDeviationBps);
      }
    }
  }

  /**
   * @inheritdoc IPriceOracle
   */
  function cost(uint256 collateralAmount) public view override returns (uint256 totalCost, uint8 _collateralDecimals) {
    totalCost = Math.mulDiv(collateralAmount, price(), (10 ** collateralDecimals));
    _collateralDecimals = collateralDecimals;
  }

  /**
   * @notice Reads a raw perp price from a HyperCore price precompile
   * @dev Reads a raw perp price from a HyperCore price precompile with bounded gas
   * @param precompile The address of the price precompile
   * @return px The raw perp price with (MAX_PX_DECIMALS - szDecimals) decimals
   */
  function _readPx(address precompile) internal view returns (uint64 px) {
    (bool success, bytes memory data) = precompile.staticcall{gas: PRECOMPILE_GAS_LIMIT}(abi.encode(perpIndex));
    if (!success || data.length != 32) {
      revert PrecompileCallFailed(precompile);
    }
    px = abi.decode(data, (uint64));
  }
}
