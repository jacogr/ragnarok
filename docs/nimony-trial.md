# Nimony nightly trial

Branch: `nimony`, based on `aea27ad` (the codec-directory move). Trial date: 2026-10-17.
Status: **65 native suites, forty-one independent corpora, 1,372 runtime misuse rejections
and 676 compilation rejections pass locally**. Exact chapter/service composition joins the verified
scalar, owned, report/extrinsic, package, header/block, bitstring, collection, C.2, raw-crypto,
state-key/node, bounded trie, entropy/roster/time, authorization, state chapters 3–5/10/12–16
and fixed C(255, service) account records, retained raw service values and request-history framing.
All production codec modules and documented M1 regression families now pass locally, including
the five early independent corpora and their original nominal/privacy safeguards. Local M1
validation migration parity is reached for the implemented scope; the parked request-namespace
policy still qualifies normative state parity. The M2 assurance and guarantee/report
signing-context slices now also pass locally. Bandersnatch guarded results, fixed imports and
native key/setup ownership, contextual VRF/RingVRF and original native-boundary/concurrency
coverage also pass locally. M2 migration regression parity is reached for the implemented
release-reference scope. M3 now has a local UDP/readiness and linked native-transport lifecycle
slice, plus shared SAN/DER identity, structural framing and enabled CE fixture composition.
The one-shot authenticated CE 143 peer matrix and retained service/integrated digest lifecycle
workloads now pass locally. Retained IPv6 mesh/reconnect and twelve peer-death recovery rounds
now pass too; same-process endpoint destruction also passes forty sessions. All 45 production
modules pass independent semantic compilation. Connection/stream admission recovery and
authenticated loss before the first request now pass locally too. Enabled proof offload also passes
locally, reaching implemented-scope M1/M2/M3 migration regression parity. The supported local
setup and bounded checked-LTO performance comparison are now implemented and verified separately
below; the final combined local verification passes. Linux confirmation of this expanded profile
remains open.
This branch targets Nimony directly, without dual-compiler source support. Nim 2.2.12 is retained
only as the historical performance control.
Protocol/dependency pins are unchanged. At the maintainer's request, the existing
`.github/workflows/ci.yml` is now the single Linux workflow and uses the pinned Nimony nightly
on every push, PR and manual run. The separate trial workflow has been removed. The maintainer reports an earlier pushed snapshot passed PR CI; the expanded offload profile
awaits its own Linux result. CI consolidation alone is not a complete migration claim.

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
- Local implemented-scope migration regression parity and the bounded performance comparison
  are recorded below. Linux confirmation of the expanded profile remains a separate gate.

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

`src/codec/work/report.nim` and `report_owned.nim` now run under the same pinned Nimony nightly.
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

`src/codec/work/package.nim` now runs under the same pinned Nimony nightly. `PackageResult[T]` keeps status/
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

## Eleventh increment: headers, signing payloads and markers

`header.nim` now runs under the same pinned Nimony nightly. `HeaderResult[T]` keeps status/value
private and requires success before application access. Defaults remain Uninitialized. Sibling
failure construction rejects None; the block adapter's missing-header return and block fixture's
winner source were mechanically adapted without claiming block runtime parity. All four owner
handle types use private nullable references retained in stable nil-checked locals.

Epoch/winner source and copied-metadata alternatives now keep presence and payloads private.
Read-only presence is always available; entropies, sequence copies and counts require presence.
Absent/default marker values remain absent. `presentEpoch`/`presentWinners` and their absent
counterparts build source alternatives; encoder preflight still validates their cardinalities.
Explicit `editEpochValidators`/`editWinnerTickets` return checked mutable source fields, while
`epochValidatorCopies`/`winnerTicketCopies` return independent copies. Immutable snapshot APIs
still expose only copied metadata and indexed records. Encoders inspect the actual private source
sequences, preserving complete-source alias checks rather than checking temporary sequence copies.

The nightly treated mutable/read-only sequence accessor overloads as ambiguous, so edits/copies
have distinct names. Concrete adapter branches replace procedure-symbol templates whose binding
is unsupported here. A guard-fixture local was renamed after collision with its imported module.
These changes use public language facilities; no compiler patch or private runtime hook is used.

All **20,144** existing independent requests pass: **1,358 fixed tickets**, **3,624 epochs**,
**3,009 winner markers**, **3,810 unsigned headers** and **8,343 full headers**. Another **8,246**
direct sealed-header inspections compare all copied fixed fields, full/signing extents, offender
counts and seal against independent logical fields. Total header corpus: **28,390 comparisons**.
Coverage retains all published tiny/full header and seal-free signing bytes, optional combinations,
validator-population changes, E1/E2/E4/count widths, illegal tags, huge configured epoch lengths,
truncations, byte budgets, duplicate/unsorted supplied sequence values, malformed fuzz, late errors,
source mutation and exact-prefix re-emission. Eight oracle example tests also pass.

The thirteenth positive suite preserves every fixed/descriptor/key/ticket/offender alias check,
default-owner rejection and full-versus-signing boundary. It adds independent source-copy checks,
parent replacement, orphaned signing/epoch/winner views and warmed ARC release coverage. After
100 warmups, 1,000 isolated retain/replace/copy/drop cycles leave public live occupancy unchanged:
**27,648 → 27,648 bytes** on this Mac, with outer fixtures live. This measures that workload, not
RSS or general leak freedom. Signing payloads still omit exactly the final 96-byte seal.

This increment adds **81 runtime misuse rejections** (60 failed/default result reads, 20 absent
source/metadata reads or edits and one invalid failure constructor) and **45 compilation
rejections** (40 private/read-only owner/result/variant checks and five nominal/owner-type checks).
Cumulative coverage is **301 runtime result/variant/constructor rejections and 190 compilation
rejections**, plus **13 positive suites**, seven family corpora and three runtime probes.
Verification remains local macOS ARM64 with checked ARC/Clang LTO. M1 migration remains partial;
Linux, state-dependent marker eligibility and cryptographic verification remain separate work.

## Twelfth increment: complete extrinsics and blocks

`block_codec.nim` now compiles on the same pristine nightly. Static schema parameters use
`static[ComponentKind]`; nullable private owners receive stable local non-null proofs. Parent
`FrameResult[T]` tags and both payload alternatives are private. Read-only `error` selects the
outcome, `value` requires success and `cause` requires `InvalidComponent`. Nested `ComponentFailure`
schema/reason fields are private; `kind` is read-only and each child-reason accessor requires its
matching schema. Default/failed operations cannot expose values, owners or consumed offsets.

The nightly rejected generic parameter tags in variant constructors even inside the selected
compile-time branch. Literal schema tags preserve exactly those branches and their typed reasons.
The adapter uses concrete schema captures and re-emission calls, explicit initialization and
public fixture I/O/parsing modules. Writable alias probes use fixed array views over real backing
allocations, including preserved spare capacity for private-wire aliases. No compiler/runtime
patch, unchecked variant read or alternate protocol representation is used.

All **17,194** existing independent complete extrinsic/block requests pass, alongside seven oracle
known-answer tests. They preserve all published original bytes and their existing typed structural
policy rejections, plus independently authored valid counterparts. Encoder sources remain separate
from parent decoding. Observations compare every child count and exact wire after caller-input
erasure, exercise on-demand family APIs, and check truncation/fuzz, remaining byte budgets,
stricter recapture policies, exact/short/spare output capacity and late atomic failures.

Both native composition suites pass, preserving descriptor/private-wire cross-child alias checks,
copied-record independence, default-owner failures and profile-reinterpretation rejection. The new
release workload replaces a parent with a structurally different block, releases both parents and
the extrinsic handle, erases caller bytes, then materializes all six retained original child
families. After 100 warmups, 1,000 isolated cycles leave public live occupancy unchanged:
**48,816 → 48,816 bytes** with outer fixtures live. This is workload-specific live occupancy,
not RSS or a general leak-freedom claim.

This increment adds **85 runtime misuse rejections**: 52 failed/default parent-result reads,
three invalid cause reads and all 30 wrong selected-schema reason reads. It adds **28 compilation
rejections**: 25 private/read-only result/cause/owner checks and three component/parent type checks.
Cumulative totals are **386 runtime result/variant/constructor rejections, 218 compilation
rejections (190 privacy + 28 nominal), 15 positive native suites and eight family corpora**,
plus the three runtime language probes. All pass under local macOS ARM64 checked ARC/Clang LTO.
The block frame still does not establish state eligibility, commitment correctness or valid seals.

## Thirteenth increment: strict Booleans and packed bitstrings

`bitstrings.nim` now runs on the same pristine nightly. `BitResult[T]` hides its status and payload;
read-only `error` selects the outcome and `value` requires `None`. Defaults remain Uninitialized,
with no Boolean, metadata, owner or consumed/written progress. Private `OwnedBits` backing references
are explicitly nullable and retained in stable checked locals. The wire representation, policy
and error precedence are unchanged; no specialized assurance or dispute codec was replaced.

Both native bitstring suites pass. They retain empty versus default ownership, caller-buffer
mutation, stricter re-emission policy, indexed bounds, fixed-count mismatch, full-output atomicity,
spare suffixes and borrowed/private packed-wire alias rejection. Writable alias probes use fixed
array views over real allocations, including actual spare capacity. Source-owner replacement,
callee-local source escape, copied metadata/output independence and warmed ARC release checks
extend lifetime coverage. After 100 warmups, 1,000 isolated retain/replace/reframe/drop scopes return
public live allocator occupancy to baseline: **384 → 384 bytes**, with outer fixtures live. This
observes the measured workload, not RSS or a general leak-freedom property; exact counts are in the
evidence JSON.

All **11,274** unchanged independent requests pass, alongside six oracle known-answer tests.
Coverage exhausts all 256 Boolean octets and all final-byte patterns for lengths 1–8 under both
framings. It preserves logical bit order, zero padding, natural-width and packed-byte boundaries,
all small truncations, empty/exact/short/spare output, late padding rejection, strict bit limits,
maximum-uint64 count claims and 4,000 malformed-byte requests. Pinned tiny/full assurance bitfields
and distinct dispute Boolean fields remain checked after their JSON hash verification; no dedicated
published general-bitstring fixture family exists. Encoders receive independently authored logical
sequences; decoded observations compare every bit, count, consumed extent and both owner framings.

The original division/remainder ceiling calculation remains safe at the uint64 boundary; it never
forms `count+7`. Policy/available-byte proofs still precede host narrowing and snapshot allocation.
No arithmetic-exception emulation, compiler patch, private runtime API or fallback encoding is used.
Fixture adapters use the nightly's public parsing/I/O modules and explicit initialization. Former
FieldDefect catches become independent exact-contract subprocess checks.

This increment adds **30 runtime misuse rejections** across failed/default public operations and
**12 compilation rejections**: ten private/read-only owner/result checks and two nominal count/limit
checks. Cumulative totals are **416 runtime result/variant/constructor rejections, 230 compilation
rejections (200 privacy + 30 nominal), 17 positive native suites and nine family corpora**, plus
three runtime language probes. Verification remains local macOS ARM64 with checked ARC/Clang LTO.
M1 migration is still partial; Linux, M2 and M3 remain unverified.

## Fourteenth increment: canonical scalar sets and dictionaries

`collections.nim` now runs on the same pristine nightly. `CollectionResult[T]` keeps status/payload
private, with read-only outcomes and success-precondition application access. Nullable set/dictionary
references receive stable local non-null proofs. Supported elements remain value-only naturals,
E0–E8 unsigned scalars and fixed octets. Public generic APIs combine a scalar-operation concept with
a closed family gate; arbitrary mutable schemas cannot opt into collection ownership.

This was a harder compiler port than the preceding increments. Unconstrained generic bodies did
not resolve their scalar operations. Typedesc-parameter constructors triggered an internal
`isTrival` compiler error; explicit `CollectionUInt[W]`/`CollectionBytes[N]` names avoid it. Concept
matching across modules required visible implementing operations. Safe scalar readers, sizing,
comparison and atomic `encodeScalar` operations now provide that public interface; unchecked
cursor writers remain private and have an explicit negative compilation probe. Scalar encoding
copies its fixed value before writing, including shifted source/output overlap. Parent collection
encoders retain their stronger whole-source alias rejection and complete preflight. The checked
writer adds another field-level validation path; whether LTO eliminates that work has not been
measured. This increment establishes correctness coverage, not performance parity.

The explicit E0–E8 family registry rejects invalid collection schemas at compile time. Direct
scalar helper width contracts also reject constant-invalid calls during compilation, for example
`contract violated: 0 <= 9 and 9 <= 8`. These two probes are compilation rejections, not runtime
repair or guard measurements. No historical compiler-repair count is inferred from this run.
Concept default requirements are written explicitly so the existing `nimpretty` formatter can
parse them; there is no formatter bypass or alternate compiler source path.

The first adapter build exposed a standard-sequence division-by-zero warning for physically
zero-sized `CollectionBytes[0]`. A private `array[ord(size == 0), byte]` storage unit makes that
scalar physically nonzero, while adding no wire bytes. Positive-width scalar extents are unchanged.
The unit is inaccessible to callers and excluded from comparison/serialization. Zero-width sets
and dictionary key domains still admit only one distinct element. The final build has no such
warning; neither compiler nor standard-library sources are modified.

All **13,161** unchanged independent requests pass, alongside seven oracle known answers. They
retain every E0–E8 instantiation, natural/fixed-byte schemas, mixed dictionaries, numeric versus
wire-order inversions, strict duplicate/descending rejection, unordered associated values,
zero-width domains, huge count/host-bound claims, late source overflow, truncation, malformed fuzz,
item/byte budgets and exact/short/spare output. Published report fields supply only hash-checked
empty set/dictionary cross-checks; nonempty logical-order examples remain independently authored.

Both native suites preserve retained owners, copied value independence, stricter policy, defaults,
signed index errors and borrowed/private typed-storage aliases. Added coverage exercises callee-local
source escape, same-sized owner replacement, copied pairs, checked scalar failures and shifted
scalar overlap. After 100 warmups, 1,000 retain/replace/reframe/drop cycles return public live allocator
occupancy to baseline: **480 → 480 bytes**, including zero-width typed sequences, with outer fixtures
live. Exact counts are in the evidence JSON; this measures that workload rather than RSS or general
leak freedom.

This increment adds **50 runtime misuse rejections** and **22 compilation rejections**: 14 private/
read-only result/owner/storage/writer checks, three nominal count/schema/owner checks and five
unsupported-schema/static-width checks. Cumulative totals are **466 runtime result/variant/
constructor rejections, 252 compilation rejections (214 privacy + 33 nominal + five schema),
19 positive native suites and ten family corpora**, plus three runtime language probes. Verification
remains local macOS ARM64 with checked ARC/Clang LTO; M1 migration is partial and Linux/M2/M3 remain
unverified. These generic/storage adaptations are concrete compiler friction and should inform the
trial assessment; passing the earlier simpler slices alone did not establish generic maturity.

## Fifteenth increment: C.2 availability and accumulation records

`c2_records.nim` now runs on the same pristine nightly. `RecordResult[T]` hides status/payload and
requires success before values, retained owners or progress can be read. Operand ownership uses
private nullable backing references and stable checked locals. Copied result/source/metadata tags
are read-only; every selected work payload, output length and operand/transfer branch has its own
supported access precondition. Defaults preserve the existing success-empty source output and
operand source tag; default results and operand owners remain invalid/uninitialized.

`successfulOperandOutput` and `failedOperandOutput` construct source alternatives together with
their payload/tag; the failure constructor rejects Success. `editOperandPayload` explicitly edits
selected success sources and `operandPayloadCopies` returns independent bytes. `operandSource`
and `transferSource` construct the source union. Public source branch getters return copies;
decoded branch getters retain the immutable operand or copy fixed transfer fields. Encoders use
the actual private source descriptors/sequences internally, preserving complete-source alias
checks rather than checking temporary accessor copies. Metadata cannot fabricate an error-output
length or retag itself to access an inactive field.

No wire/resource policy changed. Availability remains a fixed 104-byte tuple; transfers remain
153 bytes with outer tag one, fixed 128-byte memo and E8 balance/gas. Operand outer tag zero and
gas use canonical naturals, followed by the existing work result and final trace; union encoding
adds no second tag. Child validation, aggregate subtraction, checked host extent growth, no-allocation
scan and whole-output preflight remain intact. Actual work errors remain valid decoded application
values whose output extraction returns NoPayload.

All **26,090** unchanged independent requests pass, alongside eight oracle known answers. Coverage
retains pinned tiny/full report availability prefixes, independently derived report-to-operand
fields, authored transfers, every work-result alternative, unsigned/natural gas/count boundaries,
shard/core domains, truncation/fuzz, invalid/overlong tags, huge blob claims, strict limits,
independent field/byte observations and exact/short/spare output. Derived operands are not claimed
as published standalone vectors, nor as valid state transitions or cryptographic verification.

Both native suites preserve caller mutation, fixed copies, stricter retained policy, defaults,
whole descriptor/cross-blob/private-wire aliases and unchanged failure output. Writable fixtures
use fixed views over real backing allocations. Added coverage proves copied source branches/
payloads cannot modify original sources, retains an operand after a callee-local union/source
expires, replaces same-sized owners and tests independent extracted bytes/metadata. After 100
warmups, 1,000 scoped release cycles, including all six work-error alternatives, return public live
occupancy to baseline: **2,272 → 2,272 bytes**, with outer fixtures live. Exact counts are in the
evidence JSON; this is workload-specific occupancy, not RSS or general leak freedom.

This increment adds **56 runtime misuse rejections**: 32 failed/default result reads, 18 selected
work-error payload/metadata accesses, five wrong source/decoded branch reads and one invalid failure
constructor. It adds **41 compilation rejections**: 38 private/read-only result/owner/variant checks
and three nominal balance/root/payload-hash checks. Cumulative totals are **522 runtime result/
variant/constructor rejections, 293 compilation rejections (252 privacy + 36 nominal + five schema),
21 positive native suites and eleven family corpora**, plus three runtime language probes.
Temporary-expression/default type queries in a few negative fixtures were replaced with named
locals/concrete RHS types so probes fail for their intended contract/member. No compiler patch,
private runtime API, fallback encoding or omitted existing corpus case is used. Formatting passes;
verification remains local macOS ARM64 with checked ARC/Clang LTO. M1 migration is still partial;
Linux and M2/M3 parity remain unverified.

## Sixteenth increment: raw cryptographic primitives

`src/crypto/primitives.nim` now runs on the same pristine nightly, through the existing maintained
C ABI and unchanged pinned BoringSSL/XKCP sources. `CryptoResult[T]` hides its discriminator and
payload behind a read-only error and success-precondition value getter. Hashes, keys and signatures
keep their distinct types. Default results remain Uninitialized; exact-width imports, empty raw
messages and backend acceptance behavior are unchanged. Clients supply the public bridge include
directory explicitly; generated C no longer depends on a source-relative header location.

Opaque seed handles use private nullable ARC references, stable checked locals and a typed object
destructor. Import copies caller bytes. Explicit clear invalidates all aliases; missing/cleared
seeds cannot stand in for an imported all-zero seed. A test-only observer wraps the project bridge
in a separate library, matching the original seed allocation's address. It sees nonzero fixture
bytes before the real wipe and zero bytes afterward, inside the wipe callback while storage is
still live. It retains no ARC owner and never reads freed memory. Dropping an intermediate alias
does not wipe; dropping the last owner does. Explicit/repeated clear and typed refusals from all
four fallible backend operations pass, followed by successful recovery. No compiler/runtime hook
or upstream patch is used. This verifies exercised seed storage, not all possible secret copies,
allocation-failure recovery or concurrent clear/sign behavior.

The preserved independent corpus passes **five RFC 8032 cases, 151 Wycheproof cases, 56 raw messages
for each hash**, exact-width/retained-input checks, the existing failed-result probe and **32
deterministic generated signing fixtures**. Blake2b is compared with Python hashlib; Keccak uses
the existing independent integer oracle. The four-worker test uses supported `RawThread` creation
and joins every started thread, including if later creation fails. Each worker owns its seed and
runs **128 rounds** of hashing, signing and verification; no ARC seed owner crosses threads.
Direct C pointer/length, unchanged-output and wipe checks pass too.

The exceptional-point probes retain the actual backend verdicts: identity A/R with S=0 is accepted
for empty/abc messages; tested all-zero A/R and S=group-order cases are rejected. The normative
JAM acceptance policy remains unresolved; passing this corpus does not settle it.

After 100 warmups, **1,000 scoped seed release cycles return live occupancy 192 → 192 bytes**.
This isolated allocator observation is not RSS or a general leak-freedom claim. The new guards add
**22 runtime misuse rejections** for default/failed hash, import, derivation and signature results,
including backend, missing-seed and cleared-seed failures. **13 compilation rejections** cover
11 private/read-only result/seed bypasses and two nominal hash/signature/key swaps.
Cumulative totals are **544 runtime result/variant/constructor rejections, 306 compilation
rejections (263 privacy + 38 nominal + five schema), 22 positive native suites and twelve family
corpora**, plus three language runtime probes. Formatting covers **509 Nim files**. The final
evidence records **429 matching source/test hashes**.
All results remain local macOS ARM64, checked ARC/Clang LTO. Production native sources and pins are
unchanged. This completes the raw primitive slice, not all M2 or M1 migration.

## Seventeenth increment: state keys and fixed node layout/hashing

`src/codec/state/layout.nim` now runs on the same pristine nightly. The scope remains Gray Paper
0.8.0 state-key functions C, branch/leaf encodings B/L and raw node identification from the
merklization chapter. No wire rule, native primitive, dependency pin or compiler source changes.
This adds no trie construction, state-component serialization, proof or persistence behavior.

`StateLayoutResult[T]` hides status/payload behind a read-only reason and success-precondition
value getter. Copied node metadata hides its discriminator and all seven alternative fields.
Read-only kind selection and field-specific contracts prevent inactive reads or retagging. The
three source factories (`branchNodeInfo`, `embeddedNodeInfo`, `hashedNodeInfo`) construct tags and
fixed copied fields together. They preserve the existing source-validation boundary:
`encodeStateNode` rejects an invalid partial commitment, embedded length or padding before
publishing any encoded node. Default metadata remains the existing all-zero branch; default
results remain Uninitialized.

All **12,233 unchanged independent requests** and **six literal oracle checks** pass. Coverage
retains all chapter octets, E4 service boundaries/interleaving, raw preimage limits, every node
header and embedded source-length octet, padding pollution, 32/33-byte leaf boundaries, hash
input boundaries, truncations, suffixes, malformed bytes, exact metadata re-emission and raw
Blake2b node hashes. Expected bytes/hashes come from the independent Python equations/hashlib,
not native round trips. Five legacy singleton roots retain their explicitly labelled projection
from historical 32-byte input keys to current 31-byte keys; they are not unmodified 0.8.0 vectors
or multi-entry trie evidence.

The native suite preserves destructive caller mutation, fixed independent copies and loss of
exactly the left child's high bit. Source/getter copies cannot rewrite original metadata.
Injected primitive refusals become BackendFailure for hashed service keys, long leaves and
node hashing. Explicit limits and canonicality precede hashing, short embedded values remain
usable without hashing, and normal hashing recovers after the test-only refusal is removed.
The production-linked corpus has no observer/fault symbols. All protocol loops operate within
fixed 31/32/64-byte extents or validated short lengths; borrowed input lengths are compared in
uint64 before hashing. No input-derived heap owner, retained pointer or new unchecked size
arithmetic is introduced.

This increment adds **32 runtime misuse rejections**: 18 default/failed result reads (including
consumed progress and three backend-failure paths) and 14 inactive metadata field reads, testing
both wrong alternatives for every field. It adds **29 compilation rejections**: 26 private/read-only
result/metadata checks and three nominal key/partial-commitment/value-hash versus full-node-hash
checks. Cumulative totals are **576 runtime result/variant/constructor rejections, 335 compilation
rejections (289 privacy + 41 nominal + five schema), 23 positive native suites and thirteen family
corpora**, plus three runtime language probes. Formatting covers **536 Nim files**; the final
evidence records **463 matching source/test hashes**. Verification remains local macOS ARM64, checked ARC/Clang LTO; full M1, broader M2, M3 and Linux parity remain
unverified. No compiler/private-runtime hooks, source patches or omitted corpus cases are used.

## Eighteenth increment: bounded state trie roots

`src/codec/state/trie.nim` now runs on the same pristine nightly, retaining Gray Paper 0.8.0
merklization equation M and the verified B/L encodings. Private sorted key/index scratch still
uses the supported standard-library sort. `StateTrieResult[T]` hides status/payload behind a
read-only reason and success-precondition getter, protecting both public commitments and private
recursive child hashes. Empty mappings remain zero roots with zero nodes; duplicate identities
are rejected, source order is preserved and every unary branch remains committed.

All **2,308 unchanged independent requests** and **six literal topology/boundary checks** pass.
The oracle partitions unsorted lists directly and uses hashlib, independently of the production
sorted ranges/binary search. Coverage includes every divergence bit 0..247 with zero/one shared
prefixes, permutations, exact/one-below topology budgets, empty/singleton maps, 32/33-byte values,
primitive block boundaries, all payload/entry policies, equal/unequal duplicates, random maps and
maps through 1,024 entries. Eleven frozen historical roots retain their labelled 32-to-31-byte
key projection, with no projected duplicates. They are compatibility checks, not unmodified
current-schema conformance or complete state serialization evidence.

The native tests preserve copied roots and destructive caller mutation. A separate observer-linked
suite verifies that entry, individual/aggregate payload, duplicate and topology failures occur
before any cryptographic work. Empty mappings also succeed without hashing while the test backend
is refusing. Immediate refusal and refusal after three successful primitive calls return only
BackendFailure; the latter occurs after a complete child hash exists. Recovery reproduces the
original root. The observer/fault symbols remain outside the production library/corpus adapter.

Arithmetic remains explicit: native scratch extents are checked before allocation, aggregate
lengths use remaining-budget subtraction, topology increments check ceilings first, and midpoint
arithmetic stays inside the sorted range. White-box project tests exercise used=high(uint64),
used=high(uint64)-1, empty children at exhausted budgets and the depth-248 defense without unsafe
sequence descriptors or private compiler/runtime hooks. Public LengthOverflow remains defended
but unexercised with ordinary small allocations; recoverable allocation exhaustion is not claimed.

After 100 warmups, **1,000 scoped cycles return live occupancy 2,048 → 2,048 bytes**, with the
16-entry long-value source retained outside each scope. Each cycle includes success, early and
late backend failures, recovery, exhausted topology and duplicate-key rejection. Source key order
and value bytes remain unchanged. This is workload-specific live allocator occupancy, not RSS
or a general leak-freedom claim.

This increment adds **26 runtime misuse rejections**: root/entry/node reads for default results,
four independent resource failures, duplicates and immediate/late backend failures, plus default/
failed private child-hash reads. It adds **eight compilation rejections**: six private/read-only
result checks and the existing root-as-node and bytes-as-node-budget nominal probes. Cumulative
totals are **602 runtime result/variant/constructor rejections, 343 compilation rejections
(295 privacy + 43 nominal + five schema), 25 positive native suites and fourteen family corpora**,
plus three runtime language probes. Formatting covers **544 Nim files**; the final evidence
records **477 matching source/test hashes**. Verification remains local macOS ARM64, checked ARC/Clang LTO; full M1, broader M2, M3 and Linux parity remain unverified.
Protocol/native dependency pins and pristine upstream/compiler sources are unchanged.

## Nineteenth increment: entropy, validator rosters and timeslot state

`src/codec/state/safrole.nim` now runs on the same pristine nightly. It preserves Gray Paper
0.8.0 T(state) chapters 6–9 and 11: four ordered fixed entropy words, staging/active/previous
variable validator rosters and the exact E4 most-recent timeslot. This is structural serialization,
not Safrole execution, key/point verification or a complete state root. Protocol/native dependency
pins and pristine upstream/compiler sources are unchanged.

`StateComponentResult[T]` hides status/payload behind a read-only reason and success-precondition
getter, covering fixed reads, entry payloads, sizes, retained rosters, copied records and consumed
progress. Roster handles use private nullable acyclic ARC references and stable checked locals.
The decoder proves the whole wire extent before allocating copied records; accessors reject missing
owners and check uint64 ordinals before native indexing. Source entry bytes remain caller-owned
mutable values; decoded roster storage stays private and immutable.

All **3,068 unchanged independent requests** and **six literal oracle checks** pass. Coverage
retains exact chapter keys/record fields, E4 endianness and entropy order, all proper fixed-prefix
truncations, every truncation of a six-record roster, larger record/prefix boundaries, natural
transitions, populations through 1,023 and beyond, invalid counts/configuration, complete-byte and
element limits, massive counts/native extent overflow, overlong/random input and unrelated suffixes.
Three five-entry trie integrations match the separate list-partition reference. Four pre/post
tiny/full state sources retain their frozen file hashes; their component encodings are derived
fixtures, not standalone published binary vectors or passed Safrole transitions.

Population validation still uses divisibility and count/3 versus cores, avoiding a configuration
multiplication. Native wire/typed extents are checked before count narrowing and multiplication;
byte policy includes the count prefix. The maximum uint64 population has valid divisibility but
returns LengthOverflow before allocation. Exact size and prefix-scan checks remain 2,017 bytes
for six records. No wrapping exception emulation or unsafe sequence descriptor is introduced.

Native ownership tests retain a roster returned from a callee whose typed source, entry and wire
aliases have retired. Replacing one same-sized owner does not affect an alias; extracted record
mutation and destructive caller mutation cannot rewrite the snapshot. Fixed entropy/time values
remain independent copies. Generated-C inspection identified unchecked integer-to-enum conversion
in this nightly. `validatorEntry` now explicitly rejects chapter representations outside 7–9 with
InvalidTag before building an entry. All 256 underlying chapter-byte values are tested; allowed
chapters retain their exact namespace keys. This closes a typed-source validation gap without
changing any accepted roster encoding. After 100 warmups, **1,000 scoped cycles return live occupancy
6,368 → 6,368 bytes**, including replaced/retained owners, entry/fixed-value temporaries and
invalid owner/index/framing/count paths. This is workload-specific live allocator occupancy,
not RSS or a general leak-freedom claim. Allocation exhaustion keeps the existing fail-stop policy.

This increment adds **39 runtime misuse rejections**: 38 default/actual failure reads across fixed
values, entries, owners, records, sizes and progress, plus the original direct-time default probe.
Actual failures include InvalidConfig, InvalidCount, Truncated, NonCanonical, LimitExceeded,
LengthOverflow, InvalidOwner, InvalidIndex and InvalidTag. Chapter-4 tag/variant behavior
remains unported. **16 compilation rejections** cover 14 private/read-only result/owner
checks and the two original entropy/time and Ed25519/Bandersnatch domain probes. Cumulative totals
are **641 runtime result/variant/constructor rejections, 359 compilation rejections (309 privacy +
45 nominal + five schema), 26 positive native suites and fifteen family corpora**, plus three
runtime language probes. Formatting covers **558 Nim files**; the final evidence records
**498 matching source/test hashes**. Results remain local macOS ARM64,
checked ARC/Clang LTO; full M1, broader M2, M3 and Linux parity remain unverified.

## Twentieth increment: authorization pools and queues

`src/codec/state/authorization.nim` now runs on the same pristine nightly, preserving Gray Paper
0.8.0 T(state) chapters 1–2 and authorization composition. Core order, per-core hash order, duplicate
hashes, explicit empty pools, canonical pool counts and fixed 80-hash queues remain unchanged.
This is serialization, not authorization execution or a complete state commitment. No protocol
pin, primitive backend, dependency or compiler source change is involved.

`AuthorizationResult[T]` hides status/payload behind read-only reasons and success-precondition
getters. This protects public entries, snapshot reads, component kind, counts and copied hashes,
plus private count/prefix tuples. Snapshots use private nullable acyclic ARC storage and stable
checked locals. Both whole-component validation passes remain: all source rows before encoding
allocation and all input rows before descriptor/hash capture. Caller entry payloads remain mutable
owned bytes; captured nested rows stay private and immutable.

`AuthorizationKind` is explicitly validated before either public API selects a namespace or schema.
The nightly permits unchecked integer-to-enum conversion; invalid representations formerly could
select the queue path or bypass the row-cardinality clauses. All **256 underlying kind bytes** are
now tested against both APIs: Pools/Queues retain their own behavior and other representations
return InvalidTag. Accepted pool/queue bytes and existing error ordering for valid kinds do not
change. Default snapshots remain invalid owners rather than fabricated empty Pools.

All **7,059 unchanged independent requests** and **six literal oracle checks** pass. Coverage
retains all pool count pairs 0..9, exact/below aggregate budgets, late invalid rows, every proper
truncation of two full pools and two 80-hash queues, outer source counts, queue lengths 0/1/79/80/81,
malformed/overlong/huge counts, invalid/overflowing configurations, repeated/non-sorted hashes,
suffixes, random pools/malformed wire and two partial trie integrations. Four pre/post tiny/full
state sources retain their frozen Git blob identities/hashes; their component encodings remain
derived fixtures, not standalone published binaries or authorization STF passes.

Native tests retain callee-local pool/queue snapshots after source/entry/wire retirement, replace
same-sized owners while aliases survive, mutate extracted fixed hashes and check empty/high-index
failures. Private arithmetic probes charge a hash count up to high(uint64), reject the next hash
before addition, and check prefix/stride overflow at high(int) before addition/multiplication.
Huge descriptor/minimum-wire configurations reject before narrowing. No unsafe sequence descriptor,
private compiler/runtime hook or wrapping-exception emulation is used.

After 100 warmups, **1,000 scoped ownership/error cycles return live occupancy 192 → 192 bytes**,
including replaced/retained Pools, both full queue rows, nested caller storage and late malformed
row temporaries. This is workload-specific live allocator occupancy, not RSS or general leak
freedom. Allocation exhaustion retains the existing fail-stop policy.

This increment adds **44 runtime misuse rejections**: default/failed entry, owner, consumed cursor,
kind, core/row count, hash and private count/prefix reads. Actual failures cover invalid kind,
configuration, shape, framing, budgets, native extents, owners and ordinals. **15 compilation
rejections** cover 13 private/read-only result/owner checks and the original core-as-position and
bytes-as-hash-budget domain probes. Cumulative totals are **685 runtime result/variant/constructor
rejections, 374 compilation rejections (322 privacy + 47 nominal + five schema), 28 positive native
suites and sixteen family corpora**, plus three runtime language probes. Formatting covers
**572 Nim files**; the final evidence records **519 matching source/test hashes**. Results remain
local macOS ARM64, checked ARC/Clang LTO; full M1, broader M2,
M3 and Linux parity remain unverified.

## Twenty-first increment: chapter-4 Safrole basic state

`src/codec/state/consensus.nim` now runs on the same pristine nightly, preserving Gray Paper
0.8.0 T(state) chapter 4 and C.2 ticket fields: pending full validators, opaque 144-byte ring
commitment, tag-selected fixed sealer schedule and variable ticket accumulator. This remains
structural serialization, not Safrole execution, key/proof verification or a complete state root.
No protocol pin, primitive backend, dependency or compiler source change is involved.

Chapter operations now return `SafroleStateResult[T]`, with private status/payload, read-only
reason and success-precondition value. It reuses StateComponentError without reopening the roster
module's private result constructors. Pending-validator extraction explicitly converts selected
child successes or failure reasons. The wrapper also protects private no-allocation scan layouts
and accumulator count tuples. This is a chapter-local API type change; error vocabulary and
accepted wire bytes are unchanged.

`SealerSchedule` hides its discriminator and both arrays. `ticketSchedule` and `keySchedule`
construct only the selected alternative; kind is read-only. Source factories retain ordinary
source sequence references, which must remain stable during encoding. `tickets`/`keys` inspection
requires the selected branch and returns independent sequence copies; source editing can replace
the whole alternative using a constructor. Encoding/preflight uses actual private selected arrays,
so inspecting APIs do not introduce copying/allocation into whole-parent sizing. Raw wire tags
2..255 still return InvalidTag before schedule access. Default sources remain empty Tickets.

Parent snapshots use private nullable acyclic ARC references and stable checked locals. All late
schedule/count/payload checks still precede any child or parent allocation. Copied metadata and
fixed child values cannot retag or mutate the owner; inactive owner extraction returns WrongVariant.
The parent retains its immutable pending-roster child, while replacing/dropping one handle leaves
other owners intact. A white-box project test retains only the child after its callee-local parent
retires; the child still exposes all six original records.

All **7,298 unchanged independent requests** and **six literal oracle checks** pass. Coverage
retains both schedule modes, all proper representative truncations, every reserved tag and E1
attempt, 127/128 accumulator prefixes, late overlong/huge counts, exact/below byte limits, roster
and accumulator ceilings, fixed source cardinalities, zero/oversized epochs, repeated/arbitrary
ordered sequences, suffixes, random states and ten single-entry trie integrations. Eight frozen
published state sources remain hash-checked derived component fixtures, not standalone published
T binaries or passed Safrole transitions. Partial roots commit C(4) alone.

Private stride probes reach high(int) exactly, reject the next byte and a 33-byte record before
addition, accept zero growth at the ceiling, and reject a high(uint64) count before narrowing or
multiplication. No unsafe sequence descriptor, wrapping-exception emulation or private compiler/
runtime hook is used. After 100 warmups, **1,000 scoped cycles return live occupancy 192 → 192
bytes**, including both parent modes, replaced/retained parents, escaped roster children, copied
source arrays/metadata/records and late malformed parent temporaries. This is workload-specific
live allocator occupancy, not RSS or general leak freedom; allocation exhaustion remains fail-stop.

This increment adds **60 runtime misuse rejections**: 58 default/failed public/private result reads
and both inactive source-array accesses. Actual failures cover configuration, pending counts,
reserved tags, late accumulator framing/count/policy, whole-parent byte limits, host extents,
default owners, high indices and wrong owner variants. **24 compilation rejections** cover 22
private/read-only result/owner/source bypasses and the original BLS-as-ring and validator-as-slot
nominal probes. Cumulative totals are **745 runtime result/variant/constructor rejections, 398
compilation rejections (344 privacy + 49 nominal + five schema), 30 positive native suites and
seventeen family corpora**, plus three runtime language probes. Formatting covers **595 Nim files**;
the final evidence records **549 matching source/test hashes**. Results remain local macOS ARM64, checked ARC/Clang LTO; full M1, broader M2, M3 and Linux parity
remain unverified.

## Twenty-second bounded increment: branch Linux CI

The maintainer requested Linux CI before further codec ports. The separate
[CI workflow](../.github/workflows/ci.yml) targets pushes to `nimony`, PRs whose head
branch is `nimony`, and manual dispatch. The historical Nim 2 Linux job skips this branch/PR;
main-branch CI remains unchanged. This is trial infrastructure, not a completed compiler migration.

Two independent jobs expose progress without hiding remaining failures:

- The migrated runtime job runs formatting, CI safeguards and the full current `test_nimony.py`
  slice. Its summary reports actual suite, corpus and guard counts.
- The all-source gate discovers every `src/**/*.nim`, including newly added modules. Each gets an
  isolated semantic check and log. Any failure or timeout fails the job; there is no expected-failure
  allowlist. Semantic success alone does not establish native linking or runtime equivalence.

Both jobs retain summaries and scoped logs/reports even on failure. No binaries, compiler caches,
vendor trees or generated keys are uploaded. The overall workflow can remain red while the
migrated runtime job passes; this makes the unfinished port visible in the PR.

[Linux toolchain pins](../spec/toolchain.json) select Ubuntu 24.04 x86_64, Python 3.12
and official Nimony 0.6.3 nightly `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410` (2026-10-15).
The `linux_amd64` archive SHA-256 is
`39f3493ad68418a38da0fc7c8e048ef67b2a96b60c7e6a97246f6ec595ee19c9`, verified against the
[official release](https://github.com/nim-lang/nimony-website/releases/tag/nightly-0.6.3-5b51edfed).
Setup verifies the archive digest and nightly commit/date/platform before execution. Clang/lld
provide the checked ARC/LTO native profile. Formatting reuses the existing pinned Nim 2.2.12
archive solely for `nimpretty`: only its formatter is exposed on PATH, not a second Nim compiler.
Dependency sources stay pristine and existing gitlinks are unchanged.

Local verification on macOS ARM64:

- Nine CI safeguard tests pass: archive checksum, extraction boundaries, compiler identity,
  complete module discovery, timeout/failure handling and truthful summaries.
- Official actionlint 1.7.12 accepts both workflows; formatting passes for 595 Nim files.
- Both actual Linux tool archives pass checksum verification and safe extraction. Their Linux
  executables were not run on macOS; this is installer verification, not Linux runtime evidence.
- The real all-source semantic audit reports **24/43 passing modules**, with all 19 failures
  retained and a failing exit status. These are macOS compilation observations, not Linux results
  or additional intentional rejection tests. Evidence: `build/nimony-ci/modules/results.json`.
- Production source and existing functional test files are unchanged. The prior functional
  report's 549 source/test hashes still match. Totals remain **30 native suites, seventeen corpora,
  745 runtime misuse rejections and 398 compilation rejections**. No new functional runtime or
  Linux pass is claimed for this infrastructure increment.

Reproduce the CI safeguards with `python3 tests/test_nimony_ci.py`. Run the independent module gate
with `python3 tools/audit_nimony_modules.py --compiler /absolute/path/to/nimony`; it writes every
command, source hash and verdict under `build/nimony-ci/modules/`. The workflow records Linux
compiler/environment metadata and uses `tools/setup_nimony.py` for verified installation.
Full Linux runtime evidence still awaits CI execution after publishing these changes.

## Twenty-third bounded increment: chapter-5 dispute judgment/offender state

`src/codec/state/disputes.nim` now targets the same pristine Nimony nightly. Gray Paper 0.8.0
T(state) chapter 5 retains four independently canonical sorted sets, canonical general-natural
counts and nominally separate report hashes and offender keys. There is no source sorting,
deduplication, alternate wire format, dispute transition or cryptographic validation added here.
No protocol/dependency pin, compiler source or native primitive backend changes.

`DisputeStateResult[T]` now hides its discriminator/payload behind read-only `error` and
success-precondition `value` accessors. This protects the private no-allocation scan layout too;
failed/default results cannot authorize entries, owners, copied counts/identities or consumed
progress. Nullable acyclic snapshot storage is bound to a checked stable local before access.
Default owners, huge indices and forged judgment enum tags return typed errors; `InvalidTag`
is appended to the error vocabulary for invalid source API tags, with no new wire tag.

Whole-source and whole-parent checks still precede allocations, including final offender ordering.
Independent immutable capture survives callee return, destructive wire/source mutation, retained
aliases and handle replacement. Editing copied metadata or fixed identities cannot alter its
owner. Direct private arithmetic probes reach `high(int)` exactly, reject the next count prefix
and a 33-byte extent before addition, allow zero growth at the ceiling, and reject `high(uint64)`
counts by aggregate or host extent checks before narrowing/multiplication. They do not construct
fake sequence descriptors or depend on overflow exceptions.

All **2,766 unchanged independent corpus requests** and **six literal reference checks** pass.
These retain all four sorted sets, duplicate/descending source and wire rejection, differences in
every identity octet, proper truncations, late offender failures, huge/overlong counts, 127/128 and
255/256 boundaries, policy ceilings, suffixes and randomized cases. Twelve hash-checked published
pre/post state sources remain derived component fixtures; twelve singleton trie integrations
commit C(5) alone, not complete state roots or successful dispute transitions.

After 100 warmups, **1,000 scoped cycles return live occupancy 192 → 192 bytes**, including
escaped/replaced/retained owners, copied metadata/identities, empty states and late malformed
parent temporaries. A duplicate final offender also rejects without increasing live occupancy.
This is workload-specific allocator evidence, not RSS or general leak freedom; OOM remains
fail-stop. No compiler/runtime hook or dependency patch is used.

This slice adds **32 runtime misuse rejections** (sixteen actual failure/default payload pairs)
and **13 compilation rejections** (eleven private/read-only result or owner bypasses and the two
original report-as-offender/byte-budget-as-ordinal probes). Cumulative totals are **777 runtime
misuse rejections, 411 compilation rejections (355 privacy + 51 nominal + five schema), 32 positive
native suites and eighteen independent corpora**, plus the three separate language probes.
Formatting covers **607 Nim files**. Functional evidence records **568 source/test hashes** in
`build/nimony-trial/verification/results.json`.

Nimony diagnostics rejected same-container read/write expressions in two new test statements as
`mutable argument aliases with immutable parameter`. Explicit local reads before writes retained
the intended test operations. This is an observed compiler diagnostic, not a measured defect-rate
comparison or a claim that it proves alias safety across the implementation.

Results remain local macOS ARM64 with checked ARC/Clang LTO. The branch Linux workflow picks up the
new suites, corpus and guards automatically. The local all-source compilation gate advances from
24/43 to **25/43 passing modules**; its remaining failures stay visible. Actual Linux results and
full M1/M2/M3 parity remain unverified; compile-only success does not replace runtime gates.

## Twenty-fourth bounded increment: chapter-3 recent history

`src/codec/state/history.nim` now targets the same pristine Nimony nightly, preserving Gray Paper
0.8.0 T(state) chapter 3. Ordered recent blocks retain header/super-peak/state/E4-slot order,
independently canonical package/segment dictionaries and ordered optional belt peaks. No
history/MMR transition, commitment verification, source normalization or new wire format is added.
Protocol pins, upstream sources and native primitive backends are unchanged.

`HistoryResult[T]` hides its discriminator/payload behind read-only reasons and success-only
accessors, including private count tuples and stack scan layouts. Nullable acyclic owner storage
uses checked stable locals. Parent/cardinality/block metadata and package/segment pairs are
independent fixed copies; extraction remains bound to the original history/block indices.
Whole-source and whole-parent preflight still precedes any output/retained array allocation,
including the final optional peak's tag and payload.

`HistoryPeak` now hides its discriminator and hash storage. `absentHistoryPeak()` and
`presentHistoryPeak(hash)` construct the alternatives; read-only `present` preserves default
absence, and `hash` requires presence. A present all-zero hash remains distinct from absence.
Source editing replaces the whole value; callers cannot retag it or write through either getter.
Returned copied peaks retain the same contracts, without exporting owner storage.

All **1,985 unchanged independent requests** and **six literal reference checks** pass. Coverage
retains T field order, E4 endianness, package/segment association, sorted/duplicate/descending
keys, every proper representative truncation, reserved optional tags, history 0/1/7/8/9 counts,
127/128 and 255/256 framing, large dictionaries/belts, resource/host limits, suffixes and random
sources/malformed inputs. Eight hash-checked phase/profile sources are derived from four published
JSON blobs, with identical tiny/full contents at this pin; they are not eight unique states or
standalone published T binaries. Nine singleton trie integrations commit C(3) alone, not full
state validity or successful history transitions.

After 100 warmups, **1,000 scoped cycles return live occupancy 192 → 192 bytes**. The workload
covers escaped/replaced/retained parents, nested dictionaries, copied metadata/pairs/peaks,
empty states and late malformed tag temporaries. A reserved final tag rejects without increasing
live occupancy. Direct arithmetic checks reach `high(int)` exactly, reject the next byte and a
33-byte extent before addition, permit zero growth at the ceiling, and reject `high(uint64)` pair
claims before native multiplication/narrowing or aggregate addition. No fake descriptors,
overflow-exception emulation or compiler/runtime hooks are used. Occupancy is workload-specific,
not RSS or general leak freedom; allocation exhaustion remains fail-stop.

This slice adds **63 runtime misuse rejections**: thirty actual-failure/default result pairs and
three dynamically selected absent-hash reads (default, source and decoded). **22 compilation
rejections** cover nineteen private/read-only result/owner/peak probes, the two original nominal
substitutions and one statically proven absent-hash contract violation. Nimony rejected the known
absence before execution with `Error: contract violated: peak.isPresent`; this remains a separate
compilation test. Runtime and static contract checks are counted separately in the runner and CI
summary. The constructor diagnostic for segment-as-package abbreviates both static `ReportHash`
domains; the source-hashed negative probe still tests that exact rejected substitution.

Cumulative totals are **840 runtime misuse rejections, 433 compilation rejections (374 privacy +
53 nominal + five schema + one static contract), 34 positive native suites and nineteen family
corpora**, plus the three separate language probes. Formatting covers **628 Nim files**; the
functional report records **596 matching source/test hashes**. The nine CI reporting/installer
safeguards also pass, including exclusion of static contracts from runtime counts.

Results remain local macOS ARM64, checked ARC/Clang LTO. The branch Linux workflow automatically
runs the expanded migrated slice and strict all-source compilation gate. The local module audit
advances from 25/43 to **26/43 passing modules**, with every remaining failure retained. Actual
Linux execution and full M1/M2/M3 parity remain separate gates. The next slice is chapter-10
availability state.

## Linux CI repair: capture the compiler version stream

The first PR setup run failed before compilation despite displaying `0.6.3 [linux; amd64]`.
Nimony writes its version banner to stderr, while the installer captured stdout alone. The same
behavior was reproduced with the pinned macOS binary: stdout was empty and stderr contained the
correct version. The installer now captures both streams before checking the exact version prefix;
wrong/empty versions and nonzero command exits still fail before PATH/environment export. Archive
SHA-256, nightly commit/date/platform checks and all toolchain pins remain unchanged.

The all-source audit captures both streams too, so its compiler metadata records the actual banner.
Ten CI safeguard tests pass, including real Python child processes exercising stdout and stderr
banners, a near-matching wrong version, empty output and a nonzero exit. The exact pinned native
Nimony binary also passes the repaired check. This is a local installer/metadata fix; confirmation
of Linux setup and subsequent runtime checks requires the next CI run.

No codec/runtime behavior changed and all 596 prior functional source/test hashes still match.
The cumulative 34-suite, nineteen-corpus, 840-runtime/433-compilation rejection evidence remains
unchanged; CI safeguard tests are separate. Chapter-10 availability remains the next codec slice.

## Twenty-fifth bounded increment: chapter-10 availability state

`src/codec/state/availability.nim` now runs on the same pristine Nimony nightly, preserving Gray
Paper 0.8.0 T(state) chapter 10: a fixed per-core sequence of optional full standalone guarantees,
each followed by its distinct E4 registration time. Shared guarantee/report framing, credential
policy and error precedence remain unchanged. This does not verify signatures, availability
transitions, eligibility or contextual report-core/outer-position agreement. Protocol/dependency
pins, upstream sources and maintained native bridges are unchanged.

`AvailabilityResult[T]` now has private status/payload, read-only reasons and success-only value
contracts, including the private fixed stack scan layout. Nullable acyclic parent storage is
checked through stable local references. `AvailabilityAssignment` hides its discriminator, child
and registration fields behind `absentAssignment()` / `presentAssignment(guarantee, registered)`
constructors and read-only `present`, `guarantee` and `registered` accessors. Selected child fields
require presence; default absence cannot expose a fabricated report or timestamp. These factories
select source alternatives; encoding still validates the full guarantee content.

Copied assignment/guarantee metadata and credentials are independent fixed values. Their opaque
report handle retains immutable report bytes after caller sources and parent scopes retire.
Editing source or extracted alternatives replaces the whole assignment; editing a copied child
cannot alter a sibling owner. Whole-parent/source validation still precedes retained/output and
child scratch allocation, including final malformed tags, child credentials and registration bytes.

All **2,949 unchanged independent requests** and **six literal reference checks** pass, retaining
fixed tiny/full core shapes, every reserved optional tag, proper representative truncations,
full child/report/credential observations, E4 boundaries, exact/below byte/item ceilings, malformed
late children, canonical framing, suffixes, random assignments and four singleton trie roots.
Twelve hash-checked published phase/profile observations remain explicitly derived JSON fixtures.
Eight decode successfully; four retain the expected report-policy `LimitExceeded` rejection and
corresponding invalid source reports. Neither erasure shards nor credentials are repaired to
force acceptance. These are component/partial-root observations, not passed STFs or full state roots.

After 100 warmups, **1,000 scoped cycles return live occupancy 592 → 592 bytes**, with the stable
independent report fixture included in the baseline. The workload covers escaped/replaced parents,
copied assignments and credentials, retained report children after parent retirement, byte-for-byte
child replay, empty state and late malformed parent temporaries. A reserved final tag rejects
without increasing live occupancy. Direct arithmetic probes reach `high(int)` exactly, reject the
next byte and a four-byte timestamp before addition, allow zero growth at the ceiling and retain
explicit byte policy. No fabricated descriptors, overflow-exception emulation, synchronization
bypass or compiler/runtime hook is used. Occupancy is workload-specific, not RSS/general leak
freedom; allocation exhaustion remains fail-stop.

This increment adds **52 runtime misuse rejections**: twenty-three actual/default result pairs
and six default/source/decoded absent-field reads. **22 compilation rejections** cover eighteen
private/read-only result/owner/assignment probes, two nominal time/index substitutions and two
statically proven absent-child/timestamp contract violations. The original registration-time
nominal probe now calls the closed source factory, preserving its rejected GuaranteeSlot versus
AssignmentSlot substitution. Nimony also rejected mutable global fixture reads in test helpers;
passing fixture bytes explicitly retained the tests without suppressing its access checks.

Cumulative totals are **892 runtime misuse rejections, 455 compilation rejections (392 privacy +
55 nominal + five schema + three static contracts), 36 positive native suites and twenty family
corpora**, plus three separate language probes. Formatting covers **649 Nim files**; the functional
report records **624 matching source/test hashes**. Existing report/guarantee and block regressions
remain in the same full runner. The local all-source semantic audit advances from 26/43 to
**27/43 passing modules**, retaining every remaining failure. Results are local macOS ARM64, checked
ARC/Clang LTO; actual Linux execution and full M1/M2/M3 migration remain separate gates.

## Twenty-sixth bounded increment: chapter-12 privileged services

`src/codec/state/privileges.nim` now targets the same pristine Nimony nightly, preserving Gray
Paper 0.8.0 T(state) chapter 12. Fixed E4 manager/assigner/delegator/registrar roles precede one
canonical natural dictionary count and fixed E4-service/E8-gas pairs. Keys remain strictly
increasing numerically, including cases such as 255/256 whose little-endian byte order differs.
The full unsigned gas range is retained. No sorting, deduplication, compact-pair fallback, service
eligibility checks or privilege transitions are added. Protocol/dependency pins and upstream
compiler/library sources are unchanged.

`PrivilegeResult[T]` now hides its discriminator/payload behind read-only reasons and a checked
success-only value accessor, including the private natural reader and no-allocation scan layout.
Nullable acyclic owner storage is checked through stable retained locals. Whole-source/parent
shape, count, order and byte checks still precede output/retained array allocation, including late
key/gas failures. Metadata, assigners and service/gas pairs are independent fixed copies; replacing
handles or editing source/wire/extracted values cannot alter a retained sibling owner.

All **1,390 unchanged independent requests** and **seven literal reference checks** pass, retaining
fixed E4/E8 padding and field order, full numeric service/gas domains, no-count core assigners,
count boundaries through 1,024, supported/invalid core profiles, exact/below byte/item policies,
duplicate/descending numeric keys, representative proper truncations, malformed/overlong/huge
counts, legacy compact-pair probes, suffixes, random source/input mutations and 24 singleton trie
integrations. Sixteen derived phase/profile sources from eight hash-checked published JSON blobs
remain unchanged. These are component fixtures and C(12)-only roots, not standalone published T
binaries, passed STFs or complete state roots.

After 100 warmups, **1,000 scoped cycles return live occupancy 192 → 192 bytes**, covering
escaped/replaced/retained parents, scalar metadata and pair copies, empty dictionaries and late
malformed parent temporaries. A duplicate final key rejects without increasing live occupancy.
Direct arithmetic probes reach `high(int)` exactly, reject the next byte and an E8 extent before
addition, allow zero growth at the ceiling, accept the largest representable typed-array count and
reject its successor or `high(uint64)` without allocation. Caller item policy still precedes native
extent failure. No fake descriptors, overflow exceptions or private compiler/runtime hooks are
used. Live occupancy is workload-specific, not RSS/general leak freedom; OOM remains fail-stop.

This increment adds **50 runtime misuse rejections** (twenty-five actual/default result pairs)
and **14 compilation rejections** (twelve private/read-only result/owner probes and the original
gas-as-service and dictionary-index-as-core substitutions). The existing nominal probes retain
precise compiler type/argument diagnostics. Cumulative totals are **942 runtime misuse rejections,
469 compilation rejections (404 privacy + 57 nominal + five schema + three static contracts),
38 positive native suites and twenty-one family corpora**, plus three separate language probes.
Formatting covers **662 Nim files**; the functional report records **644 matching source/test
hashes**. No historical compiler-repair measurements are inferred from these safety-test totals.

The branch Linux workflow automatically uses the expanded runner and all-source compilation gate.
The local semantic module audit advances from 27/43 to **28/43 passing**, with every remaining
failure retained. Results remain local macOS ARM64, checked ARC/Clang LTO. Actual Linux execution
and full M1/M2/M3 runtime parity remain separate migration gates. Chapter-13 activity statistics is the next slice;
the accepted compact C13 gas policy and parked request-namespace question remain unchanged.

## Twenty-seventh bounded increment: chapter-13 activity statistics

`src/codec/state/statistics.nim` now targets the same pristine Nimony nightly, preserving Gray
Paper 0.8.0 T(state) chapter 13 and the maintainer's accepted compact gas policy. Separate current
and previous validator populations retain their natural counts and six E4 counters per record.
Core tuples retain eight natural fields without an array count; the numeric service dictionary
retains E4 IDs and eleven natural fields, including the two gas positions. Full uint32 counters
and uint64 natural/gas values remain supported. No alternative gas encoding, source normalization,
statistics updates, epoch rotation or protocol/dependency change is introduced.

`ActivityResult[T]` hides its discriminator/payload behind read-only reasons and success-only
accessors, including internal natural/key reads, eight/eleven-field tuples and stack scan layouts.
Nullable acyclic owner storage is checked through stable retained locals. A forged epoch selector
returns appended `InvalidTag` before retained roster indexing; no wire tag is added. Metadata and
all validator/core/service records remain independent fixed copies. Whole-source/parent preflight
still precedes output/retained allocation, including the last accumulation-gas scalar.

The compiler port uses supported ordinal-range iteration in declaration order, explicit fixed
array initialization and `static[int]` tuple parameters. Initial targeted builds rejected the older
`static int` spelling; changing the syntax allowed both adapter/selftest builds to succeed. This
is observed migration syntax friction, not a protocol defect or an upstream compiler patch.

All **2,615 unchanged independent requests** and **seven literal reference checks** pass. Coverage
retains every representative proper truncation, all tuple field positions and natural width
boundaries, E4 counter/service boundaries, numeric dictionary order, independent resized roster
populations, core/profile shapes, exact/below item/byte policy, late malformed/overlong/huge
scalars, suffixes, random input/source mutations and thirteen singleton trie integrations.

Eight hash-checked published validator-pair observations retain their exact partial fields;
zero core tuples and empty services are explicit authored completion, not published full-state
values. Six exact pre/post C(13) trace entries decode and reproduce their complete original bytes,
with per-entry consumed/trailing counts and SHA-256 retained. Sixteen later raw statistics values
remain in the same corpus. Compact gas known answers at all three gas positions remain checked.
The width-reference source is now hashed alongside the corpus/adapter. These are component and
partial-root observations, not executed STFs or complete-state validity claims. The accepted
compact interpretation and parked request-namespace question are unchanged.

After 100 warmups, **1,000 scoped cycles return live occupancy 192 → 192 bytes**, covering
escaped/replaced/retained parents, resized epochs, copied metadata and all three record families,
empty service dictionaries and late malformed accumulation gas. An overlong final scalar rejects
without increasing live occupancy. Direct arithmetic checks reach `high(int)` exactly, reject
the next byte and an E4 extent before addition, permit zero growth at the ceiling, and reject
unrepresentable typed service counts before allocation/narrowing. Caller item policy retains its
precedence. No fake descriptors, overflow-exception emulation or private runtime hooks are used.
Occupancy is workload-specific, not RSS/general leak freedom; OOM remains fail-stop.

This increment adds **62 runtime misuse rejections** (thirty-one actual/default result pairs)
and **18 compilation rejections** (sixteen private/read-only result/owner probes and the original
gas-as-counter and service-index-as-core substitutions). Cumulative totals are **1,004 runtime
misuse rejections, 487 compilation rejections (420 privacy + 59 nominal + five schema + three
static contracts), 40 positive native suites and twenty-two family corpora**, plus three separate
language probes. Formatting covers **679 Nim files**; the functional report records **669 matching
source/test hashes**. These safety counts are separate from compiler-repair measurements.

The local all-source semantic audit advances from 28/43 to **29/43 passing modules**, with every
remaining failure retained. The branch Linux workflow uses the expanded runner automatically.
Results remain local macOS ARM64, checked ARC/Clang LTO. Actual Linux execution and full M1/M2/M3
runtime parity remain separate gates. Chapters 14/15 work queues are the next bounded family.

## Twenty-eighth bounded increment: chapters 14/15 work queues

`src/codec/state/workqueues.nim` now targets the same pristine pinned Nimony nightly. Gray Paper
0.8.0 T(state) chapters 14/15 retain their fixed epoch rings, ordered ready-report rows, complete
C.2 child reports, canonical dependency sets and canonical accumulated package sets. Report
sequence order and repeated report identities remain significant; hash sets remain strictly
lexicographic and unique within each set. There is no extra outer count, report prefix, sorting
fallback, accumulation execution or protocol/dependency change.

`WorkQueueResult[T]` hides status and payload behind read-only reasons and a success precondition,
including private natural-count/layout proofs. Explicit nullable acyclic ring storage is checked
through stable retained locals. Ready/accumulated owners and slot/item/hash ordinals remain separate
nominal domains. Fixed metadata/hashes are independent copies; extracted report handles retain
their child after parent release. Complete preflight still precedes retained allocation, including
late report/dependency failures. Native descriptor extents, aggregate metadata and fixed payload
sizes retain explicit division/subtraction checks before arithmetic, narrowing or allocation.

The port uses explicit initialization, supported nullable references, explicit byte appends and
nonthrowing integer/hex parsing in the trusted test driver. No compiler or runtime patches were
needed. One supplementary ordering test initially exceeded its aggregate item budget; its earlier
row is now empty so the intended late `NonCanonical` failure is reached without changing production
error precedence. This test-fixture correction is separate from compiler-repair measurements.

All **2,904 unchanged independent requests** and **six literal reference checks** pass. Coverage
includes truncations, count boundaries, late failures, all hash-order octets, row/aggregate/child
budgets, ring positions, repeated report identities, deterministic mutations and **48 partial
component trie roots**. The corpus retains **24 JSON-derived component observations** from pinned
accumulation STF sources and **12 exact raw trace components**, all fully consumed and re-emitted
unchanged. JSON-derived sorted mathematical sets and raw trace bytes remain distinct evidence;
selected raw ready rings are empty, with nonempty ready coverage supplied by the JSON sources.
The isolated retain/replace/drop workload returns public live occupancy from **592 to 592 bytes**
after **1,000 warmed cycles**, including escaped report children and late-failure preflight. This
is a scoped allocator observation, not an RSS or general leak-freedom claim.

This increment adds **86 runtime misuse rejections** (forty-three actual/default result pairs)
and **19 compilation rejections** (sixteen private/read-only result/owner probes and three nominal
owner/index substitutions). Cumulative totals are **1,090 runtime misuse rejections, 506 compilation
rejections (436 privacy + 62 nominal + five schema + three static contracts), 42 positive native
suites and twenty-three family corpora**, plus three separate language probes. Formatting covers
**695 Nim files**; the functional report records **694 matching source/test hashes**. These safety
counts are separate from compiler-repair measurements.

The local all-source semantic audit advances from 29/43 to **30/43 passing modules**, retaining all
thirteen remaining failures. Branch Linux CI uses the expanded runner automatically. Verification
here is macOS ARM64, checked ARC/Clang LTO. Actual Linux execution and full M1/M2/M3 runtime parity
remain separate gates. Chapter-16 last accumulation outputs is the next bounded family.

## Twenty-ninth bounded increment: chapter-16 last accumulation outputs

`src/codec/state/outputs.nim` now targets the same pristine pinned Nimony 0.6.3 nightly. Gray
Paper 0.8.0 T(state) chapter 16 retains one canonical natural pair count followed by fixed E4
service IDs and opaque 32-byte commitments. Source order, descending/repeated service IDs and
repeated pairs remain unchanged. No sorting, deduplication, output commitment verification or
accumulation execution is introduced; protocol and dependency pins remain unchanged.

`OutputLogResult[T]` now hides status/payload behind read-only reasons and a success precondition,
covering public entries/reads/counts/pairs and private native extent proofs. Owner storage is
explicitly nullable and checked through stable retained locals. Whole-parent count/extent preflight
still precedes allocation, including the final commitment byte. Division/subtraction checks prove
wire and typed-record extents before multiplication, addition and narrowing. Extracted pairs are
independent fixed values; no mutable owner arrays or detached coordinates are public.

The port uses explicit fixed-array initialization and supported nullable references. The trusted
test driver uses explicit initialization and nonthrowing complete-token integer/hex parsing.
The existing native selftest and driver both passed their first targeted checked-LTO builds;
new private-lifetime and isolated-result binaries also compiled on their first targeted builds.
These are observed builds for this increment, not invented historical compiler-repair totals.
No compiler patches or private-runtime hooks were needed.

All **1,901 unchanged independent requests** and **six literal reference checks** pass. Coverage
includes every representative proper truncation, every commitment octet, E4 service boundaries,
canonical count boundaries, sequence order/repetition, exact/one-below limits, hostile native count
announcements, deterministic mutations and **21 partial component trie roots**. Eight pinned raw
pre/post trace entries consume completely and re-emit unchanged. All eight are empty logs;
nonempty field/order/policy coverage is authored, not claimed as published nonempty conformance.
The isolated retain/replace/drop workload returns public live occupancy from **192 to 192 bytes**
after **1,000 warmed cycles**, including detached fixed pairs and late malformed parents. This
is a scoped allocator observation, not an RSS or general leak-freedom claim.

This increment adds **32 runtime misuse rejections** (sixteen actual/default result pairs) and
**12 compilation rejections** (ten private/read-only result/owner probes plus root-as-commitment
and service-as-sequence-index substitutions). Cumulative totals are **1,122 runtime misuse
rejections, 518 compilation rejections (446 privacy + 64 nominal + five schema + three static
contracts), 44 positive native suites and twenty-four family corpora**, plus three separate language
probes. Formatting covers **706 Nim files**; the functional report records **712 matching source/test
hashes**. These safety counts are separate from compiler-repair measurements.

The local all-source semantic audit advances from 30/43 to **31/43 passing modules**, retaining
the twelve remaining failures. Branch Linux CI automatically uses the expanded runner. Results
here remain local macOS ARM64, checked ARC/Clang LTO; actual Linux execution and full M1/M2/M3
runtime parity are separate gates. Chapters 1–16 now have their existing typed serializers ported,
but service-keyed state and whole-state composition remain. Next is C(255, service) account metadata.

## Thirtieth bounded increment: C(255, service) account metadata

`src/codec/state/accounts.nim` now targets the same pristine pinned Nimony 0.6.3 nightly. Gray
Paper 0.8.0 T's C(255, service) mapping retains the interleaved service key and exact 89-byte
version-zero value: one canonical zero discriminator, a fixed code hash, five E8 fields and four
E4 fields. Balance, gas, storage, timeslot and service domains remain nominally distinct, with
full unsigned field ranges preserved. No variable-width fallback, account eligibility/deposit
validation, nested service maps, transition execution or protocol/dependency change is introduced.

`ServiceMetadataResult[T]` now hides status/payload behind read-only reasons and a success
precondition. Complete fixed metadata and its consumed extent remain independent values: no
heap-backed snapshot or owner relation is needed. Encoded entry bytes remain caller-owned fresh
storage. The existing fixed-budget, canonical version, supported version and complete-payload
failure precedence is unchanged. Even the last parent-service byte must exist before field copies.
Fixed offsets introduce no input-derived size arithmetic or advertised-size allocation.

The port explicitly initializes byte arrays and scalar read accumulators. The trusted driver uses
nonthrowing complete-token integer/hex parsing. Initial targeted selftest and driver builds both
rejected `uint64(maxBytes) < ServiceMetadataBytes`: the compiler reported expected uint64 but got
int64 for the named fixed-size constant. **One observed source repair cycle** made the comparison
explicitly unsigned at both call sites; both builds then passed. This is compiler/type-inference
migration friction, not a discovered wire-format defect. Initial diagnostics remain in ignored
`build/nimony-trial/verification/{test_state_accounts,state_accounts_driver}-initial-build.log`.
The new private-copy and isolated-result binaries passed their first targeted builds. No upstream
patches or private runtime hooks were needed; no historical repair counts are inferred.

All **1,794 unchanged independent requests** and **six literal reference checks** pass. Coverage
includes every proper record truncation, every code-hash octet, each E8/E4 field across unsigned
boundaries, service key boundaries, fixed byte budgets, canonical/unknown/truncated/overlong
versions, suffixes, deterministic mutations and **51 partial metadata-entry trie roots**. The
corpus retains **20 JSON-derived metadata records** and **20 exact nonempty raw trace entries**
with complete key/value replay. No published fields are normalized and no accumulation STF runs.
Supplementary checks exercise escaped/replaced fixed records, independent copies, literal
little-endian high-bit reads and late failures. After **1,000 warmed cycles**, public live allocation
returns from **192 to 192 bytes** while fresh encoded entries retire. This scoped observation does
not establish general leak freedom or RSS behavior; the decoded metadata itself has no references.

This increment adds **16 runtime misuse rejections** (eight actual/default result pairs) and
**nine compilation rejections** (six private/read-only result probes plus gas-as-balance,
bytes-as-items and timeslot-as-parent substitutions). Cumulative totals are **1,138 runtime misuse
rejections, 527 compilation rejections (452 privacy + 67 nominal + five schema + three static
contracts), 46 positive native suites and twenty-five family corpora**, plus three separate language
probes. Formatting covers **714 Nim files**; the functional report records **727 matching source/test
hashes**. Safety rejection counts remain separate from compiler-repair measurements.

The all-source semantic audit advances from 31/43 to **32/43 passing modules**, retaining all eleven
remaining failures. Branch Linux CI automatically runs the expanded migrated slice. Evidence here
remains local macOS ARM64, checked ARC/Clang LTO; actual Linux execution and full M1/M2/M3 runtime
parity remain gates. Next is service storage/preimage keys and retained raw values.

## Thirty-first bounded increment: service storage/preimage keyed values

`src/codec/state/service_values.nim` now targets the same pristine pinned Nimony nightly. Gray
Paper 0.8.0 T's storage/preimage mappings retain their distinct E4 namespace prefixes, original
raw keys/fixed lookup hashes, maintained Blake2b-256 key derivation and unframed raw values.
Values, including empty/count-like bytes and supplied hash/content mismatches, remain structural
state data. Capturing an existing hashed key checks its service octets without inferring its
original namespace or requiring original storage-key enumeration. No protocol/dependency change,
contextual hash/content validation or service-state transition is introduced.

`ServiceValueResult[T]` hides status/payload behind read-only reasons and a success precondition,
including private scratch extent proofs. A small private `storageExtent` helper preserves the
existing key-length-plus-four check and permits native arithmetic boundary tests without fake
open arrays or huge allocations. Nullable immutable owner storage is checked through stable
retained locals. Fixed identity metadata is copied; copy capacity/overlap checks still precede
every write, destination suffixes remain unchanged, and re-emitted entries own fresh raw bytes.

The port uses explicit initialization, nullable references and supported nonthrowing test-driver
parsers. The initial mechanical edit accidentally renamed ordinary function parameters along with
result fields. The compiler rejected those edits; restoring the parameter names was **one observed
source repair cycle**, not evidence of a language/library limitation. Initial build diagnostics
remain under ignored `build/nimony-trial/verification/*-initial-build.log`. A separate test-only
observer library-path typo caused one local link failure and was corrected without a source
change; that is infrastructure friction, not a compiler repair. No upstream or private-runtime
patches were needed, and no historical repair totals are inferred.

All **2,047 unchanged independent requests** and **six literal reference checks** pass. Coverage
retains namespace/hash boundaries, raw empty/binary/count-like values, service identity mutation,
key/value limits, fixed copies, deterministic sources and **83 partial single-entry trie roots**.
Pinned JSON supplies **12 storage and 16 preimage mappings** with exact source fields. Sixteen raw
trace captures retain original keys/values, explicitly unclassified: hashed namespaces cannot be
recovered from those keys and may include request histories. Constructor and opaque-capture
evidence remain separate. No published fields are repaired and no upstream generators execute.

Expanded private checks retain/release replaced owners, independent metadata/entry/copy outputs,
empty captures, atomic exact aliases, shifted overlap detection and short-destination precedence.
The existing separate test-only crypto observer demonstrates immediate backend refusal, policy
rejection before hashing (zero calls), successful recovery and scratch cleanup; production corpus
binaries link the unmodified bridge. Native extent checks cover `high(int)-4`, the exact fitting
boundary and larger rejected lengths without allocating advertised storage. After **1,000 warmed
cycles**, public live allocation returns from **272 to 272 bytes**. This scoped observation does
not establish general leak freedom or RSS behavior.

This increment adds **38 runtime misuse rejections** (nineteen actual/default result pairs) and
**13 compilation rejections** (eleven private/read-only result/owner probes and two nominal
hash/key substitutions). Cumulative totals are **1,176 runtime misuse rejections, 540 compilation
rejections (463 privacy + 69 nominal + five schema + three static contracts), 48 positive native
suites and twenty-six family corpora**, plus three separate language probes. Formatting covers
**725 Nim files**; the functional report records **746 matching source/test hashes**. Safety
rejections remain separate from compiler-repair measurements.

The all-source semantic audit advances from 32/43 to **33/43 passing modules**, retaining all ten
remaining failures. Branch Linux CI automatically uses the expanded runner. Verification here
remains local macOS ARM64, checked ARC/Clang LTO; Linux execution and full M1/M2/M3 runtime parity
remain gates. Next is service request-history framing and its tagged alternatives, preserving the
maintainer-parked namespace question without inventing interim restrictions.

## Thirty-second bounded increment: service request histories

`src/codec/state/requests.nim` now targets the same pristine pinned Nimony nightly. Gray Paper
0.8.0 T's request mappings retain E4 advertised lengths plus fixed lookup hashes, maintained
Blake2b/interleaved-service keys, canonical 0–3 counts and E4 timeslots in supplied order.
Equal/descending slots and the complete uint32 length domain remain structural data. Both top-end
namespace overlaps and duplicate-key rejection remain tested. The maintainer-parked namespace
question and its pending test are unchanged; no interim length restriction, chronology/lifecycle
rule, alternate encoding or protocol/dependency change is introduced.

`RequestResult[T]` hides status/payload behind read-only reasons and a success precondition,
including private extent proofs. `RequestHistory` now hides its mode and timestamp payloads.
`requestedHistory`, `availableHistory`, `unavailableHistory` and `reavailableHistory` construct the
four valid shapes. The read-only `state` and guarded timestamp accessors preserve familiar field
reads while preventing retagging, forged alternatives and inactive-field reads. To change a fixed
source value, construct a new valid history; raw object construction and field assignment are no
longer public. Default history remains valid Requested; default result remains failure.

The port explicitly initializes private staging fields, slot/preimage arrays and decoded history.
Accepted counts are checked in uint64 before narrowing and bound all native extent arithmetic to
1/5/9/13 bytes. Whole-prefix presence still precedes field copies. The trusted driver uses
nonthrowing complete-token parsing and valid source constructors. Existing selftest/driver and
new private/guard binaries passed their first targeted builds. A constructor-only inactive-read
probe initially remained a runtime contract; adding an explicit state proof made the compiler
reject it statically. This records proof availability, not a protocol defect or a source-port
repair. No compiler patches, private runtime hooks or historical repair totals are introduced.

All **2,273 unchanged independent requests** and **six passing literal checks** pass; the seventh
literal test remains explicitly skipped for the parked namespace policy. Coverage retains every
representative proper truncation, all E4 domains and active slot positions, invalid/huge/overlong
counts, caller limits, suffixes, deterministic mutations and **98 partial request-entry roots**.
Pinned JSON supplies **28 histories** (14/6/8/0 across counts 0/1/2/3); three-slot restoration is
authored coverage. Twenty exact raw identified histories consume completely and re-emit unchanged,
all count one. Identity is established by same-state content/preimage/request relationships, never
by reversing or guessing a hashed namespace. No STF or request lifecycle executes.

Expanded private checks cover all four fixed shapes, escaped/replaced copies, suffixes, late
truncation, protocol bounds and backend refusal/recovery. Observer counters prove history/key
policy rejects before hashing. Production corpora link the unmodified primitive bridge; fault
injection is isolated in test-only binaries. After **1,000 warmed cycles**, public live allocation
returns from **192 to 192 bytes** while fresh keyed entries retire. Fixed histories contain no
heap references; this scoped allocation observation is not an RSS or general leak-freedom claim.

This increment adds **74 runtime misuse rejections**: sixteen actual/default result pairs and
42 inactive-field reads (all six fields against every wrong source/decoded shape, plus defaults).
It adds **27 compilation rejections**: 24 private/read-only result/shape probes, two nominal
length/slot substitutions and one explicitly proven inactive timestamp contract. Cumulative
totals are **1,250 runtime misuse rejections, 567 compilation rejections (487 privacy + 71 nominal
+ five schema + four static contracts), 50 positive native suites and twenty-seven family corpora**,
plus three separate language probes. Formatting covers **752 Nim files**; the functional report
records **779 matching source/test hashes**. Safety counts are separate from compiler-repair metrics.

The all-source semantic audit advances from 33/43 to **34/43 passing modules**, retaining all nine
remaining failures. Branch Linux CI automatically runs the expanded migrated slice. Evidence here
remains local macOS ARM64, checked ARC/Clang LTO; Linux execution and full M1/M2/M3 runtime parity
remain gates. Next is exact chapter/service composition and whole-state root evidence, preserving
all existing interpretations and the parked namespace question.

## Thirty-third bounded increment: exact state composition and published roots

`src/codec/state/composition.nim` now targets the same pristine pinned Nimony nightly. Gray Paper
0.8.0 T's sixteen mandatory chapters retain exact typed capture, complete consumed extents and
shared core/validator/epoch profile association. Typed service metadata, storage/preimage/request
sources and explicitly opaque captured mappings retain their original keys and bytes. Parent
entry/value ceilings precede key work, and trie composition rejects every duplicate rather than
selecting an overwrite policy. C13 compact gas and the maintainer-parked request namespace remain
unchanged. No transition execution, namespace inference or protocol/dependency change is introduced.

`StateCompositionResult[T]` hides status/payload behind read-only reasons and a success
precondition. Nullable chapter/mapping owners are checked through stable retained locals.
`StateChapters` is a fixed sixteen-slot container with private storage and nominal `StateChapterId`
indexing: the nightly cannot default-initialize the former nonzero enum-indexed array. Its guarded
index accessors preserve chapter identity without exposing retained bytes. Forged chapter enum
values reject before dispatch. Exact captures, copied roots/counts and fresh extracted entries
retain immutable acyclic ownership; replacing caller chapter slots cannot mutate a completed state.

This port exposed more compiler friction than the smaller codec families. **Four rejected targeted
driver builds** preceded the first successful build, covering nonzero enum array/index/default
support, enum iteration, template-dependent field lookup and success symbols. One attempted shared
error-type name was my editing error. Explicit ordinal iteration, a nominal fixed container and
ordinary typed decode dispatch are supported without compiler patches or private runtime hooks.
After compilation, the existing duplicate-key selftest found **one error-translation defect**:
generic `when compiles(T.member)` checks did not retain the expected mapping, yielding
InvalidComponent instead of DuplicateKey. Explicit closed typed error adapters now preserve the
shared categories. Initial compiler logs and the isolated failing selftest are retained under
ignored `build/nimony-trial/verification/state_composition-*-build.log` and `composition-debug.log`.
These observed repairs and post-compilation failure are separate from safety rejection totals;
no historical repair counts are inferred.

All **14,471 unchanged independent composition requests** and **seven literal checks** pass,
comparing every completed key/value entry, root and topology count. All **224 unchanged published
chapter captures** succeed. All **fourteen complete published mappings** reproduce their roots
(ten distinct roots), with fixed metadata re-encoded and other keyed service values explicitly
opaque. Original namespaces are not recovered from hashes. A separate **154-request raw whole-map
root corpus** retains permutations, sensitivity mutations, exact budgets and duplicate/policy
failures over those same pinned states. No fixture bytes or published roots are repaired.

Expanded private checks cover escaped/replaced mappings and chapter handles, independent entries
and fixed commitments, missing/wrong-profile sources, exact descriptor/aggregate arithmetic and
late backend refusal after three successful service-key hashes. Observer counters demonstrate
parent preflight before hashing and recovery after refusal; production corpora link the unmodified
primitive bridge. After **1,000 warmed cycles**, public live allocation returns from **35,920 to
35,920 bytes**, including the retained authored chapter baseline. This scoped observation is not
an RSS or general leak-freedom claim.

This increment adds **36 runtime misuse rejections** (eighteen actual/default result pairs) and
**17 compilation rejections** (fourteen private/read-only result/owner/container probes and three
nominal owner/index substitutions). Cumulative totals are **1,286 runtime misuse rejections,
584 compilation rejections (501 privacy + 74 nominal + five schema + four static contracts),
51 positive native suites and twenty-nine independent corpora**, plus three separate language
probes. Formatting covers **768 Nim files**; the functional report records **803 matching source/test
hashes**. The composition corpus retains its embedded public ownership/association selftest;
the new native suite separately observes private lifetime/backend cleanup.

The all-source semantic audit advances from 34/43 to **35/43 passing modules**: every production
codec module now passes, with the remaining eight failures in contextual crypto/Bandersnatch and
QUIC. Branch Linux CI automatically uses the expanded runner. Verification here remains local
macOS ARM64, checked ARC/Clang LTO. Full M1 verification is not yet declared: next is a final audit
of M1 validation entry points, including the existing width-evidence and parked namespace-witness
regressions through this ported driver. This replays existing evidence, not new clarification work.
Linux execution and full M2/M3 runtime parity remain gates.

## Thirty-fourth bounded increment: M1 state regression replay and validation audit

The Nimony runner now replays the existing state-width and request-namespace regressions through
its already ported composition driver. This changes verification tooling only: no production
codec, protocol encoding, dependency pin or namespace admissibility rule changes.

- **37 width requests** preserve the embedded ownership selftest and all **36 exact captures**
  from four nonempty binary privilege fields and sixteen raw trace observations. Profiles,
  original byte hashes, candidate diagnostics and metadata associations remain in the report.
  C12 retains E4/E8 and C13 retains E4 keys/compact gas, with no fallback.
- **Seven namespace requests** preserve the embedded selftest, four successful predecessor/control
  mappings and two DuplicateKey post-states. Both funded tiny-payload local witnesses and their
  five pinned normative source hashes are retained. This is evidence replay, without new normative
  investigation, PVM execution or genesis-reachability claims. The request-history pending test
  stays skipped and the question stays parked until Gray Paper 0.8.1/0.8.2.
- The runner also executes the existing literal report, assurance and whole-state-root oracle
  safeguards, which the audit found were absent from the trial runner, plus specification source
  identity checks. Every new verdict participates in the runner's failing exit status. A failed
  composition build prevents both new regressions from executing a stale binary.

Width requests are now authored once in `tests/state_widths_oracle.py`; the historical wrapper and
Nimony runner consume that same unchanged input/expectation construction. A direct comparison with
the committed construction confirms identical requests, expectations and evidence records
(`build/nimony-trial/width-extraction-check.json`). All eighteen literal
width/namespace/root checks and all ten CI-helper checks pass. No new native adapter or production
implementation was needed, so there are **zero new compiler repair cycles, zero new production
implementation lines and zero observed production defects** in this tooling increment. This is
not an additional equivalent implementation task for language comparisons.

Cumulative checked evidence is **51 positive native suites, thirty-one independent corpora,
1,286 runtime misuse rejections and 584 compilation rejections** (501 privacy + 74 nominal + five
schema + four static contracts), plus three language probes. Formatting still covers **768 Nim
files**. The full functional report records **811 source/test hashes** and complete commands,
request/actual/expected hashes and individual verdicts. Results are local macOS ARM64, pristine
pinned Nimony 0.6.3, checked ARC/Clang LTO. Branch Linux CI consumes the expanded runner; this
local result does not establish Linux execution.

The audit compared the original Linux workflow's validation entry points with the trial runner:

| Validation scope | Nimony evidence / remaining work |
| --- | --- |
| Codec-native success, ownership and misuse checks | 51 suites and isolated runtime/compiler rejection checks |
| Reports, extrinsics, packages, headers, blocks, bits, collections and C.2 | Existing independent corpora; report/assurance literal harnesses now also gated |
| Typed state chapters, service values, composition and raw roots | Existing corpora; root literal harness now also gated |
| State-width evidence and parked namespace witnesses | Both unchanged regressions now gated |
| Specification identity | Existing provenance tests now gated |
| Early natural/fixed/bounded/composite/digest adapters | Native suites pass; five legacy independent batch corpora are not yet integrated |
| Contextual signatures, Bandersnatch, networking and integrated service | Separate M2/M3 ports; not M1 codec completion |

**Full local M1 validation parity is not yet declared.** The audit found that the historical
`tests/test_codec.py` entry point additionally drives natural, fixed-width, bounded, composite and
digest independent corpora through five batch adapters. Their successful native suites do not
replace those corpus comparisons. That is the next bounded validation task. No production codec
module remains to port; the all-source semantic baseline remains 35/43, with the eight remaining
failures in contextual crypto/Bandersnatch and QUIC.

## Thirty-fifth bounded increment: early independent corpora and local M1 validation parity

The natural, fixed-width unsigned, bounded bytes/sequences, optional/work/preimage and full digest
batch adapters now compile and run on the pristine pinned nightly. Production codec behavior,
protocol/dependency pins and the parked request-namespace question are unchanged. Trusted batch
I/O uses supported `cmdline`/`syncio`; textual uint64 and host-int parsing explicitly validates
before multiply/add/narrowing under intentional Nimony wrapping. Signed widths include `low(int)`
without an unrepresentable positive intermediate. Assertions and checked ARC/Clang LTO remain on.

The original Python request construction is extracted into reusable constructors; no cases or
expectations are replaced by production output. A direct comparison against the committed
constructors confirms exact equality, including metadata. Five checked corpus-identity tests freeze
the original request/expectation hashes so a later omission cannot silently reduce coverage.

| Independent family | Unchanged native requests |
| --- | ---: |
| General naturals | 45,215 |
| Fixed-width unsigned integers | 73,278 |
| Bounded byte strings and fixed-width sequences | 26,712 |
| Optional/work variants and nested preimages | 25,890 |
| Complete work digests | 14,278 |
| Total added to the trial runner | 185,373 |

Each original successful decode still exercises the existing owner-copy checks where applicable.
Encoder and sequence/preimage failure paths retain their whole-destination sentinels, including
late-field failures. Full fields, exact consumed extents, complete wire bytes and precise typed
failures are compared; this is more than round-trip agreement. Missing/extra response lines fail.
The original thirteen nominal rejection fixtures and two privacy/forgery fixtures now also run
through Nimony with their intended diagnostics. Existing isolated default/error runtime guards
replace the historical in-process `FieldDefect` catches; contracts must still terminate misuse.

**Eleven rejected adapter builds** were observed before all five built successfully: two each for
natural/fixed/bounded/digest, three for composite. The first five all report the same shared helper
initialization issue, so these are not eleven independent language problems. Explicit output-local
initialization fixes that diagnostic. The next round covers fixture I/O effects, supported `assert`
and element-wise sequence insertion. The final composite rejection caught my misplaced payload
loop outside its source scope. No production defect was found after successful compilation; all
five complete independent corpora passed their first native execution. These are adapter-port
measurements, not new protocol implementations. New production implementation LOC is **zero**;
historical compiler-repair totals and elapsed implementation times are not reconstructed.
Diagnostic evidence is retained in `build/nimony-trial/verification/early-*-first-build.log`,
`early-*-second-build.log` and `early-composite-third-build.log`. Corpus extraction/equality
and targeted execution evidence are in `build/nimony-trial/early-corpus-extraction.json` and
`early-targeted-results.json`. The full runner preserves final commands and hashes alongside them.

Cumulative coverage is **51 positive native suites, thirty-six independent corpora, 1,286 runtime
misuse rejections and 599 compilation rejections** (503 privacy + 87 nominal + five schema + four
static contracts), plus three language probes. This increment adds five corpora and fifteen
compilation rejections, with no increase to the runtime-misuse count. Formatting covers **769 Nim
files**. The functional report records **838 matching source/test/fixture hashes**. All five new
corpus verdicts and the five identity checks are required for a successful runner exit. Ten
CI-helper checks also pass.

**Local Nimony M1 validation migration parity is reached for the documented implemented scope.**
All codec modules and the audited original M1 regression families now have checked native evidence.
This does not resolve the maintainer-parked namespace question, imply general state admissibility,
implement state transitions or establish Linux execution. The separate source audit remains at
35/43: all production codec modules pass, with eight contextual crypto/Bandersnatch and QUIC
modules remaining. The global trial status stays `partial-checks-passed` until M2/M3 migration.
Next is the M2 assurance signing-context/validator-key slice.

## Thirty-sixth bounded increment: M2 assurance signing contexts

`src/crypto/assurance_context.nim` now targets the same pristine pinned Nimony nightly. The
Historical migration record: the following 46-byte transcript preserved the then-existing behavior.
The later [credential-backed token audit](../spec/signing-domains.md) identifies and corrects
its extra dollar byte; current assurance/guarantee transcripts are 45 bytes.

Gray Paper 0.8.0 `assurancesig` transcript was retained as exactly 46 bytes:
`$jam_available || Blake2b-256(parent32 || fixed_profile_bits)`. Canonical bits include the entire
native storage domain. Verification retains configuration/key-count/count precedence, then all
record index/order/padding/parent checks before any signature work. Validator identity selects
its key. Empty batches still require a valid configuration and complete key mapping. No state
eligibility, availability threshold, provider point-policy or protocol/dependency pin changes.

`AssuranceContextResult[T]` now hides its discriminator and fixed payload, exposes a read-only
error and requires success before copying a transcript or verified count. Default/error results
cannot be forged, retagged or read as all-zero credentials. Transcript storage is explicitly
initialized; all outputs are fixed copies. Foreign borrows remain synchronous, without retained
caller pointers or protocol heap owners. The test driver uses supported I/O and the shared
checked batch parsers, preserving the exact frozen input and expected outputs.

All **2,087 unchanged independent requests** and **four literal oracle checks** pass. Expected
transcripts come from Python hashlib and ordinary Ed25519 credentials from an independently
validated OpenSSL provider. Tiny/full and byte-width boundaries, empty/maximum counts, key
mapping, validator/order/padding/parent errors, wrong domain/hash framing and signature-byte
mutations retain their original coverage. Inputs remain unchanged after verification. The known
exceptional-point acceptance policy is neither resolved nor altered by these ordinary fixtures.

The observer-linked native suite proves complete structural/context preflight makes zero hash
attempts, including a later bad parent or padding behind an earlier invalid signature. Immediate
message refusal and refusal after the first verified record remain BackendFailure, never a partial
count; ordinary signature rejection remains InvalidSignature. Recovery succeeds with unchanged
borrowed records and public keys. Mutating source fields or an extracted transcript copy cannot
alter completed message bytes. The scoped workload returns public live occupancy from **192 to
192 bytes after 1,000 warmed cycles**. This is workload-specific allocator evidence, not RSS or
a general leak-freedom claim. The independent corpus links the production bridge; refusal tests
alone link the existing project-only observer. No native ABI or upstream source changes are needed.

Observed compiler friction: **two rejected corpus-driver builds** preceded success. The first
required unqualified `of None` in the generic variant branch; the second required binding generic
default results to locals before invoking their read-only error accessors. The new native suite
needed **one rejected build** to replace implicit distinct-key array equality with explicit copied
key-byte comparisons. The misuse adapter built on its first attempt. Thus **three rejected targeted
builds** were measured in this increment, with **zero defects found after successful compilation**.
These are port/test repairs, separate from the deliberate safety rejections below; unavailable
historical repair totals and development elapsed time are not reconstructed. Initial diagnostics
remain in `assurance-context-first-build.log`, `assurance-context-second-build.log` and
`assurance-context-private-first-build.log` under `build/nimony-trial/verification/`.

This increment adds **24 actual/default runtime misuse rejections** across message configuration,
padding and backend failures, and verifier configuration, keys, count, index, order, padding,
parent, backend and signature failures. **Nine compilation rejections** cover seven private/
read-only result probes plus the original parent/anchor and message/signature nominal probes.
Cumulative checked totals are **52 positive native suites, thirty-seven independent corpora,
1,310 runtime misuse rejections and 608 compilation rejections** (510 privacy + 89 nominal + five
schema + four static contracts), plus three language probes. Formatting covers **778 Nim files**;
the functional report captures **854 matching source/test/fixture hashes**. Ten CI-helper checks
also pass. The all-source semantic audit advances to **36/43**, leaving guarantee composition,
Bandersnatch and five QUIC modules as seven separate migration gates.

Verification remains local macOS ARM64, pristine pinned Nimony 0.6.3, checked ARC/Clang LTO.
Branch Linux CI automatically runs the expanded slice; Linux execution remains unverified.
Local M1 validation migration parity is retained, with the namespace policy still parked. Broader
M2/M3 parity remains open. Next is guarantee signing-message and complete-report signature
composition through the existing primitive bridge.

## Thirty-seventh bounded increment: guarantee messages and complete-report credentials

`src/crypto/guarantee.nim` now targets the pristine pinned nightly. The Gray Paper 0.8.0
`guarantorsig` message remains exactly `$jam_guarantee || Blake2b-256(canonical_report_bytes)`:
46 owned bytes, including the leading dollar sign, with no added timeslot or second hash. The
raw helper hashes supplied bytes; validating canonical complete reports remains the caller's
responsibility. No validator-assignment, eligibility or exceptional-point acceptance rule changes.

The new **`GuaranteeMessageResult`** owns private status and fixed completed storage, retaining
read-only `.error` and guarded `.value` access. It replaces this helper's former explicit
`CryptoResult[GuaranteeMessage]` return type: primitive result constructors remain private to the
primitive module. Current callers use the same read interface. The dedicated name also avoids
colliding with the codec's generic `GuaranteeResult[T]`. No public unchecked-success factory or
compiler/private-runtime workaround is introduced. Default/backend-failed alternatives cannot
publish partial/default signing bytes; successful outputs are independent fixed copies.

The full `report_driver.nim` now builds with the real production crypto bridge and handles both
its unchanged **18,430 codec requests** and its explicit credential subcommand. All **63 original
independent signature checks** pass across seven authored/published report fixtures: two valid
ordinary credentials, independent signature corruption, changed report hash, each new 0.8.0
shard/anchor-slot/lookup-state field, wrong domain and swapped public keys. Native output must
match every re-encoded report byte, all 46 signing bytes and the expected credential verdict.
The corpus remains structural evidence; a permissive profile does not make every sample
chain-eligible or establish guarantor assignments.

The original cases now have one shared `composition_cases()` constructor. Comparing its complete
ordered wire/credential/verdict tuples against the committed helper confirms exact equality.
`build/nimony-trial/report-signature-extraction.json` records that comparison. Two harness tests
freeze the full public case identity and independently check literal mutation offsets and unchanged
source fields. OpenSSL fixtures remain independently checked against the pinned RFC 8032 known
answer; expected message bytes come from Python hashlib. Every native command, input hash,
actual/expected output hash and individual verdict is retained by the trial runner.

A separate observer-linked native suite verifies independent known answers for empty and three-byte
raw inputs, copied transcript/source independence, immediate hash refusal and recovery. Those raw
inputs test the helper contract, not report admissibility. Public live occupancy returns **192 to
192 bytes after 1,000 warmed scopes**; this is workload-specific Nim allocator evidence, not RSS
or general provider leak freedom. The credential corpus links the production bridge; only fault
checks use the existing project-only observer. Native/upstream sources and pins remain unchanged.

**Zero rejected targeted builds or compile/fix cycles** and **zero post-compilation defects** were
observed in this increment. The full report driver, new native suite and misuse adapter each built
on their first attempt; all targeted execution passed. This is a small composition/adapter port,
not evidence that fewer cycles alone imply greater reliability. Historical repair totals and
elapsed development time are not reconstructed. Intentional rejection fixtures are safety evidence,
not compiler repairs.

This increment adds **four actual/default runtime misuse rejections** (empty/nonempty backend
failures), **six private/read-only result compilation rejections** and **two nominal probes**
(message versus signature, raw hash versus message). Cumulative totals are **53 positive native
suites, thirty-eight independent corpora, 1,314 runtime misuse rejections and 616 compilation
rejections** (516 privacy + 91 nominal + five schema + four static contracts), plus three language
probes. Formatting covers **788 Nim files**; the functional report records **868 matching source/
test/fixture hashes**. Ten CI-helper checks pass. The all-source semantic audit advances to
**37/43**, with Bandersnatch and five QUIC modules remaining.

Results are local macOS ARM64, pristine pinned Nimony 0.6.3, checked ARC/Clang LTO. Local M1
validation migration parity is retained. Raw primitives, assurances and guarantee/report signing
composition now pass, while Bandersnatch/VRF, networking and Linux confirmation remain separate
migration gates. The parked namespace and exceptional-point policies are unchanged. Next is the
Bandersnatch adapter's guarded results and native key/setup ownership slice.

## Thirty-eighth bounded increment: Bandersnatch results and native owner lifetimes

The GP 0.8.0 release-reference Bandersnatch adapter now targets the same pristine pinned Nimony
nightly. `BsResult[T]` hides status and payload behind read-only reasons and supported success
contracts for keys, setups, public keys, signatures, ring roots/proofs, verified outputs and
normalized sequences. The private acyclic `NativeData` reference is explicitly nullable in default
`BsKey`/`BsSetup` handles. Stable retained locals guard access; `close` clears the shared native
handle, and last-owner destruction selects the original Rust destructor exactly once.

Native pointers and out-handle storage now express the ABI's nullability explicitly. Native out-handle
pointers start nil, fixed buffers start initialized, and successful construction uses supported ARC
reference constructors. The public ABI, reason mapping, bounded setup capacities, synchronous
borrows, 96/784-byte contracts, normalization policy, source/SRS hashes and ark-vrf 0.2.2 profile
remain unchanged. No compiler/private-runtime hook, proof padding or unsafe test-vector feature
is introduced. Closing an owner still must not race an in-flight call through another alias.

The new native suite uses the **real Rust ABI**, including SRS-backed setups. A test-only C
observer counts successful constructors, destructor calls and live native keys/setups, and can
refuse either constructor. Only test C call sites redirect four owner functions to that observer;
production/upstream symbols and sources are unchanged. Successful observer calls delegate to the
original ABI. It never suppresses a destructor, dereferences freed memory or exposes a secret/native
address, and resetting counters cannot erase live-allocation counts. Counts establish release
pairing; they do not independently inspect Rust's scalar zeroization.

The suite verifies escaped key scope, source mutation independence, alias-retained replacement,
explicit close invalidating aliases, harmless repeated/default close, and one free at final ARC
release. Setup allocations have the same coverage with their own allocator/destructor, including
real commitment calls proving alias liveness. Setup capacities at both host extremes and outside
1..1023 reject before any native constructor call. Invalid scalar imports and injected constructor
refusals publish no owner; subsequent imports/setups recover. The suite observes zero live native
keys/setups after each scope.

Fixed public imports use the pinned draft-29 vector-one public encoding. Signature/root/proof
imports retain all bytes at their exact widths, reject short/long inputs and survive source
mutation; these width imports do not validate a proof equation. A separately extracted normalized
sequence can be changed without modifying its completed result. The warmed scalar/import workload
returns public live Nim occupancy from **192 to 192 bytes after 1,000 scopes**. Real setup release
is observed separately rather than rebuilding the SRS 1,000 times. This is bounded allocator/lifetime
evidence, not RSS, full-ring sizing or general provider leak freedom.

The maintained Rust builder is now shared independently of historical Nim driver compilation.
It rechecks pristine source trees, the SRS/fixture hashes and Cargo lock; runs rustfmt and **three
Rust bridge tests**, rejects unsafe `test-vectors` features, and builds with Rust/Cargo **1.99.0**
locked/offline. `tests/bandersnatch_native.py` records the compiler versions and separate observer
build. The Nimony Linux workflow installs the existing pinned Rust/rustfmt and explicitly fetches
the locked registry closure; actual builds/tests remain offline. No dependency or gitlink advances.

**Two rejected semantic checks** were measured before success: first the native handle storage/out
parameters needed explicit nullability; then the nullable contract needed to extend through native
calls and selectors. The owner suite and misuse adapter subsequently built and passed on their
first attempts. **No post-compilation defect** was observed. Diagnostics remain in
`build/nimony-trial/bs-initial.log`, `bs-second.log` and `bs-third.log`. These port repairs are
separate from intentional safety rejections; historical repair totals and elapsed development time
are not reconstructed.

This increment adds **32 isolated actual/default runtime misuse rejections** across sixteen native
import/owner/refusal paths, **17 private/read-only result/owner compiler probes** and **three nominal
probes**. Cumulative totals are **54 positive Nimony suites, thirty-eight independent corpora,
1,346 runtime misuse rejections and 636 compilation rejections** (533 privacy + 94 nominal + five
schema + four static contracts), plus three language probes and the separately recorded Rust tests.
No new full proof corpus is counted for these ownership/import checks. Formatting covers **810 Nim
files**; the functional report records **900 matching source/test/configuration hashes**. Ten
CI-helper tests pass. The all-source semantic audit advances to **39/43**: Bandersnatch and its dependent
`src/quic/offload.nim` now pass with the optional offload body disabled. Four QUIC modules remain;
offload-enabled compilation and runtime/lifecycle parity are still unverified.

All results remain local macOS ARM64, checked ARC/Clang LTO on the pristine pinned Nimony nightly.
Semantic compilation of the full Bandersnatch module is not full runtime conformance: original
ordinary/ring vectors, contextual JAM ticket domains, generated proofs, wrong context/additional
data and concurrent/native boundary coverage still need migration/replay. The namespace question stays parked and the
Bandersnatch draft-text/reference discrepancy remains documented; Linux confirmation remains
separate. Next is the contextual Bandersnatch/VRF/RingVRF vector and native-boundary slice.

## Thirty-ninth bounded increment: contextual Bandersnatch conformance

The original fixture driver now builds with public Nimony assertion, command-line, output and
`std/rawthreads` APIs. Four stationary OS-thread records borrow four caller-owned integer identities;
each worker creates its own ARC/native key owner. Every started worker is joined, including on
partial thread-creation failure, before argument storage leaves scope. No owner is shared between
threads and no compiler/private-runtime hook or dependency patch is introduced.

The existing Python oracle is reused rather than replaced. The production Rust library is linked
directly for these checks; test-only allocation interposition remains confined to the separate owner
suite. Proof bytes, contexts, additional data, JAM domains, source/SRS identities, capacities and
expected outputs remain unchanged.

| Checked release/LTO evidence | Local result |
| --- | --- |
| Published ordinary contextual vectors | All seven reproduce public keys, exact 96-byte signatures and outputs; wrong context/additional data reject |
| Published ring vectors | All seven reproduce 144-byte roots and verify 784-byte proofs/outputs |
| Independent published JAM tickets | All seven tiny/full tickets verify with the exact ticket-seal transcript; padding fixture root matches |
| Generated proofs | One randomized ring proof verifies; sixteen additional scalar/context messages sign and verify |
| Native concurrency | Four workers each complete 32 signing/verification rounds with independent owners |
| Native ABI boundaries | 99 wrong ordinary widths, 785 wrong ring widths and 64 mutated proofs reject; failed writes retain sentinel output |
| Failed-result access | Stops at the supported success precondition, before exposing default output |

The full corpus records **131 successful driver requests** plus its separately recorded deliberate
failed-result probe. Rejected protocol operations are successful driver invocations returning typed
failure, not process crashes. Exact commands/responses and per-command logs are retained in
`bandersnatch_corpus` in `build/nimony-trial/verification/results.json`; source hashes cover the driver,
shared oracle, consumed published fixtures, ABI and pins. Reproduce with the full runner below.

There was **one measured compiler repair** in this bounded increment: fixed-array output through
`echo` is unavailable in Nimony's output API, so the deliberate failed-result probe selects one byte
instead. It still rejects at the same success contract before output. The initial diagnostic is
retained locally in `build/nimony-trial/verification/bandersnatch-context-first-build.log`. Historical
repair counts are not reconstructed. No production implementation behavior changed.

Cumulative coverage is **54 native suites, thirty-nine independent corpora, 1,346 runtime misuse
rejections and 636 compilation rejections** (533 privacy + 94 nominal + five schema + four static
contracts), plus three language probes and three separately recorded Rust tests. This corpus does
not inflate existing result-guard or compilation counts. Formatting still covers **810 Nim files**;
source/test/configuration hashes total **906**. The unchanged all-source semantic baseline is
**39/43**; optional offload-enabled compilation remains unverified.

All results are local macOS ARM64, pinned pristine Nimony 0.6.3, checked ARC/Clang LTO and locked
Rust 1.99.0. **Local M2 migration regression parity is reached for the implemented release-reference
scope.** This preserves the Bandersnatch draft-text/reference discrepancy and exceptional-point
Ed25519 policy gate; it does not claim an audit, normative resolution or Linux confirmation.
M1's request-namespace policy remains parked.

## Fortieth bounded increment: nonblocking UDP and transport retirement

`src/quic/io.nim` replaces the unavailable Nim 2 socket/selector imports with a small maintained
POSIX adapter. Public OS headers define socket addresses, poll entries and byte-order calls; the
public Nimony POSIX bindings provide descriptor/error operations. Dependencies and the compiler
remain pristine. No private runtime API, worker pool or per-connection thread is introduced.

The dispatcher synchronously polls at most **two** descriptors with a **0–10 ms** wait, preserving
the controlled standalone/two-role topology. Every call rebuilds its fixed poll array, so there is
no asynchronous registration or pending buffer borrow. UDP remains nonblocking, non-inheritable
across exec, limited to existing IPv4/IPv6 loopback scope and 2,048-byte sends. The transport still
drains at most 64 packets per endpoint iteration. Interrupted/would-block reads yield to the next
bounded dispatcher/timer iteration; sends retain retryable versus terminal error distinctions.
This is a deliberately bounded adapter, not a general large-peer poll implementation.

Socket ownership is non-copyable. An endpoint retains only its dispatcher metadata; the dispatcher
stores copied descriptor numbers and never references endpoints, so ownership stays acyclic.
Explicit close and scope destruction both unregister before closing the descriptor. The custom destructor also
releases its retained ARC metadata field through the public destructor hook. One endpoint
cannot register with two dispatchers, and closing a dispatcher prevents subsequent waits. Retiring
one borrowed endpoint leaves its sibling active. Transport stack addresses remain stable while
LSQUIC callbacks borrow them, and callers still explicitly close native engines before scope exit.
The callback and engine defaults now express nullability. Scoped Nimony string storage provides
terminating-zero C strings only for the duration of synchronous native construction.

| Checked release/LTO evidence | Local result |
| --- | --- |
| Original idle/ready retirement matrix | 256 cases per family, sharing dispatcher metadata across retirements |
| Automatic scope retirement | Another 256 cases per family; rebind each retired port to prove OS socket release |
| Shared UDP dispatch | Both ready sockets route exact bytes/source ports; duplicate, foreign-dispatcher and capacity admission reject |
| Boundary/setup failure | Would-block reads, closed dispatchers, short result arrays, invalid send sizes, failed bind and live-owner overwrite reject |
| Native LSQUIC/TLS lifecycle | Failed certificate setup recovers; 16 IPv4/IPv6 standalone cycles and four shared engine pairs construct/poll/retire |
| Ownership/compiler safeguards | Private endpoint/dispatcher metadata reject; full compilation rejects implicit endpoint copying |
| Dispatcher ARC release | 1,000 warmed explicit/automatic scopes return public occupied memory to baseline |

The native QUIC build was extracted from the historical peer command without changing configure,
compile, link or dependency pins. The Nimony runner rebuilds that pristine library, creates ignored
fixture identities and links the two new suites. Linux branch CI runs these automatically and
retains `build/quic/build.log`; it does not invoke the historical Nim 2 peer build. The `nim` field
in the original QUIC pin file remains historical provenance, not this trial's compiler selection.

There were **four observed compiler repair rounds** during this port: ambiguous imported
socket enum names, mutable imported poll constants triggering synchronization checks, implicit
non-null default owners/string-to-C-string conversions, and missing exported close-on-exec
constants. Repairs qualify the socket enums, use
immutable header constants, model nullable owners/scoped C string storage and bind the missing
constants through public OS headers. Diagnostics are in
`build/nimony-trial/udp-first.log`, `quic-io-second.log`, `transport-io-first.log` and
`udp-cloexec-first.log`. The final round was caught by both suites and the module audit; its two
dependent suite failures count as one shared compiler repair, not independent language defects.
The separately intentional ownership probe passes semantic checking but full compilation rejects
`'=dup' is not available for type <UdpEndpoint>`; the runner therefore requires the full lowering
check. These are prospective observations, not reconstructed historical repair totals. Post-build
review also found an initially missing close-on-exec flag; it was restored and an OS-flag assertion
was added before final verification. A separate public-occupancy probe then found a custom
destructor omission: socket retirement passed, but the retained dispatcher ARC field was not
released (832 to 4,032 bytes over 100 scopes). Explicitly destroying that field fixes the probe
(192 to 192 bytes); the maintained suite now repeats 1,000 warmed explicit/automatic scopes (480 to 480 bytes).
Evidence is retained in `verification/udp-lifetime.log` and `udp-lifetime-fixed.log` under
`build/nimony-trial/`. These two review-found port defects are distinct from compiler repairs;
no upstream compiler/runtime change was needed.

Cumulative coverage is **56 positive native suites, thirty-nine independent corpora, 1,346 runtime
misuse rejections and 639 compilation rejections**: 535 privacy, 94 nominal, five schema, four static
contracts and one full-compilation ownership rejection. The new lifecycle checks belong to the two
positive suites, not additional independent codec/crypto corpora or result-misuse guard counts.
Formatting covers **816 Nim files** and the runner hashes **921 source/test/configuration files**.
The all-source semantic audit advances to **41/44**: the new I/O module and transport pass; peer,
mesh and integration remain. Offload-enabled compilation is still unverified.

All results remain local macOS ARM64 with pinned Nimony 0.6.3, checked ARC/Clang LTO and unchanged
LSQUIC/TLS pins. This proves only the exercised I/O/lifecycle slice. No authenticated peer exchange,
network service/mesh/resilience/offload parity or Linux execution is claimed. M1/M2 local regression
parity, the parked M1 namespace question and documented crypto policy gates retain their scope.

## Forty-first bounded increment: shared identity and frame validation

`src/quic/protocol.nim` now owns the existing pinned JAMNP-S key-derived SAN formula, copied DER
identity checks, E4 length admission and structural CE 143 frame boundaries. The peer imports that
module and delegates structural validation before its existing content-key, fixture and integration
checks. Those application checks remain in the peer; a structurally complete frame alone does not
establish preimage eligibility. The peer executable and its full original selftest are still migration
gates. This increment exercises the shared parsers independently of peer scheduling and sockets.

Applicable source remains `vendor/jam-np/simple.md` at networking revision
`439c45aad135dc654b3de6f56d7d694fd02b7aa8`: its alternative-name formula, Messages E4 framing and
CE 143 request/reply/FIN rules. Source, TLS, LSQUIC and crypto pins are unchanged. Identity policy
still requires Ed25519 key/signature algorithms and exactly one complete key-derived DNS SAN;
dialers compare all pinned key bytes, while an empty expected key allows identity discovery.
DER must be bounded and consumed exactly. No certificate chain/point-policy decision is introduced.

`LengthResult` and `FrameResult` keep tags and payload storage private. Read-only reasons distinguish
uninitialized, incomplete and rejected input. Only exact bytes with FIN expose frame size/extent;
partial input and complete bytes without FIN remain pending with no successful metadata. E4 counts
are compared before narrowing, and frame-header addition checks its remaining host-int capacity
before arithmetic on Nimony's wrapping target. The existing peer-facing `(complete, valid)` verdicts
are preserved by mapping pending to `(false, true)`, failure to `(false, false)` and success to the
unchanged payload/content checks.

| Checked release/LTO evidence | Local result |
| --- | --- |
| Shared native selftest | Every request/reply prefix and the original 10,000 deterministic malformed DER/frame byte inputs pass |
| Independent SAN formula | 322 inputs cover zero/all-one keys, all 256 individual bits and 64 deterministic unrelated keys |
| Independent E4 admission | 84 width/policy cases include unsigned extremes and host-int ceilings without large allocation |
| Independent structural framing | 11,394 cases cover prefixes, FIN, trailing bytes, wrong CE selector, large claims and original fuzz bytes |
| DER/identity policy | Real valid/wrong-key/SAN/algorithm fixtures, every DER truncation, trailing bytes/certificate, oversize and embedded-NUL SAN mutations |
| Result safety | Eight isolated default/error/pending reads reject; nine private/read-only/forged-result compilation probes reject |

The independent Python oracle uses arbitrary-precision radix division and length arithmetic, not
the native bit-grouping implementation or a Python production verifier. Its literal anchors protect
byte order, alphabet and FIN behavior. The full corpus has over **25,000 requests**, with exact groups,
commands, request/output SHA-256 values and first-mismatch diagnostics recorded as
`quic_protocol_corpus` in the full report. DER lengths vary with newly generated public fixtures;
the exact count belongs to that run's report. CI retains the public
`build/nimony-trial/verification/quic-protocol-requests.txt` for replay; private fixture keys remain
in ignored build storage and are not uploaded.

There were **two observed compiler repair rounds**: nullable test pointers/default initialization
in the frontend, then C generation for a header-defined structure containing inline byte arrays.
The maintained C extractor zeroes its full output after the preflight this caller proves; the
adapter therefore declares that output uninitialized until the synchronous extractor fills it,
checks extraction success, then copies public key bytes individually into native fixed storage.
It neither initializes C inline arrays with Nimony's distinct array representation nor passes an
incompatible native-array pointer. No warning suppression, compiler/runtime hook or dependency
patch is used. Diagnostics are retained in `build/nimony-trial/protocol-first-build.log` and
`protocol-second-build.log`.

One independent test anchor initially assumed that radix index 31 selected `7`; the pinned literal
alphabet includes its leading dollar sign, so index 31 selects `6`. The reference test expectation
was corrected; production output and the pinned formula were unchanged. This is a test-reference
repair, separate from compiler friction or a production defect. Historical repair/time totals are
not reconstructed.

Cumulative coverage is **57 native suites, forty independent corpora, 1,354 runtime misuse
rejections and 648 compilation rejections**: 544 privacy, 94 nominal, five schema, four static
contracts and one ownership-lowering rejection. Formatting covers **829 Nim files**; the full runner
hashes **938 source/test/configuration files**. The all-source semantic audit is **42/45**, adding the
shared protocol module while peer, mesh and integration remain. Enabled proof-offload compilation
is still unverified.

These are local macOS ARM64 results on the unchanged pinned Nimony 0.6.3, checked ARC/Clang LTO.
M1/M2 local regression parity retains its documented scope and normative gates. No authenticated
exchange, whole-peer selftest, service/mesh/resilience/offload parity or Linux execution is claimed.

## Forty-second bounded increment: CE digest integration ownership

`src/quic/integration.nim` now passes both its enabled crypto-linked path and its disabled typed
refusal path. This preserves the existing CE 143 test workload: capture one complete Gray Paper
0.8.0 C.2 work digest, overwrite borrowed receive bytes, serialize the retained codec owner, then
bind those bytes to the requested Blake2b-256 key. It introduces no normative relationship between
an embedded C.2 field and that query key, and changes no specification, native ABI or dependency pin.

Integration result status and payloads are private, with read-only reasons and success contracts.
`VerifiedDigest` retains an immutable acyclic ARC snapshot containing its codec owner and exact
serialization. Callers can retain the codec child, inspect a checked size or copy into preflighted
caller storage; mutable backing bytes never escape. Peer call sites use those APIs, including a
response-size overflow check, but the whole executable remains a migration gate.

Fixture banks now retain private immutable data. Fixed keys are copied and wire extraction returns
an explicit defensive copy. Default banks reject lookup, including an all-zero key. A complete
candidate is published only after all eight bounded trusted file reads and hashes succeed; a late
hash refusal or missing file preserves the prior bank and aliases. Successful reload tests use
actually different fixture bytes so accidental partial publication cannot pass unnoticed.

The enabled suite preserves the original 10,000 arbitrary captures and tests escaped aliases,
children surviving all integration handles, source overwrite, output mutation/tail preservation,
atomic short-output refusal, default handles, wrong keys and native refusal/recovery. Over 1,000
warmed owner/refusal/recovery scopes, public occupied memory returns **736 to 736 bytes**, with
outer fixtures live. This establishes release for that workload, not arbitrary service stability.

A separate production-linked driver matches **10,748 independent requests** against the existing
mathematical C.2 decoder and Python standard-library Blake2b. Inputs include the original eight
integration fixtures, published tiny/full work-result sources, every small truncation, selected
large boundaries, trailing bytes, wrong keys and the original arbitrary byte stream. Parse/trailing
failures preserve source bytes; post-parse hash refusal retains the original deliberate overwrite
behavior. Fourteen default/actual failed-result reads trap at success contracts, and eighteen
compiler probes reject private storage, retagging, forged snapshots/banks and old mutable fields.

One observed compiler repair was in the new test: equality is unavailable directly on the distinct
`PreimageKey` role, so the test now explicitly compares its fixed byte representation, matching the
existing implementation. The enabled production module passed its first semantic check. The
initial diagnostic is retained in `build/nimony-trial/integration-first-build.log`; historical
repair/time totals are not reconstructed.

The first cumulative run also exposed a negative-test naming collision: five new privacy fixtures
used `owned` for a local handle while importing the `owned` module. Three failed the strict
diagnostic gate, while two emitted an additional rejection alongside their intended error. All
five handles were renamed, retaining the strict gate and intended privacy checks. This is a
second observed test repair batch, not a production defect; the corrected probes are rechecked
before repeating the cumulative run.

Cumulative coverage is **59 native suites, forty-one independent corpora, 1,368 runtime misuse
rejections and 666 compilation rejections**: 562 privacy, 94 nominal, five schema, four static
contracts and one ownership-lowering rejection. Formatting covers **851 Nim files**. The full
runner hashes **971 source/test/configuration files** and records generated fixture hashes,
commands and verdicts in `build/nimony-trial/verification/results.json`. The all-source semantic audit is
**43/45**; peer and mesh remain. Enabled integration is built and executed separately, rather than
inferred from the disabled module audit. Enabled proof-offload compilation remains unverified.

Results are local macOS ARM64 on the unchanged pinned Nimony 0.6.3, checked ARC/Clang LTO.
Implemented-scope M1/M2 regression parity and their documented normative gates remain unchanged.
Authenticated exchanges, whole-peer/service/mesh/resilience/offload parity and Linux execution
remain separate gates.

## Forty-third bounded increment: authenticated peer executable

The actual `src/quic/peer.nim` entry point now builds with the unchanged pinned compiler and
LSQUIC/TLS ABI, under checked ARC/Clang release LTO. Explicit imports replace former implicit
standard-library exports, stable indexed slot pointers replace mutable iteration, and the included
mesh code uses the already migrated bounded dispatcher. Public POSIX `nanosleep` supplies the
existing ten-millisecond observation-barrier pause only when no native endpoint is live. Trusted
CLI/filesystem exceptions return a bounded process failure with a generic diagnostic. No runtime,
compiler or dependency source is patched, and no dual-compiler path is introduced.

Protocol behavior remains pinned JAMNP-S identity/SAN, exact ALPN, and CE 143 selector/E4/hash/FIN
framing. `tests/nimony_peer.py` reuses the original `tests/test_quic.py` matrix with isolated binary
and log paths, preserving all sixteen scenarios and their deadlines. Both endpoints must now have
the expected exit code, rather than letting one failed endpoint hide success on the other.
The valid case completes eight exact request/reply streams. Ten identity/TLS scenarios (including
the valid case) and six authenticated framing failures retain their expectations. Twelve additional
valid cold starts also pass. The no-FIN scenario observes **one OS thread per endpoint** while work
is pending. Nine malformed role/arity/port/deadline controls reject before READY or authentication.

Four additional positive suite invocations replay the real executable's 10,000-case malformed
DER/frame selftest, 256 UDP retirement cases, mesh ordering policy selftest, and the crypto-enabled
entry point's original 10,000 digest captures. The enabled binary is separately built and linked;
its no-socket selftest does not establish integrated service lifecycle parity. The 28 live pairs
and nine CLI cases are recorded separately from the 41 independent pure codec/crypto corpora and
1,368 failed-result contract probes. Branch CI retains nested peer logs and reports the network
matrix separately; a failure stays red. Shared startup and CI summary harness safeguards run too.

Four observed compile/fix rounds preceded the first successful semantic check: a mechanical loop
indentation repair; explicit formatting for nominal `JobId` diagnostics plus POSIX/calendar time
disambiguation; the remaining distinct POSIX `Time` initializer; and explicit zero initialization
of `liveMesh`'s count result. Nimony's definite-initialization diagnostic prevented the empty-peer
count from reading an undefined accumulator. Logs `peer-first-check.log` through
`peer-fifth-check.log` remain under `build/nimony-trial/`. The first linked build then passed.
These are measured repair batches for this task, not reconstructed historical totals.

Live testing/review found two further migration defects after compilation. First, this nightly's
native stdout is fully buffered: an unflushed READY marker can appear only after the listener exits.
A small local `progress` template uses public `syncio` writes/flush so lifecycle gates observe live
owners, preserving marker bytes and the original deadlines. Second, the compiler accepted
uninitialized local authentication/open flags and a nullable callback lookup pointer and emitted
uninitialized C locals. These are now explicitly initialized to false/nil. Authentication callbacks
and native counters were already successful in the failing live run; explicitly initializing those
locals restored stream admission. Repeated cold startups retain coverage for that path. This is a
**compiler safety limitation**, not an intentional arithmetic-wrapping difference; compilation alone does not prove
initialization safety. The integer-accumulator diagnostic above does not cover every scalar kind.

Cumulative coverage is **63 native suites, forty-one independent corpora, 1,368 runtime misuse
rejections and 666 compilation rejections**, plus the **16-case peer matrix, twelve repeated valid
startups and nine CLI rejections**. Compilation rejections remain 562 privacy, 94 nominal, five
schema, four static contracts and one ownership-lowering check. Formatting covers **851 Nim files**.
The full runner hashes **974 source/test/configuration files** and records commands and endpoint
outputs in `build/nimony-trial/verification/results.json`. The all-source semantic audit is **44/45**: the
standalone `mesh.nim` include fragment still fails without its parent peer context. Its policy
selftest passes through the real peer; retained mesh lifecycle and standalone module structure
remain separate migration work. Offload-enabled compilation remains unverified.

Results are local macOS ARM64 on pinned Nimony 0.6.3. Implemented-scope M1/M2 regression parity and
normative gates are unchanged. Service/integrated lifecycle, mesh/reconnect/resilience, proof
offload, Linux execution and a normal build/CI cutover remain open.

## Forty-fourth bounded increment: retained service and integrated digest lifecycles

The existing checked Nimony peers pass the original retained-listener and codec/crypto integration
workloads without further production changes. Only test binary/log routing and reproducible
verification/CI evidence change. The same pinned JAMNP-S CE 143 rules, Gray Paper 0.8.0 C.2 test
fixtures, native ABI and compiler/dependency revisions remain in force. Complete C.2 digests are
still an authored integration workload, not a new normative interpretation of CE preimages.

`tests/test_quic_service.py` accepts isolated binaries and log paths while retaining its sixteen
waves, four warmup observations, original deadlines and resource budgets. One server PID, UDP
socket and LSQUIC engine survive all waves. Two mixed clients retain real parked writes while
independent healthy peers complete requests. Wrong SAN/ALPN attempts reject without poisoning the
listener; two authenticated peers are killed, their connections expire and later waves recover.
The run retires **66 connections**, with peak overlap **five**, and checks exact healthy, malformed,
missing-FIN and cancellation outcomes before final shutdown. Client engines are fresh per dial.

`tests/test_integration.py` similarly reuses its original twelve waves and four warmup observations.
Three concurrent identities per wave each run eight independently owned streams: three successful
captures, four expected rejections (including wrong content hash), and one cancellation. The server
retains the validated digest owner across real backpressure before the cancelled stream's close
releases it. Codec, trailing and missing-key failures leave healthy siblings operational; later
healthy work succeeds. This retires **36 connections**, covers **288 initiated streams** and records
**36 cancelled-snapshot releases**, with peak overlap **three**. All source-overwrite, retained
serialization and Blake2b behavior remains in the previously verified native composition.

Targeted local observations, after the unchanged warmup:

| Observation | Retained service | Integrated digest service |
| --- | ---: | ---: |
| Waves / post-warmup samples | 16 / 12 | 12 / 8 |
| Live Nim allocation range | 0 bytes (6,112 throughout) | 0 bytes (1,088,656 throughout) |
| Idle descriptor range | 0 | 0 |
| Observed server OS threads | 1 | 1 |
| Idle RSS range | 81,920 bytes | 49,152 bytes |
| Post-engine Nim allocation, before / after | 192 / 5,664 bytes | 192 / 5,792 bytes |

The integration fixture bank intentionally remains alive at idle, including its one-MiB fixture;
flat live allocation is not a zero-allocation claim. The same finite budgets remain **64 KiB** for
post-warmup language allocation, **16 MiB** for RSS range, **two** descriptors and **256 MiB** active
RSS, with one thread. Final engine destruction has a separate **64 KiB** language-allocation
allowance. These observations cover controlled local workloads, not arbitrary leak freedom or a
performance benchmark. Targeted results and logs are preserved in `verification/retained-targeted-results.json` and
`verification/retained-targeted-{service,integration}/` below `build/nimony-trial/`. Final-run
observations are retained independently in `results.json`.

The cumulative runner now executes both workloads as separate mandatory gates and retains their
idle samples, peaks, connection counts and failure diagnoses. Branch CI archives server/client logs
and resource JSON and shows each workload's own verdict. Eleven existing lifecycle-harness tests
retain marker/deadline, sample-count, counter-scope and exact resource-boundary safeguards; the CI
summary tests also keep a failed integrated workload visible when ordinary service passes. All
native positives remain **63**, independent corpora **41**, runtime misuse rejections **1,368** and
compilation rejections **666**; network waves are not relabelled as compiler or codec probes.

No production implementation or compiler repair cycle was needed in this increment: both targeted
workloads passed on their first run. There is no new implementation LOC. Formatting still covers
**851 Nim files**. The full runner hashes **977 source/test/configuration files**, including the
shared service/resource harnesses.
The all-source semantic audit remains **44/45** with unchanged production hashes: the standalone
mesh include fragment still needs structure work. The prior boolean/pointer initialization safety
limitation remains recorded and is not resolved by these passing lifecycle tests.

Results are local macOS ARM64, pinned Nimony 0.6.3, checked ARC/Clang release LTO. Implemented-scope
M1/M2 parity and normative gates are unchanged. Retained IPv6 client engines, duplicate arbitration,
mesh/reconnect/resilience, enabled proof offload, Linux execution and normal build/CI cutover remain
separate gates.

## Linux workflow consolidation

The maintainer explicitly requests converting the existing Linux workflow rather than keeping a
parallel trial workflow. `.github/workflows/ci.yml` now installs the pinned Nimony nightly and
formatter and runs the migrated runtime suite plus the independent strict all-source audit. Pushes,
PRs and manual runs use this workflow on every branch, including after merge; neither job has a
branch-name condition. `.github/workflows/nimony-linux.yml` is removed. No Nim 2 runtime CI job is
retained, and no installer/action/compiler/dependency revision is advanced.

The runtime job preserves protocol provenance checks, checked ARC/Clang LTO, original lifecycle
budgets, failure summaries and diagnostic-only uploads. The module job remains independently red
for unported sources: the local 44/45 audit and remaining standalone mesh fragment are unchanged.
This consolidation is specifically authorized; earlier entries describing a separate trial workflow
record the historical sequence. Runtime gaps, initialization safety limitations and Linux execution
remain open, and ordinary local setup documentation is still a separate cutover task.

Local validation parses the workflow YAML, verifies unrestricted push/PR/manual triggers and both
jobs, and checks Bash syntax for all thirteen shell steps. Thirteen CI safeguard tests pass,
including a regression check against duplicate Linux workflows and branch-name exemptions.
Protocol provenance has two passing checks and the existing draft-29 discrepancy skip. This is a
CI-only change; no new Linux execution or full runtime-suite result is claimed.

## Forty-fifth bounded increment: standalone sessions and retained IPv6 mesh

`src/quic/peer.nim` is now the thin CLI; `src/quic/session.nim` owns the private peer/stream state,
identity callbacks, framing, single/service sessions and retained mesh coordination. The former
`mesh.nim` include fragment was moved with `git mv` and combined with the peer implementation.
This preserves stack-stable native callback owners and keeps all stream buffers and handles
private, without a circular module dependency or public mutable state. Only the bounded lifecycle
entry points, selftests and diagnostic helper are exported. Four compiler probes reject access to
private peer/stream types, frame inspection and certificate callbacks.

The source audit now independently compiles **45/45 production modules**. No file was excluded,
renamed out of the audit's Nim inventory or accepted through an expected-failure allowlist. This
covers the enabled-by-default source profile; it does not establish offload-enabled compilation or
complete runtime parity. The pinned compiler, dependency sources, native ABI and checked
ARC/Clang release LTO profile are unchanged.

Protocol policy remains the pinned JAMNP-S Required-connectivity preferred-initiator expression,
its example five-second fallback, duplicate-direction retirement and exact bidirectional CE 143
framing. The original independent Python byte-order expression checks direction decisions; literal
reference tests cover both final-byte high bits and symmetry. The original sixteen-round mesh
workload retains two IPv6 role engines and one dispatcher in each peer throughout fallback,
fifteen duplicate arbitrations, retirement and reconnect, completing **128 bidirectional queries**.
A wrong expected identity rejects both directions before any application exchange.

The original recovery workload retains one keeper and both its engines across **twelve peer
deaths/restarts**. Before each kill, eight real request owners are pending. Idle expiry settles
all **96 pending operations** exactly once, and each generation is followed by healthy exchange,
including an additional final generation: **104 healthy queries**. The targeted maximum observed
recovery was **1.974 seconds**, below the unchanged ten-second deadline. Client restarts use the
same identity/listener port, not a replacement keeper. No protocol deadline or resource allowance
is relaxed.

Targeted post-warmup observations are retained in `verification/mesh-targeted-results.json` and
adjacent `mesh-targeted/`, `mesh-bad-pin-targeted/` and `mesh-disruption-targeted/` logs below
`build/nimony-trial/`:

| Observation | Mesh peer A | Mesh peer B | Recovery keeper |
| --- | ---: | ---: | ---: |
| Live Nim allocation range | 0 | 0 | 0 |
| Idle descriptor range | 0 | 0 | 0 |
| Observed OS threads | 1 | 1 | 1 |
| Idle RSS range, bytes | 262,144 | 245,760 | 163,840 |

The same 64 KiB language-allocation, 16 MiB RSS-range, two-descriptor and 256 MiB active-RSS budgets
remain, with post-engine cleanup checked separately. These finite controlled observations do not
establish arbitrary leak freedom, network throughput or independent JAM-stack interoperability.
The cumulative runner and canonical Linux workflow now gate mesh, wrong identity and peer-loss
recovery separately, and retain endpoint logs/resource JSON and actual verdicts.

The standalone session and native peer built on the first attempt; there were **zero compiler
repair cycles** or new production decoder failures. One tooling repair completed compiler-specific
binary/thread-limit plumbing after an interrupted editing script left the original callable in an
initial orchestration process; recovery was then rerun with the completed helper. That is test
infrastructure friction, not a Nimony diagnostic or protocol defect. Three independent harness
checks protect the ordering reference, explicit one-thread/RSS budget and dead-keeper rejection.

Cumulative coverage is **63 native suites, forty-one independent corpora, 1,368 runtime misuse
rejections and 670 compilation rejections**: 566 privacy, 94 nominal, five schema, four static
contracts and one ownership-lowering rejection. Formatting covers **855 Nim files**; the full
runner hashes **984 source/test/configuration files**. Live network waves/queries are recorded separately from pure corpora and failed-result contract probes. The
module's private surface is tested in addition to its ordinary and crypto-enabled peer callers.
The prior accepted uninitialized scalar/pointer limitation remains documented; this refactor does
not claim to repair the compiler.

Results are local macOS ARM64 on pinned Nimony 0.6.3. Implemented-scope M1/M2 regression parity and
normative gates are unchanged. Same-process repeated endpoint teardown, remaining admission/
resilience coverage, enabled proof offload, Linux execution and local setup cutover remain open.

## Forty-sixth bounded increment: same-process endpoint destruction soak

The original `tests/test_quic_soak.py` workload now accepts isolated compiler binary and evidence
paths, matching the retained service/mesh harnesses. The cumulative Nimony runner gates its own
checked peer through **forty sessions in the same two processes**, discarding only the original
eight warmup observations. Each session destroys both transports, UDP sockets, dispatcher
registrations, callback owners and stream buffers before the next sample/release barrier. This
is distinct from retained-engine idle sampling. No production behavior, protocol setting,
dependency pin, timeout, warmup or resource allowance changes.

Each session requires five healthy CE 143 exchanges, two malformed-request rejections and one
cancellation, alongside actual large-response backpressure and missing-FIN timeout markers.
Across forty sessions this is **200 healthy exchanges and 120 adversarial streams**, including
forty cancellations. Both endpoints must report all eight terminal outcomes each session and
exit normally after the last cleanup sample. The existing occurrence-counted READY barriers
prevent a previous listener from authorizing the next dial.

The targeted run took **42.225 seconds** on macOS ARM64. Post-warmup observations:

| Observation | Server | Client |
| --- | ---: | ---: |
| Live Nim allocation range | 0 | 0 |
| Idle descriptor range | 0 | 0 |
| Observed OS threads | 1 | 1 |
| Idle RSS range, bytes | 196,608 | 229,376 |
| Active RSS high water, bytes | 7,897,088 | 10,993,664 |

Evidence is under `build/nimony-trial/verification/endpoint-soak-targeted/` with the returned
measurements in adjacent `endpoint-soak-targeted-results.json`. The unchanged limits are 64 KiB
language-allocation range, 16 MiB idle RSS range, two idle descriptors and 256 MiB active RSS;
these finite observations do not establish arbitrary leak freedom. The cumulative gate retains
separate `endpoint-soak/` logs/resource JSON, verdict and measurements. Canonical Linux CI uploads
that evidence and displays its own pass/fail summary without counting sessions as codec corpora,
compiler repairs or failed-result guard probes.

Two focused safeguards protect isolated binary routing/failure evidence and honest summary
verdicts. All twelve lifecycle-harness checks and sixteen CI safeguards pass. No production Nim
source changed and no new compiler repair cycle was required. Existing M1/M2 implemented-scope
regression parity and normative gates are unchanged.

The cumulative rerun also passes: **63 native suites, forty-one independent corpora, 1,368 runtime
misuse rejections and 670 compilation rejections** (566 privacy, 94 nominal, five schema, four
static contracts and one ownership-lowering rejection). All **984 recorded source/test/config
hashes** match the checked files. Its independently rebuilt peer completed forty soak sessions in
**47.969 seconds**, with zero post-warmup allocation/descriptor range, one thread per peer and
idle RSS ranges of 278,528 server / 212,992 client bytes. Formatting passes for all **855 Nim
files**. The 45-module compilation inventory is unchanged; no production source was modified.
The new network gate adds no compiler rejection cases, implementation LOC or compiler repairs.
Reproduce the complete checks with the commands below; `endpoint-soak-full.log` retains this
run's transcript and `verification/results.json` retains the cumulative verdict/measurements.

The first canonical Linux run at `658b5a9` passed the 45-module semantic gate but stopped before
runtime checks because the shared Bandersnatch builder did not create its output directory.
Commit `4f73ac5` fixes that clean-checkout setup defect and adds a missing/reused-directory check;
this was Python build infrastructure, not a Nimony compiler or protocol failure. A passing local
run is not a new Linux CI verdict. Linux runtime confirmation remains open.

## Forty-seventh bounded increment: admission recovery and pre-request connection loss

The remaining original IPv6 resilience workloads now accept isolated compiler binary/evidence
paths. Every server and load source uses the checked Nimony peer, while explicit per-role thread
limits preserve one dispatcher thread independently of the executable filename. This changes
only test routing and cumulative gates; production Nim, LSQUIC settings, protocol policy,
dependency pins and time/resource budgets are unchanged.

The original **twelve admission/recovery waves**, with four warmup samples and eight retained
observations, now pass locally. Each wave fills sixteen authenticated connections and rejects a
seventeenth without displacing the accepted peers. After those peers retire, eight holders fill
exactly **64 pending stream slots**. An excess stream rejects, killing one holder frees eight
slots, and a healthy query completes while the other seven loaded peers stay alive. All owners
then retire before the idle sample. Native state counters must retain the exact 16-connection/
64-stream ceilings and each cumulative rejection count.

The targeted run completed in **69.492 seconds** with **312 accepted/retired connections**, twelve
connection-capacity rejections, twelve stream-capacity rejections and twelve healthy queries after
release. Its server remained on one OS thread; post-warmup allocation and descriptor ranges were
zero. Idle RSS range was **65,536 bytes** and active RSS high water was **5,783,552 bytes**, within
the unchanged 64 KiB language-allocation, two-descriptor, 16 MiB idle RSS and 256 MiB active RSS
budgets. Neither the five-second probe retirement limit nor the original server/load deadlines
were widened.

The separate authenticated-close regression kills the server after `AUTH_OK` while the client
has deliberately opened **zero application streams**. The client must return failure with
`CONNECTION_CLOSED`, no fabricated `EXCHANGE_OK`, and settle within five seconds. The targeted
observation was **1.843 seconds**. Handshake history alone cannot authorize application success;
there is no stream callback available to settle this particular failure.

Targeted evidence is `build/nimony-trial/verification/admission-targeted-results.json`, adjacent
`admission-targeted/` logs/resource JSON and `closed-before-request-targeted/` endpoint logs.
The cumulative runner keeps independent admission and pre-request-close verdicts and requires
both. Canonical Linux CI retains their logs and admission resource samples and displays actual
waves, connection retirements and zero-stream close observations separately from codec/compiler
counts. Five mesh/resilience harness checks and seventeen CI safeguards pass, including isolated
binary routing, failed-startup child cleanup, strict probe deadlines/exit codes and independent
summary verdicts. No production implementation LOC or compiler repair cycle was added.

The complete cumulative rerun passes **63 native suites, forty-one independent corpora, 1,368
runtime misuse rejections and 670 compilation rejections** (566 privacy, 94 nominal, five schema,
four static contracts and one ownership-lowering rejection). All **984 recorded source/test/
configuration hashes** match. Its fresh admission run took **70.898 seconds**, again retired 312
connections and completed all twelve healthy recovery queries, with zero allocation/descriptor
range, one server thread and an idle RSS range of **393,216 bytes**. Fresh zero-stream close
detection took **1.782 seconds**. Evidence is in `verification/results.json` alongside the
`admission/` and `closed-before-request/` logs; `admission-full.log` retains the full transcript
under `build/nimony-trial/`. Formatting passes for all **855 Nim files**. The unchanged 45-module
source inventory retains its previously passing compilation audit; no production module changed.

These are finite controlled workloads, not proof of arbitrary leak freedom or interoperability
with another JAM implementation. M1/M2 implemented-scope parity and their normative gates are
unchanged; enabled proof offload, Linux runtime confirmation and local setup cutover remain open.

## Forty-eighth bounded increment: enabled bounded proof offload

The enabled peer now uses public Nimony `std/rawthreads` create/join operations for the original
fixed two workers. Each worker creates, uses and closes its own Rust setup; only copied fixed
proof/root/context/output arrays cross the mutex-protected four-slot queue. Neither ARC owners,
stream pointers nor TLS state cross into workers. The shared pool remains stack-stable until both
workers join. Explicit imports/effects, initialized local pools/counters/arrays, indexed stable
slot access and POSIX selftest sleeps replace the historical compiler assumptions. Public
`syncio` diagnostics flush complete lifecycle markers on the I/O thread. The pinned compiler,
checked ARC/Clang LTO profile, native ABI, dependency sources and protocol policy are unchanged.

`OffloadPollResult` now hides its discriminator and payload. Read-only readiness selects a
success-only completion accessor; four independent child probes reject default/actual-empty
completion reads with the expected contract diagnostic, in both disabled and enabled builds.
Enabled empty-poll probes start and join workers before attempting the invalid read. Five
compiler probes reject private-state inspection, public retagging, success forgery and completion
assignment. A full lowering probe rejects duplicating `OffloadPool`: containing `RawThread`
alone did not reject the composite copy probe, so the pool now exports its own explicit forbidden
copy contract. It must not be moved while workers borrow its address.

Job generations reject exhaustion before intentional integer wrapping can reuse an ID. The
no-network capacity selftest still proves four uncollected completions occupy all four slots,
then checks delivery of `high(uint64)` and rejection of the following submission. The separate
held-shutdown selftest still joins two held-running workers and drops two queued inputs without
requiring a controller to release the hold. Actual Rust execution is measured separately.

The original live workload passes **ten waves**, two warmup/eight retained samples and **128
RingVRF verification repetitions configured per job**; invalid proofs stop at the first failure. It verifies queue pressure, cheap networking while both workers
are held and while both are actually inside Rust, queued cancellation, held-running cancellation,
cancellation during real Rust work, wrong-domain rejection, stale-generation exclusion and joined
shutdown with **four jobs pending**. The targeted results are:

| Observation | Result |
| --- | ---: |
| Verified jobs delivered | 30 |
| Healthy lightweight queries | 70 |
| Capacity / wrong-domain rejections | 10 / 10 |
| Queued / held-running / actual-crypto cancellations | 10 / 10 / 10 |
| Fixed listener threads, including workers | 3 |
| Job slots / worker threads | 4 / 2 |
| Post-warmup Nim allocation / descriptor ranges | 0 / 0 |
| Idle RSS range, bytes | 409,600 |
| Active RSS high water, bytes | 11,075,584 |
| Elapsed seconds | 61.073 |

The original 64 KiB language-allocation, 16 MiB idle RSS, two-descriptor and 256 MiB active RSS
budgets and all observation/retirement deadlines remain. Language occupancy measures the I/O
thread; whole-process RSS and joined shutdown cover a different scope and are not proof of
arbitrary worker/native leak freedom. Evidence is in
`build/nimony-trial/verification/offload-targeted/results.json` and adjacent endpoint/resource
logs. Cumulative CI retains `offload/` diagnostics and a separate offload verdict, without counting
live jobs or queries as codec corpora or contract probes. Three independent offload-harness tests
freeze the original official tiny-ticket wire hash and reject missing completion/join observations
or a dead server; eighteen CI safeguards pass.

There were **three measured production-port compile/fix rounds**: explicit imports/public raw
thread operations, nominal job-ID diagnostic formatting, then fixture-I/O effect propagation.
The first linked enabled peer passed. Logs are `quic-peer-offload-first-build.log` through
`quic-peer-offload-fourth-build.log` under `verification/`. A subsequent ownership review found
the accepted composite pool copy; the explicit pool contract now produces the expected full-build
rejection, and the production peer still builds. One separate test-fixture correction batch
replaced direct `default(...).field` expressions with named locals in two privacy probes: the
former produced an unrelated variant-construction diagnostic instead of proving privacy. This is
not counted as two independent production/compiler defects. No historical totals are reconstructed.
The ordinary module audit passes **45/45**, including the shared completion API; enabled linking
and runtime evidence are recorded separately. Formatting covers **862 Nim files**.

The complete cumulative rerun passes **65 native suites, forty-one independent corpora, 1,372
runtime misuse rejections and 676 compilation rejections**: 571 privacy, 94 nominal, five schema,
four static contracts and two ownership-lowering rejections. All **994 recorded source/test/config
hashes** match. Its freshly rebuilt offload peer repeats the ten waves in **63.892 seconds**,
with three fixed listener threads, zero post-warmup language-allocation/descriptor range, an idle
RSS range of **163,840 bytes** and active RSS high water of **10,747,904 bytes**. Both capacity/
held-shutdown selftests, all four completion guards and the pool copy rejection pass. The fresh
45-module audit also matches every current production source hash. Cumulative evidence is in
`verification/results.json`, `verification/offload/` and `offload-full.log` under
`build/nimony-trial/`; the independent audit is `build/nimony-ci/modules/results.json`.

**Local M1/M2/M3 migration regression parity is reached for the documented implemented scope.**
This includes the original enabled proof-offload workload, not full JAM validator functionality
or resolution of the parked normative policy gates. These correctness workloads are not a
performance comparison with Nim 2. Normal build/setup cutover, that bounded comparison and
Linux execution of the newly expanded profile remain separate completion gates.

On 2026-10-17 the maintainer reported that an earlier pushed state passed PR CI and was pushing
the current committed state. No run ID or exact revision was supplied here; that is a reported
Linux pass for the earlier snapshot, not verification of this newly enabled offload profile.
The remaining uninitialized scalar/pointer compiler limitation remains documented and unchanged.

## Forty-ninth completion increment: supported setup and verification cutover

The offload increment was committed as `4986d05`. The maintainer explicitly requested completing
all remaining local migration tasks while retaining a single final push for Linux CI. No push or
merge was performed during this completion work.

`tools/setup_nimony.py` is now the shared local/CI installer, moved with `git mv` from the
Linux-only trial installer. `spec/toolchain.json` is the corresponding moved/consolidated pin
file: the compiler revision and existing Linux archive hashes are unchanged; the already selected
macOS ARM64 compiler archive and official formatter archive are now pinned there too. Common
checksum/safe-extraction code lives in the moved `tools/toolchain_archives.py`; the old Nim 2
installer entry point and separate historical CI archive pin file are removed. The formatter is
still official nimpretty from Nim 2.2.12; only its binary is exposed, never a supported Nim 2
production compiler. Both hosts use exact archive identity checks and checksum verification,
with installed compiler/formatter hashes retained for normal local verification.

A fresh project-local installation under `build/toolchain/` and a repeated installation both pass
on macOS ARM64. `environment.json` lets tools resolve it automatically; `env.sh` optionally exports
quoted NIMONY/NIMPRETTY/PATH settings. Unknown hosts, changed archives, changed installed tools,
wrong identities/versions and unrelated formatter-path collisions reject. No upstream installer
script runs. Linux setup uses the identical platform selector and installer; it retains its
previously pinned official binary/formatter assets.

`python3 tools/test.py` is the supported command. Its `all` plan combines the independent every-
source audit, formatting, CI/toolchain safeguards, protocol provenance, the complete checked
native runner and discovery of every independent `test_*harness.py`. CI uses that same plan split
into `modules` and `runtime` jobs; redundant separate preflight steps were removed. Normal tests
never select a global Nim 2 compiler. Historical individual runners retain reference/build helper
functions used by the cumulative verification, but their Nim 2 entry points are no longer the
supported workflow. README, development, design, networking, crypto and agent instructions now
state the active compiler and commands.

Cutover testing exposed a concrete infrastructure issue: Nimony dependency indexes cached under
the old compiler location caused full builds at the new location to report missing
`sys9kudoj1.s.deps.nif` files. An identical compiler archive is not sufficient to reuse those
location-dependent caches. Both native/negative builds and semantic audits now namespace caches
by resolved compiler location, without deleting historical evidence or patching the compiler.
A location-isolation regression check and a native natural-codec smoke build pass. This is build-
cache routing friction, not a new decoder/runtime failure. A separate new test initially compared
macOS `/var` and `/private/var` paths without resolving both; that test correction is recorded
separately. Twenty-three setup/CI safeguards pass. All 223 independent Python harness tests pass,
with one existing normative-policy skip.

## Fiftieth completion increment: bounded checked-LTO performance control

The [measured comparison](nimony-performance.md) and opt-in `tools/compare_nimony.py` close the
local performance question. Historical source is extracted from pre-port commit
`aea27ad0789ddb0abbea24c3923d0eb192a67e3a`; current source is copied into a separate ignored
snapshot. Both compile the identical checked workload with ARC, Clang `-O3` and LTO. The same
native crypto library is shared; the observer is separately compiled without LTO to prevent
result pruning. No production compatibility path, compiler/dependency patch or speed optimization
was introduced. The baseline remains a historical control, not a second maintained target.

Nine cases include observer overhead, compact decoding, 4,096-element E4 sequence encode/decode,
64-KiB owned byte capture/encoding, Blake2b, Keccak and Ed25519 verification. Seven raw native
batch samples alternate process order with equal calibrated iteration counts and matching result
fingerprints. Setup, compilation, preflight, warmup and process startup are outside native timing.
The observed sequence paths take **54–55% of the Nim 2 baseline time**; owned bytes are within
about **2%**, and common-provider crypto is within about **0.1%**. Tiny-call overhead differs and
is reported without subtraction. Near-unity differences are not demonstrated wins or regressions.
This single-host controlled sample reveals no broad regression in the measured paths, but is not
a full-client, contention, cold-cache, network-throughput or Linux performance claim. Correctness
coverage remains separate. Raw samples, source/build/library identities, tool versions and
isolated artifacts are retained in `build/nimony-comparison/`.

## Final verification: UDP readiness test correction

The first combined run exposed an intermittent assertion in the shared UDP test. Its two sends
succeeded, but the first `poll` could report only one ready socket. A successful datagram send does
not promise simultaneous delivery/readiness for both sockets. The test now drains and validates
both owners' payload/source identities over successive readiness events under the original single
10 ms budget. It still rejects duplicate/foreign descriptors and failed readiness. No production
networking code or deadline was changed. The corrected executable passed 100 consecutive runs.
A longer stress run also observed a separate scoped single-socket wait return zero after about
11 ms; its existing 10 ms limit is retained, with elapsed-time and OS-context diagnostics added.
That observation is test/environment timing evidence, not proof of a compiler or adapter defect.

At the maintainer's request, the two canonical CI job labels now omit the compiler name:
`Codec, crypto and QUIC (Ubuntu 24.04 x86-64)` and `All-source compilation gate (Linux)`.

## Final combined local result and merge assessment

`python3 tools/test.py` exits **0** with `PASS supported Nimony verification: all` on the pinned
macOS ARM64 installation. It includes **45/45 production modules**, formatting of **863 Nim source
files**, twenty-three setup/CI safeguards, protocol provenance, **65 native suites, forty-one
independent corpora, 1,372 runtime misuse rejections and 676 compilation rejections**. The latter
remain 571 privacy + 94 nominal + five schema + four static contracts + two ownership-lowering
rejections. All 223 independent Python harness tests pass with one existing normative-policy skip;
the separate provenance suite also retains its existing parked-policy skip. All **1,000 recorded
source/test/config hashes** match the final checkout after the run. The cumulative report retains
`partial-checks-passed` because this is implemented-scope migration coverage, not full JAM parity.

Evidence is retained in `build/nimony-trial/final-local-verification.log`,
`build/nimony-trial/verification/results.json` and `build/nimony-ci/modules/results.json`, with
individual build/run logs alongside them. The measured performance report is separate. The
completion changes are prepared for review; only the earlier offload increment was committed,
and nothing was pushed.

I recommend merging this compiler migration **if the expanded final Linux profile passes**.
The planned local setup, compilation, regression, lifecycle/offload and bounded performance gates
are complete without upstream patches, private-runtime hooks or a second production compiler path.
This is a recommendation for this pinned project/toolchain profile, not a claim that Nimony is
universally safer or ready for every application. Explicit initialization, guarded result access,
non-copyable owner contracts and reviewed foreign lifetimes remain requirements. The strict
10 ms UDP timing sensitivity observed during extended stress is retained explicitly above;
passing one complete run does not erase it. Specification/acceptance-policy gates remain unchanged.
The next planned action is the maintainer's final push and Linux CI verification, followed by a
merge decision; no additional feature increment is started here.

## Remaining work and next bounded increment

The normal local setup/verification cutover and bounded checked-LTO comparison are implemented.
The final combined local verification passes; the maintainer will push for Linux confirmation
after reviewing this completion. That confirmation must include the newly enabled offload gate.

Scope and remaining external/specification gates:

- M1: local validation migration parity is reached for the documented implemented codec scope.
  The request-namespace normative policy remains parked; Linux execution is a separate gate.
- M2: raw primitives, assurance contexts and guarantee/report signature composition pass locally.
  Bandersnatch result/import/native-owner safety and original contextual VRF/RingVRF, JAM ticket,
  generated-proof, concurrency and native-boundary regression coverage now pass locally. The
  documented release-reference/draft-text and Ed25519 policy gates remain.
- M3: bounded POSIX UDP/readiness, descriptor retirement and linked transport setup/teardown pass
  locally. Shared identity/DER, structural framing and enabled integration ownership/results pass
  too. The actual peer and one-shot authentication/framing matrix now pass locally. Retained
  service and integrated digest lifecycles pass too, alongside retained IPv6 mesh/reconnect and
  twelve peer-death recovery rounds, same-process endpoint teardown soak, connection/stream
  admission recovery, authenticated pre-request connection loss and enabled bounded proof
  offload. Implemented-scope M3 migration regression parity now passes locally; Linux confirmation
  of the expanded profile remains separate.
- Toolchain: normal local setup, supported verification commands and documentation now use the
  same pinned Nimony/formatter installation as the single canonical Linux workflow. The final
  combined local verification passes; expanded Linux execution remains a gate.

The Linux CI compiler switch is authorized and configured. All planned local migration tasks are
complete; final Linux confirmation remains before merge.
The M1 request-namespace question
remains parked for Gray Paper 0.8.1/0.8.2 review; this trial does not reopen protocol decisions.

## Reproduce

Install the prerequisites in [development](development.md), then use the shared pinned installer
and normal verification entry point. No upstream compiler build scripts or global Nim 2 compiler
are needed. Native dependencies and Rust registry packages must be provisioned before the runner's
locked/offline native builds.

```sh
python3 tools/setup_nimony.py
python3 tools/setup_submodules.py
rustup toolchain install 1.99.0 --profile minimal --component rustfmt --no-self-update
rustup run 1.99.0 cargo fetch --locked --manifest-path native/bandersnatch/Cargo.toml
python3 tools/test.py
```

The runner now targets **only Nimony**. It writes commands, compiler/nightly metadata, source/test
hashes and individual verdicts to `build/nimony-trial/verification/results.json`, with adjacent logs.
`protected_results_increment: passed`, `status: partial-checks-passed` and exit **0** record the
verified codec, owned-snapshot, report/extrinsic, package, header/block, packed-bit, collection and
C.2 slices, alongside raw crypto, state keys/node layouts, bounded trie, entropy/rosters/time,
authorization, state chapters 3–5/10/12–16, fixed service-account metadata and storage/preimage
keyed values, request histories, exact chapter/service composition, raw whole-state roots, published width
evidence, the unchanged parked namespace witnesses, the original five early codec corpora, stateless
assurance signing contexts, guarantee/report credential composition and the bounded Bandersnatch
result/import/native-owner and contextual proof/native-boundary/concurrency slices, plus the
bounded UDP/readiness and linked native transport lifecycle suites, shared identity/frame selftests
and their independent SAN/DER/framing corpus.
A missing check or failed guard still makes the runner exit one. There is no claim of full-client
parity. The maintainer reports an earlier snapshot passed Linux PR CI; the newly expanded offload
profile still requires its own Linux result. The canonical workflow uses Nimony; formatting passes.
Historical Nim 2 measurements are references, not an ongoing second source-support requirement.
