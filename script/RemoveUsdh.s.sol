// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {USDX} from "../src/USDX.sol";

/**
 * @title RemoveUsdh
 * @notice SOC-66: delist USDH from USDX on HyperEVM mainnet.
 * @dev removeSupportedToken does not check residual balance; any USDH held by
 *      USDX at removal is permanently locked and rebases USDX down. The balance
 *      assertion below executes in the same transaction context as the removal,
 *      so a donation cannot land in between.
 *
 * Run (from packages/contracts, signer must hold SUPPORTED_TOKEN_ROLE):
 *   forge script script/RemoveUsdh.s.sol --rpc-url https://rpc.hyperliquid.xyz/evm --broadcast <signer flags>
 */
contract RemoveUsdh is Script {
  address internal constant USDX_ADDRESS = 0x22632C11c1B4FF37edB06DDC1d5bF9C4ca2132E5;
  address internal constant USDH_ADDRESS = 0x111111a1a0667d36bD57c0A9f569b98057111111;
  address internal constant USDT0_ADDRESS = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
  address internal constant USDC_ADDRESS = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

  function run() external {
    USDX usdx = USDX(USDX_ADDRESS);

    uint256 usdhBalance = IERC20(USDH_ADDRESS).balanceOf(USDX_ADDRESS);
    uint256 supplyBefore = usdx.totalSupply();
    require(usdx.isTokenSupported(USDH_ADDRESS), "USDH already removed");
    require(usdhBalance == 0, "USDX holds USDH: drain via withdraw() before removing");

    vm.startBroadcast();
    usdx.removeSupportedToken(USDH_ADDRESS);
    vm.stopBroadcast();

    require(!usdx.isTokenSupported(USDH_ADDRESS), "removal failed");
    require(usdx.isTokenSupported(USDT0_ADDRESS) && usdx.isTokenSupported(USDC_ADDRESS), "wrong token removed");
    require(usdx.totalSupply() == supplyBefore, "totalSupply changed: holders were rebased");
    console.log("USDH removed. totalSupply unchanged:", supplyBefore);
  }
}
