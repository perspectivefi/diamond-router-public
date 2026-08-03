// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

contract SpectraFileManager is Script, Test {
    
    /**
     * @dev Erases (deletes) a JSON file at the specified path
     * @param filePath The full path to the JSON file to be erased
     * @notice This function uses vm.removeFile() which is only available in Forge test/script environment
     */
    function eraseJsonFile(string memory filePath) public {
        // Use Forge's vm.removeFile to delete the file
        // This will silently fail if the file doesn't exist
        try vm.removeFile(filePath) {
            // File successfully removed
        } catch {
            // File might not exist or removal failed
            // In most cases, we want to continue execution
        }
    }

    /**
     * @dev Erases a JSON file using directory path and prefix (following your existing pattern)
     * @param directoryPath The directory path where the file is located
     * @param prefix The prefix for the filename
     * @param chainid The chain ID to determine the chain name
     */
    function eraseJsonFileWithPrefix(
        string memory directoryPath, 
        string memory prefix, 
        uint256 chainid
    ) external {
        string memory filePath = getFilePathWithPrefix(directoryPath, prefix, chainid);
        eraseJsonFile(filePath);
    }

    // Helper functions from your original contract (copied for library completeness)
    function getChainName(uint256 chainid) internal pure returns (string memory) {
        if (chainid == 1) {
            return "mainnet";
        } else if (chainid == 10) {
            return "optimism";
        } else if (chainid == 8453) {
            return "base";
        } else if (chainid == 42161) {
            return "arbitrum";
        } else if (chainid == 146) {
            return "sonic";
        } else if (chainid == 43111) {
            return "hemi";
        } else if (chainid == 43114) {
            return "avax";
        } else if (chainid == 56) {
            return "bsc";
        } else if (chainid == 999) {
            return "hyperevm";
        } else if (chainid == 31337) {
            return "local";
        } else if (chainid == 747474) {
            return "katana";
        } else {
            revert("UnsupportedChain");
        }
    }

    function _ensureTrailingSlash(string memory path) internal pure returns (string memory) {
        bytes memory pathBytes = bytes(path);
        if (pathBytes.length == 0) return "/";
        if (pathBytes[pathBytes.length - 1] == "/") return path;
        return string.concat(path, "/");
    }

    function _ensureLeadingSlash(string memory path) internal pure returns (string memory) {
        bytes memory pathBytes = bytes(path);
        if (pathBytes.length == 0) return "/";
        if (pathBytes[0] == "/") return path;
        return string.concat("/", path);
    }

    function getFilePathWithPrefix(
        string memory directoryPath, 
        string memory prefix, 
        uint256 chainid
    ) internal view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory basePath = string.concat(root, _ensureLeadingSlash(_ensureTrailingSlash(directoryPath)));
        string memory fileName = string.concat(getChainName(chainid), ".json");
        string memory path = string.concat(basePath, prefix, "-", fileName);
        return path;
    }
}