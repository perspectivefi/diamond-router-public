// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICommandManager, ICommand} from "src/interfaces/ICommandManager.sol";

// Remember to add the loupe functions from DiamondLoupeFacet to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

error EmptyCommandList();
error MissmatchLength();
error NoSelectorsProvidedForFacetForCut(address _facetAddress);
error CannotAddSelectorsToZeroAddress(bytes4[] _selectors);
error NoBytecodeAtAddress(address _contractAddress);
error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);
error CannotReplaceFunctionsFromFacetWithZeroAddress(bytes4[] _selectors);
error CannotReplaceImmutableFunction(bytes4 _selector);
error CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(bytes4 _selector);
error CannotReplaceFunctionThatDoesNotExists(bytes4 _selector);
error RemoveFacetAddressMustBeZeroAddress(address _facetAddress);
error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);
error CannotRemoveImmutableFunction(bytes4 _selector);
error IncorrectManagementAction(uint8 _action);
error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);
error CommandAlreadyRegistered(bytes1 commandId);

library LibModuleManager {
    // EIP-7201: keccak256(abi.encode(uint256(keccak256("native.modules.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant MODULES_STORAGE_POSITION = keccak256(abi.encode(uint256(keccak256("native.modules.storage")) - 1)) & ~bytes32(uint256(0xff));

    struct ImplementationAndFunction {
        address implementation;
        bytes4 functionSelector;
    }

    struct ModulesManagerStorage {
        // function selector => facet address and selector position in selectors array
        mapping(bytes1 => ImplementationAndFunction) implementationAndFunction;
        bytes1[] commands;
    }

    // Events
    event CommandModifications(
        ICommand.CommandModification[] _commandModifications, address _init, bytes _calldata
    );

    function modulesManagerStorage() internal pure returns (ModulesManagerStorage storage mms) {
        bytes32 position = MODULES_STORAGE_POSITION;
        assembly {
            mms.slot := position
        }
    }

    function manageCommands(
        ICommand.CommandModification[] memory _commandModifications,
        address _init,
        bytes memory _calldata
    ) internal {
        for (
            uint256 implementationIndex;
            implementationIndex < _commandModifications.length;
            implementationIndex++
        ) {
            bytes memory commands = _commandModifications[implementationIndex].commands;
            bytes4[] memory selectors = _commandModifications[implementationIndex].functionSelectors;
            address implementation = _commandModifications[implementationIndex].implementation;
            if (commands.length != selectors.length) {
                revert MissmatchLength();
            }
            if (commands.length == 0) {
                revert EmptyCommandList();
            }
            ICommand.ImplementationAction action = _commandModifications[implementationIndex].action;
            if (action == ICommand.ImplementationAction.Add) {
                addFunctions(implementation, commands, selectors);
            } else if (action == ICommand.ImplementationAction.Replace) {
                replaceFunctions(implementation, commands, selectors);
            } else if (action == ICommand.ImplementationAction.Remove) {
                removeFunctions(implementation, commands, selectors);
            } else {
                revert IncorrectManagementAction(uint8(action));
            }
        }
        emit CommandModifications(_commandModifications, _init, _calldata);
        initializeImplementation(_init, _calldata);
    }

    function addFunctions(address _implementationAddress, bytes memory _commands, bytes4[] memory _functionSelectors)
        internal
    {
        if (_implementationAddress == address(0)) {
            revert CannotAddSelectorsToZeroAddress(_functionSelectors);
        }
        ModulesManagerStorage storage mms = modulesManagerStorage();
        enforceHasContractCode(_implementationAddress);
        for (uint256 commandIndex; commandIndex < _commands.length; commandIndex++) {
            bytes1 command = _commands[commandIndex];
            bytes4 selector = _functionSelectors[commandIndex];
            // Check if command is already registered by searching for implementation
            address oldImplementationAddress = mms.implementationAndFunction[command].implementation;
            if (oldImplementationAddress != address(0)) {
                revert CommandAlreadyRegistered(command);
            }

            // Add to commands array for enumeration
            mms.commands.push(command);
            mms.implementationAndFunction[command] = ImplementationAndFunction(_implementationAddress, selector);
        }
    }

    //this function replace the current address & selector associated to a command
    function replaceFunctions(
        address _implementationAddress,
        bytes memory _commands,
        bytes4[] memory _functionSelectors
    ) internal {
        ModulesManagerStorage storage mms = modulesManagerStorage();
        if (_implementationAddress == address(0)) {
            revert CannotReplaceFunctionsFromFacetWithZeroAddress(_functionSelectors);
        }
        enforceHasContractCode(_implementationAddress);
        for (uint256 commandIndex; commandIndex < _commands.length; commandIndex++) {
            bytes1 command = _commands[commandIndex];
            bytes4 selector = _functionSelectors[commandIndex];
            address oldImplementationAddress = mms.implementationAndFunction[command].implementation;
            if (oldImplementationAddress == _implementationAddress) {
                revert CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(selector);
            }
            if (oldImplementationAddress == address(0)) {
                revert CannotReplaceFunctionThatDoesNotExists(selector);
            }
            // replace old facet address
            mms.implementationAndFunction[command].implementation = _implementationAddress;
            mms.implementationAndFunction[command].functionSelector = selector;
        }
    }

    /// notice: this function keeps the storage of the implementation of the removed function
    function removeFunctions(address _facetAddress, bytes memory commands, bytes4[] memory _functionSelectors)
        internal
    {
        ModulesManagerStorage storage mms = modulesManagerStorage();
        if (_facetAddress != address(0)) {
            revert RemoveFacetAddressMustBeZeroAddress(_facetAddress);
        }
        for (uint256 commandIndex; commandIndex < commands.length; commandIndex++) {
            bytes1 command = commands[commandIndex];
            bytes4 selector = _functionSelectors[commandIndex];

            ImplementationAndFunction memory implementationAndFunction = mms.implementationAndFunction[command];
            if (implementationAndFunction.implementation == address(0)) {
                revert CannotRemoveFunctionThatDoesNotExist(selector);
            }

            // can't remove immutable functions -- functions defined directly in the diamond
            if (implementationAndFunction.implementation == address(this)) {
                revert CannotRemoveImmutableFunction(selector);
            }

            // Remove command from commands array
            for (uint256 i = 0; i < mms.commands.length; i++) {
                if (mms.commands[i] == command) {
                    // Replace with the last element and pop
                    mms.commands[i] = mms.commands[mms.commands.length - 1];
                    mms.commands.pop();
                    break;
                }
            }

            // delete last selector
            delete mms.implementationAndFunction[command];
        }
    }

    function initializeImplementation(address _init, bytes memory _calldata) internal {
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
