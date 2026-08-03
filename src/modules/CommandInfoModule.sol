// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {LibModuleManager} from "../modules/libraries/LibModuleManager.sol";
import {ICommandInfo} from "../interfaces/ICommandInfo.sol";
import {IERC165} from "../interfaces/IERC165.sol";

// This is a helper implementation for the router to get information about the commands available
/// SHOULD NOT BE USED ON-CHAIN
contract CommandInfoModule is ICommandInfo {
    // , IERC165
    // Custom errors
    error CommandAlreadyRegistered(bytes1 commandId);
    error CommandNotRegistered(bytes1 commandId);
    error CountMustBeGreaterThanZero();
    error NotEnoughAvailableCommandIds(uint256 requested, uint256 available);
    error NoAvailableCommandIds();
    error NoCommandForFunctionAndImplementation();
    error InvalidInput();

    /**
     * @notice Get detailed information about a specific command
     * @param commandId The command identifier to query
     * @return info Struct containing command details
     */
    function getCommandInfo(bytes1 commandId) external view returns (CommandInfo memory info) {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
        if (ds.implementationAndFunction[commandId].implementation == address(0)) {
            revert CommandNotRegistered(commandId);
        }

        return CommandInfo({
            commandId: commandId,
            implementation: ds.implementationAndFunction[commandId].implementation,
            functionSelector: ds.implementationAndFunction[commandId].functionSelector
        });
    }

    /**
     * @notice Get detailed information about all registered commands
     * @return allCommands Array of structs containing command details
     */
    function getAllCommandInfo() external view returns (CommandInfo[] memory allCommands) {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
        uint256 length = ds.commands.length;
        allCommands = new CommandInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            bytes1 commandId = ds.commands[i];
            allCommands[i] = CommandInfo({
                commandId: commandId,
                implementation: ds.implementationAndFunction[commandId].implementation,
                functionSelector: ds.implementationAndFunction[commandId].functionSelector
            });
        }

        return allCommands;
    }

    /**
     * @notice Get all commands associated with a specific implementation address
     * @param implementation The implementation address to query
     * @return commandsForImpl Array of structs containing command and selector information
     */
    function getCommandsByImplementation(address implementation)
        external
        view
        returns (CommandInfo[] memory commandsForImpl)
    {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
        // First count how many commands are associated with this implementation
        uint256 count = 0;
        for (uint256 i = 0; i < ds.commands.length; i++) {
            if (ds.implementationAndFunction[ds.commands[i]].implementation == implementation) {
                count++;
            }
        }

        // Now create and populate the array
        commandsForImpl = new CommandInfo[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < ds.commands.length; i++) {
            bytes1 commandId = ds.commands[i];
            if (ds.implementationAndFunction[commandId].implementation == implementation) {
                commandsForImpl[index] = CommandInfo({
                    commandId: commandId,
                    implementation: implementation,
                    functionSelector: ds.implementationAndFunction[commandId].functionSelector
                });
                index++;
            }
        }

        return commandsForImpl;
    }

    /**
     * @notice Get the command associated with an implementation address and function selector
     * @param implementation The implementation address
     * @param functionSelector The function selector to query
     * @return commandId The command identifier associated with the implementation and selector
     */
    function getCommandByImplementationAndSelector(address implementation, bytes4 functionSelector)
        external
        view
        returns (bytes1 commandId)
    {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
        for (uint256 i = 0; i < ds.commands.length; i++) {
            bytes1 cmd = ds.commands[i];
            if (
                ds.implementationAndFunction[cmd].implementation == implementation
                    && ds.implementationAndFunction[cmd].functionSelector == functionSelector
            ) {
                return cmd;
            }
        }
        revert NoCommandForFunctionAndImplementation();
    }

    /**
     * @notice Get all unique implementation addresses used in the registry
     * @return implementations Array of all unique implementation addresses
     */
    function getAllCommandImplementations() external view returns (address[] memory implementations) {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();

        // Array to track unique implementation addresses
        address[] memory uniqueAddresses = new address[](ds.commands.length);
        uint256 uniqueCount = 0;

        // Loop through all commands to find unique implementation addresses
        for (uint256 i = 0; i < ds.commands.length; i++) {
            address impl = ds.implementationAndFunction[ds.commands[i]].implementation;
            if (impl != address(0)) {
                bool isUnique = true;
                // Check if the implementation address is already in the uniqueAddresses array
                for (uint256 j = 0; j < uniqueCount; j++) {
                    if (uniqueAddresses[j] == impl) {
                        isUnique = false;
                        break;
                    }
                }
                // If the implementation address is unique, add it to the array
                if (isUnique) {
                    uniqueAddresses[uniqueCount] = impl;
                    uniqueCount++;
                }
            }
        }

        // Create the final array of unique implementation addresses
        implementations = new address[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            implementations[i] = uniqueAddresses[i];
        }

        return implementations;
    }

    /**
     * @notice Find the next available command identifiers
     * @param count The number of available command IDs to find
     * @return availableIds Array of available command identifiers
     */
    function findAvailableCommandIds(uint256 count) external view returns (bytes1[] memory availableIds) {
        if (count == 0) {
            revert CountMustBeGreaterThanZero();
        }

        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();

        availableIds = new bytes1[](count);
        uint256 found = 0;
        uint8 current = 0;

        while (found < count && current < 256) {
            bytes1 potentialId = bytes1(uint8(current));
            if (ds.implementationAndFunction[potentialId].implementation == address(0)) {
                availableIds[found] = potentialId;
                found++;
            }
            current++;
        }

        if (found != count) {
            revert NotEnoughAvailableCommandIds(count, found);
        }
        return availableIds;
    }

    /**
     * @notice Find the smallest available command identifier
     * @return smallestId The smallest available command ID
     */
    function getSmallestAvailableCommandId() external view returns (bytes1 smallestId) {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
        for (uint16 i = 0; i < 256; i++) {
            bytes1 potentialId = bytes1(uint8(i));
            if (ds.implementationAndFunction[potentialId].implementation == address(0)) {
                return potentialId;
            }
        }
        revert NoAvailableCommandIds();
    }

    /**
     * @notice Get all registered commands
     * @return commands Array of all registered command identifiers
     */
    function getAllRegisteredCommands() external view returns (bytes1[] memory) {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
        return ds.commands;
    }

    /**
     * @notice Get the count of registered commands
     * @return count The number of registered commands
     */
    function getRegisteredCommandCount() external view returns (uint256) {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
        return ds.commands.length;
    }

    /**
     * @notice Check if a specific command ID is registered
     * @param commandId The command identifier to check
     * @return isRegistered Whether the command ID is registered
     */
    function isCommandIdRegistered(bytes1 commandId) external view returns (bool) {
        LibModuleManager.ModulesManagerStorage storage ds = LibModuleManager.modulesManagerStorage();
        return ds.implementationAndFunction[commandId].implementation != address(0);
    }
}
