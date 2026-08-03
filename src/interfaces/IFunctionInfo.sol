// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IFunctionInfo {
    struct FunctionInfo {
        bytes4 functionSelector;
        address implementation;
    }

    /**
     * @notice Get detailed information about a specific function
     * @param functionSelector The function selector to query
     * @return info Struct containing function details
     */
    function getFunctionInfo(bytes4 functionSelector) external view returns (FunctionInfo memory info);

    /**
     * @notice Get detailed information about all registered functions
     * @return allFunctions Array of structs containing function details
     */
    function getAllFunctionInfo() external view returns (FunctionInfo[] memory allFunctions);

    /**
     * @notice Get all functions associated with a specific implementation address
     * @param implementation The implementation address to query
     * @return functionsForImpl Array of structs containing function information
     */
    function getFunctionsByImplementation(address implementation)
        external
        view
        returns (FunctionInfo[] memory functionsForImpl);

    /**
     * @notice Get the implementation address for a specific function selector
     * @param functionSelector The function selector to query
     * @return implementation The implementation address associated with the function
     */
    function getImplementationForFunction(bytes4 functionSelector) external view returns (address implementation);

    /**
     * @notice Get all unique implementation addresses used in the registry
     * @return implementations Array of all unique implementation addresses
     */
    function getAllFunctionImplementations() external view returns (address[] memory implementations);

    /**
     * @notice Get all registered function selectors
     * @return selectors Array of all registered function selectors
     */
    function getAllRegisteredFunctions() external view returns (bytes4[] memory);

    /**
     * @notice Get the count of registered functions
     * @return count The number of registered functions
     */
    function getRegisteredFunctionCount() external view returns (uint256);

    /**
     * @notice Check if a specific function selector is registered
     * @param functionSelector The function selector to check
     * @return isRegistered Whether the function selector is registered
     */
    function isFunctionRegistered(bytes4 functionSelector) external view returns (bool);
}