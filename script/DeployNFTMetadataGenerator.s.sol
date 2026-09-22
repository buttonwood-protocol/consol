// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseScript} from "./BaseScript.s.sol";
import {INFTMetadataGenerator} from "../src/interfaces/INFTMetadataGenerator.sol";
import {NFTMetadataGenerator} from "../src/NFTMetadataGenerator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract DeployNFTMetadataGenerator is BaseScript {
  NFTMetadataGenerator public nftMetadataGeneratorImplementation;
  INFTMetadataGenerator public nftMetadataGenerator;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual override {
    super.run();
    startDeployerBroadcast();
    deployNFTMetadataGenerator();
    vm.stopBroadcast();
  }

  /**
   * @notice Deploys the NFT metadata generator the LoanManager's MortgageNFT will point at.
   * @dev The pointer is immutable on the NFT, so the NFT gets the UUPS proxy rather than the implementation.
   */
  function deployNFTMetadataGenerator() public {
    nftMetadataGeneratorImplementation = new NFTMetadataGenerator();
    bytes memory initializerData = abi.encodeCall(NFTMetadataGenerator.initialize, (deployerAddress));
    ERC1967Proxy proxy = new ERC1967Proxy(address(nftMetadataGeneratorImplementation), initializerData);
    nftMetadataGenerator = INFTMetadataGenerator(address(proxy));

    // Grant the admin role to the admins
    for (uint256 i = 0; i < admins.length; i++) {
      NFTMetadataGenerator(address(nftMetadataGenerator)).grantRole(Roles.DEFAULT_ADMIN_ROLE, admins[i]);
    }

    // Renounce the deployer's admin role (skipped when the deployer must keep it; see BaseScript.renounceUnlessAdmin)
    renounceUnlessAdmin(address(nftMetadataGenerator), Roles.DEFAULT_ADMIN_ROLE);
  }

  function logNFTMetadataGenerator(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "nftMetadataGeneratorAddress", address(nftMetadataGenerator));
  }
}
