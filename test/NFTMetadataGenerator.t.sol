// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "./BaseTest.t.sol";
import {NFTMetadataGenerator} from "../src/NFTMetadataGenerator.sol";
import {MockNFTMetadataGeneratorUpgraded} from "./mocks/MockNFTMetadataGeneratorUpgraded.sol";
import {MortgageNFT} from "../src/MortgageNFT.sol";
import {MortgagePosition, MortgageStatus} from "../src/types/MortgagePosition.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Roles} from "../src/libraries/Roles.sol";

contract NFTMetadataGeneratorTest is BaseTest {
  string public constant METADATA_PREFIX = "data:application/json;base64,";
  string public constant DESCRIPTION =
    "A Buttonwood Cash mortgage position: fixed-term, non-liquidating credit secured by escrowed collateral.";

  NFTMetadataGenerator public generatorImplementation;
  NFTMetadataGenerator public generator;

  function setUp() public virtual override {
    super.setUp();
    generatorImplementation = new NFTMetadataGenerator();
    bytes memory initializerData = abi.encodeCall(NFTMetadataGenerator.initialize, (admin));
    generator = NFTMetadataGenerator(address(new ERC1967Proxy(address(generatorImplementation), initializerData)));
  }

  /*//////////////////////////////////////////////////////////////
                          INITIALIZATION
  //////////////////////////////////////////////////////////////*/

  function test_initialize_grantsAdminRole() public view {
    assertTrue(generator.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "Admin should hold DEFAULT_ADMIN_ROLE");
  }

  function test_initialize_grantsNoOtherAdmin(address other) public view {
    vm.assume(other != admin);
    assertFalse(generator.hasRole(Roles.DEFAULT_ADMIN_ROLE, other), "Only the initializer's admin should hold the role");
  }

  function test_initialize_revertWhenAlreadyInitialized() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    generator.initialize(admin);
  }

  function test_initialize_revertOnImplementation() public {
    vm.expectRevert(Initializable.InvalidInitialization.selector);
    generatorImplementation.initialize(admin);
  }

  /*//////////////////////////////////////////////////////////////
                              UPGRADES
  //////////////////////////////////////////////////////////////*/

  function test_upgradeTo_revertWhenNotAdmin(address caller) public {
    vm.assume(caller != admin);

    MockNFTMetadataGeneratorUpgraded newImplementation = new MockNFTMetadataGeneratorUpgraded();

    vm.startPrank(caller);
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, Roles.DEFAULT_ADMIN_ROLE)
    );
    generator.upgradeToAndCall(address(newImplementation), "");
    vm.stopPrank();
  }

  function test_upgradeTo_isAdmin(bytes32 salt) public {
    MockNFTMetadataGeneratorUpgraded newImplementation = new MockNFTMetadataGeneratorUpgraded{salt: salt}();

    vm.startPrank(admin);
    generator.upgradeToAndCall(address(newImplementation), "");
    vm.stopPrank();

    assertTrue(
      MockNFTMetadataGeneratorUpgraded(address(generator)).newFunction(),
      "generator should have the new implementation functions"
    );
    // The upgrade preserves the role that authorized it
    assertTrue(generator.hasRole(Roles.DEFAULT_ADMIN_ROLE, admin), "Admin should still hold DEFAULT_ADMIN_ROLE");
  }

  /*//////////////////////////////////////////////////////////////
                          GENERATE METADATA
  //////////////////////////////////////////////////////////////*/

  function test_generateMetadata_matchesExpectedJson() public view {
    string memory metadata = generator.generateMetadata(_samplePosition(MortgageStatus.ACTIVE));
    string memory expectedJson = _expectedSampleJson("ACTIVE");

    // The payload is the exact base64 of the expected JSON, cross-checked against forge's own encoder
    assertEq(metadata, string.concat(METADATA_PREFIX, vm.toBase64(bytes(expectedJson))), "Metadata data URI mismatch");
    // ...and decoding it back independently yields that same JSON
    assertEq(_decodeMetadata(metadata), expectedJson, "Decoded metadata mismatch");
  }

  function test_generateMetadata_decodesToParseableJson() public view {
    string memory decoded = _decodeMetadata(generator.generateMetadata(_samplePosition(MortgageStatus.ACTIVE)));

    assertEq(vm.parseJsonString(decoded, ".name"), "Buttonwood Position #7", "Name mismatch");
    assertEq(vm.parseJsonString(decoded, ".description"), DESCRIPTION, "Description mismatch");
    assertFalse(vm.keyExistsJson(decoded, ".image"), "v1 must not emit an image key");

    string[21] memory traitTypes = _expectedTraitTypes();
    for (uint256 i = 0; i < traitTypes.length; i++) {
      assertEq(
        vm.parseJsonString(decoded, string.concat(".attributes[", vm.toString(i), "].trait_type")),
        traitTypes[i],
        string.concat("Attribute #", vm.toString(i), " trait_type mismatch")
      );
    }
    assertFalse(vm.keyExistsJson(decoded, ".attributes[21]"), "Attribute count mismatch");

    assertEq(vm.parseJsonString(decoded, ".attributes[0].value"), _sampleCollateral(), "Collateral value mismatch");
    assertEq(vm.parseJsonUint(decoded, ".attributes[1].value"), 8, "Collateral decimals mismatch");
    assertEq(vm.parseJsonString(decoded, ".attributes[11].value"), "100000000000000000000000", "Borrowed mismatch");
    assertTrue(vm.parseJsonBool(decoded, ".attributes[19].value"), "Payment plan flag mismatch");
    assertEq(vm.parseJsonString(decoded, ".attributes[20].value"), "ACTIVE", "Status mismatch");
  }

  function test_generateMetadata_statusLabels() public view {
    string[3] memory labels = ["ACTIVE", "FORECLOSED", "REDEEMED"];
    for (uint256 i = 0; i < labels.length; i++) {
      string memory decoded = _decodeMetadata(generator.generateMetadata(_samplePosition(MortgageStatus(i))));
      assertEq(decoded, _expectedSampleJson(labels[i]), string.concat("Status JSON mismatch: ", labels[i]));
    }
  }

  function test_generateMetadata_tokenIdInName(uint256 tokenId) public view {
    MortgagePosition memory position = _samplePosition(MortgageStatus.ACTIVE);
    position.tokenId = tokenId;

    string memory decoded = _decodeMetadata(generator.generateMetadata(position));
    assertEq(
      vm.parseJsonString(decoded, ".name"),
      string.concat("Buttonwood Position #", vm.toString(tokenId)),
      "Name should carry the tokenId"
    );
  }

  /*//////////////////////////////////////////////////////////////
                         TOKEN URI END TO END
  //////////////////////////////////////////////////////////////*/

  function test_tokenURI_rendersRealPosition() public {
    // Open a real mortgage so the LoanManager holds a position for tokenId 1
    _mintUsdx(lender, 606_000e18);
    vm.startPrank(lender);
    usdx.approve(address(originationPool), 606_000e18);
    originationPool.deposit(606_000e18);
    vm.stopPrank();
    vm.warp(originationPool.deployPhaseTimestamp());
    _requestNoncompoundingPaymentPlanMortgage(borrower, "mortgage1", 100_000e18, 2e8, address(0));

    // The generator pointer is immutable on MortgageNFT, so point a fresh NFT at the real generator.
    // It still resolves positions through the GeneralManager's LoanManager, which now holds tokenId 1.
    MortgageNFT nft =
      new MortgageNFT(MORTGAGE_NFT_NAME, MORTGAGE_NFT_SYMBOL, address(generalManager), address(generator));
    vm.prank(address(generalManager));
    uint256 tokenId = nft.mint(borrower, "mortgage1");

    MortgagePosition memory position = loanManager.getMortgagePosition(tokenId);
    string memory decoded = _decodeMetadata(nft.tokenURI(tokenId));

    assertEq(
      vm.parseJsonString(decoded, ".name"),
      string.concat("Buttonwood Position #", vm.toString(tokenId)),
      "Name mismatch"
    );
    assertEq(
      vm.parseJsonString(decoded, ".attributes[0].value"),
      Strings.toHexString(address(wbtc)),
      "Collateral should be the mortgage's collateral"
    );
    assertEq(
      vm.parseJsonString(decoded, ".attributes[11].value"),
      vm.toString(position.amountBorrowed),
      "Borrowed amount should match the position"
    );
    assertEq(vm.parseJsonString(decoded, ".attributes[20].value"), "ACTIVE", "A fresh mortgage is ACTIVE");
  }

  /*//////////////////////////////////////////////////////////////
                              HELPERS
  //////////////////////////////////////////////////////////////*/

  /// @dev The attribute order the generator emits, which follows the MortgagePosition struct
  function _expectedTraitTypes() internal pure returns (string[21] memory traitTypes) {
    traitTypes = [
      "collateral",
      "collateralDecimals",
      "collateralAmount",
      "collateralConverted",
      "subConsol",
      "interestRate",
      "conversionPremiumRate",
      "dateOriginated",
      "termOriginated",
      "totalPeriods",
      "termBalance",
      "amountBorrowed",
      "amountPrior",
      "termPaid",
      "termConverted",
      "amountConverted",
      "penaltyAccrued",
      "penaltyPaid",
      "paymentsMissed",
      "hasPaymentPlan",
      "status"
    ];
  }

  function _sampleCollateral() internal pure returns (string memory collateral) {
    collateral = Strings.toHexString(address(0xBEEF));
  }

  function _samplePosition(MortgageStatus status) internal pure returns (MortgagePosition memory position) {
    position = MortgagePosition({
      tokenId: 7,
      collateral: address(0xBEEF),
      collateralDecimals: 8,
      collateralAmount: 2e8,
      collateralConverted: 1e7,
      subConsol: address(0xCAFE),
      interestRate: 425,
      conversionPremiumRate: 5000,
      dateOriginated: 1_700_000_000,
      termOriginated: 1_700_086_400,
      termBalance: 120_000e18,
      amountBorrowed: 100_000e18,
      amountPrior: 5_000e18,
      termPaid: 2_500e18,
      termConverted: 1_000e18,
      amountConverted: 3_000e18,
      penaltyAccrued: 42e18,
      penaltyPaid: 12e18,
      paymentsMissed: 3,
      totalPeriods: 36,
      hasPaymentPlan: true,
      status: status
    });
  }

  /// @dev The JSON literal the sample position must render to, written out rather than rebuilt from the contract's pieces
  function _expectedSampleJson(string memory statusLabel) internal pure returns (string memory json) {
    json = string.concat(
      '{"name":"Buttonwood Position #7","description":"',
      DESCRIPTION,
      '","attributes":[',
      '{"trait_type":"collateral","value":"0x000000000000000000000000000000000000beef"},',
      '{"trait_type":"collateralDecimals","value":8},',
      '{"trait_type":"collateralAmount","value":"200000000"},',
      '{"trait_type":"collateralConverted","value":"10000000"},',
      '{"trait_type":"subConsol","value":"0x000000000000000000000000000000000000cafe"},',
      '{"trait_type":"interestRate","value":425},',
      '{"trait_type":"conversionPremiumRate","value":5000},',
      '{"trait_type":"dateOriginated","value":1700000000},',
      '{"trait_type":"termOriginated","value":1700086400},',
      '{"trait_type":"totalPeriods","value":36},',
      _expectedSampleBalances(),
      '{"trait_type":"penaltyAccrued","value":"42000000000000000000"},',
      '{"trait_type":"penaltyPaid","value":"12000000000000000000"},',
      '{"trait_type":"paymentsMissed","value":3},',
      '{"trait_type":"hasPaymentPlan","value":true},',
      '{"trait_type":"status","value":"',
      statusLabel,
      '"}]}'
    );
  }

  function _expectedSampleBalances() internal pure returns (string memory json) {
    json = string.concat(
      '{"trait_type":"termBalance","value":"120000000000000000000000"},',
      '{"trait_type":"amountBorrowed","value":"100000000000000000000000"},',
      '{"trait_type":"amountPrior","value":"5000000000000000000000"},',
      '{"trait_type":"termPaid","value":"2500000000000000000000"},',
      '{"trait_type":"termConverted","value":"1000000000000000000000"},',
      '{"trait_type":"amountConverted","value":"3000000000000000000000"},'
    );
  }

  /// @dev Asserts the data URI prefix and returns the decoded JSON behind it
  function _decodeMetadata(string memory metadata) internal pure returns (string memory json) {
    bytes memory raw = bytes(metadata);
    bytes memory prefix = bytes(METADATA_PREFIX);
    require(raw.length > prefix.length, "metadata: shorter than its prefix");
    for (uint256 i = 0; i < prefix.length; i++) {
      require(raw[i] == prefix[i], "metadata: not a json base64 data uri");
    }

    bytes memory payload = new bytes(raw.length - prefix.length);
    for (uint256 i = 0; i < payload.length; i++) {
      payload[i] = raw[prefix.length + i];
    }
    json = string(_base64Decode(payload));
  }

  /// @dev Standard-alphabet base64 decoder, independent of the encoder the contract uses
  function _base64Decode(bytes memory data) internal pure returns (bytes memory decoded) {
    require(data.length % 4 == 0, "base64: bad length");
    if (data.length == 0) {
      return decoded;
    }

    uint256 padding = 0;
    if (data[data.length - 1] == "=") {
      padding++;
    }
    if (data[data.length - 2] == "=") {
      padding++;
    }

    decoded = new bytes((data.length / 4) * 3 - padding);
    uint256 written = 0;
    for (uint256 i = 0; i < data.length; i += 4) {
      uint256 chunk = (_base64Value(data[i]) << 18) | (_base64Value(data[i + 1]) << 12)
        | (_base64Value(data[i + 2]) << 6) | _base64Value(data[i + 3]);
      if (written < decoded.length) {
        decoded[written++] = bytes1(uint8(chunk >> 16));
      }
      if (written < decoded.length) {
        decoded[written++] = bytes1(uint8(chunk >> 8));
      }
      if (written < decoded.length) {
        decoded[written++] = bytes1(uint8(chunk));
      }
    }
  }

  function _base64Value(bytes1 character) internal pure returns (uint256 value) {
    uint8 code = uint8(character);
    if (code >= 65 && code <= 90) {
      return code - 65; // A-Z
    }
    if (code >= 97 && code <= 122) {
      return code - 97 + 26; // a-z
    }
    if (code >= 48 && code <= 57) {
      return code - 48 + 52; // 0-9
    }
    if (code == 43) {
      return 62; // +
    }
    if (code == 47) {
      return 63; // /
    }
    require(code == 61, "base64: bad character");
    return 0; // = padding
  }
}
