# Vendored test dependencies

The project has no `lib/` directory and no remappings, so the test suite's dependencies live here as
ordinary committed files and are imported by relative path. Nothing under `src/` depends on them.

| Directory | Source | Version | Licence |
| --- | --- | --- | --- |
| `forge-std/` | github.com/foundry-rs/forge-std (`src/` only) | v1.9.7 | MIT / Apache-2.0 (`LICENSE-MIT`, `LICENSE-APACHE`) |
| `v4-core/` | github.com/Uniswap/v4-core (`src/` without `src/test/`) | commit `46c6834698c48bc4a463a86d8420f4eb1d7f3b75` (2026-04-02) | BUSL-1.1 / MIT per file (`licenses/`) |
| `solmate/` | github.com/transmissions11/solmate (`src/auth/Owned.sol` only) | main | MIT (`LICENSE`) |

One line was changed from upstream: `v4-core/src/ProtocolFees.sol` imports `Owned` from
`../../solmate/src/auth/Owned.sol` instead of the `solmate/` remapping.

The pool tests build the real v4 `PoolManager` in place at its Ethereum mainnet address
(`0x000000000004444c5dc75cB358380D2e3dE08A90`) and etch a plain ERC-20 stand-in at IMD's address
(`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), so no RPC or fork is needed. A run against live
mainnet state with the deployed PoolManager and IMD token is still owed and cannot run offline.
