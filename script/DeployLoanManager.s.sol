// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployGeneralManager} from "./DeployGeneralManager.s.sol";
import {DeployNFTMetadataGenerator} from "./DeployNFTMetadataGenerator.s.sol";
import {ILoanManager} from "../src/interfaces/ILoanManager/ILoanManager.sol";
import {LoanManager} from "../src/LoanManager.sol";
import {IMortgageNFT} from "../src/interfaces/IMortgageNFT/IMortgageNFT.sol";

contract DeployLoanManager is DeployGeneralManager, DeployNFTMetadataGenerator {
  ILoanManager public loanManager;
  IMortgageNFT public mortgageNFT;

  function setUp() public virtual override(DeployGeneralManager, DeployNFTMetadataGenerator) {
    super.setUp();
  }

  function run() public virtual override(DeployGeneralManager, DeployNFTMetadataGenerator) {
    super.run();
    vm.startBroadcast(deployerPrivateKey);
    deployLoanManager();
    vm.stopBroadcast();
  }

  function deployLoanManager() public {
    string memory nftName = vm.envString("NFT_NAME");
    string memory nftSymbol = vm.envString("NFT_SYMBOL");

    loanManager =
      new LoanManager(nftName, nftSymbol, address(nftMetadataGenerator), address(consol), address(generalManager));

    mortgageNFT = IMortgageNFT(address(loanManager.nft()));
  }

  function logLoanManager(string memory objectKey) public returns (string memory json) {
    json = vm.serializeAddress(objectKey, "loanManagerAddress", address(loanManager));
    json = vm.serializeAddress(objectKey, "mortgageNFTAddress", address(mortgageNFT));
  }
}
