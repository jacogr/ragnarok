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

## Eighth increment: ticket records and extrinsics

`tickets.nim` now runs under the same pinned Nimony nightly. `TicketWrite` and `TicketRead` hide
status/payload storage behind read-only outcomes and success preconditions on written/count/
consumed. Defaults remain Uninitialized. Explicit local proof initialization supports definite
assignment; fixed E1 attempts, opaque 784-byte proofs, framing, preflight order and caller-buffer
atomicity are unchanged. Fully owned fixed records require no retained heap owner or ARC wrapper.

All **22,939** existing independent ticket requests pass, including published hash-pinned tiny/full
fixtures, every attempt octet (especially 128..255), conventional and multi-byte test count bounds,
representative truncations, malformed natural prefixes, exact/short capacities and 3,500
structured/random fuzz inputs. Six extra encoding/decoding cases exercise zero and uint64-maximum
limits, including a huge permitted count that still fails the raw-extent proof before narrowing.
Another **22,654** direct inspection requests cover every original/new decode input without typed
capacity restrictions. Total ticket corpus: **45,599 comparisons**.

The tenth positive suite preserves source-mutation lifetime, unused typed-output sentinels,
short-output atomicity and both overlap directions. A new alias case places typed output wholly
inside unrelated trailing input and requires rejection without changing any source byte. Trusted
alias probes use fixed array views within real storage, with no compiler/runtime hooks. The shared
adapter now overwrites caller input before observing successful proof values, preserves nonzero
sentinel records across failures/unused capacity, and parses the complete unsigned fixture domain.
The three independent ticket-oracle example tests also pass.

This increment adds **10 runtime misuse rejections** and **14 compilation rejections** (12
private/read-only result checks and two nominal attempt/proof checks). Cumulative coverage is
**144 runtime result/variant/constructor rejections and 110 compilation rejections**, plus
**10 positive suites**, the report/assurance/guarantee/ticket corpora and three runtime probes.
Verification remains local macOS ARM64 with checked ARC/Clang LTO. No Linux, RingVRF verification
or Safrole eligibility parity is claimed by this codec increment.

## Ninth increment: dispute verdicts and evidence

`disputes.nim` now runs under the same pinned Nimony nightly. `DisputeResult[T]` keeps status/value
private, exposes read-only outcomes and requires success before value access. Defaults remain
Uninitialized. `disputeFailure[T]` permits sibling failure reporting with a non-success reason;
the block adapter's missing-owner branch was mechanically adapted, without claiming block parity.
Private snapshot references are explicitly nullable and retained in stable nil-checked locals.
The judgment getter proves its backing reference independently of the nested verdict query.

Fixed helpers use explicit initialization and supported static parameter syntax. Scan-before-
allocation, section budgets, variable judgment counts, canonical Boolean/E2/E4 fields, ordering,
full-source preflight and atomic output are unchanged. Published tiny/full samples retain their
NonCanonical verdict-order rejection; separately sorted test copies retain their acceptance role.
No upstream source, vector or protocol interpretation changed.

All **10,908** existing independent dispute requests pass. Six extra cases cover unsigned validator/
byte-budget extremes, canonical empty prefixes with trailing input and huge announced counts.
Another **10,831** direct inspections compare all section cardinalities and exact consumption with
independently decoded logical fields. Total dispute corpus: **21,745 comparisons**. Coverage retains
16-verdict/1023-judgment and 16-culprit/fault ceilings, count widths, representative truncations,
budget precedence, every illegal Boolean tag, late ordering/index errors, fixed-field identities,
3,500 structured/random malformed inputs, complete record copies and unused-output sentinels.
The six independent oracle example tests also pass.

The eleventh positive suite preserves all owner/index errors and real-storage alias probes for
outer descriptors, verdicts, nested judgments, culprits and faults. Public writable fixed-array
views replace unsupported writable pointer slices. Snapshot replacement tests retain old aliases,
escape local source scopes, mutate copied metadata/records and exercise all record families.
After 100 warmups, 1,000 isolated retain/replace/copy/drop cycles leave public live occupancy
unchanged: **140,880 → 140,880 bytes** on this Mac. Outer test fixtures remain live throughout;
this checks that workload's ARC release, not RSS or general leak freedom.

This increment adds **25 runtime misuse rejections** and **12 compilation rejections** (eight
private/read-only owner/result checks and four nominal epoch/judge/key/signature checks).
Cumulative coverage is **169 runtime result/variant/constructor rejections and 122 compilation
rejections**, plus **11 positive suites**, five independent family corpora and three runtime probes.
The former FieldDefect catch is replaced by independent exact-contract subprocess checks for every
public result type and failure construction. Verification remains local macOS ARM64 with checked
ARC/Clang LTO. Linux, contextual quorum/epoch eligibility and signature verification remain separate.

## Tenth increment: work-package inputs and retained item snapshots

`work_package.nim` now runs under the same pinned Nimony nightly. `PackageResult[T]` keeps status/
value private and guards application access on success. Default results remain Uninitialized.
Package/item handles use private nullable references, retained in stable checked locals before
access or extraction. Child indices remain private. A child retains its complete original parent
snapshot after package handles are dropped or replaced; no second source pool can be supplied.

Import identities now hide their discriminator and variant payloads. Read-only `kind` selects
success-precondition `root`/`package` getters returning copied nominal identities. `rootImport`
and `packageImport` construct the corresponding typed source; encoder preflight still validates
the fifteen-bit index. Defaults remain Root with index zero and a zero root. No wire, resource,
ordering, duplicate/dependency or gas policy changed. Published profile hashes remain pinned.

All **8,123** existing independent requests pass: **1,460 contexts**, **991 imports**, **959
commitments**, **1,607 standalone items** and **3,106 complete packages**. Coverage includes exact
published tiny/full context/item/package bytes, complete field observation after caller mutation,
E2/E4/E8 and natural boundaries, strict gas inequalities, unsigned aggregate-overflow attempts,
inclusive bundle footprints, cross-item limits, tagged dependency counting, canonical context
sets, truncations, late failures, atomic output and 4,500 structured/random malformed cases.
The eight independent oracle example tests also pass.

The twelfth positive suite preserves every original blob/payload/import/commitment/descriptor
alias check and all default-owner, short-output, escaped-child and context/report consistency
checks. It adds same-sized parent replacement, retained aliases, both named blobs, copied import
identities and orphaned child manifest/payload access. After 100 warmups, 1,000 isolated parent/
child retain/replace/copy/drop cycles leave public live occupancy unchanged: **30,400 → 30,400
bytes** on this Mac, with outer fixtures still live. This measures that workload, not RSS or
general leak freedom.

The nightly lacks enum-type iteration; the two blob roles are enumerated explicitly in their
existing order. The adapter's procedure-symbol template and subsequent expression form exposed
unsupported template/overload binding. Three concrete fixed-record branches preserve all prior
checks. The nominal import probe now calls the typed factory; Nimony rejects the wrong domain but
prints `ReportHash` on both sides without static arguments. These changes use public language
features, with no compiler patches or private runtime hooks.

This increment adds **51 runtime misuse rejections** (48 failed/default result reads and three
wrong import-identity reads) and **23 compilation rejections** (19 result/owner/variant privacy
checks and four nominal-domain checks). Cumulative coverage is **220 runtime result/variant/
constructor rejections and 145 compilation rejections**, plus **12 positive suites**, six family
corpora and three runtime probes. Formatting passes. Verification remains local macOS ARM64 with
checked ARC/Clang LTO; Linux and M2/M3 remain unverified. M1 migration remains partial.

## Remaining work and next bounded increment

Next: port header and marker codecs (`header.nim`), including full/signing header forms,
epoch/winner alternatives, retained owners, guarded results and the independent published/
boundary/lifetime corpus. Other M1 families and M2/M3 remain separate increments.

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
verified scalar/composite/digest/owned/report/assurance/guarantee/ticket/dispute/package slice.
A missing check or failed guard still makes the runner exit one. There is no claim of full-client parity or an already
switched normal CI. Formatting passes.
Historical Nim 2 measurements are references, not an ongoing second source-support requirement.
