// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract MockHyperCorePrecompile {
  mapping(uint32 => bytes) internal _responses;
  bool internal _consumeAllGas;

  function setResponse(uint32 index, bytes memory response) external {
    _responses[index] = response;
  }

  function setConsumeAllGas(bool consumeAllGas_) external {
    _consumeAllGas = consumeAllGas_;
  }

  fallback(bytes calldata input) external returns (bytes memory) {
    uint32 index = abi.decode(input, (uint32));
    bytes memory response = _responses[index];
    if (_consumeAllGas || response.length == 0) {
      // Mimic the real precompiles, which consume all forwarded gas on invalid input
      assembly {
        invalid()
      }
    }
    return response;
  }
}
