# Upstream sieve: three interpreters

This comparison uses PolkaVM's actual `bench-prime-sieve`, linked once to JAM V1.
PolkaVM is explicitly forced to **Interpreter**. Master and the experiment consume the
same code/jump table, initial registers, pages, permissions, entry point and gas.
The candidate is the shared prepared-table interpreter from the previous increment,
with larger bounded capacity for this guest; production sources remain unchanged.

The Rust algorithm is copied unchanged from pinned PolkaVM commit
`69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa` (v0.37.0). Its upstream README attributes
it to [PrimeRust solution_1](https://github.com/PlummersSoftwareLLC/Primes/tree/708075dd82f5f1aa92c56c5cfd15338f524f03c0/PrimeRust/solution_1).
A separate checked export calls `run_sieve(limit)`, counts primes, validates the result
with the upstream validator and returns the count. Upstream's stock benchmark only
black-boxes `run_sieve(10_000_000)`; our counting/checking adds work. All three engines
execute our same checked export, not different implementations of the algorithm.

The guest has 157,152 code bytes, 38,590 static instruction records, 74 distinct static
opcodes and 262 mapped pages. Static inventory is not a claim that every error path or
every opcode in the ISA has been exercised. It includes the upstream unrolled sieve,
allocator and runtime. Returned counts are independently checked against 168, 1,229,
9,592 and 664,579 for the four sizes below.

## Method

Apple M1 Max, macOS ARM64. Baseline is a separately compiled archive of master commit
`b723f0c1aeaa3b807f062af69004f1fd76352ea5`; its PVM production sources match this branch.
Both Nim binaries use pinned Nimony 0.6.3 (`5b51edfed`), ARC, Clang, checked release and
ThinLTO, with bounds checks enabled. Deliberately failing assertion controls pass for
both binaries before timing. Rust host uses pinned 1.99.0, release with LTO and one
codegen unit; the guest uses upstream nightly-2025-05-10, release with fat LTO.

Primary results use process CPU time (`CLOCK_PROCESS_CPUTIME_ID`) in all three
engines; full wall times are also retained. Two sequential passes reverse engine order.
Each small case has three warmups and ten measured samples per pass, giving twenty
measured samples per engine. The original 10-million case has one warmup and two
measured samples per pass, giving four measured samples per engine. Its limited sample
count and possible frequency/cache contention make small differences inconclusive.
No other experiment compilation or profiling runs concurrently with these timings.

Each engine starts from the same pristine state. PolkaVM module/instance construction,
Nim program decoding and source capture, and candidate preparation/binding are outside
the execution clocks. Per-execution caches, memory operations, gas accounting and
result publication remain inside. PolkaVM uses its public interpreter API with 4 KiB
pages, synchronous gas and `Full(L2Hit)` pricing. Both Nim engines retain their production
simulation limit of 1,000,000 and execution limit of 1,000,000,000 instructions.
The common initial gas allowance is 1,000,000,000,000.

Every timed invocation must halt and return the known prime count. Outside timing,
checks compare exact remaining gas, all thirteen registers and every byte of every
mapped page against PolkaVM's result. Nim additionally checks terminal PC/charging
metadata, permissions and that the original CPU/memory snapshot remains unchanged.
PolkaVM repeats must reproduce the same full reference output. Both passes must have
byte-identical inputs and reference outputs. These are workload differential checks,
not a proof of general equivalence or complete opcode/fault coverage.

## Recorded measurement

| Limit | Engine | CPU ms median (min–max) | Samples | Master / engine |
| ---: | --- | ---: | ---: | ---: |
| 1,000 | polkavm | 0.485 (0.468–0.497) | 20 | 7.018× |
| 1,000 | master | 3.404 (3.215–3.535) | 20 | 1.000× |
| 1,000 | prepared | 3.342 (3.256–3.509) | 20 | 1.018× |
| 10,000 | polkavm | 1.998 (1.940–2.060) | 20 | 13.587× |
| 10,000 | master | 27.140 (26.599–28.060) | 20 | 1.000× |
| 10,000 | prepared | 27.194 (26.533–28.250) | 20 | 0.998× |
| 100,000 | polkavm | 5.944 (5.885–6.284) | 20 | 41.220× |
| 100,000 | master | 244.994 (240.838–251.912) | 20 | 1.000× |
| 100,000 | prepared | 241.750 (239.875–271.408) | 20 | 1.013× |
| 10,000,000 | polkavm | 376.229 (374.851–381.991) | 4 | 78.541× |
| 10,000,000 | master | 29549.548 (28826.875–29973.209) | 4 | 1.000× |
| 10,000,000 | prepared | 29615.132 (29611.721–29680.392) | 4 | 0.998× |

Preparation + binding is excluded from those execution timings. Across eight process
initializations it took median 1.151 ms wall time (range
1.113–1.265 ms), retaining the same 2.66 MiB table for each size.

| Limit | Engine | Pass 1 CPU median, ms | Pass 2 CPU median, ms |
| ---: | --- | ---: | ---: |
| 1,000 | polkavm | 0.493 | 0.476 |
| 1,000 | master | 3.425 | 3.318 |
| 1,000 | prepared | 3.442 | 3.300 |
| 10,000 | polkavm | 2.048 | 1.951 |
| 10,000 | master | 27.297 | 27.043 |
| 10,000 | prepared | 27.668 | 26.613 |
| 100,000 | polkavm | 6.158 | 5.893 |
| 100,000 | master | 250.576 | 241.514 |
| 100,000 | prepared | 250.192 | 240.335 |
| 10,000,000 | polkavm | 375.842 | 378.808 |
| 10,000,000 | master | 29059.577 | 29890.013 |
| 10,000,000 | prepared | 29615.132 | 29646.056 |

At ten million, PolkaVM interpreted is **78.54× faster than master** and
**78.72× faster than prepared**. Prepared differs from master by about 0.2% in the
combined CPU medians, far below what these samples establish. The small-case differences
also do not establish a useful improvement. The larger workload therefore does not
support a broad performance claim for this prepared representation, despite the earlier
arithmetic-loop win.

The table increases retained memory without a demonstrated sieve execution benefit.
The useful next step is to profile execution and isolate the costs that dominate this
workload before adding more IR machinery. Memory ownership/copying and gas/block work
are candidates for investigation; these timings alone do not apportion the gap.

All **252 invocations** passed the workload checks (60 warmups and 192 measured runs).
That includes both engines on the full-size case, all memory bytes/permissions, exact
gas and complete registers. Both assertion controls passed.

## Separate diagnostic profile

After all timing passes completed, a separate two-second macOS `sample` capture ran
against the same master binary at limit 100,000 (13 invocations, all still validated).
Its timings are excluded from the benchmark. Of 1,507 main-thread samples, the callsite
leading to block gas work accounted for 693 and the store path for 297. The largest
named leaf was `blockGas` (596 samples); `store` had 225 leaf samples. Inlining and
sampling make these directional observations, not precise CPU-cost attribution.

This points first to repeated block gas simulation, then to memory stores. Source
inspection agrees that execution currently retains only one block charge, while each
successful scalar store creates a new page-reference vector and clones touched pages.
Prepared instruction records leave both paths intact. A bounded cache of block charges,
keyed to the immutable program and simulation policy, is a more focused next experiment;
its gas-limit/refusal behavior would need the same boundary checks. Store ownership can
be investigated separately while preserving observable immutable snapshots.

The local `master-profile.txt`, `profile-command.json`, `profile-tool.log` and
`profile-workload.log` retain the diagnostic evidence. Capture command was
`sample <master-pid> 2 1 -file <output>` against the generated `nim-master` with the
100,000 input/expected fixtures; it ran only after `make sieve` finished.

## Scope and reproduction

Run `make sieve` as described in [README.md](README.md#upstream-sieve-comparison).
The driver saves commands, full logs, raw warmup/measured samples, per-pass medians,
source/toolchain/binary hashes, original upstream source identities, derived lockfiles,
fixtures, linked artifact and generated source diff under
`build/pvm-ir-experiment/sieve/`. `results.json` binds the measured tree to its sources;
HEAD in that identity is the pre-commit parent, with exact source hashes covering the
new files. Raw evidence is local ignored output, not checked into Git.

Preparation is bounded to 1 MiB code and 65,535 records for this experiment. Actual
retained table payload is 2,784,064 bytes (2.66 MiB), excluding sequence/allocator metadata
and the existing program owner. The original small shared-table experiment's limits
and recorded results are unchanged. This larger table does not demonstrate a general
production policy or a compact optimized IR.

Only interpreter execution is compared. End-to-end loading/startup costs, other real
programs, host calls, fault recovery and Linux measurements remain separate work.
The earlier focused loop/effects checks continue to document those narrower boundaries.
