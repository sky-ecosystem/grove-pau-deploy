// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { VmSafe } from "../lib/forge-std/src/Vm.sol";

import { IAccessControl }          from "../lib/diamond-pau/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IEnumerableIntegrations } from "../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";

import { AccessControls } from "../lib/diamond-pau/src/AccessControls.sol";
import { Controller }     from "../lib/diamond-pau/src/Controller.sol";

import { Ethereum } from "../lib/grove-address-registry/src/Ethereum.sol";

import { PostDeployTestBase } from "./PostDeployTestBase.t.sol";

contract PostDeployTests is PostDeployTestBase {

    // Paste from script output.
    address internal constant ACCESS_CONTROLS = 0x0000000000000000000000000000000000000000;
    address internal constant CONTROLLER      = 0x0000000000000000000000000000000000000000;
    address internal constant DEPLOYER        = 0x0000000000000000000000000000000000000000;

    // Get from SKY
    address internal constant BEACON = 0x0000000000000000000000000000000000000000;

    address internal constant ADMIN              = Ethereum.GROVE_PROXY;
    address internal constant ALLOCATOR          = Ethereum.ALM_RELAYER;
    address internal constant ALLOCATOR_ADMIN    = Ethereum.ALM_FREEZER;
    address internal constant ALM_PROXY          = Ethereum.ALM_PROXY;
    address internal constant BACKSTOP_ALLOCATOR = Ethereum.GROVE_SECONDARY_RELAYER_OPERATOR;
    address internal constant RATE_LIMITS        = Ethereum.ALM_RATE_LIMITS;

    AccessControls internal accessControls;
    Controller     internal controller;

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, _getBlock());

        accessControls = AccessControls(ACCESS_CONTROLS);
        controller     = Controller(payable(CONTROLLER));
    }

    function _getBlock() internal pure returns (uint256) {
        return 25130165;
    }

    function test_deployState() external {
        // Controller initializes with the correct state.
        assertEq(controller.accessControls(), ACCESS_CONTROLS);
        assertEq(controller.beacon(),         BEACON);
        assertEq(controller.proxy(),          ALM_PROXY);
        assertEq(controller.rateLimits(),     RATE_LIMITS);

        // AccessControls roles
        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,       ALLOCATOR),          true);
        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,       BACKSTOP_ALLOCATOR), true);
        assertEq(accessControls.hasRole(ALLOCATOR_ADMIN_ROLE, ALLOCATOR_ADMIN),    true);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE,   ADMIN),              true);

        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE),   1);
        assertEq(accessControls.getRoleMemberCount(ALLOCATOR_ROLE),       2);
        assertEq(accessControls.getRoleMemberCount(ALLOCATOR_ADMIN_ROLE), 1);

        assertEq(accessControls.getRoleAdmin(ALLOCATOR_ROLE), ALLOCATOR_ADMIN_ROLE); // via setRoleAdmin.

        // DEPLOYER has no roles on AccessControls
        assertEq(accessControls.hasRole(ALLOCATOR_ROLE,       DEPLOYER), false);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE,   DEPLOYER), false);
        assertEq(accessControls.hasRole(ALLOCATOR_ADMIN_ROLE, DEPLOYER), false);
    }

    function test_postDeployEvents() external {
       /*******************************************************************************************/
       /*** AccessControls events                                                               ***/
       /*******************************************************************************************/

        VmSafe.EthGetLogs[] memory accessControlsAllLogs = _getEvents(block.chainid, ACCESS_CONTROLS, "");

        assertEq(accessControlsAllLogs.length, 7);

        // RoleGranted(DEFAULT_ADMIN_ROLE, DEPLOYER, DEPLOYER) from Deploy: AccessControls constructor.
        assertEq(accessControlsAllLogs[0].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(accessControlsAllLogs[0].topics[1],             DEFAULT_ADMIN_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[0].topics[2]), DEPLOYER);
        assertEq(_toAddress(accessControlsAllLogs[0].topics[3]), DEPLOYER);

        // RoleGranted(ALLOCATOR_ROLE, ALLOCATOR, DEPLOYER) from TransferRoles: ALLOCATOR_ROLE grant.
        assertEq(accessControlsAllLogs[1].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(accessControlsAllLogs[1].topics[1],             ALLOCATOR_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[1].topics[2]), ALLOCATOR);
        assertEq(_toAddress(accessControlsAllLogs[1].topics[3]), DEPLOYER);

        // RoleGranted(ALLOCATOR_ROLE, BACKSTOP_ALLOCATOR, DEPLOYER) from TransferRoles: ALLOCATOR_ROLE grant.
        assertEq(accessControlsAllLogs[2].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(accessControlsAllLogs[2].topics[1],             ALLOCATOR_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[2].topics[2]), BACKSTOP_ALLOCATOR);
        assertEq(_toAddress(accessControlsAllLogs[2].topics[3]), DEPLOYER);

        // RoleGranted(ALLOCATOR_ADMIN_ROLE, ALLOCATOR_ADMIN, DEPLOYER) from TransferRoles: ALLOCATOR_ADMIN_ROLE grant.
        assertEq(accessControlsAllLogs[3].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(accessControlsAllLogs[3].topics[1],             ALLOCATOR_ADMIN_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[3].topics[2]), ALLOCATOR_ADMIN);
        assertEq(_toAddress(accessControlsAllLogs[3].topics[3]), DEPLOYER);

        // RoleAdminChanged(ALLOCATOR_ROLE, DEFAULT_ADMIN_ROLE, ALLOCATOR_ADMIN_ROLE) from TransferRoles: setRoleAdmin.
        // From AccessControls.setRoleAdmin.
        assertEq(accessControlsAllLogs[4].topics[0], IAccessControl.RoleAdminChanged.selector);
        assertEq(accessControlsAllLogs[4].topics[1], ALLOCATOR_ROLE);
        assertEq(accessControlsAllLogs[4].topics[2], DEFAULT_ADMIN_ROLE);
        assertEq(accessControlsAllLogs[4].topics[3], ALLOCATOR_ADMIN_ROLE);

        // RoleGranted(DEFAULT_ADMIN_ROLE, ADMIN, DEPLOYER) from TransferRoles: DEFAULT_ADMIN_ROLE grant.
        // Role transfers from deployer to admin.
        assertEq(accessControlsAllLogs[5].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(accessControlsAllLogs[5].topics[1],             DEFAULT_ADMIN_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[5].topics[2]), ADMIN);
        assertEq(_toAddress(accessControlsAllLogs[5].topics[3]), DEPLOYER);

        // RoleRevoked(DEFAULT_ADMIN_ROLE, DEPLOYER, DEPLOYER) from TransferRoles: DEFAULT_ADMIN_ROLE revoke.
        // Role revoked from deployer.
        assertEq(accessControlsAllLogs[6].topics[0],             IAccessControl.RoleRevoked.selector);
        assertEq(accessControlsAllLogs[6].topics[1],             DEFAULT_ADMIN_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[6].topics[2]), DEPLOYER);
        assertEq(_toAddress(accessControlsAllLogs[6].topics[3]), DEPLOYER);

       /*******************************************************************************************/
       /*** Controller events                                                                   ***/
       /*******************************************************************************************/

        // @TODO
    }
}
