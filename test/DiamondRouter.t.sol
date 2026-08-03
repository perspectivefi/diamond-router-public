// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {DiamondRouter} from "src/DiamondRouter.sol";
import {DeployDiamondRouter, AMTransparentUpgradeableProxy, IAMTransparentUpgradeableProxy} from "script/00_deployDiamondRouter.s.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";
import {FunctionManagerModule, IFunctionManager} from "src/modules/FunctionManagerModule.sol";
import {CommandsModule} from "src/modules/CommandsModule.sol";
import {Mock1Module} from "test/modules/MockModules.sol";
import {TransferModule} from "test/modules/TransferModule.sol";
import {Mock1Module} from "test/modules/MockModules.sol";
import {ICommandManager} from "src/interfaces/ICommandManager.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {AccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {LibFunctionManager} from "src/modules/libraries/LibFunctionManager.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {AMProxyAdmin} from "src/proxy/AMProxyAdmin.sol";
import {IRouter} from "src/interfaces/IRouter.sol";
import {DiamondMultiInit} from "src/upgradeInitializers/DiamondMultiInit.sol";


// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DiamondRouterTest is Test {
    address router;
    AccessManager accessManager;
    FunctionManagerModule functionManagerModule;
    CommandsModule commandsModule;  
    TransferModule transferModule;
    MockToken mockToken;
    DeployDiamondRouter deployDiamondRouterScript;
    address proxyAdmin;

   IFunctionManager.FunctionUpgrade[] emptyUpgrades;
    
    // Test accounts
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address unauthorizedUser = makeAddr("unauthorizedUser");
    
    // Role IDs for access management
    uint64 constant PAUSER_ROLE = 1;
    uint64 constant UPGRADER_ROLE = 2;
    uint64 constant FUNCTION_MANAGER_ROLE = 3;
    
    // Events to track
    event Initialized(uint64 version);
    event Paused(address account);
    event Unpaused(address account);
    event TestEvent(address something);
    event FunctionAdded(bytes4 selector, address implementation);
    event FunctionRemoved(bytes4 selector);
    
    // Errors to check
    error InvalidInitialization();
    error NotInitializing();
    error EnforcedPause();
    error AccessManagedUnauthorized(address caller);

    function setUp() public {
        // Setup the accessManager with this contract as initial admin
        accessManager = new AccessManager(address(this));
        
        // Deploy mock token and mint to test accounts
        mockToken = new MockToken();
        mockToken.mint(alice, 1000 * 10**18);
        mockToken.mint(bob, 1000 * 10**18);
        
        // Initialize router with all implementations in one constructor call
        deployDiamondRouterScript = new DeployDiamondRouter();
        (router, proxyAdmin) = deployDiamondRouterScript.deployForTest(address(accessManager));

        accessManager.grantRole(FUNCTION_MANAGER_ROLE, address(deployDiamondRouterScript), 0);

        // Setup modules for testing
        transferModule = new TransferModule();
    }

    function testInitialDeployment() public {
        // Test that router was properly initialized
        assertTrue(router != address(0), "Router should be deployed");
        
        // Use a getter function to verify initialization status
        // Most contracts have an initialized state getter or version getter
        bytes memory versionCall = abi.encodeWithSelector(
            bytes4(keccak256("getInitializedVersion()"))
        );
        
        (bool success, bytes memory result) = router.staticcall(versionCall);
        
        if (!success) {
            // Try alternative getter functions that should exist on initialized contracts
            bytes memory altCall = abi.encodeWithSelector(
                bytes4(keccak256("initialized()"))
            );
            (success, result) = router.staticcall(altCall);
        }
        
        if (!success) {
            // Try checking if access manager is set (indicates initialization)
            bytes memory accessCall = abi.encodeWithSelector(
                bytes4(keccak256("authority()"))
            );
            (success, result) = router.staticcall(accessCall);
            
            if (success && result.length == 32) {
                address authority = abi.decode(result, (address));
                assertEq(authority, address(accessManager), "Authority should be set to access manager");
            }
        }
        
        assertTrue(success, "Should be able to call getter functions on initialized router");
        
        // Verify we cannot call arbitrary functions without proper setup
        bytes memory randomCall = abi.encodeWithSelector(
            bytes4(keccak256("nonExistentFunction()"))
        );
        
        (bool randomSuccess,) = router.call(randomCall);
        assertFalse(randomSuccess, "Random function calls should fail on unConfigured router");
    }

    function testDoubleInitializationFails() public {
        // Try to initialize the router again - it should fail
        vm.expectRevert(InvalidInitialization.selector);
        
        bytes memory reinitCall = abi.encodeWithSelector(
            bytes4(keccak256("initialize()")),
            ""
        );
        
        (bool success,) = router.call(reinitCall);
        assertFalse(success, "Re-initialization should fail");
    }

    function testAccessManagementGrantAndRevokeRoles() public {
        // First, set up function roles for pause functions
        bytes4[] memory pauseSelectors = new bytes4[](2);
        pauseSelectors[0] = bytes4(keccak256("pause()"));
        pauseSelectors[1] = bytes4(keccak256("unPause()"));
        accessManager.setTargetFunctionRole(router, pauseSelectors, PAUSER_ROLE);
        
        // Test granting roles
        accessManager.grantRole(PAUSER_ROLE, alice, 0);
        accessManager.grantRole(UPGRADER_ROLE, bob, 0);
        accessManager.grantRole(FUNCTION_MANAGER_ROLE, alice, 0);
        
        // Test that roles were granted correctly
        (bool hasRole, ) = accessManager.hasRole(PAUSER_ROLE, alice);
        assertTrue(hasRole, "Alice should have pauser role");
        (hasRole, ) = accessManager.hasRole(UPGRADER_ROLE, bob);
        assertTrue(hasRole, "Bob should have upgrader role");
        (hasRole, ) = accessManager.hasRole(FUNCTION_MANAGER_ROLE, alice);
        assertTrue(hasRole, "Alice should have function manager role");
        
        // Test that alice can now call pause (should work)
        vm.startPrank(alice);
        // Expect Paused event
        vm.expectEmit(true, false, false, false);
        emit Paused(alice);
        IRouter(router).pause();
        
        // Unpause for next test
        // Expect Paused event
        vm.expectEmit(true, false, false, false);
        emit Unpaused(alice);
        IRouter(router).unPause();
        vm.stopPrank();
        
        // Test that bob cannot call pause (should fail)
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSelector(AccessManagedUnauthorized.selector, bob));
        IRouter(router).pause();
        vm.stopPrank();
        
        // Test revoking roles
        accessManager.revokeRole(PAUSER_ROLE, alice);
        (hasRole, ) = accessManager.hasRole(PAUSER_ROLE, alice);
        assertTrue(!hasRole, "Alice should not have pauser role after revocation");
        
        // Test that alice can no longer call pause after role revocation (should fail)
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(AccessManagedUnauthorized.selector, alice));
        IRouter(router).pause();
        vm.stopPrank();
    }

    function testAccessManagementSetTargetFunctionRole() public {
        // Set specific function roles for the router
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("pause()"));
        selectors[1] = bytes4(keccak256("unPause()"));
        
        accessManager.setTargetFunctionRole(router, selectors, PAUSER_ROLE);
        
        // Grant role to alice
        accessManager.grantRole(PAUSER_ROLE, alice, 0);
        
        // Test that alice can now call pause
        vm.startPrank(alice);
        IRouter(router).pause();
        vm.stopPrank();
        
        // Test that unauthorized user cannot call pause
        vm.startPrank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(AccessManagedUnauthorized.selector, unauthorizedUser));
        IRouter(router).pause();
        vm.stopPrank();
    }

    function testPauseAndUnpauseFunctionality() public {
        // Grant pause role to alice
        accessManager.grantRole(PAUSER_ROLE, alice, 0);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("pause()"));
        selectors[1] = bytes4(keccak256("unPause()"));
        accessManager.setTargetFunctionRole(router, selectors, PAUSER_ROLE);
        
        // Test pause functionality
        vm.startPrank(alice);
        
        // Expect Paused event
        vm.expectEmit(true, false, false, false);
        emit Paused(alice);
        
        bytes memory pauseCall = abi.encodeWithSelector(bytes4(keccak256("pause()")));
        (bool success,) = router.call(pauseCall);
        assertTrue(success, "Pause should succeed");
        
        // Test that functions are blocked when paused
        bytes memory randomCall = abi.encodeWithSelector(
            bytes4(keccak256("someRandomFunction()")),
            ""
        );
        
        vm.expectRevert(EnforcedPause.selector);
        (success,) = router.call(randomCall);
        
        // Test unpause functionality
        vm.expectEmit(true, false, false, false);
        emit Unpaused(alice);
        
        bytes memory unpauseCall = abi.encodeWithSelector(bytes4(keccak256("unPause()")));
        (success,) = router.call(unpauseCall);
        assertTrue(success, "Unpause should succeed");
        
        // Test that functions work again after unpause
        (success,) = router.call(randomCall);
        // This should not revert with EnforcedPause anymore
        
        vm.stopPrank();
    }

    function testPauseRestrictedAccess() public {
        // Test that unauthorized users cannot pause
        vm.startPrank(unauthorizedUser);
                
        // This should fail due to access control
        vm.expectRevert();
        IRouter(router).pause();
        
        vm.stopPrank();
    }

    function testRouterUpgrade() public {
        // Grant upgrader role to bob
        accessManager.grantRole(UPGRADER_ROLE, bob, 0);
        accessManager.grantRole(PAUSER_ROLE, bob, 0);
        accessManager.grantRole(PAUSER_ROLE, address(proxyAdmin), 0);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("pause()"));
        selectors[1] = bytes4(keccak256("unPause()"));
        accessManager.setTargetFunctionRole(router, selectors, PAUSER_ROLE);
        
        
        // Set upgrader role for the proxy admin
        bytes4[] memory upgradeSelectors = new bytes4[](1);
        upgradeSelectors[0] = AMProxyAdmin.upgradeAndCall.selector;
        accessManager.setTargetFunctionRole(address(proxyAdmin), upgradeSelectors, UPGRADER_ROLE);
        
        // Deploy a new implementation
        DiamondRouter newImplementation = new DiamondRouter();
        
        // Test upgrade functionality
        vm.startPrank(bob);
        
        // Prepare upgrade call
        bytes memory upgradeData = abi.encodeWithSelector(IRouter.pause.selector);
        
        // Call upgrade through proxy admin
        AMProxyAdmin(proxyAdmin).upgradeAndCall(
            IAMTransparentUpgradeableProxy(payable(router)),
            address(newImplementation),
            upgradeData
        );
        
        // Test that the router still works after upgrade
        bytes memory testCall = abi.encodeWithSelector(
            bytes4(keccak256("unPause()")),
            ""
        );
        (bool success,) = router.call(testCall);
        assertTrue(success, "Router should work after upgrade");
        
        vm.stopPrank();
    }

    function testUpgradeRestrictedAccess() public {
        // Deploy a new implementation
        DiamondRouter newImplementation = new DiamondRouter();
        
        // Test that unauthorized users cannot upgrade
        vm.startPrank(unauthorizedUser);
        
        vm.expectRevert();
        AMProxyAdmin(proxyAdmin).upgradeAndCall(
            IAMTransparentUpgradeableProxy(payable(router)),
            address(newImplementation),
            ""
        );
        
        vm.stopPrank();
    }

    function testInitializerEffect() public {
        address multiInit = address(new DiamondMultiInit());
        // Test complete deployment flow
        address[] memory initilizersAddress = new address[](1);        
        bytes[] memory initializersCalldata = new bytes[](1);

        Mock1Module mock1Module = new Mock1Module();
        initilizersAddress[0] = address(mock1Module);
        // Test the transfer module functionality during initialization
        // Since transferFrom can only be called during Diamond initialization,
        // we need to deploy a new router with proper initialization
        
        // Prepare the initializer calldata that will call transferFrom
        initializersCalldata[0] = abi.encodeWithSelector(
            Mock1Module.mock1Func1.selector
        );
        
        // Deploy a new router with TransferModule as initializer
        DeployDiamondRouter deployScript = new DeployDiamondRouter();
                
        // Deploy router with transferFrom in the initializer
        // This should execute transferFrom during initialization
        (address newRouter,) = deployScript.deployForTest(
            address(accessManager),
            emptyUpgrades,
            multiInit,
            initilizersAddress,
            initializersCalldata
        );
                
        assertTrue(newRouter != address(0), "New router should be deployed");

        // Add the mock1Func2 to the router
        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = Mock1Module.mock1Func2.selector;

        // Create IFunctionManager implementation upgrade
        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(mock1Module),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: functionSelectors
        });
        IFunctionManager(newRouter).manageFunctions(upgrades, address(0x0), "");

        assertTrue(Mock1Module(newRouter).mock1Func2() != address(0x0));
        
        // Test that mock1Func1 cannot be called again after initialization
        vm.expectRevert(); 
        Mock1Module(router).mock1Func1(); 
    }

    function testEventEmissions() public {
        // Test that proper events are emitted during various operations
        
        // Test pause event
        accessManager.grantRole(PAUSER_ROLE, alice, 0);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = bytes4(keccak256("pause()"));
        selectors[1] = bytes4(keccak256("unPause()"));
        accessManager.setTargetFunctionRole(router, selectors, PAUSER_ROLE);
        
        vm.startPrank(alice);
        
        // Expect Paused event
        vm.expectEmit(true, false, false, false);
        emit Paused(alice);
        
        IRouter(router).pause();
        
        // Expect Unpaused event
        vm.expectEmit(true, false, false, false);
        emit Unpaused(alice);
        
        IRouter(router).unPause();
        
        vm.stopPrank();
    }

    function testComplexAccessManagementScenario() public {
        // Test a complex scenario with multiple roles and functions
        
        // Setup roles
        accessManager.grantRole(PAUSER_ROLE, alice, 0);
        accessManager.grantRole(UPGRADER_ROLE, bob, 0);
        accessManager.grantRole(FUNCTION_MANAGER_ROLE, alice, 0);
        
        // Set function-specific permissions
        bytes4[] memory pauseSelectors = new bytes4[](2);
        pauseSelectors[0] = bytes4(keccak256("pause()"));
        pauseSelectors[1] = bytes4(keccak256("unPause()"));
        accessManager.setTargetFunctionRole(router, pauseSelectors, PAUSER_ROLE);
        
        bytes4[] memory upgradeSelectors = new bytes4[](1);
        upgradeSelectors[0] = AMProxyAdmin.upgradeAndCall.selector;
        accessManager.setTargetFunctionRole(address(proxyAdmin), upgradeSelectors, UPGRADER_ROLE);
        
        // Test that alice can pause but not upgrade
        vm.startPrank(alice);
        IRouter(router).pause();
        
        // Alice should not be able to upgrade
        DiamondRouter newImpl = new DiamondRouter();

        // Prepare initialization data for the new implementation
        bytes memory initData = "";
        
        vm.expectRevert();
        AMProxyAdmin(proxyAdmin).upgradeAndCall(
            IAMTransparentUpgradeableProxy(payable(router)),
            address(newImpl),
            initData
        );
        vm.stopPrank();
        
        // Test that bob can upgrade but not pause (when unpaused)
        vm.startPrank(alice);
        IRouter(router).unPause();
        vm.stopPrank();
        
        vm.startPrank(bob);
        // Bob should not be able to pause
        vm.expectRevert();
        IRouter(router).pause();
        
        // But bob should be able to upgrade
        AMProxyAdmin(proxyAdmin).upgradeAndCall(
            IAMTransparentUpgradeableProxy(payable(router)),
            address(newImpl),
            initData
        );
        vm.stopPrank();
    }
}

//     function testAddFacet() public {
//         Mock1Module Mock1Module = new Mock1Module();

//         // Create a bytes array with '1' as first byte and '2' as second byte
//         bytes memory _commands = new bytes(2);
//         _commands[0] = 0x01;
//         _commands[1] = 0x02;

//         // Initialize function selectors with proper size
//         bytes4[] memory functionSelectors = new bytes4[](2);
//         functionSelectors[0] = Mock1Module.mock1Func1.selector;
//         functionSelectors[1] = Mock1Module.mock1Func2.selector;
//         addImplementationViaModuleManager(address(Mock1Module), functionSelectors, _commands);

//         // Create inputs array with proper size
//         bytes[] memory _inputs = new bytes[](1);
//         _inputs[0] = "";

//         uint256 _deadline = block.timestamp + 1 weeks;

//         bytes memory commands = new bytes(1);
//         commands[0] = 0x01;

//         // Pass memory variables to router.execute
//         IExecutor(router).execute(commands, _inputs, _deadline);

//         commands[0] = 0x02;
//         bytes[] memory output = IExecutor(router).execute(commands, _inputs, _deadline, true);
//         (address myAddress) = abi.decode(output[0], (address));
//         assertEq(myAddress, address(router));
//     }

//     function testTransferModule() external {
//         // setup the transferModule
//         TransferModule transferModule = new TransferModule();
//         // Create a bytes array with '1' as first byte and '2' as second byte
//         bytes memory _commands = new bytes(2);
//         _commands[0] = 0x01;
//         _commands[1] = 0x02;

//         // Initialize function selectors with proper size
//         bytes4[] memory functionSelectors = new bytes4[](2);
//         functionSelectors[0] = TransferModule.transferFrom.selector;
//         functionSelectors[1] = TransferModule.transferFromWithPermit.selector;
//         addImplementationViaModuleManager(address(transferModule), functionSelectors, _commands);

//         // call for a transferFrom to the router
//         ERC20 myToken = new MyToken("test", "TST");
//         deal(address(myToken), address(this), 1 ether);
//         myToken.approve(address(router), 1 ether);

//         bytes[] memory inputs = new bytes[](1);
//         inputs[0] = abi.encode(address(myToken), 1 ether);
//         bytes memory commands = new bytes(1);
//         commands[0] = 0x01;

//         uint256 deadline = block.timestamp + 1 weeks;

//         IExecutor(router).execute(commands, inputs, deadline);

//         assertEq(myToken.balanceOf(address(router)), 1 ether);
//         // assertEq(OwnershipFacet(address(router)).owner(), address(this));
//     }

//     function addImplementationViaModuleManager(
//         address implementation,
//         bytes4[] memory functionSelectors,
//         bytes memory commandIds
//     ) internal {
//         // Create commandsModule implementation modification
//         ICommand.CommandModification[] memory mods = new ICommand.CommandModification[](1);

//         mods[0] = ICommand.CommandModification(
//             implementation, ICommand.ImplementationAction.Add, commandIds, functionSelectors
//         );

//         // Call manageCommands directly through the ICommandManager interface
//         ICommandManager(router).manageCommands(mods, address(0), "");
//     }
// }

// contract MyToken is ERC20 {
//     constructor(string memory name, string memory ticker) ERC20(name, ticker) {}
// }
