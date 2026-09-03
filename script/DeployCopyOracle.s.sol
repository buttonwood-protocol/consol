// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {CopyOracle} from "../src/CopyOracle.sol";
import {CopyOraclePriceOracle} from "../src/CopyOraclePriceOracle.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";
import {Roles} from "../src/libraries/Roles.sol";

/**
 * @title DeployCopyOracle
 * @notice Deploys a CopyOracle store and one CopyOraclePriceOracle adapter per collateral, points the
 * GeneralManager at the adapters, and records the new addresses in the chain's address book.
 * @dev The collaterals and the GeneralManager are read from addresses/addresses-<chainId>.json so that the
 * adapters are written back in the same positional order as the collaterals. The deployer must hold the
 * DEFAULT_ADMIN_ROLE on the GeneralManager.
 *
 * Run (from packages/contracts):
 *   forge script script/DeployCopyOracle.s.sol --rpc-url robinhood-testnet --broadcast
 */
contract DeployCopyOracle is Script {
  uint256 public constant MAX_AGE = 60 seconds;

  address public deployerAddress;
  uint256 public deployerPrivateKey;
  bool public isTest;
  string public testAddressesFileSuffix;

  address[] public collateralAddresses;
  IGeneralManager public generalManager;
  CopyOracle public copyOracle;
  CopyOraclePriceOracle[] public priceOracles;

  function setUp() public virtual {
    deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    deployerAddress = vm.addr(deployerPrivateKey);
    isTest = vm.envOr("IS_TEST", false);
  }

  function run() public virtual {
    string memory path = getPath();
    loadAddressBook(path);

    address admin = vm.envAddress("COPY_ORACLE_ADMIN");
    address signer = vm.envAddress("COPY_ORACLE_SIGNER");
    uint256 collateralTokenLength = vm.envUint("COLLATERAL_TOKEN_LENGTH");
    require(
      collateralTokenLength == collateralAddresses.length, "COLLATERAL_TOKEN_LENGTH does not match the address book"
    );
    require(
      IAccessControl(address(generalManager)).hasRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress),
      "Deployer does not hold DEFAULT_ADMIN_ROLE on the GeneralManager"
    );

    vm.startBroadcast(deployerPrivateKey);
    copyOracle = new CopyOracle(admin, signer);
    deployPriceOracles();
    vm.stopBroadcast();

    // Verify the wiring before recording it
    require(copyOracle.signer() == signer, "CopyOracle signer mismatch");
    require(copyOracle.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "CopyOracle admin missing");
    for (uint256 i = 0; i < collateralAddresses.length; i++) {
      require(
        generalManager.priceOracles(collateralAddresses[i]) == address(priceOracles[i]),
        string.concat("GeneralManager price oracle mismatch #", vm.toString(i))
      );
    }

    logAddresses(path);
  }

  function getPath() public view returns (string memory path) {
    string memory root = vm.projectRoot();
    if (isTest) {
      path = string.concat(root, "/addresses/tests/addresses-", testAddressesFileSuffix, ".json");
    } else {
      path = string.concat(root, "/addresses/addresses-", vm.toString(block.chainid), ".json");
    }
  }

  function loadAddressBook(string memory path) public {
    string memory json = vm.readFile(path);
    collateralAddresses = vm.parseJsonAddressArray(json, ".collateralAddresses");
    generalManager = IGeneralManager(vm.parseJsonAddress(json, ".generalManagerAddress"));
  }

  function deployPriceOracles() public {
    for (uint256 i = 0; i < collateralAddresses.length; i++) {
      bytes32 feedId = vm.envBytes32(string.concat("PYTH_PRICE_ID_", vm.toString(i)));
      uint8 collateralDecimals = uint8(vm.envUint(string.concat("COLLATERAL_DECIMALS_", vm.toString(i))));
      require(
        IERC20Metadata(collateralAddresses[i]).decimals() == collateralDecimals,
        string.concat("COLLATERAL_DECIMALS_", vm.toString(i), " does not match the token")
      );
      CopyOraclePriceOracle priceOracle =
        new CopyOraclePriceOracle(address(copyOracle), feedId, collateralDecimals, MAX_AGE);
      priceOracles.push(priceOracle);
      generalManager.setPriceOracle(collateralAddresses[i], address(priceOracle));
    }
  }

  /// @dev Adds copyOracleAddress to the address book and replaces priceOracles, leaving every other key untouched
  function logAddresses(string memory path) public {
    string memory obj = "addressBook";
    string memory json = vm.serializeJson(obj, vm.readFile(path));
    json = vm.serializeAddress(obj, "copyOracleAddress", address(copyOracle));
    address[] memory addressList = new address[](priceOracles.length);
    for (uint256 i = 0; i < priceOracles.length; i++) {
      addressList[i] = address(priceOracles[i]);
    }
    json = vm.serializeAddress(obj, "priceOracles", addressList);
    vm.writeJson(json, path);
  }

  /// @dev This creates a unique file suffix during unit tests. Not used in actual deployment.
  function setTestAddressesFileSuffix(string memory _testAddressesFileSuffix) public {
    testAddressesFileSuffix = _testAddressesFileSuffix;
  }
}
