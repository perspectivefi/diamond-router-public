// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {DiamondRouter} from "src/DiamondRouter.sol";
import {AccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {ICommandManager, ICommand} from "src/interfaces/ICommandManager.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";
import {DeployDiamondRouter} from "script/00_deployDiamondRouter.s.sol";
import {TransferModule} from "test/modules/TransferModule.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock ERC20 token with permit functionality
contract MockERC20Permit is ERC20, IERC20Permit {
    mapping(address => uint) public nonces;
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 ,
        uint8 ,
        bytes32 ,
        bytes32
    ) external override {
        // Simple mock implementation - just approve
        _approve(owner, spender, value);
    }
    
    function DOMAIN_SEPARATOR() external pure override returns (bytes32) {
        return keccak256("MOCK_DOMAIN");
    }
}

contract ExecutionModuleTest is Test {
    address router;
    AccessManager accessManager;
    TransferModule transferModule;
    MockERC20 mockToken;
    MockERC20Permit mockTokenPermit;
    
    address user1 = address(0x1);
    address user2 = address(0x2);
    address recipient = address(0x3);

    // Execute Selectors
    bytes4 constant EXECUTE_SELECTOR = bytes4(keccak256("execute(bytes,bytes[])"));
    bytes4 constant EXECUTE_WITH_DEADLINE_SELECTOR = bytes4(keccak256("execute(bytes,bytes[],uint256)"));
    bytes4 constant EXECUTE_WITH_RETURN_SELECTOR = bytes4(keccak256("execute(bytes,bytes[],bool)"));
    bytes4 constant EXECUTE_WITH_DEADLINE_RETURN_SELECTOR = bytes4(keccak256("execute(bytes,bytes[],uint256,bool)"));

    // TransferModule function selectors
    bytes4 constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,uint256)"));
    bytes4 constant TRANSFER_FROM_WITH_PERMIT_SELECTOR = bytes4(keccak256("transferFromWithPermit(address,uint256,uint256,uint8,bytes32,bytes32)"));
    bytes4 constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,address,uint256)"));

    // Command IDs for testing
    bytes constant TRANSFER_FROM_COMMAND = abi.encodePacked(uint8(1));
    bytes constant TRANSFER_FROM_WITH_PERMIT_COMMAND = abi.encodePacked(uint8(2));
    bytes constant TRANSFER_COMMAND = abi.encodePacked(uint8(3));
    bytes constant TRANSFER_NATIVE_COMMAND = abi.encodePacked(uint8(4));

    // Events
    event CommandModifications(
        ICommand.CommandModification[] _commandModifications, 
        address _init, 
        bytes _calldata
    );
    
    event TestEvent(address something);

    // Errors
    error TransactionDeadlinePassed();
    error LengthMismatch();
    error CommandNotFound(bytes1 command);
    error PermitFailed();

    function setUp() public {
        // Setup the accessManager
        accessManager = new AccessManager(address(this));

        DeployDiamondRouter deployDiamondRouterScript = new DeployDiamondRouter();
        (router,) = deployDiamondRouterScript.deployForTest(address(accessManager));

        // Deploy TransferModule
        transferModule = new TransferModule();

        // Deploy mock tokens
        mockToken = new MockERC20("Mock Token", "MOCK");
        mockTokenPermit = new MockERC20Permit("Mock Token Permit", "MOCKP");

        // Setup users with tokens
        mockToken.mint(user1, 1000e18);
        mockToken.mint(user2, 1000e18);
        mockTokenPermit.mint(user1, 1000e18);
        mockTokenPermit.mint(user2, 1000e18);

        // Add TransferModule commands to router
        _addTransferCommands();
    }

    function _addTransferCommands() internal {
        // All selectors in one array
        bytes4[] memory allSelectors = new bytes4[](4);
        allSelectors[0] = TRANSFER_FROM_SELECTOR;
        allSelectors[1] = TRANSFER_FROM_WITH_PERMIT_SELECTOR;
        allSelectors[2] = TRANSFER_SELECTOR;
        allSelectors[3] = TransferModule.transferNative.selector;
        
        // All commands in one array (each command is bytes1)
        bytes memory allCommands = new bytes(4);
        allCommands[0] = TRANSFER_FROM_COMMAND[0];
        allCommands[1] = TRANSFER_FROM_WITH_PERMIT_COMMAND[0];
        allCommands[2] = TRANSFER_COMMAND[0];
        allCommands[3] = TRANSFER_NATIVE_COMMAND[0];
        
        // Create modifications array
        ICommand.CommandModification[] memory modifications = 
            new ICommand.CommandModification[](1);
        
        // Create modifications for each command-selector pair
            modifications[0] = ICommand.CommandModification({
                implementation: address(transferModule),
                action: ICommand.ImplementationAction.Add,
                commands: allCommands,
                functionSelectors: allSelectors
            });
        
        // Expect the CommandModifications event
        vm.expectEmit(true, true, true, true);
        emit CommandModifications(modifications, address(0), "");

        // Execute the command management
        ICommandManager(router).manageCommands(
            modifications,
            address(0),
            ""
        );
    }

    function testTransferFromCommand() public {
        uint256 transferAmount = 100e18;
        
        // User1 approves router to spend tokens
        vm.prank(user1);
        mockToken.approve(router, transferAmount);

        // Prepare command inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockToken), transferAmount);

        uint256 routerBalanceBefore = mockToken.balanceOf(router);
        uint256 user1BalanceBefore = mockToken.balanceOf(user1);

        // Expect Transfer event from ERC20
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(user1, router, transferAmount);

        // Execute transferFrom command
        vm.prank(user1);
        (bool success,) = router.call(
            abi.encodeWithSelector(EXECUTE_SELECTOR, TRANSFER_FROM_COMMAND, inputs)
        );

        assertTrue(success, "TransferFrom command should succeed");
        assertEq(mockToken.balanceOf(router), routerBalanceBefore + transferAmount, "Router should receive tokens");
        assertEq(mockToken.balanceOf(user1), user1BalanceBefore - transferAmount, "User1 should lose tokens");
    }

    function testTransferFromCommandInsufficientAllowance() public {
        uint256 transferAmount = 100e18;
        
        // User1 approves less than needed
        vm.prank(user1);
        mockToken.approve(router, transferAmount - 1);

        // Prepare command inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockToken), transferAmount);

        // Execute transferFrom command - should fail
        vm.prank(user1);
        (bool success,) = router.call(
            abi.encodeWithSelector(EXECUTE_SELECTOR, TRANSFER_FROM_COMMAND, inputs)
        );

        assertFalse(success, "TransferFrom command should fail with insufficient allowance");
    }

    function testTransferFromWithPermitCommand() public {
        uint256 transferAmount = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint8 v = 27;
        bytes32 r = keccak256("mock_r");
        bytes32 s = keccak256("mock_s");

        // Prepare command inputs
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockTokenPermit), transferAmount, deadline, v, r, s);

        uint256 routerBalanceBefore = mockTokenPermit.balanceOf(router);
        uint256 user1BalanceBefore = mockTokenPermit.balanceOf(user1);

        // Expect Transfer event
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(user1, router, transferAmount);

        // Execute transferFromWithPermit command
        vm.prank(user1);
        (bool success,) = router.call(
            abi.encodeWithSelector(EXECUTE_SELECTOR, TRANSFER_FROM_WITH_PERMIT_COMMAND, inputs)
        );

        assertTrue(success, "TransferFromWithPermit command should succeed");
        assertEq(mockTokenPermit.balanceOf(router), routerBalanceBefore + transferAmount, "Router should receive tokens");
        assertEq(mockTokenPermit.balanceOf(user1), user1BalanceBefore - transferAmount, "User1 should lose tokens");
    }

    function testTransferCommand() public {
        uint256 transferAmount = 100e18;
        
        // First, get tokens to the router
        vm.prank(user1);
        mockToken.approve(router, transferAmount);
        
        bytes[] memory transferFromInputs = new bytes[](1);
        transferFromInputs[0] = abi.encode(address(mockToken), transferAmount);
        
        vm.prank(user1);
        IExecutor(router).execute(TRANSFER_FROM_COMMAND, transferFromInputs);

        // Now test transfer command
        bytes[] memory transferInputs = new bytes[](1);
        transferInputs[0] = abi.encode(address(mockToken), recipient, transferAmount);

        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);
        uint256 routerBalanceBefore = mockToken.balanceOf(router);

        // Expect Transfer event from router to recipient
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(router, recipient, transferAmount);

        // Execute transfer command
        vm.prank(user1);
        (bool success,) = router.call(
            abi.encodeWithSelector(EXECUTE_SELECTOR, TRANSFER_COMMAND, transferInputs)
        );

        assertTrue(success, "Transfer command should succeed");
        assertEq(mockToken.balanceOf(recipient), recipientBalanceBefore + transferAmount, "Recipient should receive tokens");
        assertEq(mockToken.balanceOf(router), routerBalanceBefore - transferAmount, "Router should lose tokens");
    }

    function testTransferCommandWithZeroAmount() public {
        uint256 transferAmount = 0;
        
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockToken), recipient, transferAmount);

        uint256 recipientBalanceBefore = mockToken.balanceOf(recipient);
        uint256 routerBalanceBefore = mockToken.balanceOf(router);

        // Execute transfer command with zero amount
        vm.prank(user1);
        (bool success,) = router.call(
            abi.encodeWithSelector(EXECUTE_SELECTOR, TRANSFER_COMMAND, inputs)
        );

        assertTrue(success, "Transfer command with zero amount should succeed");
        assertEq(mockToken.balanceOf(recipient), recipientBalanceBefore, "Recipient balance should not change");
        assertEq(mockToken.balanceOf(router), routerBalanceBefore, "Router balance should not change");
    }

    function testExecuteWithDeadline() public {
        uint256 transferAmount = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(user1);
        mockToken.approve(router, transferAmount);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockToken), transferAmount);

        // Execute with valid deadline
        vm.prank(user1);
        (bool success,) = router.call(
            abi.encodeWithSelector(EXECUTE_WITH_DEADLINE_SELECTOR, TRANSFER_FROM_COMMAND, inputs, deadline)
        );

        assertTrue(success, "Execute with valid deadline should succeed");
    }

    function testExecuteWithExpiredDeadline() public {
        uint256 transferAmount = 100e18;
        uint256 deadline = block.timestamp - 1; // Expired deadline
        
        vm.prank(user1);
        mockToken.approve(router, transferAmount);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockToken), transferAmount);

        // Execute with expired deadline - should revert
        vm.prank(user1);
        vm.expectRevert(TransactionDeadlinePassed.selector);
        IExecutor(router).execute(TRANSFER_FROM_COMMAND, inputs, deadline);
    }

    function testExecuteWithReturnData() public {
        uint256 transferAmount = 100e18;
        
        vm.prank(user1);
        mockToken.approve(router, transferAmount);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockToken), transferAmount);

        // Execute with return data flag
        vm.prank(user1);
        (bool success, bytes memory returnData) = router.call(
            abi.encodeWithSelector(EXECUTE_WITH_RETURN_SELECTOR, TRANSFER_FROM_COMMAND, inputs, true)
        );

        assertTrue(success, "Execute with return data should succeed");
        assertTrue(returnData.length > 0, "Should return data when requested");
    }

    function testExecuteWithDeadlineAndReturnData() public {
        uint256 transferAmount = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        
        vm.prank(user1);
        mockToken.approve(router, transferAmount);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockToken), transferAmount);

        // Execute with deadline and return data
        vm.prank(user1);
        (bool success, bytes memory returnData) = router.call(
            abi.encodeWithSelector(EXECUTE_WITH_DEADLINE_RETURN_SELECTOR, TRANSFER_FROM_COMMAND, inputs, deadline, true)
        );

        assertTrue(success, "Execute with deadline and return data should succeed");
        assertTrue(returnData.length > 0, "Should return data when requested");
    }

    function testLengthMismatchError() public {
        bytes[] memory inputs = new bytes[](2); // Wrong number of inputs
        inputs[0] = abi.encode(address(mockToken), 100e18);
        inputs[1] = abi.encode(address(mockToken), 200e18);

        // Commands only expect 1 input but we provide 2
        bytes memory commands = abi.encodePacked(TRANSFER_FROM_COMMAND[0]);

        vm.prank(user1);
        vm.expectRevert(LengthMismatch.selector);
        IExecutor(router).execute(commands, inputs);
    }

    function testCommandNotFoundError() public {
        bytes memory invalidCommand = abi.encodePacked(uint8(99)); // Non-existent command
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(mockToken), 100e18);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(CommandNotFound.selector, bytes1(uint8(99))));
        IExecutor(router).execute(invalidCommand, inputs);
    }

    function testMultipleCommandsExecution() public {
        uint256 transferAmount1 = 100e18;
        uint256 transferAmount2 = 50e18;
        
        // User1 approves router for both transfers
        vm.prank(user1);
        mockToken.approve(router, transferAmount1 + transferAmount2);

        // Prepare multiple commands
        bytes memory commands = abi.encodePacked(TRANSFER_FROM_COMMAND[0], TRANSFER_FROM_COMMAND[0]);
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(address(mockToken), transferAmount1);
        inputs[1] = abi.encode(address(mockToken), transferAmount2);

        uint256 routerBalanceBefore = mockToken.balanceOf(router);
        uint256 user1BalanceBefore = mockToken.balanceOf(user1);


        // Expect multiple Transfer events
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(user1, router, transferAmount1);
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(user1, router, transferAmount2);

        // Execute multiple commands
        vm.prank(user1);
        (bool success,) = router.call(
            abi.encodeWithSelector(EXECUTE_SELECTOR, commands, inputs)
        );

        assertTrue(success, "Multiple commands should succeed");
        assertEq(
            mockToken.balanceOf(router), 
            routerBalanceBefore + transferAmount1 + transferAmount2, 
            "Router should receive all transferred tokens"
        );
        assertEq(
            mockToken.balanceOf(user1), 
            user1BalanceBefore - transferAmount1 - transferAmount2, 
            "User1 should lose all transferred tokens"
        );
    }

    function testPayableExecuteFunction() public {
        uint256 ethValue = 1 ether;
        
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(router), ethValue);

        // Send ETH with the transaction
        vm.deal(user1, ethValue);
        vm.prank(user1);
        (bool success,) = router.call{value: ethValue}(
            abi.encodeWithSelector(EXECUTE_SELECTOR, TRANSFER_NATIVE_COMMAND, inputs)
        );

        assertTrue(success, "Payable execute should succeed");
        assertEq(router.balance, ethValue, "Router should receive ETH");
    }

    function testEmptyCommandsExecution() public {
        bytes memory emptyCommands = "";
        bytes[] memory emptyInputs = new bytes[](0);

        vm.prank(user1);
        (bool success,) = router.call(
            abi.encodeWithSelector(EXECUTE_SELECTOR, emptyCommands, emptyInputs)
        );

        assertTrue(success, "Empty commands should succeed");
    }
}