// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MockGatedERC20} from "../test/mocks/MockGatedERC20.sol";

/**
 * @notice Deploys the 10 mock Robinhood stock tokens (BW-114) as MockGatedERC20s.
 * @dev Mint admins are read from the MOCK_MINT_ADMIN_* env namespace, deliberately
 * separate from ADMIN_ADDRESS_*: the fulfiller bot keeper needs mint rights on these
 * mocks without being a protocol admin.
 *
 * Uses the parameterless vm.startBroadcast() so the signer comes from the CLI
 * (--private-key / --ledger / etc.).
 */
contract DeployMockStockTokens is Script {
  uint8 public constant DECIMALS = 18;

  address[] public mintAdmins;

  function setUp() public {
    uint256 adminLength = vm.envUint("MOCK_MINT_ADMIN_LENGTH");
    // MockGatedERC20's admin list is constructor-immutable: there is no way to add an
    // admin after deployment. A deploy with only the maintainer would lock the fulfiller
    // bot keeper out of mint() and force a redeploy, so require both up front.
    require(adminLength >= 2, "need maintainer + fulfiller keeper");
    for (uint256 i = 0; i < adminLength; i++) {
      mintAdmins.push(vm.envAddress(string.concat("MOCK_MINT_ADMIN_ADDRESS_", vm.toString(i))));
    }
  }

  function run() public {
    // "m" prefix marks these as mocks: Robinhood ships real faucet Stock Tokens on this
    // testnet (TSLA, AMZN, NFLX, AMD, PLTR), so unprefixed symbols would collide with,
    // and be mistaken for, genuine issuer tokens.
    string[10] memory symbols = ["mNVDA", "mTSLA", "mAAPL", "mMSFT", "mAMZN", "mMETA", "mGOOGL", "mSPY", "mGME", "mQQQ"];
    string[10] memory names = [
      "Mock NVIDIA",
      "Mock Tesla",
      "Mock Apple",
      "Mock Microsoft",
      "Mock Amazon",
      "Mock Meta Platforms",
      "Mock Alphabet",
      "Mock SPDR S&P 500 ETF",
      "Mock GameStop",
      "Mock Invesco QQQ Trust"
    ];

    address[10] memory deployed;

    vm.startBroadcast();
    for (uint256 i = 0; i < symbols.length; i++) {
      deployed[i] = address(new MockGatedERC20(names[i], symbols[i], DECIMALS, mintAdmins));
    }
    vm.stopBroadcast();

    console.log("=== Mock stock tokens (ticker -> address) ===");
    for (uint256 i = 0; i < symbols.length; i++) {
      console.log(symbols[i], "->", deployed[i]);
    }
  }
}
