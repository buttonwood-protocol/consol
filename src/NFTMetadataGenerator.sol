// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {INFTMetadataGenerator} from "./interfaces/INFTMetadataGenerator.sol";
import {MortgagePosition, MortgageStatus} from "./types/MortgagePosition.sol";
import {Roles} from "./libraries/Roles.sol";

/**
 * @title NFTMetadataGenerator
 * @author SocksNFlops
 * @notice The NFTMetadataGenerator contract renders a mortgage position as an ERC-721 metadata data URI
 */
contract NFTMetadataGenerator is Initializable, AccessControlUpgradeable, UUPSUpgradeable, INFTMetadataGenerator {
  using Strings for address;
  using Strings for uint256;

  /**
   * @notice Storage structure for the NFTMetadataGenerator contract
   * @custom:storage-location erc7201:buttonwood.storage.NFTMetadataGenerator
   * @dev Uses ERC-7201 namespaced storage pattern
   * @param _reserved Unused by this version. Reserves the namespace so a later version can add state.
   */
  struct NFTMetadataGeneratorStorage {
    uint256 _reserved;
  }

  /**
   * @dev The storage location of the NFTMetadataGenerator contract
   * @dev keccak256(abi.encode(uint256(keccak256("buttonwood.storage.NFTMetadataGenerator")) - 1)) & ~bytes32(uint256(0xff))
   */
  // solhint-disable-next-line const-name-snakecase
  bytes32 private constant NFTMetadataGeneratorStorageLocation =
    0xf4bcf94fca67fc8b4686b21f2330cb0a7de98e8d9eaf5ccaad8b293b01c42600;

  /// @dev The data URI scheme prefix that every generated metadata string carries
  string private constant METADATA_PREFIX = "data:application/json;base64,";

  /// @dev The `name` prefix, completed with the position's tokenId
  string private constant NAME_PREFIX = "Buttonwood Position #";

  /// @dev The `description` rendered for every position
  string private constant DESCRIPTION =
    "A Buttonwood Cash mortgage position: fixed-term, non-liquidating credit secured by escrowed collateral.";

  /**
   * @dev Gets the storage location of the NFTMetadataGenerator contract
   * @return $ The storage location of the NFTMetadataGenerator contract
   */
  function _getNFTMetadataGeneratorStorage() private pure returns (NFTMetadataGeneratorStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := NFTMetadataGeneratorStorageLocation
    }
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /**
   * @notice Initializes the NFTMetadataGenerator contract
   * @param admin The address granted DEFAULT_ADMIN_ROLE, which gates upgrades
   */
  function initialize(address admin) external initializer {
    __AccessControl_init();
    __UUPSUpgradeable_init();
    _grantRole(Roles.DEFAULT_ADMIN_ROLE, admin);
  }

  /**
   * @dev Authorizes the upgrade of the contract. Only the admin can authorize the upgrade
   * @param newImplementation The address of the new implementation
   */
  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(Roles.DEFAULT_ADMIN_ROLE) {}

  /**
   * @inheritdoc INFTMetadataGenerator
   */
  function generateMetadata(MortgagePosition memory mortgagePosition)
    external
    pure
    override
    returns (string memory metadata)
  {
    string memory json = string.concat(
      "{\"name\":\"",
      NAME_PREFIX,
      mortgagePosition.tokenId.toString(),
      "\",\"description\":\"",
      DESCRIPTION,
      "\",\"attributes\":[",
      _attributes(mortgagePosition),
      "]}"
    );
    metadata = string.concat(METADATA_PREFIX, Base64.encode(bytes(json)));
  }

  /**
   * @dev Renders every meaningful field of the position as a comma-separated list of attribute objects,
   * without the enclosing brackets. Built in groups because one concat over every attribute runs out of stack.
   * @param position The position of the mortgage
   * @return attributes The comma-separated attribute objects
   */
  function _attributes(MortgagePosition memory position) internal pure returns (string memory attributes) {
    attributes = string.concat(
      _collateralAttributes(position),
      ",",
      _termAttributes(position),
      ",",
      _balanceAttributes(position),
      ",",
      _statusAttributes(position)
    );
  }

  /**
   * @dev Renders the collateral-side attributes of the position
   * @param position The position of the mortgage
   * @return attributes The comma-separated attribute objects
   */
  function _collateralAttributes(MortgagePosition memory position) internal pure returns (string memory attributes) {
    attributes = string.concat(
      _stringAttribute("collateral", position.collateral.toHexString()),
      ",",
      _numberAttribute("collateralDecimals", position.collateralDecimals),
      ",",
      _amountAttribute("collateralAmount", position.collateralAmount),
      ",",
      _amountAttribute("collateralConverted", position.collateralConverted),
      ",",
      _stringAttribute("subConsol", position.subConsol.toHexString())
    );
  }

  /**
   * @dev Renders the rate and term attributes of the position. Rates are in basis points and dates are
   * unix timestamps, both as the mortgage records them.
   * @param position The position of the mortgage
   * @return attributes The comma-separated attribute objects
   */
  function _termAttributes(MortgagePosition memory position) internal pure returns (string memory attributes) {
    attributes = string.concat(
      _numberAttribute("interestRate", position.interestRate),
      ",",
      _numberAttribute("conversionPremiumRate", position.conversionPremiumRate),
      ",",
      _numberAttribute("dateOriginated", position.dateOriginated),
      ",",
      _numberAttribute("termOriginated", position.termOriginated),
      ",",
      _numberAttribute("totalPeriods", position.totalPeriods)
    );
  }

  /**
   * @dev Renders the principal and payment balances of the position
   * @param position The position of the mortgage
   * @return attributes The comma-separated attribute objects
   */
  function _balanceAttributes(MortgagePosition memory position) internal pure returns (string memory attributes) {
    attributes = string.concat(
      _amountAttribute("termBalance", position.termBalance),
      ",",
      _amountAttribute("amountBorrowed", position.amountBorrowed),
      ",",
      _amountAttribute("amountPrior", position.amountPrior),
      ",",
      _amountAttribute("termPaid", position.termPaid),
      ",",
      _amountAttribute("termConverted", position.termConverted),
      ",",
      _amountAttribute("amountConverted", position.amountConverted)
    );
  }

  /**
   * @dev Renders the penalty, payment-plan and lifecycle attributes of the position
   * @param position The position of the mortgage
   * @return attributes The comma-separated attribute objects
   */
  function _statusAttributes(MortgagePosition memory position) internal pure returns (string memory attributes) {
    attributes = string.concat(
      _amountAttribute("penaltyAccrued", position.penaltyAccrued),
      ",",
      _amountAttribute("penaltyPaid", position.penaltyPaid),
      ",",
      _numberAttribute("paymentsMissed", position.paymentsMissed),
      ",",
      _boolAttribute("hasPaymentPlan", position.hasPaymentPlan),
      ",",
      _stringAttribute("status", _statusLabel(position.status))
    );
  }

  /**
   * @dev Renders one attribute whose value is a JSON string. Every value passed here is an address or a
   * fixed label, so none of them can contain a character that JSON would need escaped.
   * @param traitType The name of the trait
   * @param value The value of the trait
   * @return attribute The attribute object
   */
  function _stringAttribute(string memory traitType, string memory value)
    internal
    pure
    returns (string memory attribute)
  {
    attribute = string.concat("{\"trait_type\":\"", traitType, "\",\"value\":\"", value, "\"}");
  }

  /**
   * @dev Renders one attribute whose value is a JSON number. Only used for values small enough to survive
   * a consumer parsing them as a double.
   * @param traitType The name of the trait
   * @param value The value of the trait
   * @return attribute The attribute object
   */
  function _numberAttribute(string memory traitType, uint256 value) internal pure returns (string memory attribute) {
    attribute = string.concat("{\"trait_type\":\"", traitType, "\",\"value\":", value.toString(), "}");
  }

  /**
   * @dev Renders one token amount as an attribute. Amounts are quoted rather than emitted as JSON numbers
   * because they routinely exceed what a consumer parsing JSON into doubles can hold exactly.
   * @param traitType The name of the trait
   * @param value The amount of the trait
   * @return attribute The attribute object
   */
  function _amountAttribute(string memory traitType, uint256 value) internal pure returns (string memory attribute) {
    attribute = _stringAttribute(traitType, value.toString());
  }

  /**
   * @dev Renders one attribute whose value is a JSON boolean
   * @param traitType The name of the trait
   * @param value The value of the trait
   * @return attribute The attribute object
   */
  function _boolAttribute(string memory traitType, bool value) internal pure returns (string memory attribute) {
    attribute = string.concat("{\"trait_type\":\"", traitType, "\",\"value\":", value ? "true" : "false", "}");
  }

  /**
   * @dev Maps a mortgage status onto its label
   * @param status The status of the mortgage
   * @return label The label for the status
   */
  function _statusLabel(MortgageStatus status) internal pure returns (string memory label) {
    if (status == MortgageStatus.ACTIVE) {
      return "ACTIVE";
    }
    if (status == MortgageStatus.FORECLOSED) {
      return "FORECLOSED";
    }
    return "REDEEMED";
  }
}
