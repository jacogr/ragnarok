# Execution-local block-price reuse

## Scope, invariant and completion plan

Gray Paper 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401` remains primary. Block
pricing depends on immutable program bytes/register roles and the fixed simulation
cycle limit, not runtime register values or memory. The scoped PolkaVM pricing
exceptions remain unchanged. No new opcode, protocol interpretation or public API is
introduced; checked Nimony ARC/Clang LTO remains mandatory.

A macOS sample of 100 repetitions of the unchanged validated benchmark workloads
found 361/776 top-of-stack samples (about 47%) in `blockGas`, with instruction decoding
next. Profiling uses a separate ignored wrapper so the maintained benchmark inputs,
sample counts and timings are unchanged. Sampling is directional evidence, not a
deterministic instruction count; local cachegrind/hyperfine are unavailable.

Try one private single-entry block-price cache inside each `executeBudget` invocation.
Its immutable program and cycle limit are fixed for that invocation; instruction
successors retain the same program. Cache only completed successful simulation at its
actual containing block start. Every visit still checks affordability and debits gas.
Single-step entry points allocate a fresh empty scalar cache. A host suspension,
fault, terminal exit or new execution call discards the cache; it never crosses
program/profile/limit changes, stores guest balances, or grows with input size.

Completion requires unchanged independent fixture outcomes, low/exact cycle limits,
cross-call/program isolation, source snapshot preservation and local failure behavior.
Run affected execution/host/retry suites and the integrated reference pairs. Preserve
baseline/final binaries and raw opposite-order measurements on fixed fixtures/flags;
retain the optimization only for a repeatable improvement and re-profile afterwards.

## Observed local completion

The selected execution, single-step, host execution/response/failure suites and all
fourteen integrated public-reference/native groups pass. The new execution cases
check exact minimum cycle budget, one-less refusal, every-visit gas debits, different
programs at the same PC, direct-step isolation and source snapshots. Allocation
observations remain stable across 1000 cycles in the selected ARC suites. Pinned
formatting passes; no checks, pipeline prices or public ownership contracts changed.

On Apple M1 Max, ordinary checked ARC/Clang LTO baseline/final executables replayed
the same frozen fixture. After three process warmups per variant, ten paired runs
(first five baseline/final, last five final/baseline) retained 100 measured samples
per workload/variant, plus the driver's validated warmups. Medians in microseconds:

| Workload | Before | After | Before / after |
| --- | ---: | ---: | ---: |
| arithmetic-10000 | 4950.69 | 2445.94 | 2.02× |
| memory-aligned-1000 | 1451.29 | 591.60 | 2.45× |
| memory-crossing-1000 | 1607.75 | 752.31 | 2.14× |
| hosts-aligned-1000 | 2090.08 | 2091.04 | 1.00× |
| hosts-crossing-1000 | 2248.04 | 2240.19 | 1.00× |

The host-heavy differences are within noise and are not claimed as improvements.
Their execution segments discard this cache at each host suspension. Raw ranges,
samples, source/binary hashes and starting/ending load averages are retained in
`build/pvm-interpreter-profile/ab-results.json`; standard baseline results remain in
`build/tests/pvm-benchmark/`. Sampling controls use separate repeated-workload
executables and never contribute performance-table timings. No deterministic
instruction-count or exact-head Linux result is claimed from these local measurements.

Remaining costs include repeated instruction decoding and snapshot validation.
Cross-host reuse would need a separately reviewed invariant and host/refusal tests;
it is not implied by this segment-local optimization.

The subsequent [invocation-local extension](pvm-host-price-reuse.md) preserves this
same scalar memo across host replies, relying on the existing fixed-program/fixed-limit
host-response boundary. The segment-local measurements and lifetime discussion above
describe this first optimization; the extension has its own evidence and regression cases.
