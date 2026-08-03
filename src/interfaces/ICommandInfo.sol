// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {LibModuleManager} from "../modules/libraries/LibModuleManager.sol";

interface ICommandInfo {
    /**
     * @notice Struct for command information
     */
    struct CommandInfo {
        bytes1 commandId;
        address implementation;
        bytes4 functionSelector;
    }

    /**
     * @notice Get detailed information about a specific command
     * @param commandId The command identifier to query
     * @return info Struct containing command details
     */
    function getCommandInfo(bytes1 commandId) external view returns (CommandInfo memory info);

    /**
     * @notice Get detailed information about all registered commands
     * @return allCommands Array of structs containing command details
     */
    function getAllCommandInfo() external view returns (CommandInfo[] memory allCommands);

    /**
     * @notice Get all commands associated with a specific implementation address
     * @param implementation The implementation address to query
     * @return commandsForImpl Array of structs containing command and selector information
     */
    function getCommandsByImplementation(address implementation)
        external
        view
        returns (CommandInfo[] memory commandsForImpl);

    /**
     * @notice Get the command associated with an implementation address and function selector
     * @param implementation The implementation address
     * @param functionSelector The function selector to query
     * @return commandId The command identifier associated with the implementation and selector
     */
    function getCommandByImplementationAndSelector(address implementation, bytes4 functionSelector)
        external
        view
        returns (bytes1 commandId);

    /**
     * @notice Get all unique implementation addresses used in the registry
     * @return implementations Array of all unique implementation addresses
     */
    function getAllCommandImplementations() external view returns (address[] memory implementations);

    /**
     * @notice Find the next available command identifiers
     * @param count The number of available command IDs to find
     * @return availableIds Array of available command identifiers
     */
    function findAvailableCommandIds(uint256 count) external view returns (bytes1[] memory availableIds);

    /**
     * @notice Find the smallest available command identifier
     * @return smallestId The smallest available command ID
     */
    function getSmallestAvailableCommandId() external view returns (bytes1 smallestId);

    /**
     * @notice Get all registered commands
     * @return commands Array of all registered command identifiers
     */
    function getAllRegisteredCommands() external view returns (bytes1[] memory);

    /**
     * @notice Get the count of registered commands
     * @return count The number of registered commands
     */
    function getRegisteredCommandCount() external view returns (uint256);

    /**
     * @notice Check if a specific command ID is registered
     * @param commandId The command identifier to check
     * @return isRegistered Whether the command ID is registered
     */
    function isCommandIdRegistered(bytes1 commandId) external view returns (bool);
}
