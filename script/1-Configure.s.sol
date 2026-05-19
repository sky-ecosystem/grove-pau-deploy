// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { console2 }        from "../lib/forge-std/src/console2.sol";
import { Script, stdJson } from "../lib/forge-std/src/Script.sol";

import { ScriptTools } from "../lib/dss-test/src/ScriptTools.sol";

interface IControllerLike {
 
    function updateIntegrations(IntegrationIds memory integrationIds) external;

}

contract ConfigureController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    struct IntegrationIds {
        bytes32 basinFacet;
        bytes32 erc4626Facet;
        bytes32 mapleFacet;
        bytes32 uniswapV3Facet;
    }

    address internal controller;

    function run() external {
        string memory chain = vm.envOr("CHAIN", string("mainnet"));

        vm.createSelectFork(getChain(chain).rpcUrl);

        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        string memory env      = vm.envString("ENV");
        string memory fileSlug = string(abi.encodePacked("config-", chain, "-", env));
        string memory config   = ScriptTools.loadConfig(fileSlug);

        require(block.chainid == config.readUint(".chainId"), "ConfigureController/Invalid chain ID");

        controller = config.readAddress(".controller");

        vm.startBroadcast();

        // Step 1: Update integrations.

        _updateIntegrations();

        console2.log("Integrations updated");

        vm.stopBroadcast();
    }

    function _updateIntegrations() internal {
        IntegrationIds memory integrationIds = _getIntegrationIds();

        controller.updateIntegrations(integrationIds);
    }

    // @NOTE: Hardcoded integration IDs. Update this function to read from the config file if new integrations are added.
    function _getIntegrationIds() internal pure returns (IntegrationIds memory integrationIds) {
        integrationIds.basinFacet     = bytes32(keccak256(abi.encodePacked(".integrationIds.basinFacet")));
        integrationIds.erc4626Facet   = bytes32(keccak256(abi.encodePacked(".integrationIds.erc4626Facet")));
        integrationIds.mapleFacet     = bytes32(keccak256(abi.encodePacked(".integrationIds.mapleFacet")));
        integrationIds.uniswapV3Facet = bytes32(keccak256(abi.encodePacked(".integrationIds.uniswapV3Facet")));
    }
}
