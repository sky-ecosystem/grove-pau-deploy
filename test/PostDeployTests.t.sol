// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { VmSafe } from "../lib/forge-std/src/Vm.sol";

import { IAccessControl }                 from "../lib/diamond-pau/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IEnumerableIntegrations as IEI } from "../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";
import { IMainnetControllerFull }         from "../lib/diamond-pau/test/interfaces/IMainnetControllerFull.sol";

import { AccessControls } from "../lib/diamond-pau/src/AccessControls.sol";
import { Beacon }         from "../lib/diamond-pau/src/Beacon.sol";

import { IERC4626Facet }   from "../lib/diamond-pau/src/facets/erc4626/IERC4626Facet.sol";
import { IUniswapV3Facet } from "../lib/diamond-pau/src/facets/uniswap-v3/IUniswapV3Facet.sol";

import { Ethereum } from "../lib/grove-address-registry/src/Ethereum.sol";

import { PostDeployTestBase } from "./PostDeployTestBase.t.sol";

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

    address internal constant UNISWAP_V3_DAI_USDC_POOL  = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;
    address internal constant UNISWAP_V3_USDC_USDT_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;

    AccessControls         internal accessControls;
    Beacon                 internal beacon;
    IMainnetControllerFull internal controller;

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, _getBlock());

        accessControls = AccessControls(ACCESS_CONTROLS);
        beacon         = Beacon(BEACON);
        controller     = IMainnetControllerFull(payable(CONTROLLER));
    }

    function _getBlock() internal pure returns (uint256) {
        return 25130165;
    }

    function test_deployState() external {
       /*******************************************************************************************/
       /*** AccessControls post deploy state                                                    ***/
       /*******************************************************************************************/

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

       /*******************************************************************************************/
       /*** Controller post deploy state                                                        ***/
       /*******************************************************************************************/

        // Constructor initializes with the correct state.
        assertEq(controller.accessControls(), ACCESS_CONTROLS);
        assertEq(controller.beacon(),         BEACON);
        assertEq(controller.proxy(),          ALM_PROXY);
        assertEq(controller.rateLimits(),     RATE_LIMITS);

        // Configurations: updateIntegrations.

        IEI.Integration[] memory integrations = controller.integrations();

        assertEq(integrations.length, 4);

        assertEq(integrations[0].id, bytes32(keccak256(abi.encodePacked("BASIN_FACET"))));
        assertEq(integrations[1].id, bytes32(keccak256(abi.encodePacked("OTC_FACET"))));
        assertEq(integrations[2].id, bytes32(keccak256(abi.encodePacked("ERC4626_FACET"))));
        assertEq(integrations[3].id, bytes32(keccak256(abi.encodePacked("UNISWAP_V3_FACET"))));

        _assertIntegration(integrations[0].id);
        _assertIntegration(integrations[1].id);
        _assertIntegration(integrations[2].id);
        _assertIntegration(integrations[3].id);

        // Configurations: setMaxExchangeRate.
        _assertMaxExchangeRate(Ethereum.SUSDS);
        _assertMaxExchangeRate(Ethereum.SUSDE);

        // Configurations: migrate UniswapV3 pools.
        _assertUniswapV3PoolMigration(UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3PoolMigration(UNISWAP_V3_USDC_USDT_POOL);
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

        VmSafe.EthGetLogs[] memory controllerAllLogs = _getEvents(block.chainid, CONTROLLER, "");

        assertEq(controllerAllLogs.length, 16);

        // IntegrationSet(integrationId, config) from ConfigureController: updateIntegrations.
        _assertIntegrationSetEvent(controllerAllLogs[0], bytes32(keccak256(abi.encodePacked("BASIN_FACET"))));
        _assertIntegrationSetEvent(controllerAllLogs[1], bytes32(keccak256(abi.encodePacked("OTC_FACET"))));
        _assertIntegrationSetEvent(controllerAllLogs[2], bytes32(keccak256(abi.encodePacked("ERC4626_FACET"))));
        _assertIntegrationSetEvent(controllerAllLogs[3], bytes32(keccak256(abi.encodePacked("UNISWAP_V3_FACET"))));

        // ERC4626MaxExchangeRateSet(token, maxExchangeRate) from ConfigureController: setMaxExchangeRate.
        _assertERC4626MaxExchangeRateSetEvent(controllerAllLogs[4], Ethereum.SUSDS);
        _assertERC4626MaxExchangeRateSetEvent(controllerAllLogs[5], Ethereum.SUSDE);

        // UniswapV3 Migration events.
        _assertUniswapV3MaxSlippageSetEvent(controllerAllLogs[6],                UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3PoolMaxTickDeltaSetEvent(controllerAllLogs[7],           UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3AddLiquidityLowerTickBoundSetEvent(controllerAllLogs[8], UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3AddLiquidityUpperTickBoundSetEvent(controllerAllLogs[9], UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3TWAPSecondsAgoSetEvent(controllerAllLogs[10],            UNISWAP_V3_DAI_USDC_POOL);

        _assertUniswapV3MaxSlippageSetEvent(controllerAllLogs[11],                UNISWAP_V3_USDC_USDT_POOL);
        _assertUniswapV3PoolMaxTickDeltaSetEvent(controllerAllLogs[12],           UNISWAP_V3_USDC_USDT_POOL);
        _assertUniswapV3AddLiquidityLowerTickBoundSetEvent(controllerAllLogs[13], UNISWAP_V3_USDC_USDT_POOL);
        _assertUniswapV3AddLiquidityUpperTickBoundSetEvent(controllerAllLogs[14], UNISWAP_V3_USDC_USDT_POOL);
        _assertUniswapV3TWAPSecondsAgoSetEvent(controllerAllLogs[15],             UNISWAP_V3_USDC_USDT_POOL);
    }

    function _assertIntegration(bytes32 integrationId) internal view{
        IEI.Config memory beaconConfig     = beacon.getConfig(integrationId);
        IEI.Config memory controllerConfig = controller.getConfig(integrationId);

        assertEq(controllerConfig.facet,        beaconConfig.facet);
        assertEq(controllerConfig.wires.length, beaconConfig.wires.length);

        for (uint256 i = 0; i < controllerConfig.wires.length; ++i) {
            assertEq(controllerConfig.wires[i].callSelector,     beaconConfig.wires[i].callSelector);
            assertEq(controllerConfig.wires[i].delegateSelector, beaconConfig.wires[i].delegateSelector);
        }
    }
    
    function _assertMaxExchangeRate(address token) internal view {
        uint256 oldMaxExchangeRate = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER).maxExchangeRates(token);

        assertEq(controller.erc4626_getMaxExchangeRate(token), oldMaxExchangeRate);
    }

    function _assertUniswapV3PoolMigration(address pool) internal view {
        IOldMainnetControllerLike oldController = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER);

        IOldMainnetControllerLike.UniswapV3PoolParams memory oldPoolParams = oldController.uniswapV3PoolParams(pool);

        assertEq(controller.uniswapV3_getMaxSlippage(pool), oldController.maxSlippages(pool));

        ( int24 lowerTickBound, int24 upperTickBound ) = controller.uniswapV3_getLiquidityTickBounds(pool);

        assertEq(controller.uniswapV3_getMaxTickDelta(pool),   oldPoolParams.swapMaxTickDelta);
        assertEq(lowerTickBound,                               oldPoolParams.addLiquidityTickBounds.lower);
        assertEq(upperTickBound,                               oldPoolParams.addLiquidityTickBounds.upper);
        assertEq(controller.uniswapV3_getTWAPSecondsAgo(pool), oldPoolParams.twapSecondsAgo);
    }

    function _assertIntegrationSetEvent(VmSafe.EthGetLogs memory log, bytes32 integrationId) internal view {
        IEI.Config memory controllerConfig = abi.decode(log.data, (IEI.Config));
        IEI.Config memory beaconConfig     = beacon.getConfig(integrationId);

        assertEq(log.topics[0], IEI.IntegrationSet.selector);
        assertEq(log.topics[1], integrationId);

        assertEq(controllerConfig.facet,        beaconConfig.facet);
        assertEq(controllerConfig.wires.length, beaconConfig.wires.length);

        for (uint256 i = 0; i < controllerConfig.wires.length; ++i) {
            assertEq(controllerConfig.wires[i].callSelector,     beaconConfig.wires[i].callSelector);
            assertEq(controllerConfig.wires[i].delegateSelector, beaconConfig.wires[i].delegateSelector);
        }
    }

    function _assertERC4626MaxExchangeRateSetEvent(VmSafe.EthGetLogs memory log, address token) internal view {
        uint256 oldMaxExchangeRate = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER).maxExchangeRates(token);

        assertEq(log.topics[0],             IERC4626Facet.ERC4626MaxExchangeRateSet.selector);
        assertEq(_toAddress(log.topics[1]), token);
        assertEq(log.data,                  abi.encode(oldMaxExchangeRate));
    }

    function _assertUniswapV3MaxSlippageSetEvent(VmSafe.EthGetLogs memory log, address pool) internal view {
        uint256 oldMaxSlippage = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER).maxSlippages(pool);

        assertEq(log.topics[0],             IUniswapV3Facet.UniswapV3MaxSlippageSet.selector);
        assertEq(_toAddress(log.topics[1]), pool);
        assertEq(log.data,                  abi.encode(oldMaxSlippage));
    }

    function _assertUniswapV3PoolMaxTickDeltaSetEvent(VmSafe.EthGetLogs memory log, address pool) internal view {
        uint24 oldMaxTickDelta = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER).uniswapV3PoolParams(pool).swapMaxTickDelta;

        assertEq(log.topics[0],             IUniswapV3Facet.UniswapV3MaxTickDeltaSet.selector);
        assertEq(_toAddress(log.topics[1]), pool);
        assertEq(log.data,                  abi.encode(oldMaxTickDelta));
    }

    function _assertUniswapV3AddLiquidityLowerTickBoundSetEvent(VmSafe.EthGetLogs memory log, address pool) internal view {
        int24 oldLowerTickBound = IOldMainnetControllerLike(
            Ethereum.ALM_CONTROLLER
        ).uniswapV3PoolParams(pool).addLiquidityTickBounds.lower;

        assertEq(log.topics[0],             IUniswapV3Facet.UniswapV3LowerTickSet.selector);
        assertEq(_toAddress(log.topics[1]), pool);
        assertEq(log.data,                  abi.encode(oldLowerTickBound));
    }

    function _assertUniswapV3AddLiquidityUpperTickBoundSetEvent(VmSafe.EthGetLogs memory log, address pool) internal view {
        int24 oldUpperTickBound = IOldMainnetControllerLike(
            Ethereum.ALM_CONTROLLER
        ).uniswapV3PoolParams(pool).addLiquidityTickBounds.upper;

        assertEq(log.topics[0],             IUniswapV3Facet.UniswapV3UpperTickSet.selector);
        assertEq(_toAddress(log.topics[1]), pool);
        assertEq(log.data,                  abi.encode(oldUpperTickBound));
    }

    function _assertUniswapV3TWAPSecondsAgoSetEvent(VmSafe.EthGetLogs memory log, address pool) internal view {
        uint32 oldTWAPSecondsAgo = IOldMainnetControllerLike(
            Ethereum.ALM_CONTROLLER
        ).uniswapV3PoolParams(pool).twapSecondsAgo;

        assertEq(log.topics[0],             IUniswapV3Facet.UniswapV3TWAPSecondsAgoSet.selector);
        assertEq(_toAddress(log.topics[1]), pool);
        assertEq(log.data,                  abi.encode(oldTWAPSecondsAgo));
    }

}
