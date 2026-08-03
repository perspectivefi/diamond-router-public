// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/interfaces/ICommandInfo.sol";
import {ICommandManager, ICommand} from "src/interfaces/ICommandManager.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";
import {AccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {DiamondRouter} from "src/DiamondRouter.sol";
import {DeployDiamondRouter} from "script/00_deployDiamondRouter.s.sol";
import {FunctionManagerModule, IFunctionManager} from "src/modules/FunctionManagerModule.sol";
import {CommandsModule} from "src/modules/CommandsModule.sol";
import {CommandInfoModule} from "src/modules/CommandInfoModule.sol";
import {LibFunctionManager} from "src/modules/libraries/LibFunctionManager.sol";

contract CommandsInformationTest is Test {
    address router;
    AccessManager accessManager;

    // Mock implementation for testing
    address mockImpl1;
    address mockImpl2;

    // Function selectors
    bytes4 constant MOCK_FUNC1_SELECTOR = bytes4(keccak256("mockFunction1()"));
    bytes4 constant MOCK_FUNC2_SELECTOR = bytes4(keccak256("mockFunction2()"));
    bytes4 constant MOCK_FUNC3_SELECTOR = bytes4(keccak256("mockFunction3(uint256)"));

    // Command IDs we'll use for testing
    bytes1 constant COMMAND_1 = 0x01;
    bytes1 constant COMMAND_2 = 0x02;
    bytes1 constant COMMAND_3 = 0x03;

    function setUp() public {
        // Setup the accessManager
        accessManager = new AccessManager(address(this));

        DeployDiamondRouter deployDiamondRouterScript = new DeployDiamondRouter();
        (router,) = deployDiamondRouterScript.deployForTest(address(accessManager));

        console2.log("Router initialized with all initial modules");

        // Deploy mock implementations and the CommandInfoModule implementation
        mockImpl1 = address(new MockImplementation());
        mockImpl2 = address(new MockImplementation2());
        address commandsInfoAddress = address(new CommandInfoModule());

        // Add CommandInfoModule implementation using CommandManager
        addInformationFunctions(commandsInfoAddress);

        // Add mock implementations using CommandManager
        addMockImplementations();
    }

    function addInformationFunctions(address commandsInfoAddress) internal {

        // Get all function selectors from ICommandInfo
        bytes4[] memory commandsInfoSelectors = new bytes4[](10);
        commandsInfoSelectors[0] = ICommandInfo.getCommandInfo.selector;
        commandsInfoSelectors[1] = ICommandInfo.getAllCommandInfo.selector;
        commandsInfoSelectors[2] = ICommandInfo.getCommandsByImplementation.selector;
        commandsInfoSelectors[3] = ICommandInfo.getCommandByImplementationAndSelector.selector;
        commandsInfoSelectors[4] = ICommandInfo.getAllCommandImplementations.selector;
        commandsInfoSelectors[5] = ICommandInfo.findAvailableCommandIds.selector;
        commandsInfoSelectors[6] = ICommandInfo.getSmallestAvailableCommandId.selector;
        commandsInfoSelectors[7] = ICommandInfo.getAllRegisteredCommands.selector;
        commandsInfoSelectors[8] = ICommandInfo.getRegisteredCommandCount.selector;
        commandsInfoSelectors[9] = ICommandInfo.isCommandIdRegistered.selector;

        addFunctionViaFunctionManager(commandsInfoAddress, commandsInfoSelectors, address(0x0), "");
    }

    function addFunctionViaFunctionManager(
        address implementationAddress,
        bytes4[] memory functionSelectors,
        address initializerAddress,
        bytes memory _inputs
    ) internal {
        // Create FunctionManagerModule implementation upgrade
        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: implementationAddress,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: functionSelectors
        });

        // Add implementation via FunctionManagerModule
        FunctionManagerModule(router).manageFunctions(upgrades, initializerAddress, _inputs);
    }

    function addMockImplementations() internal {
        // For mockImpl1
        bytes4[] memory impl1Selectors = new bytes4[](2);
        impl1Selectors[0] = MOCK_FUNC1_SELECTOR;
        impl1Selectors[1] = MOCK_FUNC2_SELECTOR;

        bytes memory impl1Commands = new bytes(2);
        impl1Commands[0] = COMMAND_1;
        impl1Commands[1] = COMMAND_2;

        addImplementationViaModuleManager(mockImpl1, impl1Selectors, impl1Commands);

        // For mockImpl2
        bytes4[] memory impl2Selectors = new bytes4[](1);
        impl2Selectors[0] = MOCK_FUNC3_SELECTOR;

        bytes memory impl2Commands = new bytes(1);
        impl2Commands[0] = COMMAND_3;

        addImplementationViaModuleManager(mockImpl2, impl2Selectors, impl2Commands);
    }

    function addImplementationViaModuleManager(
        address implementation,
        bytes4[] memory functionSelectors,
        bytes memory commandIds
    ) internal {
        // Create CommandManager implementation modification
        ICommand.CommandModification[] memory mods = new ICommand.CommandModification[](1);

        mods[0] = ICommand.CommandModification(
            implementation, ICommand.ImplementationAction.Add, commandIds, functionSelectors
        );

        // Call manageCommands directly through the ICommandManager interface
        ICommandManager(router).manageCommands(mods, address(0), "");
    }

    // ==================== TESTS ====================

    function testGetCommandInfo() public view {
        // Call getCommandInfo directly on the router
        ICommandInfo.CommandInfo memory info = ICommandInfo(router).getCommandInfo(COMMAND_1);

        // Assert that the returned info is correct
        assertEq(info.commandId, COMMAND_1);
        assertEq(info.implementation, mockImpl1);
        assertEq(info.functionSelector, MOCK_FUNC1_SELECTOR);
    }

    function testGetAllCommandInfo() public view {
        // Call getAllCommandInfo directly on the router
        ICommandInfo.CommandInfo[] memory allCommands = ICommandInfo(router).getAllCommandInfo();

        // We expect at least 13 commands (10 info commands + 3 mock commands)
        assertEq(allCommands.length, 3);

        // Check for mock commands
        bool foundCmd1 = false;
        bool foundCmd2 = false;
        bool foundCmd3 = false;

        for (uint256 i = 0; i < allCommands.length; i++) {
            if (allCommands[i].commandId == COMMAND_1) {
                foundCmd1 = true;
                assertEq(allCommands[i].implementation, mockImpl1);
                assertEq(allCommands[i].functionSelector, MOCK_FUNC1_SELECTOR);
            } else if (allCommands[i].commandId == COMMAND_2) {
                foundCmd2 = true;
                assertEq(allCommands[i].implementation, mockImpl1);
                assertEq(allCommands[i].functionSelector, MOCK_FUNC2_SELECTOR);
            } else if (allCommands[i].commandId == COMMAND_3) {
                foundCmd3 = true;
                assertEq(allCommands[i].implementation, mockImpl2);
                assertEq(allCommands[i].functionSelector, MOCK_FUNC3_SELECTOR);
            }
        }

        assertTrue(foundCmd1);
        assertTrue(foundCmd2);
        assertTrue(foundCmd3);
    }

    function testGetCommandsByImplementation() public view {
        // Call getCommandsByImplementation directly on the router for mockImpl1
        ICommandInfo.CommandInfo[] memory impl1Commands = ICommandInfo(router).getCommandsByImplementation(mockImpl1);

        // We expect 2 commands for mockImpl1
        assertEq(impl1Commands.length, 2);

        bool foundCmd1 = false;
        bool foundCmd2 = false;

        for (uint256 i = 0; i < impl1Commands.length; i++) {
            if (impl1Commands[i].commandId == COMMAND_1) {
                foundCmd1 = true;
                assertEq(impl1Commands[i].implementation, mockImpl1);
                assertEq(impl1Commands[i].functionSelector, MOCK_FUNC1_SELECTOR);
            } else if (impl1Commands[i].commandId == COMMAND_2) {
                foundCmd2 = true;
                assertEq(impl1Commands[i].implementation, mockImpl1);
                assertEq(impl1Commands[i].functionSelector, MOCK_FUNC2_SELECTOR);
            }
        }

        assertTrue(foundCmd1);
        assertTrue(foundCmd2);

        // Test for mockImpl2
        ICommandInfo.CommandInfo[] memory impl2Commands = ICommandInfo(router).getCommandsByImplementation(mockImpl2);

        // We expect 1 command for mockImpl2
        assertEq(impl2Commands.length, 1);
        assertEq(impl2Commands[0].commandId, COMMAND_3);
        assertEq(impl2Commands[0].implementation, mockImpl2);
        assertEq(impl2Commands[0].functionSelector, MOCK_FUNC3_SELECTOR);
    }

    function testGetCommandByImplementationAndSelector() public view {
        // Call getCommandByImplementationAndSelector directly on the router
        bytes1 commandId = ICommandInfo(router).getCommandByImplementationAndSelector(mockImpl1, MOCK_FUNC1_SELECTOR);

        // Assert we got the correct command ID
        assertEq(commandId, COMMAND_1);

        // Test for another function selector
        commandId = ICommandInfo(router).getCommandByImplementationAndSelector(mockImpl1, MOCK_FUNC2_SELECTOR);
        assertEq(commandId, COMMAND_2);

        // Test for mockImpl2
        commandId = ICommandInfo(router).getCommandByImplementationAndSelector(mockImpl2, MOCK_FUNC3_SELECTOR);
        assertEq(commandId, COMMAND_3);
    }

    function testGetAllImplementations() public view {
        // Call getAllImplementations directly on the router
        address[] memory implementations = ICommandInfo(router).getAllCommandImplementations();

        // We expect exactly 2 implementations (2 mock impls)
        assertEq(implementations.length, 2, "Should have exactly 2 implementations");

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

    function testFindAvailableCommandIds() public view {
        // Call findAvailableCommandIds directly on the router - request 3 available IDs
        bytes1[] memory availableIds = ICommandInfo(router).findAvailableCommandIds(3);

        // Check that we got 3 unique IDs
        assertEq(availableIds.length, 3);

        // They should be distinct from our already used IDs
        for (uint256 i = 0; i < availableIds.length; i++) {
            assertFalse(isCommandUsed(availableIds[i]));

            // Check IDs are unique among themselves
            for (uint256 j = 0; j < i; j++) {
                assertFalse(availableIds[i] == availableIds[j]);
            }
        }
    }

    function isCommandUsed(bytes1 commandId) internal view returns (bool) {
        // Use the actual isCommandIdRegistered function to check if command is used
        return ICommandInfo(router).isCommandIdRegistered(commandId);
    }

    function testGetSmallestAvailableCommandId() public view {
        // Call getSmallestAvailableCommandId directly on the router
        bytes1 smallestId = ICommandInfo(router).getSmallestAvailableCommandId();

        // The smallest ID should not be any of our already used IDs
        assertFalse(ICommandInfo(router).isCommandIdRegistered(smallestId));
    }

    function testGetAllRegisteredCommands() public view {
        // Call getAllRegisteredCommands directly on the router
        bytes1[] memory commands = ICommandInfo(router).getAllRegisteredCommands();

        // We expect exactly 13 commands (3 mock commands)
        assertEq(commands.length, 3, "Should have exactly 3 registered commands");

        bool foundCmd1 = false;
        bool foundCmd2 = false;
        bool foundCmd3 = false;

        for (uint256 i = 0; i < commands.length; i++) {
            if (commands[i] == COMMAND_1) foundCmd1 = true;
            if (commands[i] == COMMAND_2) foundCmd2 = true;
            if (commands[i] == COMMAND_3) foundCmd3 = true;
        }

        assertTrue(foundCmd1, "Command 1 should be registered");
        assertTrue(foundCmd2, "Command 2 should be registered");
        assertTrue(foundCmd3, "Command 3 should be registered");
    }

    function testGetRegisteredCommandCount() public view {
        // Call getRegisteredCommandCount directly on the router
        uint256 count = ICommandInfo(router).getRegisteredCommandCount();

        // We expect exactly 3 commands (3 mock commands)
        assertEq(count, 3, "Should have exactly 3 registered commands");
    }

    function testIsCommandIdRegistered() public view {
        // Test registered command
        bool isRegistered = ICommandInfo(router).isCommandIdRegistered(COMMAND_1);
        assertTrue(isRegistered);

        // Test another registered command
        isRegistered = ICommandInfo(router).isCommandIdRegistered(COMMAND_2);
        assertTrue(isRegistered);

        // Test unregistered command (assuming 0xFF is not registered)
        bytes1 unregisteredCmd = 0xFF;
        isRegistered = ICommandInfo(router).isCommandIdRegistered(unregisteredCmd);
        assertFalse(isRegistered);
    }
}

// Mock implementations for testing
contract MockImplementation {
    function mockFunction1() external pure returns (uint256) {
        return 1;
    }

    function mockFunction2() external pure returns (string memory) {
        return "test";
    }
}

contract MockImplementation2 {
    function mockFunction3(uint256 a) external pure returns (uint256) {
        return a * 2;
    }
}