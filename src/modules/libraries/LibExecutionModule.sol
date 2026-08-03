// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

library LibExecutionModule {
    // EIP-7201: keccak256(abi.encode(uint256(keccak256("native.execution.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant EXECUTION_STORAGE_POSITION = keccak256(abi.encode(uint256(keccak256("native.execution.storage")) - 1)) & ~bytes32(uint256(0xff));

    struct ExecutionStorage {
        address msgSender;
        uint256 msgValue;
    }

    function executionStorage() internal pure returns (ExecutionStorage storage es) {
        bytes32 position = EXECUTION_STORAGE_POSITION;
        assembly {
            es.slot := position
        }
    }

    function getMsgSender() internal view returns(address) {
        return executionStorage().msgSender;
    }

    function getMsgValue() internal view returns(uint256) {
        return executionStorage().msgValue;
    }
}
