# YulERC20

A fully ERC-20 compliant token written in **inline Yul assembly**. No OpenZeppelin. No Solidity logic. Pure opcodes.

Built as a 4-day deep dive into EVM internals using Foundry.

## What's inside

- `src/YulERC20.sol` — Full ERC-20 in a single fallback function with a manual selector router
- `src/OZToken.sol` — OpenZeppelin ERC20 wrapper for benchmarking
- `test/YulERC20.t.sol` — 42 tests: unit, fuzz, raw storage verification, calldata anatomy
- `test/GasBenchmark.t.sol` — Side-by-side gas comparison
- `GAS_REPORT.md` — Full benchmark analysis

## Gas Results

| Operation | OpenZeppelin | Yul | Saved |
|---|---|---|---|
| Deploy | 864,990 | 294,595 | **−65.9%** |
| transfer | 38,481 | 37,273 | −3.1% |
| transferFrom | 52,870 | 50,661 | −4.2% |
| approve | 33,188 | 32,209 | −3.0% |

## Run it

```bash
forge test -vv
forge snapshot
```

## Storage layout

| Slot | Variable |
|---|---|
| 0 | totalSupply |
| 1 | balanceOf mapping |
| 2 | allowance mapping |
| 3 | name (bytes32) |
| 4 | symbol (bytes32) |
| 5 | decimals |

## Concepts covered

Manual ABI decoding · keccak256 slot derivation · calldata layout · mstore/sstore/sload · log3 event emission · Foundry fuzz testing · forge snapshot gas benchmarks
EOF