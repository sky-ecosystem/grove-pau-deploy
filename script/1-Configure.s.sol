// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { console2 }        from "../lib/forge-std/src/console2.sol";
import { Script, stdJson } from "../lib/forge-std/src/Script.sol";

import { ScriptTools } from "../lib/dss-test/src/ScriptTools.sol";

import { Ethereum } from "../lib/grove-address-registry/src/Ethereum.sol";

import { IAdministeredAgent } from "../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";

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

interface IAccessControlsLike {

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

}

contract ConfigureController is Script {

    using stdJson     for string;
    using ScriptTools for string;

    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

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

        address admin = config.readAddress(".admin");

        require(admin != msg.sender, "ConfigureController/invalid-admin-and-deployer");

        controller    = IMainnetControllerFull(config.readAddress(".controller"));
        oldController = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER);

        IAccessControlsLike accessControls = IAccessControlsLike(controller.accessControls());

        vm.startBroadcast();

        address deployer = msg.sender;

        // Step 1: Update integrations.

        _updateIntegrations();

        console2.log("Integrations updated");

        // Step 2: Migrate max exchange rates.

        _copyERC4626MaxExchangeRate(Ethereum.SUSDS);
        _copyERC4626MaxExchangeRate(Ethereum.SUSDE);

        console2.log("Max exchange rates copied");

        // Step 3: Migrate UniswapV3 pools
        // NOTE : SKIPPED because these pools are not returning a valid config from old controller.
        // _copyUniswapV3PoolConfig(UNISWAP_V3_DAI_USDC_POOL);
        // _copyUniswapV3PoolConfig(UNISWAP_V3_USDC_USDT_POOL);

        console2.log("UniswapV3 pools copied");

        // Step 4: Grant ALLOCATOR_ROLE to administeredAgent.

        address administeredAgent = config.readAddress(".administeredAgent");

        accessControls.grantRole(ALLOCATOR_ROLE, administeredAgent);

        // Step 5: Transfer DEFAULT_ADMIN_ROLE to admin and revoke from deployer.

        accessControls.grantRole(accessControls.DEFAULT_ADMIN_ROLE(),  admin);
        accessControls.revokeRole(accessControls.DEFAULT_ADMIN_ROLE(), deployer);

        // Step 6: Add admins, actors and grantors to administeredAgent.

        IAdministeredAgent(administeredAgent).addActor(config.readAddress(".allocator"));
        IAdministeredAgent(administeredAgent).addActor(config.readAddress(".backstopAllocator"));
        IAdministeredAgent(administeredAgent).addGrantor(config.readAddress(".allocatorAdmin"));
        IAdministeredAgent(administeredAgent).addRevoker(config.readAddress(".allocatorAdmin"));

        // Step 7: Add admin to administeredAgent and remove deployer.

        IAdministeredAgent(administeredAgent).addAdmin(admin);
        IAdministeredAgent(administeredAgent).removeAdmin(deployer);

        console2.log("AccessControls and AdministeredAgent roles configured and transferred");

        vm.stopBroadcast();
    }

    function _copyERC4626MaxExchangeRate(address vault) internal {
        uint256 oldRate = oldController.maxExchangeRates(vault);
        
        controller.erc4626_setMaxExchangeRate(vault, controller.erc4626_EXCHANGE_RATE_PRECISION(), oldRate);

        require(
            controller.erc4626_getMaxExchangeRate(vault) == oldRate,
            "ConfigureController/max-exchange-rate-not-migrated"
        );
    }

    function _copyUniswapV3PoolConfig(address pool) internal {
        // Step 1: Copy max slippages.

        controller.uniswapV3_setMaxSlippage(pool, oldController.maxSlippages(pool));

        // Step 2: Copy pool params.

        IOldMainnetControllerLike.UniswapV3PoolParams memory oldPoolParams = oldController.uniswapV3PoolParams(pool);

        controller.uniswapV3_setMaxTickDelta(pool,            oldPoolParams.swapMaxTickDelta);
        controller.uniswapV3_setLiquidityLowerTickBound(pool, oldPoolParams.addLiquidityTickBounds.lower);
        controller.uniswapV3_setLiquidityUpperTickBound(pool, oldPoolParams.addLiquidityTickBounds.upper);
        controller.uniswapV3_setTWAPSecondsAgo(pool,          oldPoolParams.twapSecondsAgo);
    }

    function _updateIntegrations() internal {
        bytes32[] memory integrationIds = new bytes32[](4);

        integrationIds[0] = "BASIN_FACET";
        integrationIds[1] = "ERC4626_FACET";
        integrationIds[2] = "MAPLE_FACET";
        integrationIds[3] = "UNISWAP_V3_FACET";

        controller.updateIntegrations(integrationIds);
    }

}
