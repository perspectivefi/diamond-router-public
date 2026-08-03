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
contract DeployDiamondRouterProductionTest is Test, DeployDiamondRouter {
    address public admin;
    address public accessManager;
    
    // Test implementations for production scenarios
    TestProductionModule public productionModule;
    TestProductionInitializer public productionInitializer;
    DiamondMultiInit public multiInit;
    
   IFunctionManager.FunctionUpgrade[] emptyUpgrades;
    
    function setUp() public {

        // Mock JSON file paths for testing
        configFilePath = "/test/testConstants/00_deployDiamondRouter";
        configFilePrefix = "00_deployDiamondRouter";
        outputFilePath = "/test/testOutput/00_deployDiamondRouter";
        outputFilePrefix = "00_deployDiamondRouter";

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
     * @notice Test generateAndStoreInitializerAddressesAndCalldataForProduction function
     * @dev This tests the JSON config generation for initializer addresses and calldata
     */
    function testGenerateAndStoreInitializerAddressesAndCalldataForProduction() public {
        vm.startPrank(admin);
        
        // Prepare test data for production deployment
        address[] memory initializerAddresses = new address[](2);
        initializerAddresses[0] = address(productionInitializer);
        initializerAddresses[1] = address(productionModule);
        
        bytes[] memory initializerCalldata = new bytes[](2);
        initializerCalldata[0] = abi.encodeWithSelector(
            TestProductionInitializer.initializeProduction.selector,
            "Production Router",
            1000,
            true
        );
        initializerCalldata[1] = abi.encodeWithSelector(
            TestProductionModule.setProductionConfig.selector,
            "config_v1",
            [uint256(100), uint256(200), uint256(300)]
        );
        
        // Call the function to generate and store config
        generateAndStoreInitializerAddressesAndCalldataForProduction(
            address(multiInit),
            initializerAddresses,
            initializerCalldata
        );
        
        vm.stopPrank();
        
        // In a real scenario, this would write to JSON files
        // For testing, we verify the function executes without reverting
        // and that the parameters are properly formatted
        
        // Test with empty arrays (edge case)
        vm.startPrank(admin);
        address[] memory emptyAddresses = new address[](0);
        bytes[] memory emptyCalldata = new bytes[](0);
        
        generateAndStoreInitializerAddressesAndCalldataForProduction(
            address(0), // No multi-init needed for empty case
            emptyAddresses,
            emptyCalldata
        );
        vm.stopPrank();
    }
    
    /**
     * @notice Test generateAndStoreAdditionalFunctionUpgradesForProduction function
     * @dev This tests the JSON config generation for additional function upgrades
     */
    function testGenerateAndStoreAdditionalFunctionUpgradesForProduction() public {
        vm.startPrank(admin);
        
        // Prepare additional function upgrades for production
        IFunctionManager.FunctionUpgrade[] memory additionalUpgrades = 
            new IFunctionManager.FunctionUpgrade[](2);
        
        // First upgrade - Add ProductionModule functions
        bytes4[] memory productionSelectors = new bytes4[](3);
        productionSelectors[0] = TestProductionModule.executeProduction.selector;
        productionSelectors[1] = TestProductionModule.getProductionStatus.selector;
        productionSelectors[2] = TestProductionModule.updateProductionConfig.selector;
        
        additionalUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(productionModule),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: productionSelectors
        });
        
        // Second upgrade - Add another module (simulate multi-module production deployment)
        TestProductionModule secondModule = new TestProductionModule();
        bytes4[] memory secondModuleSelectors = new bytes4[](1);
        secondModuleSelectors[0] = bytes4(keccak256("backupFunction()"));
        
        additionalUpgrades[1] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(secondModule),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: secondModuleSelectors
        });
        
        // Call the function to generate and store additional upgrades config
        generateAndStoreAdditionalFunctionUpgradesForProduction(additionalUpgrades);
        
        vm.stopPrank();
        
        // Test with empty upgrades array (edge case)
        vm.startPrank(admin);
        
        generateAndStoreAdditionalFunctionUpgradesForProduction(emptyUpgrades);
        vm.stopPrank();
    }
    
    /**
     * @notice Test production deployment with complex additional function upgrades
     * @dev Tests multiple modules and complex initialization scenarios
     */
    function testComplexProductionAdditionalFunctionUpgrades() public {
        vm.startPrank(admin);
        
        // Deploy additional test modules for complex scenario
        TestProductionModule moduleB = new TestProductionModule();
        TestProductionModule moduleC = new TestProductionModule();
        
        // Create complex additional function upgrades
        IFunctionManager.FunctionUpgrade[] memory complexUpgrades = 
            new IFunctionManager.FunctionUpgrade[](3);
        
        // Module A upgrades
        bytes4[] memory selectorsA = new bytes4[](2);
        selectorsA[0] = TestProductionModule.executeProduction.selector;
        selectorsA[1] = TestProductionModule.getProductionStatus.selector;
        
        complexUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(productionModule),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectorsA
        });
        
        // Module B upgrades (using keccak256 for unique selectors)
        bytes4[] memory selectorsB = new bytes4[](1);
        selectorsB[0] = bytes4(keccak256("moduleB_function()"));
        
        complexUpgrades[1] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(moduleB),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectorsB
        });
        
        // Module C upgrades
        bytes4[] memory selectorsC = new bytes4[](2);
        selectorsC[0] = bytes4(keccak256("moduleC_function1()"));
        selectorsC[1] = bytes4(keccak256("moduleC_function2()"));
        
        complexUpgrades[2] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(moduleC),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: selectorsC
        });
        
        // Generate and store the complex upgrades
        generateAndStoreAdditionalFunctionUpgradesForProduction(complexUpgrades);
        
        // Test that the function handles complex scenarios without reverting
        // In production, this would write properly formatted JSON
        
        vm.stopPrank();
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
    
/**
     * @notice Test production deployment with realistic complex scenario
     * @dev Simulates a real-world production deployment with multiple modules and initializers
     */
    function testRealisticProductionScenario() public {
        logAddress("accessManager", accessManager);
        console.log("deployed accessManager is ", accessManager);
        saveOutput(configFilePath, configFilePrefix);

        vm.startPrank(admin);
        
        // Deploy multiple production modules (simulating a real system)
        TestProductionModule coreModule = new TestProductionModule();
        TestProductionModule governanceModule = new TestProductionModule();
        TestProductionModule treasuryModule = new TestProductionModule();
        
        // Step 1: Generate and store initializer config
        address[] memory productionInitializers = new address[](3);
        productionInitializers[0] = address(productionInitializer);
        productionInitializers[1] = address(coreModule);
        productionInitializers[2] = address(governanceModule);
        
        bytes[] memory productionCalldata = new bytes[](3);
        productionCalldata[0] = abi.encodeWithSelector(
            TestProductionInitializer.initializeProduction.selector,
            "MainNet Router v2.0",
            10000,
            true
        );
        productionCalldata[1] = abi.encodeWithSelector(
            TestProductionModule.setProductionConfig.selector,
            "core_config",
            [uint256(500), uint256(1000), uint256(1500)]
        );
        productionCalldata[2] = abi.encodeWithSelector(
            TestProductionModule.setProductionConfig.selector,
            "governance_config",
            [uint256(24), uint256(48), uint256(72)] // hours
        );
        
        generateAndStoreInitializerAddressesAndCalldataForProduction(
            address(multiInit),
            productionInitializers,
            productionCalldata
        );
        
        // Step 2: Generate and store additional function upgrades
        IFunctionManager.FunctionUpgrade[] memory productionUpgrades = 
            new IFunctionManager.FunctionUpgrade[](3);
        
        // Core module functions
        bytes4[] memory coreSelectors = new bytes4[](2);
        coreSelectors[0] = TestProductionModule.executeProduction.selector;
        coreSelectors[1] = TestProductionModule.getProductionStatus.selector;
        
        productionUpgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(coreModule),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: coreSelectors
        });
        
        // Governance module functions
        bytes4[] memory governanceSelectors = new bytes4[](1);
        governanceSelectors[0] = bytes4(keccak256("propose(bytes32,bytes)"));
        
        productionUpgrades[1] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(governanceModule),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: governanceSelectors
        });
        
        // Treasury module functions
        bytes4[] memory treasurySelectors = new bytes4[](2);
        treasurySelectors[0] = bytes4(keccak256("deposit(uint256)"));
        treasurySelectors[1] = bytes4(keccak256("withdraw(uint256,address)"));
        
        productionUpgrades[2] = IFunctionManager.FunctionUpgrade({
            implementationAddress: address(treasuryModule),
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: treasurySelectors
        });
        
        generateAndStoreAdditionalFunctionUpgradesForProduction(productionUpgrades);
        
        // Step 3: Use actual production deployment (what run() would do)
        // Call the production deployment that uses _deploy() instead of deployForTest()
        _deploy();

        address mainnetRouter = getAddressFromFile(outputFilePath, outputFilePrefix, ".addresses.diamondRouterAddr");
        
        // Get the proxy admin address from the deployed router
        address mainnetProxyAdmin = getAddressFromFile(outputFilePath, outputFilePrefix, ".addresses.proxyAdminAddr");
        
        // Step 4: Setup access control for production
        setupAccessControl(accessManager, mainnetRouter, mainnetProxyAdmin);
        
        // Step 5: Add production info modules
        addInfoModules(mainnetRouter);
        
        // Step 6: Add view functions for comprehensive verification
        bytes4[] memory allViewSelectors = new bytes4[](7);
        allViewSelectors[0] = bytes4(keccak256("isProductionInitialized()"));
        allViewSelectors[1] = bytes4(keccak256("productionName()"));
        allViewSelectors[2] = bytes4(keccak256("productionValue()"));
        allViewSelectors[3] = bytes4(keccak256("isProductionActive()"));
        allViewSelectors[4] = bytes4(keccak256("configName()"));
        allViewSelectors[5] = bytes4(keccak256("configValues(uint256)"));
        allViewSelectors[6] = bytes4(keccak256("getConfig()"));
        
        addFunctionViaFunctionManager(
            mainnetRouter,
            address(productionInitializer),
            allViewSelectors,
            address(0),
            ""
        );
        
        vm.stopPrank();
        
        // Comprehensive verification of production deployment
        assertNotEq(mainnetRouter, address(0));
        assertNotEq(mainnetProxyAdmin, address(0));
        
        // Verify initialization
        TestProductionInitializer routerAsInit = TestProductionInitializer(mainnetRouter);
        assertTrue(routerAsInit.isProductionInitialized());
        assertEq(routerAsInit.productionName(), "MainNet Router v2.0");
        assertEq(routerAsInit.productionValue(), 10000);
        assertTrue(routerAsInit.isProductionActive());
        
        // Verify core functionality
        TestProductionModule routerAsCore = TestProductionModule(mainnetRouter);
        assertEq(routerAsCore.executeProduction(), "Production executed successfully");
        assertTrue(routerAsCore.getProductionStatus());
        
        // Verify info modules are fully functional
        IFunctionInfo functionInfo = IFunctionInfo(mainnetRouter);
        uint256 totalFunctions = functionInfo.getRegisteredFunctionCount();
        assertGt(totalFunctions, 15); // Should have many functions from all modules
        
        bytes4[] memory allFunctions = functionInfo.getAllRegisteredFunctions();
        assertGt(allFunctions.length, 0);
        
        // Verify all production functions are registered
        assertTrue(functionInfo.isFunctionRegistered(TestProductionModule.executeProduction.selector));
        assertTrue(functionInfo.isFunctionRegistered(TestProductionModule.getProductionStatus.selector));
        
        console.log("Production deployment successful!");
        console.log("Router address:", mainnetRouter);
        console.log("ProxyAdmin address:", mainnetProxyAdmin);
        console.log("Total functions registered:", totalFunctions);
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