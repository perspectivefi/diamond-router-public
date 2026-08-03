// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ICommand} from "./ICommand.sol";
interface ICommandManager {

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
    ) external;
}
