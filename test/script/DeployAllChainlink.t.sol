// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DeployAllTest} from "./DeployAll.t.sol";
import {ChainlinkPriceOracle} from "../../src/ChainlinkPriceOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @notice Runs DeployAll with the Chainlink price oracle type and verifies the deployed oracles.
 * @dev The oracle type is selected through the script's setter rather than PRICE_ORACLE_TYPE, because
 * vm.setEnv writes process-global state and a divergent oracle type would leak into parallel suites
 * (see DeployAllRoleInvariants.t.sol). CHAINLINK_MAX_PRICE_AGE is safe to set: no other suite reads it,
 * and every setUp writes the same value.
 */
contract DeployAllChainlinkTest is DeployAllTest {
  uint256 public constant MAX_PRICE_AGE = 604800;

  function testId() public view virtual override returns (string memory) {
    return type(DeployAllChainlinkTest).name;
  }

  function setUp() public virtual override {
    super.setUp();
    vm.setEnv("CHAINLINK_MAX_PRICE_AGE", "604800");
    deployAll.setPriceOracleType("chainlink");
  }

  function run() public virtual override {
    deployAll.run();

    assertTrue(deployAll.usesChainlinkPriceOracles(), "Oracle type mismatch");
    uint256 collateralTokenLength = vm.envUint("COLLATERAL_TOKEN_LENGTH");
    for (uint256 i = 0; i < collateralTokenLength; i++) {
      IERC20Metadata collateralToken = deployAll.collateralTokens(i);
      ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(address(deployAll.priceOracles(i)));

      // The oracle reads the mock aggregator's 8-decimal $1.00 reading
      assertEq(priceOracle.maxAge(), MAX_PRICE_AGE, string.concat("Max age mismatch #", vm.toString(i)));
      assertEq(priceOracle.feedDecimals(), 8, string.concat("Feed decimals mismatch #", vm.toString(i)));
      assertEq(
        priceOracle.collateralDecimals(),
        collateralToken.decimals(),
        string.concat("Collateral decimals mismatch #", vm.toString(i))
      );
      assertEq(priceOracle.price(), 1e18, string.concat("Price mismatch #", vm.toString(i)));

      // The GeneralManager prices the collateral through the Chainlink adapter
      assertEq(
        deployAll.generalManager().priceOracles(address(collateralToken)),
        address(priceOracle),
        string.concat("GeneralManager price oracle mismatch #", vm.toString(i))
      );
    }
  }
}
