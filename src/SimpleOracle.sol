// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISimpleOracle} from "./interfaces/ISimpleOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title SimpleOracle
 * @author SocksNFlops
 * @notice The SimpleOracle contract stores the latest price per feed, accepting only readings signed by the
 * configured signer. Signatures are EIP-712 typed data bound to this chain and this contract, so a reading signed
 * for one deployment cannot be replayed on another. Anyone may relay a valid reading.
 */
contract SimpleOracle is ISimpleOracle, AccessControl, EIP712 {
  /**
   * @inheritdoc ISimpleOracle
   */
  bytes32 public constant override PRICE_UPDATE_TYPEHASH =
    keccak256("PriceUpdate(bytes32 id,int256 price,uint256 timestamp)");
  /**
   * @notice The number of decimals of every stored price, matching the source feeds
   * @return PRICE_DECIMALS The number of decimals of every stored price
   */
  uint8 public constant PRICE_DECIMALS = 8;

  /**
   * @inheritdoc ISimpleOracle
   */
  address public override signer;

  /**
   * @notice The latest stored reading of a feed
   * @param answer The price with PRICE_DECIMALS decimals
   * @param updatedAt The timestamp of the price. Zero while the feed has never been updated
   */
  struct PriceData {
    int256 answer;
    uint256 updatedAt;
  }

  /**
   * @dev The latest stored reading per feed id
   */
  mapping(bytes32 id => PriceData priceData) private _prices;

  /**
   * @notice The error thrown when the signer is set to the zero address
   */
  error InvalidSigner();

  /**
   * @notice Constructor
   * @param admin_ The address granted the DEFAULT_ADMIN_ROLE
   * @param signer_ The address whose signatures are accepted
   */
  constructor(address admin_, address signer_) EIP712("SimpleOracle", "1") {
    _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    _setSigner(signer_);
  }

  /**
   * @inheritdoc ISimpleOracle
   */
  function decimals() external pure override returns (uint8) {
    return PRICE_DECIMALS;
  }

  /**
   * @inheritdoc ISimpleOracle
   */
  function setSigner(address newSigner) external override onlyRole(DEFAULT_ADMIN_ROLE) {
    _setSigner(newSigner);
  }

  /**
   * @inheritdoc ISimpleOracle
   */
  function latestRoundData(bytes32 id) external view override returns (int256 answer, uint256 updatedAt) {
    PriceData memory priceData = _prices[id];
    if (priceData.updatedAt == 0) {
      revert UnknownFeed(id);
    }
    answer = priceData.answer;
    updatedAt = priceData.updatedAt;
  }

  /**
   * @inheritdoc ISimpleOracle
   */
  function updatePrice(bytes32 id, int256 price, uint256 timestamp, bytes calldata signature) external override {
    _updatePrice(id, price, timestamp, signature);
  }

  /**
   * @inheritdoc ISimpleOracle
   */
  function updatePrices(bytes[] calldata updates) external override {
    for (uint256 i = 0; i < updates.length; i++) {
      (bytes32 id, int256 price, uint256 timestamp, bytes memory signature) =
        abi.decode(updates[i], (bytes32, int256, uint256, bytes));
      _updatePrice(id, price, timestamp, signature);
    }
  }

  /**
   * @notice Validates and stores a signed price reading for a feed
   * @dev Validates the price, then the signature, then the timestamp, and stores the reading. A reading whose
   * timestamp equals the stored one is a no-op
   * @param id The feed id
   * @param price The price with PRICE_DECIMALS decimals
   * @param timestamp The time the reading was taken
   * @param signature The signer's EIP-712 signature over the reading
   */
  function _updatePrice(bytes32 id, int256 price, uint256 timestamp, bytes memory signature) internal {
    if (price <= 0) {
      revert InvalidPrice(id, price);
    }

    // The digest binds the reading to this chain and this contract through the EIP-712 domain
    bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(PRICE_UPDATE_TYPEHASH, id, price, timestamp)));
    (address recovered,,) = ECDSA.tryRecover(digest, signature);
    if (recovered != signer) {
      revert InvalidSignature();
    }

    // A reading must not be from the future or older than the stored one. Resubmitting the stored timestamp
    // changes nothing, so it is accepted without writing or emitting
    uint256 latest = _prices[id].updatedAt;
    if (timestamp > block.timestamp || timestamp < latest) {
      revert InvalidTimestamp(id, timestamp, latest);
    }
    if (timestamp == latest) {
      return;
    }

    _prices[id] = PriceData(price, timestamp);
    emit PriceUpdated(id, price, timestamp);
  }

  /**
   * @notice Sets the address whose signatures are accepted
   * @dev Rejects the zero address, which would otherwise match every malformed signature
   * @param newSigner The new signer
   */
  function _setSigner(address newSigner) internal {
    if (newSigner == address(0)) {
      revert InvalidSigner();
    }
    emit SignerUpdated(signer, newSigner);
    signer = newSigner;
  }
}
