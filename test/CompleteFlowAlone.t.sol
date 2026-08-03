// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {DeployDiamondRouter} from "script/00_deployDiamondRouter.s.sol";
import {DiamondRouter} from "src/DiamondRouter.sol";
import {AccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {IAccessManager} from "openzeppelin-contracts/access/manager/IAccessManager.sol";
import {FunctionManagerModule, IFunctionManager} from "src/modules/FunctionManagerModule.sol";
import {CommandsModule, ICommandManager, ICommand} from "src/modules/CommandsModule.sol";
import {FunctionInfoModule, IFunctionInfo} from "src/modules/FunctionInfoModule.sol";
import {CommandInfoModule, ICommandInfo} from "src/modules/CommandInfoModule.sol";
import {Roles} from "src/libraries/Roles.sol";
import {DiamondMultiInit} from "src/upgradeInitializers/DiamondMultiInit.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";
import {SpectraFileManager} from "test/libraries/SpectraFileManager.sol";

/**
 * @title Production Deployment Tests for DeployDiamondRouter
 * @dev Tests specifically for production deployment scenarios including JSON config generation
 */
contract CompleteFlowAlone is Test, DeployDiamondRouter {
    address public admin;
    address public accessManager;
    
    // Test implementations for production scenarios
    TestProductionModule public productionModule;
    TestProductionInitializer public productionInitializer;
    DiamondMultiInit public multiInit;
    
   IFunctionManager.FunctionUpgrade[] emptyUpgrades;
    
    function setUp() public {

        // Mock JSON file paths for testing
        configFilePath = "/test/testConstants/01_deployDiamondRouter";
        configFilePrefix = "01_deployDiamondRouter";
        outputFilePath = "/test/testOutput/01_deployDiamondRouter";
        outputFilePrefix = "01_deployDiamondRouter";

        SpectraFileManager spectraFileManager = new SpectraFileManager(); 
        spectraFileManager.eraseJsonFileWithPrefix(configFilePath, configFilePrefix, block.chainid);
        eraseContractState();

        admin = makeAddr("admin");
        
        // Setup access manager
        vm.startPrank(admin);
        accessManager = address(new AccessManager(admin));
        AccessManager(accessManager).grantRole(Roles.ROUTER_MANAGER_ROLE, admin, 0);
        vm.stopPrank();
        
        
        // Deploy test contracts
        productionModule = new TestProductionModule();
        productionInitializer = new TestProductionInitializer();
        multiInit = new DiamondMultiInit();
        delete outputBytesArrays;
        delete outputAddressArrays;
        delete outputTransactions;
        delete outputAddresses;
    }

/**
 * @dev Erases all contract state variables
 */
function eraseContractState() internal {   
    // Clear dynamic arrays
    delete routerInitializationCalldataArray;
    delete routerInitializationAddressArray;
    
    // Clear bytes variable
    delete routerInitializerCalldata;
    
    // Clear struct arrays
    delete functionsUpgrades;
    delete additionalFunctionsUpgrades;
    delete additionalFunctionsInitializersAddresses;
    delete additionalFunctionsCalldata;
}
    
    /**
     * @notice Test complete production deployment flow simulation
     * @dev This simulates what would happen when run() is called with proper JSON config
     */
    function testCompleteProductionDeploymentFlow() public {
        logAddress("accessManager", accessManager);
        console.log("deployed accessManager is ", accessManager);
        saveOutput(configFilePath, configFilePrefix);

        vm.startPrank(admin);
        
        // Step 1: Generate and store initializer config
        address[] memory initializerAddresses = new address[](1);
        initializerAddresses[0] = address(productionInitializer);
        
        bytes[] memory initializerCalldata = new bytes[](1);
        initializerCalldata[0] = abi.encodeWithSelector(
            TestProductionInitializer.initializeProduction.selector,
            "Production Router v1.0",
            5000,
            true
        );
        
        generateAndStoreInitializerAddressesAndCalldataForProduction(
            address(multiInit),
            initializerAddresses,
            initializerCalldata
        );
        
        // Step 2: Generate and store additional function upgrades
        IFunctionManager.FunctionUpgrade[] memory additionalUpgrades = 
            new IFunctionManager.FunctionUpgrade[](1);
        
        bytes4[] memory productionSelectors = new bytes4[](2);
        productionSelectors[0] = TestProductionModule.executeProduction.selector;
        productionSelectors[1] = TestProductionModule.getProductionStatus.selector;
        
        additionalUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(productionModule),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: productionSelectors
        });
        
        generateAndStoreAdditionalFunctionUpgradesForProduction(additionalUpgrades);
        
        // Step 3: Use actual production deployment (what run() would do)
        // Call the production deployment that uses _deploy() instead of deployForTest()
        _deploy();

        address productionRouter = getAddressFromFile(outputFilePath, outputFilePrefix, "diamondRouterAddr");
        
        // Get the proxy admin address from the deployed router
        address productionProxyAdmin = getAddressFromFile(outputFilePath, outputFilePrefix, "proxyAdminAddr");
        
        // Step 4: Setup access control for production
        setupAccessControl(accessManager, productionRouter, productionProxyAdmin);
        
        // Step 5: Add production info modules
        addInfoModules(productionRouter);
        
        // Step 6: Add view functions for verification
        bytes4[] memory viewSelectors = new bytes4[](4);
        viewSelectors[0] = bytes4(keccak256("isProductionInitialized()"));
        viewSelectors[1] = bytes4(keccak256("productionName()"));
        viewSelectors[2] = bytes4(keccak256("productionValue()"));
        viewSelectors[3] = bytes4(keccak256("isProductionActive()"));
        
        addFunctionViaFunctionManager(
            productionRouter,
            address(productionInitializer),
            viewSelectors,
            address(0),
            ""
        );
        
        vm.stopPrank();
        
        // Verify production deployment
        assertNotEq(productionRouter, address(0));
        assertNotEq(productionProxyAdmin, address(0));
        
        // Test production functionality through the router
        TestProductionInitializer routerAsInitializer = TestProductionInitializer(productionRouter);
        assertTrue(routerAsInitializer.isProductionInitialized());
        assertEq(routerAsInitializer.productionName(), "Production Router v1.0");
        assertEq(routerAsInitializer.productionValue(), 5000);
        assertTrue(routerAsInitializer.isProductionActive());
        
        // Test production module functionality
        TestProductionModule routerAsModule = TestProductionModule(productionRouter);
        assertEq(routerAsModule.executeProduction(), "Production executed successfully");
        assertTrue(routerAsModule.getProductionStatus());
        
        // Test info modules work in production
        IFunctionInfo functionInfo = IFunctionInfo(productionRouter);
        uint256 functionCount = functionInfo.getRegisteredFunctionCount();
        assertGt(functionCount, 10); // Should have many functions registered
        
        bytes4[] memory allFunctions = functionInfo.getAllRegisteredFunctions();
        assertGt(allFunctions.length, 0);
        
        // Verify specific production functions are registered
        assertTrue(functionInfo.isFunctionRegistered(TestProductionModule.executeProduction.selector));
        assertTrue(functionInfo.isFunctionRegistered(TestProductionModule.getProductionStatus.selector));
        
        console.log("Complete production deployment flow successful!");
        console.log("Router address:", productionRouter);
        console.log("ProxyAdmin address:", productionProxyAdmin);
        console.log("Total functions registered:", functionCount);
    }
    
    /**
     * @notice Test production deployment error handling
     * @dev Tests edge cases and error conditions in production deployment
     */
    function testProductionDeploymentErrorHandling() public {
        vm.startPrank(admin);
        
        // Test with invalid addresses (should handle gracefully)
        address[] memory invalidAddresses = new address[](1);
        invalidAddresses[0] = address(0);
        
        bytes[] memory validCalldata = new bytes[](1);
        validCalldata[0] = abi.encodeWithSelector(
            TestProductionInitializer.initializeProduction.selector,
            "test",
            1,
            false
        );
        
        // This should not revert but should handle the zero address appropriately
        generateAndStoreInitializerAddressesAndCalldataForProduction(
            address(0),
            invalidAddresses,
            validCalldata
        );
        
        // Test mismatched array lengths
        address[] memory mismatchedAddresses = new address[](2);
        mismatchedAddresses[0] = address(productionInitializer);
        mismatchedAddresses[1] = address(productionModule);
        
        bytes[] memory mismatchedCalldata = new bytes[](1); // Length mismatch
        mismatchedCalldata[0] = validCalldata[0];
        
        // In a robust implementation, this should handle the mismatch gracefully
        // or provide appropriate error handling
        generateAndStoreInitializerAddressesAndCalldataForProduction(
            address(multiInit),
            mismatchedAddresses,
            mismatchedCalldata
        );
        
        vm.stopPrank();
    }
}
    
// Production test contracts
contract TestProductionModule {
    struct ProductionConfig {
        string name;
        uint256[3] values;
        bool isActive;
    }
    
    ProductionConfig public config;
    string public configName;
    uint256[3] public configValues;
    
    function executeProduction() external pure returns (string memory) {
        return "Production executed successfully";
    }
    
    function getProductionStatus() external pure returns (bool) {
        return true;
    }
    
    function updateProductionConfig(string memory _name, uint256[3] memory _values) external {
        configName = _name;
        configValues = _values;
    }
    
    function setProductionConfig(string memory _name, uint256[3] memory _values) external {
        configName = _name;
        configValues = _values;
    }
    
    function getConfig() external view returns (string memory, uint256[3] memory) {
        return (configName, configValues);
    }
}

contract TestProductionInitializer {
    bool public isProductionInitialized;
    string public productionName;
    uint256 public productionValue;
    bool public isProductionActive;
    
    function initializeProduction(
        string memory _name,
        uint256 _value,
        bool _active
    ) external {
        isProductionInitialized = true;
        productionName = _name;
        productionValue = _value;
        isProductionActive = _active;
    }
}