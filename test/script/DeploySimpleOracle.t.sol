// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {DeploySimpleOracle} from "../../script/DeploySimpleOracle.s.sol";
import {SimpleOracle} from "../../src/SimpleOracle.sol";
import {SimpleOraclePriceOracle} from "../../src/SimpleOraclePriceOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

// The slice of the GeneralManager the script touches
contract MockGeneralManager is AccessControl {
  mapping(address collateral => address priceOracle) private _priceOracles;

  constructor(address admin) {
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
  }

  function setPriceOracle(address collateral, address priceOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _priceOracles[collateral] = priceOracle;
  }

  function priceOracles(address collateral) external view returns (address) {
    return _priceOracles[collateral];
  }
}

contract DeploySimpleOracleTest is Test {
  bytes32 public constant FEED_ID_0 = 0x4279e31cc369bbcc2faf022b382b080e32a8e689ff20fbc530d2a603eb6cd98b;
  bytes32 public constant FEED_ID_1 = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

  address public deployerAddress;
  uint256 public deployerPrivateKey;
  address public admin;
  address public signer;
  address public consol;
  MockERC20 public whype;
  MockERC20 public wbtc;
  MockGeneralManager public generalManager;
  address[] public oldPriceOracles;

  function setUp() public {
    (deployerAddress, deployerPrivateKey) = makeAddrAndKey("Deployer");
    admin = makeAddr("Simple oracle admin");
    signer = makeAddr("Simple oracle signer");
    consol = makeAddr("Consol");
    whype = new MockERC20("Wrapped HYPE", "WHYPE", 18);
    wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
    generalManager = new MockGeneralManager(deployerAddress);
    oldPriceOracles.push(makeAddr("Old price oracle 0"));
    oldPriceOracles.push(makeAddr("Old price oracle 1"));

    vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(deployerPrivateKey));
    vm.setEnv("IS_TEST", "True");
    vm.setEnv("SIMPLE_ORACLE_ADMIN", vm.toString(admin));
    vm.setEnv("SIMPLE_ORACLE_SIGNER", vm.toString(signer));
    vm.setEnv("COLLATERAL_TOKEN_LENGTH", "2");
    vm.setEnv("COLLATERAL_DECIMALS_0", "18");
    vm.setEnv("COLLATERAL_DECIMALS_1", "8");
    vm.setEnv("PYTH_PRICE_ID_0", vm.toString(FEED_ID_0));
    vm.setEnv("PYTH_PRICE_ID_1", vm.toString(FEED_ID_1));
  }

  function test_run() public {
    address[] memory collaterals = new address[](2);
    collaterals[0] = address(whype);
    collaterals[1] = address(wbtc);
    DeploySimpleOracle deploy = _prepare("DeploySimpleOracleTest", collaterals, address(generalManager));
    deploy.run();

    // The store is configured from the environment
    SimpleOracle simpleOracle = deploy.simpleOracle();
    assertEq(simpleOracle.signer(), signer, "Signer mismatch");
    assertTrue(simpleOracle.hasRole(simpleOracle.DEFAULT_ADMIN_ROLE(), admin), "Admin role missing");
    assertFalse(simpleOracle.hasRole(simpleOracle.DEFAULT_ADMIN_ROLE(), deployerAddress), "Deployer must not be admin");

    // One adapter per collateral, in collateral order, wired into the GeneralManager
    bytes32[2] memory feedIds = [FEED_ID_0, FEED_ID_1];
    uint8[2] memory decimals = [18, 8];
    for (uint256 i = 0; i < collaterals.length; i++) {
      SimpleOraclePriceOracle priceOracle = deploy.priceOracles(i);
      assertEq(address(priceOracle.simpleOracle()), address(simpleOracle), "Store mismatch");
      assertEq(priceOracle.feedId(), feedIds[i], "Feed id mismatch");
      assertEq(priceOracle.collateralDecimals(), decimals[i], "Collateral decimals mismatch");
      assertEq(priceOracle.maxAge(), 60, "Max age mismatch");
      assertEq(generalManager.priceOracles(collaterals[i]), address(priceOracle), "GeneralManager wiring mismatch");
    }

    // The address book gains simpleOracleAddress, replaces priceOracles in order, and keeps every other key
    string memory json = vm.readFile(deploy.getPath());
    assertEq(vm.parseJsonAddress(json, ".simpleOracleAddress"), address(simpleOracle), "simpleOracleAddress mismatch");
    address[] memory priceOracles = vm.parseJsonAddressArray(json, ".priceOracles");
    assertEq(priceOracles.length, 2, "priceOracles length mismatch");
    assertEq(priceOracles[0], address(deploy.priceOracles(0)), "priceOracles[0] mismatch");
    assertEq(priceOracles[1], address(deploy.priceOracles(1)), "priceOracles[1] mismatch");
    assertEq(vm.parseJsonAddressArray(json, ".collateralAddresses"), collaterals, "collateralAddresses changed");
    assertEq(vm.parseJsonAddress(json, ".generalManagerAddress"), address(generalManager), "generalManager changed");
    assertEq(vm.parseJsonAddress(json, ".consolAddress"), consol, "consolAddress changed");
    assertEq(vm.parseJsonKeys(json, "$").length, 5, "Unexpected keys");
  }

  function test_run_collateralLengthMismatch() public {
    address[] memory collaterals = new address[](3);
    collaterals[0] = address(whype);
    collaterals[1] = address(wbtc);
    collaterals[2] = address(new MockERC20("Extra", "EXTRA", 6));
    DeploySimpleOracle deploy = _prepare("DeploySimpleOracleTestLength", collaterals, address(generalManager));
    vm.expectRevert(bytes("COLLATERAL_TOKEN_LENGTH does not match the address book"));
    deploy.run();
  }

  function test_run_deployerNotAdmin() public {
    address[] memory collaterals = new address[](2);
    collaterals[0] = address(whype);
    collaterals[1] = address(wbtc);
    MockGeneralManager foreignManager = new MockGeneralManager(makeAddr("Someone else"));
    DeploySimpleOracle deploy = _prepare("DeploySimpleOracleTestAdmin", collaterals, address(foreignManager));
    vm.expectRevert(bytes("Deployer does not hold DEFAULT_ADMIN_ROLE on the GeneralManager"));
    deploy.run();
  }

  function test_run_collateralDecimalsMismatch() public {
    address[] memory collaterals = new address[](2);
    collaterals[0] = address(whype);
    collaterals[1] = address(new MockERC20("Six", "SIX", 6));
    DeploySimpleOracle deploy = _prepare("DeploySimpleOracleTestDecimals", collaterals, address(generalManager));
    vm.expectRevert(bytes("COLLATERAL_DECIMALS_1 does not match the token"));
    deploy.run();
  }

  // Writes the address book the script reads and returns a script pointed at it
  function _prepare(string memory suffix, address[] memory collaterals, address generalManagerAddress)
    internal
    returns (DeploySimpleOracle deploy)
  {
    deploy = new DeploySimpleOracle();
    deploy.setAddressesFileSuffix(suffix);
    deploy.setUp();

    string memory obj = string.concat("book-", suffix);
    vm.serializeAddress(obj, "collateralAddresses", collaterals);
    vm.serializeAddress(obj, "consolAddress", consol);
    vm.serializeAddress(obj, "generalManagerAddress", generalManagerAddress);
    string memory json = vm.serializeAddress(obj, "priceOracles", oldPriceOracles);
    vm.writeJson(json, deploy.getPath());
  }
}
