// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessManagedUpgradeable} from "openzeppelin-contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {IFunctionManager} from "src/interfaces/IFunctionManager.sol";
import {LibFunctionManager} from "src/modules/libraries/LibFunctionManager.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

contract DiamondRouter is Initializable, PausableUpgradeable, AccessManagedUpgradeable {
    constructor(
    )  {
        _disableInitializers();
    }

    function initialize(
        address initialAuthority,
        IFunctionManager.FunctionUpgrade[] memory _functionUpgrades,
        address _init, 
        bytes memory _calldata) 
        external initializer {
        __AccessManaged_init(initialAuthority);
        __Pausable_init();
        // Using LibFunctionManager to manage functions directly during construction
        LibFunctionManager.functionUpgrade(_functionUpgrades, _init, _calldata);
    }

    // Errors
    error FunctionNotFound(bytes4 functionSignature);

    /* Setters
     *********************************************************************************************************/

    function pause() public restricted {
        _pause();
    }

    function unPause() public restricted {
        _unpause();
    }

    /* Execution
     *********************************************************************************************************/

    // Find implementationAddress for function that is called and execute the
    // function if a implementationAddress is found and return any value.
    fallback() external payable whenNotPaused {
        LibFunctionManager.FunctionStorage storage fs = LibFunctionManager.functionStorage();
        // get implementationAddress from function selector
        address implementationAddress = fs.implementationAddressAndSelectorPosition[msg.sig].implementationAddress;
        if (implementationAddress == address(0)) {
            revert FunctionNotFound(msg.sig);
        }
        // Execute external function from implementationAddress using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the implementationAddress
            let result := delegatecall(gas(), implementationAddress, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}
