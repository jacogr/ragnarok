# November 16 Nimony qualification

Qualify official nightly `1e3c6de070dd59d2c59188fc8b28fbf23a064470` on November 17, 2026,
replacing the November 14 pin. The release was published November 16 at 18:15:27 UTC;
its macOS job and archive completed later. Select by publication time and embedded metadata,
not API ordering. All three pinned archives were downloaded, checked against the official
SHA-256 digests, and inspected for matching `NIGHTLY.txt` commit/date/platform fields.

| Archive | SHA-256 |
| --- | --- |
| linux_amd64 | `44d2ed32e352e96336c6f9fb2bd1883022cd1e76e98480ccc33b8751737c44ac` |
| linux_arm64 | `d912da8a2804be39113a350e39698db30ba1d4a30eef525eb519c445a265664e` |
| macos_arm64 | `a10ab50497edb568d40a3b1749ff66549dea72b8a1dd09c4c1e974cf91d3fd84` |

Browser sources match this compiler and its `src/nativenif.commit`,
`95bdfb32f2b33c9ba8e4ffbabe513ac975664522`. Source hashes are recorded in
[web-toolchain.json](web-toolchain.json). Keep the compiler-selected backend rather than
advancing it independently. Nimpretty/Nim 2.4.1 remains the formatter/bootstrap provider.
Upstream sources, runtime checks, ownership guarantees and protocol/provider pins are preserved.

## Changes and retained observations

The archive includes [inductive loop invariants](https://github.com/nim-lang/nimony/commit/9ae359611b89db4ef8538515d131e3d27699a7a7),
[stricter postcondition checking](https://github.com/nim-lang/nimony/pull/3013),
[affine-index optimization](https://github.com/nim-lang/nimony/pull/3006),
[restored memory-loop recognition](https://github.com/nim-lang/nimony/pull/3019), and the
[optimizer fixpoint](https://github.com/nim-lang/nimony/pull/3022) with its
[mutation-tracking follow-up](https://github.com/nim-lang/nimony/pull/3024).
These changes do not require a production compatibility edit in the qualified tree.

NIM-010 is **not fixed** by the optimizer follow-ups: the exact hash-matched experimental
composition input still fails in `shoggoth` on undeclared `iir.1000`. A private copy with only the
recorded direct comparisons compiles and links the Pinky driver. Retain the supported comparisons;
this is not runtime qualification of the experimental composition path. See the
[original report and new retest](nimony-reports-2026-11-15/fusion-handler-composition.md).
NIM-005's test-only counter observers remain; their removal has not been justified.
Concrete integer-formatting overloads remain supported code, not a compiler workaround.

NIM-006's unchanged omitted-default, explicit-default and factory probes compile and execute.
NIM-011's unchanged imported-accessor reproducer and one-file control pass semantic checking.
Historical failure receipts and resolution dates remain in the [issue register](compiler-issues.md).

The current direct NIM-007 catalog check targeting Linux AMD64 stops on ordinary compile-time
string-evaluation errors under **both** the November 14 and November 16 compilers. It does not
reach the historical `nifcore` assertion. This is an inconclusive retest, not a new regression,
a demonstrated fix, or Linux runtime evidence. No unrelated CLI source change is included.

## Local verification

On macOS ARM64, checked ARC/Clang release/speed builds retain ThinLTO and bounds checks:

- `make check-smoke`: all 639 production modules plus the peer entry point pass semantic checking;
  pinned formatting and the real UI bundle build pass.
- `make build`: the optimized production peer links with its integration, proof-worker and ARM JIT profiles.
- `make unit SUITE=...`: `nimony_noninline_var_write`, `nimony_pointer_refinement`,
  `nimony_sequence_ownership`, `pvm_execution_cache`, `pvm_resident_bytes`,
  `pvm_read_cycle_execution_arm`, `pvm_shared_async_arm`, and `history_transition` pass.
- Actual lowering rejects the four retained scalar/sequence/callback-owner copy guards with
  their exact expected unavailable-hook diagnostics.
- Browser RPC JavaScript compilation and fixture provenance pass.

Full commands, outputs, archive identities, source snapshots and receipts remain under ignored
`build/upstream-watch/nimony/2026-11-17-upgrade/`. A sandbox-blocked Rustup setup attempt was
stopped; the ordinary setup and smoke check then passed with the required host-tool access.
Native Linux, networking E2E and real-browser execution remain separate CI qualification.


## Bounded C-backend comparison and review hold

Compile the same current `tests/performance/pvm_workload.nim` with the pristine November 14
and November 16 compilers using checked ARC/Clang release/speed, ThinLTO and fresh private caches.
The fixture matches its independent Python generator. Both binaries reject the intentional native
assertion control. All eleven cases validate their complete outputs through the existing strict
parser before contributing timings. No build overlaps measurement.

An initial six-process batch exposes slower host-call cases. A second batch uses twelve processes
per compiler, alternating pair order, each with three warmups and ten measured observations per
case. Median-of-process-medians below is wall-clock nanoseconds in the legacy planned-price
mode. Positive changes mean slower. These are short synthetic observations, not full-invocation
or native-backend measurements and not a claim of overall application speed.

| Case | November 14 ns | November 16 ns | Change |
| --- | ---: | ---: | ---: |
| arithmetic-10000 | 93,697.75 | 93,750.25 | +0.06% |
| memory-aligned-1000 | 15,125.00 | 15,291.50 | +1.10% |
| memory-crossing-1000 | 15,854.25 | 16,093.75 | +1.51% |
| hosts-aligned-1000 | 337,718.75 | 371,333.25 | +9.95% |
| hosts-crossing-1000 | 477,593.75 | 508,687.50 | +6.51% |
| arithmetic-1 | 780.75 | 875.00 | +12.07% |
| arithmetic-16 | 927.25 | 1,000.00 | +7.85% |
| bits-mixed-1000 | 15,478.75 | 15,666.75 | +1.21% |
| sparse-aligned-1000 | 16,916.25 | 17,072.75 | +0.93% |
| sparse-crossing-1000 | 17,812.50 | 17,791.50 | -0.12% |
| blocks-alternating-1000 | 13,208.25 | 13,104.25 | -0.79% |

A bounded diagnostic then changes only `SHOGGOTH_DISABLE=coldguards` for one isolated candidate
build, retaining assertions, bounds checks and the same source/flags. With twelve processes per
variant, aligned-host medians are 333,375 ns (old), 365,093.75 ns (candidate default), and
337,604.25 ns (diagnostic). Crossing-host medians are 476,301.75 ns, 500,552.25 ns, and 467,854 ns.
This implicates the new cold-guard layout in these C/ThinLTO losses; it is not a minimized upstream
bug report. Deterministic instruction-counter profiling was not available on this macOS host.
The diagnostic environment is not part of production setup or this PR.

Correctness qualification passes, but the draft remains for review: NIM-010 still fails and the
host-call comparison regresses with official defaults. There is no demonstrated performance win.
No upstream issue/comment, compiler patch, heavy CI request or automatic merge is made here.
