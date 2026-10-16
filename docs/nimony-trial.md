# Nimony nightly trial

Branch: `nimony`, based on `aea27ad` (the codec-directory move). Trial date: 2026-10-16.
Status: **six native codec suites, guarded results and the five-schema owned-snapshot layer pass;
report ownership and the broader port remain unported**. This branch targets Nimony directly, without
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

All 81 runtime rejection checks require the contract diagnostic and expected exit status; an
unrelated process failure cannot count as protection. The 56 privacy/API checks require member-specific
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

## Fourth increment: owned snapshots

`owned.nim` now runs under Nimony for Bytes, Optional, Work, Preimages and Digest snapshots.
The handle's private backing reference is explicitly nullable; default handles still return
`InvalidOwner`. Each accessor retains one stable local reference before checking nil, allowing
Nimony to prove later access without `lenientnils`, unchecked casts or assumptions. This is a
source proof requirement, not evidence that the former immutable handle had a decoder defect.

`OwnedResult[T]` keeps its status/payload private and gates `value` on success. Copied optional and
work metadata hide their tags and lengths, with presence/Success preconditions on length reads.
Defaults remain Uninitialized results, absent optional metadata and zero-length Success work
metadata. Explicit sibling helpers construct completed generic results or length-only work metadata;
these helpers do not validate an arbitrary handle. A default handle deliberately wrapped as a
success is still rejected by the owner APIs themselves.

The existing 10,000-case five-schema ownership corpus passes. Source mutation, escaped stack
inputs, same-sized distinct owners, detached payload mutation, short-output atomicity, indices,
schema mismatches, default-owner rejection and exact-prefix re-emission retain their checks.
New replacement tests keep the old snapshot alive after its original handle is overwritten.

After 100 warmup calls, 1,000 varying-payload retain/copy/drop cycles across **all five schemas**
leave the public `getOccupiedMem()` count unchanged. `results.json` records the observed before/
after values and workload. This checks live allocator occupancy after isolated scopes, not RSS,
allocator page return or general leak freedom; no private ARC/runtime hooks are used.

This increment adds 27 runtime misuse rejections and 14 compilation rejections, including the
existing wrong-source-pool API probe. Cumulative coverage is **81 runtime result/variant/constructor
rejections and 56 compilation rejections**, alongside six positive suites and three runtime probes.
Constructor users in report ownership/block composition were mechanically adapted to the private
shared result API; those higher-level families are not yet runtime-ported or claimed passing.

## Fifth increment: complete work reports and report snapshots

`work_report.nim` and `report_owned.nim` now run under the same pinned Nimony nightly.
Report/header results keep their discriminator and payload private. Read-only `error` remains
available on every outcome; `value` and report `consumed` require success. Default results still
carry Uninitialized. Hash/root/slot/shard domains remain distinct. Report owners use a stable
nil-checked backing reference, retaining the original private consumed prefix through ARC.

A child digest's span accessor returns a copy. Report decoding and the independent-source test
adapter now rebuild the successful work variant when rebasing the child span to the original
complete input/pool. Mutating a returned descriptor would otherwise leave the stored offset
unchanged. The full independent semantic/byte corpus catches this regression.

All **18,430** existing independent report requests pass, including pinned published 0.8.0 tiny/full
fixtures, every field, canonical ordering, truncations, aggregate limits, maximum unsigned values,
malformed fuzz cases, late encoder failures, overlap atomicity and owner extraction after input
mutation. The shared codec adapter is split from the existing explicit crypto `check` subcommand;
that integration entry point is preserved, but its signature/hash checks remain unported M2 work.
No crypto verification is replaced with a successful stub or omitted from the ordinary runner.

A seventh positive suite checks escaped input lifetimes, same-sized distinct owners, retained
replacement handles, metadata-copy independence, payload-free work errors, every default-owner
API and atomic short-output failure. After 100 warmup cycles, 1,000 report retain/replace/copy/drop
cycles with varying bytes leave public live occupancy unchanged: **192 → 192 bytes** on this Mac.
This measures that isolated ARC workload, not RSS or general leak freedom.

This increment adds **14 runtime misuse rejections**, **10 privacy compilation rejections** and
**four nominal-type compilation rejections**. Cumulative coverage is **95 runtime result/variant/
constructor rejections and 70 compilation rejections**, plus **seven positive suites**, the report
corpus and three language/runtime probes. The generic hash diagnostic rejects the substitution but
prints `ReportHash` on both sides without its static domain argument; the rejection is useful, while
its explanation is less precise than the slot/shard diagnostics. Linux remains unverified.

## Sixth increment: assurance records and extrinsics

`assurances.nim` now runs under the same pinned Nimony nightly. Both result types keep status and
payload private, with read-only outcomes and success preconditions on written/count/consumed.
Defaults still return Uninitialized. The fixed owned records require no retained heap owner;
explicit initialization preserves zero storage beyond a profile's serialized bitfield width.
Configuration, error precedence, two-pass preflight, atomic writes and wire encodings are unchanged.

All **20,706** existing independent assurance requests pass, including pinned published tiny/full
fixtures, every configured core's bit position, width boundaries, full validator counts, unsigned
configuration extremes, every representative truncation, count/order/index/padding failures,
6,000 structured/unstructured fuzz requests, source mutation, unused destination sentinels and
encoder/decoder overlap rejection. Another **18,831** requests compare `inspectAssurances` directly
with the independent decoder model using maximum valid typed capacity; inspection itself needs no
record destination. Every original decode input receives its own inspection expectation, including
semantic failures that a small typed destination could otherwise mask.

An eighth positive suite checks guarded defaults, empty-prefix consumption, unsigned configuration
bounds, escaped source lifetimes, independently mutable fixed copies and zero-extended tiny-profile
bitsets. The trusted fixture utility uses checked unsigned/hex parsers, explicit byte append loops,
public open-array views and aligned fixed storage for deliberate unsafe overlap probes. No
production allocation, compiler patch or private runtime dependency was introduced. This is codec
coverage; contextual signature verification remains separate M2 work.

This increment adds **10 runtime misuse rejections**, **12 privacy/read-only compilation
rejections** and **three nominal-domain compilation rejections**. Cumulative coverage is now
**105 runtime result/variant/constructor rejections and 85 compilation rejections**, alongside
**eight positive suites**, both independent report/assurance corpora and three runtime probes.
The compiler rejects anchor/signature swaps, validator/core index swaps and configuration-domain
swaps. Verification remains local macOS ARM64 with checked ARC/Clang LTO; Linux is unverified.

## Seventh increment: guarantee records and extrinsics

`guarantees.nim` now runs under the same pinned Nimony nightly. `GuaranteeResult[T]` hides its
status/value, exposes read-only outcomes and requires success before value access. Defaults remain
Uninitialized. `guaranteeFailure[T]` lets sibling adapters report a non-success reason; it cannot
construct success. The block adapter's existing missing-owner return was mechanically changed to
this helper; block runtime parity is not claimed. Private parent storage is explicitly nullable,
and getters retain a stable nil-checked reference for access and ARC lifetime proofs.

The original scan-before-allocation, frame budgets, error precedence, core/credential order and
fixed E4/E2 fields are unchanged. Child reports still use their validated immutable owner API.
The complete **7,617-request** independent extrinsic corpus passes, including published tiny/full
fixtures, the full 341-core count, every representative truncation, late errors, malformed fuzz,
complete fixed fields, caller-source mutation, copied-getter independence and atomic output.
Another **7,555** direct inspections check every original decode input without child capture.
**8,836** additional standalone capture/inspection/measurement/fresh-encoding comparisons check
complete child bytes and fixed metadata, prefix consumption, budgets through uint64 maximum,
truncations, credential counts, configuration extremes and deterministic malformed input.
Total guarantee corpus: **24,008 requests**. The standalone oracle parses directly so removing
an extrinsic count cannot accidentally change budget-versus-report failure precedence.

The ninth positive suite retains the existing late-failure, source-alias and default-owner checks.
It additionally replaces parent handles while aliases retain old snapshots, returns child reports
past the last parent scope, mutates original sources, and runs 1,000 isolated retain/replace/copy/drop
cycles after 100 warmups. Public live occupancy remains **16,608 → 16,608 bytes** on this Mac;
other outer test snapshots remain live during that observation. This checks that workload's ARC
release, not RSS or general leak freedom. No private runtime/refcount hooks are used.

This increment adds **29 runtime misuse rejections** and **11 compilation rejections** (eight
private/read-only owner/result checks and three nominal slot/index/signature checks). Cumulative
coverage is **134 runtime result/variant/constructor rejections and 96 compilation rejections**,
plus **nine positive suites**, the report/assurance/guarantee corpora and three runtime probes.
The former FieldDefect catch is replaced by independent processes matching the actual Nimony
success-contract failures, including all public generic result instantiations and the failure
factory's precondition. The four independent guarantee-oracle example tests also pass.
Verification remains local macOS ARM64 with checked ARC/Clang LTO; Linux is unverified.
Credential verification, assignments and eligibility remain separate state/M2 work.

## Remaining work and next bounded increment

Next: port ticket records and extrinsics (`tickets.nim`), preserving fixed E1 attempts and
784-byte opaque proofs, guarded progress results, caller-buffer atomicity and the independent
published/boundary/fuzz corpus. Cryptographic proof verification remains separate M2 work.
Other M1 families and M2/M3 remain separate increments.

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
verified scalar/composite/digest/owned/report/assurance/guarantee slice. A missing check or failed guard
still makes the runner exit one. There is no claim of full-client parity or an already switched normal CI. Formatting passes.
Historical Nim 2 measurements are references, not an ongoing second source-support requirement.
