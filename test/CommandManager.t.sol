// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {DiamondRouter} from "src/DiamondRouter.sol";
import {AccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {ICommandManager, ICommand} from "src/interfaces/ICommandManager.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";
import {DeployDiamondRouter} from "script/00_deployDiamondRouter.s.sol";
import {Mock1Module, Mock2Module, Mock3Module} from "test/modules/MockModules.sol";

contract CommandManagerTest is Test {
    address router;
    AccessManager accessManager;

    // Execute Selector
    bytes4 constant EXECUTE_SELECTOR = bytes4(keccak256("execute(bytes,bytes[])"));

    // Mock implementation for testing
    address mockImpl1;
    address mockImpl2;
    address mockImpl3;

    // Function selectors for mock contracts
    bytes4 constant MOCK_FUNC1_SELECTOR = bytes4(keccak256("mockFunction1()"));
    bytes4 constant MOCK_FUNC2_SELECTOR = bytes4(keccak256("mockFunction2()"));
    bytes4 constant MOCK_FUNC3_SELECTOR = bytes4(keccak256("mockFunction3(uint256)"));
    bytes4 constant MOCK1_FUNC1_SELECTOR = bytes4(keccak256("mock1Func1()"));
    bytes4 constant MOCK1_FUNC2_SELECTOR = bytes4(keccak256("mock1Func2()"));

    // Command IDs for testing
    bytes constant COMMAND_ID_1 = abi.encodePacked(uint8(1));
    bytes constant COMMAND_ID_2 = abi.encodePacked(uint8(2));
    bytes constant COMMAND_ID_3 = abi.encodePacked(uint8(3));

    event CommandModifications(
        ICommand.CommandModification[] _commandModifications, 
        address _init, 
        bytes _calldata
    );

    function setUp() public {
        // Setup the accessManager
        accessManager = new AccessManager(address(this));

        DeployDiamondRouter deployDiamondRouterScript = new DeployDiamondRouter();
        (router,) = deployDiamondRouterScript.deployForTest(address(accessManager));

        // Deploy mock implementations
        mockImpl1 = address(new Mock1Module());
        mockImpl2 = address(new Mock2Module());
        mockImpl3 = address(new Mock3Module());
    }

    function testAddSingleCommand() public {
        // Prepare command modification for adding a new command
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](1);
        
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK1_FUNC1_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: mockImpl1,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_1,
            functionSelectors: selectors
        });

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, address(0), "");

        // Execute the command management
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );

        // Verify the command was added by checking if we can call the command
        bytes[] memory input = new bytes[](1);
        input[0] = "";
        
        IExecutor(router).execute(COMMAND_ID_1, input);
    }

    function testAddMultipleCommands() public {
        // Prepare command modifications for adding multiple commands
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](2);
        
        // First command
        bytes4[] memory selectors1 = new bytes4[](1);
        selectors1[0] = MOCK1_FUNC1_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: mockImpl1,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_1,
            functionSelectors: selectors1
        });

        // Second command
        bytes4[] memory selectors2 = new bytes4[](1);
        selectors2[0] = MOCK1_FUNC2_SELECTOR;
        
        modifications[1] = ICommand.CommandModification({
            implementation: mockImpl1,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_2,
            functionSelectors: selectors2
        });

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, address(0), "");

        // Execute the command management
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );

        // Verify both commands were added
        bytes[] memory input = new bytes[](1);
        input[0] = "";
        
        IExecutor(router).execute(COMMAND_ID_1, input);
        
        IExecutor(router).execute(COMMAND_ID_2, input);
    }

    function testReplaceCommand() public {
        // First, add a command
        testAddSingleCommand();

        // Now replace it with a different implementation
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](1);
        
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC3_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: mockImpl3, // Different implementation
            action: ICommand.ImplementationAction.Replace,
            commands: COMMAND_ID_1,
            functionSelectors: selectors
        });

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, address(0), "");

        // Execute the replacement
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );

        // Verify the function is still callable (but now uses different implementation)
        bytes[] memory input = new bytes[](1);
        input[0] = abi.encode(21);
        
        IExecutor(router).execute(COMMAND_ID_1, input);
    }

    function testRemoveCommand() public {
        // First, add a command
        testAddSingleCommand();

        // Now remove it
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](1);
        
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK1_FUNC1_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: address(0), // Implementation doesn't matter for removal
            action: ICommand.ImplementationAction.Remove,
            commands: COMMAND_ID_1,
            functionSelectors: selectors
        });

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, address(0), "");

        // Execute the removal
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );

        // Verify the function is no longer callable
        bytes[] memory input = new bytes[](1);
        input[0] = "";
        vm.expectRevert();
        IExecutor(router).execute(COMMAND_ID_1, input);
    }

    function testMixedActions() public {
        ICommand.CommandModification[] memory initialModifications = 
            new ICommand.CommandModification[](2);
        
        // Add a new command
        bytes4[] memory selectors2 = new bytes4[](1);
        selectors2[0] = MOCK_FUNC1_SELECTOR;

        // Command to be replaced
        initialModifications[0] = ICommand.CommandModification({
            implementation: mockImpl3,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_2,
            functionSelectors: selectors2
        });

        bytes4[] memory selectors3 = new bytes4[](1);
        selectors3[0] = MOCK_FUNC1_SELECTOR;

        // Command to be removed
        initialModifications[1] = ICommand.CommandModification({
            implementation: mockImpl2,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_3,
            functionSelectors: selectors3
        });

        // Expect event emission for initial modifications
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(initialModifications, address(0), "");

        ICommandManager(router).manageCommands(
            initialModifications,
            address(0),
            ""
        );

        // Test adding, replacing, and removing commands in a single transaction
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](3);
        
        // Add a new command
        bytes4[] memory selectors1 = new bytes4[](1);
        selectors1[0] = MOCK1_FUNC1_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: mockImpl1,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_1,
            functionSelectors: selectors1
        });

        // Replace an existing command (assuming MOCK_FUNC1_SELECTOR was added in setup)
        selectors2[0] = MOCK_FUNC1_SELECTOR;
        
        modifications[1] = ICommand.CommandModification({
            implementation: mockImpl2,
            action: ICommand.ImplementationAction.Replace,
            commands: COMMAND_ID_2,
            functionSelectors: selectors2
        });

        // Remove a command (assuming MOCK_FUNC2_SELECTOR was added in setup)
        selectors3[0] = MOCK_FUNC2_SELECTOR;
        
        modifications[2] = ICommand.CommandModification({
            implementation: address(0),
            action: ICommand.ImplementationAction.Remove,
            commands: COMMAND_ID_3,
            functionSelectors: selectors3
        });

        // Expect event emission for mixed actions
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, address(0), "");

        // Execute all modifications
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );

        // Verify results
        bytes[] memory input = new bytes[](1);
        input[0] = '';
        
        IExecutor(router).execute(COMMAND_ID_1, input);        
        
        IExecutor(router).execute(COMMAND_ID_2, input);        

        input[0] = abi.encode(21);

        vm.expectRevert(abi.encodeWithSelector(IExecutor.CommandNotFound.selector, bytes1(uint8(3))));
        IExecutor(router).execute(COMMAND_ID_3, input);
    }

    function testManageCommandsWithInitialization() public {
        // Prepare command modification
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](1);
        
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK_FUNC3_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: mockImpl3,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_1,
            functionSelectors: selectors
        });

        // Prepare initialization call
        bytes memory initCalldata = abi.encodeWithSelector(
            MOCK_FUNC3_SELECTOR, // Assuming there's an initialize function
            21
        );

        // Expect event emission
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, mockImpl3, initCalldata);

        // Execute with initialization
        ICommandManager(router).manageCommands(
            modifications,
            mockImpl3, // Use the same implementation as init contract
            initCalldata
        );

        // Verify the command was added
        bytes[] memory input = new bytes[](1);
        input[0] = abi.encode(42);

        IExecutor(router).execute(COMMAND_ID_1, input);
    }

    function testEventEmission() public {
        // Prepare command modification
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](1);
        
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK1_FUNC1_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: mockImpl3,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_1,
            functionSelectors: selectors
        });

        bytes memory initCalldata = abi.encodeWithSelector(MOCK_FUNC3_SELECTOR, 21);

        // Expect the event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, mockImpl3, initCalldata);

        // Execute the command management
        ICommandManager(router).manageCommands(
            modifications,
            mockImpl3,
            initCalldata
        );
    }

    function testUnauthorizedAccess() public {
        // Switch to a different sender who shouldn't have access
        vm.prank(address(0x123));

        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](1);
        
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK1_FUNC1_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: mockImpl3,
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_1,
            functionSelectors: selectors
        });

        // This should revert due to access control
        vm.expectRevert();
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );
    }

    function testEmptyModifications() public {
        // Test with empty modifications array
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](0);

        // Expect event emission even for empty modifications
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, address(0), "");

        // This should not revert but also not change anything
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );
    }

    function testInvalidImplementationAddress() public {
        // Test adding a command with zero address implementation
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](1);
        
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MOCK1_FUNC1_SELECTOR;
        
        modifications[0] = ICommand.CommandModification({
            implementation: address(0), // Invalid for Add action
            action: ICommand.ImplementationAction.Add,
            commands: COMMAND_ID_1,
            functionSelectors: selectors
        });

        // This should revert
        vm.expectRevert();
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );
    }
}