# Complete reports, guarantee composition and language-selection evidence

Date: **2026-10-15**. Baseline: `a2d6800` (the committed bulk-copy/LTO investigation).
Pinned GP **v0.7.1** and official vectors remain at the revisions in [pins](../spec/pins.json).

**This workload supports keeping Nim as the provisional architectural preference.** Checked
LTO removes a broad performance objection for these bounded report paths, while ARC retains
the ownership advantage. This does not establish higher full-client throughput or lower defect
rates. Odin still wins several codec stages, and backend choice affects the combined ranking.

## Implemented and verified

All three candidates now encode/decode complete work reports with typed availability/context
fields, ordered prerequisites and segment-root dictionaries, authorization output/gas, and all
nested work digests. Borrowed parsing uses fixed metadata capacity. Immutable owners provide
copied metadata, owner-bound payload extraction and canonical re-emission. See the
[wire contract](../spec/work-report.md) and [API guide](../docs/work-report.md).

Structural limits are 1–16 digests, eight combined dependencies and 49,152 aggregate payload
bytes. State-dependent eligibility, validator assignments and gas/state transitions remain
outside this increment. Authored workloads are structurally valid shapes, not sampled live JAM
traffic; the case named `typical` is a chosen four-digest workload, not a measured traffic distribution.

- **18,197 shared report requests passed per candidate**, including both official profiles,
  independent construction/field decoding, truncation, canonicality/order/uniqueness failures,
  aggregate/count bounds, late encoder failure/alias atomicity, full input mutation after capture,
  retained metadata/payload checks and deterministic malformed-input fuzzing.
- **42 independent crypto composition checks passed per candidate**. OpenSSL-generated ordinary
  credentials verify over `$jam_guarantee || Blake2b-256(report)`; changed reports, keys, signatures
  and signing domains fail. The test provider first passes a pinned RFC 8032 known-answer case.
- The existing **185,373-request codec suite** passed in each journal recheck, including native
  tests and intentional rejection fixtures. All three new package-hash/segment-root type guards
  also reject their intended misuse. The evidence/oracle harness passed **13 integrity tests**.
- Official formatting passed for **144 native source files**. Linux CI now builds, checks and
  benchmarks the same increment with explicit `lld` support for Nim LTO; **this local record
  does not claim a Linux CI pass**.

The official tiny/full standalone reports currently have identical bytes and empty dependency
collections. Authored nonempty/dependency-boundary cases provide additional coverage; passing
them is not additional independent published-vector coverage.

## Measured performance

Host: **Apple M1 Max, macOS 27.0.1 arm64**. Nim **2.2.12**, ARC/Clang **LTO only**; assertions,
bounds, ranges, field and overflow checks enabled. Odin **dev-2026-10:84bc3fc21**, optimized with
vet/strict style and runtime checks. Mojo **1.1.0 (8189361e)**, `-O3`, public native SDK APIs.
Apple clang **21.0.0**. No toolchain/dependency source patches or version changes.

Median µs/operation, derived from native batch averages:

| Report | Stage | Nim LTO | Odin | Mojo |
| --- | --- | ---: | ---: | ---: |
| official | pipeline | 72.148 | 115.363 | 74.128 |
| typical | decode | 0.426 | 0.409 | 2.108 |
| typical | encode | 0.621 | 0.398 | 1.850 |
| typical | owned | 0.703 | 0.745 | 2.538 |
| typical | pipeline | 79.488 | 123.986 | 81.717 |
| maximum-metadata | pipeline | 75.793 | 119.493 | 81.260 |
| maximum-payload | encode | 2.214 | 1.694 | 6.200 |
| maximum-payload | owned | 3.788 | 4.306 | 7.739 |
| maximum-payload | pipeline | 130.641 | 171.733 | 133.107 |
| maximum-lookup | encode | 0.440 | 0.173 | 1.374 |

The four-digest report is 5,206 bytes. The 16-digest payload-boundary report is 51,338 bytes,
including its 49,152-byte common blob budget. `owned` includes capture, re-emission and final
owner retirement. `pipeline` additionally hashes the canonical report and verifies two distinct
ordinary-key credentials. The guarantee timeslot is not part of this signing message.

Nim still has codec differences worth retaining: the eight-entry lookup encode is **2.54×**
Odin here, although the absolute difference is about **0.27 µs/report**. The largest observed
Nim-minus-Odin borrowed-encode difference in this corpus is about **0.52 µs/report**. Do not
describe all codec stages as equal. The earlier 16,384-element sequence benchmark also remains
a separate result; these at-most-16-digest reports do not erase it.

Hashing and signature verification dominate the composed operation. Nim and Mojo use the
pinned BoringSSL bridge; Odin uses its pinned core Ed25519 implementation. The two-credential
stage is roughly 72 µs for Nim/Mojo and 115–117 µs for Odin. Consequently the pipeline ranking
includes **provider performance**, not a language/compiler-only advantage. Mojo has greater
codec overhead here but remains close to Nim in the combined crypto-heavy workload.

Nim/Odin application allocator counters record zero calls for borrowed/prepared stages and
**two balanced allocations per owner/pipeline operation**. Their scopes exclude native-provider
allocations outside those allocators. Mojo reports public process-malloc live deltas and RSS;
its allocation-call counts remain **N/A**. None of these scopes should be silently equated.

The [complete 42-row table](work-report/comparison.md) also reports individual p95 latency.
Each report/stage/candidate uses **three fresh measurement processes**, seven native batches
per process and 128 individual-operation latency observations per process. A seeded order is
rotated so every candidate occupies every position. Calibration chooses the same operation
count for all candidates in a case. macOS CPU affinity is unavailable; Linux uses one allowed CPU.
File loading, startup, credential imports and full-byte preflight occur outside timing.
A separately compiled **non-LTO observer** keeps complete outputs live. Full wire/message
equality, expected verdicts and operation checksums are checked before accepting observations.

## Ergonomics and remaining decision gates

The [prospective comparison](work-report/ergonomics.md) records compiler repairs **0 / 5 / 4**,
implementation LOC **338 / 480 / 513**, no confirmed native post-compilation defects, no additional
post-registration human interventions, and zero confirmed regressions over one shared baseline
check per candidate. These are Nim/Odin/Mojo task observations, not historical estimates.
Comparable development times are **N/A** because shared work and initial architecture analysis
contaminate the interleaved raw clocks. A Mojo compiler crash was resolved with an ordinary
local-value refactor; its source and diagnostic evidence are preserved.

Automatic report ownership plus these bounded performance results strengthen the provisional
Nim choice. They do not prove it the most reliable language: all three pass the same correctness
checks, one task provides little defect-rate evidence, and later candidates saw earlier code.
The exceptional-key **Ed25519 acceptance-policy gate remains unresolved**, as do the previously
documented dependency/audit and full-client work. Nothing here normalizes backend verdicts or
implements validator authorization, full guarantees extrinsics, PVM/state transitions or a new
networking workload. Linux performance must be read from the new CI artifacts.

## Reproduce and inspect

After installing the pinned toolchains/submodules, build the primitive library if needed:
`python3 interoperability/test_crypto.py --mojo --fetch`. Then run:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/benchmark_report.py --build-only
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_work_report.py --skip-build
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_report_types.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_report_harness.py
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/benchmark_report.py --skip-build
```

All new Nim measurements use LTO; no paired non-LTO run was performed. Linux installs `lld`
and passes `--passL:-fuse-ld=lld`. Crypto bridge reuse is explicit; new standalone tests still
check the normative message against independent Python hashing/OpenSSL signatures.

Evidence: [full compressed benchmark JSON](work-report/comparison.json.gz),
[verified raw observations](work-report/observations.tar.gz) and
[per-member hash index](work-report/observations-index.json),
[environment inventory](work-report/environment.json),
[Nim](work-report/nim-correctness.json) / [Odin](work-report/odin-correctness.json) /
[Mojo](work-report/mojo-correctness.json) correctness receipts, and the
[ergonomics contract/journals](work-report/ergonomics.md) and
[compiler/baseline log archive](work-report/compiler-attempts.tar.gz). The main JSON retains build commands,
source/binary hashes, observer receipts, public credentials, calibration and raw process paths.
The archive contains the 630 final-run native processes (calibration, timing and allocation),
not the earlier smoke run. The crypto-library inventory is explicitly a post-measurement snapshot.
No native binaries, dependency trees or private networking credentials are committed.
