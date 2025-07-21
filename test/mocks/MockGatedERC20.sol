// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";

contract MockGatedERC20 is MockERC20 {
  address[] public admins;

  error AdminsOnly(address caller);

  constructor(string memory name, string memory symbol, uint8 _decimals, address[] memory _admins)
    MockERC20(name, symbol, _decimals)
  {
    admins = _admins;
  }

  modifier onlyAdmins() {
    bool isAdmin = false;
    for (uint256 i = 0; i < admins.length; i++) {
      if (admins[i] == _msgSender()) {
        isAdmin = true;
        break;
      }
    }
    if (!isAdmin) {
      revert AdminsOnly(_msgSender());
    }
    _;
  }

  function mint(address account, uint256 amount) external override onlyAdmins {
    _mint(account, amount);
  }

  function burn(address account, uint256 amount) external override onlyAdmins {
    _burn(account, amount);
  }
}
