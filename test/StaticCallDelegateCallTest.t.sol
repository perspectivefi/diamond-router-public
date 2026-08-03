// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// Contract C with the view function
contract ContractC {
    uint256 public storedValue = 0;

    function viewFunction() public view returns (uint256) {
        // Simple view function returning the stored value
        return storedValue;
    }
}

// Contract B with the delegatecall
contract ContractB {
    uint256 public storedValue = 15;

    function intermediaryFunction(address contractC) public returns (uint256) {
        // Create calldata for the view function (no parameters needed)
        bytes memory callData = abi.encodeWithSignature("viewFunction()");

        // Perform delegatecall
        (bool success, bytes memory result) = contractC.delegatecall(callData);
        require(success, "Delegatecall failed");

        // Decode the result
        return abi.decode(result, (uint256));
    }

    // Function that attempts to modify state - should fail when called via staticcall
    function modifyState(uint256 value) public returns (uint256) {
        storedValue = value;
        return storedValue;
    }
}

// Contract A with the staticcall
contract ContractA {
    function safeCall(address contractB, address contractC) public view returns (uint256) {
        // Create calldata for the intermediary function
        bytes memory callData = abi.encodeWithSignature("intermediaryFunction(address)", contractC);

        // Perform staticcall
        (bool success, bytes memory result) = contractB.staticcall(callData);
        require(success, "Static call failed");

        // Decode the result
        return abi.decode(result, (uint256));
    }

    // Function to test staticcall to a state-modifying function - should revert
    function attemptStateModification(address contractB, uint256 value) public view returns (uint256) {
        bytes memory callData = abi.encodeWithSignature("modifyState(uint256)", value);

        (bool success, bytes memory result) = contractB.staticcall(callData);
        require(success, "Static call failed"); // This should fail when called

        return abi.decode(result, (uint256));
    }
}

contract StaticCallDelegateCallTest is Test {
    ContractA contractA;
    ContractB contractB;
    ContractC contractC;

    function setUp() public {
        contractC = new ContractC();
        contractB = new ContractB();
        contractA = new ContractA();
    }

    function testDelegateCallUsesCallerStorage() public {
        // Verify initial storage values
        assertEq(contractB.storedValue(), 15, "ContractB should start with storedValue = 15");
        assertEq(contractC.storedValue(), 0, "ContractC should start with storedValue = 0");

        // Call intermediaryFunction which uses delegatecall to execute ContractC's viewFunction
        uint256 result = contractB.intermediaryFunction(address(contractC));

        // The result should be 15 (from ContractB's storage) not 0 (from ContractC's storage)
        assertEq(result, 15, "Delegatecall should use ContractB's storage context");
    }

    function testStaticCallToDelegateCallPreservesContext() public view {
        // When contractA makes a staticcall to contractB's intermediaryFunction,
        // which makes a delegatecall to contractC's viewFunction,
        // the value returned should be from contractB's storage
        uint256 result = contractA.safeCall(address(contractB), address(contractC));

        // The result should be 15 (from ContractB's storage)
        assertEq(result, 15, "StaticCall to DelegateCall should return ContractB's storage value");
    }

    function testModifyContractBStorageValue() public {
        // Change ContractB's stored value
        contractB.modifyState(42);

        // Verify the value changed
        assertEq(contractB.storedValue(), 42, "ContractB's storedValue should be updated to 42");

        // Now when we call the delegatecall, it should return the new value
        uint256 result = contractB.intermediaryFunction(address(contractC));
        assertEq(result, 42, "Delegatecall should return ContractB's updated storage value");
    }

    function testStaticCallEnforcesReadOnly() public {
        uint256 inputValue = 10;

        // This should revert because modifyState attempts to change state
        vm.expectRevert();
        contractA.attemptStateModification(address(contractB), inputValue);

        // Verify contractB's state wasn't modified
        assertEq(contractB.storedValue(), 15, "State should not be modified");
    }
}
