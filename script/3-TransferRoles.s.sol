// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { console2 }        from "../lib/forge-std/src/console2.sol";
import { Script, stdJson } from "../lib/forge-std/src/Script.sol";

import { ScriptTools } from "../lib/dss-test/src/ScriptTools.sol";

interface IAccessControlsLike {

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;

    function revokeRole(bytes32 role, address account) external;

}

contract TransferRoles is Script {

    using stdJson     for string;
    using ScriptTools for string;

    bytes32 internal constant ALLOCATOR_ROLE       = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant ALLOCATOR_ADMIN_ROLE = keccak256("ALLOCATOR_ADMIN_ROLE");

    function run() external {
        string memory chain = vm.envOr("CHAIN", string("mainnet"));

        vm.createSelectFork(getChain(chain).rpcUrl);

        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        string memory env      = vm.envString("ENV");
        string memory fileSlug = string(abi.encodePacked("transfer-", chain, "-", env));
        string memory config   = ScriptTools.loadConfig(fileSlug);

        require(block.chainid == config.readUint(".chainId"), "TransferRoles/Invalid chain ID");

        address admin = config.readAddress(".admin");

        require(admin != msg.sender, "TransferRoles/Invalid admin and deployer");

        vm.startBroadcast();

        IAccessControlsLike accessControls = IAccessControlsLike(config.readAddress(".accessControls"));

        // Step 1: Grant roles to allocator, backstopAllocator and allocatorAdmin.

        accessControls.grantRole(ALLOCATOR_ROLE,       config.readAddress(".allocator"));
        accessControls.grantRole(ALLOCATOR_ROLE,       config.readAddress(".backstopAllocator"));
        accessControls.grantRole(ALLOCATOR_ADMIN_ROLE, config.readAddress(".allocatorAdmin"));

        // Step 2: Set role admin for ALLOCATOR_ROLE to ALLOCATOR_ADMIN_ROLE.

        accessControls.setRoleAdmin(ALLOCATOR_ROLE, ALLOCATOR_ADMIN_ROLE);

        // Step 3: Transfer DEFAULT_ADMIN_ROLE to admin and revoke from deployer.

        accessControls.grantRole(accessControls.DEFAULT_ADMIN_ROLE(),  admin);
        accessControls.revokeRole(accessControls.DEFAULT_ADMIN_ROLE(), msg.sender);

        console2.log("Roles transferred");

        vm.stopBroadcast();

    }

}
