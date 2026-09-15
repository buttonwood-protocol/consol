// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DeployAllTest} from "./DeployAll.t.sol";
import {DeployAll} from "../../script/DeployAll.s.sol";

/**
 * @notice Runs DeployAll with a nonzero origination fee rate and verifies the GeneralManager is configured
 * from the env values. The shared scaffolding keeps the rate at 0 because the integration suites pin
 * zero-fee borrower flows; DeployAll itself originates nothing, so a nonzero rate is safe here.
 * @dev vm.setEnv writes process-global state, so the divergent rate is confined to the deployAll.setUp()
 * call and verified afterwards, mirroring DeployAllRoleInvariants.t.sol.
 */
contract DeployAllOriginationFeeTest is DeployAllTest {
  uint16 public constant LAUNCH_ORIGINATION_FEE_RATE = 100;

  function testId() public view virtual override returns (string memory) {
    return type(DeployAllOriginationFeeTest).name;
  }

  function setUp() public virtual override {
    super.setUp();
    for (uint256 attempt = 0; attempt < 20; attempt++) {
      deployAll = new DeployAll();
      deployAll.setAddressesFileSuffix(testId());
      vm.setEnv("ORIGINATION_FEE_RATE_BPS", vm.toString(uint256(LAUNCH_ORIGINATION_FEE_RATE)));
      deployAll.setUp();
      // Restore the scaffolding default so parallel suites read their expected configuration
      vm.setEnv("ORIGINATION_FEE_RATE_BPS", "0");
      if (deployAll.originationFeeRate() == LAUNCH_ORIGINATION_FEE_RATE && deployAll.feeRecipient() == feeRecipient) {
        return;
      }
    }
    revert("DeployAllOriginationFeeTest: could not build DeployAll with the launch fee rate");
  }

  function run() public virtual override {
    deployAll.run();

    assertEq(deployAll.generalManager().feeRecipient(), feeRecipient, "Fee recipient mismatch");
    assertEq(
      deployAll.generalManager().originationFeeRate(), LAUNCH_ORIGINATION_FEE_RATE, "Origination fee rate mismatch"
    );
  }
}
