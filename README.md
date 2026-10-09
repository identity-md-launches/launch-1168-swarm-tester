# Swarm Tester (TESTER)

`src/TESTERToken.sol` is a dependency-free ERC-20 for Ethereum mainnet.
Its constructor takes no arguments and mints exactly **1,000,000,000 TESTER**
with 18 decimals (`1000000000000000000000000000` minor units) to `msg.sender`.
For the launch, that deployer is the launch factory. Construction makes no
external calls and works on an empty chain.

Name, symbol, decimals and total supply are constants. There is no owner,
administrator, mint or burn function, pause, blacklist, fee, transfer limit,
proxy or upgrade mechanism. The contract has no external calls, delegate calls
or destruction mechanism. Holders transfer their own balances; spenders can
transfer only within allowances granted by holders. The deployer has no special
powers after receiving the initial supply.

Transfers deliver the exact requested amount, including to and from contracts.
Zero-value transfers and self-transfers are supported. Transfers involving the
zero address and approvals to the zero address revert. Insufficient balances
or allowances revert with ERC-6093 errors and leave all state unchanged.
`approve` replaces the current allowance; `type(uint256).max` means unlimited
and is not reduced by `transferFrom`. `Approval` is emitted on `approve`, while
`Transfer` is emitted on minting and every successful transfer. Allowance
consumption does not emit an additional `Approval`. Clients changing an existing
allowance should account for the standard ERC-20 approval ordering race.

## Build and smoke tests

Run at the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

The compiler is pinned in `foundry.toml`: Cancun EVM, optimizer enabled with 200
runs, and `bytecode_hash = "none"`. All imports resolve to repository files;
there are no packages or submodules to fetch. Tests require no RPC, environment
variables, keys, FFI or filesystem permissions.

The eight smoke tests cover deployment and full supply, exact transfers in both
directions at the specified PoolManager address, transfer and approval events,
allowance spending, self/zero transfers, insufficient funds/allowances, failure
rollback, and zero-address rejection. The PoolManager test checks token movement
using impersonation, not pool initialization or actual swaps. The provided
protected harness belongs to the independent launch checks and is not copied
into this project. Full fuzz/invariant testing and Uniswap v4 integration testing
are reserved for the subsequent test contributor; this smoke suite is not an audit.

## Deployment and launch responsibilities

`launch.json` is the complete manifest, including no application contracts and
an empty constructor argument list. Ethereum mainnet (chain ID 1) is selected
by the order and is intentionally not a manifest field. The launch operator
deploys the compiled `TESTERToken` creation bytecode through the factory and
verifies the deployed source using the pinned compiler settings.

The factory receives **100%** of the supply before doing any distribution. The
factory, not this token, sends 10% (100,000,000 TESTER) through its Merkle
distributor, uses the 90% pool allocation (900,000,000 TESTER) to seed liquidity,
and forwards any unspent remainder to the explicitly requested
`0x000000000000000000000000000000000000dead`. There is no separately reserved
token allocation and no token-side distribution logic. The nominal percentages
consume the entire supply; the factory handles any liquidity rounding remainder.

The fixed launch parameters are:

| Parameter | Value |
| --- | --- |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals) |
| Uniswap v4 PoolManager | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Pool fee | `12500` (1.25%, a pool swap fee; TESTER transfers have no fee) |
| Tick spacing | `60` |
| Provenance initialPrice | `125270724187523965593206900` |
| poolBps | `9000` |
| initialMarketCapWei | `2500000000000000000000` (2,500 IMD in minor units) |

The manifest's `initialPrice` is the supplied sqrtPriceX96 provenance value,
assuming TESTER is currency0 and pricing paired-currency minor units per TESTER
minor unit. The launch operator derives the actual opening price from the
economics and deployed currency order. The target opening price is 0.0000025
IMD per TESTER. The contract does not read the manifest or enforce market price.

The chain addresses and economics above come from the assignment. The operator
is responsible for factory distribution, pool setup, Merkle claims and source
verification; none require token administration or post-launch token settings.
This project performs no broadcasts or live-chain verification.
