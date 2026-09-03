// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CopyOracle} from "../src/CopyOracle.sol";
import {ICopyOracle} from "../src/interfaces/ICopyOracle.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract CopyOracleTest is Test {
  // Constants
  bytes32 public constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 public constant PRICE_UPDATE_TYPEHASH = keccak256("PriceUpdate(bytes32 id,int256 price,uint256 timestamp)");
  bytes32 public constant AAPL_ID = keccak256("MOCK_PYTH:46630:AAPL");
  bytes32 public constant TSLA_ID = keccak256("MOCK_PYTH:46630:TSLA");
  int256 public constant AAPL_PRICE = 227_52000000;
  int256 public constant TSLA_PRICE = 345_98000000;
  uint256 public constant START_TIME = 1_700_000_000;

  // Actors
  address public admin;
  address public signer;
  uint256 public signerPrivateKey;
  address public relayer;

  // Contracts
  CopyOracle public oracle;

  function setUp() public virtual {
    vm.warp(START_TIME);
    admin = makeAddr("admin");
    (signer, signerPrivateKey) = makeAddrAndKey("signer");
    relayer = makeAddr("relayer");
    oracle = new CopyOracle(admin, signer);
  }

  function test_constructor() public view {
    assertEq(oracle.signer(), signer, "Signer mismatch");
    assertTrue(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), admin), "Admin role missing");
    assertFalse(oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), address(this)), "Deployer must not hold the admin role");
    assertEq(oracle.decimals(), 8, "Decimals mismatch");
    assertEq(oracle.PRICE_UPDATE_TYPEHASH(), PRICE_UPDATE_TYPEHASH, "Type hash mismatch");
  }

  function test_constructor_domain() public view {
    (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) = oracle.eip712Domain();
    assertEq(name, "CopyOracle", "Domain name mismatch");
    assertEq(version, "1", "Domain version mismatch");
    assertEq(chainId, block.chainid, "Domain chain id mismatch");
    assertEq(verifyingContract, address(oracle), "Domain verifying contract mismatch");
  }

  function test_constructor_zeroSigner() public {
    vm.expectRevert(abi.encodeWithSelector(CopyOracle.InvalidSigner.selector));
    new CopyOracle(admin, address(0));
  }

  function test_updatePrice() public {
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME);
    vm.expectEmit(true, true, true, true);
    emit ICopyOracle.PriceUpdated(AAPL_ID, AAPL_PRICE, START_TIME);
    vm.prank(relayer);
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);

    (int256 answer, uint256 updatedAt) = oracle.latestRoundData(AAPL_ID);
    assertEq(answer, AAPL_PRICE, "Answer mismatch");
    assertEq(updatedAt, START_TIME, "Updated at mismatch");
  }

  function test_updatePrice_permissionless(address caller, int256 price, uint256 timestamp) public {
    price = bound(price, 1, type(int256).max);
    timestamp = bound(timestamp, 1, START_TIME);
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, price, timestamp);
    vm.prank(caller);
    oracle.updatePrice(AAPL_ID, price, timestamp, signature);

    (int256 answer, uint256 updatedAt) = oracle.latestRoundData(AAPL_ID);
    assertEq(answer, price, "Answer mismatch");
    assertEq(updatedAt, timestamp, "Updated at mismatch");
  }

  function test_updatePrice_newerTimestamp() public {
    _update(AAPL_ID, AAPL_PRICE, START_TIME - 10);
    _update(AAPL_ID, AAPL_PRICE + 1, START_TIME);

    (int256 answer, uint256 updatedAt) = oracle.latestRoundData(AAPL_ID);
    assertEq(answer, AAPL_PRICE + 1, "Answer mismatch");
    assertEq(updatedAt, START_TIME, "Updated at mismatch");
  }

  function test_updatePrice_independentFeeds() public {
    _update(AAPL_ID, AAPL_PRICE, START_TIME);
    _update(TSLA_ID, TSLA_PRICE, START_TIME - 5);

    (int256 aaplAnswer, uint256 aaplUpdatedAt) = oracle.latestRoundData(AAPL_ID);
    (int256 tslaAnswer, uint256 tslaUpdatedAt) = oracle.latestRoundData(TSLA_ID);
    assertEq(aaplAnswer, AAPL_PRICE, "AAPL answer mismatch");
    assertEq(aaplUpdatedAt, START_TIME, "AAPL updated at mismatch");
    assertEq(tslaAnswer, TSLA_PRICE, "TSLA answer mismatch");
    assertEq(tslaUpdatedAt, START_TIME - 5, "TSLA updated at mismatch");
  }

  function test_updatePrice_wrongSigner() public {
    (, uint256 otherPrivateKey) = makeAddrAndKey("other");
    bytes memory signature = _sign(otherPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);
  }

  function test_updatePrice_tamperedPrice(int256 tamperedPrice) public {
    tamperedPrice = bound(tamperedPrice, 1, type(int256).max);
    vm.assume(tamperedPrice != AAPL_PRICE);
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, tamperedPrice, START_TIME, signature);
  }

  function test_updatePrice_tamperedTimestamp(uint256 tamperedTimestamp) public {
    tamperedTimestamp = bound(tamperedTimestamp, 1, START_TIME);
    vm.assume(tamperedTimestamp != START_TIME - 1);
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME - 1);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, tamperedTimestamp, signature);
  }

  function test_updatePrice_tamperedId(bytes32 tamperedId) public {
    vm.assume(tamperedId != AAPL_ID);
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(tamperedId, AAPL_PRICE, START_TIME, signature);
  }

  function test_updatePrice_malformedSignature(bytes memory signature) public {
    vm.assume(signature.length != 65);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);
  }

  function test_updatePrice_replayOlderTimestamp() public {
    _update(AAPL_ID, AAPL_PRICE, START_TIME);
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME - 1);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidTimestamp.selector, AAPL_ID, START_TIME - 1, START_TIME));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME - 1, signature);
  }

  function test_updatePrice_replayEqualTimestamp() public {
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME);
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidTimestamp.selector, AAPL_ID, START_TIME, START_TIME));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);
  }

  function test_updatePrice_futureTimestamp(uint256 timestamp) public {
    timestamp = bound(timestamp, START_TIME + 1, type(uint256).max);
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, timestamp);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidTimestamp.selector, AAPL_ID, timestamp, 0));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, timestamp, signature);
  }

  function test_updatePrice_zeroPrice() public {
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, 0, START_TIME);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidPrice.selector, AAPL_ID, 0));
    oracle.updatePrice(AAPL_ID, 0, START_TIME, signature);
  }

  function test_updatePrice_negativePrice(int256 price) public {
    price = bound(price, type(int256).min, -1);
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, price, START_TIME);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidPrice.selector, AAPL_ID, price));
    oracle.updatePrice(AAPL_ID, price, START_TIME, signature);
  }

  // The price is validated before the timestamp, and the timestamp before the signature
  function test_updatePrice_checkOrder() public {
    bytes memory badSignature = new bytes(65);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidPrice.selector, AAPL_ID, 0));
    oracle.updatePrice(AAPL_ID, 0, START_TIME + 1, badSignature);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidTimestamp.selector, AAPL_ID, START_TIME + 1, 0));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME + 1, badSignature);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, badSignature);
  }

  // A signature for the same reading on another contract must not verify here
  function test_updatePrice_wrongVerifyingContract() public {
    CopyOracle otherOracle = new CopyOracle(admin, signer);
    bytes32 digest = _digest(address(otherOracle), block.chainid, AAPL_ID, AAPL_PRICE, START_TIME);
    bytes memory signature = _signDigest(signerPrivateKey, digest);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);

    // The same signature is valid on the contract it was made for
    otherOracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);
  }

  // A signature for the same reading on another chain must not verify here
  function test_updatePrice_wrongChainId(uint256 chainId) public {
    chainId = bound(chainId, 1, type(uint64).max - 1);
    vm.assume(chainId != block.chainid);
    bytes32 digest = _digest(address(oracle), chainId, AAPL_ID, AAPL_PRICE, START_TIME);
    bytes memory signature = _signDigest(signerPrivateKey, digest);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);
  }

  // The domain follows the chain id, so a signature made before a chain id change stops verifying
  function test_updatePrice_chainIdChange() public {
    bytes memory signature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME);
    vm.chainId(block.chainid + 1);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, signature);

    bytes memory rebased = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME);
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, rebased);
    (int256 answer,) = oracle.latestRoundData(AAPL_ID);
    assertEq(answer, AAPL_PRICE, "Answer mismatch");
  }

  function test_updatePrices() public {
    bytes[] memory updates = new bytes[](2);
    updates[0] = _encode(AAPL_ID, AAPL_PRICE, START_TIME - 1);
    updates[1] = _encode(TSLA_ID, TSLA_PRICE, START_TIME);
    vm.expectEmit(true, true, true, true);
    emit ICopyOracle.PriceUpdated(AAPL_ID, AAPL_PRICE, START_TIME - 1);
    vm.expectEmit(true, true, true, true);
    emit ICopyOracle.PriceUpdated(TSLA_ID, TSLA_PRICE, START_TIME);
    vm.prank(relayer);
    oracle.updatePrices(updates);

    (int256 aaplAnswer, uint256 aaplUpdatedAt) = oracle.latestRoundData(AAPL_ID);
    (int256 tslaAnswer, uint256 tslaUpdatedAt) = oracle.latestRoundData(TSLA_ID);
    assertEq(aaplAnswer, AAPL_PRICE, "AAPL answer mismatch");
    assertEq(aaplUpdatedAt, START_TIME - 1, "AAPL updated at mismatch");
    assertEq(tslaAnswer, TSLA_PRICE, "TSLA answer mismatch");
    assertEq(tslaUpdatedAt, START_TIME, "TSLA updated at mismatch");
  }

  // Later elements of a batch are validated against the state written by earlier ones
  function test_updatePrices_sameFeedInOrder() public {
    bytes[] memory updates = new bytes[](2);
    updates[0] = _encode(AAPL_ID, AAPL_PRICE, START_TIME - 1);
    updates[1] = _encode(AAPL_ID, AAPL_PRICE + 1, START_TIME);
    oracle.updatePrices(updates);
    (int256 answer, uint256 updatedAt) = oracle.latestRoundData(AAPL_ID);
    assertEq(answer, AAPL_PRICE + 1, "Answer mismatch");
    assertEq(updatedAt, START_TIME, "Updated at mismatch");
  }

  function test_updatePrices_sameFeedOutOfOrder() public {
    bytes[] memory updates = new bytes[](2);
    updates[0] = _encode(AAPL_ID, AAPL_PRICE, START_TIME);
    updates[1] = _encode(AAPL_ID, AAPL_PRICE + 1, START_TIME - 1);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidTimestamp.selector, AAPL_ID, START_TIME - 1, START_TIME));
    oracle.updatePrices(updates);
  }

  // One invalid element reverts the whole batch
  function test_updatePrices_atomic() public {
    (, uint256 otherPrivateKey) = makeAddrAndKey("other");
    bytes[] memory updates = new bytes[](2);
    updates[0] = _encode(AAPL_ID, AAPL_PRICE, START_TIME);
    updates[1] = abi.encode(TSLA_ID, TSLA_PRICE, START_TIME, _sign(otherPrivateKey, TSLA_ID, TSLA_PRICE, START_TIME));
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrices(updates);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.UnknownFeed.selector, AAPL_ID));
    oracle.latestRoundData(AAPL_ID);
  }

  function test_updatePrices_empty() public {
    oracle.updatePrices(new bytes[](0));
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.UnknownFeed.selector, AAPL_ID));
    oracle.latestRoundData(AAPL_ID);
  }

  function test_latestRoundData_unknownFeed(bytes32 id) public {
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.UnknownFeed.selector, id));
    oracle.latestRoundData(id);
  }

  function test_setSigner() public {
    (address newSigner, uint256 newSignerPrivateKey) = makeAddrAndKey("newSigner");
    vm.expectEmit(true, true, true, true);
    emit ICopyOracle.SignerUpdated(signer, newSigner);
    vm.prank(admin);
    oracle.setSigner(newSigner);
    assertEq(oracle.signer(), newSigner, "Signer mismatch");

    // Only the new signer's readings are accepted
    bytes memory oldSignature = _sign(signerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME);
    vm.expectRevert(abi.encodeWithSelector(ICopyOracle.InvalidSignature.selector));
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, oldSignature);
    oracle.updatePrice(AAPL_ID, AAPL_PRICE, START_TIME, _sign(newSignerPrivateKey, AAPL_ID, AAPL_PRICE, START_TIME));
    (int256 answer,) = oracle.latestRoundData(AAPL_ID);
    assertEq(answer, AAPL_PRICE, "Answer mismatch");
  }

  function test_setSigner_notAdmin(address caller) public {
    vm.assume(caller != admin);
    address newSigner = makeAddr("newSigner");
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector, caller, oracle.DEFAULT_ADMIN_ROLE()
      )
    );
    vm.prank(caller);
    oracle.setSigner(newSigner);
    assertEq(oracle.signer(), signer, "Signer must be unchanged");
  }

  function test_setSigner_zeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(CopyOracle.InvalidSigner.selector));
    vm.prank(admin);
    oracle.setSigner(address(0));
  }

  function _update(bytes32 id, int256 price, uint256 timestamp) internal {
    oracle.updatePrice(id, price, timestamp, _sign(signerPrivateKey, id, price, timestamp));
  }

  function _encode(bytes32 id, int256 price, uint256 timestamp) internal view returns (bytes memory) {
    return abi.encode(id, price, timestamp, _sign(signerPrivateKey, id, price, timestamp));
  }

  function _sign(uint256 privateKey, bytes32 id, int256 price, uint256 timestamp) internal view returns (bytes memory) {
    return _signDigest(privateKey, _digest(address(oracle), block.chainid, id, price, timestamp));
  }

  function _signDigest(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    return abi.encodePacked(r, s, v);
  }

  // Computed independently of the contract so the test pins the exact EIP-712 encoding a signer must produce
  function _digest(address verifyingContract, uint256 chainId, bytes32 id, int256 price, uint256 timestamp)
    internal
    pure
    returns (bytes32)
  {
    bytes32 domainSeparator = keccak256(
      abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256("CopyOracle"), keccak256("1"), chainId, verifyingContract)
    );
    bytes32 structHash = keccak256(abi.encode(PRICE_UPDATE_TYPEHASH, id, price, timestamp));
    return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
  }
}
