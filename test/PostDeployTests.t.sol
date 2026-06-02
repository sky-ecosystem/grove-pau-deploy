// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { VmSafe } from "../lib/forge-std/src/Vm.sol";

import { IAccessControl }                 from "../lib/diamond-pau/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { Initializable }                  from "../lib/diamond-pau/lib/oz-upgradeable/contracts/proxy/utils/Initializable.sol";
import { IEnumerableIntegrations as IEI } from "../lib/diamond-pau/src/interfaces/IEnumerableIntegrations.sol";
import { IMainnetControllerFull }         from "../lib/diamond-pau/test/interfaces/IMainnetControllerFull.sol";

import { AccessControls } from "../lib/diamond-pau/src/AccessControls.sol";
import { Beacon }         from "../lib/diamond-pau/src/Beacon.sol";

import { IERC4626Facet }   from "../lib/diamond-pau/src/facets/erc4626/IERC4626Facet.sol";
import { IUniswapV3Facet } from "../lib/diamond-pau/src/facets/uniswap-v3/IUniswapV3Facet.sol";

import { Ethereum } from "../lib/grove-address-registry/src/Ethereum.sol";

import { IAdministeredAgent } from "../lib/pau-administered-agent/src/interfaces/IAdministeredAgent.sol";

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
    address internal constant ACCESS_CONTROLS    = 0x0000000000000000000000000000000000000000;
    address internal constant ADMINISTERED_AGENT = 0x0000000000000000000000000000000000000000;
    address internal constant CONTROLLER         = 0x0000000000000000000000000000000000000000;
    address internal constant DEPLOYER           = 0x0000000000000000000000000000000000000000;

    // Get from SKY
    address internal constant ADMINISTERED_AGENT_FACTORY = 0x0000000000000000000000000000000000000000;
    address internal constant BEACON                     = 0x0000000000000000000000000000000000000000;
    address internal constant PAU_FACTORY                = 0x0000000000000000000000000000000000000000;

    address internal constant ADMIN              = Ethereum.GROVE_PROXY;
    address internal constant ALLOCATOR          = Ethereum.ALM_RELAYER;
    address internal constant ALLOCATOR_ADMIN    = Ethereum.ALM_FREEZER;
    address internal constant ALM_PROXY          = Ethereum.ALM_PROXY;
    address internal constant BACKSTOP_ALLOCATOR = Ethereum.GROVE_SECONDARY_RELAYER_OPERATOR;
    address internal constant RATE_LIMITS        = Ethereum.ALM_RATE_LIMITS;

    address internal constant UNISWAP_V3_DAI_USDC_POOL  = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;
    address internal constant UNISWAP_V3_USDC_USDT_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;

    AccessControls         internal accessControls;
    IAdministeredAgent     internal administeredAgent;
    Beacon                 internal beacon;
    IMainnetControllerFull internal controller;

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, _getBlock());

        accessControls    = AccessControls(ACCESS_CONTROLS);
        administeredAgent = IAdministeredAgent(ADMINISTERED_AGENT);
        beacon            = Beacon(BEACON);
        controller        = IMainnetControllerFull(payable(CONTROLLER));
    }

    function _getBlock() internal pure returns (uint256) {
        return 25130165;
    }

    function test_deployState() external view {
       /*******************************************************************************************/
       /*** AccessControls post deploy state                                                    ***/
       /*******************************************************************************************/

        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, ADMIN),     true);
        assertEq(accessControls.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);

        // DEPLOYER/PAU_FACTORY has no roles on AccessControls.
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, DEPLOYER),    false);
        assertEq(accessControls.hasRole(DEFAULT_ADMIN_ROLE, PAU_FACTORY), false);

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

        assertEq(integrations[0].id, bytes32(abi.encodePacked("BASIN_FACET")));
        assertEq(integrations[1].id, bytes32(abi.encodePacked("ERC4626_FACET")));
        assertEq(integrations[2].id, bytes32(abi.encodePacked("MAPLE_FACET")));
        assertEq(integrations[3].id, bytes32(abi.encodePacked("UNISWAP_V3_FACET")));

        _assertIntegration(integrations[0].id);
        _assertIntegration(integrations[1].id);
        _assertIntegration(integrations[2].id);
        _assertIntegration(integrations[3].id);

        // Configurations: setMaxExchangeRate.
        _assertMaxExchangeRateCopy(Ethereum.SUSDS);
        _assertMaxExchangeRateCopy(Ethereum.SUSDE);

        // Configurations: copy UniswapV3 pools config.
        _assertUniswapV3PoolConfigCopy(UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3PoolConfigCopy(UNISWAP_V3_USDC_USDT_POOL);

        /******************************************************************************************/
        /*** AdministeredAgent post deploy state                                                ***/
        /******************************************************************************************/

        assertEq(administeredAgent.adminCount(),   1);
        assertEq(administeredAgent.actorCount(),   2);
        assertEq(administeredAgent.grantorCount(), 1);
        assertEq(administeredAgent.revokerCount(), 1);

        assertEq(administeredAgent.getAdmin(0),   ADMIN);
        assertEq(administeredAgent.getActor(0),   ALLOCATOR);
        assertEq(administeredAgent.getActor(1),   BACKSTOP_ALLOCATOR);
        assertEq(administeredAgent.getGrantor(0), ALLOCATOR_ADMIN);
        assertEq(administeredAgent.getRevoker(0), ALLOCATOR_ADMIN);
    }

    function test_postDeployEvents() external {
       /*******************************************************************************************/
       /*** AccessControls events                                                               ***/
       /*******************************************************************************************/

        VmSafe.EthGetLogs[] memory accessControlsAllLogs = _getEvents(block.chainid, ACCESS_CONTROLS, "");

        assertEq(accessControlsAllLogs.length, 4);

        // RoleGranted(DEFAULT_ADMIN_ROLE, DEPLOYER, PAU_FACTORY) from PAUFactory.deployAccessControls: AccessControls constructor.
        assertEq(accessControlsAllLogs[0].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(accessControlsAllLogs[0].topics[1],             DEFAULT_ADMIN_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[0].topics[2]), DEPLOYER);
        assertEq(_toAddress(accessControlsAllLogs[0].topics[3]), PAU_FACTORY);

        // RoleGranted(ALLOCATOR_ROLE, ADMINISTERED_AGENT, DEPLOYER) from ConfigureController: ALLOCATOR_ROLE grant.
        assertEq(accessControlsAllLogs[1].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(accessControlsAllLogs[1].topics[1],             ALLOCATOR_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[1].topics[2]), ADMINISTERED_AGENT);
        assertEq(_toAddress(accessControlsAllLogs[1].topics[3]), DEPLOYER);

        // RoleGranted(DEFAULT_ADMIN_ROLE, ADMIN, DEPLOYER) from ConfigureController: DEFAULT_ADMIN_ROLE grant.
        // Role transfers from deployer to admin.
        assertEq(accessControlsAllLogs[2].topics[0],             IAccessControl.RoleGranted.selector);
        assertEq(accessControlsAllLogs[2].topics[1],             DEFAULT_ADMIN_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[2].topics[2]), ADMIN);
        assertEq(_toAddress(accessControlsAllLogs[2].topics[3]), DEPLOYER);

        // RoleRevoked(DEFAULT_ADMIN_ROLE, DEPLOYER, DEPLOYER) from ConfigureController: DEFAULT_ADMIN_ROLE revoke.
        // Role revoked from deployer.
        assertEq(accessControlsAllLogs[3].topics[0],             IAccessControl.RoleRevoked.selector);
        assertEq(accessControlsAllLogs[3].topics[1],             DEFAULT_ADMIN_ROLE);
        assertEq(_toAddress(accessControlsAllLogs[3].topics[2]), DEPLOYER);
        assertEq(_toAddress(accessControlsAllLogs[3].topics[3]), DEPLOYER);

       /*******************************************************************************************/
       /*** Controller events                                                                   ***/
       /*******************************************************************************************/

        VmSafe.EthGetLogs[] memory controllerAllLogs = _getEvents(block.chainid, CONTROLLER, "");

        assertEq(controllerAllLogs.length, 17);

        // Initialized(1) from Controller constructor.
        _assertInitializedEvent(controllerAllLogs[0]);

        // IntegrationSet(integrationId, config) from ConfigureController: updateIntegrations.
        _assertIntegrationSetEvent(controllerAllLogs[1], bytes32(abi.encodePacked("BASIN_FACET")));
        _assertIntegrationSetEvent(controllerAllLogs[2], bytes32(abi.encodePacked("ERC4626_FACET")));
        _assertIntegrationSetEvent(controllerAllLogs[3], bytes32(abi.encodePacked("MAPLE_FACET")));
        _assertIntegrationSetEvent(controllerAllLogs[4], bytes32(abi.encodePacked("UNISWAP_V3_FACET")));

        // ERC4626MaxExchangeRateSet(token, maxExchangeRate) from ConfigureController: setMaxExchangeRate.
        _assertERC4626MaxExchangeRateSetEvent(controllerAllLogs[5], Ethereum.SUSDS);
        _assertERC4626MaxExchangeRateSetEvent(controllerAllLogs[6], Ethereum.SUSDE);

        // UniswapV3 Migration events.
        _assertUniswapV3MaxSlippageSetEvent(controllerAllLogs[7],                 UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3PoolMaxTickDeltaSetEvent(controllerAllLogs[8],            UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3AddLiquidityLowerTickBoundSetEvent(controllerAllLogs[9],  UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3AddLiquidityUpperTickBoundSetEvent(controllerAllLogs[10], UNISWAP_V3_DAI_USDC_POOL);
        _assertUniswapV3TWAPSecondsAgoSetEvent(controllerAllLogs[11],             UNISWAP_V3_DAI_USDC_POOL);

        _assertUniswapV3MaxSlippageSetEvent(controllerAllLogs[12],                UNISWAP_V3_USDC_USDT_POOL);
        _assertUniswapV3PoolMaxTickDeltaSetEvent(controllerAllLogs[13],           UNISWAP_V3_USDC_USDT_POOL);
        _assertUniswapV3AddLiquidityLowerTickBoundSetEvent(controllerAllLogs[14], UNISWAP_V3_USDC_USDT_POOL);
        _assertUniswapV3AddLiquidityUpperTickBoundSetEvent(controllerAllLogs[15], UNISWAP_V3_USDC_USDT_POOL);
        _assertUniswapV3TWAPSecondsAgoSetEvent(controllerAllLogs[16],             UNISWAP_V3_USDC_USDT_POOL);

       /*******************************************************************************************/
       /*** AdministeredAgent events                                                            ***/
       /*******************************************************************************************/

        VmSafe.EthGetLogs[] memory administeredAgentAllLogs = _getEvents(block.chainid, ADMINISTERED_AGENT, "");

        assertEq(administeredAgentAllLogs.length, 7);

        // AdminAdded(DEPLOYER, ADMINISTERED_AGENT_FACTORY) from AdministeredAgent constructor.
        assertEq(administeredAgentAllLogs[0].topics[0],             IAdministeredAgent.AdminAdded.selector);
        assertEq(_toAddress(administeredAgentAllLogs[0].topics[1]), DEPLOYER);
        assertEq(_toAddress(administeredAgentAllLogs[0].topics[2]), ADMINISTERED_AGENT_FACTORY);

        // ActorAdded(ALLOCATOR, DEPLOYER) from ConfigureController: addActor.
        assertEq(administeredAgentAllLogs[1].topics[0],             IAdministeredAgent.ActorAdded.selector);
        assertEq(_toAddress(administeredAgentAllLogs[1].topics[1]), ALLOCATOR);
        assertEq(_toAddress(administeredAgentAllLogs[1].topics[2]), DEPLOYER);

        // ActorAdded(BACKSTOP_ALLOCATOR, DEPLOYER) from ConfigureController: addActor.
        assertEq(administeredAgentAllLogs[2].topics[0],             IAdministeredAgent.ActorAdded.selector);
        assertEq(_toAddress(administeredAgentAllLogs[2].topics[1]), BACKSTOP_ALLOCATOR);
        assertEq(_toAddress(administeredAgentAllLogs[2].topics[2]), DEPLOYER);

        // GrantorAdded(ALLOCATOR_ADMIN, DEPLOYER) from ConfigureController: addGrantor.
        assertEq(administeredAgentAllLogs[3].topics[0],             IAdministeredAgent.GrantorAdded.selector);
        assertEq(_toAddress(administeredAgentAllLogs[3].topics[1]), ALLOCATOR_ADMIN);
        assertEq(_toAddress(administeredAgentAllLogs[3].topics[2]), DEPLOYER);

        // RevokerAdded(ALLOCATOR_ADMIN, DEPLOYER) from ConfigureController: addRevoker.
        assertEq(administeredAgentAllLogs[4].topics[0],             IAdministeredAgent.RevokerAdded.selector);
        assertEq(_toAddress(administeredAgentAllLogs[4].topics[1]), ALLOCATOR_ADMIN);
        assertEq(_toAddress(administeredAgentAllLogs[4].topics[2]), DEPLOYER);

        // AdminAdded(ADMIN, DEPLOYER) from ConfigureController: addAdmin.
        assertEq(administeredAgentAllLogs[5].topics[0],             IAdministeredAgent.AdminAdded.selector);
        assertEq(_toAddress(administeredAgentAllLogs[5].topics[1]), ADMIN);
        assertEq(_toAddress(administeredAgentAllLogs[5].topics[2]), DEPLOYER);

        // AdminRemoved(DEPLOYER, DEPLOYER) from ConfigureController: removeAdmin.
        assertEq(administeredAgentAllLogs[6].topics[0],             IAdministeredAgent.AdminRemoved.selector);
        assertEq(_toAddress(administeredAgentAllLogs[6].topics[1]), DEPLOYER);
        assertEq(_toAddress(administeredAgentAllLogs[6].topics[2]), DEPLOYER);
    }

    /*******************************************************************************************/
    /*** Helper functions                                                                    ***/
    /*******************************************************************************************/

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
    
    function _assertMaxExchangeRateCopy(address token) internal view {
        uint256 oldMaxExchangeRate = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER).maxExchangeRates(token);

        assertEq(controller.erc4626_getMaxExchangeRate(token), oldMaxExchangeRate);
    }

    function _assertUniswapV3PoolConfigCopy(address pool) internal view {
        IOldMainnetControllerLike oldController = IOldMainnetControllerLike(Ethereum.ALM_CONTROLLER);

        IOldMainnetControllerLike.UniswapV3PoolParams memory oldPoolParams = oldController.uniswapV3PoolParams(pool);

        assertEq(controller.uniswapV3_getMaxSlippage(pool), oldController.maxSlippages(pool));

        ( int24 lowerTickBound, int24 upperTickBound ) = controller.uniswapV3_getLiquidityTickBounds(pool);

        assertEq(controller.uniswapV3_getMaxTickDelta(pool),   oldPoolParams.swapMaxTickDelta);
        assertEq(lowerTickBound,                               oldPoolParams.addLiquidityTickBounds.lower);
        assertEq(upperTickBound,                               oldPoolParams.addLiquidityTickBounds.upper);
        assertEq(controller.uniswapV3_getTWAPSecondsAgo(pool), oldPoolParams.twapSecondsAgo);
    }

    /*******************************************************************************************/
    /*** Event test helpers                                                                  ***/
    /*******************************************************************************************/

    function _assertInitializedEvent(VmSafe.EthGetLogs memory log) internal pure {
        assertEq(log.topics[0], Initializable.Initialized.selector);
        assertEq(log.data,      abi.encode(1));
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
