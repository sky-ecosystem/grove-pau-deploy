// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { console2 }        from "../lib/forge-std/src/console2.sol";
import { Script, stdJson } from "../lib/forge-std/src/Script.sol";

import { ScriptTools } from "../lib/dss-test/src/ScriptTools.sol";

import { Ethereum } from "../lib/grove-address-registry/src/Ethereum.sol";

import { IMainnetControllerFull } from "../lib/diamond-pau/test/interfaces/IMainnetControllerFull.sol";

interface IOldMainnetControllerLike {

    struct Tick {
        int24 lower;
        int24 upper;
    }

    struct UniswapV3PoolParams {
        uint24 swapMaxTickDelta;
        Tick   addLiquidityTickBounds;
        uint32 twapSecondsAgo;
    }

    function maxExchangeRates(address vault) external view returns (uint256 maxExchangeRate);

    function maxSlippages(address pool) external view returns (uint256 maxSlippage);

    function uniswapV3PoolParams(address pool) external view returns (UniswapV3PoolParams memory);

}

contract ConfigureController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    address internal constant UNISWAP_V3_DAI_USDC_POOL  = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;
    address internal constant UNISWAP_V3_USDC_USDT_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;

    IMainnetControllerFull    internal controller;
    IOldMainnetControllerLike internal oldController;

    function run() external {
        string memory chain = vm.envOr("CHAIN", string("mainnet"));

        vm.createSelectFork(getChain(chain).rpcUrl);

        vm.setEnv("FOUNDRY_ROOT_CHAINID", vm.toString(block.chainid));

        string memory env      = vm.envString("ENV");
        string memory fileSlug = string(abi.encodePacked("config-", chain, "-", env));
        string memory config   = ScriptTools.loadConfig(fileSlug);

        require(block.chainid == config.readUint(".chainId"), "ConfigureController/invalid-chain-id");

        controller    = IMainnetControllerFull(config.readAddress(".controller"));
        oldController = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER);

        vm.startBroadcast();

        // Step 1: Update integrations.

        _updateIntegrations();

        console2.log("Integrations updated");

        // Step 2: Migrate max exchange rates.

        _migrateERC4626MaxExchangeRates(Ethereum.SUSDS, 10);
        _migrateERC4626MaxExchangeRates(Ethereum.SUSDE, 10);

        console2.log("Max exchange rates migrated");

        // Step 3: Migrate UniswapV3 pools

        _migrateUniswapV3Pool(UNISWAP_V3_DAI_USDC_POOL);
        _migrateUniswapV3Pool(UNISWAP_V3_USDC_USDT_POOL);

        console2.log("UniswapV3 pools migrated");

        vm.stopBroadcast();
    }

    // @NOTE: Hardcoded integration IDs. Update this function to read from the config file if new integrations are added.
    function _updateIntegrations() internal {
        bytes32[] memory integrationIds = new bytes32[](4);

        integrationIds[0] = bytes32(keccak256(abi.encodePacked(".integrationIds.basinFacet")));
        integrationIds[1] = bytes32(keccak256(abi.encodePacked(".integrationIds.erc4626Facet")));
        integrationIds[2] = bytes32(keccak256(abi.encodePacked(".integrationIds.mapleFacet")));
        integrationIds[3] = bytes32(keccak256(abi.encodePacked(".integrationIds.uniswapV3Facet")));

        controller.updateIntegrations(integrationIds);
    }

    function _migrateERC4626MaxExchangeRates(address vault, uint256 rate) internal {
        controller.erc4626_setMaxExchangeRate(vault, 1, rate);

        require(
            controller.erc4626_getMaxExchangeRate(vault) == oldController.maxExchangeRates(vault),
            "ConfigureController/max-exchange-rate-not-migrated"
        );
    }

    function _migrateUniswapV3Pool(address pool) internal {
        // Step 1: Migrate max slippages.

        controller.uniswapV3_setMaxSlippage(pool, oldController.maxSlippages(pool));

        // Step 2: Migrate pool params.

        IOldMainnetControllerLike.UniswapV3PoolParams memory oldPoolParams = oldController.uniswapV3PoolParams(pool);

        controller.uniswapV3_setMaxTickDelta(pool,            oldPoolParams.swapMaxTickDelta);
        controller.uniswapV3_setLiquidityLowerTickBound(pool, oldPoolParams.addLiquidityTickBounds.lower);
        controller.uniswapV3_setLiquidityUpperTickBound(pool, oldPoolParams.addLiquidityTickBounds.upper);
        controller.uniswapV3_setTWAPSecondsAgo(pool,          oldPoolParams.twapSecondsAgo);
    }

}
