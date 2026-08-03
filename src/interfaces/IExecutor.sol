// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

// https://github.com/Uniswap/universal-router/blob/main/contracts/interfaces/IUniversalRouter.sol

interface IExecutor {
    /// @notice Thrown when executing commands with an expired deadline
    error TransactionDeadlinePassed();

    /// @notice Thrown when attempting to execute commands and an incorrect number of inputs are provided
    error LengthMismatch();

    /// @notice Thrown when onFlashloan() is called directly, rather than through a command execution
    error DirectOnFlashloanCall();

    /// @notice Thrown when onFlashloan() is called by an address other than flashloan lender
    error UnauthorizedOnFlashloanCaller();

    /// @notice Thrown when an address other than msgSender and Router reenters execute()
    error UnauthorizedReentrantCall();

    /// @notice Thrown when the command isn't associated to a valid function
    error CommandNotFound(bytes1 command);

    /**
     * @dev Executes encoded commands along with provided inputs
     * Reverts if deadline has expired
     * @param _commands A set of concatenated commands, each 1 byte in length
     * @param _inputs An array of byte strings containing ABI-encoded inputs for each command
     * @param _deadline The deadline by which the transaction must be executed
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs, uint256 _deadline) external payable;

    /**
     * @dev Executes encoded commands along with provided inputs
     * @param _commands A set of concatenated commands, each 1 byte in length
     * @param _inputs An array of byte strings containing ABI-encoded inputs for each command
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs) external payable;

    /**
     * @dev Executes encoded commands along with provided inputs and returns the output
     * Reverts if deadline has expired
     * @param _commands A set of concatenated commands, each 1 byte in length
     * @param _inputs An array of byte strings containing ABI-encoded inputs for each command
     * @param _deadline The deadline by which the transaction must be executed
     * @param returnOutput Whether to return the output data
     * @return returnData The output data from the executed commands
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs, uint256 _deadline, bool returnOutput)
        external
        payable
        returns (bytes[] memory returnData);

    /**
     * @dev Executes encoded commands along with provided inputs and returns the output
     * @param _commands A set of concatenated commands, each 1 byte in length
     * @param _inputs An array of byte strings containing ABI-encoded inputs for each command
     * @param returnOutput Whether to return the output data
     * @return returnData The output data from the executed commands
     */
    function execute(bytes calldata _commands, bytes[] calldata _inputs, bool returnOutput)
        external
        payable
        returns (bytes[] memory returnData);
}
