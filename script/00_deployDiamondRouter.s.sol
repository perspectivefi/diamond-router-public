// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import {DiamondRouter} from "src/DiamondRouter.sol";
import {AMProxyAdmin} from "src/proxy/AMProxyAdmin.sol";
import {IAMTransparentUpgradeableProxy, AMTransparentUpgradeableProxy, ERC1967Utils} from "src/proxy/AMTransparentUpgradeableProxy.sol";
import {IExecutor} from "src/interfaces/IExecutor.sol";
import {FunctionManagerModule, IFunctionManager} from "src/modules/FunctionManagerModule.sol";
import {CommandsModule} from "src/modules/CommandsModule.sol";
import {ICommandManager, ICommand} from "src/interfaces/ICommandManager.sol";
import {IFunctionManager} from "src/interfaces/IFunctionManager.sol";
import {AccessManager, IAccessManager} from "openzeppelin-contracts/access/manager/AccessManager.sol";
import {IFunctionManager} from "src/interfaces/IFunctionManager.sol";
import {FunctionInfoModule, IFunctionInfo} from "src/modules/FunctionInfoModule.sol";
import {CommandInfoModule, ICommandInfo} from "src/modules/CommandInfoModule.sol";
import {Roles} from "src/libraries/Roles.sol";
import {DiamondMultiInit} from "src/upgradeInitializers/DiamondMultiInit.sol";
import {SpectraConfigReader} from "config/SpectraConfigReader.s.sol";
import {SpectraConfigWriter} from "config/SpectraConfigWriter.s.sol";

contract DeployDiamondRouter is Script, SpectraConfigReader, SpectraConfigWriter {
    
    string internal configFilePath = "/script/constants/00_deployDiamondRouter";
    string internal configFilePrefix = "00_deployDiamondRouter";
    string internal outputFilePath = "/script/output/00_deployDiamondRouter";
    string internal outputFilePrefix = "00_deployDiamondRouter";

    address private functionManagerModule;
    address private commandsModule;
    address private accessManager;
    address private diamondRouterAddr;
    address private proxyAdminAddr;
    address private routerInitializerImplementation;
    bytes[] internal routerInitializationCalldataArray;
    address[] internal routerInitializationAddressArray;

    bytes4[] private functionManagerSelectors = new bytes4[](1);
    bytes4[] private commandsModuleSelectors = new bytes4[](5);

    bytes internal routerInitializerCalldata;

    IFunctionManager.FunctionUpgrade[] internal functionsUpgrades;

    IFunctionManager.FunctionUpgrade[] internal additionalFunctionsUpgrades;
    address[] internal additionalFunctionsInitializersAddresses;
    bytes[] internal additionalFunctionsCalldata;

    bool private forTest;


/**
 * @dev Simple function to log router initialization arrays
 * @param routerInitializationAddressArray Array of router addresses
 * @param routerInitializationCalldataArray Array of initialization calldata
 */
function logRouterArrays(
    address[] memory routerInitializationAddressArray,
    bytes[] memory routerInitializationCalldataArray
) internal {
    console.log("=== Router Arrays ===");
    console.log("Length:", routerInitializationAddressArray.length);
    
    for (uint256 i = 0; i < routerInitializationAddressArray.length; i++) {
        console.log("Index:", i);
        console.log("Address:", routerInitializationAddressArray[i]);
        console.log("Calldata:");
        console.logBytes(routerInitializationCalldataArray[i]);
        console.log("---");
    }
}

    function run() public virtual {
        vm.startBroadcast();
        _deploy();
        vm.stopBroadcast();
    }

    function _deploy() public returns(address, address) {
        // Define selectors for the modules
        functionManagerSelectors[0] = FunctionManagerModule.manageFunctions.selector;
        commandsModuleSelectors[0] = ICommandManager.manageCommands.selector;
        commandsModuleSelectors[1] = bytes4(keccak256("execute(bytes,bytes[],uint256)"));
        commandsModuleSelectors[2] = bytes4(keccak256("execute(bytes,bytes[])"));
        commandsModuleSelectors[3] = bytes4(keccak256("execute(bytes,bytes[],uint256,bool)"));
        commandsModuleSelectors[4] = bytes4(keccak256("execute(bytes,bytes[],bool)"));

        // For production deployment, load from env variables
        if (!forTest) {
            accessManager = getAddressFromFile(
                configFilePath,
                configFilePrefix,
                "accessManager"
            );

            routerInitializerImplementation = getAddressFromFile(
                configFilePath,
                configFilePrefix,
                "routerInitializerImplementation"
            );

            routerInitializationCalldataArray = getBytesArrayFromFile(
                configFilePath,
                configFilePrefix,
                ".routerInitializationCalldataArray"
                );

            routerInitializationAddressArray = getAddressArrayFromFile(
                configFilePath,
                configFilePrefix,
                ".routerInitializationAddressArray"
                );

            // Check for router initialization values
            bool hasImplementation = routerInitializerImplementation != address(0x0);
            bool hasCalldata = routerInitializationCalldataArray.length > 0;
            
            if (hasImplementation && hasCalldata) {
                // Both values are set - log them               
                console.log("Router initializer implementation:", routerInitializerImplementation);
                console.log("Router initializer calldata length:", routerInitializerCalldata.length);
            } else if (hasImplementation && !hasCalldata) {
                // Implementation is set but calldata is missing - this is an error
                revert(string.concat("routerInitializerCalldata must be set when routerInitializerImplementation is provided"));
            } else {
                // Neither or only calldata is set - continue with defaults
                routerInitializerImplementation = address(0x0);
                routerInitializerCalldata = "";
                console.log("Router initialization values not found, using defaults");
            }
        }

        // Deploy the necessary modules
        functionManagerModule = address(new FunctionManagerModule());
        logAddress("functionManagerModule", functionManagerModule);
        console.log("FunctionManagerModule deployed at", functionManagerModule);

        commandsModule = address(new CommandsModule());
        logAddress("commandsModule", commandsModule);
        console.log("commandsModule deployed at", commandsModule);

        // 1. FunctionManagerModule configuration
        functionsUpgrades.push(IFunctionManager.FunctionUpgrade({
            implementationAddress: functionManagerModule,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: functionManagerSelectors
        }));

        // 2. CommandsModule configuration
        functionsUpgrades.push(IFunctionManager.FunctionUpgrade({
            implementationAddress: commandsModule,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: commandsModuleSelectors
        }));


        // 3. Add the optional functions
        if (!forTest){
            bytes[] memory encodedAdditionalFunctionUpgrades = getBytesArrayFromFile(configFilePath, configFilePrefix, ".additionalFunctionUpgrades");
            for (uint i; i<encodedAdditionalFunctionUpgrades.length; i++){
            functionsUpgrades.push(abi.decode(encodedAdditionalFunctionUpgrades[i], (IFunctionManager.FunctionUpgrade)));
            }
        } else {
            for (uint i; i<additionalFunctionsUpgrades.length; i++){
                functionsUpgrades.push(additionalFunctionsUpgrades[i]);
            }
        }

        // 4. Build the intialization calldata from the arrays (see storage var)

        //routerInitializationAddressArray + additionalFunctionsInitializersAddresses
        for (uint i; i<additionalFunctionsInitializersAddresses.length; i++){
            routerInitializationAddressArray.push(additionalFunctionsInitializersAddresses[i]);
        }
        //routerInitializationCalldataArray + additionalFunctionsCalldata
        for (uint i; i<additionalFunctionsCalldata.length; i++){
            routerInitializationCalldataArray.push(additionalFunctionsCalldata[i]);
        }

        logRouterArrays(routerInitializationAddressArray, routerInitializationCalldataArray);

        routerInitializerCalldata = abi.encodeWithSelector(DiamondMultiInit.multiInit.selector, routerInitializationAddressArray, routerInitializationCalldataArray);

        address routerImplementation = address(new DiamondRouter());
        // Initialize router with all functionsUpgrades
        diamondRouterAddr = payable(
            address(
                new AMTransparentUpgradeableProxy(
                    routerImplementation,
                    accessManager,
                    abi.encodeWithSelector(
                        DiamondRouter.initialize.selector,
                        accessManager,
                        functionsUpgrades,
                        routerInitializerImplementation,
                        routerInitializerCalldata
                    )
                )
            )
        );
        logAddress("diamondRouterAddr", diamondRouterAddr);
        console.log("DiamondRouter deployed at:", diamondRouterAddr);

        delete functionsUpgrades;
        delete routerInitializationAddressArray;
        delete additionalFunctionsUpgrades;
        delete additionalFunctionsInitializersAddresses;
        delete additionalFunctionsCalldata;


        bytes32 adminSlot = vm.load(diamondRouterAddr, ERC1967Utils.ADMIN_SLOT);
        proxyAdminAddr = address(uint160(uint256(adminSlot)));
        logAddress("proxyAdminAddr", proxyAdminAddr);
        
        if (!forTest){
            saveOutput(outputFilePath, outputFilePrefix);
        }
        return (diamondRouterAddr, proxyAdminAddr);
    }

    function setupAccessControl(address _accessManager, address _routerAddr, address _proxyAdmin) public {
        // Set roles for the diamond router functions
        IAccessManager manager = IAccessManager(_accessManager);

        bytes4[] memory _selectors_proxy_admin = new bytes4[](1);
        _selectors_proxy_admin[0] = AMProxyAdmin(address(0)).upgradeAndCall.selector;

        manager.setTargetFunctionRole(
            _proxyAdmin,
            _selectors_proxy_admin,
            Roles.UPGRADE_ROLE
        );

        // Set role for FunctionManagerModule.manageFunctions
        manager.setTargetFunctionRole(_routerAddr, functionManagerSelectors, Roles.ROUTER_MANAGER_ROLE);

        // Set role for ICommandManager.manageCommands
        bytes4[] memory commandsManagementSelector = new bytes4[](1);
        commandsManagementSelector[0] = commandsModuleSelectors[0];
        manager.setTargetFunctionRole(_routerAddr, commandsManagementSelector, Roles.ROUTER_MANAGER_ROLE);

        // Set role for pause and unpause functions
        bytes4[] memory pausableSelectors = new bytes4[](2);
        pausableSelectors[0] = DiamondRouter.pause.selector;
        pausableSelectors[1] = DiamondRouter.unPause.selector;

        manager.setTargetFunctionRole(_routerAddr, pausableSelectors, Roles.PAUSER_ROLE);
    }

    function deployForTest(
        address _accessManager,
        IFunctionManager.FunctionUpgrade[] memory _additionalFunctionsUpgrades,
        address _routerInitializerImplementation,
        address[] memory _routerInitializationAddressArray,
        bytes[] memory _routerInitializationCalldataArray
    ) public returns (address _diamondRouterAddr, address _returnProxyAdminAddr) {
        forTest = true;
        accessManager = _accessManager;

        // Manually copy _additionalFunctionsUpgrades to storage
        delete additionalFunctionsUpgrades;
        for (uint256 i = 0; i < _additionalFunctionsUpgrades.length; i++) {
            additionalFunctionsUpgrades.push(_additionalFunctionsUpgrades[i]);
        }

        routerInitializerImplementation = _routerInitializerImplementation;

        // Manually copy _routerInitializationAddressArray to storage
        delete routerInitializationAddressArray;
        for (uint256 i = 0; i < _routerInitializationAddressArray.length; i++) {
            routerInitializationAddressArray.push(_routerInitializationAddressArray[i]);
        }

        // Manually copy _routerInitializationCalldataArray to storage
        delete routerInitializationCalldataArray;
        for (uint256 i = 0; i < _routerInitializationCalldataArray.length; i++) {
            routerInitializationCalldataArray.push(_routerInitializationCalldataArray[i]);
        }

        _deploy();

        _diamondRouterAddr = diamondRouterAddr;
        _returnProxyAdminAddr = proxyAdminAddr;

        // Reset state for next deployment
        forTest = false;
        accessManager = address(0);
        delete additionalFunctionsUpgrades;
        proxyAdminAddr = address(0);
        routerInitializerImplementation = address(0);
        delete routerInitializationAddressArray;
        delete routerInitializationCalldataArray; 
        diamondRouterAddr = address(0);
        functionManagerModule = address(0);
        commandsModule = address(0);

        return (_diamondRouterAddr, _returnProxyAdminAddr);
    }


    function deployForTest(address _accessManager) public returns (address _diamondRouterAddr, address _returnProxyAdminAddr) {
        forTest = true;
        accessManager = _accessManager;
        routerInitializerImplementation = address(0x0);
        delete routerInitializationAddressArray;
        delete routerInitializationCalldataArray;
        _deploy();

        _diamondRouterAddr = diamondRouterAddr;
        _returnProxyAdminAddr = proxyAdminAddr;

        // Reset state for next deployment
        forTest = false;
        accessManager = address(0);
        proxyAdminAddr = address(0);
        routerInitializerImplementation = address(0);
        delete routerInitializationAddressArray;
        delete routerInitializationCalldataArray; 
        diamondRouterAddr = address(0);
        functionManagerModule = address(0);
        commandsModule = address(0);

        return (_diamondRouterAddr, _returnProxyAdminAddr);
    }

    function generateAndStoreInitializerAddressesAndCalldataForProduction(address multiInitializerAddress, address[] memory _routerInitializationAddressArray, bytes[] memory _routerInitializationCalldataArray) public {
        logAddress("routerInitializerImplementation", multiInitializerAddress);
        logAddressArray("routerInitializationAddressArray", _routerInitializationAddressArray);
        logBytesArray("routerInitializationCalldataArray", _routerInitializationCalldataArray);
        saveOutput(configFilePath, configFilePrefix);
    }

    function generateAndStoreAdditionalFunctionUpgradesForProduction(IFunctionManager.FunctionUpgrade[] memory _additionalFunctionUpgrades) public {
        bytes[] memory encodedFunctionUpgrades = new bytes[](_additionalFunctionUpgrades.length);
        for (uint i; i<_additionalFunctionUpgrades.length; i++){
            encodedFunctionUpgrades[i] = abi.encode(_additionalFunctionUpgrades[i]);
        }
        logBytesArray("additionalFunctionUpgrades", encodedFunctionUpgrades);
        saveOutput(configFilePath, configFilePrefix);
    }


    /**
     * @notice Helper function to add any implementation to the function manager
     * @dev This function facilitates the addition of new function implementations to a router via the FunctionManagerModule.
     *      It supports initializing the implementation with custom data through an initializer contract.
     * @param router Address of the router that contains the function manager
     * @param implementationAddress Address of the implementation contract containing the functions to be added
     * @param functionSelectors Array of function selectors (bytes4) that should be registered from the implementation
     * @param initializerAddress Address of the contract that will initialize the implementation (can be address(0) if no initialization is needed)
     * @param _inputs Encoded initialization data to be passed to the initializer contract
     */
    function addFunctionViaFunctionManager(
        address router,
        address implementationAddress,
        bytes4[] memory functionSelectors,
        address initializerAddress,
        bytes memory _inputs
    ) public {
        // Create IFunctionManager implementation upgrade
        IFunctionManager.FunctionUpgrade[] memory upgrades = new IFunctionManager.FunctionUpgrade[](1);
        upgrades[0] = IFunctionManager.FunctionUpgrade({
            implementationAddress: implementationAddress,
            action: IFunctionManager.FunctionUpgradeAction.Add,
            functionSelectors: functionSelectors
        });

        // Add implementation via IFunctionManager
        IFunctionManager(router).manageFunctions(upgrades, initializerAddress, _inputs);
    }

    /**
     * @notice Helper function to add module's commands to the command/module manager
     * @dev This function registers new module implementations with the CommandManager, connecting function selectors to command IDs.
     *      It also supports initialization through an initializer contract.
     * @param router Address of the router that contains the command/module manager
     * @param implementation Address of the module implementation contract to be added
     * @param functionSelectors Array of function selectors (bytes4) that should be registered from the implementation
     * @param commandIds Encoded array of command IDs that the module will handle
     * @param initializerAddress Address of the contract that will initialize the module (can be address(0) if no initialization is needed)
     * @param _inputs Encoded initialization data to be passed to the initializer contract
     */
    function addCommandsViaModuleManager(
        address router,
        address implementation,
        bytes4[] memory functionSelectors,
        bytes memory commandIds,
        address initializerAddress,
        bytes memory _inputs
    ) public {
        // Create CommandManager implementation modification
        ICommand.CommandModification[] memory mods = new ICommand.CommandModification[](1);

        mods[0] = ICommand.CommandModification(
            implementation, ICommand.ImplementationAction.Add, commandIds, functionSelectors
        );

        // Call manageCommands directly through the ICommandManager interface
        ICommandManager(router).manageCommands(mods, initializerAddress, _inputs);
    }

    function addCommandsViaModuleManager2(
        address router,
        ICommand.CommandModification[] memory mods,
        address initializerAddress,
        bytes memory _inputs
    ) public {
        // Call manageCommands directly through the ICommandManager interface
        ICommandManager(router).manageCommands(mods, initializerAddress, _inputs);
    }

    /**
     * @notice Helper function to restrict access to specific functions by assigning them a role
     * @dev This function sets access control roles for specific functions on a target contract through the AccessManager.
     *      Only accounts with the assigned role will be able to call these functions after restriction.
     * @param _accessManager Address of the AccessManager contract that manages role-based permissions
     * @param router Address of the target contract containing the functions to be restricted
     * @param functionSelectors Array of function selectors (bytes4) that should be restricted
     * @param chosenRole Role ID (uint64) that will be required to call the specified functions (e.g., Roles.UPGRADE_ROLE, Roles.ADMIN_ROLE)
     */
    function setTragetFunctionRole(
        address _accessManager,
        address router,
        bytes4[] memory functionSelectors,
        uint64 chosenRole
    ) public {
        // Set role for your functions
        IAccessManager(_accessManager).setTargetFunctionRole(
            router,
            functionSelectors,
            chosenRole // e.g., Roles.UPGRADE_ROLE, Roles.ADMIN_ROLE, etc.
        );
    }

    /**
    * @notice Add the FunctionInfoModule and CommandInfoModule to the router
    * @param router Address of the DiamondRouter that will receive the info modules
    */
    function addInfoModules(address router) public {
        // Deploy the info modules if not already deployed
        address functionInfoModuleAddr = address(new FunctionInfoModule());
        console.log("FunctionInfoModule deployed at", functionInfoModuleAddr);
        
        address commandInfoModuleAddr = address(new CommandInfoModule());
        console.log("CommandInfoModule deployed at", commandInfoModuleAddr);
        
        // Define selectors for FunctionInfoModule based on IFunctionInfo interface
        bytes4[] memory functionInfoSelectors = new bytes4[](8);
        functionInfoSelectors[0] = IFunctionInfo.getFunctionInfo.selector;
        functionInfoSelectors[1] = IFunctionInfo.getAllFunctionInfo.selector;
        functionInfoSelectors[2] = IFunctionInfo.getFunctionsByImplementation.selector;
        functionInfoSelectors[3] = IFunctionInfo.getImplementationForFunction.selector;
        functionInfoSelectors[4] = IFunctionInfo.getAllFunctionImplementations.selector;
        functionInfoSelectors[5] = IFunctionInfo.getAllRegisteredFunctions.selector;
        functionInfoSelectors[6] = IFunctionInfo.getRegisteredFunctionCount.selector;
        functionInfoSelectors[7] = IFunctionInfo.isFunctionRegistered.selector;
        
        // Define selectors for CommandInfoModule based on ICommandInfo interface
        bytes4[] memory commandInfoSelectors = new bytes4[](10);
        commandInfoSelectors[0] = ICommandInfo.getCommandInfo.selector;
        commandInfoSelectors[1] = ICommandInfo.getAllCommandInfo.selector;
        commandInfoSelectors[2] = ICommandInfo.getCommandsByImplementation.selector;
        commandInfoSelectors[3] = ICommandInfo.getCommandByImplementationAndSelector.selector;
        commandInfoSelectors[4] = ICommandInfo.getAllCommandImplementations.selector;
        commandInfoSelectors[5] = ICommandInfo.findAvailableCommandIds.selector;
        commandInfoSelectors[6] = ICommandInfo.getSmallestAvailableCommandId.selector;
        commandInfoSelectors[7] = ICommandInfo.getAllRegisteredCommands.selector;
        commandInfoSelectors[8] = ICommandInfo.getRegisteredCommandCount.selector;
        commandInfoSelectors[9] = ICommandInfo.isCommandIdRegistered.selector;
        
        // Add FunctionInfoModule to the router using the FunctionManagerModule
        addFunctionViaFunctionManager(
            router,
            functionInfoModuleAddr,
            functionInfoSelectors,
            address(0), // No initializer needed for view/info modules
            "" // No initialization data needed
        );
        console.log("FunctionInfoModule added to router");
        
        // Add CommandInfoModule to the router using the FunctionManagerModule
        addFunctionViaFunctionManager(
            router,
            commandInfoModuleAddr,
            commandInfoSelectors,
            address(0), // No initializer needed for view/info modules
            "" // No initialization data needed
        );
        console.log("CommandInfoModule added to router");
    }

    /// @dev script to execute arbitray delegateCall on a function with the router
    /// @notice avoid the use of this helper function in production (DANGEROUS)
    /// @notice it emits an empty functionUpgraded event
    function executeFunction(address router, address implementation, bytes memory _calldataWithSelector) public {
        IFunctionManager.FunctionUpgrade[] memory _functionUpgrade = new IFunctionManager.FunctionUpgrade[](0);
        IFunctionManager(router).manageFunctions(_functionUpgrade, implementation, _calldataWithSelector);
    }
    // script to execute multiple arbitrary function with the router
    function executeMultipleFunctions(address router, address multiInitContract, address[] memory impls, bytes[] memory _calldataWithSelectors) public {
        if (multiInitContract == address(0x0)){
            multiInitContract = address(new DiamondMultiInit());
        }
        if (impls.length != _calldataWithSelectors.length){
            revert();
        }
        IFunctionManager.FunctionUpgrade[] memory _functionUpgrade = new IFunctionManager.FunctionUpgrade[](0);
        bytes memory _calldata = abi.encodeWithSelector(DiamondMultiInit.multiInit.selector, impls, _calldataWithSelectors);
        IFunctionManager(router).manageFunctions(_functionUpgrade, multiInitContract, _calldata);
    }
}
