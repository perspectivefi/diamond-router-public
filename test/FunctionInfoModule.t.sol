// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/interfaces/IFunctionInfo.sol";
import {ICommandManager} from "src/interfaces/ICommandManager.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";
import {AccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {DiamondRouter} from "src/DiamondRouter.sol";
import {IFunctionManager} from "src/interfaces/IFunctionManager.sol";
import {FunctionInfoModule} from "src/modules/FunctionInfoModule.sol";
import {LibFunctionManager} from "src/modules/libraries/LibFunctionManager.sol";
import {DeployDiamondRouter} from "script/00_deployDiamondRouter.s.sol";
import {Mock1Module, Mock2Module, Mock3Module} from "test/modules/MockModules.sol";


contract FunctionInfoTest is Test {
    address router;
    AccessManager accessManager;

    // Mock implementation for testing
    address mockImpl1;
    address mockImpl2;

    // Function selectors for mock contracts
    bytes4 constant MOCK_FUNC1_SELECTOR = bytes4(keccak256("mockFunction1()"));
    bytes4 constant MOCK_FUNC2_SELECTOR = bytes4(keccak256("mockFunction2()"));
    bytes4 constant MOCK_FUNC3_SELECTOR = bytes4(keccak256("mockFunction3(uint256)"));

    function setUp() public {
        // Setup the accessManager
        accessManager = new AccessManager(address(this));

        DeployDiamondRouter deployDiamondRouterScript = new DeployDiamondRouter();
        (router,) = deployDiamondRouterScript.deployForTest(address(accessManager));

        // Deploy mock implementations and the FunctionInfo implementation
        mockImpl1 = address(new Mock2Module());
        mockImpl2 = address(new Mock3Module());
        address functionInfoAddress = address(new FunctionInfoModule());

        // Add FunctionInfo selectors directly using IFunctionManager
        addFunctionInfoInterface(functionInfoAddress);

        // Add mock implementation functions directly using IFunctionManager
        addMockImplementations();
    }

    function addFunctionInfoInterface(address functionInfoAddress) internal {
        // Define all function selectors from IFunctionInfo
        bytes4[] memory functionInfoSelectors = new bytes4[](8);
        functionInfoSelectors[0] = IFunctionInfo.getFunctionInfo.selector;
        functionInfoSelectors[1] = IFunctionInfo.getAllFunctionInfo.selector;
        functionInfoSelectors[2] = IFunctionInfo.getFunctionsByImplementation.selector;
        functionInfoSelectors[3] = IFunctionInfo.getImplementationForFunction.selector;
        functionInfoSelectors[4] = IFunctionInfo.getAllFunctionImplementations.selector;
        functionInfoSelectors[5] = IFunctionInfo.getAllRegisteredFunctions.selector;
        functionInfoSelectors[6] = IFunctionInfo.getRegisteredFunctionCount.selector;
        functionInfoSelectors[7] = IFunctionInfo.isFunctionRegistered.selector;

        // Create IFunctionManager implementation upgrade
        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);

        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: functionInfoAddress,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: functionInfoSelectors
        });

        // Add implementation via IFunctionManager
        IFunctionManager(router).manageFunctions(upgrades, address(0), "");
    }

    function addMockImplementations() internal {
        // For mockImpl1
        bytes4[] memory impl1Selectors = new bytes4[](2);
        impl1Selectors[0] = MOCK_FUNC1_SELECTOR;
        impl1Selectors[1] = MOCK_FUNC2_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);

        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl1,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: impl1Selectors
        });

        // Add implementation via IFunctionManager
        IFunctionManager(router).manageFunctions(upgrades, address(0), "");

        // For mockImpl2
        bytes4[] memory impl2Selectors = new bytes4[](1);
        impl2Selectors[0] = MOCK_FUNC3_SELECTOR;

        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl2,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: impl2Selectors
        });

        // Add implementation via IFunctionManager
        IFunctionManager(router).manageFunctions(upgrades, address(0), "");
    }

    // ==================== TESTS ====================

    function testGetFunctionInfo() public view {
        // Call getFunctionInfo directly on the router
        IFunctionInfo.FunctionInfo memory info = IFunctionInfo(router).getFunctionInfo(MOCK_FUNC1_SELECTOR);

        // Assert that the returned info is correct
        assertEq(info.functionSelector, MOCK_FUNC1_SELECTOR);
        assertEq(info.implementation, mockImpl1);
    }

    function testGetAllFunctionInfo() public view {
        // Call getAllFunctionInfo directly on the router
        IFunctionInfo.FunctionInfo[] memory allFunctions = IFunctionInfo(router).getAllFunctionInfo();

        // We expect at least the number of functions we've added (8 from IFunctionInfo + 3 mock functions + initial functions)
        assertGe(allFunctions.length, 12);

        // Check for mock functions
        bool foundFunc1 = false;
        bool foundFunc2 = false;
        bool foundFunc3 = false;

        for (uint256 i = 0; i < allFunctions.length; i++) {
            if (allFunctions[i].functionSelector == MOCK_FUNC1_SELECTOR) {
                foundFunc1 = true;
                assertEq(allFunctions[i].implementation, mockImpl1);
            } else if (allFunctions[i].functionSelector == MOCK_FUNC2_SELECTOR) {
                foundFunc2 = true;
                assertEq(allFunctions[i].implementation, mockImpl1);
            } else if (allFunctions[i].functionSelector == MOCK_FUNC3_SELECTOR) {
                foundFunc3 = true;
                assertEq(allFunctions[i].implementation, mockImpl2);
            }
        }

        assertTrue(foundFunc1, "Mock function 1 should be found");
        assertTrue(foundFunc2, "Mock function 2 should be found");
        assertTrue(foundFunc3, "Mock function 3 should be found");
    }

    function testGetFunctionsByImplementation() public view {
        // Call getFunctionsByImplementation directly on the router for mockImpl1
        IFunctionInfo.FunctionInfo[] memory impl1Functions = IFunctionInfo(router).getFunctionsByImplementation(mockImpl1);

        // We expect 2 functions for mockImpl1
        assertEq(impl1Functions.length, 2);

        bool foundFunc1 = false;
        bool foundFunc2 = false;

        for (uint256 i = 0; i < impl1Functions.length; i++) {
            if (impl1Functions[i].functionSelector == MOCK_FUNC1_SELECTOR) {
                foundFunc1 = true;
                assertEq(impl1Functions[i].implementation, mockImpl1);
            } else if (impl1Functions[i].functionSelector == MOCK_FUNC2_SELECTOR) {
                foundFunc2 = true;
                assertEq(impl1Functions[i].implementation, mockImpl1);
            }
        }

        assertTrue(foundFunc1, "Mock function 1 should be found for mockImpl1");
        assertTrue(foundFunc2, "Mock function 2 should be found for mockImpl1");

        // Test for mockImpl2
        IFunctionInfo.FunctionInfo[] memory impl2Functions = IFunctionInfo(router).getFunctionsByImplementation(mockImpl2);

        // We expect 1 function for mockImpl2
        assertEq(impl2Functions.length, 1);
        assertEq(impl2Functions[0].functionSelector, MOCK_FUNC3_SELECTOR);
        assertEq(impl2Functions[0].implementation, mockImpl2);
    }

    function testGetImplementationForFunction() public view {
        // Call getImplementationForFunction directly on the router
        address implementation = IFunctionInfo(router).getImplementationForFunction(MOCK_FUNC1_SELECTOR);

        // Assert we got the correct implementation
        assertEq(implementation, mockImpl1);

        // Test for another function selector
        implementation = IFunctionInfo(router).getImplementationForFunction(MOCK_FUNC2_SELECTOR);
        assertEq(implementation, mockImpl1);

        // Test for mockImpl2's function
        implementation = IFunctionInfo(router).getImplementationForFunction(MOCK_FUNC3_SELECTOR);
        assertEq(implementation, mockImpl2);
    }

    function testGetAllImplementations() public view {
        // Call getAllImplementations directly on the router
        address[] memory implementations = IFunctionInfo(router).getAllFunctionImplementations();

        // We expect at least 5 implementations (IFunctionManager, CommandManager, ExecutionModule, FunctionInfo, and our 2 mock impls)
        assertGe(implementations.length, 5);

        bool foundMockImpl1 = false;
        bool foundMockImpl2 = false;

        for (uint256 i = 0; i < implementations.length; i++) {
            if (implementations[i] == mockImpl1) {
                foundMockImpl1 = true;
            } else if (implementations[i] == mockImpl2) {
                foundMockImpl2 = true;
            }
        }

        assertTrue(foundMockImpl1, "mockImpl1 should be found in the implementations list");
        assertTrue(foundMockImpl2, "mockImpl2 should be found in the implementations list");
    }

    function testGetAllRegisteredFunctions() public view {
        // Call getAllRegisteredFunctions directly on the router
        bytes4[] memory functions = IFunctionInfo(router).getAllRegisteredFunctions();

        // We expect at least 17 functions (8 from IFunctionInfo + 3 mock functions + 5+ initial functions)
        assertGe(functions.length, 17);

        bool foundFunc1 = false;
        bool foundFunc2 = false;
        bool foundFunc3 = false;

        for (uint256 i = 0; i < functions.length; i++) {
            if (functions[i] == MOCK_FUNC1_SELECTOR) foundFunc1 = true;
            if (functions[i] == MOCK_FUNC2_SELECTOR) foundFunc2 = true;
            if (functions[i] == MOCK_FUNC3_SELECTOR) foundFunc3 = true;
        }

        assertTrue(foundFunc1, "Function 1 should be registered");
        assertTrue(foundFunc2, "Function 2 should be registered");
        assertTrue(foundFunc3, "Function 3 should be registered");
    }

    function testGetRegisteredFunctionCount() public view {
        // Call getRegisteredFunctionCount directly on the router
        uint256 count = IFunctionInfo(router).getRegisteredFunctionCount();

        // We expect at least 18 functions (8 from IFunctionInfo + 3 mock functions + 5+ initial functions)
        assertGe(count, 17);
    }

    function testIsFunctionRegistered() public view {
        // Test registered function
        bool isRegistered = IFunctionInfo(router).isFunctionRegistered(MOCK_FUNC1_SELECTOR);
        assertTrue(isRegistered);

        // Test another registered function
        isRegistered = IFunctionInfo(router).isFunctionRegistered(MOCK_FUNC2_SELECTOR);
        assertTrue(isRegistered);

        // Test unregistered function (assuming this random selector is not registered)
        bytes4 unregisteredFunc = bytes4(keccak256("unregisteredFunction()"));
        isRegistered = IFunctionInfo(router).isFunctionRegistered(unregisteredFunc);
        assertFalse(isRegistered);
    }
}