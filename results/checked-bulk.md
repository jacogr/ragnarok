# Bounded checked codec optimization: Nim, Odin and Mojo

2026-10-15. macOS 27.0.1 arm64, Apple M1 Max. Linux performance is not inferred from these results.

The original large-payload gap substantially reflected our implementation: per-byte checked copying,
rather than an unavoidable Nim ownership/ARC cost. Standard bulk copies brought Nim close to Odin
on those paths. Typed sequences remain a significant difference. A separate ordinary checked LTO
build narrows that gap further, but does not erase Odin's advantage.

## Fixed-configuration before/after

Times are median **microseconds per operation**, lower is better. These are warm-cache kernels,
not whole-client throughput or networking latency. Payload sizes exclude their framing bytes.

| Operation | Nim before → after | Odin before → after | Mojo before → after |
| --- | ---: | ---: | ---: |
| 1 MiB byte string encode | 651.95 → 16.25 | 14.55 → 15.54 | 1672.80 → 23.90 |
| 1 MiB digest encode | 1060.09 → 16.31 | 15.37 → 15.65 | 1672.01 → 22.32 |
| 1 MiB owned decode/release | 502.71 → 23.03 | 27.93 → 28.69 | 1680.02 → 31.58 |
| 1 MiB prepared owned encode | 671.31 → 16.84 | 16.38 → 16.19 | 1689.34 → 22.09 |
| 16,384 four-byte integers encode | 337.55 → 232.32 | 17.95 → 17.99 | 315.35 → 315.33 |
| 16,384 four-byte integers decode | 57.21 → 57.31 | 7.10 → 7.12 | 99.95 → 68.34 |
| 1 MiB Blake2b-256 | 1045.50 → 1041.85 | 1014.69 → 1014.99 | 1043.04 → 1047.06 |

Nim's large ordinary encodes improved about **40–65×**, and its 1 MiB owned decode about **22×**.
Mojo's large byte copies improved substantially too. Odin's implementation was unchanged; its
median after/before time ratio across the 69 cases was **1.0001**, a useful drift control rather
than a claim that every individual result was identical.
The unchanged large hash timings also locate the improvement in codec handling, not cryptography.

On the standard build, large sequence encoding is still about **13× slower in Nim than Odin**,
and decoding about **8×**. Those differences should remain decision inputs. Do not average them
away by counting cases or assuming a future client's request mix.

All 69 rows, including small cases and official work digests, are in the
[full comparison](checked-bulk/comparison.md) and [numeric summary](checked-bulk/comparison.json).
Full per-process/batch/latency observations are retained losslessly in
[before JSON](checked-bulk/before.json.gz) and [after JSON](checked-bulk/after.json.gz);
[packed-report hashes](checked-bulk/packed-reports.json) verify their decoded bytes.

## Changes retained

- Nim uses its documented [copyMem](https://nim-lang.org/docs/system.html) for already-validated
  nonoverlapping byte ranges. Empty copies never form an element address. No reference-containing
  objects are copied as raw memory.
- Mojo uses public [Span.copy_from](https://mojolang.static.modular.com/docs/std/collections/span/Span/)
  on checked subspans instead of writing individual bytes.
- Nim's two small fixed-integer routines carry normal inline hints. Mojo retains a public inline
  hint only on fixed decode. Forcing its fixed encoder inline increased large sequence encode
  from roughly 315 to 397 µs in the trial, so that hint was removed. Decode improved from roughly
  100 to 68 µs. The [rejected trial](checked-bulk/inline-trial.json.gz) is preserved.

All source-span, output-capacity, overflow, policy, discriminator and whole-buffer alias checks
remain before commit. Failure atomicity, failure-only result branches, immutable snapshots and
ARC/manual release behavior remain intact. No benchmark-only fast API, unchecked array access,
compiler patch, private SDK hook, CPU-specific code or dependency/toolchain change was introduced.

## What the profiles show

[Before](checked-bulk/before-nim-digest-1048576.sample.txt), Nim's main-thread bulk samples are
in `writeTag`; the [generated C](checked-bulk/before-generated-c.txt) has per-byte index and checked
arithmetic operations. [After](checked-bulk/after-nim-digest-1048576.sample.txt), its hot path reaches
the platform bulk-memory routine, as Odin's does. The source and timing change agree on the cause.

The [sequence profile](checked-bulk/after-nim-sequence-16384.sample.txt) still includes scalar
encoder calls despite the C inline hint, plus the enclosing checked loop. These sequences allocate
zero times in Nim/Odin instrumentation; this is not evidence of an ARC allocation penalty.
Mojo's idle SDK worker samples are not counted as main-thread codec work.

## Separate standard-build-policy probe: checked LTO

Nim's [FAQ](https://nim-lang.org/faq.html) recommends link-time optimization when the C compiler
supports it; [Clang documents -flto](https://clang.llvm.org/docs/CommandGuide/clang.html) as
cross-module link-time optimization. One supplemental build adds only `--passC:-flto --passL:-flto`.
It retains ARC, clang, -O3 and all assertion/bounds/range/field/overflow checks. The observation
function remains in its separate **non-LTO shared library**, preserving the opaque output boundary.
This variant is diagnostic; LTO is not enabled in the default benchmark or CI by this change.

The following are a **separate paired run**, not substitutions into the main table. Each entry
uses three fresh processes, 15 batches and 128 individual latency samples per process.

| Four-byte sequence | Nim standard µs | Nim LTO µs | Odin standard µs | Mojo standard µs |
| --- | ---: | ---: | ---: | ---: |
| 32 encode | 0.458 | 0.119 | 0.054 | 0.629 |
| 32 decode | 0.134 | 0.064 | 0.046 | 0.162 |
| 1024 encode | 13.183 | 3.340 | 1.172 | 19.682 |
| 1024 decode | 3.544 | 1.615 | 0.480 | 4.236 |
| 16384 encode | 230.921 | 54.181 | 18.009 | 314.629 |
| 16384 decode | 56.168 | 25.520 | 7.090 | 67.087 |

For 16,384 elements, LTO reduced Nim encode from about **231 to 54 µs** and decode from **56 to
26 µs**. Odin still took about **18 and 7 µs**, respectively. That identifies a substantial build
optimization-boundary cost, while leaving a measured residual of roughly **3–3.6×** on these cases.
It does not establish Nim's optimization ceiling or guarantee the same improvement on Linux.

Exact variant commands, hashes and observations are in the [LTO build](checked-bulk/lto-build.json),
[registered probe](checked-bulk/lto-probe-plan.json), [results](checked-bulk/lto-probe.json), and
[checked release test record](checked-bulk/lto-checks.json). The latter includes fixed integers,
bounded/composite containers, ownership fuzzing and result-field guards under LTO.

## Validation and reproducibility

- Common full conformance passed before and on the final sources: **185,373 shared requests per
  implementation/build**, pinned official vectors, native fuzz tests, ownership/alias/failure
  atomicity checks and deliberate negative compilation tests. Mojo runs at -O0 and -O3.
- Rebuilt integrated codec/crypto/QUIC passed all three servers: **36 retained waves, 864 streams**,
  plus 10,000 owned codec/hash selftest cases per candidate.
- Both full benchmark runs completed **69 cases × 3 languages**, three fresh timing processes
  per candidate/case, 45 batch means and 384 individual-operation samples, rotated candidate order.
  Allocation observations are separate. Nim/Odin call/free counts remain available; Mojo counts
  remain unavailable, not estimated from process heap.
- Benchmark harness: 11 regression tests passed. Project formatting: 126 source files passed.

Nim 2.2.12 ARC; Odin `dev-2026-10:84bc3fc21`; Mojo `1.1.0 (8189361e)`; Apple clang 21.0.0;
Python 3.14.2. Standard Nim uses checked -O3 release; Odin -o:speed; Mojo -O3. The common
benchmark/corpus/observer and Nim/Mojo linked crypto-library hash are unchanged; Odin's core
crypto implementation is unchanged too. Exactly eight codec source files
differ between the main before/after records. Source/binary/input hashes and full commands are
in the artifacts. Protocol pins remain GP v0.7.1 Appendix C and `spec/pins.json`.

The before source is commit `802f637d83b07a8ae80fefc6bc1c7065b9046853`; after is that revision plus
the accompanying codec diff. Reproduce in independent before/after checkouts on the same host,
using the existing pinned native dependency builds:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_codec.py --mojo
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_integration.py --mojo --reuse-native
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/benchmark.py --mojo --reuse-native
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_benchmark_harness.py
python3 tools/format.py --check
```

This Mac run has no enforced CPU affinity; working sets are resident and warmed. Native clocks
exclude startup/file parsing, including Mojo SDK startup. Linux's existing CI runs the common
checked comparison with CPU affinity; the changed sources still require that pushed validation.
No realistic full-client workload or concurrency throughput was measured.

## Assessment

I retain a **provisional Nim architecture preference**, with more confidence that the original
bulk gap was fixable implementation work. This does not turn it into a measured overall winner.
Odin remains the strongest measured sequence implementation here; Mojo's sequence encode remains
slower and its bulk paths are much improved. The remaining choice should give real weight to
Linux results and realistic client call rates/sizes, alongside Nim's ownership advantage and the
existing allocation-failure-recovery tradeoff. A threefold hot-path cost can matter.

No comparable AI-development-time/reliability ranking is inferred from this optimization task.
The [preregistered scope](checked-bulk/plan.json) records targeted Nim/Mojo work and an unchanged
Odin control. Compiler attempts are preserved, but handoff-to-registration time is missing and
effort/order are unequal; this is not a matched ergonomics cohort. Historical metrics stay N/A.
An initial sampling controller requested too many iterations; the benchmark correctly rejected
it. The [failed probe](checked-bulk/invalid-profile-extent.log) is retained as infrastructure
evidence; the bounded sampling probes then used the supported limit. It was not a decoder bug.

Compiler traces are in the [verified pack](checked-bulk/compiler-attempts.tar.gz), with a
[per-member hash/count index](checked-bulk/compiler-attempts.json). All recorded nonintentional
compiler attempts passed; negative-compilation probes are separate. This is not a claim of zero
historical defects or a fair AI-development-time comparison. To inspect the archived logs:

```sh
mkdir -p build/bulk-trace-review
tar -xzf results/checked-bulk/compiler-attempts.tar.gz -C build/bulk-trace-review
```
