// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DeployAllTest} from "./DeployAll.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
import {MortgageNFT} from "../../src/MortgageNFT.sol";
import {NFTMetadataGenerator} from "../../src/NFTMetadataGenerator.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/**
 * @notice Runs DeployAll in production mode (neither IS_TEST nor IS_TESTNET) and verifies the pieces that
 * only exist on that path: the mock-only deploys are skipped and the NFT metadata generator is the real
 * UUPS proxy the MortgageNFT points at.
 * @dev The mode is flipped through the script's setter rather than IS_TEST / IS_TESTNET, because vm.setEnv
 * writes process-global state and every other DeployAll suite depends on those two variables reading as
 * test mode (see DeployAllRoleInvariants.t.sol). The production-only variables written here are additive:
 * no test-mode suite ever reads them, so a parallel suite cannot observe a divergent value.
 */
contract DeployAllProductionTest is DeployAllTest {
  string public constant METADATA_PREFIX = "data:application/json;base64,";

  function testId() public pure virtual override returns (string memory) {
    return type(DeployAllProductionTest).name;
  }

  function setUp() public virtual override {
    super.setUp();

    // Production takes its collateral, USD tokens and Pyth contract as given rather than deploying them
    vm.setEnv("COLLATERAL_ADDRESS_1", vm.toString(address(new MockERC20("Wrapped Bitcoin", "WBTC", 8))));
    vm.setEnv("USD_ADDRESS_0", vm.toString(address(new MockERC20("Tether USD", "USDT0", 6))));
    vm.setEnv("USD_ADDRESS_1", vm.toString(address(new MockERC20("USD Coin", "USDC", 6))));
    vm.setEnv("PYTH_ADDRESS", vm.toString(address(new MockPyth(120, 0))));

    deployAll.setDeployMode(false, false);
  }

  function run() public virtual override {
    super.run();

    assertFalse(deployAll.isTest(), "Script should have run in production mode");
    assertFalse(deployAll.isTestnet(), "Script should have run in production mode");

    address generator = address(deployAll.nftMetadataGenerator());
    address implementation = address(deployAll.nftMetadataGeneratorImplementation());

    assertTrue(generator != address(0), "nftMetadataGeneratorAddress should be non-zero in production");
    assertTrue(implementation != address(0), "The generator implementation should have been deployed");
    assertTrue(generator != implementation, "The generator should be the proxy, not the implementation");

    // The logged address book carries the proxy
    assertEq(
      vm.parseJsonAddress(vm.readFile(deployAll.getPath()), ".nftMetadataGeneratorAddress"),
      generator,
      "Logged nftMetadataGeneratorAddress mismatch"
    );

    // The MortgageNFT's immutable pointer is the proxy
    MortgageNFT mortgageNFT = MortgageNFT(address(deployAll.mortgageNFT()));
    assertEq(mortgageNFT.nftMetadataGenerator(), generator, "MortgageNFT should point at the deployed generator");

    // The proxy's admin role went to the configured admins and the deployer walked away without it
    assertTrue(
      IAccessControl(generator).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin1), "First admin missing DEFAULT_ADMIN_ROLE"
    );
    assertTrue(
      IAccessControl(generator).hasRole(Roles.DEFAULT_ADMIN_ROLE, admin2), "Second admin missing DEFAULT_ADMIN_ROLE"
    );
    assertFalse(
      IAccessControl(generator).hasRole(Roles.DEFAULT_ADMIN_ROLE, deployerAddress),
      "Deployer should have renounced DEFAULT_ADMIN_ROLE"
    );

    // A minted position renders through the real generator
    vm.prank(address(deployAll.generalManager()));
    uint256 tokenId = mortgageNFT.mint(address(this), "mortgage1");
    assertTrue(_hasMetadataPrefix(mortgageNFT.tokenURI(tokenId)), "tokenURI should be a json base64 data uri");
  }

  function _hasMetadataPrefix(string memory uri) internal pure returns (bool hasPrefix) {
    bytes memory raw = bytes(uri);
    bytes memory prefix = bytes(METADATA_PREFIX);
    if (raw.length <= prefix.length) {
      return false;
    }
    for (uint256 i = 0; i < prefix.length; i++) {
      if (raw[i] != prefix[i]) {
        return false;
      }
    }
    hasPrefix = true;
  }
}
