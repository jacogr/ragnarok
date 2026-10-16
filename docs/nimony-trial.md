# Nimony nightly trial

Branch: `nimony`, based on `aea27ad` (the codec-directory move). Trial date: 2026-10-16.
Status: **21 native suites, eleven independent family corpora, 522 runtime misuse rejections and
293 compilation rejections pass locally**. Availability specifications, deferred transfers and
accumulation input records now join the verified scalar, owned, report, extrinsic-family,
work-package, header, block, bitstring and collection slices.
M1 migration remains partial; M2/M3 and Linux parity remain unverified. This branch targets Nimony
directly, without dual-compiler source support. The main branch remains on Nim 2.2.12.
Protocol/dependency pins are unchanged.

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

## Remaining work and next bounded increment

Next: port the raw crypto primitive adapter (`src/crypto/primitives.nim`): Blake2b-256, Ed25519
and legacy Keccak-256, including guarded results, seed ownership/erasure and existing known-answer/
negative tests through the pristine native bridge. This is the M2 prerequisite for continuing M1
state-key/node hashing (`state_layout.nim` imports that adapter). Bandersnatch, contextual crypto,
remaining state codecs and M3 remain separate increments.

Further port work remains:

- M1: remaining record/state families still need compiler/runtime verification, guarded results
  and ownership coverage. Unsupported array slices, writable pointer views and `FieldDefect` catches
  need supported equivalents without reducing test coverage.
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
verified scalar/composite/digest/owned/report/assurance/guarantee/ticket/dispute/package/header/block/bits/collection/C.2
slice.
A missing check or failed guard still makes the runner exit one. There is no claim of full-client parity or an already
switched normal CI. Formatting passes.
Historical Nim 2 measurements are references, not an ongoing second source-support requirement.
