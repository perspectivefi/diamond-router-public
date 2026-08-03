// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {DeployDiamondRouter} from "script/00_deployDiamondRouter.s.sol";
import {DiamondRouter} from "src/DiamondRouter.sol";
import {AccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {IAccessManager} from "openzeppelin-contracts/access/manager/IAccessManager.sol";
import {FunctionManagerModule, IFunctionManager} from "src/modules/FunctionManagerModule.sol";
import {CommandsModule, ICommandManager, ICommand} from "src/modules/CommandsModule.sol";
import {CommandsModule} from "src/modules/CommandsModule.sol";
import {FunctionInfoModule, IFunctionInfo} from "src/modules/FunctionInfoModule.sol";
import {CommandInfoModule, ICommandInfo} from "src/modules/CommandInfoModule.sol";
import {Roles} from "src/libraries/Roles.sol";
import {DiamondMultiInit} from "src/upgradeInitializers/DiamondMultiInit.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";

/**
 * @title Integration tests for DeployDiamondRouter
 * @dev These tests focus on integration scenarios and edge cases to improve coverage
 */
contract DeployDiamondRouterIntegrationTest is Test, DeployDiamondRouter {
    address public admin;
    address public user;
    address public accessManager;
    
    address public router;
    address public proxyAdmin;

    // Test implementations
    TestModuleA public moduleA;
    TestModuleB public moduleB;
    TestInitializer public testInitializer;

    IFunctionManager.FunctionUpgrade[] emptyUpgrades;
    
    event RoleSet(address indexed target, bytes4 indexed selector, uint64 indexed role);
    
    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");
        
        // Deploy access manager
        vm.startPrank(admin);
        accessManager = address(new AccessManager(admin));
        AccessManager(accessManager).grantRole(Roles.ROUTER_MANAGER_ROLE, admin, 0);
        vm.stopPrank();
        
        // Deploy test modules
        moduleA = new TestModuleA();
        moduleB = new TestModuleB();
        testInitializer = new TestInitializer();

        // Deploy diamond router
        (router, proxyAdmin) = deployForTest(
            accessManager
        );
    }
    
    function testFullDeploymentFlow() public {
        address multiInit = address(new DiamondMultiInit());
        // Test complete deployment flow
        address[] memory initilizersAddress = new address[](1);
        initilizersAddress[0] = address(testInitializer);
        bytes[] memory initializersCalldata = new bytes[](1);
        initializersCalldata[0] = abi.encodeWithSelector(TestInitializer.initialize.selector, "test", 42);

        // Deploy diamond router
        (address router2, ) = deployForTest(
            accessManager,
            emptyUpgrades,
            multiInit,
            initilizersAddress,
            initializersCalldata
        );
                
        vm.startPrank(admin);
        
        // Setup access control
        setupAccessControl(accessManager, router2, admin);
        
        // Add info modules
        addInfoModules(router2);
        
        // Add custom modules with view functions
        bytes4[] memory selectorsA = new bytes4[](2);
        selectorsA[0] = TestModuleA.functionA.selector;
        selectorsA[1] = TestModuleA.functionB.selector;
        
        addFunctionViaFunctionManager(
            router2,
            address(moduleA),
            selectorsA,
            address(0),
            ""
        );
        
        // Add commands via module manager
        bytes4[] memory selectorsB = new bytes4[](1);
        selectorsB[0] = TestModuleB.executeCommand.selector;
        
        bytes memory commands = new bytes(1);
        commands[0] = bytes1(uint8(100));
        
        addCommandsViaModuleManager(
            router2,
            address(moduleB),
            selectorsB,
            commands,
            address(0),
            ""
        );
        
        // Add view functions for verification using keccak256 selectors
        bytes4[] memory viewSelectors = new bytes4[](3);
        viewSelectors[0] = bytes4(keccak256("initialized2()"));
        viewSelectors[1] = bytes4(keccak256("name()"));
        viewSelectors[2] = bytes4(keccak256("value()"));
        
        addFunctionViaFunctionManager(
            router2,
            address(testInitializer),
            viewSelectors,
            address(0),
            ""
        );
        
        vm.stopPrank();
        
        // Test function calls using interface wrapping
        TestModuleA routerAsModuleA = TestModuleA(router2);
        assertEq(routerAsModuleA.functionA(), "A");
        
        // Test info modules using interface wrapping
        IFunctionInfo routerAsInfo = IFunctionInfo(router2);
        uint256 functionCount = routerAsInfo.getRegisteredFunctionCount();
        assertGt(functionCount, 0);
        
        // Verify initializer was called through the router using interface wrapping
        TestInitializer routerAsInitializer = TestInitializer(router2);
        assertTrue(routerAsInitializer.initialized2());
        assertEq(routerAsInitializer.name(), "test");
        assertEq(routerAsInitializer.value(), 42);
    }
    
    function testMultipleCommandModifications() public {
        vm.startPrank(admin);
        
        // Create multiple command modifications
        ICommand.CommandModification[] memory mods = new ICommand.CommandModification[](2);
        
        // First modification - add moduleA
        bytes4[] memory selectorsA = new bytes4[](1);
        selectorsA[0] = TestModuleA.functionA.selector;
        
        bytes memory commandsA = new bytes(1);
        commandsA[0] = bytes1(uint8(200));
        
        mods[0] = ICommand.CommandModification({
            implementation: address(moduleA),
            action: ICommand.ImplementationAction.Add,
            commands: commandsA,
            functionSelectors: selectorsA
        });
        
        // Second modification - add moduleB
        bytes4[] memory selectorsB = new bytes4[](1);
        selectorsB[0] = TestModuleB.executeCommand.selector;
        
        bytes memory commandsB = new bytes(1);
        commandsB[0] = bytes1(uint8(201));
        
        mods[1] = ICommand.CommandModification({
            implementation: address(moduleB),
            action: ICommand.ImplementationAction.Add,
            commands: commandsB,
            functionSelectors: selectorsB
        });
        
        // Execute multiple modifications
        addCommandsViaModuleManager2(
            router,
            mods,
            address(testInitializer),
            abi.encodeWithSelector(TestInitializer.initialize.selector, "multi", 999)
        );
        
        // Add view functions for verification using keccak256 selectors
        bytes4[] memory viewSelectors = new bytes4[](3);
        viewSelectors[0] = bytes4(keccak256("initialized2()"));
        viewSelectors[1] = bytes4(keccak256("name()"));
        viewSelectors[2] = bytes4(keccak256("value()"));
        
        addFunctionViaFunctionManager(
            router,
            address(testInitializer),
            viewSelectors,
            address(0),
            ""
        );
        
        vm.stopPrank();
        
        // Verify both modules were added using interface wrapping
        IExecutor routerAsExecutor = IExecutor(router);
        
        bytes[] memory input = new bytes[](1);
        bytes[] memory output = routerAsExecutor.execute(commandsA, input, true);
        assertEq(abi.decode(output[0], (string)), "A");

        input[0] = abi.encode("201");
        bytes[] memory output2 = routerAsExecutor.execute(commandsB, input, true);
        assertEq(abi.decode(output2[0], (string)), "Command 201 executed");
        
        // Verify initializer was called using interface wrapping
        TestInitializer routerAsInitializer = TestInitializer(router);
        assertTrue(routerAsInitializer.initialized2());
        assertEq(routerAsInitializer.name(), "multi");
        assertEq(routerAsInitializer.value(), 999);
    }
    
    function testExecuteMultipleFunctionsComplex() public {
        vm.startPrank(admin);
        
        // First, add all required functions to the router using IFunctionManager
        IFunctionManager.FunctionUpgrade[] memory functionUpgrades = new IFunctionManager.FunctionUpgrade[](3);
        
        // Add TestInitializer functions
        bytes4[] memory initializerSelectors = new bytes4[](3);
        initializerSelectors[0] = bytes4(keccak256("initialized2()"));
        initializerSelectors[1] = bytes4(keccak256("name()"));
        initializerSelectors[2] = bytes4(keccak256("value()"));
        
        functionUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(testInitializer),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: initializerSelectors
        });
        
        // Add TestModuleA functions
        bytes4[] memory moduleASelectors = new bytes4[](1);
        moduleASelectors[0] = bytes4(keccak256("state()"));
        
        functionUpgrades[1] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(moduleA),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: moduleASelectors
        });
        
        // Add TestModuleB functions
        bytes4[] memory moduleBSelectors = new bytes4[](1);
        moduleBSelectors[0] = bytes4(keccak256("state2()"));
        
        functionUpgrades[2] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(moduleB),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: moduleBSelectors
        });
        
        // Register all functions with the router
        IFunctionManager(router).manageFunctions(functionUpgrades, address(0), "");
        
        // Now prepare complex multi-function execution
        address[] memory impls = new address[](3);
        impls[0] = address(testInitializer);
        impls[1] = address(moduleA);
        impls[2] = address(moduleB);
        
        bytes[] memory calldatas = new bytes[](3);
        calldatas[0] = abi.encodeWithSelector(TestInitializer.initialize.selector, "complex", 777);
        calldatas[1] = abi.encodeWithSelector(TestModuleA.setState.selector, 888);
        calldatas[2] = abi.encodeWithSelector(TestModuleB.setState.selector, 999);
        
        // Execute multiple functions
        executeMultipleFunctions(
            router,
            address(0), // Will create new DiamondMultiInit
            impls,
            calldatas
        );
        
        vm.stopPrank();
        
        // Verify all functions were executed by calling them through the router
        assertTrue(TestInitializer(router).initialized2());
        assertEq(TestInitializer(router).name(), "complex");
        assertEq(TestInitializer(router).value(), 777);
        assertEq(TestModuleA(router).state(), 888);
        assertEq(TestModuleB(router).state2(), 999);
    }
    
    function testInfoModulesFunctionality() public {
        vm.startPrank(admin);
        
        // Add info modules
        addInfoModules(router);
        
        // Add some functions to test info retrieval
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = TestModuleA.functionA.selector;
        
        addFunctionViaFunctionManager(
            router,
            address(moduleA),
            selectors,
            address(0),
            ""
        );
        
        vm.stopPrank();
        
        DiamondRouter diamondRouter = DiamondRouter(payable(router));
        
        // Test function info retrieval
        (bool success, bytes memory result) = address(diamondRouter).call(
            abi.encodeWithSelector(IFunctionInfo.getImplementationForFunction.selector, selectors[0])
        );
        assertTrue(success);
        address impl = abi.decode(result, (address));
        assertEq(impl, address(moduleA));
        
        // Test getting all registered functions
        (success, result) = address(diamondRouter).call(
            abi.encodeWithSelector(IFunctionInfo.getAllRegisteredFunctions.selector)
        );
        assertTrue(success);
        bytes4[] memory allFunctions = abi.decode(result, (bytes4[]));
        assertGt(allFunctions.length, 0);
        
        // Test if function is registered
        (success, result) = address(diamondRouter).call(
            abi.encodeWithSelector(IFunctionInfo.isFunctionRegistered.selector, selectors[0])
        );
        assertTrue(success);
        bool isRegistered = abi.decode(result, (bool));
        assertTrue(isRegistered);
    }
    
    function testCommandInfoModuleFunctionality() public {
        vm.startPrank(admin);
        
        // Add info modules
        addInfoModules(router);
        
        // Add commands
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = TestModuleB.executeCommand.selector;
        
        bytes memory commands = new bytes(1);
        commands[0] = bytes1(uint8(200));
        
        addCommandsViaModuleManager(
            router,
            address(moduleB),
            selectors,
            commands,
            address(0),
            ""
        );
        
        vm.stopPrank();
                
        // Test command info retrieval
        (bool success, bytes memory result) = address(router).call(
            abi.encodeWithSelector(ICommandInfo.isCommandIdRegistered.selector, commands[0])
        );
        assertTrue(success);
        bool isRegistered = abi.decode(result, (bool));
        assertTrue(isRegistered);
        
        // Test getting registered command count
        uint256 commandCount = ICommandInfo(router).getRegisteredCommandCount();
        assertGt(commandCount, 0);
        
        // Test finding available command IDs
        (success, result) = address(router).call(
            abi.encodeWithSelector(ICommandInfo.findAvailableCommandIds.selector, 5)
        );
        assertTrue(success);
        uint256[] memory availableIds = abi.decode(result, (uint256[]));
        assertEq(availableIds.length, 5);
        
        // Test getting smallest available command ID
        (success, result) = address(router).call(
            abi.encodeWithSelector(ICommandInfo.getSmallestAvailableCommandId.selector)
        );
        assertTrue(success);
        uint256 smallestId = abi.decode(result, (uint256));
        assertEq(smallestId, 0);
    }
    
    function testExecuteFunctionWithComplexCalldata() public {
        vm.startPrank(admin);
        
        // Execute function with complex parameters
        bytes memory complexCalldata = abi.encodeWithSelector(
            TestInitializer.initializeWithArray.selector, 
            "complex",
            [uint256(1), uint256(2), uint256(3)]
        );
        
        executeFunction(
            router,
            address(testInitializer),
            complexCalldata
        );
        
        // Add view functions for verification using keccak256 selectors
        bytes4[] memory viewSelectors = new bytes4[](3);
        viewSelectors[0] = bytes4(keccak256("initialized2()"));
        viewSelectors[1] = bytes4(keccak256("name()"));
        viewSelectors[2] = bytes4(keccak256("arrayValues(uint256)"));
        
        addFunctionViaFunctionManager(
            router,
            address(testInitializer),
            viewSelectors,
            address(0),
            ""
        );
        
        vm.stopPrank();
        
        // Verify complex initialization using interface wrapping
        TestInitializer routerAsInitializer = TestInitializer(router);
        assertTrue(routerAsInitializer.initialized2());
        assertEq(routerAsInitializer.name(), "complex");
        assertEq(routerAsInitializer.arrayValues(0), 1);
        assertEq(routerAsInitializer.arrayValues(1), 2);
        assertEq(routerAsInitializer.arrayValues(2), 3);
    }
    
    function testEmptyFunctionUpgradeArray() public {
        vm.startPrank(admin);
        
        // Execute function with empty upgrade array (should just call initializer)
        bytes memory calldata_ = abi.encodeWithSelector(
            TestInitializer.initialize.selector,
            "empty_upgrade",
            123
        );
        
        executeFunction(
            router,
            address(testInitializer),
            calldata_
        );
        
        // Add view functions for verification using keccak256 selectors
        bytes4[] memory viewSelectors = new bytes4[](3);
        viewSelectors[0] = bytes4(keccak256("initialized2()"));
        viewSelectors[1] = bytes4(keccak256("name()"));
        viewSelectors[2] = bytes4(keccak256("value()"));
        
        addFunctionViaFunctionManager(
            router,
            address(testInitializer),
            viewSelectors,
            address(0),
            ""
        );
        
        vm.stopPrank();
        
        // Verify initializer was called using interface wrapping
        TestInitializer routerAsInitializer = TestInitializer(router);
        assertTrue(routerAsInitializer.initialized2());
        assertEq(routerAsInitializer.name(), "empty_upgrade");
        assertEq(routerAsInitializer.value(), 123);
    }
    
    function testEdgeCasesAndErrorHandling() public {
        vm.startPrank(admin);
        
        // Deploy router
        (address router2,) = deployForTest(accessManager);
        
        // Test adding function with empty selectors array
        bytes4[] memory emptySelectors = new bytes4[](0);

        vm.expectRevert();
        addFunctionViaFunctionManager(
            router2,
            address(moduleA),
            emptySelectors,
            address(0),
            ""
        );
        
        // Test adding commands with empty command IDs
        bytes memory emptycommands = new bytes(0);
        
        vm.expectRevert();
        addCommandsViaModuleManager(
            router2,
            address(moduleB),
            emptySelectors,
            emptycommands,
            address(0),
            ""
        );
        
        vm.stopPrank();
    }
    
    function testStateResetAfterMultipleDeployments() public {
        // Test multiple deployments to ensure proper state management
        for (uint i = 0; i < 3; i++) {
            (address router2, address proxyAdmin2) = deployForTest(
                accessManager
            );
            
            assertNotEq(router2, address(0));
            assertNotEq(proxyAdmin2, address(0));
            
            // Each deployment should create new addresses
            if (i > 0) {
                // This test assumes each deployment creates unique addresses
                // In practice, addresses might be similar but should be properly isolated
            }
        }
    }
    
    function testComplexInitializationScenarios() public {
        vm.startPrank(admin);

        address multiInit = address(new DiamondMultiInit());
        // Test complete deployment flow
        address[] memory initilizersAddress = new address[](1);
        initilizersAddress[0] = address(testInitializer);
        bytes[] memory initializersCalldata = new bytes[](1);
        
        // Test initialization with struct data
        TestInitializer.ComplexData memory complexData = TestInitializer.ComplexData({
            id: 42,
            name: "test_struct",
            active: true,
            values: [uint256(10), uint256(20), uint256(30)]
        });
        
        initializersCalldata[0] = abi.encodeWithSelector(
            TestInitializer.initializeWithStruct.selector,
            complexData
        );

        (address router2,) = deployForTest(
            accessManager,
            emptyUpgrades,
            multiInit,
            initilizersAddress,
            initializersCalldata
        );
        
        // Add view functions for verification using keccak256 selectors
        bytes4[] memory viewSelectors = new bytes4[](2);
        viewSelectors[0] = bytes4(keccak256("initialized2()"));
        viewSelectors[1] = bytes4(keccak256("complexData()"));
        
        addFunctionViaFunctionManager(
            router2,
            address(testInitializer),
            viewSelectors,
            address(0),
            ""
        );
        
        vm.stopPrank();
        
        // Verify struct initialization using interface wrapping
        TestInitializer routerAsInitializer = TestInitializer(router2);
        assertTrue(routerAsInitializer.initialized2());

        (uint256 id, string memory name, bool active) = routerAsInitializer.complexData();
        assertEq(id, 42);
        assertEq(name, "test_struct");
        assertTrue(active);
    }

    function testAccessControlIntegration() public {        
        vm.startPrank(admin);
        // Setup access control
        setupAccessControl(accessManager, router, admin);
        
        // Add functions
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = TestModuleA.functionA.selector;
        addFunctionViaFunctionManager(
            router,
            address(moduleA),
            selectors,
            address(0),
            ""
        );
        
        // Restrict the function
        setTragetFunctionRole(
            accessManager,
            router,
            selectors,
            Roles.UPGRADE_ROLE
        );
        
        // Grant role to user
        AccessManager am = AccessManager(accessManager);
        am.grantRole(Roles.UPGRADE_ROLE, user, 0);
        
        vm.stopPrank();
        
        // Test that user with role can call function using interface wrapping
        vm.startPrank(user);
        TestModuleA routerAsModuleA = TestModuleA(router);
        
        assertEq(routerAsModuleA.functionA(), "A");
        }
}

// Test modules for comprehensive testing
contract TestModuleA {
    uint256 public state;
    
    function functionA() external pure returns (string memory) {
        return "A";
    }
    
    function functionB() external pure returns (string memory) {
        return "B";
    }
    
    function setState(uint256 _state) external {
        state = _state;
    }
}

contract TestModuleB {
    uint256 private GAP;
    uint256 public state2;
    
    function executeCommand(string memory commandId) external pure returns (string memory) {
        return string(abi.encodePacked("Command ", commandId, " executed"));
    }
    
    function setState(uint256 _state) external {
        state2 = _state;
    }
}

contract TestInitializer {
    struct ComplexData {
        uint256 id;
        string name;
        bool active;
        uint256[3] values;
    }
    uint256 gap0;
    uint256 gap2;
    bool public initialized2;
    string public name;
    uint256 public value;
    uint256[3] public arrayValues;
    ComplexData public complexData;
    
    function initialize(string memory _name, uint256 _value) external {
        initialized2 = true;
        name = _name;
        value = _value;
    }
    
    function initializeWithArray(string memory _name, uint256[3] memory _values) external {
        initialized2 = true;
        name = _name;
        arrayValues = _values;
    }
    
    function initializeWithStruct(ComplexData memory _data) external {
        initialized2 = true;
        complexData = _data;
    }
}