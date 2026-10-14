# Optimized codec/hash comparison

Date: 2026-10-14. Full checked measurements completed locally on **Apple M1 Max**, macOS 27.0.1
arm64. Linux CI now runs the same workload with both candidates pinned to one allowed CPU;
**Linux measurements await the pushed run**. The Mac has no enforced CPU affinity.

Production codec/crypto code, compiler pins, dependency pins and wire semantics are unchanged.
See [the methodology and reproducible commands](../docs/benchmark.md). These measurements compare
current implementations and providers, alongside the earlier M3 resource/integration evidence.

## Local observations

All **69 case/operation pairs** passed native preflight, independent oracle/fingerprint/hash checks,
loop-checksum checks and allocator accounting. Each language/case has three fresh processes,
45 throughput batch averages and 384 separately recorded operation latency samples.

Selected batch medians below use **microseconds per operation**, including the common observation
and wrapper/check overhead. The complete 69-row table and raw samples remain in `build/bench`.

| Case | Operation | Nim µs/op | Odin µs/op |
| --- | --- | ---: | ---: |
| fixed-4 | decode | 0.006 | 0.005 |
| blob-1024 | decode | 0.012 | 0.020 |
| blob-1024 | encode | 0.658 | 0.035 |
| blob-1024 | owned-decode | 0.544 | 0.136 |
| sequence-1024 | encode | 21.687 | 1.184 |
| digest-work_result_0 | decode | 0.048 | 0.038 |
| digest-work_result_0 | owned-decode | 0.131 | 0.126 |
| digest-65536 | encode | 66.918 | 0.818 |
| digest-65536 | owned-decode | 31.760 | 2.372 |
| digest-1048576 | owned-encode | 666.531 | 16.169 |
| blake2b-65536 | hash | 65.329 | 63.573 |

The tiny-operation rows are close to common harness cost: baseline medians were 3.49 ns for Nim
and 2.50 ns for Odin. Do not treat a few nanoseconds here as an application-level outcome.
The 1 KiB borrowed blob decoder is faster in Nim in this run; small complete digest owned decoding
is close (131 ns versus 126 ns). These counterexamples matter alongside the bulk-copy results.

The substantial gap is current bulk handling. For example, a 64 KiB successful digest encodes in
66.9 µs in Nim versus 0.818 µs in Odin; a prepared 1 MiB snapshot encodes in 667 µs versus 16.2 µs.
The 64 KiB owned digest decode/release operation takes 31.8 µs versus 2.37 µs. Large scalar sequences
also favor the current Odin implementation. These paths combine implementation choices, checked
arithmetic, copying and compiler behavior; the data does not isolate an intrinsic language ceiling.

Blake2b on 64 KiB is much closer: 65.3 µs for the Nim/BoringSSL adapter and 63.6 µs for Odin core.
This includes different providers; native core availability has not produced a large throughput
difference in this case. Other required crypto/security decisions remain as previously documented.

Borrowed and prepared-encoding operations reported **zero allocation calls** in both languages.
Every owned decode reported **two allocations and two releases**, with zero live-byte delta.
Nim's counter does not provide requested-byte totals; Odin's requested-byte observations are in
JSON. Neither counter measures C-backend allocations. Owned metadata selection and final release
are timed; preparation/loading and prepared-owner construction are excluded.

Actual single-operation samples are separate from batch averages. For illustration, the 64 KiB
owned digest decode p99 was 39.7 µs for Nim and 4.38 µs for Odin; 64 KiB Blake2b p99 was 73.3 µs
and 71.3 µs. Timer overhead and resolution dominate many tiny operations. These warm-cache tails
are not service/load tail latency or statistical significance estimates.

## Separate profile of the bulk gap

After measurement, disposable processes encoded the same authored 1 MiB digest while macOS
`sample` observed each for one second. Profiled runs are excluded from timing results.

- Nim's 755 recorded hot-stack samples were in `writeTag`, reached through `encodeWorkBorrowed`
  and `encodeDigestBorrowed`. The current source copies payload bytes individually after span,
  capacity and alias checks (`nim/src/composite.nim`).
- Odin's 621 recorded hot-stack samples were in `_platform_memmove`, reached from its digest
  encoder. Its matching source uses the standard `copy` operation (`odin/codec/composite.odin`).

This identifies a concrete implementation target: evaluate bulk copying in the Nim codec while
preserving every existing bounds, aliasing, atomic-write and ownership check, then repeat the same
benchmarks. Allocation counts already agree; a generic claim that ARC allocation explains the
large copying gap would not follow from this evidence. No production optimization was made here.

Profile files remain in `build/bench/{nim,odin}-copy-profile.txt`. They are local Mac observations,
not a Linux profile or an automatic winner. The large ratio should be evaluated after the Linux
baseline and a bounded implementation review before it drives language selection.

## Verification and artifacts

Executed:

```sh
python3 interoperability/benchmark.py --reuse-native --quick
python3 interoperability/benchmark.py --reuse-native
python3 interoperability/test_benchmark_harness.py
python3 interoperability/test_codec.py
python3 tools/format.py --check
git diff --check
```

Both optimized binaries separately rejected a malformed empty natural with assertion diagnostics,
confirming their checked result guards remain active. Eight evidence-integrity regressions passed.
The full codec suite passed 185,373 shared requests per implementation across the five existing
suites, official vectors, owned/borrowed tests and negative compilation checks. Formatting passed
86 source files, and the whitespace diff check passed. Crypto production code was unchanged;
benchmark hashes were independently verified at all four measured message sizes. Networking and
Bandersnatch suites were not rerun for this measurement-only increment.

`build/bench/results.json` retains full samples, corpus hashes, source/binary hashes, compiler and
hardware metadata, exact build commands, allocation observations and process peak RSS. The linked
crypto library hash and expected backend pins are recorded. The generated Markdown table retains
all cases. Each full-run raw-log directory is recorded in JSON. The workflow uploads these
explicit diagnostics after correctness checks. Speed has no CI failure threshold; incorrect
results or unsettled allocation ownership fail the measurement.

## Maintainability evidence alongside speed

| Area | Nim | Odin |
| --- | --- | --- |
| Checked values | Variant fields, nominal scalars, automatic retained snapshot values | Nominal scalars, checked unions, explicit success selection |
| Snapshot lifetime | ARC releases immutable handles after their last retained use | One explicit release owner; copied aliases need a clear lifetime contract |
| Native crypto | Maintained narrow C ABI plus shared Rust Bandersnatch ABI | Compiler core primitives plus shared Rust Bandersnatch ABI |
| Async service | Standard selector/nonblocking UDP owner and explicit callbacks | Core nbio receive/timer owner with explicit cancellation drain |
| Debugging evidence | Generated C and sampled native symbols expose this copy hotspot | Native symbols expose standard bulk-copy path; allocator tracking is direct |

Both passed the composed service/lifetime tests. Nim reduces manual snapshot-release work; Odin
makes allocator and callback retirement visible, with more ownership responsibility on callers.
The pinned Odin Linux adapter's io_uring/kernel-policy requirement remains a deployment consideration.
The maintainer's preference for reading/debugging these implementations is still a decision input;
no benchmark assigns that preference or collapses the rubric to a throughput score.

The next useful evidence is the pushed same-host Linux comparison and, if authorized, a bounded
Nim bulk-copy improvement followed by identical correctness and timing checks. Existing independent
peer/IPv6/outgoing-engine, crypto-policy and backend-audit limits remain. No next increment or
language selection has been started automatically.
