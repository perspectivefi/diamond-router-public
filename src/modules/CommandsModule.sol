// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IExecutor} from "src/interfaces/IExecutor.sol";
import {LibModuleManager} from "src/modules/libraries/LibModuleManager.sol";
import {LibExecutionModule} from "src/modules/libraries/LibExecutionModule.sol";
import {ICommandManager, ICommand} from "src/interfaces/ICommandManager.sol";
import {LibModuleManager} from "src/modules/libraries/LibModuleManager.sol";
import {AccessManagedUpgradeable} from "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

contract CommandsModule is IExecutor, ICommandManager, AccessManagedUpgradeable {

    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _commandModifications Array of implementation addresses, actions, commands,
    ///                                     and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call executed with delegatecall on _init
    function manageCommands(
        ICommand.CommandModification[] memory _commandModifications,
        address _init,
        bytes memory _calldata
    ) external override restricted {
        LibModuleManager.manageCommands(_commandModifications, _init, _calldata);
    }

    /* Modifiers
     *********************************************************************************************************/
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert TransactionDeadlinePassed();
        _;
    }

    /**
     * @inheritdoc IExecutor
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs, uint256 _deadline)
        external
        payable
        override
        checkDeadline(_deadline)
    {
        execute(_commands, _inputs, false);
    }

    /**
     * @inheritdoc IExecutor
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs, uint256 _deadline, bool returnOutput)
        external
        payable
        checkDeadline(_deadline)
        returns (bytes[] memory returnData)
    {
        return execute(_commands, _inputs, returnOutput);
    }

    /**
     * @inheritdoc IExecutor
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs) public payable override {
        execute(_commands, _inputs, false);
    }

    /**
     * @inheritdoc IExecutor
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs, bool returnOutput)
        public
        payable
        returns (bytes[] memory returnData)
    {
        // EXECUTION STORAGE
        LibExecutionModule.ExecutionStorage storage es = LibExecutionModule.executionStorage();

        // Relying on msg.sender is problematic as it changes during a flash loan.
        // Thus, it's necessary to track who initiated the original Router execution.
        bool topLevel;
        if (es.msgSender == address(0)) {
            es.msgSender = msg.sender;
            topLevel = true;
            es.msgValue = msg.value;
        } else if (msg.sender != address(this)) {
            revert UnauthorizedReentrantCall();
        }

        returnData = _execute(_commands, _inputs, returnOutput);

        if (topLevel) {
            // top-level reset
            es.msgSender = address(0);
            es.msgValue = 0;
        }

        return returnData;
    }

    /**
     * @dev Internal function to execute commands with their inputs
     * @param _commands The commands to execute
     * @param _inputs The inputs for each command
     * @param returnOutput Whether to return output data
     * @return returnData The output data if returnOutput is true
     */
    function _execute(bytes memory _commands, bytes[] memory _inputs, bool returnOutput)
        internal
        returns (bytes[] memory returnData)
    {
        uint256 numCommands = _commands.length;
        if (_inputs.length != numCommands) {
            revert LengthMismatch();
        }

        if (returnOutput) {
            returnData = new bytes[](numCommands);
        }

        // loop through all given commands, execute them and pass along outputs as defined
        for (uint256 commandIndex; commandIndex < numCommands;) {
            bytes1 command = _commands[commandIndex];
            bytes memory input = _inputs[commandIndex];

            LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
            // get implementation & function from the command
            address implementationAddress = ds.implementationAndFunction[command].implementation;
            bytes4 functionSelector = ds.implementationAndFunction[command].functionSelector;
            if (implementationAddress == address(0)) {
                revert CommandNotFound(command);
            }

            // Prepare calldata with function selector and input data
            bytes memory callData = abi.encodePacked(functionSelector, input);
            bool success;
            bytes memory result;

            // Execute external function from implementation using delegatecall
            assembly {
                // Calculate calldata memory pointer and length
                let ptr := add(callData, 32)
                let len := mload(callData)

                // Execute delegatecall
                success := delegatecall(gas(), implementationAddress, ptr, len, 0, 0)

                // Handle return data
                let returnDataSize := returndatasize()

                // Allocate memory for the result
                result := mload(0x40) // Get free memory pointer
                mstore(0x40, add(result, add(returnDataSize, 32))) // Update free memory pointer
                mstore(result, returnDataSize) // Store length

                // Copy return data
                returndatacopy(add(result, 32), 0, returnDataSize)
            }

            if (!success) {
                // Forward the revert message
                assembly {
                    let returnDataSize := mload(result)
                    revert(add(result, 32), returnDataSize)
                }
            }

            if (returnOutput) {
                // Store the return data from this command
                returnData[commandIndex] = result;
            }

            unchecked {
                commandIndex++;
            }
        }

        return returnData;
    }
}
