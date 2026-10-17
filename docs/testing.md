# Native test migration

Branch: `nim-tests`, based on merged Nimony migration commit `8db659c`.
The first bounded group is the natural-number, fixed-width integer and bounded-container codecs.
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

The cumulative `python3 tools/test.py` path delegates these same three suite identities to Hastur,
records its command/log/verdict and hashes each source and `.output` file. There is no second
Python compile/run path for those suites in the supported cumulative runner. The remaining
56 of its 59 ordinary file-based suites still use the previous launcher, alongside specialized
profiles and negative checks. CI already calls that cumulative path, so the native runner migration
needs no duplicate workflow/job or second execution of the three suites.

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

Next bounded group: composite/report digest codecs and immutable snapshot tests, keeping their
independent Python corpora. Then proceed through extrinsics/packages/header/block and state
families; native-linked crypto and networking ownership suites follow with explicit linker/fixture
requirements. Named `suite`/`test` conversion can be revisited when the selected compiler supplies
a supported implementation; no compiler upgrade or patch is part of this branch.

## Verification of this increment

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
