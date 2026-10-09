// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "./lib/forge-std/src/Test.sol";
import {TESTERToken} from "../src/TESTERToken.sol";
import {PoolManager} from "./lib/v4-core/src/PoolManager.sol";
import {IPoolManager} from "./lib/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "./lib/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "./lib/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "./lib/v4-core/src/types/PoolKey.sol";
import {PoolId} from "./lib/v4-core/src/types/PoolId.sol";
import {Currency} from "./lib/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "./lib/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "./lib/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "./lib/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "./lib/v4-core/src/libraries/SqrtPriceMath.sol";
import {FullMath} from "./lib/v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "./lib/v4-core/src/libraries/StateLibrary.sol";
import {Position} from "./lib/v4-core/src/libraries/Position.sol";

/// @notice The ERC-20 subset the launch flows use.
interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

/// @notice Stand-in for IMD, the paired currency, etched at IMD's mainnet address so the pool sorts
/// its two currencies the way the chain will. Plain ERC-20; only the harness mints it.
contract PairTokenStub {
    string public constant name = "IdentityMD";
    string public constant symbol = "IMD";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "IMD: balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}

/// @notice Pays what a BalanceDelta says the caller owes and takes what it is owed.
library Settle {
    function settle(IPoolManager manager, Currency currency, int128 delta) internal {
        if (delta < 0) {
            uint256 owed = uint256(uint128(-delta));
            if (currency.isAddressZero()) {
                manager.settle{value: owed}();
            } else {
                manager.sync(currency);
                require(IERC20Like(Currency.unwrap(currency)).transfer(address(manager), owed), "pay failed");
                manager.settle();
            }
        } else if (delta > 0) {
            manager.take(currency, address(this), uint256(uint128(delta)));
        }
    }
}

/// @notice Stands in for the launch factory: deploys the token through CREATE2 so it is the token's
/// deployer and receives the whole supply, forwards the swarm's share and the remainder, and seeds
/// the pool single-sided through the pool manager's unlock. Only the test drives it.
contract LaunchFactoryStub is IUnlockCallback {
    using Settle for IPoolManager;

    enum Action {
        Seed,
        Collect
    }

    address private immutable controller = msg.sender;
    IPoolManager public immutable manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    modifier onlyController() {
        require(msg.sender == controller, "not the harness");
        _;
    }

    function deploy(bytes memory code, bytes32 salt) external onlyController returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0) && deployed.code.length > 0, "constructor failed");
    }

    function move(IERC20Like token, address to, uint256 amount) external onlyController returns (bool) {
        return token.transfer(to, amount);
    }

    function initialize(PoolKey calldata key, uint160 sqrtPriceX96) external onlyController returns (int24) {
        return manager.initialize(key, sqrtPriceX96);
    }

    function seed(PoolKey calldata key, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        onlyController
        returns (BalanceDelta delta)
    {
        bytes memory out = manager.unlock(abi.encode(Action.Seed, key, tickLower, tickUpper, liquidity));
        delta = abi.decode(out, (BalanceDelta));
    }

    /// @dev A zero-liquidity modifyLiquidity realises the position's accrued fees; takes them out.
    function collectFees(PoolKey calldata key, int24 tickLower, int24 tickUpper)
        external
        onlyController
        returns (BalanceDelta fees)
    {
        bytes memory out = manager.unlock(abi.encode(Action.Collect, key, tickLower, tickUpper, uint128(0)));
        fees = abi.decode(out, (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(manager), "not the pool manager");
        (Action action, PoolKey memory key, int24 tickLower, int24 tickUpper, uint128 liquidity) =
            abi.decode(data, (Action, PoolKey, int24, int24, uint128));
        if (action == Action.Seed) {
            (BalanceDelta delta,) = manager.modifyLiquidity(
                key, ModifyLiquidityParams(tickLower, tickUpper, int256(uint256(liquidity)), bytes32(0)), ""
            );
            manager.settle(key.currency0, delta.amount0());
            manager.settle(key.currency1, delta.amount1());
            return abi.encode(delta);
        }
        (BalanceDelta collected, BalanceDelta fees) =
            manager.modifyLiquidity(key, ModifyLiquidityParams(tickLower, tickUpper, 0, bytes32(0)), "");
        manager.settle(key.currency0, collected.amount0());
        manager.settle(key.currency1, collected.amount1());
        return abi.encode(fees);
    }
}

/// @notice An ordinary trader: nothing the token has any reason to treat specially.
contract TraderStub is IUnlockCallback {
    using Settle for IPoolManager;

    IPoolManager public immutable manager;
    PoolKey private key;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    receive() external payable {}

    /// @param amountSpecified negative for exact input, positive for exact output (v4 convention).
    function swap(PoolKey calldata key_, bool zeroForOne, int256 amountSpecified) external returns (BalanceDelta) {
        key = key_;
        return abi.decode(manager.unlock(abi.encode(zeroForOne, amountSpecified)), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(manager), "not the pool manager");
        (bool zeroForOne, int256 amountSpecified) = abi.decode(data, (bool, int256));
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        BalanceDelta delta = manager.swap(key, SwapParams(zeroForOne, amountSpecified, limit), "");
        manager.settle(key.currency0, delta.amount0());
        manager.settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }
}

/// @notice Shared launch arithmetic and setup for the pool suites.
abstract contract TESTERLaunchBase is Test {
    using StateLibrary for IPoolManager;

    uint256 internal constant SUPPLY = 1_000_000_000e18;
    uint256 internal constant SWARM_BPS = 1_000;
    uint256 internal constant POOL_BPS = 9_000;
    uint256 internal constant INITIAL_MARKET_CAP = 2_500e18; // 2500 IMD, launch.json economics
    uint24 internal constant POOL_FEE = 12_500; // 1.25%, launch.json pool.fee
    int24 internal constant TICK_SPACING = 60; // launch.json pool.tickSpacing
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address internal constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address internal constant REMAINDER_TO = 0x000000000000000000000000000000000000dEaD;
    address internal constant DISTRIBUTOR = address(0xD157);
    uint256 internal constant Q96 = 2 ** 96;

    IPoolManager internal manager;
    LaunchFactoryStub internal factory;
    PairTokenStub internal imd;

    TESTERToken internal token;
    PoolKey internal key;
    bool internal tokenIsCurrency0;
    int24 internal tickLower;
    int24 internal tickUpper;
    uint128 internal liquidity;
    uint256 internal seeded;

    function _setUpInfrastructure() internal {
        // The v4 manager, constructed in place at its mainnet address: its NoDelegateCall guard
        // records the address it was built at, so it cannot be copied there.
        vm.etch(POOL_MANAGER, abi.encodePacked(type(PoolManager).creationCode, abi.encode(address(this))));
        (bool built, bytes memory runtime) = POOL_MANAGER.call("");
        require(built && runtime.length > 0, "pool manager could not be built in place");
        vm.etch(POOL_MANAGER, runtime);
        manager = IPoolManager(POOL_MANAGER);
        vm.label(POOL_MANAGER, "PoolManager");

        vm.etch(IMD, address(new PairTokenStub()).code);
        imd = PairTokenStub(IMD);
        vm.label(IMD, "IMD");

        factory = new LaunchFactoryStub(manager);
        vm.label(address(factory), "LaunchFactory");
    }

    /// @dev Deploys the token from the factory at a salt that gives the requested currency order,
    /// then performs the factory's launch: 10% to the distributor, the pool share seeded
    /// single-sided at the price derived from the economics, the remainder to remainderTo.
    function _launch(bool wantToken0) internal {
        bytes memory code = type(TESTERToken).creationCode;
        bytes32 codeHash = keccak256(code);
        bytes32 salt;
        for (uint256 i; i < 10_000; ++i) {
            address predicted = address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(i), codeHash))))
            );
            if ((predicted < IMD) == wantToken0) {
                salt = bytes32(i);
                break;
            }
        }
        token = TESTERToken(factory.deploy(code, salt));
        vm.label(address(token), "TESTER");
        tokenIsCurrency0 = address(token) < IMD;
        assertEq(tokenIsCurrency0, wantToken0, "salt search failed");
        assertEq(token.balanceOf(address(factory)), SUPPLY, "the factory must hold the whole supply");

        key = PoolKey(
            Currency.wrap(tokenIsCurrency0 ? address(token) : IMD),
            Currency.wrap(tokenIsCurrency0 ? IMD : address(token)),
            POOL_FEE,
            TICK_SPACING,
            IHooks(address(0))
        );

        uint256 swarm = SUPPLY * SWARM_BPS / 10_000;
        assertTrue(factory.move(IERC20Like(address(token)), DISTRIBUTOR, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "the swarm's share arrived short");

        // Opening price from the economics: 2500 IMD over the whole supply, in the deployed order.
        uint160 sqrtPrice = tokenIsCurrency0
            ? uint160(_sqrt(FullMath.mulDiv(INITIAL_MARKET_CAP, 2 ** 192, SUPPLY)))
            : uint160(_sqrt(FullMath.mulDiv(SUPPLY, 2 ** 192, INITIAL_MARKET_CAP)));
        int24 tick = _align(TickMath.getTickAtSqrtPrice(sqrtPrice));
        sqrtPrice = TickMath.getSqrtPriceAtTick(tick);
        int24 initialTick = factory.initialize(key, sqrtPrice);
        assertEq(initialTick, tick);

        uint256 allowed = SUPPLY * POOL_BPS / 10_000;
        if (tokenIsCurrency0) {
            tickLower = tick;
            tickUpper = _align(TickMath.MAX_TICK);
            uint160 a = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 b = TickMath.getSqrtPriceAtTick(tickUpper);
            uint256 l = FullMath.mulDiv(allowed, FullMath.mulDiv(a, b, Q96), b - a);
            while (SqrtPriceMath.getAmount0Delta(a, b, uint128(l), true) > allowed) --l;
            liquidity = uint128(l);
        } else {
            tickLower = -_align(TickMath.MAX_TICK);
            tickUpper = tick;
            uint160 a = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 b = TickMath.getSqrtPriceAtTick(tickUpper);
            uint256 l = FullMath.mulDiv(allowed, Q96, b - a);
            while (SqrtPriceMath.getAmount1Delta(a, b, uint128(l), true) > allowed) --l;
            liquidity = uint128(l);
        }
        assertGt(liquidity, 0, "no liquidity");

        uint256 before = token.balanceOf(address(factory));
        uint256 imdBefore = imd.balanceOf(address(factory));
        BalanceDelta delta = factory.seed(key, tickLower, tickUpper, liquidity);
        seeded = before - token.balanceOf(address(factory));
        assertGt(seeded, 0, "the seed took nothing");
        assertLe(seeded, allowed, "the seed took more than the pool share");
        assertGe(seeded, allowed - 1e6, "the seed left more than dust of the pool share unused");
        int128 tokenDelta = tokenIsCurrency0 ? delta.amount0() : delta.amount1();
        int128 pairDelta = tokenIsCurrency0 ? delta.amount1() : delta.amount0();
        assertEq(uint256(uint128(-tokenDelta)), seeded, "the manager credited a different amount than left the factory");
        assertEq(pairDelta, 0, "single-sided seed must not take IMD");
        assertEq(imd.balanceOf(address(factory)), imdBefore);
        assertEq(token.balanceOf(POOL_MANAGER), seeded, "the pool manager holds something other than the seed");

        uint256 remainder = token.balanceOf(address(factory));
        assertTrue(factory.move(IERC20Like(address(token)), REMAINDER_TO, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(REMAINDER_TO), remainder);
        assertEq(swarm + seeded + remainder, SUPPLY, "the launch flows do not add up to the supply");
    }

    function _newTrader(uint256 imdFunding) internal returns (TraderStub trader) {
        trader = new TraderStub(manager);
        imd.mint(address(trader), imdFunding);
    }

    /// @dev Buy: IMD in, TESTER out. Returns the amount of TESTER the manager says it delivered.
    function _buy(TraderStub trader, int256 amountSpecified) internal returns (uint256 out, uint256 paid) {
        BalanceDelta d = trader.swap(key, !tokenIsCurrency0, amountSpecified);
        int128 tokenDelta = tokenIsCurrency0 ? d.amount0() : d.amount1();
        int128 pairDelta = tokenIsCurrency0 ? d.amount1() : d.amount0();
        assertGt(tokenDelta, 0, "buy delivered nothing");
        assertLt(pairDelta, 0, "buy cost nothing");
        out = uint256(uint128(tokenDelta));
        paid = uint256(uint128(-pairDelta));
    }

    /// @dev Sell: TESTER in, IMD out. Returns the amount of TESTER the manager says it took.
    function _sell(TraderStub trader, int256 amountSpecified) internal returns (uint256 sold, uint256 received) {
        BalanceDelta d = trader.swap(key, tokenIsCurrency0, amountSpecified);
        int128 tokenDelta = tokenIsCurrency0 ? d.amount0() : d.amount1();
        int128 pairDelta = tokenIsCurrency0 ? d.amount1() : d.amount0();
        assertLt(tokenDelta, 0, "sell took nothing");
        assertGt(pairDelta, 0, "sell paid nothing");
        sold = uint256(uint128(-tokenDelta));
        received = uint256(uint128(pairDelta));
    }

    function _circulating() internal view returns (uint256) {
        return token.balanceOf(address(factory)) + token.balanceOf(DISTRIBUTOR) + token.balanceOf(POOL_MANAGER)
            + token.balanceOf(REMAINDER_TO);
    }

    function _align(int24 tick) internal pure returns (int24) {
        int24 aligned = (tick / TICK_SPACING) * TICK_SPACING;
        if (tick < 0 && aligned != tick) aligned -= TICK_SPACING;
        return aligned;
    }

    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = (x + 1) / 2;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }
}

/// @title Swarm Tester through the Uniswap v4 PoolManager
/// @notice The launch as the factory performs it and the trading that follows, against the real
/// v4 PoolManager built at its mainnet address with the manifest's fee and tick spacing. A token
/// with a hidden fee, tax or limit would arrive short somewhere in here.
contract TESTERTokenPoolTest is TESTERLaunchBase {
    using StateLibrary for IPoolManager;

    function setUp() public {
        _setUpInfrastructure();
    }

    function test_seedTakesThePoolShareExactlyAndRemainderGoesToDead() public {
        _launch(true);
        (uint160 sqrtPriceX96, int24 tick,, uint24 lpFee) = manager.getSlot0(key.toId());
        assertEq(lpFee, POOL_FEE, "pool fee is not the manifest's");
        assertEq(tick, tickLower, "the pool did not open at the derived tick");
        assertEq(sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickLower));
        // The opening price is about 2.5e-6 IMD per TESTER: 1e27 TESTER valued at 2500 IMD.
        uint256 priceE18 = FullMath.mulDiv(uint256(sqrtPriceX96) * 1e9, uint256(sqrtPriceX96) * 1e9, 2 ** 192);
        assertApproxEqRel(priceE18, 2_500_000_000_000, 0.01e18, "opening price off the 2500 IMD cap");
        assertEq(manager.getLiquidity(key.toId()), liquidity);
        assertEq(_circulating(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_traderBuysAndSellsThroughThePoolManagerAndTheLpEarnsTheFee() public {
        _launch(true);
        TraderStub trader = _newTrader(10e18);
        uint256 managerBefore = token.balanceOf(POOL_MANAGER);

        (uint256 bought, uint256 paid) = _buy(trader, -1e18);
        assertEq(paid, 1e18, "exact-input buy charged something else");
        assertEq(token.balanceOf(address(trader)), bought, "trader received less TESTER than the manager delivered");
        assertEq(token.balanceOf(POOL_MANAGER), managerBefore - bought, "manager lost a different amount");
        assertEq(imd.balanceOf(address(trader)), 9e18);
        assertEq(imd.balanceOf(POOL_MANAGER), 1e18);
        // Roughly 1 IMD / 2.5e-6, less the 1.25% fee and slippage.
        assertLt(bought, 400_000e18);
        assertGt(bought, 390_000e18);

        (uint256 sold, uint256 received) = _sell(trader, -int256(bought));
        assertEq(sold, bought, "exact-input sell took something else");
        assertEq(token.balanceOf(address(trader)), 0, "trader could not sell everything");
        assertEq(token.balanceOf(POOL_MANAGER), managerBefore, "manager did not get the sold tokens back whole");
        assertLt(received, 1e18, "round trip must cost the fee");
        assertGt(received, 0.97e18, "round trip lost more than two fees and slippage");
        assertEq(imd.balanceOf(address(trader)), 9e18 + received);

        // The 1.25% fee of each leg accrued to the factory's position; protocol fee is zero.
        BalanceDelta fees = factory.collectFees(key, tickLower, tickUpper);
        int128 feeToken = tokenIsCurrency0 ? fees.amount0() : fees.amount1();
        int128 feePair = tokenIsCurrency0 ? fees.amount1() : fees.amount0();
        assertApproxEqRel(uint256(uint128(feePair)), 1e18 * uint256(POOL_FEE) / 1e6, 0.001e18, "IMD fee off");
        assertApproxEqRel(uint256(uint128(feeToken)), sold * uint256(POOL_FEE) / 1e6, 0.001e18, "TESTER fee off");
        assertEq(token.balanceOf(address(factory)), uint256(uint128(feeToken)), "fee take arrived short");
        assertEq(imd.balanceOf(address(factory)), uint256(uint128(feePair)));
        assertEq(_circulating(), SUPPLY, "trading created or destroyed TESTER");
    }

    function test_exactOutputBuyDeliversExactlyTheAskedAmount() public {
        _launch(true);
        TraderStub trader = _newTrader(10e18);
        (uint256 bought, uint256 paid) = _buy(trader, int256(123_456_789_012_345_678_901_234));
        assertEq(bought, 123_456_789_012_345_678_901_234, "manager delivered something else");
        assertEq(token.balanceOf(address(trader)), bought, "exact-output buy arrived short");
        assertGt(paid, 0);
        assertEq(imd.balanceOf(address(trader)), 10e18 - paid);
        // And an exact-output sell: the trader asks for IMD out and the token side is taken whole.
        (uint256 sold, uint256 received) = _sell(trader, int256(0.1e18));
        assertEq(received, 0.1e18);
        assertEq(token.balanceOf(address(trader)), bought - sold, "exact-output sell took something else");
        assertEq(_circulating() + token.balanceOf(address(trader)), SUPPLY);
    }

    function test_launchAndSwapsWorkWhenTesterIsCurrency1() public {
        _launch(false);
        assertFalse(tokenIsCurrency0);
        (, int24 tick,,) = manager.getSlot0(key.toId());
        assertEq(tick, tickUpper, "the pool did not open at the derived tick");
        TraderStub trader = _newTrader(5e18);
        uint256 managerBefore = token.balanceOf(POOL_MANAGER);
        (uint256 bought,) = _buy(trader, -2e18);
        assertEq(token.balanceOf(address(trader)), bought);
        assertEq(token.balanceOf(POOL_MANAGER), managerBefore - bought);
        assertGt(bought, 780_000e18);
        (uint256 sold,) = _sell(trader, -int256(bought));
        assertEq(sold, bought);
        assertEq(token.balanceOf(address(trader)), 0);
        assertEq(token.balanceOf(POOL_MANAGER), managerBefore);
        assertEq(_circulating(), SUPPLY);
    }

    function test_manyTradersInSequenceConserveTheSupply() public {
        _launch(true);
        TraderStub[5] memory traders;
        uint256 heldByTraders;
        for (uint256 i; i < 5; ++i) {
            traders[i] = _newTrader((i + 1) * 1e18);
            (uint256 bought,) = _buy(traders[i], -int256((i + 1) * 1e18));
            heldByTraders += bought;
            assertEq(token.balanceOf(address(traders[i])), bought);
        }
        assertEq(_circulating() + heldByTraders, SUPPLY);
        // Each sells half, then the rest.
        for (uint256 i; i < 5; ++i) {
            uint256 half = token.balanceOf(address(traders[i])) / 2;
            (uint256 sold,) = _sell(traders[i], -int256(half));
            assertEq(sold, half);
            (sold,) = _sell(traders[i], -int256(token.balanceOf(address(traders[i]))));
            assertEq(token.balanceOf(address(traders[i])), 0);
        }
        assertEq(_circulating(), SUPPLY, "supply not conserved through many trades");
        assertEq(token.balanceOf(POOL_MANAGER), seeded, "manager did not end with exactly the seed");
    }

    // ------------------------------------------------------------------ failure paths ------------

    function test_traderCannotSellTesterItDoesNotHold() public {
        _launch(true);
        // Someone has to buy first: a single-sided seed above the opening price holds no IMD, so
        // until then a sell is a zero-amount swap rather than a trade.
        _buy(_newTrader(1e18), -1e18);
        TraderStub trader = _newTrader(1e18);
        (uint160 priceBefore,,,) = manager.getSlot0(key.toId());
        uint256 managerBefore = token.balanceOf(POOL_MANAGER);
        uint256 managerImdBefore = imd.balanceOf(POOL_MANAGER);
        // The pool accepts the swap; paying for it is where the token refuses, and the lock unwinds.
        vm.expectRevert(abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, address(trader), 0, 1e18));
        trader.swap(key, tokenIsCurrency0, -int256(1e18));
        (uint160 priceAfter,,,) = manager.getSlot0(key.toId());
        assertEq(priceAfter, priceBefore, "a failed sell moved the price");
        assertEq(token.balanceOf(POOL_MANAGER), managerBefore, "a failed sell moved tokens");
        assertEq(imd.balanceOf(POOL_MANAGER), managerImdBefore, "a failed sell paid out IMD");
        assertEq(token.balanceOf(address(trader)), 0);
        assertEq(imd.balanceOf(address(trader)), 1e18);
    }

    function test_traderCannotBuyWithImdItDoesNotHold() public {
        _launch(true);
        TraderStub trader = _newTrader(0);
        uint256 managerBefore = token.balanceOf(POOL_MANAGER);
        vm.expectRevert("IMD: balance");
        trader.swap(key, !tokenIsCurrency0, -int256(1e18));
        assertEq(token.balanceOf(POOL_MANAGER), managerBefore);
        assertEq(token.balanceOf(address(trader)), 0, "a failed buy delivered tokens");
    }

    function test_factoryCannotSeedMoreThanItHolds() public {
        // A seed that would need more TESTER than the factory holds is refused by the token, and
        // the manager's lock unwinds with it: nothing is credited, nothing moves.
        _launch(true);
        uint256 remaining = token.balanceOf(address(factory));
        assertEq(remaining, 0);
        uint256 managerBefore = token.balanceOf(POOL_MANAGER);
        (uint128 extra, uint256 needed) = _liquidityForAboutOneTester();
        vm.expectRevert(
            abi.encodeWithSelector(TESTERToken.ERC20InsufficientBalance.selector, address(factory), 0, needed)
        );
        factory.seed(key, tickLower, tickUpper, extra);
        assertEq(token.balanceOf(POOL_MANAGER), managerBefore);
        assertEq(manager.getLiquidity(key.toId()), liquidity, "a failed seed changed liquidity");
    }

    function test_sendingTesterStraightToTheManagerIsNotCredited() public {
        // Tokens pushed to the manager outside an unlock are stranded, not swapped: a plain
        // ERC-20 has no way to tell the manager, and the manager keeps them.
        _launch(true);
        vm.prank(DISTRIBUTOR);
        token.transfer(POOL_MANAGER, 1e18);
        assertEq(token.balanceOf(POOL_MANAGER), seeded + 1e18);
        TraderStub trader = _newTrader(1e18);
        (uint256 bought,) = _buy(trader, -1e18);
        assertEq(token.balanceOf(address(trader)), bought, "stray tokens altered a swap");
        assertEq(token.balanceOf(POOL_MANAGER), seeded + 1e18 - bought);
    }

    /// @dev Liquidity for the factory's range worth about one TESTER, and the exact amount the
    /// manager will ask for it (liquidity is coarser than a wei of token).
    function _liquidityForAboutOneTester() internal view returns (uint128 l, uint256 needed) {
        uint160 a = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 b = TickMath.getSqrtPriceAtTick(tickUpper);
        l = uint128(FullMath.mulDiv(1e18, FullMath.mulDiv(a, b, Q96), b - a));
        needed = SqrtPriceMath.getAmount0Delta(a, b, l, true);
        assertApproxEqAbs(needed, 1e18, 1e4);
    }

    // ------------------------------------------------------------------ properties ---------------

    function testFuzz_buyThenSellAllRoundTripsAndConservesSupply(uint256 imdIn, bool token0) public {
        imdIn = bound(imdIn, 1e9, 10_000e18);
        _launch(token0);
        TraderStub trader = _newTrader(imdIn);
        (uint256 bought, uint256 paid) = _buy(trader, -int256(imdIn));
        assertEq(paid, imdIn);
        assertEq(token.balanceOf(address(trader)), bought);
        assertEq(token.balanceOf(POOL_MANAGER), seeded - bought);
        (uint256 sold, uint256 received) = _sell(trader, -int256(bought));
        assertEq(sold, bought);
        assertEq(token.balanceOf(address(trader)), 0, "could not sell everything back");
        assertEq(token.balanceOf(POOL_MANAGER), seeded, "the manager did not end with exactly the seed");
        assertLt(received, imdIn, "a round trip through a 1.25% pool cannot be free");
        assertEq(_circulating(), SUPPLY);
    }
}

/// @notice Random buys and sells of bounded size by a single trader against the seeded pool.
contract PoolTradeHandler is Test {
    TESTERToken public immutable token;
    PairTokenStub public immutable imd;
    TraderStub public immutable trader;
    PoolKey internal key;
    bool internal tokenIsCurrency0;

    uint256 public totalBought;
    uint256 public totalSold;
    uint256 public buys;
    uint256 public sells;

    constructor(TESTERToken token_, PairTokenStub imd_, TraderStub trader_, PoolKey memory key_, bool token0) {
        token = token_;
        imd = imd_;
        trader = trader_;
        key = key_;
        tokenIsCurrency0 = token0;
    }

    function buy(uint256 imdIn) external {
        imdIn = bound(imdIn, 1e6, 100e18);
        imd.mint(address(trader), imdIn);
        uint256 before = token.balanceOf(address(trader));
        BalanceDelta d = trader.swap(key, !tokenIsCurrency0, -int256(imdIn));
        int128 tokenDelta = tokenIsCurrency0 ? d.amount0() : d.amount1();
        uint256 got = uint256(uint128(tokenDelta));
        assertEq(token.balanceOf(address(trader)), before + got, "buy arrived short");
        totalBought += got;
        ++buys;
    }

    function sell(uint256 amount) external {
        uint256 held = token.balanceOf(address(trader));
        if (held == 0) return;
        amount = bound(amount, 1, held);
        BalanceDelta d = trader.swap(key, tokenIsCurrency0, -int256(amount));
        int128 tokenDelta = tokenIsCurrency0 ? d.amount0() : d.amount1();
        assertEq(uint256(uint128(-tokenDelta)), amount, "sell took a different amount");
        assertEq(token.balanceOf(address(trader)), held - amount, "sell debited a different amount");
        totalSold += amount;
        ++sells;
    }
}

/// @title Pool invariants
/// @notice After any sequence of buys and sells, the manager holds exactly the seed plus net sales,
/// the trader holds exactly net purchases, and not one unit of the fixed supply has gone anywhere else.
contract TESTERTokenPoolInvariantTest is TESTERLaunchBase {
    PoolTradeHandler internal handler;
    TraderStub internal trader;

    function setUp() public {
        _setUpInfrastructure();
        _launch(true);
        trader = _newTrader(0);
        handler = new PoolTradeHandler(token, imd, trader, key, tokenIsCurrency0);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 40
    function invariant_managerHoldsTheSeedPlusNetSales() public view {
        assertEq(
            token.balanceOf(POOL_MANAGER),
            seeded + handler.totalSold() - handler.totalBought(),
            "manager balance disagrees with the swaps"
        );
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 40
    function invariant_traderHoldsNetPurchases() public view {
        assertEq(token.balanceOf(address(trader)), handler.totalBought() - handler.totalSold());
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 40
    function invariant_supplyIsConservedAcrossTrading() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(_circulating() + token.balanceOf(address(trader)), SUPPLY, "units left the known holders");
    }
}
