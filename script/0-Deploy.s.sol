// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { console2 }        from "../lib/forge-std/src/console2.sol";
import { Script, stdJson } from "../lib/forge-std/src/Script.sol";

import { ScriptTools } from "../lib/dss-test/src/ScriptTools.sol";

import { AccessControls } from "../lib/diamond-pau/src/AccessControls.sol";
import { Controller }     from "../lib/diamond-pau/src/Controller.sol";

contract DeployAccessControlsAndController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    function run() external {
        string memory chain = vm.envOr("CHAIN", string("mainnet"));

        vm.createSelectFork(getChain(chain).rpcUrl);

        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        string memory env      = vm.envString("ENV");
        string memory fileSlug = string(abi.encodePacked("deploy-", chain, "-", env));
        string memory config   = ScriptTools.loadConfig(fileSlug);

        require(block.chainid == config.readUint(".chainId"), "DeployAccessControlsAndController/Invalid chain ID");

        vm.startBroadcast();

        // Step 1: Deploy AccessControls contract.
        //         Deployer as the temporary admin to run configuration script.
        address accessControls = address(new AccessControls({
            admin: config.readAddress(".deployer")
        }));

        console2.log("AccessControls deployed at: ", accessControls);

        // Step 2: Deploy Controller contract.

        address controller = address(new Controller({
            accessControls_ : accessControls,
            beacon_         : config.readAddress(".beacon"),
            proxy_          : config.readAddress(".proxy"),
            rateLimits_     : config.readAddress(".rateLimits")
        }));

        console2.log("Controller deployed at: ", controller);

        vm.stopBroadcast();

        ScriptTools.exportContract(fileSlug, "accessControls", address(accessControls));
        ScriptTools.exportContract(fileSlug, "controller",     address(controller));
    }

}
