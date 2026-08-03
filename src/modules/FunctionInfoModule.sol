// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {LibFunctionManager} from "../modules/libraries/LibFunctionManager.sol";
import {IFunctionInfo} from "../interfaces/IFunctionInfo.sol";
import {IERC165} from "../interfaces/IERC165.sol";

// This is a helper implementation for the FunctionManagerModule to get information about functions
/// SHOULD NOT BE USED ON-CHAIN
contract FunctionInfoModule is IFunctionInfo {
    // Custom errors
    error FunctionNotRegistered(bytes4 functionSelector);
    error NoImplementationForFunction(bytes4 functionSelector);
    error InvalidInput();

    /**
     * @notice Get detailed information about a specific function
     * @param functionSelector The function selector to query
     * @return info Struct containing function details
     */
    function getFunctionInfo(bytes4 functionSelector) external view returns (FunctionInfo memory info) {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();
        address implementation = fs.implementationAddressAndSelectorPosition[functionSelector].implementationAddress;

        if (implementation == address(0)) {
            revert FunctionNotRegistered(functionSelector);
        }

        return FunctionInfo({functionSelector: functionSelector, implementation: implementation});
    }

    /**
     * @notice Get detailed information about all registered functions
     * @return allFunctions Array of structs containing function details
     */
    function getAllFunctionInfo() external view returns (FunctionInfo[] memory allFunctions) {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();
        uint256 length = fs.selectors.length;
        allFunctions = new FunctionInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            bytes4 functionSelector = fs.selectors[i];
            allFunctions[i] = FunctionInfo({
                functionSelector: functionSelector,
                implementation: fs.implementationAddressAndSelectorPosition[functionSelector].implementationAddress
            });
        }

        return allFunctions;
    }

    /**
     * @notice Get all functions associated with a specific implementation address
     * @param implementation The implementation address to query
     * @return functionsForImpl Array of structs containing function information
     */
    function getFunctionsByImplementation(address implementation)
        external
        view
        returns (FunctionInfo[] memory functionsForImpl)
    {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();
        // First count how many functions are associated with this implementation
        uint256 count = 0;
        for (uint256 i = 0; i < fs.selectors.length; i++) {
            if (fs.implementationAddressAndSelectorPosition[fs.selectors[i]].implementationAddress == implementation) {
                count++;
            }
        }

        // Now create and populate the array
        functionsForImpl = new FunctionInfo[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < fs.selectors.length; i++) {
            bytes4 functionSelector = fs.selectors[i];
            if (fs.implementationAddressAndSelectorPosition[functionSelector].implementationAddress == implementation) {
                functionsForImpl[index] =
                    FunctionInfo({functionSelector: functionSelector, implementation: implementation});
                index++;
            }
        }

        return functionsForImpl;
    }

    /**
     * @notice Get the implementation address for a specific function selector
     * @param functionSelector The function selector to query
     * @return implementation The implementation address associated with the function
     */
    function getImplementationForFunction(bytes4 functionSelector) external view returns (address implementation) {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();
        implementation = fs.implementationAddressAndSelectorPosition[functionSelector].implementationAddress;

        if (implementation == address(0)) {
            revert NoImplementationForFunction(functionSelector);
        }

        return implementation;
    }

    /**
     * @notice Get all unique implementation addresses used in the registry
     * @return implementations Array of all unique implementation addresses
     */
    function getAllFunctionImplementations() external view returns (address[] memory implementations) {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();

        // Array to track unique implementation addresses
        address[] memory uniqueAddresses = new address[](fs.selectors.length);
        uint256 uniqueCount = 0;

        // Loop through all functions to find unique implementation addresses
        for (uint256 i = 0; i < fs.selectors.length; i++) {
            address impl = fs.implementationAddressAndSelectorPosition[fs.selectors[i]].implementationAddress;
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
     * @notice Get all registered function selectors
     * @return selectors Array of all registered function selectors
     */
    function getAllRegisteredFunctions() external view returns (bytes4[] memory) {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();
        return fs.selectors;
    }

    /**
     * @notice Get the count of registered functions
     * @return count The number of registered functions
     */
    function getRegisteredFunctionCount() external view returns (uint256) {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();
        return fs.selectors.length;
    }

    /**
     * @notice Check if a specific function selector is registered
     * @param functionSelector The function selector to check
     * @return isRegistered Whether the function selector is registered
     */
    function isFunctionRegistered(bytes4 functionSelector) external view returns (bool) {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();
        return fs.implementationAddressAndSelectorPosition[functionSelector].implementationAddress != address(0);
    }
}