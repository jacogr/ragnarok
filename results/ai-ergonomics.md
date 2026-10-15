# AI-assisted development ergonomics: Nim, Odin and Mojo

Audit date: **2026-10-15**. Native source baseline:
[`cd0dbd0`](https://github.com/jacogr/ragnarok/commit/cd0dbd0b01c48bf995535d63a9ea61259b39f9f4).
Scope: equivalent bounded M1 codec, M2 crypto and M3 networking POC; no implementation behavior
was changed for this evaluation. The [local parity record](mojo-parity.md) establishes the feature
and shared-test baseline. It does not establish equal development effort or a Linux Mojo pass.

**Provisional recommendation: Nim for this project's present AI-assisted implementation.** Its
private ARC-owned snapshots, automatic last-owner seed wiping and retained Rust-owner destructors
remove release/alias obligations that the current Odin and Mojo APIs leave to their callers.
This is an ownership-based engineering judgment, **not an empirically demonstrated reliability
ranking**. We lack comparable histories for five of the six requested metrics. There is no honest
measured winner yet, and the maintainer's overall language decision remains open.

The subsequent [checked performance experiment](checked-bulk.md) changes Nim/Mojo codec copies
and scalar inlining. It supplies new performance evidence, not a matched AI-development cohort.
The LOC and historical metric table below refer to the archived POC snapshot above.

The subsequent [complete-report increment](work-report/ergonomics.md) supplies prospective compiler,
LOC and regression observations for equivalent new functionality. Shared work prevents comparable
development-time estimates; it does not change the historical N/A entries below.

## Reproducible metric comparison

| Metric | Nim | Odin | Mojo | Evidence/status |
| --- | ---: | ---: | ---: | --- |
| Compiler repair iterations | N/A | N/A | N/A | No complete equivalent-task attempt/fix traces. Intentional rejection probes are excluded. |
| Time to passing tests | N/A | N/A | N/A | No registered start clocks. Commit timestamps and suite/benchmark runtimes are not development latency. |
| Bugs found after compilation | N/A | N/A | N/A | Documented examples exist; no complete, consistently classified per-task defect ledger. |
| Implementation LOC | **2,148** | **3,000** | **3,530** | Measured current snapshot; Mojo includes 3,384 native + 146 language-specific C support. |
| Human interventions | N/A | N/A | N/A | Steering/review/CI examples exist; no comparable decision-unit/context log. |
| Regression rate | N/A | N/A | N/A | Missing matched passing-before/broken-after check histories and retested-check denominators. |

N/A means unavailable, not zero. No historical values are estimated. The
[machine-readable comparison](ergonomics/comparison.json) preserves those null values. The measured
[LOC artifact](ergonomics/loc.json), [reviewed file/exclusion manifest](../tools/ergonomics/loc-scope.json)
and [measurement tool](../tools/ergonomics/measure.py) permit reproduction and source-hash checks.

| Implementation group | Nim | Odin | Mojo native | Mojo-specific C |
| --- | ---: | ---: | ---: | ---: |
| M1 codecs and immutable snapshots | 705 | 1,072 | 944 | 0 |
| M2 primitive and Bandersnatch adapters | 269 | 379 | 385 | 0 |
| M3 adapters, integration, retained peers and proof offload | 1,174 | 1,549 | 2,055 | 146 |
| Total | 2,148 | 3,000 | 3,384 | 146 |

Counts are physical nonblank/noncomment lines, including imports, declarations and closing braces.
Project tests, compile-failure fixtures, concurrency test drivers, benchmarks, generated output and
shared C/Rust/dependency infrastructure are excluded. Explicit source-hashed ranges exclude embedded
parser/I/O/ownership selftests and their CLI dispatch. The actual POC profiles, fixture-serving
policy, cancellation controls and operational resource observations remain implementation scope;
this is not a production-validator LOC claim. Mojo's startup measurement helper is included even
though it lives in `selftests.mojo`, because the retained implementation calls it. The seven LOC
of `signed`/`capacity` helpers consumed by native QUIC are likewise included from `tests/support.mojo`;
the other test utilities and pure test imports are excluded.

Brace layout, 100-column formatting, generic specializations and module organization affect these
physical counts. Odin uses core crypto; Nim/Mojo use the maintained primitive C ABI. Library bodies
are not counted for any candidate. Mojo's non-shared OS/ABI shim is included rather than hidden as
shared infrastructure. These are review-surface observations, not a concision or correctness score.

## Environment and comparability

Fresh diagnostic probes and the LOC audit used macOS 27.0.1 arm64. The parity evidence records
Apple M1 Max. [Recorded tool outputs and configuration hashes](ergonomics/loc.json) include:

| Tool/configuration | Recorded value |
| --- | --- |
| Nim | 2.2.12; ARC; diagnostic probes use `nim check --mm:arc --skipParentCfg --skipUserCfg` |
| Odin | `dev-2026-10:84bc3fc21`; diagnostic probes use `odin check ... -file` |
| Mojo | `1.1.0 (8189361e)`; diagnostic probes use public `build --emit llvm` with native module path |
| Apple clang | 21.0.0 (`clang-2100.3.34.2`) |
| Rust | 1.99.0 (`b940084d7`) |
| Audit harness | Python 3.14.2, standard library only |
| Formatting | nimpretty, odinfmt and `mojo format`; project settings hashed in the artifact |
| Protocol and vectors | Gray Paper v0.7.1 and the repository's pinned official vectors |

[The parity record](mojo-parity-macos.json) retains earlier checked build flags and environments;
[Linux CI](../.github/workflows/linux.yml) uses Ubuntu 24.04 x86-64 and Python 3.12. Current Linux
results are not inferred from local runs or the presence of a workflow. The historical AI model,
reasoning configuration and exact context exposure are N/A. No model-controlled trial exists yet.

The functional baseline includes 185,373 codec requests per candidate build, independent crypto
fixtures and all nine directed networking pairings. That final coverage is comparable; the path
to it was not. Mojo was implemented later with completed examples, corrected contracts, mature
fixtures and the native dependencies already available. Nim/Odin bore earlier design/test costs.
The maintainer also authorized different increment boundaries. None of those differences can be
normalized away by dividing commits, elapsed calendar days or chat messages.

## Compiler protections and diagnostic quality

Nine fresh **intentional** probes cover three misuse categories in each candidate. The
[diagnostic manifest](ergonomics/diagnostics.json) records exact commands, source/log hashes,
compiler outputs and environment. These probes prevent particular invalid programs from compiling;
they are not nine observed development defects, repairs, or independent reliability trials.

| Misuse | Nim evidence | Odin evidence | Mojo evidence |
| --- | --- | --- | --- |
| Payload hash supplied as code hash | [Named type mismatch](ergonomics/diagnostics/nim-domain.log) | [Named assignment rejection](ergonomics/diagnostics/odin-domain.log) | [Conversion rejected with alias note](ergonomics/diagnostics/mojo-domain.log) |
| Natural supplied to fixed-integer encoder | [Wrong nominal argument](ergonomics/diagnostics/nim-integer.log) | [Wrong nominal argument](ergonomics/diagnostics/odin-integer.log) | [Distinct generic quantity rejected](ergonomics/diagnostics/mojo-integer.log) |
| Direct mutable snapshot storage access | [Private field unavailable](ergonomics/diagnostics/nim-storage.log) | [Private type unavailable](ergonomics/diagnostics/odin-storage.log) | [Opaque pointee has no wire field](ergonomics/diagnostics/mojo-storage.log) |

Nim/Odin name the conflicting domains directly. Mojo also supplies useful alias information, but
some generic diagnostics expose `Quantity[Int(...)]` identifiers that require consulting the alias.
Nim's private-field error can cascade into additional `.`/type errors; the first relevant error
still identifies the boundary. None of these presentation differences has a measured repair-time
impact in this dataset.

The Odin hash diagnostic suggests directly casting to `Code_Hash`. That would silence this error
without establishing that a payload hash has become a code hash. AI assistance must preserve the
semantic invariant instead of optimizing for a green compiler. A higher rejection/repair count
can therefore reflect useful enforcement rather than worse development reliability.

A separately labelled, **unpaired FFI probe** reproduces Mojo's rejection of a `RegisterPassable`
record containing fixed arrays: [archived source](ergonomics/observations/mojo-abi-layout.mojo.txt),
[current diagnostic](ergonomics/observations/mojo-abi-layout-current.log). The maintained adapter
uses compiler-derived C layout observations and bounds/alignment checks instead. This is evidence
of SDK/ABI integration friction and a useful rejected representation, not a compiler crash or a
JAM decoder bug. The SDK's Crashpad warning is also not a source rejection.

All candidates still require runtime checking for unselected result alternatives and semantic
validation of network inputs. Compiler errors alone cannot prove protocol correctness. Mojo's
opaque-pointee rejection is **not** module privacy: underscore fields and explicit unsafe casts
must not be described as equivalent to Nim/Odin private declarations.

## What the historical evidence can establish

| Observation | Attribution and significance | Evidence |
| --- | --- | --- |
| Shared result APIs exposed success-like fields after failure; detached spans lacked original-buffer identity | Review-found API/ownership risks in earlier Nim/Odin designs, not an observed decoder failure. Mojo inherited the corrected target, so it cannot receive a zero-defect advantage. | [Result safety](result-safety.md), [owned snapshot round](codec-ownership.md) |
| Authenticated connection closed before any stream could report failure; single-attempt clients waited for their long deadline | Confirmed post-compilation state-machine defect corrected in **both** Nim and Odin. Not a type/compiler defect. Mojo inherited the fix. A newly added regression test does not provide a historical regression-rate denominator. | [Reproduction and correction](quic-resilience.md#post-authentication-close-regression-2026-10-14), [native fixes](https://github.com/jacogr/ragnarok/commit/9cac74cc01827ec1d514e96485539d232df4069a) |
| Benchmark logging failed when its nested directory did not exist on fresh CI | Shared Python infrastructure defect; do not charge either native language. | [Exact fix and regression test](https://github.com/jacogr/ragnarok/commit/96c2c7f) |
| Earlier Nim QUIC wrappers needed local source transformations | Historical library/binding/packaging burden. The active maintained adapters removed it; it is not a current Nim compiler failure or an ongoing patch requirement. | [Adapter replacement](quic-adapters.md) |
| One transient unchanged Odin compiler crash during the parity work | Documented compiler incident; no complete invocation census or comparable other-language incident counts. Do not derive a compiler failure rate. | [Parity record](mojo-parity.md#resource-and-maintenance-differences) |
| Mojo startup heap/thread observations initially differed from the two original counters | SDK/runtime and measurement-infrastructure work. Raw fixed threads and process-malloc scope are now explicit; this is not evidence of a protocol defect or invented zero allocations. | [Mojo measurement contract](../docs/mojo.md#measurement-differences) |

Known examples are not a complete bug census. Likewise, maintainer decisions about checked results,
ownership, unpatched QUIC adapters, callback qualification and formatter conventions demonstrate
human steering, but their message/approval counts cannot fairly measure per-language intervention.
Routine mandated go-aheads are workflow policy, not evidence of language failure.

## Reliability judgment

| Current implementation property | Nim | Odin | Mojo |
| --- | --- | --- | --- |
| Domain and result protection | Distinct types, checked case objects | Distinct types, checked unions | Nominal specializations, checked variants |
| Retained codec lifetime | Private acyclic ARC storage | Explicit release owner and alias contract | Explicit release owner and alias contract |
| Secret/Rust owner cleanup | ARC last-owner wiping/destruction; close invalidates shared retained state | Explicit allocator/native-owner retirement | Explicit foreign-owner retirement |
| Allocation audit/control | Automatic ownership reduces release bookkeeping; allocation exhaustion remains a defect | Explicit failure paths, tracked allocation cleanup and refusal tests | Native value ownership plus manual foreign handles; process-malloc observations lack call counters |
| C callback/borrow obligations | Manual stable owners and synchronous foreign borrows remain | Manual owners plus explicit I/O cancellation drain | Public borrow/origin model; current C boundary still needs unsafe/untracked lifetime contracts |

The source evidence for Nim's advantage is concrete: [snapshot storage](../nim/src/owned.nim),
[seed destructor](../nim/crypto/primitives.nim), and [Rust-owner destructor](../nim/bandersnatch/bandersnatch.nim).
Compared with [Odin owners](../odin/codec/owned.odin) and [Mojo owners](../mojo/codec/owned.mojo), the
agent has fewer separate release/retained-alias obligations to get right. That reduces a specific
class of mistakes that can survive compilation. It does not prove that AI produces fewer bugs in
Nim, and ARC does not solve arbitrary C borrows, close races, cycles or state-machine errors.

Odin is a strong alternative when explicit allocator failure behavior and auditable resource
retirement are the main priority. Its nominal checks and core crypto are effective safeguards.
Their additional manual lifetime obligations deserve deliberate tests/review rather than a penalty
based on LOC or a single compiler incident.

Mojo has demonstrated feature feasibility and useful static ownership/type feedback. The current
implementation, however, combines manual foreign-owner contracts with additional OS/ABI support
and SDK/resource-measurement obligations. Its native ownership capabilities do not automatically
protect this chosen opaque-FFI design. This conclusion concerns the present adapter, not a claim
that Mojo intrinsically cannot express safer ownership or that more compiler repairs would be bad.

For a **measured** claim about the most reliable AI-assisted development, compare matched future
increments with complete traces and independent failure review. Fewer post-compilation defects,
confirmed regressions and semantic human corrections should weigh more than LOC or compiler
convenience. Useful static rejection may increase repair counts while improving those outcomes.
No weighted score or universal language ranking is justified by the current evidence.

## Tracking and verification

[The prospective protocol](../docs/ai-ergonomics.md) defines all six metrics, cause categories,
clock boundaries, coverage checks and task-order controls. `AGENTS.md` now requires it for future
authorized evaluation increments. The journal leaves unrecorded totals N/A, captures direct attempts
and exact logs, and validates current-source acceptance and LOC evidence. There are **no completed
matched prospective native tasks yet**.

Executed for this audit:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/ergonomics/test_tools.py
python3 tools/ergonomics/measure.py snapshot --output results/ergonomics/loc.json
python3 tools/ergonomics/measure.py diagnostics --output results/ergonomics/diagnostics.json
```

The [twelve synthetic metric-integrity tests](ergonomics/integrity-tests.log) passed; all nine matched negative probes and the
separate contextual ABI rejection reproduced. Those synthetic tests validate the measurement tools
and are excluded from candidate metrics. Native implementation behavior, tests, compiler/dependency
pins and test thresholds were unchanged. Linux CI additionally runs the metric-integrity tests;
a local pass is not a claim that the updated workflow has already passed remotely.
