// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {SafeERC20, IERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {LibExecutionModule} from "src/modules/libraries/LibExecutionModule.sol";
import {Constants} from "./Constants.sol";

/**
 * @title TransferModule
 * @notice Contract for executing various token transfer operations
 * @dev Provides functionality for ERC20 token transfers and native token transfers
 */
contract TransferModule {
    using SafeERC20 for IERC20;
    error PermitFailed();
    error NativeTransferFailed();

    function transferFrom(address token, uint256 value) external {
        IERC20(token).safeTransferFrom(LibExecutionModule.executionStorage().msgSender, address(this), value);
    }
    function transferFromWithPermit(address token, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        try IERC20Permit(token).permit(
            msg.sender, address(this), value, deadline, v, r, s
        ) {
            // Permit executed successfully, proceed
        } catch {
            // Check allowance to see if permit was already executed
            uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
            if (allowance < value) {
                revert PermitFailed();
            }
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), value);
    }
    
    function transfer(address token, address recipient, uint256 value) public payable {
        if (value != 0) {
            IERC20(token).safeTransfer(recipient, value);
        }
    }
    
    function transferNative(address recipient, uint256 amount) external payable {
        (bool success, ) = payable(recipient).call{value: amount}("");
        if(!success) {
            revert NativeTransferFailed();
        }
    }
}