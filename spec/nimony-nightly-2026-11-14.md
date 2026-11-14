# November 14 Nimony qualification

Upgrade the November 9 pin to official nightly
`8102b8e3c46bde87b733ecd82e2249cb562e3a8f`, published November 14, 2026 at
14:54:07 UTC. Publication time and embedded `NIGHTLY.txt` identify the selected archive;
release-list order is not the selection rule. The pristine browser source matches this compiler
and its `src/nativenif.commit`, `d8a9c96e1062939dddd1b1a43159eb55917ca7bc`.
The formatter remains Nimpretty from Nim 2.4.1. Protocol/provider pins are unchanged.

All three official archives were downloaded, checked against their published SHA-256 digests,
and inspected for matching compiler metadata. Native execution below is macOS ARM64 only.

| Archive | SHA-256 |
| --- | --- |
| linux_amd64 | `f47e7ab928c5a0f624ab9e538856951cc636c10e0b49a30d4b183f2b6f333b3a` |
| linux_arm64 | `1db739c9f12e198ac5ef503ceaab8c9c02c49e00f008e7fdb32ebfd528654eba` |
| macos_arm64 | `aa1310cf8f272ae1884034dab126b68cb0a80f3d1e85f753d21c8c6dace6bb49` |

Matching browser source hashes are recorded in [web-toolchain.json](web-toolchain.json).
Make builds jorogumo from those unmodified sources using the official compiler.

## Fixes and adaptation

The archive includes the [contract repair](https://github.com/nim-lang/nimony/pull/2989)
and [two-file regression test](https://github.com/nim-lang/nimony/pull/3002).
The unchanged NIM-010 imported-accessor reproducer and single-file control pass semantic
checking. Storage history compiles without changing its accessors or weakening their contracts.
NIM-006's omitted variant-default argument, explicit-default control and factory control all
compile and execute successfully. The issue register and portable reports retain historical failures.
Useful explicit-context APIs and owning empty-view factories remain supported choices.

The stricter side-effect checker rejects returning a mutable pointee location from a `func`.
`RWView` now reads a byte value through `[]`, retains its checked setter, and exposes an explicitly
borrowed location through the existing `borrowedData` API's indexed overload. That overload uses
the existing checked slice boundary; native descriptors and host copies keep synchronous pointer
lifetimes. Managed and mapped-owner tests verify that pointer writes alias the real last byte,
including the partial final resident page. No container copy or check suppression is introduced.

Inner-machine creation now explicitly rejects a nil retained code owner before constructing a
non-null instance. Missing-handle and invalid-entry protocol outcomes retain their ordering.
The module lifecycle suite exercises the valid retained-code path and refusal behavior.

Keep concrete integer-formatting overloads (NIM-002 is expected behavior), the NIM-005 test-only
counter observer, ownership exclusions and runtime checks. NIM-007's cross-target CLI observation
was not retested; native Linux qualification remains CI work.

## Local verification

- `make check-smoke`: all 631 production modules and the peer entry point pass; pinned formatting
  and the real UI JavaScript build pass as prerequisites.
- `python3 tools/build_ui.py --rpc-test`: the matching backend compiles the browser RPC fixture.
  This is compilation evidence, not a real-browser execution claim.
- `make unit SUITE=...`: `pvm_resident_bytes`, `nimony_noninline_var_write`,
  `nimony_pointer_refinement`, `nimony_sequence_ownership`, `pvm_inner_lifecycle`,
  `history_transition`, `jamnp_work_recovery`, `pvm_read_cycle_execution_arm`,
  and `pvm_fresh_resident` pass through the pinned native runner.
- Fresh 1,000-cycle ARC receipts retain identical before/after occupancy for resident bytes,
  inner lifecycle, recovery and resident frames. The ARM read-cycle suite exercises the native ABI.
- Actual lowering rejects all four retained scalar/sequence/stream-array ownership-copy guards
  with their exact expected unavailable-hook diagnostics.
- `make check-fixture-provenance`: all 350 unique fixture files and links pass.

Full local logs, commands and raw samples are under ignored
`build/upstream-watch/nimony/2026-11-14/`. Full Linux, E2E and browser runtime CI are not local claims.

## Bounded PVM comparison

Compile the same current-source `tests/performance/pvm_workload.nim` with the pristine November 9
baseline and November 14 candidate using checked ARC/Clang, release/speed and ThinLTO.
The authored fixture is checked against its independent Python generator. Both binaries fail the
intentional assertion control. Each successful legacy planned-price process validates all registers,
source immutability and memory bytes, then emits all eleven cases with three warmups and ten samples.
Use the existing strict output parser and alternating process order; no build overlaps timing.

The first eight-process batch has variable sparse-memory results. An independent twelve-process
confirmation batch reverses the starting order. Median-of-process-medians in that batch:

| Case | November 9 ns | November 14 ns | Change |
| --- | ---: | ---: | ---: |
| Arithmetic 10,000 | 91,864 | 91,990 | +0.14% |
| Aligned memory | 12,114 | 12,052 | -0.51% |
| Crossing memory | 12,479 | 12,469 | -0.08% |
| Aligned host calls | 345,896 | 349,125 | +0.93% |
| Crossing host calls | 473,520 | 474,896 | +0.29% |
| Arithmetic 1 | 667 | 666 | -0.07% |
| Arithmetic 16 | 823 | 802 | -2.49% |
| Mixed bit operations | 16,282 | 16,354 | +0.45% |
| Sparse aligned | 13,375 | 13,302 | -0.54% |
| Sparse crossing | 13,792 | 13,781 | -0.08% |
| Alternating blocks | 12,708 | 12,927 | +1.72% |

There is no demonstrated overall production speedup. These are short local synthetic timings,
not a full benchmark gate. Correctly configured full-invocation interpreted runs fail on **both**
compilers when the arithmetic-one reused sample measures zero process-CPU nanoseconds on this
host. Preserve that failure and the positivity guard; legacy wall-only results do not substitute
for a passing full-invocation comparison.

The archive contains the [location-based block-memory intrinsics](https://github.com/nim-lang/nimony/pull/2980)
and matching native-backend implementation. A separate checked `nimony n` scalar-copy probe shows
an old generic copy sequence, a newer stack load/store, and register-only moves with `copyMemIns`.
For 25 million non-inlined calls, median child CPU over six observations per variant is 54.63 ms
(old), 64.87 ms (new existing spelling), and 54.83 ms (new location intrinsic). This isolated probe
supports the code-generation opportunity, not a production gain. Production still uses `nimony c`;
keep the existing unaligned-safe PVM memory copies rather than adding a slower unproven rewrite.
