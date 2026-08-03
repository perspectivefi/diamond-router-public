# DiamondRouter

[![License: BSL 1.1](https://img.shields.io/badge/License-BSL%201.1-blue.svg)](https://mariadb.com/bsl11/)

The DiamondRouter is a modular smart contract system designed to replace monolithic routers with a more flexible, upgradeable architecture that optimizes for contract size and extensibility.

## Overview

DiamondRouter is a modular smart contract architecture that replaces traditional monolithic routers with a flexible, upgradeable design. While originally inspired by the concepts in [EIP-2535 Diamonds](https://eips.ethereum.org/EIPS/eip-2535) by Nick Mudge, DiamondRouter has been completely rewritten with its own unique implementation and architecture. Optimized for use with Foundry, DiamondRouter provides:

- **Selective Upgradability**: Update specific contract functions without redeploying the entire codebase
- **Contract Size Optimization**: Overcome Ethereum's 24KB contract size limit by distributing functionality
- **Enhanced Modularity**: Add, replace, or remove functionality without disrupting the main contract
- **Role-Based Access Control**: Secure function access with granular permissions management
- **Native Pausability**: Built-in emergency pause mechanism to halt contract operations when needed

## Table of Contents

# DiamondRouter - Table of Contents

- [Architecture](#architecture)
- [Key Components](#key-components)
- [Technical Deep Dive](#technical-deep-dive)
  - [Function Selector Routing](#function-selector-routing)
  - [Delegate Calls and Context](#delegate-calls-and-context)
  - [Storage Layout and Collisions](#storage-layout-and-collisions)
  - [Pause Mechanism](#pause-mechanism)
  - [Command System Deep Dive](#command-system-deep-dive)
- [Extending Functionality](#extending-functionality)
  - [Adding Functions via FunctionManagerModule](#adding-functions-via-FunctionManagerModule)
  - [Adding Commands via CommandManager](#adding-commands-via-commandmanager)
  - [Finding Available Command IDs](#finding-available-command-ids)
- [Access Control](#access-control)
- [Complete Examples](#complete-examples)
- [Best Practices](#best-practices)
- [References](#references)

## Architecture

DiamondRouter follows a modular architecture that enables functionality to be added through two primary mechanisms:

1. **Functions** (via FunctionManagerModule): Direct function calls on the router
2. **Commands** (via CommandManager): Functionality accessed through the `execute()` method

```
┌─────────────────────────────────┐
│          DiamondRouter          │
├─────────────────┬───────────────┤
│ FunctionManagerModule │ CommandManager│
└─────────────────┴───────────────┘
          ▲                 ▲
          │                 │
┌─────────┴─────┐   ┌───────┴───────┐
│  Function     │   │    Command    │
│Implementations│   │    Modules    │
└───────────────┘   └───────────────┘
```

## Key Components

- **DiamondRouter**: Main contract that delegates calls to appropriate implementations
- **FunctionManagerModule**: Manages direct function implementations with access restrictions
- **CommandManager**: Manages command modules accessible through `execute()`, also access-restricted
- **Execution Module**: Handles the processing of commands through the `execute()` and `executeView()` methods
- **AccessManager**: Controls access permissions for functions and commands
- **PauseManager**: Provides native pause functionality for emergency scenarios


## Technical Deep Dive

This section explains the technical mechanisms behind DiamondRouter for developers new to Solidity proxy patterns and modular contract architectures.

### Function Selector Routing

At its core, DiamondRouter works by intercepting function calls and routing them to appropriate implementation contracts using Solidity's function selectors.

#### What are Function Selectors?

Every function call in Solidity is identified by a 4-byte function selector, which is the first 4 bytes of the keccak256 hash of the function signature:

```solidity
// For function: transfer(address,uint256)
bytes4 selector = bytes4(keccak256("transfer(address,uint256)"));
// Results in: 0xa9059cbb

```

#### How Routing Works

1.  **Call Interception**: When you call `router.myFunction()`, the DiamondRouter's fallback function catches this call
2.  **Selector Extraction**: The router extracts the function selector from `msg.data`
3.  **Implementation Lookup**: The FunctionManagerModule maps selectors to implementation contract addresses
4.  **Delegate Call**: The router performs a `delegatecall` to the implementation contract

```solidity
// Simplified routing logic
fallback() external payable {
    bytes4 selector = bytes4(msg.data);
    address implementation = FunctionManagerModule.getImplementation(selector);
    require(implementation != address(0), "Function not found");
    
    // Delegate call preserves msg.sender and msg.value
    (bool success, bytes memory result) = implementation.delegatecall(msg.data);
    require(success, "Delegate call failed");
    
    // Return the result
    assembly {
        return(add(result, 0x20), mload(result))
    }
}

```

### Delegate Calls and Context

DiamondRouter uses `delegatecall` instead of regular `call` for a crucial reason: **context preservation**.

#### Understanding delegatecall

-   **Regular call**: Executes code in the target contract's context (uses target's storage, msg.sender becomes the caller contract)
-   **Delegatecall**: Executes code in the current contract's context (uses current contract's storage, preserves original msg.sender)

```solidity
// With regular call
contractB.call(data); // Executes in contractB's context, contractB's storage

// With delegatecall  
contractB.delegatecall(data); // Executes contractB's code in current contract's context

```

#### Why This Matters

When you call `router.transfer(recipient, amount)`:

1.  The router delegates to a token implementation contract
2.  The implementation code runs but uses the **router's storage**
3.  `msg.sender` remains the **original caller**, not the router
4.  State changes affect the **router's storage**, creating a unified contract experience

### Storage Layout and Collisions

One of the biggest challenges in proxy patterns is avoiding storage collisions between different implementations.

#### The Problem

```solidity
// Implementation A
contract TokenA {
    uint256 public totalSupply;     // slot 0
    mapping(address => uint256) public balances; // slot 1
}

// Implementation B  
contract TokenB {
    address public owner;           // slot 0 - COLLISION!
    uint256 public totalSupply;     // slot 1 - COLLISION!
}

```

#### DiamondRouter's Solution

DiamondRouter typically uses **Diamond Storage** pattern or **namespaced storage** to avoid collisions (see [EIP-7702](https://eips.ethereum.org/EIPS/eip-7201) explained [here](https://www.rareskills.io/post/erc-7201)):

```solidity
// Diamond Storage pattern
library TokenStorage {
    struct Layout {
        uint256 totalSupply;
        mapping(address => uint256) balances;
        address owner;
    }
    
    // Use a unique hash as storage slot
    bytes32 constant STORAGE_SLOT = keccak256("myproject.token.storage");
    
    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

// Implementation uses diamond storage
contract TokenImplementation {
    function transfer(address to, uint256 amount) external {
        TokenStorage.Layout storage s = TokenStorage.layout();
        require(s.balances[msg.sender] >= amount, "Insufficient balance");
        s.balances[msg.sender] -= amount;
        s.balances[to] += amount;
    }
}

```

### Pause Mechanism

The pause functionality is implemented using a state variable and modifiers:

#### Implementation

```solidity
contract DiamondRouter {
    bool private _paused;
    
    modifier whenNotPaused() {
        require(!_paused, "Contract is paused");
        _;
    }
    
    modifier whenPaused() {
        require(_paused, "Contract is not paused");
        _;
    }
    
    function pause() external onlyRole(PAUSER_ROLE) whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }
    
    function unpause() external onlyRole(PAUSER_ROLE) whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
    
    // All routed functions check pause state
    fallback() external payable whenNotPaused {
        // Routing logic here
    }
}

```

### Command System Deep Dive

The command system provides an additional layer of abstraction:

#### Why Commands vs Direct Functions?

1.  **Parameter Encoding**: Commands can accept complex, encoded parameters
2.  **Batching**: Multiple commands can be batched in a single transaction
3.  **Conditional Logic**: Commands can implement complex conditional execution
4.  **Gas Optimization**: Commands can optimize gas usage through specialized logic

#### Command Processing Flow Simplified

```solidity
function execute(bytes1 commandId, bytes calldata data) external returns (bytes memory) {
    // 1. Look up command implementation
    address commandModule = commandManager.getCommandModule(commandId);
    require(commandModule != address(0), "Command not found");
    
    // 2. Prepare call data
    bytes memory callData = abi.encodeWithSelector(
        ICommandModule.processCommand.selector,
        commandId,
        data
    );
    
    // 3. Delegate to command module
    (bool success, bytes memory result) = commandModule.delegatecall(callData);
    require(success, "Command execution failed");
    
    return result;
}

```

## Extending Functionality

### Adding Functions via FunctionManagerModule

Functions added via the FunctionManagerModule become directly callable on the DiamondRouter contract.

*Note*: While access restrictions apply to the management operations of both systems, the actual functions and commands aren't automatically restricted once added. Each implementation is responsible for incorporating its own access control logic if restrictions are needed.

#### Step 1: Identify Function Selectors

```solidity
// Define function selectors for your implementation
bytes4[] memory yourFunctionSelectors = new bytes4[](2);
yourFunctionSelectors[0] = IYourContract.function1.selector;
yourFunctionSelectors[1] = IYourContract.function2.selector;
```

#### Step 2: Restrict Functions with AccessManager

```solidity
// Set appropriate roles for your functions
setTragetFunctionRole(
    accessManagerAddr,
    diamondRouterAddr,
    yourFunctionSelectors,
    Roles.APPROPRIATE_ROLE // e.g., UPGRADE_ROLE, ADMIN_ROLE
);
```

#### Step 3: Add Functions via FunctionManagerModule

```solidity
addFunctionViaFunctionManager(
    diamondRouterAddr,                // Router address
    yourImplementationAddr,           // Implementation contract
    yourFunctionSelectors,            // Function selectors to add
    initializerAddress,               // Optional: address(0) if not needed
    initializerInputs                 // Optional: empty bytes if not needed
);
```

Once added, these functions can be called directly on the DiamondRouter: `router.function1()`.

*Note*: The function *addFunctionViaFunctionManager* is available in the *deployDiamond.s.sol* script.

### Adding Commands via CommandManager

Commands are accessed indirectly through the router's `execute()` method, allowing for more complex operations.

#### Step 1: Define Command IDs and Function Selectors

```solidity
// Define function selectors for command implementation
bytes4[] memory commandFunctionSelectors = new bytes4[](1);
commandFunctionSelectors[0] = IYourModule.processCommand.selector;

// Define command IDs (as bytes1 values)
bytes memory commandIdsArray = new bytes(2);
commandIdsArray[0] = 0x01; // First command ID
commandIdsArray[1] = 0x02; // Second command ID
```

#### Step 2: Restrict Command Management Functions

```solidity
// Restrict access to command management
bytes4[] memory commandManagerSelectors = new bytes4[](1);
commandManagerSelectors[0] = CommandManager.manageCommands.selector;

AccessManager(accessManager).setTragetFunctionRole(
    accessManagerAddr,
    diamondRouterAddr,
    commandManagerSelectors,
    Roles.UPGRADE_ROLE
);
```

#### Step 3: Add Commands via CommandManager

```solidity
addCommandsViaModuleManager(
    diamondRouterAddr,             // Router address
    moduleImplementationAddr,      // Module implementation 
    commandFunctionSelectors,      // Function selectors for the module
    commandIds,                    // Command IDs this module handles
    initializerAddress,            // Optional: address(0) if not needed
    initializerInputs              // Optional: empty bytes if not needed
);
```

### Step 4: Interacting with Commands

Commands are executed through the router's `execute` methods:

```solidity
// Basic execution (commandId is bytes1)
router.execute(0x01, params);

// With value
router.execute(0x01, params, value);

// View execution (for read-only operations)
router.executeView(0x01, params);

// With returnData flag
router.execute(0x01, params, false);

// With value and returnData flag
router.execute(0x01, params, value, true);
```

### Finding Available Command IDs

If the CommandInfo module is installed, you can query for available command IDs:

```solidity
// Get available command IDs
bytes1[] memory availableIds = ICommandInfo(diamondRouterAddr).findAvailableCommandIds(amount);
```

This returns unique single-byte identifiers (0x00-0xFF) that are not yet assigned to any command.

## Access Control

DiamondRouter uses role-based access control to secure functions and commands:

| Role | Description | Recommended Use |
|------|-------------|----------------|
| `UPGRADE_ROLE` | Modify contract structure | Calling upgradeToAndCall on the proxyAdmin |
| `ADMIN_ROLE` | Complete Access | Avoid direct usage |
| `PAUSER_ROLE` | Emergency controls | Pause/unpause functionality |
| `ROUTER_MANAGER_ROLE` | Add/Replace/Remove functions and commands & delegateCall to arbitrary function | Manage functionalities & intialize the modules |

## Complete Examples

### Adding a Function:

```solidity
// STEP 1: Deploy your implementation contract
address myImplementation = address(new MyImplementation());

// STEP 2: Define function selectors
bytes4[] memory functionSelectors = new bytes4[](1);
functionSelectors[0] = MyImplementation.myFunction.selector;

// STEP 3: Restrict access through AccessManager
setTragetFunctionRole(
    accessManagerAddr,
    diamondRouterAddr,
    functionSelectors,
    Roles.ADMIN_ROLE
);

// STEP 4: Add function to DiamondRouter
addFunctionViaFunctionManager(
    diamondRouterAddr,
    myImplementation,
    functionSelectors,
    address(0),  // No initializer
    ""           // No initialization data
);

// Now myFunction can be called directly on the router
// router.myFunction()
```

### Adding Commands:

```solidity
// STEP 1: Deploy your module implementation
address myModuleImpl = address(new MyCommandModule());

// STEP 2: Define function selectors for the module
bytes4[] memory moduleSelectors = new bytes4[](1);
moduleSelectors[0] = MyCommandModule.processCommand.selector;

// STEP 3: Find available command IDs or choose your own
bytes memory cmdIds = new bytes(1);
cmdIds[0] = 0x42; // Custom command ID (single byte 0x00-0xFF)

// STEP 4: Add module and commands to router
addCommandsViaModuleManager(
    diamondRouterAddr,
    myModuleImpl,
    moduleSelectors,
    cmdIds,
    address(0),  // No initializer
    ""           // No initialization data
);

// Now the command can be executed through the router
// router.execute(0x42, params)
```

## Best Practices

- **Plan Your Architecture**: Design your function and command structure before implementation
- **Test Thoroughly**: Validate all extensions in development environments before production
- **Use Command IDs Consistently**: Document your command ID assignments to avoid conflicts
- **Apply Proper Access Controls**: Always set appropriate roles for security-sensitive functions
- **Consider Gas Optimization**: Group related functionality to minimize cross-contract calls
- **Implement Pause Strategies**: Define clear conditions for pausing and unpausing in emergency situations
- **Document Role Assignments**: Keep clear documentation of which roles can call which functions

## References

- [Original EIP-2535 Diamonds](https://eips.ethereum.org/EIPS/eip-2535) - A conceptual inspiration
- [Nick Mudge's Implementation](https://github.com/mudgen/diamond) - For reference on proxy-based upgradeable systems
- [Foundry Documentation](https://book.getfoundry.sh/) - For integration with the development framework

## Audits

The DiamondRouter was reviewed by [Certora](https://www.certora.com/) in May 2026
as part of the Spectra Bridge assessment. No Critical or High severity issues
were found. See [`audits/`](./audits) for the report and a summary of the
findings that apply to this repository.

## License

The Spectra DiamondRouter is licensed under the Business Source License 1.1
(BUSL-1.1). See [LICENSE](./LICENSE).

The Change License is GNU General Public License v2.0 or later, effective on the
fourth anniversary of the first publicly available distribution of the Licensed
Work under this License.

Some files are derived from third-party work and remain under the MIT License of
their respective authors. These carry an `SPDX-License-Identifier: MIT` header
and are listed in [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).
