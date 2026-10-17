# Native test migration

Branch: `nim-tests`, based on merged Nimony migration commit `8db659c`.
Five bounded groups are migrated: primitives/containers, composites/digests/snapshots,
extrinsics, work-package/header/block codecs, and bitstrings/collections with private-wire checks.
Production code, wire behavior, bounds/ownership contracts and independent references are unchanged.

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
python3 tools/test.py --suite unit
```

That command requires only the normal pinned toolchain installation and Clang; it does not build
crypto or network dependencies. Python is a thin path/flag launcher here. After sourcing
`build/toolchain/env.sh`, Hastur can also be invoked directly using its documented CLI; retain the
flags printed by the supported command so checks and optimization settings do not change.

The cumulative `python3 tools/test.py` path delegates all nineteen migrated suite identities to Hastur,
records its command/log/verdict and hashes each source and `.output` file. There is no second
Python compile/run path for those suites in the supported cumulative runner. The remaining
40 of its 59 ordinary file-based suites still use the previous launcher, alongside specialized
profiles and negative checks. CI already calls that cumulative path, so the native runner migration
needs no duplicate workflow/job or second execution of migrated suites.

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

Next bounded group: C.2 record suites, including their private-wire alias companion. State
families follow, then native-linked crypto and networking ownership suites with explicit
linker/fixture requirements. Named `suite`/`test` conversion can be revisited when the selected compiler supplies
a supported implementation; no compiler upgrade or patch is part of this branch.

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
