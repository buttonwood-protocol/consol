// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console} from "./BaseTest.t.sol";
import {MortgageNFT} from "../src/MortgageNFT.sol";
import {MockNFTMetadataGenerator} from "./mocks/MockNFTMetadataGenerator.sol";
import {IMortgageNFT} from "../src/interfaces/IMortgageNFT/IMortgageNFT.sol";
import {IMortgageNFTEvents} from "../src/interfaces/IMortgageNFT/IMortgageNFTEvents.sol";
import {IMortgageNFTErrors} from "../src/interfaces/IMortgageNFT/IMortgageNFTErrors.sol";
import {MortgagePosition, MortgageStatus} from "../src/types/MortgagePosition.sol";
import {ILoanManager} from "../src/interfaces/ILoanManager/ILoanManager.sol";
import {IGeneralManager} from "../src/interfaces/IGeneralManager/IGeneralManager.sol";

contract MortgageNFTTest is BaseTest {
  function setUp() public override {
    super.setUp();
  }

  function test_constructor() public view {
    assertEq(mortgageNFT.name(), MORTGAGE_NFT_NAME, "Mortgage NFT name should be correct");
    assertEq(mortgageNFT.symbol(), MORTGAGE_NFT_SYMBOL, "Mortgage NFT symbol should be correct");
    assertEq(mortgageNFT.generalManager(), address(generalManager), "Mortgage NFT general manager should be correct");
    assertEq(
      mortgageNFT.nftMetadataGenerator(),
      address(nftMetadataGenerator),
      "Mortgage NFT nft metadata generator should be correct"
    );
  }

  function test_mint_revertIfMortgageIdTaken(address toA, address toB, string memory mortgageId) public {
    // Make sure neither address is the zero address
    vm.assume(toA != address(0));
    vm.assume(toB != address(0));

    // Mint an NFT to the first address with the mortgageId
    vm.startPrank(address(generalManager));
    uint256 tokenIdA = mortgageNFT.mint(toA, mortgageId);
    vm.stopPrank();

    // Attempt to mint another NFT with the same mortgageId
    vm.startPrank(address(generalManager));
    vm.expectRevert(abi.encodeWithSelector(IMortgageNFTErrors.MortgageIdAlreadyTaken.selector, tokenIdA, mortgageId));
    mortgageNFT.mint(toB, mortgageId);
    vm.stopPrank();
  }

  function test_burn_revertIfNotGeneralManager(address caller, uint256 tokenId) public {
    // Ensure the caller is not the general manager
    vm.assume(caller != address(generalManager));

    // Attempt to burn the NFT as the caller
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IMortgageNFTErrors.OnlyGeneralManager.selector, generalManager, caller));
    mortgageNFT.burn(tokenId);
    vm.stopPrank();
  }

  function test_ownerOf_mortgageId(address owner, string memory mortgageId) public {
    // Make sure the owner is not the zero address
    vm.assume(owner != address(0));

    // Mint an NFT to the owner with the mortgageId
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Validate that ownerOf returns the same owner when looking via tokenId and mortgageId
    assertEq(
      mortgageNFT.ownerOf(mortgageId), owner, "Owner of mortgageId should be the same as the owner of the tokenId"
    );
    assertEq(mortgageNFT.ownerOf(tokenId), owner, "Owner of tokenId should be the same as the owner of the mortgageId");
  }

  function test_updateMortageId_revertIfNotOwner(
    string memory callerName,
    string memory ownerName,
    string memory mortgageId,
    string memory newMortgageId
  ) public {
    // Create the caller and owner (assume they are different)
    vm.assume(keccak256(abi.encode(callerName)) != keccak256(abi.encode(ownerName)));
    address caller = makeAddr(callerName);
    address owner = makeAddr(ownerName);

    // Mint an NFT to the owner with the mortgageId
    vm.startPrank(address(generalManager));
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Attempt to update the mortgageId as the caller
    vm.startPrank(caller);
    vm.expectRevert(abi.encodeWithSelector(IMortgageNFTErrors.OnlyOwner.selector, owner, caller));
    mortgageNFT.updateMortgageId(tokenId, newMortgageId);
    vm.stopPrank();
  }

  function test_updateMortageId_revertIfMortgageIdAlreadyTaken(
    string memory ownerAName,
    string memory ownerBName,
    string memory mortgageIdA,
    string memory mortgageIdB
  ) public {
    // Assume there are different owners and mortgageIds
    vm.assume(keccak256(abi.encode(ownerAName)) != keccak256(abi.encode(ownerBName)));
    vm.assume(keccak256(abi.encode(mortgageIdA)) != keccak256(abi.encode(mortgageIdB)));

    // Create the owners
    address ownerA = makeAddr(ownerAName);
    address ownerB = makeAddr(ownerBName);

    // Get the expected tokenId
    uint256 expectedTokenId = mortgageNFT.lastTokenIdCreated() + 1;

    // Mint an NFTs to the owners with the mortgageIds
    vm.startPrank(address(generalManager));
    vm.expectEmit(true, true, true, true, address(mortgageNFT));
    emit IMortgageNFTEvents.MortgageIdUpdate(expectedTokenId, mortgageIdA);
    uint256 tokenIdA = mortgageNFT.mint(ownerA, mortgageIdA);
    uint256 tokenIdB = mortgageNFT.mint(ownerB, mortgageIdB);
    vm.stopPrank();

    // Validate that the tokenIds are correct
    assertEq(tokenIdA, expectedTokenId, "tokenIdA should be correct");
    assertEq(tokenIdB, expectedTokenId + 1, "tokenIdB should be correct");

    // Validate that the mortgageIds are correct
    assertEq(mortgageNFT.getMortgageId(tokenIdA), mortgageIdA, "mortgageIdA should be correct");
    assertEq(mortgageNFT.getMortgageId(tokenIdB), mortgageIdB, "mortgageIdB should be correct");

    // Attempt to update mortgageA to use mortgageIdB
    vm.startPrank(ownerA);
    vm.expectRevert(abi.encodeWithSelector(IMortgageNFTErrors.MortgageIdAlreadyTaken.selector, tokenIdB, mortgageIdB));
    mortgageNFT.updateMortgageId(tokenIdA, mortgageIdB);
    vm.stopPrank();
  }

  function test_updateMortageId(string memory ownerName, string memory mortgageId, string memory newMortgageId) public {
    // Create the owner
    address owner = makeAddr(ownerName);

    // Make sure the newMortgageId is different from the old mortgageId
    vm.assume(keccak256(abi.encode(newMortgageId)) != keccak256(abi.encode(mortgageId)));

    // Get the expected tokenId
    uint256 expectedTokenId = mortgageNFT.lastTokenIdCreated() + 1;

    // Mint an NFT to the owner with the mortgageId
    vm.startPrank(address(generalManager));
    vm.expectEmit(true, true, true, true, address(mortgageNFT));
    emit IMortgageNFTEvents.MortgageIdUpdate(expectedTokenId, mortgageId);
    uint256 tokenId = mortgageNFT.mint(owner, mortgageId);
    vm.stopPrank();

    // Validate that the tokenId is correct
    assertEq(tokenId, expectedTokenId, "tokenId should be correct");

    // Validate that the mortgageId is correct
    assertEq(mortgageNFT.getMortgageId(tokenId), mortgageId, "mortgageId should be correct");

    // Update the mortgageId as owner
    vm.startPrank(owner);
    vm.expectEmit(true, true, true, true, address(mortgageNFT));
    emit IMortgageNFTEvents.MortgageIdUpdate(tokenId, newMortgageId);
    mortgageNFT.updateMortgageId(tokenId, newMortgageId);
    vm.stopPrank();

    // Validate that the mortgageId was updated
    assertEq(mortgageNFT.getMortgageId(tokenId), newMortgageId, "mortgageId should be updated");
  }

  function test_tokenURI(uint256 tokenId, string calldata metadata) public {
    // Preset the metadata on the nft metadata generator
    MockNFTMetadataGenerator(address(nftMetadataGenerator)).setMetadata(metadata);

    // Mock the response to generalManager.loanManager
    vm.mockCall(
      address(generalManager), abi.encodeWithSelector(IGeneralManager.loanManager.selector), abi.encode(loanManager)
    );

    // Mock the response to loanManager.getMortgagePosition
    vm.mockCall(
      address(loanManager),
      abi.encodeWithSelector(ILoanManager.getMortgagePosition.selector, tokenId),
      abi.encode(
        MortgagePosition({
          tokenId: tokenId,
          collateral: address(0),
          collateralDecimals: 0,
          collateralAmount: 0,
          collateralConverted: 0,
          subConsol: address(0),
          interestRate: 0,
          dateOriginated: 0,
          termOriginated: 0,
          termBalance: 0,
          amountBorrowed: 0,
          amountPrior: 0,
          termPaid: 0,
          amountConverted: 0,
          penaltyAccrued: 0,
          penaltyPaid: 0,
          paymentsMissed: 0,
          periodDuration: 0,
          totalPeriods: 0,
          hasPaymentPlan: true,
          status: MortgageStatus.ACTIVE
        })
      )
    );

    // Validate that the tokenURI is correct
    assertEq(mortgageNFT.tokenURI(tokenId), metadata, "Token URI should be correct");
  }
}
