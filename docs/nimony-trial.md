# Nimony nightly trial

Branch: `nimony`, based on `aea27ad` (the codec-directory move). Trial date: 2026-10-16.
Status: **five native codec suites and their scalar/composite/digest result-safety checks pass;
owned snapshots and the broader port remain unported**. This branch targets Nimony directly, without
dual-compiler source support. The main branch remains on Nim 2.2.12. Protocol/dependency pins
are unchanged.

## Compiler and environment

The latest published nightly at trial start was
[Nimony 0.6.3, 2026-10-15](https://github.com/nim-lang/nimony-website/releases/tag/nightly-0.6.3-5b51edfed),
upstream revision `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410`.
This is the same revision as the earlier source-built one-shot trial; this run uses the official
binary archive and extends the source port and runtime checks.

- Asset: `nimony-0.6.3-5b51edfed-macos_arm64.tar.xz`.
- SHA-256: `8c61fe32bb50c8ab14b4234267abc3cc4057420f9e43d89d6db4f6cfc7639038`, checked
  against the release asset digest before extraction.
- Local environment: macOS arm64, Apple Clang 21.0.0. Historical control compiler: Nim 2.2.12.
- C backend, ARC, release speed optimization and Clang LTO. Bounds/contracts and assertions stay
  enabled; neither danger mode nor `noAssertions` is used.
- Nimony range subtypes use compile-time proofs. Compact-natural tail counters state their
  existing `0..8` invariant explicitly.
- No Linux result, performance comparison or full M1/M2/M3 parity is claimed.

## Arithmetic policy

The initial comparison observed that signed `high(int)-1+2` returns
`-9223372036854775808` under this Nimony profile, whereas checked Nim 2 raises `OverflowDefect`.
The maintainer confirms that **wrapping arithmetic is intentional Nimony behavior**. It is a
language difference, not a compiler defect or a migration gate. Do not emulate Nim 2 arithmetic
exceptions or maintain an alternate compiler path.

Protocol sizes, offsets and conversions must still be validated explicitly. The bounded codec
compares counts in uint64 and uses remaining-length subtraction/division before multiplication or
narrowing. Its tests reject claims at `high(int)-1`, `high(int)`, `high(int)+1` and
`high(uint64)` without allocating advertised payloads or modifying caller output. Other modules
need the same boundary review as they are ported; passing a raw wrapping probe is not that review.

## Retained partial port

Five existing native suites execute successfully: naturals, fixed-width unsigned integers,
bounded containers, composite values and work digests. Their boundary, truncation, canonicality,
aliasing, atomic-failure and 10,000-case fuzz checks remain active where applicable. These passes
establish only exercised paths, not compiler-wide correctness.

Adaptations include explicit default initialization, unqualified enum labels in variant branches,
a bounded compact-tail counter and ordinary mutable sequence indexing. Tests directly import
Nimony assertion/output modules and use its release-enabled `assert`. There is no compatibility
include or compiler-conditional source path. Compiler and standard-library sources are pristine.
Broader unverified exploratory edits were removed.

## First safety increment: bounded results

The initial trial reproduced a real invalid read: `decodeBytesBorrowed` returned `Truncated`,
but reading its public `length` field printed zero. Checked Nim 2 rejected the same caller with
`FieldDefect`. Nimony does not supply that raw variant-field protection; result APIs must enforce
it explicitly instead of deleting their negative tests.

`WriteResult`, `BlobResult` and `SequenceResult` now keep both discriminator and success fields
private. Their existing property names are read-only accessors; success-only getters have Nimony
`.requires: value.status == ContainerError.None` preconditions. Proven calls need no runtime
check; undecided calls retain the supported contract check. No compiler hook or blanket exception
emulation is involved. Only the defining module constructs successes. Empty valid values remain
distinct from default/uninitialized results.

| Check under checked release/LTO | Current observation |
| --- | --- |
| Five existing native codec suites | Pass. |
| Deliberately false assertion | Stops at the assertion. |
| Index past a one-element sequence | Stops at the bounds contract. |
| Signed arithmetic wrapping | Matches the accepted Nimony behavior. |
| Six bounded-result properties, actual failures | All six stop at the success precondition. |
| Same six properties, default results | All six stop at the success precondition. |
| Three raw-payload reads, private retagging, public-reason assignment and forged success | All six fail compilation for the intended member. |
| Natural/fixed-width success payload reads on default/error results | All ten stop at their success precondition. |
| Error-reason reads on successful natural/fixed-width results | All three stop at their failure precondition. |
| Primitive private storage, retagging, forgery and public-property assignment | All twelve fail compilation for the intended member. |
| Composite/digest result payload reads on defaults/errors | All eighteen stop at the success precondition. |
| Absent optional and six work-error payload reads | All eight stop at their variant precondition. |
| Invalid explicit constructor arguments | All three stop at their constructor precondition. |
| Composite/digest result and nested-variant privacy | All 24 raw-access, retagging, assignment and forgery probes reject compilation. |

All 54 runtime rejection checks require the contract diagnostic and expected exit status; an
unrelated process failure cannot count as protection. The 42 privacy checks require member-specific
compilation diagnostics. Existing successful property reads are exercised by the positive suites.
Malformed input still returns typed failure; invalid caller access is a programmer contract error.
Wire bytes, output atomicity and borrowed-storage lifetimes do not change.

## Second safety increment: primitive results

`DecodeResult`, `FixedDecodeResult` and `FixedEncodeResult` now have private Boolean
discriminators, success payloads and failure reasons. `ok` is read-only. The existing property
spellings (`value`, `consumed`, `encoded`, `error`) call guarded accessors: payloads require success,
and error reasons require failure. Callers cannot retag a failure or forge a success through safe
construction. Returned fixed-byte storage is copied, with no new borrowed lifetime.

Default behavior is unchanged: natural decode defaults fail with `truncated`; fixed encode/decode
defaults fail with `InvalidWidth`. Zero-width fixed encoding/decoding remains successful for zero,
consuming/emitting no bytes. Wire encodings, byte widths and canonicality rules are unchanged.
The existing natural/fixed boundary and 10,000-case fuzz suites, plus bounded/composite/digest
integration, all pass under the same checked ARC/Clang LTO profile.

This increment adds 13 runtime rejection checks (ten failed/default payload reads and three
success-side error reads) and 12 private-state/forgery compilation rejections. Combined with the
previous increment, the runner verifies **25 runtime result rejections and 18 compilation
rejections**, alongside the five positive suites and three runtime-language probes.

## Third safety increment: composite/digest results and nested variants

`CompositeWrite`, `OptionalResult`, `WorkResult`, `PreimageResult` and `DigestResult` now keep
private status/payload alternatives. Their property names remain read-only, with success
preconditions for values and progress. Defaults retain `CompositeError.Uninitialized`.
The original failed-optional progress reproducer is now one of the passing guarded probes.

`OptionalBlob` and `WorkOutput` also hide their discriminators and spans. Construct source
values with `absentBlob`, `presentBlob`, `successfulWork` and `failedWork`. Span access requires
presence/Success; `failedWork` rejects Success because that alternative needs an explicit span.
Constructors accept source coordinates; matching-pool bounds remain the encoder's responsibility,
with the same typed errors and atomic output behavior. They do not retain or validate a pool.
Default optional remains absent; default work output remains an empty Success, as before.

Sibling encoders now use explicit `compositeFailure(reason)` / `compositeWritten(extent)`
builders. A failure reason cannot be None and a completed extent cannot be negative. These
builders express the sibling encoder's completed operation; they do not independently prove
that arbitrary caller storage was written. Raw result fields and discriminators remain private.

Span and digest accessors return copies. Original-input digest offset adjustment rebuilds the
work variant with its checked offset instead of mutating a span returned by an accessor.
Positive tests verify unchanged absence/empty-success bytes, default reasons, original-input
span offsets and independence of extracted descriptors/digests. Existing boundary, aliasing,
truncation, late-failure atomicity and 10,000-case fuzz suites still pass.

This increment adds 29 runtime misuse rejections and 24 compilation rejections. Cumulative
coverage is **54 runtime result/variant/constructor rejections and 42 compilation rejections**,
plus the five positive suites and three language/runtime probes. The runner now exits zero for
this verified slice. That does not establish a working full-client compiler migration.

## Remaining work and next bounded increment

Next: port owned codec snapshots (`owned.nim` and their ownership/result tests), preserving
immutable retained bytes, owner-bound extraction, ARC release and default-owner rejection.
Report ownership and higher-level codec families can then follow in coherent groups. Unported
families still contain public result variants and Nim 2 library/API assumptions.

Further port work remains:

- M1: collection generics need explicit constraints and replacements for unsupported `static`
  statements. Array slices, writable `toOpenArray` views and `FieldDefect` catches need supported
  equivalents without reducing test coverage.
- M2: crypto/VRF runtime parity, FFI ownership, destruction, secret erasure and thread safety are
  unverified. Exploratory semantic checks alone do not establish those properties.
- M3: `std/nativesockets`, `std/selectors` and top-level `posix` imports do not resolve in the nightly.
  Its alternative networking facilities require a dispatcher port and the existing lifecycle,
  service, mesh, resilience and offload tests.
- Toolchain: compiler installation/pinning, normal build commands, formatter setup, Linux CI and
  main documentation still need a deliberate switch after the port demonstrates equivalent safety.

No full migration or normal-CI compiler switch has occurred. The M1 request-namespace question
remains parked for Gray Paper 0.8.1/0.8.2 review; this trial does not reopen protocol decisions.

## Reproduce

Download the exact macOS ARM64 release asset above, verify its SHA-256 and extract under ignored
`build/nimony-trial/`. It supplies `nimony/bin/nimony` and libraries; no upstream build scripts
are required. A C compiler must be on `PATH`.

```sh
python3 tools/test_nimony.py --compiler build/nimony-trial/nimony/bin/nimony
python3 tools/format.py --check
```

The runner now targets **only Nimony**. It writes commands, compiler/nightly metadata, source/test
hashes and individual verdicts to `build/nimony-trial/verification/results.json`, with adjacent logs.
`protected_results_increment: passed`, `status: partial-checks-passed` and exit **0** record the
verified scalar/composite/digest slice. A missing check or failed guard still makes the runner
exit one. There is no claim of full-client parity or an already switched normal CI. Formatting passes.
Historical Nim 2 measurements are references, not an ongoing second source-support requirement.
