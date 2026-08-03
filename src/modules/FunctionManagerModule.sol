// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {LibFunctionManager} from "src/modules/libraries/LibFunctionManager.sol";
import {IFunctionManager} from "src/interfaces/IFunctionManager.sol";
import {AccessManagedUpgradeable} from "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

contract FunctionManagerModule is IFunctionManager, AccessManagedUpgradeable {
    /// @notice Add, replace, or remove any number of functions and optionally execute a function with delegatecall
    /// @dev This function allows for the management of function implementations in a proxy contract.
    ///      It supports adding, replacing, or removing functions and can optionally execute a function
    ///      with a delegatecall to an initialization contract.
    /// @param _functionUpgrade An array of implementation upgrades, each containing an implementation address,
    ///                      an action (add, replace, or remove), and a function selector.
    /// @param _init The address of the contract to which the delegatecall will be made.
    /// @param _calldata The encoded function call to be executed with delegatecall on the initialization contract.
    function manageFunctions(
        IFunctionManager.FunctionUpgrade[] memory _functionUpgrade,
        address _init,
        bytes memory _calldata
    ) external restricted {
        LibFunctionManager.functionUpgrade(_functionUpgrade, _init, _calldata);
    }
}
