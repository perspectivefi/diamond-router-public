// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFunctionManager} from "src/interfaces/IFunctionManager.sol";

error NoSelectorsProvidedForImplementationForUpgrade(address _implementationAddress);
error CannotAddSelectorsToZeroAddress(bytes4[] _selectors);
error NoBytecodeAtAddress(address _contractAddress);
error IncorrectFunctionUpgradeAction(uint8 _action);
error CannotAddFunctionToProxyThatAlreadyExists(bytes4 _selector);
error CannotReplaceFunctionsFromImplementationWithZeroAddress(bytes4[] _selectors);
error CannotReplaceImmutableFunction(bytes4 _selector);
error CannotReplaceFunctionWithTheSameFunctionFromTheSameImplementation(bytes4 _selector);
error CannotReplaceFunctionThatDoesNotExists(bytes4 _selector);
error RemoveImplementationAddressMustBeZeroAddress(address _implementationAddress);
error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);
error CannotRemoveImmutableFunction(bytes4 _selector);
error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

library LibFunctionManager {
    // EIP-7201: keccak256(abi.encode(uint256(keccak256("native.functions.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant PROXY_STORAGE_POSITION = keccak256(abi.encode(uint256(keccak256("native.functions.storage")) - 1)) & ~bytes32(uint256(0xff));

    struct ImplementationAddressAndSelectorPosition {
        address implementationAddress;
        uint16 selectorPosition;
    }

    struct FunctionStorage {
        // function selector => implementation address and selector position in selectors array
        mapping(bytes4 => ImplementationAddressAndSelectorPosition) implementationAddressAndSelectorPosition;
        bytes4[] selectors;
    }

    function functionStorage() internal pure returns (FunctionStorage storage ps) {
        bytes32 position = PROXY_STORAGE_POSITION;
        assembly {
            ps.slot := position
        }
    }

    event FunctionUpgraded(IFunctionManager.FunctionUpgrade[] _functionUpgrade, address _init, bytes _calldata);

    // Internal function version of functionUpgrade
    function functionUpgrade(
        IFunctionManager.FunctionUpgrade[] memory _functionUpgrade, address _init, bytes memory _calldata)
        internal
    {
        for (uint256 ImplementationIndex; ImplementationIndex < _functionUpgrade.length; ImplementationIndex++) {
            bytes4[] memory functionSelectors = _functionUpgrade[ImplementationIndex].functionSelectors;
            address implementationAddress = _functionUpgrade[ImplementationIndex].implementationAddress;
            if (functionSelectors.length == 0) {
                revert NoSelectorsProvidedForImplementationForUpgrade(implementationAddress);
            }
            IFunctionManager.FunctionUpgradeAction action = _functionUpgrade[ImplementationIndex].action;
            if (action == IFunctionManager.FunctionUpgradeAction.Add) {
                addFunctions(implementationAddress, functionSelectors);
            } else if (action == IFunctionManager.FunctionUpgradeAction.Replace) {
                replaceFunctions(implementationAddress, functionSelectors);
            } else if (action == IFunctionManager.FunctionUpgradeAction.Remove) {
                removeFunctions(implementationAddress, functionSelectors);
            } else {
                revert IncorrectFunctionUpgradeAction(uint8(action));
            }
        }
        emit FunctionUpgraded(_functionUpgrade, _init, _calldata);
        initializeFunctionUpgrade(_init, _calldata);
    }

    function addFunctions(address _implementationAddress, bytes4[] memory _functionSelectors) internal {
        if (_implementationAddress == address(0)) {
            revert CannotAddSelectorsToZeroAddress(_functionSelectors);
        }
        FunctionStorage storage ps = functionStorage();
        uint16 selectorCount = uint16(ps.selectors.length);
        enforceHasContractCode(_implementationAddress);
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldImplementationAddress =
                ps.implementationAddressAndSelectorPosition[selector].implementationAddress;
            if (oldImplementationAddress != address(0)) {
                revert CannotAddFunctionToProxyThatAlreadyExists(selector);
            }
            ps.implementationAddressAndSelectorPosition[selector] =
                ImplementationAddressAndSelectorPosition(_implementationAddress, selectorCount);
            ps.selectors.push(selector);
            selectorCount++;
        }
    }

    function replaceFunctions(address _implementationAddress, bytes4[] memory _functionSelectors) internal {
        FunctionStorage storage ps = functionStorage();
        if (_implementationAddress == address(0)) {
            revert CannotReplaceFunctionsFromImplementationWithZeroAddress(_functionSelectors);
        }
        enforceHasContractCode(_implementationAddress);
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldImplementationAddress =
                ps.implementationAddressAndSelectorPosition[selector].implementationAddress;
            // can't replace immutable functions -- functions defined directly in the proxy in this case
            if (oldImplementationAddress == address(this)) {
                revert CannotReplaceImmutableFunction(selector);
            }
            if (oldImplementationAddress == _implementationAddress) {
                revert CannotReplaceFunctionWithTheSameFunctionFromTheSameImplementation(selector);
            }
            if (oldImplementationAddress == address(0)) {
                revert CannotReplaceFunctionThatDoesNotExists(selector);
            }
            // replace old implementation address
            ps.implementationAddressAndSelectorPosition[selector].implementationAddress = _implementationAddress;
        }
    }

    function removeFunctions(address _implementationAddress, bytes4[] memory _functionSelectors) internal {
        FunctionStorage storage ps = functionStorage();
        uint256 selectorCount = ps.selectors.length;
        if (_implementationAddress != address(0)) {
            revert RemoveImplementationAddressMustBeZeroAddress(_implementationAddress);
        }
        for (uint256 selectorIndex; selectorIndex < _functionSelectors.length; selectorIndex++) {
            bytes4 selector = _functionSelectors[selectorIndex];
            ImplementationAddressAndSelectorPosition memory oldImplementationAddressAndSelectorPosition =
                ps.implementationAddressAndSelectorPosition[selector];
            if (oldImplementationAddressAndSelectorPosition.implementationAddress == address(0)) {
                revert CannotRemoveFunctionThatDoesNotExist(selector);
            }

            // can't remove immutable functions -- functions defined directly in the proxy
            if (oldImplementationAddressAndSelectorPosition.implementationAddress == address(this)) {
                revert CannotRemoveImmutableFunction(selector);
            }
            // replace selector with last selector
            selectorCount--;
            if (oldImplementationAddressAndSelectorPosition.selectorPosition != selectorCount) {
                bytes4 lastSelector = ps.selectors[selectorCount];
                ps.selectors[oldImplementationAddressAndSelectorPosition.selectorPosition] = lastSelector;
                ps.implementationAddressAndSelectorPosition[lastSelector].selectorPosition =
                    oldImplementationAddressAndSelectorPosition.selectorPosition;
            }
            // delete last selector
            ps.selectors.pop();
            delete ps.implementationAddressAndSelectorPosition[selector];
        }
    }

    function initializeFunctionUpgrade(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            return;
        }
        enforceHasContractCode(_init);
        (bool success, bytes memory error) = _init.delegatecall(_calldata);
        if (!success) {
            if (error.length > 0) {
                // bubble up error
                /// @solidity memory-safe-assembly
                assembly {
                    let returndata_size := mload(error)
                    revert(add(32, error), returndata_size)
                }
            } else {
                revert InitializationFunctionReverted(_init, _calldata);
            }
        }
    }

    function enforceHasContractCode(address _contract) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        if (contractSize == 0) {
            revert NoBytecodeAtAddress(_contract);
        }
    }
}
