// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderFulfillmentCallback} from "../../src/interfaces/IOrderFulfillmentCallback.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {MockERC20} from "./MockERC20.sol";

/**
 * @dev A fulfiller that holds no capital. Its callback spends part of the USDX advance at a mock market and
 *      mints the collateral, with switches for every way a callback can misbehave.
 */
contract MockCallbackFulfiller is IOrderFulfillmentCallback {
  enum Delivery {
    Full,
    OneShort,
    Nothing,
    FromInventory
  }

  IOrderPool public immutable orderPool;
  IERC20 public immutable usdx;
  address public immutable market;

  Delivery public delivery;
  // An optional call made from inside the callback, before delivering
  address public reentryTarget;
  bytes public reentryData;
  bool public swallowReentryFailure;
  bool public reentryFailed;

  // What the last callback observed
  uint256 public callbackCount;
  address public lastCaller;
  uint256 public lastTokenId;
  address public lastCollateral;
  uint256 public lastCollateralAmount;
  uint256 public lastUsdxAmount;
  uint256 public lastUsdxBalance;
  bytes public lastData;

  constructor(IOrderPool orderPool_, IERC20 usdx_, address market_) {
    orderPool = orderPool_;
    usdx = usdx_;
    market = market_;
  }

  receive() external payable {}

  function setDelivery(Delivery delivery_) external {
    delivery = delivery_;
  }

  function setReentry(address target, bytes calldata data, bool swallowFailure) external {
    reentryTarget = target;
    reentryData = data;
    swallowReentryFailure = swallowFailure;
  }

  function fill(uint256[] memory indices, uint256[][] memory hintPrevIdsList, bytes[] memory fulfillerDataList)
    external
  {
    orderPool.processOrdersWithCallback(indices, hintPrevIdsList, fulfillerDataList);
  }

  function fillUpfront(uint256[] memory indices, uint256[][] memory hintPrevIdsList) external {
    orderPool.processOrders(indices, hintPrevIdsList);
  }

  function approve(address token, address spender, uint256 amount) external {
    IERC20(token).approve(spender, amount);
  }

  /// @inheritdoc IOrderFulfillmentCallback
  /// @dev data is abi.encode(uint256 usdxSpend): the USDX the mock market charges for the collateral
  function orderFulfillmentCallback(
    uint256 tokenId,
    address collateral,
    uint256 collateralAmount,
    uint256 usdxAmount,
    bytes calldata data
  ) external {
    callbackCount++;
    lastCaller = msg.sender;
    lastTokenId = tokenId;
    lastCollateral = collateral;
    lastCollateralAmount = collateralAmount;
    lastUsdxAmount = usdxAmount;
    lastUsdxBalance = usdx.balanceOf(address(this));
    lastData = data;

    if (reentryTarget != address(0)) {
      // solhint-disable-next-line avoid-low-level-calls
      (bool success, bytes memory returndata) = reentryTarget.call(reentryData);
      if (!success) {
        if (!swallowReentryFailure) {
          // solhint-disable-next-line no-inline-assembly
          assembly {
            revert(add(returndata, 0x20), mload(returndata))
          }
        }
        reentryFailed = true;
      }
    }

    uint256 usdxSpend = abi.decode(data, (uint256));
    if (usdxSpend > 0) {
      usdx.transfer(market, usdxSpend);
    }

    if (delivery == Delivery.Full) {
      MockERC20(collateral).mint(msg.sender, collateralAmount);
    } else if (delivery == Delivery.OneShort) {
      MockERC20(collateral).mint(msg.sender, collateralAmount - 1);
    } else if (delivery == Delivery.FromInventory) {
      IERC20(collateral).transfer(msg.sender, collateralAmount);
    }
  }
}
