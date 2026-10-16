# Nimony nightly trial

Branch: `nimony`, based on `aea27ad` (the codec-directory move). Trial date: 2026-10-16.
Status: **partial codec port works; migration is blocked by missing safety behavior**.
This branch targets Nimony directly; dual Nim 2/Nimony source support is not a goal.
The main branch remains on Nim 2.2.12. No dependency or protocol pins change.

## Compiler and environment

The latest published nightly at trial start was
[Nimony 0.6.3, 2026-10-15](https://github.com/nim-lang/nimony-website/releases/tag/nightly-0.6.3-5b51edfed),
upstream revision `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`.
This is the same revision as the earlier source-built one-shot trial; this run uses the official
binary archive and extends the source port and runtime checks.

- Asset: `nimony-0.6.3-5b51edfed-macos_arm64.tar.xz`.
- SHA-256: `8c61fe32bb50c8ab14b4234267abc3cc4057420f9e43d89d6db4f6cfc7639038`, verified
  against the release asset's published digest before extraction.
- Local environment: macOS arm64, Apple Clang 21.0.0; control compiler Nim 2.2.12.
- C backend, ARC, release speed optimization and Clang LTO; bounds checks enabled, assertions
  retained. Neither compiler uses danger mode. Nim control builds explicitly retain assertions,
  bounds, range, field and overflow checks.
- Nimony range subtypes use compile-time proofs rather than Nim 2 runtime range checks. The
  compact-natural tail counters now state their existing `0..8` invariant explicitly.
- No Linux result, performance comparison or full M1/M2/M3 parity is claimed.

## Retained partial port

Five existing native suites execute successfully under the nightly: natural numbers, fixed-width
unsigned integers, bounded containers, composite values and work digests. Their existing boundary,
truncation, canonicality, aliasing, atomic-failure and 10,000-case fuzz checks remain active where
applicable. These passes establish only the exercised paths, not compiler-wide correctness.

The source adaptations are explicit default initialization, unqualified enum labels in variant
branches, a bounded compact-tail counter and ordinary indexing for a mutable sequence sentinel.
Tests import Nimony's assertion/output modules directly and use its release-enabled `assert`.
There is no compatibility include, compiler-conditional source branch or assertion alias.
No compiler or standard-library sources are patched. Nim 2 is used only as the reference control
for the safety measurements; its coincidental acceptance of these syntax changes is not a support
requirement for the port.

Broader exploratory edits were removed rather than retaining an unverified bulk port. The
production result types, immutable-owner APIs, protocol encodings and normal CI remain intact.

## Safety results

The same subprocess fixtures are compiled with checked release/LTO profiles for both compilers.
Runtime arguments prevent constant folding of the bounds and signed-overflow probes.

| Probe | Nim 2.2.12 control | Nimony nightly | Interpretation |
| --- | --- | --- | --- |
| Deliberately false assertion | Rejects at runtime | Rejects at runtime | Existing test assertions execute. |
| Index one past a one-element sequence | Rejects at runtime | Rejects at runtime | The tested sequence bounds guard executes. |
| Signed `high(int) - 1 + 2` | Rejects with `OverflowDefect` | Prints `-9223372036854775808`, exits 0 | Required signed-overflow failure is missing in the tested profile. |
| Read `length` from a failed `decodeBytesBorrowed` result | Rejects with `FieldDefect` | Prints `0`, exits 0 | A caller can read nonexistent success data from the actual codec result. |

The field probe is `tests/native/nimony_wrong_variant.nim`: an empty byte buffer produces
`ContainerError.Truncated`, then the caller intentionally reads the success-only `length` field.
This reproduces the exact invalid-application-state risk that the result variants were introduced
to prevent. Nimony's successful compilation does not protect that access. Do not remove the
existing field-guard tests or reinterpret this behavior as equivalent safety.

These results are observations for this nightly and backend, not a claim that all Nimony arithmetic
or variants are unsafe. The required Nim-style overflow/field command-line switches are not accepted
by this nightly. Restoring equivalent behavior would require supported compiler functionality or a
reviewed source/API redesign; it must not be hidden in skipped tests or unchecked compatibility code.

## Remaining port work

- M1: typed collection generics need explicit Nimony constraints and replacements for unsupported
  `static` statement checks. Other codec tests use array slices, writable `toOpenArray` views and
  `FieldDefect` catches that need supported equivalents while preserving the same coverage.
- M2: no native crypto/VRF runtime parity has been established. Exploratory semantic checks are
  insufficient to establish FFI ownership, destructor, secret erasure or thread safety.
- M3: the current `std/nativesockets`, `std/selectors` and top-level `posix` imports do not resolve
  in the nightly. It has other networking facilities; porting the dispatcher requires API and
  lifecycle work, followed by the existing service/mesh/resilience/offload tests. Networking has
  not reached runtime validation.

The two measured safety gaps block adoption before that larger port. This branch preserves a
small reproducible foothold for a later nightly; no global toolchain switch or migration commit
has been made.

## Reproduce

Download the exact macOS ARM64 asset from the release above, verify its SHA-256, then extract it
under ignored `build/nimony-trial/`. The archive supplies `nimony/bin/nimony` and its libraries.
Use a C compiler available on `PATH`; no upstream build scripts are needed for this binary trial.

```sh
python3 tools/test_nimony.py --compiler build/nimony-trial/nimony/bin/nimony
```

The runner deliberately exits **1** when a required safety check fails. It prints individual
results and writes `build/nimony-trial/verification/results.json` plus build/run logs, compiler
versions, nightly metadata, source hashes, flags and observed outputs. A nonzero result must not be
presented as a passing migration. Even a future clean run covers only this partial trial.

Formatting verification:

```sh
python3 tools/format.py --check
```

Formatting passes locally. Before removal of the compatibility layer, the normal Nim codec
regression passed 45,215 requests plus native and negative-compilation checks; this is a recorded
control, not a requirement to maintain dual source support. Linux confirmation remains separate. The M1 request-namespace question stays
parked for Gray Paper 0.8.1/0.8.2 review; this compiler trial does not reopen protocol decisions.
