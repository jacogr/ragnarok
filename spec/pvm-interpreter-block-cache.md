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


## Bounded secondary working set, 2026-10-23

The October23 compiler baseline (`4724f66c2`) still spends most sampled sieve time
in pipeline pricing. A separately instrumented copy of ordinary public execution
records353856 unpaid-block visits across1015 distinct starts at sieve limit100000.
Offline replay gives252310 misses for the first-plus-three policy, versus1721 for
an eight-set/two-way LRU experiment. These are trace-policy diagnostics, not elapsed
time or a claim that the final insertion policy has the same exact miss count.

Execution retains its original pinned first price and three recent hot prices.
Only a miss reaches a non-inlined secondary lookup with sixteen scalar entries in
eight two-way sets. Wrapping multiplicative address mixing selects the top three
bits; checked array accesses remain enabled and complete address tags decide hits.
Successful simulation fills the hot ring and one secondary way, alternating that
set's insertion slot. Hits remain read-only; no replacement counter grows with guest
work. The table uses fixed invocation-owned stack storage, no allocation, global
state, owner reference, program preparation pass or new caller resource default.
The twenty total slots may contain duplicate prices across the hot and secondary
levels. Capacity and mixing are private implementation choices.

Every actual visit still checks/debits the current gas balance. Interior unpaid
entry still resolves the containing start; failures never insert. The program,
profile and cycle limit remain fixed across host replies, and new/nested invocations
start empty. Gas/step refusals and source/host/fault ownership contracts are unchanged.

Literal starts9/30/64/85/98/119 all collide in one secondary set and exceed both hot
and secondary capacity. Different dependent-multiply blocks recur four times;
complete public-single-step CPU/gas parity and the exact step refusal remain required.
Twenty-four recurrent blocks exceed all slots, including across the independently
framed two-byte code length. Existing exact-gas, interior-entry, lower-limit,
new-owner, callback and retry tests remain controls, with1000 balanced ARC cycles.
The benchmark contract records repeated real/small-workload measurements and costs.

## Larger working sets with a bounded lazy owner, 2026-10-24

The maintained Pinky frame executes32,055,270 PVM instructions. A fresh uninstrumented
macOS sample of merged master`32d1e9c4` attributes most dynamic execution samples to
whole-block simulation, while complete-plan execution spends most samples decoding.
These are separate costs; this increment changes only invocation-local price reuse.

The first successful price remains pinned and three recent prices remain inline.
After the fifth distinct successful miss, execution allocates one private secondary
owner with128 scalar entries in64 two-way sets and64 replacement flags. It seeds the
three preceding recent facts before replacement, then inserts the new successful price.
Invocations using at most four distinct prices allocate no secondary owner. Complete
plan execution bypasses this cache; lazy memo execution retains its existing front
cache semantics. Each secondary lookup checks both validity and the full original
address. Multiplicative hashing selects six bits; insertion alternates the two fixed
ways and has no growing guest-controlled counter.

This replaces the old sixteen-entry stack secondary table. The new scalar payload
is roughly3.1KiB before ARC/allocator overhead on the measured profile, once per
invocation under pressure. The reference contains no program, machine, memory, host
context or balance. Its only owners are the private invocation cache and synchronous
local temporaries; there are no cycles or exported aliases. It remains alive across
host replies and is destroyed on every successful or failed invocation return.
The local retained lookup owner is intentional: removing that retain with a cursor
reduced generated C bookkeeping but regressed the representative sieve measurement.

All existing admission, fixed-program/cycle-limit, paid-entry, per-visit debit,
callback/fault and source-snapshot contracts remain unchanged. Only complete successful
prices enter the table; a simulation refusal neither allocates nor inserts a new fact.
New/nested invocations start empty. There is no new prepared representation or public API.

The cache suite retains its historical24-block case and adds144 recurrent blocks,
exceeding the132 total hot/secondary positions even before duplicates. Six literal
starts9/64/153/208/297/352 all share secondary set35 and repeatedly execute different
multiply-dependent prices. Complete public-single-step CPU/gas parity, exact final
registers, one-less step refusal and retained sources check both cases. Existing
thousand-cycle ARC controls exercise spill creation and every ordinary host/refusal
boundary; all occupied memory must be released.

An initial fixed128-entry stack layout reduced dynamic Pinky time but repeatedly
regressed memo-priced sieve by12–14%. A cursor lookup and a separately specialized
dynamic/memo policy also regressed that control. Those variants were rejected; neither
lower ARC operation counts nor a larger table alone establishes a speed improvement.
Raw rejected and accepted-candidate measurements, sources and binaries remain under
`build/pvm12/`; the uninstrumented profile is under`build/pvm12/baseline/`.

The final checked ARC/Clang ThinLTO comparison retains two opposite process orders,
three warmups and ten measured samples per process on all seven bounded real-guest
inputs and all three pricing modes:1,092 complete-state-checked invocations. CPU
medians in milliseconds (preparation excluded) on M1 Max/macOS:

| Input | Pricing | Parent | Lazy secondary | Change |
| --- | --- | ---: | ---: | ---: |
| Sieve100,000 | Dynamic | 16.001 | 14.971 | -6.4% |
| Sieve100,000 | Complete plan | 10.714 | 10.883 | +1.6% |
| Sieve100,000 | Lazy memo | 11.383 | 11.358 | -0.2% |
| Memory fill100,000 | Dynamic | 12.149 | 11.315 | -6.9% |
| Memory fill100,000 | Complete plan | 10.854 | 10.830 | -0.2% |
| Memory fill100,000 | Lazy memo | 11.967 | 11.271 | -5.8% |
| Pinky frame | Dynamic | 4,673.302 | 2,718.181 | -41.8% |
| Pinky frame | Complete plan | 665.548 | 665.848 | +0.0% |
| Pinky frame | Lazy memo | 754.733 | 744.114 | -1.4% |

Two additional opposite-order control comparisons on the six non-Pinky inputs each
retain936 full-state invocations. They reproduce dynamic sieve improvements of5.6–6.5%
and memory-fill improvements of5.8–7.2% for dynamic/memo pricing. Indirect-call changes,
complete-plan differences and smaller Pinky memo differences are unproven. This is
local interpreter evidence with no CPU affinity/frequency isolation, not exact-head
Linux, compiled-backend, whole-JAM throughput or a universal pricing-policy result.

Selected cache, host-memory-reentry and mixed-policy reference suites pass. Cache
and host reentry each retain1,000 balanced ARC cycles, including spill allocation
and callback/nested invocation retirement. Two complete synthetic comparisons each
pass1,716 validated invocations; smaller planned-workload differences vary by a few
percent (some individual cells reach3–4%), so no general synthetic gain is claimed.
The unchanged calibrated census still passes429 invocations, nine affected Python
instrumentation/guard tests and pinned formatting pass. The accepted raw comparison
is`build/pvm12/charge-lazy-final-paired.json`; the additional controls and rejected
variants are retained alongside it.
