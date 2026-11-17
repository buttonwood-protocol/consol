// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1822Proxiable} from "@openzeppelin/contracts/interfaces/draft-IERC1822.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {GeneralManager} from "../../src/GeneralManager.sol";
import {OrderPool} from "../../src/OrderPool.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {IOrderPool} from "../../src/interfaces/IOrderPool/IOrderPool.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/**
 * @title PayFirstUpgrade
 * @notice Moves a live chain onto the fulfillment-callback origination path: a new GeneralManager
 *         implementation and a new OrderPool, both signed by ADMIN_ADDRESS_0. Four entry points, run in order:
 *           run()       deploys the GeneralManager implementation and the configured OrderPool. Touches nothing live.
 *           pause()     pauses the GeneralManager so no order can be created during the cutover.
 *           cutover()   upgrades the GeneralManager, points it at the new OrderPool, unpauses.
 *           rollback()  points the (paused) GeneralManager back at the previous OrderPool, unpauses.
 *         verify() is read-only and never broadcasts.
 * @dev Inputs:
 *        ADMIN_ADDRESS_0                         the signer; DEFAULT_ADMIN_ROLE and PAUSE_ROLE on the GeneralManager
 *        PAY_FIRST_FULFILLERS                    comma-separated addresses granted FULFILLMENT_ROLE on the new
 *                                                OrderPool; each must hold it on the current one
 *        PAY_FIRST_GENERAL_MANAGER_IMPLEMENTATION  logged by run(); required from cutover() on
 *        PAY_FIRST_ORDER_POOL                    logged by run(); required from cutover() on
 *        PAY_FIRST_PREVIOUS_IMPLEMENTATION       logged by run(); required by rollback() and verify()
 *        PAY_FIRST_ROLLBACK_IMPLEMENTATION       optional, default false; true makes rollback() also restore
 *                                                the previous GeneralManager implementation
 *      The address book's orderPoolAddress is the previous OrderPool throughout; it is repointed in a
 *      follow-up change once the cutover is verified. See script/ops/README.md.
 */
contract PayFirstUpgrade is Script {
  /// @dev ERC-1967 implementation slot
  bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  /// @dev The GeneralManager configuration an upgrade must leave untouched
  struct Config {
    address usdx;
    address consol;
    address insuranceFund;
    address interestRateOracle;
    address originationPoolScheduler;
    address loanManager;
    address mortgageNFT;
    address feeRecipient;
    uint16 priceSpread;
    uint16 originationFeeRate;
  }

  IGeneralManager public generalManager;
  IOrderPool public previousOrderPool;
  address public admin;
  address[] public fulfillers;

  address public newImplementation;
  IOrderPool public newOrderPool;
  address public previousImplementation;
  bool public rollbackImplementation;

  string internal _addressBookJson;
  bool internal _fulfillersPinned;
  bool internal _deploymentPinned;

  /// @notice Supplies the address book JSON directly instead of reading the chain's file.
  function setAddressBookJson(string memory json) external {
    _addressBookJson = json;
  }

  /// @notice Pins the signer instead of reading ADMIN_ADDRESS_0.
  function setAdmin(address admin_) external {
    admin = admin_;
  }

  /// @notice Pins the fulfillers instead of reading PAY_FIRST_FULFILLERS.
  function setFulfillers(address[] memory fulfillers_) external {
    _fulfillersPinned = true;
    fulfillers = fulfillers_;
  }

  /// @notice Pins what run() deployed instead of reading the PAY_FIRST_* deployment variables.
  function setDeployment(
    address newImplementation_,
    address newOrderPool_,
    address previousImplementation_,
    bool rollbackImplementation_
  ) external {
    _deploymentPinned = true;
    newImplementation = newImplementation_;
    newOrderPool = IOrderPool(newOrderPool_);
    previousImplementation = previousImplementation_;
    rollbackImplementation = rollbackImplementation_;
  }

  function setUp() public virtual {
    string memory json = bytes(_addressBookJson).length != 0
      ? _addressBookJson
      : vm.readFile(string.concat(vm.projectRoot(), "/addresses/addresses-", vm.toString(block.chainid), ".json"));
    generalManager = IGeneralManager(vm.parseJsonAddress(json, ".generalManagerAddress"));
    previousOrderPool = IOrderPool(vm.parseJsonAddress(json, ".orderPoolAddress"));
    if (admin == address(0)) {
      admin = vm.envAddress("ADMIN_ADDRESS_0");
    }

    if (!_fulfillersPinned && vm.envExists("PAY_FIRST_FULFILLERS")) {
      fulfillers = vm.envAddress("PAY_FIRST_FULFILLERS", ",");
    }
    if (!_deploymentPinned) {
      newImplementation = vm.envOr("PAY_FIRST_GENERAL_MANAGER_IMPLEMENTATION", address(0));
      newOrderPool = IOrderPool(vm.envOr("PAY_FIRST_ORDER_POOL", address(0)));
      previousImplementation = vm.envOr("PAY_FIRST_PREVIOUS_IMPLEMENTATION", address(0));
      rollbackImplementation = vm.envOr("PAY_FIRST_ROLLBACK_IMPLEMENTATION", false);
    }
  }

  /// @notice Deploys the new GeneralManager implementation and the new OrderPool. Changes nothing on the live stack.
  function run() public {
    _requireAdmin();
    require(
      generalManager.orderPool() == address(previousOrderPool), "GeneralManager is not on the address book's OrderPool"
    );
    require(fulfillers.length != 0, "PAY_FIRST_FULFILLERS is empty");
    for (uint256 i = 0; i < fulfillers.length; i++) {
      require(
        IAccessControl(address(previousOrderPool)).hasRole(Roles.FULFILLMENT_ROLE, fulfillers[i]),
        "PAY_FIRST_FULFILLERS has an address without FULFILLMENT_ROLE on the current OrderPool"
      );
      for (uint256 j = 0; j < i; j++) {
        require(fulfillers[j] != fulfillers[i], "PAY_FIRST_FULFILLERS has a duplicate address");
      }
    }
    previousImplementation = _implementation();

    vm.startBroadcast(admin);
    newImplementation = address(new GeneralManager());
    newOrderPool = new OrderPool(previousOrderPool.nativeWrapper(), address(generalManager), admin);
    newOrderPool.setGasFee(previousOrderPool.gasFee());
    newOrderPool.setMaximumOrderDuration(previousOrderPool.maximumOrderDuration());
    for (uint256 i = 0; i < fulfillers.length; i++) {
      IAccessControl(address(newOrderPool)).grantRole(Roles.FULFILLMENT_ROLE, fulfillers[i]);
    }
    vm.stopBroadcast();

    _checkDeployment();
    require(generalManager.orderPool() == address(previousOrderPool), "run() must not repoint the GeneralManager");
    require(_implementation() == previousImplementation, "run() must not upgrade the GeneralManager");

    console.log("GeneralManager:", address(generalManager));
    console.log("Current OrderPool:", address(previousOrderPool));
    console.log("Record these, then continue with pause() and cutover():");
    console.log(string.concat("  PAY_FIRST_GENERAL_MANAGER_IMPLEMENTATION=", vm.toString(newImplementation)));
    console.log(string.concat("  PAY_FIRST_ORDER_POOL=", vm.toString(address(newOrderPool))));
    console.log(string.concat("  PAY_FIRST_PREVIOUS_IMPLEMENTATION=", vm.toString(previousImplementation)));
    console.log("  GeneralManager implementation runtime size:", newImplementation.code.length);
  }

  /// @notice Pauses the GeneralManager. Order requests and originations revert until cutover() or rollback() unpauses.
  function pause() public {
    _requireAdmin();
    if (generalManager.paused()) {
      console.log("Nothing to do: the GeneralManager is already paused");
      return;
    }
    vm.startBroadcast(admin);
    generalManager.setPaused(true);
    vm.stopBroadcast();
    require(generalManager.paused(), "GeneralManager is not paused");
    console.log("GeneralManager paused; continue with cutover() or rollback()");
  }

  /// @notice Upgrades the paused GeneralManager, points it at the new OrderPool, and unpauses.
  function cutover() public {
    _requireAdmin();
    require(generalManager.paused(), "GeneralManager is not paused; run pause() first");
    require(
      generalManager.orderPool() == address(previousOrderPool), "GeneralManager is not on the address book's OrderPool"
    );
    _requireNoOpenOrders(previousOrderPool);
    _checkDeployment();
    Config memory before = _config();

    vm.startBroadcast(admin);
    UUPSUpgradeable(address(generalManager)).upgradeToAndCall(newImplementation, "");
    generalManager.setOrderPool(address(newOrderPool));
    generalManager.setPaused(false);
    vm.stopBroadcast();

    _checkCutover();
    _requireSameConfig(before, _config());
    console.log("Cutover simulated; confirm on-chain with --sig 'verify()' after broadcasting");
    console.log("  GeneralManager implementation:", newImplementation);
    console.log("  OrderPool:", address(newOrderPool));
  }

  /// @notice Points the paused GeneralManager back at the previous OrderPool and unpauses. With
  ///         PAY_FIRST_ROLLBACK_IMPLEMENTATION=true it also restores the previous implementation.
  function rollback() public {
    _requireAdmin();
    require(generalManager.paused(), "GeneralManager is not paused; run pause() first");
    require(address(newOrderPool) != address(0), "PAY_FIRST_ORDER_POOL is not set");
    require(generalManager.orderPool() == address(newOrderPool), "GeneralManager is not on PAY_FIRST_ORDER_POOL");
    _requireNoOpenOrders(newOrderPool);
    if (rollbackImplementation) {
      require(previousImplementation.code.length != 0, "PAY_FIRST_PREVIOUS_IMPLEMENTATION has no code");
    }
    Config memory before = _config();

    vm.startBroadcast(admin);
    generalManager.setOrderPool(address(previousOrderPool));
    if (rollbackImplementation) {
      UUPSUpgradeable(address(generalManager)).upgradeToAndCall(previousImplementation, "");
    }
    generalManager.setPaused(false);
    vm.stopBroadcast();

    require(
      generalManager.orderPool() == address(previousOrderPool), "GeneralManager is not back on the previous OrderPool"
    );
    require(
      IAccessControl(address(generalManager)).hasRole(Roles.NFT_ROLE, address(previousOrderPool)),
      "previous OrderPool lacks NFT_ROLE"
    );
    require(
      !IAccessControl(address(generalManager)).hasRole(Roles.NFT_ROLE, address(newOrderPool)),
      "new OrderPool still holds NFT_ROLE"
    );
    if (rollbackImplementation) {
      require(_implementation() == previousImplementation, "previous implementation was not restored");
    }
    require(!generalManager.paused(), "GeneralManager is still paused");
    _requireSameConfig(before, _config());
    console.log("Rolled back to OrderPool:", address(previousOrderPool));
    console.log("  GeneralManager implementation:", _implementation());
  }

  /// @notice Read-only check that the cutover is in place. Never broadcasts.
  function verify() public view {
    _checkDeployment();
    _checkCutover();
    _requireNoOpenOrders(previousOrderPool);
    console.log("GeneralManager:", address(generalManager));
    console.log("  implementation:", newImplementation);
    console.log("  implementation runtime size:", newImplementation.code.length);
    console.log("  previous implementation:", previousImplementation);
    console.log("OrderPool:", address(newOrderPool));
    console.log("  previous OrderPool:", address(previousOrderPool));
    console.log("  gasFee:", newOrderPool.gasFee());
    console.log("  maximumOrderDuration:", newOrderPool.maximumOrderDuration());
    console.log("  orderCount:", newOrderPool.orderCount());
    for (uint256 i = 0; i < fulfillers.length; i++) {
      console.log("  FULFILLMENT_ROLE:", fulfillers[i]);
    }
    console.log("Verified the pay-first cutover");
  }

  /// @notice The EIP-170 runtime size limit the new implementation must fit.
  /// @dev Overridable for builds that compile the GeneralManager with other optimizer settings than this repo.
  function maxRuntimeSize() public pure virtual returns (uint256) {
    return 24_576;
  }

  function fulfillerCount() external view returns (uint256) {
    return fulfillers.length;
  }

  function _requireAdmin() internal view {
    require(address(generalManager).code.length != 0, "generalManagerAddress has no code");
    require(
      IAccessControl(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin),
      "ADMIN_ADDRESS_0 lacks DEFAULT_ADMIN_ROLE on the GeneralManager"
    );
    require(
      IAccessControl(address(generalManager)).hasRole(Roles.PAUSE_ROLE, admin),
      "ADMIN_ADDRESS_0 lacks PAUSE_ROLE on the GeneralManager"
    );
  }

  /// @dev Reverts when an order pool still holds an order. An order left in a pool the GeneralManager no
  ///      longer points at can neither be filled nor refunded until the GeneralManager points back at it.
  function _requireNoOpenOrders(IOrderPool pool) internal view {
    uint256 count = pool.orderCount();
    for (uint256 i = 0; i < count; i++) {
      require(
        pool.orders(i).mortgageParams.collateral == address(0), "an OrderPool being left still holds an open order"
      );
    }
  }

  /// @dev Checks what run() deployed: the implementation is a GeneralManager that fits EIP-170, and the new
  ///      OrderPool is wired and configured like the previous one.
  function _checkDeployment() internal view {
    require(newImplementation.code.length != 0, "PAY_FIRST_GENERAL_MANAGER_IMPLEMENTATION has no code");
    require(
      newImplementation.code.length <= maxRuntimeSize(), "GeneralManager implementation exceeds the EIP-170 limit"
    );
    require(
      IERC1822Proxiable(newImplementation).proxiableUUID() == IMPLEMENTATION_SLOT,
      "PAY_FIRST_GENERAL_MANAGER_IMPLEMENTATION is not a UUPS implementation"
    );
    require(address(newOrderPool).code.length != 0, "PAY_FIRST_ORDER_POOL has no code");
    require(address(newOrderPool) != address(previousOrderPool), "PAY_FIRST_ORDER_POOL is the previous OrderPool");
    require(
      IERC165(address(newOrderPool)).supportsInterface(type(IOrderPool).interfaceId),
      "PAY_FIRST_ORDER_POOL does not support processOrdersWithCallback"
    );
    require(newOrderPool.generalManager() == address(generalManager), "new OrderPool has another GeneralManager");
    require(newOrderPool.usdx() == generalManager.usdx(), "new OrderPool has another USDX");
    require(newOrderPool.consol() == generalManager.consol(), "new OrderPool has another Consol");
    require(
      newOrderPool.nativeWrapper() == previousOrderPool.nativeWrapper(), "new OrderPool has another native wrapper"
    );
    require(newOrderPool.gasFee() == previousOrderPool.gasFee(), "new OrderPool gasFee differs");
    require(
      newOrderPool.maximumOrderDuration() == previousOrderPool.maximumOrderDuration(),
      "new OrderPool maximumOrderDuration differs"
    );
    require(
      IAccessControl(address(newOrderPool)).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin),
      "ADMIN_ADDRESS_0 lacks DEFAULT_ADMIN_ROLE on the new OrderPool"
    );
    for (uint256 i = 0; i < fulfillers.length; i++) {
      require(
        IAccessControl(address(newOrderPool)).hasRole(Roles.FULFILLMENT_ROLE, fulfillers[i]),
        "a fulfiller lacks FULFILLMENT_ROLE on the new OrderPool"
      );
    }
  }

  function _checkCutover() internal view {
    require(_implementation() == newImplementation, "GeneralManager is not on the new implementation");
    require(generalManager.orderPool() == address(newOrderPool), "GeneralManager is not on the new OrderPool");
    require(
      IAccessControl(address(generalManager)).hasRole(Roles.NFT_ROLE, address(newOrderPool)),
      "new OrderPool lacks NFT_ROLE"
    );
    require(
      !IAccessControl(address(generalManager)).hasRole(Roles.NFT_ROLE, address(previousOrderPool)),
      "previous OrderPool still holds NFT_ROLE"
    );
    require(
      IAccessControl(address(generalManager)).hasRole(Roles.NFT_ROLE, generalManager.loanManager()),
      "LoanManager lacks NFT_ROLE"
    );
    require(!generalManager.paused(), "GeneralManager is paused");
  }

  function _implementation() internal view returns (address) {
    return address(uint160(uint256(vm.load(address(generalManager), IMPLEMENTATION_SLOT))));
  }

  function _config() internal view returns (Config memory) {
    return Config({
      usdx: generalManager.usdx(),
      consol: generalManager.consol(),
      insuranceFund: generalManager.insuranceFund(),
      interestRateOracle: generalManager.interestRateOracle(),
      originationPoolScheduler: generalManager.originationPoolScheduler(),
      loanManager: generalManager.loanManager(),
      mortgageNFT: generalManager.mortgageNFT(),
      feeRecipient: generalManager.feeRecipient(),
      priceSpread: generalManager.priceSpread(),
      originationFeeRate: generalManager.originationFeeRate()
    });
  }

  function _requireSameConfig(Config memory a, Config memory b) internal pure {
    require(keccak256(abi.encode(a)) == keccak256(abi.encode(b)), "GeneralManager configuration changed");
  }
}
