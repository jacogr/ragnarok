# Maintained real-guest interpreter pack

`make bench-pvm-guests` compares three additional frozen checked upstream workloads against pinned
PolkaVM **Interpreter**, JamV1, Sync/Full/L2Hit. Ragnarök uses dynamic pricing, complete immutable
plans and lazy memos. This broadens the [real-sieve comparison](pvm-sieve-benchmark.md) with indirect
function calls, memory fill and one initialized Pinky NES frame. Perf PVM runs the pack
on master pushes and existing performance/full requests. It adds no production execution
API, compiled backend, dependency upgrade or historical compiler installation.

## Frozen inputs and independent expectations

The [fixture pack](../tests/fixtures/pvm-guests/README.md) retains upstream licenses, artifact and
source digests, normalized rebuild manifests, guest lock and checked entries. Minimal retains the
unchanged `bench-minimal` function-pointer loop, resetting state before 1,000 or 100,000 iterations;
its independent result is `2*limit + limit%2`. Memory fill retains the exact upstream source prefix
through `benchmark_run`, omitting the separate accelerated/naive/compiler-builtins exports and an
unused dependency. Its checked entry resizes the existing vector to the selected extent, runs the
original fill once and verifies every byte, returning `limit-1`. The original 4 MiB allocator remains
mapped. Guest allocation, initialization and checked-result validation are included in execution
timing in both interpreters. These adapted executions are not published stock benchmark scores.

The [separate Pinky fixture](../tests/fixtures/pvm-pinky/README.md) retains the pinned
NES emulator and homebrew ROM. Its public initializer runs nine frames untimed before
input capture. Both measured interpreters start from the exact initialized memory;
the reference restores writable pages into fresh instances outside timing. The checked
entry renders/converts one frame and returns one after completion. Complete framebuffer
and NES state are part of the memory comparison. This completion witness is not an
independent NES oracle. Pinky guest initialization is excluded, unlike the minimal and
memory-fill setup within their checked entries; each timing boundary is explicit.

Every member and recorded upstream source is mandatory. All guest and host dependency identities
must already occur in the existing pinned locks. Coordinated provenance/checksum edits cannot
substitute another family, source prefix or unpinned package. Normal runs read immutable linked
artifacts; explicit rebuild instructions retain the existing nightly, public linker and profiles.

## Process, state and measurement contract

One explicit immutable family selects independent expectations in each adapter. Every new measured
process emits a mandatory first family witness before pricing metadata/samples. Raw parsing and
structured summaries reject missing, duplicate or foreign witnesses. Existing sieve framing remains
compatible. All four engine/pricing modes must fail their assertion sentinel and reject truncated
initial bytes, corrupted expected registers and foreign family selection before measurements.

Untimed public interpreted preparation freezes the exact initial CPU/memory and terminal reference.
Every execution compares final gas, all thirteen registers and every mapped page byte, plus the
independent result. Ragnarök also verifies normalized terminal PC, paid-block flag, zero deficit,
permissions and preservation of the original CPU and memory snapshots. Input/result hashes are
checked before and after every measured process. No expected output is regenerated during timing.

Minimal and memory fill have two sizes each; Pinky has one frame. Each uses four
engine/pricing modes and two reversed process orders. Every pass contains three warmups
and ten measured fresh-machine executions: 520 total raw CPU/wall samples across the pack. Construction/reset and complete state comparison stay outside the execution clocks.
Pricing initialization and first-cold execution are shown separately from warmed medians; memo
learning in sample zero stays visible. The existing spread and pass-dispersion flags retain noisy
observations rather than filtering them. This does not provide CPU affinity/frequency isolation.

Outputs live under `build/tests/pvm-guests/`: aggregate JSON/CSV/Markdown and per-family complete
reports, controls and logs. All children must pass with exact identities before an aggregate table
or downloadable CSV appears. A failure in any child fails the pack and retires stale aggregate
success; partial child evidence remains inspectable. Source/toolchain/hardware/build identities and
actual executable hashes qualify every result. No remote workflow is triggered by local execution.

## Local observations and remaining work

Initial checked ARC/Clang ThinLTO M1 Max CPU medians were:

| Workload | Size | Dynamic ms | Complete plan ms | Lazy memo ms | PolkaVM interpreted ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Indirect calls | 1,000 | 0.362 | 0.344 | 0.341 | 0.076 |
| Indirect calls | 100,000 | 34.795 | 33.873 | 33.821 | 6.003 |
| Memory fill | 1,000 | 0.220 | 0.156 | 0.171 | 0.134 |
| Memory fill | 100,000 | 14.546 | 13.335 | 14.487 | 3.943 |

The large indirect-call gap remains roughly 5.6–5.8x, while large memory fill is about 3.4–3.7x.
Reusable pricing helps these workloads less than sieve, and memo reuse is not universally faster
than complete plans. These results identify further control/dispatch and sustained-memory work;
they establish neither whole-JAM throughput nor Linux performance. Keep future optimizations tied
to all maintained workloads rather than overfitting one guest. Fuzzing remains deferred pending
maintainer Daybreak access. M1 framing is complete in its documented scope; full state serialization
and whole-JAM/STF equivalence remain open.

## CI workload expansion, 2026-10-24

The expanded Perf PVM sequence (`make bench-pvm bench-pvm-sieve bench-pvm-guests`)
passed locally on M1 Max/macOS with pinned Nimony 0.6.3, checked release ARC/Clang
ThinLTO and pinned PolkaVM interpreted JamV1 Sync/Full/L2Hit. Production PVM code
is unchanged from master 8ec989d6; the measured working-tree host/fixture/report
sources and actual binaries are SHA-256 recorded in each report. The synthetic
comparison passed as well. The real guests retained 936 raw CPU/wall observations
including warmups; every cell below has twenty measured execution CPU samples
across two reversed-order passes, and every process satisfied the existing
pass/spread dispersion guards. Lower is faster; preparation is excluded:

| Workload | Size | Dynamic ms | Complete plan ms | Lazy memo ms | PolkaVM interpreted ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sieve | 1,000 | 0.553 | 0.178 | 0.181 | 0.479 |
| Sieve | 10,000 | 3.926 | 1.419 | 1.502 | 2.025 |
| Sieve | 100,000 | 18.139 | 13.451 | 13.771 | 6.070 |
| Sieve | 10,000,000 | 1,536.920 | 1,457.384 | 1,560.243 | 374.735 |
| Minimal | 1,000 | 0.364 | 0.349 | 0.349 | 0.076 |
| Minimal | 100,000 | 36.419 | 34.074 | 34.208 | 6.101 |
| Memory fill | 1,000 | 0.237 | 0.163 | 0.173 | 0.135 |
| Memory fill | 100,000 | 14.533 | 13.340 | 14.586 | 3.977 |
| Pinky frame | 1 | 4,785.467 | 746.693 | 833.451 | 95.834 |

Pinky starts from the same initialized NES snapshot in both interpreters; its nine
setup frames and instance/memory restoration stay outside execution timing. The
full memory comparison includes framebuffer and NES state. Dynamic pricing is
particularly expensive here; complete pricing reduces its execution CPU by about
6.4x, while remaining about 7.8x slower than interpreted PolkaVM. This is a workload
observation, not evidence that pricing dominates every guest or that the best
policy is universal. The other input families retain their documented checked
entry boundaries.

Raw `results.json`, `samples.csv` and summaries are under `build/tests/pvm-sieve/`
and `build/tests/pvm-guests/`, including all per-family controls and source/binary
identities. Tables now retain CPU mean/sample SD, min–max and wall medians in
addition to median ratios and scoped pricing/first-execution costs. Format,
inventory, workflow YAML parsing and 76 affected Python benchmark/CI safeguard
tests passed. This local result does not claim an exact-head Linux CI pass.

## Fixed-width scalar copies

The next checked M1 Max investigation sampled the maintained indirect-call guest separately
from timing runs. Scalar reads/writes accounted for the largest sampled subtree; dynamic target
validation was smaller. The private chunk helpers now express complete two-, four- and eight-byte
copies with constant lengths. Clang can lower these unaligned-safe copies directly. Fragment
lengths retain the bounded variable copy, and chunk-crossing/big-endian accesses retain the byte
fallback. Complete permission preflight and clone-before-write ownership are unchanged.

A paired comparison against merged master `8ec989d6`, using the pinned checked ARC/Clang ThinLTO
profile, retained two reversed passes over all three maintained families at both sizes and all
three Ragnarök pricing modes: 936 full-state checked executions, including warmups. Large
indirect-call CPU medians were 35.852 to 32.887 ms dynamically, 34.833 to 32.390 ms planned, and
35.038 to 32.061 ms with lazy memo pricing (about 7–8.5% lower). Memory fill changed by -0.4%
to +1.3%; sieve by -1.3% to -2.6%. Those smaller differences remain unproven. Initialization and
first-cold samples remain separate in the raw process records; this is no universal speed claim.
The existing independent scalar boundary/writer/snapshot suites cover admitted widths, unaligned
accesses, all page-split fragment lengths, chunk crossings, faults and retained predecessor bytes.
Raw paired samples, exact source identities and diagnostic profile are retained under
`build/pvm11/scalar-copy/` and `build/pvm11/profile/`. Local observations are distinct from Linux CI.
