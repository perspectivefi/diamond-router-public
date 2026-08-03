// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";

// Example library to show a simple example of diamond storage
library TestLib {
    bytes32 constant MODULES_STORAGE_POSITION = keccak256("diamond.standard.test.storage");

    struct TestState {
        address myAddress;
        uint256 myNum;
    }

    function diamondStorage() internal pure returns (TestState storage ds) {
        bytes32 position = MODULES_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function setMyAddress(address _myAddress) internal {
        TestState storage testState = diamondStorage();
        testState.myAddress = _myAddress;
    }

    function getMyAddress() internal view returns (address) {
        TestState storage testState = diamondStorage();
        return testState.myAddress;
    }
}

contract Mock1Module {
    event TestEvent(address something);

    function mock1Func1() external {
        TestLib.setMyAddress(address(this));
    }

    function mock1Func2() external view returns (address) {
        return TestLib.getMyAddress();
    }

    function supportsInterface(bytes4 _interfaceID) external view returns (bool) {}
}

// Mock implementations for testing
contract Mock2Module {
    function mockFunction1() external pure returns (uint256) {
        return 1;
    }

    function mockFunction2() external pure returns (string memory) {
        return "test";
    }
}

contract Mock3Module {
    function mockFunction3(uint256 a) external pure returns (uint256) {
        return a * 2;
    }
}

contract Mock4Module {
    function mockFunction1() external pure returns (uint256) {
        return 21 * 2;        
    }
}