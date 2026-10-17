# Native test migration

Original migration branch: `nim-tests`, based on Nimony migration commit `8db659c`.
Migration now covers primitives, composite/block codecs and successive state families.
Current total: **76 ordinary native suites**, including three state-store, two authorization-transition and
two history-transition, two entropy/time, two validator-rotation and two telemetry profiles; all original 59 suites remain migrated.
The migration preserved wire behavior, bounds/ownership contracts and independent references.
Subsequent native suites cover the new storage foundation as recorded below.

## Current verification groups

| Make target | Scope | CI job |
| --- | --- | --- |
| `check-modules` | Every-source semantic compilation | Source compilation |
| `check-python` | One Python reference/tooling/provenance discovery | Python tests |
| `check-unit` | 76 native suites and 41 corpora | Native units/codecs |
| `check-failures` | 1,408 runtime behavior/contract probes plus store positive controls | Runtime failures/contracts |
| `check-guards` | 701 compiler rejection probes | Compiler rejection guards |
| `check-e2e` | Six peer-entry selftests and live networking/resource scenarios | End-to-end networking |

`make check` runs all six locally; CI schedules them independently and concurrently on separate
VMs. Each target provisions its own dependencies and writes its own report. There is no CI
`needs` chain or duplicated Python discovery. `make unit` remains a quick native-only subset;
`make runtime` aliases `check-unit`, and `make modules` aliases `check-modules`.

Reports live in `build/tests/modules/`, `build/tests/python/`, `build/tests/runtime/` (unit/corpus),
`build/tests/failures/` (runtime contracts), `build/tests/guards/` (compiler rejections) and
`build/tests/e2e/`. Combined native coverage remains
76 + 6 = 82 profiles. The new [state store](../spec/state-store.md) has three native profiles and
five privacy probes and nine isolated runtime misuse checks. E2E retains the
original rounds, warmups, failure schedules, timeouts and resource ceilings. Its self-contained
build uses the same shared checked native compiler profile as the unit verifier.

Historical increment records below describe the earlier cumulative runner, including its former
embedded Python gate and lifecycle reporting. Current reproduction uses the groups above.

The [authorization transition](../spec/authorization-transition.md) adds six published tiny/full
STF cases, atomic store integration, 1,000 scoped ARC cycles, four result misuse probes and
three compiler privacy/nominal rejections. These are additional execution tests, not duplicate
Python implementations of the transition.

The [recent-history transition](../spec/history-transition.md) adds eight published history cases,
11 independent output-tree checks, two native profiles, six runtime misuse probes and three
compiler rejections, including stage ordering, atomic rollback and scoped ARC evidence.

The [signing-domain audit](../spec/signing-domains.md) adds a native suite for 1,035 external
assurance/report credentials and independently sampled OpenSSL domain checks. Existing 2,087
assurance and 63 report-composition workloads remain; their frozen hashes change intentionally
with the corrected protocol bytes, including rejection of old-domain credentials.

The [entropy/time transition](../spec/entropy-transition.md) adds two native profiles, twelve
published Safrole projections, four result-access probes and three compiler rejections. Both
fixed chapters publish together; tests cover aggregate write budgets, rollback and ARC release.

The [validator rotation](../spec/validator-rotation.md) adds two native suites, sixteen published
roster/root projections and four compiler/four runtime result guards. Atomic C(4)/C(8)/C(9)
publication preserves schedules/accumulators and is verified against ring/store refusal, exact
chapter parsing, aggregate budgets and historical snapshot lifetimes.

The [ticket admission](../spec/ticket-admission.md) adds two native suites, 28 published
proof/accumulator projections, four compiler privacy checks and four runtime result guards. The
store profile tests actual entropy/time handoff, atomic C(4) publication, exact budget boundaries,
first/late hash and primitive refusal, both schedule alternatives and 1,000 no-op ARC cycles.

The [sealer-schedule core](../spec/sealer-schedule.md) adds one native suite with 33 published
posterior C(4) projections, bounded outside-in/fallback selection, first/late primitive refusals
and a scoped 1,000-cycle ARC workload. Two compiler privacy checks and two runtime extraction
probes protect immutable candidate results. Atomic publication and header marker checks follow.

## Runtime failure job split (2026-10-17)

`make check-failures` selects `tools/test_runtime.py --group failures`; the default remains
unit/corpus verification. Both groups reuse the same checked native build profile and retain
separate caches, logs, stale-report invalidation and summaries. Compiler rejection checks remain
in `check-guards`. No new Python launcher or production behavior is introduced.

Against a fresh combined run on master `573f000`, the separated runs preserve all 73 suite
identities/verdicts, all 45 runtime families (1,402 records) in their original order, and the store
positive controls. All 41 corpora pass; 40 stable corpus records match after excluding process
logging/timing. The QUIC corpus regenerates certificates during existing setup, so its DER-derived
request count and hashes vary between runs (25,655 versus 25,654 here). An AST comparison also
confirms that all 503 original workload statements occur exactly once across the extracted groups,
excluding the clarified runtime log labels.

Master advanced to `20e2b85` during publication. Its ticket-admission increment is included;
the split preserves all 509 workload statements from that revision, including the four new runtime
probes. Current totals are 75 suites, 41 corpora, 1,406 runtime records and 699 compiler guards.
All affected groups pass after that merge, including 286 Python tests with two existing skips.

Reproduce with `make check-unit check-failures check-guards check-python`. Local baseline, split
logs and inventory comparison are under `build/tests/failure-split-baseline/`; group reports remain
at the paths above. The Python safeguards check missing/duplicate/failed records, disjoint report
ownership, independent summaries, clean Make bootstrap and failure propagation through `tee`.
Linux scheduling and elapsed-time effects require the PR CI run; no speedup is claimed locally.

## What the investigation found

Most application assertions already live in Nim under `tests/native/`; Python currently compiles,
launches and records them. Independent Python oracles also compare independently authored bytes
against native drivers. Those are different responsibilities and both remain useful.

Nim 2 provides [`std/unittest` with `suite`/`test`](https://nim-lang.org/docs/unittest.html).
Our pinned Nimony 0.6.3 archive does not contain that module. A direct compile probe rejects
`import std/unittest`, `suite`, `test` and `check`; the diagnostic is retained under
`build/nim-tests/probes/unittest.log`. Importing Nim 2's library or implementing a lookalike DSL
would add a compatibility/framework project to this test migration, so neither is introduced.

The same official archive already ships **Hastur**, Nimony's native test runner. Its public
`test <file>/<directory>` command compiles and runs ordinary Nim assertion tests. See the pinned
[runner](https://github.com/nim-lang/nimony/blob/5b51edfedb4d0dbd9028d9e57ac61d69dffe9410/src/hastur/runner.nim)
and [CLI](https://github.com/nim-lang/nimony/blob/5b51edfedb4d0dbd9028d9e57ac61d69dffe9410/src/hastur/hastur.nim).
This increment uses that supported file-based runner; it does not provide the unavailable
`std/unittest` API. Both checksum-pinned macOS ARM64 and Linux x86-64 archives contain Hastur.

## Parallel execution validation

On 2026-10-17, the pinned Nimony 0.6.3 toolchain on macOS arm64 passed `make check` with four
workers in **587.96 seconds**, using an existing local build tree. The 669 pooled compiler
rejections took **88.23 seconds**. Coverage retained all 65 native profiles, 41 corpora and 676
compiler rejections. These local timings do not establish a Linux CI speedup.
The separate `make unit` path passed all 59 suites and 31 ARC observations; `make modules`
passed all 45 sources with four workers. Final Python discovery passed 278 tests with two
existing skips. Four-worker failure probes preserved both assertion and output-mismatch diagnostics.

Ignored `build/tests/parallel-review/` retains command logs, serial/parallel codec observations and
the coverage comparison. Deliberate assertion/output-mismatch probes retained a failing exit code
and individual diagnostics beside a passing sibling. `build/tests/runtime/results.json` records
per-command elapsed seconds and the pooled rejection phase time; shared group commands should be
counted once by their log identity when analyzing costs.

## First converted group

The three files were moved with `git mv` to `tests/unit/codec/`. Their bodies are preserved
byte-for-byte apart from the relative production import path. Each owns a checked-in `.output`
file containing its existing successful completion marker. No golden is recorded automatically.

| Suite | Preserved code coverage |
| --- | --- |
| Natural numbers | 65,536 small values, binary boundaries, truncations, all headers, 10,000 deterministic fuzz inputs |
| Fixed-width integers | Full E1/E2 domains, widths 0–8, invalid widths, overflow, truncations, 10,000 deterministic fuzz inputs |
| Bounded containers | Byte/sequence length transitions, atomic failures, aliasing, huge counts, zero-width sequences, 10,000 deterministic fuzz inputs |

Hastur owns compilation, execution and exact expected-output comparison. Tests run in separate
processes (`--joined:off`), preserving scope/destructor isolation and keeping generated joined
drivers out of the source tree. Artifacts remain under ignored `build/nim-tests/` with compiler-
location cache isolation. ARC, Clang, checked release speed optimization and LTO are forwarded
explicitly; Linux retains lld. The backend command files confirm Clang `-O3` and `-flto`.

```sh
make unit
```

That command runs **22 codec, 40 state, five crypto and five QUIC suites** through Hastur.
The codec directory is dependency-free; other cases have explicit per-file profiles, including
native-free UDP and disabled integration. The launcher prepares the same pristine pinned C/Rust
crypto bridges, observers, LSQUIC/TLS and generated certificates/CE inputs as the cumulative run.
Initialized pinned submodules, CMake, Clang and the pinned Rust toolchain are required. Private
keys and generated data remain under ignored `build/`. Python supplies setup, paths and checked
flags; Hastur owns application test verdicts. Direct Hastur use must retain those exact flags and
fixture environment paths.

Compatible codec directory runs, all-source semantic compilation and independent
contract/privacy/nominal compiler checks share
one setting: `COMPILE_CHECK_JOBS=1..4`, default **4** locally and in CI. Use
`make check COMPILE_CHECK_JOBS=1` for a serial control; the same setting applies to `make unit`.
Linked state/crypto suites, QUIC suites and later network/resource scenarios remain sequential.

Hastur uses private worker caches and `--joined:off` retains separate test processes. This pinned
runner deletes successful worker caches, so serial codec runs can be faster for warm local repeats.
Compiler-rejection probes keep persistent private caches/logs, unchanged diagnostic checks and
registry-ordered results. Cumulative command records include elapsed seconds to identify costs.

Hastur runs from a compiler-specific directory under `build/tests/native/`, containing its relative
`nimcache_static/hastur.times` history. The `working-unit` compiler cache namespace separates this
layout from older caches with paths relative to the repository root.

Both entry points group the 21 dependency-free codec suites into one directory invocation.
The remaining 38 suites retain their separate library/runtime profiles. Cumulative evidence keeps
all 59 suite identities and per-suite ARC observations; a failed group marks every member failed
and retains Hastur's individual diagnostics.

The cumulative `make check` path delegates **all 59 ordinary suites** to Hastur and
hashes every source and `.output` file. The old Python positive-suite build/run branch is removed;
there is no fallback to old file locations. A registry/discovery safeguard rejects missing or extra
suite identities. All **31 ARC report fields** retain fresh numeric observations and native
equality assertions. CI already uses this cumulative path; no duplicate job was added.

Independent oracle drivers, specialized result/ownership profiles, negative compilation and
runtime-crash checks, published-vector validation and multi-process network scenarios retain
Python orchestration where it provides independent evidence or the native runner lacks an equally
strict failure contract. These are intentional responsibilities, not unmigrated ordinary suites.

## Second converted group: composites, digests and immutable snapshots

Four further suites move with `git mv`: `composite`, `work_digest`, `ownership` and
`report_snapshots`. Their encode/decode, mutation, retained-lifetime, truncation, aliasing,
atomic-copy, default-owner and deterministic fuzz assertions remain in Nim. The shared
`ownership_checks.nim` helper moves to `tests/support/`; independent bounded/composite/digest
drivers and unit tests import that single helper. No assertion is replaced with a Python model.

Composite and digest tests retain their existing output. Snapshot tests retain their original
public `getOccupiedMem()` measurements, 1,000-cycle workloads and equality assertions. Their
stdout markers now say `cycles=1000 unchanged`, avoiding platform-specific heap sizes in output
goldens. A small test-only helper writes the raw before/after observations to JSON when the
supported launcher supplies `RAGNAROK_TEST_EVIDENCE`. Standalone Hastur still executes the same
native equality assertions without requiring report files.

The supported quick and cumulative paths remove old per-suite observations before execution.
Missing, malformed, incomplete or inconsistent new evidence fails reporting; evidence-write
failure fails the native test. The cumulative report keeps its original `arc_release` and
`report_arc_release` fields, including the five-schema count for owned frames. Numeric records
live beside compiler-isolated caches under `build/nim-tests/`, outside the source tree. Native
assertions and exact completion output authorize success; Python retains the measurements.

One compile/fix cycle was needed for the new test-only file writer: Nimony rejected its unhandled
fallible `writeFile` call. Explicit exception handling now fails the test if evidence cannot be
written. No production/compiler code or dependency pin changed.

## Third converted group: extrinsics and fixture provisioning

The preceding snapshot increment is committed as `e1d35fb`. Tickets, assurances, guarantees and
disputes now move with `git mv` into the same native directory. Tickets/assurances retain their
complete bodies apart from imports. Guarantees/disputes retain all native owner, late-failure,
default-result, alias and 1,000-cycle ARC assertions; their raw ARC numbers use the same evidence
helper as the snapshot group, preserving `guarantee_arc_release` and `dispute_arc_release` fields.

Hastur executes files without the old guarantee test's positional fixture argument. The test now
reads `RAGNAROK_GUARANTEE_FIXTURE`, supplied by the launcher as an absolute, checksum-verified
path. The [393-byte fixture and provenance](../tests/fixtures/README.md) preserve the exact
`guarantees_oracle.record(0)['report']` bytes formerly generated per cumulative run. The quick
unit command needs no oracle generation or dependency checkout to obtain them. A harness compares
the saved bytes with that same independent oracle; missing/changed input fails before native
execution. The native test also fails on missing/unreadable fixture input, with no fallback.
The committed binary and its launcher hash participate in cumulative source provenance.

For a direct Hastur run that includes guarantees, supply `RAGNAROK_GUARANTEE_FIXTURE` explicitly;
the supported unit/cumulative commands prepare and validate it automatically. Standalone tests
still execute their ARC equality checks whether or not numeric evidence capture is requested.
No production encoding, validation, crypto or networking source changes in this increment.

## Fourth converted group: packages, headers and blocks

The extrinsic increment is committed as `d96fee5`. Work-package, header, block and block-private
suites now move with `git mv`. They retain their parent/child ownership, stricter-policy,
late-failure, complete-destination alias and guarded-default assertions. The private block suite
keeps its white-box `include` and full assertion body apart from the relative source path; it does
not export any production field. Strict public privacy/compiler probes are unchanged.

Work-package/header/block ARC workloads retain their original 1,000 cycles and native equality
assertions. Numeric observations use the existing helper, preserving `package_arc_release`,
`header_arc_release` and `block_arc_release` report fields. Output expectations remain portable.
The quick/cumulative paths now retain seven ARC observations across the fifteen native suites.

The block suite's positional fixture directory becomes `RAGNAROK_BLOCK_FIXTURES`. Its six exact
old oracle-authored tiny-profile children are saved under `tests/fixtures/block-tiny/`, with
[provenance and per-file hashes](../tests/fixtures/README.md). The fixture manifest now handles
both file targets and directory targets through explicit required-file lists. Every required
child is verified before native execution, and all seven input files across both fixture groups
participate in cumulative provenance. The native block suite also requires a nonempty fixture
configuration before constructing child paths. No fixture is generated by the production codec.

## Fifth converted group: bitstrings and collections

The preceding package/header/block increment is committed as `2aa7238`. Boolean/bitstring and
collection public suites, plus both private-wire alias companions, now move with `git mv`.
The private test bodies remain byte-for-byte identical apart from the relative production
`include` path. Public suites preserve their boundary, padding/order, zero-width, retained-owner,
atomicity, copied-metadata, stricter-policy and scalar-write assertions.

The two original 1,000-cycle ARC workloads keep their native equality checks. Their existing
`bits_arc_release` and `collection_arc_release` fields use the same fresh numeric evidence path;
portable output markers authorize successful completion. No fixtures, foreign libraries,
framework features or production code are added. Independent bit/collection references and
strict nominal/privacy/runtime-negative probes retain their existing roles and coverage.

## Sixth converted group: C.2 records

The bitstring/collection increment is committed as `344e5f6`. Public C.2 record regressions and
their private-wire alias companion move with `git mv`. The public suite retains guarded result
access, fixed-field copies, retained owner/source independence, strict resource-policy checks,
atomic failures and complete destination aliases. The private body is unchanged apart from its
relative production include path; production storage remains private.

The original 1,000-cycle ARC workload and native equality assertion remain intact. The existing
numeric evidence helper preserves `c2_arc_release`, bringing the quick/cumulative paths to ten
ARC observations across twenty-one suites. Only the stdout observation becomes a portable
success marker. Independent C.2 oracle/driver and strict privacy/nominal/runtime-negative checks
retain their existing roles; no fixture, native dependency or production behavior changes.

## Seventh converted group: state key/layout and trie

The C.2 increment is committed as `ba3cbb4`. State layout, public trie and private trie tests
move with `git mv` into `tests/unit/state/`. Public bodies change only their relative import
paths. The private suite retains all preflight hash-call counts, early/late primitive refusal,
recovery, topology arithmetic, input preservation and 1,000-cycle ARC assertions; only the
numeric stdout line moves to the existing evidence helper with a portable success marker.
The `trie_arc_release` field is preserved, bringing ARC observations to eleven.

These are the first migrated native-linked suites. The public trie test links only the real
crypto bridge. Layout and private trie link only the existing test observer, preserving refusal
injection and call-count checks in isolated processes. Every linked case forwards the maintained
crypto header path and uses its own compiler-location-isolated cache. A missing profile/library
or output expectation fails before compilation. The supported unit launcher rebuilds the pinned
libraries; the cumulative launcher reuses its existing preparation, without duplicate builds or
a second application verdict path. Native preparation evidence lives in
`build/nim-tests/native/preparation.json`; unit launcher source now participates in cumulative
provenance. Independent layout/trie adapters still link only the production bridge.

The first local native build failed because the new launcher omitted the maintained C header
include path; forwarding the same path as the existing build helper fixed it. This was one
infrastructure compile/fix cycle, not a language rejection or implementation defect. Its log is
`build/nim-tests/seventh/first-link-attempt.log`. No compiler, dependency or production source
was changed.

## Eighth converted group: Safrole and authorization state

The state layout/trie increment is committed as `43ef98e`. Safrole's entropy/validator/time
contracts and authorization's public/private pool/queue contracts move with `git mv` into
`tests/unit/state/`. Every original assertion is preserved. The public authorization body changes
only its relative import path. Safrole and private authorization additionally send their original
1,000-cycle allocation observations through the existing evidence helper and emit portable
success markers. Cumulative `safrole_arc_release` and `authorization_arc_release` fields remain,
bringing native ARC observations to thirteen.

All three cases retain their original production crypto profile, without observer substitution.
Existing checked linking, per-case cache isolation and fresh-evidence safeguards apply directly;
no new launcher feature, fixture, native dependency or production behavior is introduced. Retained
and replaced roster/pool/queue owners, copied keys/hashes, invalid tags, selected alternatives,
index boundaries and preflight arithmetic remain native checks. Independent byte/hash oracles,
published derived state inputs and strict compiler/runtime-negative probes retain their roles.

## Ninth converted group: consensus and dispute state

The Safrole/authorization increment is committed as `ad8bd63`. Consensus and dispute public
suites, plus both private ownership companions, move with `git mv` into `tests/unit/state/`.
The public bodies change only their relative import paths. Private bodies additionally use the
existing ARC evidence helper and portable completion markers; every original assertion remains.
The existing `consensus_arc_release` and `state_disputes_arc_release` fields are preserved,
bringing native ARC observations to fifteen across thirty-one suites.

Consensus coverage retains both ticket/key schedules, parent replacement, independent roster
children surviving parent retirement, copied fields/source alternatives, index/variant failures
and checked extent arithmetic. Dispute coverage retains independent judgment/offender domains,
canonical set checks, duplicate late failures before allocation, copied fields and retained/replaced
owners. Both private workloads keep their original 1,000 isolated cycles. All four suites retain
their production crypto profile and existing checked linking/cache isolation. No new launcher
feature, fixture, native dependency or production behavior is introduced. Independent oracles,
published derived inputs and strict negative compiler/runtime probes retain their roles.

## Tenth converted group: history state

The consensus/dispute increment is committed as `316997e`. Public history state and its private
ownership companion move with `git mv` into `tests/unit/state/`. The public body changes only its
relative import path. The private body additionally sends the same 1,000-cycle allocation
observations through the existing evidence helper and emits a portable completion marker.
Every original assertion is preserved, including malformed final peak rejection before owner
allocation, dictionary associations, absent versus present-zero peaks, copied metadata, retained
and replaced parents, index errors and extent/count arithmetic.

Both cases retain their production crypto profile and existing checked linking/cache isolation.
The cumulative `history_arc_release` field remains, bringing native ARC observations to sixteen
across thirty-three suites. Independent byte/hash oracles, published derived state inputs and
strict privacy/nominal/runtime-negative probes retain their roles. No new launcher feature,
fixture, dependency or production behavior is introduced.

## Python responsibilities and migration order

| Test responsibility | Direction |
| --- | --- |
| Implementation unit, boundary, ownership and deterministic fuzz assertions | Move in coherent groups to native Nim files executed by Hastur |
| Independent codec/state/crypto oracles and pinned-vector interpretation | Retain independence; Python remains appropriate |
| Multi-process QUIC topology, disruption and resource observations | Retain process orchestration while assertions remain native where practical |
| Compiler failures and runtime contract/crash probes | Retain strict existing checks pending an equally strong native runner contract |
| Toolchain/archive/reporting safeguards | Test the tooling in its implementation language |

The last distinction is supported by an actual fault probe: in the pinned Hastur, a `.exitcode`
file does **not** require the program to fail. A program changed to exit successfully can pass
without comparing that file. See the pinned runner above and
`build/nim-tests/probes/exitcode-contract/result.json`. Do not migrate crash guards using
`.exitcode` alone: that would weaken the current nonzero-exit checks. Compiler-diagnostic goldens
also need a portability review before replacing the existing specific rejection checks.

The ordinary-suite migration is complete. Future application tests belong in the appropriate
`tests/unit/` family, with an explicit output contract and checked profile. Retained Python work
is independent references, native preparation, specialized profiles, strict negative probes,
toolchain safeguards and process/resource orchestration. Revisit those negative probes only when
Hastur provides a demonstrably equivalent contract; never use permissive `.exitcode` expectations.
Named `suite`/`test` syntax can be revisited if the pinned compiler supplies a supported API.

The obsolete Nim 2 `FieldDefect` probe and its Python entry point have been removed. Their
Nimony successors remain the strict primitive/bounded/composite default/error payload-access
processes in `tools/test_runtime.py`, plus positive zero-width, empty-count and work-error cases
in the native codec suites. No exception-catching shim or weaker Hastur exit-code expectation
replaces those checks.

### Retiring superseded Python runners

After all 59 ordinary suites migrated, 34 unreferenced standalone Python runners were removed.
The runner-removal increment reduced top-level Python test code from 131 files / 15,424 lines
to 97 files / 13,561 lines: 1,863 fewer lines, including retired shared build/rejection helpers. These are
physical source lines, including comments and blank lines; they are not implementation LOC metrics.
Their application assertions already run through Hastur; their independent corpus comparisons
and specific compiler/privacy rejection probes remain in the cumulative verifier. The old Nim 2
entry points were also removed from the primitive, bounded, composite and digest reference modules.
Every retained reference function has the same parsed body as before this cleanup. The retained
`test_codec.py` name is an import interface, not an executable test command.

Use `make unit` for native application tests and `make check` for the complete supported path.
Commands in older specification/trial evidence describe historical runs; removed standalone
scripts are not required to reproduce current coverage. Python remains for independent oracles,
pinned native preparation, process/resource orchestration and strict/tooling safeguards.

Local verification: `make check` passes on macOS ARM64 with the pinned compiler and checked LTO:
45 production modules, 59 Hastur suites / 65 total native profiles, all 41 corpora, strict negative
and lifecycle checks, 246 harness tests (one existing skip), 23 setup/CI checks and formatting.
All 40 deterministic corpus records match the pre-cleanup baseline. Fresh certificate DER lengths
vary in the remaining QUIC corpus; its observations still match its independent expectations.
Evidence: `build/nim-tests/cleanup/full-check.log` and `comparison.json`. Linux CI is not inferred.



## Clean bootstrap and canonical CI commands

Make owns setup, command ordering and diagnostic directories. Linux CI invokes the four
`make check-*` groups concurrently, then their corresponding `make summary-*` targets. There are
no separate compiler, submodule, Rust, package or directory setup commands. Normal reports live
under `build/tests/{modules,python,runtime,e2e}/` and `build/ci/`. The older trial paths below are
historical evidence. `tools/test.py` is removed; native fixture/profile logic remains in
`tools/native_tests.py`. See [the tooling audit](development.md#tooling-audit) for retained helpers.

On 2026-10-17, local macOS ARM64 verification ran `make clean`, confirmed that `build/` was absent,
and ran `make check` without restoring archives, tools or caches. Make reinstalled the pinned
compiler/formatter and prepared sources, pinned Rust/Cargo dependencies and native libraries.
The complete run passed: 45 production modules, 59 Hastur suites / 65 native profiles, 41 corpora,
1,372 runtime misuse probes, 676 compiler rejections, 247 harness tests (one existing skip),
23 setup/CI safeguards and formatting of 863 Nim files. All 40 deterministic corpus records match
the preceding run; the generated-certificate QUIC corpus matches its independent expectations.
Test inventories are unchanged, and every recorded source hash matches the checked working tree.
The standalone `make unit` also passes all 59 suites and 31 ARC observations. Plain `make` builds
`build/ragnarok`; its parser and I/O selftests pass.

The isolated Make safeguard checks clean bootstrap and deliberately failed runtime execution:
logging through `tee` must preserve failure on both macOS Make 3.81 and Linux Make. Both summary
targets were exercised against real reports. Full logs are `/tmp/ragnarok-cold-check.log` and
`/tmp/ragnarok-make-unit.log`; the generated comparison is
`build/ci/cold-verification.json`. This is local verification; the revised Linux workflow still
requires CI after push.

## Final helper and reproduction cleanup (historical)

The remaining historical Nim 2 builders and standalone crypto/network entry points are retired:
17 functions and 460 net Python lines were removed. Maintained native builders, independent
reference equations and process/resource helpers remain importable; every retained function body
matches its pre-cleanup parsed form. The default proof-peer build still passes.

At that increment, the runtime verifier ran one fresh `unittest discover -s tests -p 'test_*.py'` gate before
native preparation. It includes all oracle/tooling harnesses, setup/CI safeguards and specification
provenance. The report's `python_tests` entry records the executed command, status and log;
per-corpus `harness` records reference that same complete gate. Thirty-four duplicate command
sites in the verifier and the redundant Make-level invocations are removed. An earlier successful
report is retired before execution, and a failed Python gate writes a failed report and stops
before native work. A deliberate-failure regression checks this behavior.

Complete local `make check` passes after cleanup: 59 Hastur suites / 65 native profiles,
41 corpora, 1,372 runtime misuse checks, 676 compiler rejections, formatting and a single Python
discovery of 274 tests with two existing policy/provenance skips. All 40 deterministic corpus
records match the preceding full run; generated certificates are independently checked anew.
Native/negative inventories are unchanged, and recorded source hashes match the checked tree.
Evidence: `build/test-cleanup/full-check.log`, `comparison.json`, and the runtime report/logs.

The reproduction audit covers all 41 specification Markdown records. Current commands use Make;
all referenced test/tool files exist, and current evidence paths use `build/tests/runtime/`.
Historical compiler profiles and numerical observations are identified as records of the original
increments. Detailed compiler-trial history remains in its historical document. Linux verification
must refer to the exact pushed revision; local success never substitutes for its result.

## Verification of the first increment

Local macOS ARM64, pinned Nimony 0.6.3 (`5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`), ARC,
Apple Clang 21 and checked LTO:

- All three native suites pass through Hastur.
- Deliberate assertion failure, compile failure and output mismatch all make the positive runner
  fail; a matching-output control succeeds. Logs/commands are under `build/nim-tests/probes/`.
- All 228 Python harness tests pass, with the existing parked-policy skip; five are new native
  launcher safeguards covering missing tools/evidence, empty discovery and checked host profiles.
- All 23 setup/CI safeguards pass; the installer now requires the archive's Hastur binary too.
- Protocol provenance passes with its existing unresolved draft-text skip.
- All 863 Nim source files retain canonical formatting.

These are focused migration checks. They are not a new full codec/crypto/QUIC run or a Linux CI
result for this branch. No production source or protocol behavior changed.


## Verification of the second increment

Same pinned macOS ARM64 checked-LTO profile:

- All seven migrated native suites pass, including the three earlier suites.
- Both snapshot workloads record 192 live bytes before and after their 1,000 isolated cycles on
  this host; these values are observations, not required cross-platform constants.
- Fault-injected +1-byte observations fail the original Nim equality assertions in both snapshot
  suites. An invalid evidence destination also fails inside the native writer; no stale record
  survives those test invocations. Evidence is under `build/nim-tests/second/arc-faults.json`.
- Six freshly rebuilt independent corpora (natural, fixed, bounded, composite, digest and report)
  match all **203,803 requests**; commands/verdicts are in `build/nim-tests/second/corpora.json`.
- All **231 Python harness tests** pass, with the existing parked-policy skip; eight are native
  launcher/evidence safeguards. All **23 setup/CI safeguards** pass. Protocol provenance retains
  its existing unresolved draft-text skip. All **864 Nim files** pass formatting.
- Launcher safeguards cover stale/missing records, JSON types, incomplete workloads and changed
  occupancy. Logs are retained under `build/nim-tests/second/`; individual cumulative invocations
  and their retained ARC fields also pass for all seven suites.

This remains focused native migration verification, not a full QUIC/crypto lifecycle run or a
Linux CI result for the new changes. Seven of 59 ordinary cumulative file suites now use Hastur;
52 remain, alongside specialized profiles and the deliberately retained strict negative probes.


## Verification of the third increment

Same pinned macOS ARM64 checked-LTO profile:

- All **eleven native suites** pass. Guarantee and dispute workloads preserve 1,000 isolated ARC
  cycles, with equal before/after observations of 22,736 and 140,880 bytes respectively on this
  host. These are observations, not cross-platform constants.
- Injecting +1 into either new ARC observation fails its original Nim assertion; an evidence-write
  failure also fails natively. Evidence: `build/nim-tests/third/arc-faults.json`.
- Four freshly rebuilt independent base extrinsic corpora (assurances, tickets, guarantees and
  disputes) match **62,170 requests**. Evidence: `build/nim-tests/third/corpora.json`.
- All **233 Python harness tests** pass, including ten native-launcher/evidence/fixture safeguards,
  with the existing parked-policy skip. The fixture checks cover exact independent-reference
  equality, missing input, changed bytes and overriding an inherited stale fixture path.
- All **23 setup/CI safeguards** pass. Protocol provenance retains its existing draft-text skip.
  All **864 Nim files** pass formatting. Logs are under `build/nim-tests/third/`. Individual
  cumulative invocations also pass for all eleven suites, retaining all four ARC report fields.

The first two increments remain documented with their original counts above. Current native
migration totals are **11/59 ordinary file suites migrated, 48 remaining**. Strict negative probes,
independent references and multi-process orchestration retain their existing roles. This is
focused local verification; it does not claim a fresh full QUIC/crypto run or Linux CI result.


## Verification of the fourth increment

Same pinned macOS ARM64 checked-LTO profile:

- All **fifteen native suites** pass, including the private block alias assertions. Their seven
  ARC workloads all return to their observed baselines after 1,000 isolated cycles each.
- Injecting +1 into each newly moved work-package/header/block observation fails its original
  Nim assertion. Missing block fixture configuration also fails natively before child paths are
  constructed. Evidence: `build/nim-tests/fourth/native-faults.json`.
- Three freshly rebuilt independent base corpora (work-package, header and block) match
  **45,461 requests**. Evidence: `build/nim-tests/fourth/corpora.json`. Original published
  malformed-policy fixtures remain covered alongside the authored valid counterparts.
- All **235 Python harness tests** pass, including twelve native launcher/evidence/fixture
  safeguards, with the existing parked-policy skip. Group checks cover missing/changed later
  children, stale inherited paths, original-oracle equality and complete source-hash inventory.
- All **23 setup/CI safeguards** pass. Protocol provenance retains its existing draft-text skip.
  All **864 Nim files** pass formatting. Individual cumulative invocations pass for all fifteen
  suites, retaining all seven ARC report fields. Logs and native/corpus evidence are under
  `build/nim-tests/fourth/`.

Current migration totals: **15/59 ordinary file suites migrated, 44 remaining**. Earlier increment
results remain historical records above. These are focused local checks, not a fresh full
QUIC/crypto lifecycle run or a Linux CI result for these new changes. Production code and protocol
behavior are unchanged.


## Verification of the fifth increment

Same pinned macOS ARM64 checked-LTO profile:

- All **nineteen native suites** pass, including both relocated private-wire alias tests. All nine
  ARC workloads retain their original 1,000 isolated cycles and return to observed baselines.
- Injecting +1 into the bitstring or collection observation fails its original Nim equality
  assertion and leaves no fresh success evidence. Records: `build/nim-tests/fifth/native-faults.json`.
- Two freshly rebuilt independent corpora match **24,435 requests**: 11,274 Boolean/fixed/variable
  bitstring observations and 13,161 collection order/framing/field observations. Commands and
  verdicts: `build/nim-tests/fifth/corpora.json`.
- All **235 Python harness tests** pass with the existing parked-policy skip. All **23 setup/CI
  safeguards** pass; protocol provenance retains its existing draft-text skip.
- All **864 Nim files** pass formatting. Individual cumulative invocations pass for all nineteen
  suites, retaining nine ARC report fields; all 59 source paths resolve. Focused logs are under
  `build/nim-tests/fifth/`.

Current migration totals: **19/59 ordinary file suites migrated, 40 remaining**. Earlier increment
counts remain historical records above. Verification is local and focused; these results do not
claim a new full QUIC/crypto lifecycle run or a Linux CI pass for this increment.


## Verification of the sixth increment

Same pinned macOS ARM64 checked-LTO profile:

- All **twenty-one native suites** pass, retaining ten original 1,000-cycle ARC workloads and
  their fresh equal before/after observations.
- Injecting +1 into the C.2 after-release observation fails its original Nim assertion and
  leaves no fresh success evidence: `build/nim-tests/sixth/native-faults.json`.
- A freshly rebuilt C.2 driver matches **26,090 independent requests**. Commands and verdicts:
  `build/nim-tests/sixth/corpora.json`.
- All **235 Python harness tests** pass with the existing parked-policy skip. All **23 setup/CI
  safeguards** pass; protocol provenance retains its existing draft-text skip.
- All **864 Nim files** pass formatting. All twenty-one individual cumulative invocations pass,
  all 59 suite source paths resolve, and the relocated private body is unchanged apart from its
  include path. Records and logs: `build/nim-tests/sixth/`.

Current migration totals: **21/59 ordinary file suites migrated, 38 remaining**. Earlier counts
remain historical records above. These are focused local checks, not a fresh full QUIC/crypto
lifecycle run or Linux CI result. Implemented M1 scope and protocol behavior remain unchanged.


## Verification of the seventh increment

Same pinned macOS ARM64 checked-LTO profile:

- The supported unit command passes **21 pure codec suites and three native-linked state suites**,
  retaining eleven fresh ARC observations. All **24 individual cumulative invocations** also pass;
  all 59 source paths resolve and both moved public assertion bodies are unchanged.
- Injecting +1 into private trie's after-release observation fails its original Nim assertion,
  with no fresh success evidence: `build/nim-tests/seventh/native-faults.json`.
- Fresh production-linked independent adapters match **14,541 requests**: **12,233 layout** and
  **2,308 trie** cases. Commands, hashes and verdicts: `build/nim-tests/seventh/corpora.json`.
- All **238 Python harness tests** pass with the existing parked-policy skip. Three additional
  safeguards cover missing profiles/libraries, production/observer host flags and cache isolation,
  and missing linked output expectations. The quick-plan safeguard now checks all four invocations.
- All **23 setup/CI safeguards** pass; protocol provenance retains its existing draft-text skip.
  All **864 Nim files** pass formatting. Logs and individual suite records are under
  `build/nim-tests/seventh/`.

Current migration totals: **24/59 ordinary file suites migrated, 35 remaining**. Earlier counts
remain historical. Verification is focused and local; it does not claim a new full crypto/QUIC
lifecycle run or Linux CI pass. Implemented M1 scope and protocol behavior remain unchanged.


## Verification of the eighth increment

Same pinned macOS ARM64 checked-LTO profile:

- The supported unit command passes **21 pure codec suites and six native-linked state suites**,
  retaining thirteen fresh ARC observations. All **27 individual cumulative invocations** pass;
  all 59 source paths resolve. Comparing each moved body with its prior version confirms that
  only import/include paths and the two ARC reporting blocks changed.
- Injecting +1 into Safrole or private authorization's after-release observation fails the
  original native assertion and leaves no fresh success evidence. Records:
  `build/nim-tests/eighth/native-faults.json`.
- Fresh production-linked independent adapters match **10,127 requests**: **3,068 Safrole** and
  **7,059 authorization** cases. Commands, request hashes and verdicts:
  `build/nim-tests/eighth/corpora.json`.
- All **238 Python harness tests** and **23 setup/CI safeguards** pass. The parked-policy and
  draft-text provenance skips are unchanged. All **864 Nim files** pass formatting. Logs and
  individual suite records are under `build/nim-tests/eighth/`.

Current migration totals: **27/59 ordinary file suites migrated, 32 remaining**. Earlier counts
remain historical. These are focused local checks, not a fresh full crypto/QUIC lifecycle run or
Linux CI result. Implemented M1 scope and protocol behavior remain unchanged.


## Verification of the ninth increment

Same pinned macOS ARM64 checked-LTO profile:

- The supported unit command passes **21 pure codec suites and ten native-linked state suites**,
  retaining fifteen fresh ARC observations. All **31 individual cumulative invocations** pass;
  all 59 source paths resolve. Comparing all four moved bodies with their prior versions confirms
  that only import/include paths and the two ARC reporting blocks changed.
- Injecting +1 into either private suite's after-release observation fails its original native
  assertion and leaves no fresh success evidence. Records:
  `build/nim-tests/ninth/native-faults.json`.
- Fresh production-linked independent adapters match **10,064 requests**: **7,298 consensus** and
  **2,766 dispute** cases. Commands, request hashes and verdicts:
  `build/nim-tests/ninth/corpora.json`.
- All **238 Python harness tests** and **23 setup/CI safeguards** pass. The parked-policy and
  draft-text provenance skips are unchanged. All **864 Nim files** pass formatting. Logs and
  individual suite records are under `build/nim-tests/ninth/`.

Current migration totals: **31/59 ordinary file suites migrated, 28 remaining**. Earlier counts
remain historical. These are focused local checks, not a fresh full crypto/QUIC lifecycle run or
Linux CI result. Implemented M1 scope and protocol behavior remain unchanged.


## Verification of the tenth increment

Same pinned macOS ARM64 checked-LTO profile:

- The supported unit command passes **21 pure codec suites and twelve native-linked state suites**,
  retaining sixteen fresh ARC observations. All **33 individual cumulative invocations** pass;
  all 59 source paths resolve. Comparing both moved bodies with their prior versions confirms
  that only import/include paths and the private ARC reporting block changed.
- Injecting +1 into private history's after-release observation fails its original native assertion
  and leaves no fresh success evidence: `build/nim-tests/tenth/native-faults.json`.
- A freshly rebuilt production-linked history adapter matches **1,985 independent requests**.
  Commands, request hash and verdict: `build/nim-tests/tenth/corpora.json`.
- All **238 Python harness tests** and **23 setup/CI safeguards** pass. The parked-policy and
  draft-text provenance skips are unchanged. All **864 Nim files** pass formatting. Logs and
  individual suite records are under `build/nim-tests/tenth/`.

Current migration totals: **33/59 ordinary file suites migrated, 26 remaining**. Earlier counts
remain historical. These are focused local checks, not a fresh full crypto/QUIC lifecycle run or
Linux CI result. Implemented M1 scope and protocol behavior remain unchanged.


## Availability and work-queue batch

History was committed as `1d41c76`. Both public/private availability and work-queue suites now
use Hastur with unchanged production linking and native assertions. Their positional fixture
becomes an explicit checked environment path; missing input fails with no fallback. The committed
independent report and its original oracle are documented in `tests/fixtures/README.md`.

Local checked-LTO verification: **37 suites**, **18 ARC observations**, and **5,853 independent
requests** (2,949 availability; 2,904 work queues) pass. **239 harness tests** pass with the existing
skip. Evidence: `build/nim-tests/remaining/state-reports-*` and `state-reports/corpora.json`.
Migration total: **37/59; 22 remaining**. Next: fixed/numeric state families. Linux CI pending.


## Fixed/numeric state batch

Privileges, statistics, outputs and account metadata public/private suites pass through Hastur
with original assertion bodies and production crypto profiles. **45 suites**, **22 ARC observations**,
and **7,700 independent requests** pass (1,390 privileges; 2,615 statistics; 1,901 outputs;
1,794 accounts), plus **239 harness tests** with the existing skip. Evidence:
`build/nim-tests/remaining/state-fixed-*` and `state-fixed/corpora.json`.
Migration total: **45/59; 14 remaining**. Next: service values, requests and composition.


## Service and composition batch

All five service-value/request/composition cases pass Hastur, with production versus observer
linking preserved. Composition reads the same independent sixteen chapters through an explicit
checked fixture path. **50 suites**, **25 ARC observations**, **240 harness tests** (existing skip),
and **18,791 independent requests** pass: 2,047 service values, 2,273 requests, 14,471 composition.
Evidence: `build/nim-tests/remaining/state-services-*`, `state-services/corpora.json`, and
`state-composition/corpora.json`. Migration total: **50/59; 9 remaining**. Next: crypto ownership.


## Crypto ownership batch

Seed wiping, assurance context, guarantee messages and Bandersnatch owners pass Hastur with
unchanged observer/native ABIs and original assertions. The launcher now prepares the same
pinned Rust ABI and owner observer as the cumulative runner, forwarding the original C call-site
renames and runtime search paths. **54 suites**, **29 ARC observations** and **240 harness tests**
(existing skip) pass locally. Evidence: `build/nim-tests/remaining/crypto-unit.log` and
`crypto-harness.log`. Migration total: **54/59; 5 remaining**. Next: QUIC native suites.


## QUIC batch and completed native discovery

The five QUIC suites now use Hastur: UDP readiness/retirement, transport setup/teardown,
protocol framing/DER, enabled integration and disabled-provider refusal. Original assertions,
IPv4/IPv6 rounds, native libraries and `-d:integration` separation are preserved. Transport and
integration read explicit environment paths backed by freshly prepared required-file manifests;
missing fixtures or a changed later sibling fail before execution. Certificates/private keys
remain generated under ignored build directories. New harness checks cover dynamic fixture
requirements, sibling integrity and exact native discovery.

UDP expected output retains its original fixed family/round markers; timing diagnostics still
fail the native test when the original readiness assertion fails. Integration's explicit expected
output includes the existing 10,000-case capture selftest marker. That marker was initially omitted
from the new golden; Hastur caught the mismatch without any implementation change.

Local native launch passes **59/59 suites**, **31 ARC observations**, **243 harness tests** with
the existing parked-policy skip, and the existing **23 setup/CI safeguards**. The draft-text
provenance skip is unchanged. Evidence: `build/nim-tests/remaining/quic-unit.log`,
`quic-harness.log`, `final-ci-safeguards.log`, `final-provenance.log` and `final-format.log`.
Full cumulative verification is recorded below when complete. Linux CI remains separate.


## Final cumulative verification

`python3 tools/test.py` completed successfully on macOS ARM64 with the pinned Nimony 0.6.3,
ARC/Clang/checked-LTO profile and Python 3.14.2. This is a fresh complete local run after migration:

| Gate | Result |
| --- | --- |
| Every production module | 45/45 semantic checks pass |
| Ordinary application suites through Hastur | 59/59 pass |
| Total native/runtime profiles, including six specialized offload/peer profiles | 65/65 pass |
| Independent corpora | 41/41 pass |
| Fresh native ARC observations | 31/31 retain their 1,000-cycle baseline |
| Compiler/privacy/nominal/schema/ownership rejection checks | 676/676 pass |
| Python harness tests | 243 pass, one existing parked-policy skip |
| Setup/CI safeguards | 23 pass |
| Formatting | 864 Nim files pass |

The full run also passes authenticated startup/matrix, retained and integrated services, IPv6
mesh/reconnect and peer loss, 40-session teardown soak, admission recovery, pre-request connection
loss and ten real-crypto bounded offload waves. Strict failed-result and ownership process checks
remain intact. Every source hash in the cumulative report matches the final tested source tree.
The report retains its historical `partial-checks-passed` status label: implemented verification
passes, while protocol-policy gates and full JAM functionality remain separate.

Reproducible transcript: `build/nim-tests/remaining/full-verification.log`.
Detailed source hashes, commands and verdicts: `build/nimony-trial/verification/results.json`.
Module inventory: `build/nimony-ci/modules/results.json`.

Migration is complete: **59/59 ordinary suites; zero remaining**. Python remains for independent
references, native preparation, specialized profiles, strict negative tests and multi-process
orchestration. Production sources, wire behavior and dependency/compiler pins are unchanged.
Linux execution still requires the PR CI run; local safeguards are not a Linux runtime result.

## Linux CI confirmation

The pushed migration revision `a3ed5131f473f83953361d1c6c22eaddbc16944d` passes both Linux
runtime and all-source compilation jobs on 2026-10-17:
[PR run](https://github.com/jacogr/ragnarok/actions/runs/39017975011) and
[push run](https://github.com/jacogr/ragnarok/actions/runs/39017971723).
This verifies the completed native-suite migration on Linux. Subsequent Makefile additions
are separately verified locally and are not part of those run revisions.
