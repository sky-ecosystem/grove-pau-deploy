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

    struct IntegrationIds {
        bytes32 aaveFacet;
        bytes32 basinFacet;
        bytes32 cctpFacet;
        bytes32 centrifugeFacet;
        bytes32 curveFacet;
        bytes32 daiUsdsFacet;
        bytes32 erc4626Facet;
        bytes32 erc7540Facet;
        bytes32 ethenaFacet;
        bytes32 farmFacet;
        bytes32 layerZeroFacet;
        bytes32 mapleFacet;
        bytes32 merklFacet;
        bytes32 otcFacet;
        bytes32 pendleFacet;
        bytes32 psmFacet;
        bytes32 psm3Facet;
        bytes32 sparkVaultFacet;
        bytes32 superstateFacet;
        bytes32 transferAssetFacet;
        bytes32 uniswapV3Facet;
        bytes32 uniswapV4Facet;
        bytes32 usdsFacet;
        bytes32 weethFacet;
        bytes32 wrapProxyETHFacet;
        bytes32 wstethFacet;
    }

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

        _updateIntegrations(config);

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

    function _updateIntegrations(string memory config) internal {
        IntegrationIds memory allIntegrationIds = _readIntegrationIds(config);

        bytes32[] memory integrationIds = new bytes32[](config.readUint(".integrationIds.length"));

        bytes32 emptyIntegrationId = bytes32(keccak256(abi.encodePacked("")));

        uint256 i;

        if (allIntegrationIds.aaveFacet          != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.aaveFacet;
        if (allIntegrationIds.cctpFacet          != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.cctpFacet;
        if (allIntegrationIds.centrifugeFacet    != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.centrifugeFacet;
        if (allIntegrationIds.curveFacet         != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.curveFacet;
        if (allIntegrationIds.daiUsdsFacet       != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.daiUsdsFacet;
        if (allIntegrationIds.erc4626Facet       != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.erc4626Facet;
        if (allIntegrationIds.erc7540Facet       != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.erc7540Facet;
        if (allIntegrationIds.ethenaFacet        != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.ethenaFacet;
        if (allIntegrationIds.farmFacet          != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.farmFacet;
        if (allIntegrationIds.layerZeroFacet     != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.layerZeroFacet;
        if (allIntegrationIds.mapleFacet         != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.mapleFacet;
        if (allIntegrationIds.merklFacet         != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.merklFacet;
        if (allIntegrationIds.otcFacet           != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.otcFacet;
        if (allIntegrationIds.pendleFacet        != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.pendleFacet;
        if (allIntegrationIds.psmFacet           != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.psmFacet;
        if (allIntegrationIds.psm3Facet          != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.psm3Facet;
        if (allIntegrationIds.sparkVaultFacet    != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.sparkVaultFacet;
        if (allIntegrationIds.superstateFacet    != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.superstateFacet;
        if (allIntegrationIds.transferAssetFacet != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.transferAssetFacet;
        if (allIntegrationIds.uniswapV3Facet     != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.uniswapV3Facet;
        if (allIntegrationIds.uniswapV4Facet     != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.uniswapV4Facet;
        if (allIntegrationIds.usdsFacet          != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.usdsFacet;
        if (allIntegrationIds.weethFacet         != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.weethFacet;
        if (allIntegrationIds.wrapProxyETHFacet  != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.wrapProxyETHFacet;
        if (allIntegrationIds.wstethFacet        != emptyIntegrationId) integrationIds[i++] = allIntegrationIds.wstethFacet;

        require(i + 1 == config.readUint(".integrationIds.length"), "ConfigureController/invalid-number-of-facets");

        controller.updateIntegrations(integrationIds);
    }

    function _readIntegrationIds(
        string memory config
    ) internal pure returns (IntegrationIds memory integrationIds) {
        integrationIds.aaveFacet          = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.aaveFacet"))));
        integrationIds.cctpFacet          = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.cctpFacet"))));
        integrationIds.centrifugeFacet    = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.centrifugeFacet"))));
        integrationIds.curveFacet         = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.curveFacet"))));
        integrationIds.daiUsdsFacet       = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.daiUsdsFacet"))));
        integrationIds.erc4626Facet       = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.erc4626Facet"))));
        integrationIds.erc7540Facet       = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.erc7540Facet"))));
        integrationIds.farmFacet          = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.farmFacet"))));
        integrationIds.layerZeroFacet     = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.layerZeroFacet"))));
        integrationIds.mapleFacet         = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.mapleFacet"))));
        integrationIds.merklFacet         = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.merklFacet"))));
        integrationIds.otcFacet           = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.otcFacet"))));
        integrationIds.pendleFacet        = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.pendleFacet"))));
        integrationIds.psmFacet           = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.psmFacet"))));
        integrationIds.psm3Facet          = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.psm3Facet"))));
        integrationIds.sparkVaultFacet    = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.sparkVaultFacet"))));
        integrationIds.superstateFacet    = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.superstateFacet"))));
        integrationIds.transferAssetFacet = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.transferAssetFacet"))));
        integrationIds.uniswapV3Facet     = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.uniswapV3Facet"))));
        integrationIds.uniswapV4Facet     = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.uniswapV4Facet"))));
        integrationIds.ethenaFacet        = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.ethenaFacet"))));
        integrationIds.usdsFacet          = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.usdsFacet"))));
        integrationIds.weethFacet         = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.weethFacet"))));
        integrationIds.wrapProxyETHFacet  = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.wrapProxyETHFacet"))));
        integrationIds.wstethFacet        = bytes32(keccak256(abi.encodePacked(config.readString(".integrationIds.wstethFacet"))));
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
