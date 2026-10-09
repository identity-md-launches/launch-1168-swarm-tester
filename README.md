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

## Website

The one-page site of Swarm Tester lives in `site/` and is published from the
committed export in `dist/` at https://swarmtester.si-md.xyz. It is static
HTML, CSS and JS with no build step: `site/index.html`, `site/styles.css`,
`site/app.js` and `site/assets/` (logo, the SIMD panel art, self-hosted latin
subsets of Inter and IBM Plex Mono). It follows the SIMD Swarm meme template
(beige hardware panels, green signal accents, a black terminal) personalized
for $TESTER with the lab-coat blue of the logo as secondary accent, a Swarm Lab
of Pepe engineers compiling at glowing terminals, and Einstein's machine with
clickable dials, levers and a BUILD button that launches a coin rocket.

Live data: the page fetches `/simd-coin.json` from its own origin (served by
SIMD) and paints name, symbol, chain, status, market readouts and the contract
address. The address is never hardcoded: the contract LCD reads `launching…`
and the copy button stays disabled until `token` arrives, and the Buy and Chart
buttons point at the launchpad until `coinUrl` and `chartUrl` arrive. No wallet
connection, no forms, no trackers, no third-party requests.

### Install, preview, rebuild, publish

Requires Node 20+ and npm. Run inside `site/`:

```sh
cd site
npm install            # dev dependency: typescript (for the typecheck only)
npm run preview        # serves ../dist at http://localhost:4173 with a sample /simd-coin.json
npm run preview -- --live   # same, with a sample that includes a token and market data
npm run preview -- --src    # serve the source in site/ instead of dist/
npm run build          # copies site/ into ../dist and checks the export
npm run typecheck      # tsc --noEmit on app.js (strict, checkJs)
npm run check          # headless-Chrome interaction, layout and contrast checks + screenshots
npm run verify         # build + typecheck + check
```

To change the site, edit the files in `site/`, run `npm run verify`, and commit
`site/`, `dist/` and the screenshots. The publisher serves the committed `dist/`
exactly as it is and does not rebuild, so always rebuild after the last source
change. Asset URLs are relative (`./assets/...`), so the export also works from
a subpath or an ENS gateway. Do not commit `site/node_modules`.

`npm run check` needs Playwright: it resolves it from `site/node_modules`, from
the directory in `$PLAYWRIGHT_DIR`, or from a globally installed
`@playwright/mcp`; it launches Google Chrome (`PW_CHANNEL=chrome` by default,
falling back to Playwright's bundled Chromium). The script starts its own local
server, drives the export at 320, 390, 768 and 1280px, and writes screenshots to
`artifacts/screenshots/`.

### Validation results

Recorded in `artifacts/validation.md` (coverage of the six Better Interface
domains, findings, fixes, limitations; `artifacts/` is delivered separately
from the Git tree, so an identical copy is kept at `site/VALIDATION.md`).
Final run on the committed source:
`npm run build` exit 0 (8 files, 306,481 bytes), `npm run typecheck` exit 0,
`npm run check` 48 passed / 0 failed / 0 skipped, `forge build` and `forge test`
51 passed. Checks not performed: screen-reader session, forced-colors mode,
native 200% zoom, physical devices; the published origin's real
`/simd-coin.json` was mocked. The design system of the final source is
documented in `DESIGN.md`.
