// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

/**
 * @title Roles library
 * @author Spectra Finance
 * @notice Identifiers for roles used in Spectra protocol.
 */
library Roles {
    uint64 internal constant ADMIN_ROLE = 0;
    uint64 internal constant UPGRADE_ROLE = 1;
    uint64 internal constant PAUSER_ROLE = 2;
    uint64 internal constant ROUTER_MANAGER_ROLE = 15;
}
