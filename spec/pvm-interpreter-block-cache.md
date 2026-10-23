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


## Bounded multi-block pricing, 2026-10-23

The current invocation memo holds four successful prices: a fixed first-block entry
checked directly, plus three recent secondary entries inspected in bounded order.
Only a successful miss replaces the next secondary entry; a 0..2 index wraps through
explicit branches. Failed simulations never populate, evict or advance replacement.
All fields are private scalars. The memo retains no program, machine, memory, host
context, guest balance or partial simulator state, and allocates no heap storage.

An exact cached start also certifies block membership in this invocation's immutable
program. On that hit, execution can reuse the price before repeating a containing-block
scan. Arbitrary interior entry still resolves its complete containing block and pays
the full price, including skipped instructions. Every visit independently checks
current affordability and debits gas, including primary/secondary hits. A new call or
simulation limit starts with no prices. Host replies retain the same program/profile
and limit, so both callback forms keep this bounded memo for the same invocation.

A new alternating two-block guest exposes repeated single-entry eviction. Independent
pipeline simulation prices its blocks at 15 and22, with terminal22, at their actual
code PCs. Both embeddings validate all three prices and every final register/gas
value. The oracle accepts a code prefix for nonzero block PCs; default-prefix fixtures
remain byte-identical. All original ten benchmark records are independently hash
protected. Memoryless kind5 uses auxiliary address/initial-word header slots for the
second block PC/price; it has no guest memory payload or new unbounded field.

`pvm_execution_cache` adds complete public-step comparisons, exact cached-hit gas
shortages, lower-limit isolation, interior entry, and five recurrent blocks exceeding
four-price capacity. The pressure blocks have independently known prices
15/15/16/21/22, plus terminal22, so stale/wrong-start reuse changes observable gas.
These cases join the existing 1000-cycle ARC group and nested program/callback controls.
A compiler guard keeps cached price lookup invocation-owned. Independent pipeline,
unsigned-gas, host/fault/repair and snapshot controls remain required.

Matched eleven-guest binaries show approximately 87% less alternating-block time and
10–12% less long arithmetic time. Full samples, smaller-workload limits and pinned
interpreter ratios are in the benchmark contract. No pipeline equation, opcode fee,
profile, pin or runtime check changed. M1 framing remains scoped completion; full
STF/JAM parity is still open. Fuzzing and compiled comparison remain deferred.
