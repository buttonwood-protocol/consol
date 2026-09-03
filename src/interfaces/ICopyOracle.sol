// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title ICopyOracle
 * @author SocksNFlops
 * @notice Interface for the copy oracle: a price store that accepts readings signed by a configured signer and
 * serves the latest reading per feed.
 */
interface ICopyOracle {
  /**
   * @notice A signed price reading for a feed
   * @param id The feed id
   * @param price The price with `decimals()` decimals
   * @param timestamp The time the reading was taken
   */
  struct PriceUpdate {
    bytes32 id;
    int256 price;
    uint256 timestamp;
  }

  /**
   * @notice Emitted when a feed's price is updated
   * @param id The feed id
   * @param price The new price
   * @param timestamp The timestamp of the new price
   */
  event PriceUpdated(bytes32 indexed id, int256 price, uint256 timestamp);
  /**
   * @notice Emitted when the signer is updated
   * @param previousSigner The previous signer
   * @param newSigner The new signer
   */
  event SignerUpdated(address indexed previousSigner, address indexed newSigner);

  /**
   * @notice The error thrown when a signature does not recover to the signer
   */
  error InvalidSignature();
  /**
   * @notice The error thrown when a timestamp is in the future or not newer than the stored timestamp
   * @param id The feed id
   * @param timestamp The rejected timestamp
   * @param latest The timestamp currently stored for the feed
   */
  error InvalidTimestamp(bytes32 id, uint256 timestamp, uint256 latest);
  /**
   * @notice The error thrown when a price is not positive
   * @param id The feed id
   * @param price The rejected price
   */
  error InvalidPrice(bytes32 id, int256 price);
  /**
   * @notice The error thrown when a feed has never been updated
   * @param id The feed id
   */
  error UnknownFeed(bytes32 id);

  /**
   * @notice The number of decimals of every stored price
   * @return The number of decimals of every stored price
   */
  function decimals() external view returns (uint8);

  /**
   * @notice The address whose signatures are accepted
   * @return The address whose signatures are accepted
   */
  function signer() external view returns (address);

  /**
   * @notice Sets the address whose signatures are accepted
   * @param newSigner The new signer
   */
  function setSigner(address newSigner) external;

  /**
   * @notice Returns the latest stored reading of a feed
   * @param id The feed id
   * @return answer The latest price with `decimals()` decimals
   * @return updatedAt The timestamp of the latest price
   */
  function latestRoundData(bytes32 id) external view returns (int256 answer, uint256 updatedAt);

  /**
   * @notice Stores a signed price reading for a feed
   * @param id The feed id
   * @param price The price with `decimals()` decimals
   * @param timestamp The time the reading was taken
   * @param signature The signer's EIP-712 signature over the reading
   */
  function updatePrice(bytes32 id, int256 price, uint256 timestamp, bytes calldata signature) external;

  /**
   * @notice Stores a batch of signed price readings
   * @param updates The readings, each encoded as abi.encode(bytes32 id, int256 price, uint256 timestamp, bytes
   * signature)
   */
  function updatePrices(bytes[] calldata updates) external;

  /**
   * @notice The EIP-712 type hash of a price update
   * @return The EIP-712 type hash of a price update
   */
  // solhint-disable-next-line func-name-mixedcase
  function PRICE_UPDATE_TYPEHASH() external view returns (bytes32);
}
