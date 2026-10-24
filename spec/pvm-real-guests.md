# Maintained real-guest interpreter pack

`make bench-pvm-guests` compares two additional frozen checked upstream workloads against pinned
PolkaVM **Interpreter**, JamV1, Sync/Full/L2Hit. Ragnarök uses dynamic pricing, complete immutable
plans and lazy memos. This broadens the [real-sieve comparison](pvm-sieve-benchmark.md) with indirect
function calls and memory fill. It adds no production execution API, ordinary CI workload,
compiled backend, dependency upgrade or historical compiler installation.

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

Each family has two sizes, four engine/pricing modes and two reversed process orders. Every pass
contains three warmups and ten measured fresh-machine executions: 416 total raw CPU/wall samples
across the pack. Construction/reset and complete state comparison stay outside the execution clocks.
Pricing initialization and first-cold execution are shown separately from warmed medians; memo
learning in sample zero stays visible. The existing spread and pass-dispersion flags retain noisy
observations rather than filtering them. This does not provide CPU affinity/frequency isolation.

Outputs live under `build/tests/pvm-guests/`: aggregate JSON/CSV/Markdown and per-family complete
reports, controls and logs. Both children must pass with exact identities before an aggregate table
or downloadable CSV appears. A failure in either child fails the pack and retires stale aggregate
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
