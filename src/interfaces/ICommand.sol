// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

interface ICommand {
        enum ImplementationAction {
        Add,
        Replace,
        Remove
    }
    // Add=0, Replace=1, Remove=2

    struct CommandModification {
        address implementation; // implementation address
        ImplementationAction action; // action to realize
        bytes commands; // command IDs to associate with function selectors
        bytes4[] functionSelectors; // one command is associated to one function selector
    }

    event CommandModifications(
        CommandModification[] _commandModifications, address _init, bytes _calldata
    );

}