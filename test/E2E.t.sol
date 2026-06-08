// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.34;

import { IERC20 } from "../lib/forge-std/src/interfaces/IERC20.sol";

import { IAccessControl } from "../lib/diamond-pau/lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { IMainnetControllerFull } from "../lib/diamond-pau/test/interfaces/IMainnetControllerFull.sol";

import { IALMProxy }   from "../lib/diamond-pau/src/interfaces/IALMProxy.sol";
import { IRateLimits } from "../lib/diamond-pau/src/interfaces/IRateLimits.sol";

import { IBasinFacet }     from "../lib/diamond-pau/src/facets/basin/IBasinFacet.sol";
import { IERC4626Facet }   from "../lib/diamond-pau/src/facets/erc4626/IERC4626Facet.sol";
import { IMapleFacet }     from "../lib/diamond-pau/src/facets/maple/IMapleFacet.sol";
import { IUniswapV3Facet } from "../lib/diamond-pau/src/facets/uniswap-v3/IUniswapV3Facet.sol";

import {
    IMapleTokenExtendedLike,
    IPermissionManagerLike,
    IPoolManagerLike,
    IWithdrawalManagerLike
} from "../lib/diamond-pau/test/interfaces/Maple.sol";

import { IUniswapV3PoolLike } from "../lib/diamond-pau/test/interfaces/UniswapV3.sol";

import { GroveBasin }        from "../lib/diamond-pau/lib/grove-basin/src/GroveBasin.sol";
import { FixedRateProvider } from "../lib/diamond-pau/lib/grove-basin/src/rate-providers/FixedRateProvider.sol";

import { Ethereum } from "../lib/grove-address-registry/src/Ethereum.sol";

import { PostDeployTestBase } from "./PostDeployTestBase.t.sol";

contract E2E is PostDeployTestBase {

    // Paste from script output.
    address internal constant ACCESS_CONTROLS = 0x10d1AdE77F1b81Ef95057bb2fACE292313F66277;
    address internal constant CONTROLLER      = 0x0DD65461610Fe5b65cE50A870B10ED0F3d24d8C2;

    address internal constant ADMIN       = Ethereum.GROVE_PROXY;
    address internal constant ALM_PROXY   = Ethereum.ALM_PROXY;
    address internal constant RATE_LIMITS = Ethereum.ALM_RATE_LIMITS;

    IPermissionManagerLike internal constant MAPLE_PERMISSION_MANAGER
        = IPermissionManagerLike(0xBe10aDcE8B6E3E02Db384E7FaDA5395DD113D8b3);

    IMainnetControllerFull internal controller;
    IRateLimits            internal rateLimits;

    address internal allocator = makeAddr("allocator");

    function setUp() public {
        vm.createSelectFork(getChain("mainnet").rpcUrl, _getBlock());

        controller = IMainnetControllerFull(payable(CONTROLLER));
        rateLimits = IRateLimits(RATE_LIMITS);

        vm.startPrank(ADMIN);

        IALMProxy(ALM_PROXY).grantRole(IALMProxy(ALM_PROXY).CONTROLLER(), CONTROLLER);
        rateLimits.grantRole(rateLimits.CONTROLLER(),                     CONTROLLER);
        IAccessControl(ACCESS_CONTROLS).grantRole(ALLOCATOR_ROLE,         allocator);

        vm.stopPrank();
    }

    function _getBlock() internal pure returns (uint256) {
        return 25252729; // Jun-05-2026 05:39:47 PM +UTC : After scripts execution.
    }

    function _setRateLimit(bytes32 key, uint256 maxAmount, uint256 perDay) internal {
        vm.prank(ADMIN);
        rateLimits.setRateLimitData(key, maxAmount, perDay / 1 days);
    }

    /**********************************************************************************************/
    /*** Maple (ERC4626 deposit + Maple requestRedemption)                                      ***/
    /**********************************************************************************************/

    function test_e2e_maple_depositAndRequestRedeem() external {
        IMapleTokenExtendedLike syrup = IMapleTokenExtendedLike(Ethereum.MAPLE_SYRUP_USDC);
        
        uint256 totalAssetsBefore = syrup.totalAssets();
        uint256 totalSupplyBefore = syrup.totalSupply();

        _setupMaple(address(syrup));

        deal(Ethereum.USDC, ALM_PROXY, 1_000_000e6);

        // Step 1: Deposit USDC into Maple

        uint256 expectedShares      = syrup.convertToShares(1_000_000e6);
        uint256 proxySyrupBalBefore = syrup.balanceOf(ALM_PROXY);
        uint256 proxyUSDCBalBefore  = IERC20(Ethereum.USDC).balanceOf(ALM_PROXY);
        uint256 syrupUSDCBalBefore  = IERC20(Ethereum.USDC).balanceOf(address(syrup));

        assertEq(IERC20(Ethereum.USDC).balanceOf(ALM_PROXY),      proxyUSDCBalBefore);
        assertEq(IERC20(Ethereum.USDC).balanceOf(address(syrup)), syrupUSDCBalBefore);

        assertEq(syrup.totalSupply(),        totalSupplyBefore);
        assertEq(syrup.totalAssets(),        totalAssetsBefore);
        assertEq(syrup.balanceOf(ALM_PROXY), proxySyrupBalBefore);

        vm.expectEmit(address(controller));
        emit IERC4626Facet.ERC4626Deposit(address(syrup), 1_000_000e6, expectedShares);

        vm.prank(allocator);
        uint256 shares = controller.erc4626_deposit(address(syrup), 1_000_000e6, expectedShares);

        assertEq(IERC20(Ethereum.USDC).balanceOf(ALM_PROXY),      0);
        assertEq(IERC20(Ethereum.USDC).balanceOf(address(syrup)), syrupUSDCBalBefore + 1_000_000e6);

        assertEq(syrup.totalSupply(),        totalSupplyBefore + shares);
        assertEq(syrup.totalAssets(),        totalAssetsBefore + 1_000_000e6);
        assertEq(syrup.balanceOf(ALM_PROXY), proxySyrupBalBefore + shares);

        // Step 2: Request redemption of the shares

        skip(1 days);  // Warp to accrue interest

        address withdrawalManager    = IPoolManagerLike(syrup.manager()).withdrawalManager();
        uint256 escrowedSharesBefore = syrup.balanceOf(withdrawalManager);

        assertEq(syrup.balanceOf(withdrawalManager),  escrowedSharesBefore);
        assertEq(syrup.balanceOf(ALM_PROXY),          proxySyrupBalBefore + shares);

        vm.expectEmit(address(controller));
        emit IMapleFacet.MapleRequestRedemption(address(syrup), shares);

        vm.prank(allocator);
        controller.maple_requestRedemption(address(syrup), shares);

        assertEq(syrup.balanceOf(withdrawalManager), escrowedSharesBefore + shares);
        assertEq(syrup.balanceOf(ALM_PROXY),         proxySyrupBalBefore);

        // Step 3: Fulfill Redeem (done by Maple)

        skip(1 days);  // Warp to accrue more interest

        uint256 totalAssets    = syrup.totalAssets();
        uint256 withdrawAssets = syrup.convertToAssets(shares);

        assertGt(totalAssets, totalAssetsBefore + 1_000_000e6);  // Interest accrued

        assertEq(withdrawAssets, 1_000_246.463617e6);  // Interest accrued

        assertEq(syrup.totalSupply(),                totalSupplyBefore + shares);
        assertEq(syrup.totalAssets(),                totalAssets);
        assertEq(syrup.balanceOf(withdrawalManager), escrowedSharesBefore + shares);

        assertEq(IERC20(Ethereum.USDC).balanceOf(address(syrup)), syrupUSDCBalBefore + 1_000_000e6);
        assertEq(IERC20(Ethereum.USDC).balanceOf(ALM_PROXY),      0);

        vm.prank(IPoolManagerLike(syrup.manager()).poolDelegate());
        IWithdrawalManagerLike(withdrawalManager).processRedemptions(shares);

        assertEq(syrup.totalAssets(),                totalAssets - withdrawAssets);
        assertEq(syrup.balanceOf(withdrawalManager), escrowedSharesBefore);

        assertEq(IERC20(Ethereum.USDC).balanceOf(address(syrup)), syrupUSDCBalBefore + 1_000_000e6 - withdrawAssets);
        assertEq(IERC20(Ethereum.USDC).balanceOf(ALM_PROXY),      withdrawAssets);
    }

    function _setupMaple(address syrup_) internal {
        IMapleTokenExtendedLike syrup = IMapleTokenExtendedLike(syrup_);

        _setRateLimit(controller.erc4626_getDepositRateLimitKey(address(syrup), Ethereum.USDC), 5_000_000e6, 1_000_000e6);
        _setRateLimit(controller.maple_getRequestRedeemRateLimitKey(address(syrup)),            5_000_000e6, 1_000_000e6);

        // Maple onboarding: allowlist almProxy as a lender for the pool.
        address[] memory lenders  = new address[](1);
        bool[]    memory booleans = new bool[](1);

        lenders[0]  = ALM_PROXY;
        booleans[0] = true;

        vm.startPrank(MAPLE_PERMISSION_MANAGER.admin());
        MAPLE_PERMISSION_MANAGER.setLenderAllowlist(syrup.manager(), lenders, booleans);
        vm.stopPrank();
    }

    /**********************************************************************************************/
    /*** UniswapV3 (swap + add liquidity + remove liquidity)                                    ***/
    /**********************************************************************************************/

    function test_e2e_uniswapV3_swapAddRemoveLiquidity() external {
        address pool   = Ethereum.UNISWAP_V3_AUSD_USDC;
        address token0 = IUniswapV3PoolLike(pool).token0();  // AUSD
        address token1 = IUniswapV3PoolLike(pool).token1();  // USDC

        ( , int24 initTick, , , , , ) = IUniswapV3PoolLike(pool).slot0();

        // Step 1: Setup UniswapV3

        _setupUniswapV3(pool, token0, token1, initTick);

        // Step 2: Swap USDC -> AUSD

        deal(token1, ALM_PROXY, 50_000e6);

        vm.prank(allocator);
        uint256 ausdOut = controller.uniswapV3_swap(pool, token1, 10_000e6, 10_000e6 * 99 / 100, 200);

        assertGt(ausdOut, 0, "swap should return AUSD");

        uint256 token0Bal = IERC20(token0).balanceOf(ALM_PROXY);
        uint256 token1Bal = IERC20(token1).balanceOf(ALM_PROXY);

        assertGt(token0Bal, 0, "proxy should hold AUSD after swap");
        assertGt(token1Bal, 0, "proxy should hold USDC after swap");

        // Step 3: Add a balanced position straddling the tick, then remove all liquidity

        _addAndRemoveLiquidity(pool, token0Bal < token1Bal ? token0Bal : token1Bal, initTick);
    }

    function _setupUniswapV3(address pool, address token0, address token1, int24 initTick) internal {
        // Set rate limits

        _setRateLimit(controller.uniswapV3_getSwapRateLimitKey(pool, token1),          5_000_000e6,   1_000_000e6);
        _setRateLimit(controller.uniswapV3_getAggregateDepositRateLimitKey(pool),      10_000_000e18, 2_000_000e18);
        _setRateLimit(controller.uniswapV3_getAssetDepositRateLimitKey(pool, token0),  5_000_000e6,   1_000_000e6);
        _setRateLimit(controller.uniswapV3_getAssetDepositRateLimitKey(pool, token1),  5_000_000e6,   1_000_000e6);
        _setRateLimit(controller.uniswapV3_getAggregateWithdrawRateLimitKey(pool),     10_000_000e18, 2_000_000e18);
        _setRateLimit(controller.uniswapV3_getAssetWithdrawRateLimitKey(pool, token0), 5_000_000e6,   1_000_000e6);
        _setRateLimit(controller.uniswapV3_getAssetWithdrawRateLimitKey(pool, token1), 5_000_000e6,   1_000_000e6);

        // Set some relaxed pool parameters for testing.

        vm.startPrank(ADMIN);
        controller.uniswapV3_setMaxSlippage(pool, 0.98e18);
        controller.uniswapV3_setMaxTickDelta(pool, 200);
        controller.uniswapV3_setTWAPSecondsAgo(pool, 600);
        controller.uniswapV3_setLiquidityLowerTickBound(pool, initTick - 1000);
        controller.uniswapV3_setLiquidityUpperTickBound(pool, initTick + 1000);
        vm.stopPrank();
    }

    function _addAndRemoveLiquidity(address pool, uint256 addAmount, int24 initTick) internal {
        IUniswapV3Facet.Ticks memory ticks = IUniswapV3Facet.Ticks({
            lower: initTick - 100,
            upper: initTick + 100
        });
        IUniswapV3Facet.TokenAmounts memory desired = IUniswapV3Facet.TokenAmounts({
            amount0: addAmount,
            amount1: addAmount
        });

        vm.prank(allocator);
        ( uint256 tokenId, uint128 liquidity, IUniswapV3Facet.TokenAmounts memory used )
            = controller.uniswapV3_addLiquidity(
                pool,
                0,
                ticks,
                desired,
                IUniswapV3Facet.TokenAmounts({ amount0: addAmount * 98 / 100, amount1: addAmount * 98 / 100 }),
                block.timestamp + 1 hours
            );

        assertGt(tokenId,   0, "position should be minted");
        assertGt(liquidity, 0, "liquidity should be added");

        vm.prank(allocator);
        IUniswapV3Facet.TokenAmounts memory removed = controller.uniswapV3_removeLiquidity(
            pool,
            tokenId,
            liquidity,
            IUniswapV3Facet.TokenAmounts({ amount0: used.amount0 * 98 / 100, amount1: used.amount1 * 98 / 100 }),
            block.timestamp + 1 hours
        );

        assertGt(removed.amount0, 0, "should withdraw AUSD");
        assertGt(removed.amount1, 0, "should withdraw USDC");
    }

    /**********************************************************************************************/
    /*** Basin (deposit + withdraw)                                                             ***/
    /**********************************************************************************************/

    function test_e2e_basin_depositAndWithdraw() external {
        // Step 1: Setup Basin

        FixedRateProvider rateProvider = new FixedRateProvider(1e27);

        GroveBasin basin = new GroveBasin(
            address(this),     // owner
            ALM_PROXY,         // liquidityProvider
            Ethereum.USDC,     // swapToken
            Ethereum.USDS,     // collateralToken (tested asset)
            Ethereum.DAI,      // creditToken
            address(rateProvider),
            address(rateProvider),
            address(rateProvider)
        );

        // Step 2: Seed the basin

        uint256 seedAmount = 1_000e18;

        deal(Ethereum.USDS, address(this), seedAmount);

        IERC20(Ethereum.USDS).approve(address(basin), seedAmount);

        basin.depositInitial(Ethereum.USDS, seedAmount);

        // Step 3: Set rate limits

        _setRateLimit(controller.basin_getDepositRateLimitKey(address(basin),  Ethereum.USDS), 5_000_000e18, 1_000_000e18);
        _setRateLimit(controller.basin_getWithdrawRateLimitKey(address(basin), Ethereum.USDS), 5_000_000e18, 1_000_000e18);

        // Step 4: Deposit USDS into the basin

        uint256 depositAmount = 1_000_000e18;
        deal(Ethereum.USDS, ALM_PROXY, depositAmount);

        uint256 expectedShares = basin.previewDeposit(Ethereum.USDS, depositAmount);

        assertEq(expectedShares, depositAmount);

        vm.expectEmit(address(controller));
        emit IBasinFacet.BasinDeposit(address(basin), Ethereum.USDS, depositAmount, expectedShares);

        vm.prank(allocator);
        uint256 shares = controller.basin_deposit(address(basin), Ethereum.USDS, depositAmount, expectedShares);

        assertEq(shares, expectedShares);
        assertGt(shares, 0);

        assertEq(IERC20(Ethereum.USDS).balanceOf(ALM_PROXY),      0);
        assertEq(IERC20(Ethereum.USDS).balanceOf(address(basin)), depositAmount + seedAmount);

        // Step 5: Withdraw the USDS back out

        uint256 withdrawAmount = 1_000_000e18;

        vm.expectEmit(address(controller));
        emit IBasinFacet.BasinWithdraw(address(basin), Ethereum.USDS, withdrawAmount, expectedShares);

        vm.prank(allocator);
        uint256 assetsWithdrawn = controller.basin_withdraw(address(basin), Ethereum.USDS, withdrawAmount, 1e18);

        assertEq(assetsWithdrawn,                                 withdrawAmount);
        assertEq(IERC20(Ethereum.USDS).balanceOf(ALM_PROXY),      withdrawAmount);
        assertEq(IERC20(Ethereum.USDS).balanceOf(address(basin)), depositAmount + seedAmount - withdrawAmount);
    }

}
