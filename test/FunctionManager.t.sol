// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IFunctionManager} from "src/interfaces/IFunctionManager.sol";
import {AccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {DeployDiamondRouter} from "script/00_deployDiamondRouter.s.sol";
import {Mock1Module, Mock2Module, Mock3Module, Mock4Module} from "test/modules/MockModules.sol";


contract FunctionsManagerTest is Test {
    address router;
    AccessManager accessManager;

    // Mock implementation for testing
    address mockImpl1;
    address mockImpl2;
    address mockImpl3;
    address mockImpl4;

    // Function selectors for mock contracts
    bytes4 constant MOCK_FUNC1_SELECTOR = bytes4(keccak256("mockFunction1()"));
    bytes4 constant MOCK_FUNC2_SELECTOR = bytes4(keccak256("mockFunction2()"));
    bytes4 constant MOCK_FUNC3_SELECTOR = bytes4(keccak256("mockFunction3(uint256)"));
    bytes4 constant MOCK1_FUNC1_SELECTOR = bytes4(keccak256("mock1Func1()"));
    bytes4 constant MOCK1_FUNC2_SELECTOR = bytes4(keccak256("mock1Func2()"));

    function setUp() public {
        // Setup the accessManager
        accessManager = new AccessManager(address(this));

        DeployDiamondRouter deployDiamondRouterScript = new DeployDiamondRouter();
        (router,) = deployDiamondRouterScript.deployForTest(address(accessManager));

        // Deploy mock implementations
        mockImpl1 = address(new Mock1Module());
        mockImpl2 = address(new Mock2Module());
        mockImpl3 = address(new Mock3Module());
        mockImpl4 = address(new Mock4Module());
    }

    function test_AddSingleFunction() public {
        // Create function upgrade to add mockFunction1
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC1_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl2,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectors
        });

        // Expect the FunctionUpgraded event
        vm.expectEmit(true, true, true, true);
        emit IFunctionManager.FunctionUpgraded(upgrades, address(0), "");

        // Add the function
        IFunctionManager(router).manageFunctions(upgrades, address(0), "");

        // Test that the function works
        (bool success, bytes memory data) = router.call(abi.encodeWithSelector(MOCK_FUNC1_SELECTOR));
        assertTrue(success);
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 1);
    }

    function test_AddMultipleFunctions() public {
        // Create function upgrade to add multiple functions
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MOCK_FUNC1_SELECTOR;
        selectors[1] = MOCK_FUNC2_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl2,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectors
        });

        // Expect the FunctionUpgraded event
        vm.expectEmit(true, true, true, true);
        emit IFunctionManager.FunctionUpgraded(upgrades, address(0), "");

        // Add the functions
        IFunctionManager(router).manageFunctions(upgrades, address(0), "");

        // Test that both functions work
        (bool success1, bytes memory data1) = router.call(abi.encodeWithSelector(MOCK_FUNC1_SELECTOR));
        assertTrue(success1);
        uint256 result1 = abi.decode(data1, (uint256));
        assertEq(result1, 1);

        (bool success2, bytes memory data2) = router.call(abi.encodeWithSelector(MOCK_FUNC2_SELECTOR));
        assertTrue(success2);
        string memory result2 = abi.decode(data2, (string));
        assertEq(result2, "test");
    }

    function test_ReplaceFunction() public {
        // First add a function from mockImpl2
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC1_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory addUpgrades = new IFunctionManager.FunctionUpgrade[](1);
        addUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl2,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectors
        });

        IFunctionManager(router).manageFunctions(addUpgrades, address(0), "");

        // Verify the original function works
        (bool success1, bytes memory data1) = router.call(abi.encodeWithSelector(MOCK_FUNC1_SELECTOR));
        assertTrue(success1);
        uint256 result1 = abi.decode(data1, (uint256));
        assertEq(result1, 1);

        // Now replace it with a different implementation
        // Note: We'll need to create a new mock that has the same selector but different behavior
        // For this test, we'll replace with the same implementation but verify the event is emitted
        IFunctionManager.FunctionUpgrade[] memory replaceUpgrades = new IFunctionManager.FunctionUpgrade[](1);
        replaceUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl4, // Same implementation for simplicity
            action: IFunctionManager.FunctionUpgradeAction.Replace,
            functionSelectors: selectors
        });

        vm.expectEmit(true, true, true, true);
        emit IFunctionManager.FunctionUpgraded(replaceUpgrades, address(0), "");

        IFunctionManager(router).manageFunctions(replaceUpgrades, address(0), "");

        // Function should still work
        (bool success2, bytes memory data2) = router.call(abi.encodeWithSelector(MOCK_FUNC1_SELECTOR));
        assertTrue(success2);
        uint256 result2 = abi.decode(data2, (uint256));
        assertEq(result2, 42);
    }

    function test_RemoveFunction() public {
        // First add a function
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC1_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory addUpgrades = new IFunctionManager.FunctionUpgrade[](1);
        addUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl2,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectors
        });

        IFunctionManager(router).manageFunctions(addUpgrades, address(0), "");

        // Verify function works
        (bool success1,) = router.call(abi.encodeWithSelector(MOCK_FUNC1_SELECTOR));
        assertTrue(success1);

        // Now remove the function
        IFunctionManager.FunctionUpgrade[] memory removeUpgrades = new IFunctionManager.FunctionUpgrade[](1);
        removeUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(0), // Address doesn't matter for removal
            action: IFunctionManager.FunctionUpgradeAction.Remove,
            functionSelectors: selectors
        });

        vm.expectEmit(true, true, true, true);
        emit IFunctionManager.FunctionUpgraded(removeUpgrades, address(0), "");

        IFunctionManager(router).manageFunctions(removeUpgrades, address(0), "");

        // Function should no longer work
        (bool success2,) = router.call(abi.encodeWithSelector(MOCK_FUNC1_SELECTOR));
        assertFalse(success2);
    }

    function test_MultipleUpgradesInSingleCall() public {
        // Create upgrades that add functions from different implementations
        bytes4[] memory selectors1 = new bytes4[](2);
        selectors1[0] = MOCK1_FUNC1_SELECTOR;
        selectors1[1] = MOCK1_FUNC2_SELECTOR;

        bytes4[] memory selectors2 = new bytes4[](1);
        selectors2[0] = MOCK_FUNC3_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](2);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl1,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectors1
        });
        upgrades[1] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl3,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectors2
        });

        // Expect the FunctionUpgraded event
        vm.expectEmit(true, true, true, true);
        emit IFunctionManager.FunctionUpgraded(upgrades, address(0), "");

        IFunctionManager(router).manageFunctions(upgrades, address(0), "");

        // Test that functions from mockImpl1 work
        (bool success1,) = router.call(abi.encodeWithSelector(MOCK1_FUNC1_SELECTOR));
        assertTrue(success1);

        (bool success2, ) = router.call(abi.encodeWithSelector(MOCK1_FUNC2_SELECTOR));
        assertTrue(success2);

        // Test that function from mockImpl3 works
        (bool success3, bytes memory data3) = router.call(abi.encodeWithSelector(MOCK_FUNC3_SELECTOR, 5));
        assertTrue(success3);
        uint256 result3 = abi.decode(data3, (uint256));
        assertEq(result3, 10); // 5 * 2
    }

    function test_ManageFunctionsWithInitialization() public {
        // Create a simple initialization contract for testing
        address initContract = address(new TestInitContract());
        bytes memory initCalldata = abi.encodeWithSignature("initialize(uint256)", 42);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC1_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl2,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectors
        });

        // Expect the event with initialization parameters
        vm.expectEmit(true, true, true, true);
        emit IFunctionManager.FunctionUpgraded(upgrades, initContract, initCalldata);

        IFunctionManager(router).manageFunctions(upgrades, initContract, initCalldata);

        // Function should work
        (bool success, bytes memory data) = router.call(abi.encodeWithSelector(MOCK_FUNC1_SELECTOR));
        assertTrue(success);
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 1);
    }

    function test_RevertOnInvalidAction() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC1_SELECTOR;

        // Manually encode the call with invalid enum value
        bytes memory callData = abi.encodeWithSelector(
            IFunctionManager.manageFunctions.selector,
            // Manually construct the upgrades array with invalid action
            abi.encode(
                // Array length
                1,
                // Struct data
                mockImpl2,  // implementationAddress
                99,         // invalid action
                selectors   // functionSelectors
            ),
            address(0), // _init
            ""          // _calldata
        );

        vm.expectRevert();
        router.call(callData);
    }

    function test_RevertOnAddingExistingFunction() public {
        // Add a function first
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC1_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: mockImpl2,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectors
        });

        // Expect the FunctionUpgraded event
        vm.expectEmit(true, true, true, true);
        emit IFunctionManager.FunctionUpgraded(upgrades, address(0), "");

        IFunctionManager(router).manageFunctions(upgrades, address(0), "");

        // Try to add the same function again - should revert
        vm.expectRevert();
        IFunctionManager(router).manageFunctions(upgrades, address(0), "");
    }

    function test_RevertOnRemovingNonExistentFunction() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC1_SELECTOR;

        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(0),
            action: IFunctionManager.FunctionUpgradeAction.Remove,
            functionSelectors: selectors
        });

        // Try to remove a function that doesn't exist - should revert
        vm.expectRevert();
        IFunctionManager(router).manageFunctions(upgrades, address(0), "");
    }
}

// Helper contract for initialization testing
contract TestInitContract {
    uint256 public value;

    function initialize(uint256 _value) external {
        value = _value;
    }
}