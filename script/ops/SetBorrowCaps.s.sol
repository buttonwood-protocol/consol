// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IGeneralManager} from "../../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/**
 * @title SetBorrowCaps
 * @notice Sets GeneralManager.maximumCap (and optionally minimumCap) for every collateral in the
 *         chain's address book, in one broadcast signed by ADMIN_ADDRESS_0.
 * @dev Inputs:
 *        BORROW_MAX_CAP     required, USDX wei (18 decimals), within [100e18, 1_000_000e18]
 *        BORROW_MIN_CAP     optional, USDX wei; when set it is applied too and must be below the max
 *        COLLATERAL_FILTER  optional, comma-separated collateral addresses from the address book
 *      Idempotent: a cap already at its target is not sent, so a re-run after a partial broadcast
 *      sends only what is missing. The checks after the broadcast run against the local simulation;
 *      verify() reads the mined chain. See script/ops/README.md.
 */
contract SetBorrowCaps is Script {
  uint256 public constant MIN_MAX_CAP = 100e18;
  uint256 public constant MAX_MAX_CAP = 1_000_000e18;

  struct CapChange {
    address collateral;
    string symbol;
    uint256 oldMax;
    uint256 oldMin;
    bool sendMax;
    bool sendMin;
  }

  IGeneralManager public generalManager;
  address public admin;
  address[] public collaterals;

  uint256 public maxCap;
  uint256 public minCap;
  bool public applyMin;
  address[] internal _filter;

  uint256 public sentCount;

  string internal _addressBookJson;
  bool internal _inputsPinned;

  /// @notice Supplies the address book JSON directly instead of reading the chain's file.
  function setAddressBookJson(string memory json) external {
    _addressBookJson = json;
  }

  /// @notice Pins the cap inputs instead of reading BORROW_MAX_CAP, BORROW_MIN_CAP and COLLATERAL_FILTER.
  function setInputs(uint256 maxCap_, bool applyMin_, uint256 minCap_, address[] memory filter) external {
    _inputsPinned = true;
    maxCap = maxCap_;
    applyMin = applyMin_;
    minCap = minCap_;
    _filter = filter;
  }

  function setUp() public virtual {
    string memory json = bytes(_addressBookJson).length != 0
      ? _addressBookJson
      : vm.readFile(string.concat(vm.projectRoot(), "/addresses/addresses-", vm.toString(block.chainid), ".json"));
    generalManager = IGeneralManager(vm.parseJsonAddress(json, ".generalManagerAddress"));
    admin = vm.envAddress("ADMIN_ADDRESS_0");

    if (!_inputsPinned) {
      maxCap = vm.envUint("BORROW_MAX_CAP");
      applyMin = vm.envExists("BORROW_MIN_CAP");
      minCap = applyMin ? vm.envUint("BORROW_MIN_CAP") : 0;
      if (vm.envExists("COLLATERAL_FILTER") && bytes(vm.envString("COLLATERAL_FILTER")).length != 0) {
        _filter = vm.envAddress("COLLATERAL_FILTER", ",");
      }
    }
    validateCaps(maxCap, applyMin, minCap);

    delete collaterals;
    address[] memory book = vm.parseJsonAddressArray(json, ".collateralAddresses");
    require(book.length != 0, "address book has no collateralAddresses");
    if (_filter.length == 0) {
      collaterals = book;
    } else {
      for (uint256 i = 0; i < _filter.length; i++) {
        require(_contains(book, _filter[i]), "COLLATERAL_FILTER has an address not in collateralAddresses");
        for (uint256 j = 0; j < i; j++) {
          require(_filter[j] != _filter[i], "COLLATERAL_FILTER has a duplicate address");
        }
        collaterals.push(_filter[i]);
      }
    }
  }

  /// @notice Reverts, naming the env var, when a cap is outside its sanity bounds.
  function validateCaps(uint256 maxCap_, bool applyMin_, uint256 minCap_) public pure {
    require(maxCap_ >= MIN_MAX_CAP && maxCap_ <= MAX_MAX_CAP, "BORROW_MAX_CAP out of bounds [100e18, 1_000_000e18]");
    require(!applyMin_ || minCap_ < maxCap_, "BORROW_MIN_CAP must be below BORROW_MAX_CAP");
  }

  function collateralCount() external view returns (uint256) {
    return collaterals.length;
  }

  function run() public {
    console.log("GeneralManager:", address(generalManager));
    console.log("Admin (ADMIN_ADDRESS_0):", admin);
    console.log("Target maximumCap:", maxCap);
    if (applyMin) {
      console.log("Target minimumCap:", minCap);
    } else {
      console.log("Target minimumCap: unchanged (BORROW_MIN_CAP not set)");
    }
    console.log("Collaterals:", collaterals.length);

    // Preconditions
    _requireGeneralManager();
    CapChange[] memory changes = new CapChange[](collaterals.length);
    uint256 pending;
    for (uint256 i = 0; i < collaterals.length; i++) {
      address collateral = collaterals[i];
      require(
        generalManager.priceOracles(collateral) != address(0), "collateral has no price oracle on the GeneralManager"
      );
      CapChange memory change = changes[i];
      change.collateral = collateral;
      change.symbol = _symbol(collateral);
      change.oldMax = generalManager.maximumCap(collateral);
      change.oldMin = generalManager.minimumCap(collateral);
      change.sendMax = change.oldMax != maxCap;
      change.sendMin = applyMin && change.oldMin != minCap;
      uint256 effectiveMin = applyMin ? minCap : change.oldMin;
      require(effectiveMin < maxCap, "on-chain minimumCap is not below BORROW_MAX_CAP; set BORROW_MIN_CAP");
      if (change.sendMax) pending++;
      if (change.sendMin) pending++;
    }
    console.log("Transactions to send:", pending);

    sentCount = 0;
    if (pending != 0) {
      vm.startBroadcast(admin);
      for (uint256 i = 0; i < changes.length; i++) {
        if (changes[i].sendMax) {
          generalManager.setMaximumCap(changes[i].collateral, maxCap);
          sentCount++;
        }
        if (changes[i].sendMin) {
          generalManager.setMinimumCap(changes[i].collateral, minCap);
          sentCount++;
        }
      }
      vm.stopBroadcast();
    } else {
      console.log("Nothing to do: every cap is already at its target");
    }

    // Postconditions
    _checkCaps();
    for (uint256 i = 0; i < changes.length; i++) {
      _logChange(i, changes[i]);
    }
    if (pending != 0) {
      console.log("Simulated values; confirm on-chain with --sig 'verify()' after broadcasting");
    }
  }

  /// @notice Read-only check that every selected collateral is at the target caps. Never broadcasts.
  function verify() public view {
    _requireGeneralManager();
    _checkCaps();
    console.log("GeneralManager:", address(generalManager));
    for (uint256 i = 0; i < collaterals.length; i++) {
      address collateral = collaterals[i];
      console.log(
        string.concat(
          "  ",
          _symbol(collateral),
          " ",
          vm.toString(collateral),
          " max ",
          vm.toString(generalManager.maximumCap(collateral)),
          " min ",
          vm.toString(generalManager.minimumCap(collateral))
        )
      );
    }
    console.log("Verified caps for", collaterals.length, "collaterals");
  }

  function _requireGeneralManager() internal view {
    require(address(generalManager).code.length != 0, "generalManagerAddress has no code");
    require(
      IAccessControl(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin),
      "ADMIN_ADDRESS_0 lacks DEFAULT_ADMIN_ROLE on the GeneralManager"
    );
  }

  function _checkCaps() internal view {
    for (uint256 i = 0; i < collaterals.length; i++) {
      require(generalManager.maximumCap(collaterals[i]) == maxCap, "maximumCap differs from BORROW_MAX_CAP");
      if (applyMin) {
        require(generalManager.minimumCap(collaterals[i]) == minCap, "minimumCap differs from BORROW_MIN_CAP");
      }
    }
  }

  function _logChange(uint256 index, CapChange memory change) internal view {
    string memory line = string.concat(
      "  [",
      vm.toString(index),
      "] ",
      change.symbol,
      " ",
      vm.toString(change.collateral),
      " max ",
      vm.toString(change.oldMax),
      change.sendMax ? string.concat(" -> ", vm.toString(maxCap)) : " unchanged"
    );
    if (applyMin) {
      line = string.concat(
        line,
        " | min ",
        vm.toString(change.oldMin),
        change.sendMin ? string.concat(" -> ", vm.toString(minCap)) : " unchanged"
      );
    }
    console.log(line);
  }

  function _symbol(address token) internal view returns (string memory) {
    try IERC20Metadata(token).symbol() returns (string memory symbol) {
      return symbol;
    } catch {
      return "?";
    }
  }

  function _contains(address[] memory list, address item) internal pure returns (bool) {
    for (uint256 i = 0; i < list.length; i++) {
      if (list[i] == item) return true;
    }
    return false;
  }
}
