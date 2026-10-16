# Nimony nightly trial

Branch: `nimony`, based on `aea27ad` (the codec-directory move). Trial date: 2026-10-16.
Status: **44 native suites, twenty-four independent family corpora, 1,122 runtime misuse rejections
and 518 compilation rejections pass locally**. Chapter-16 last accumulation outputs joins the verified
scalar, owned, report/extrinsic, package, header/block, bitstring, collection, C.2, raw-crypto,
state-key/node, bounded trie, entropy/roster/time, authorization and state chapters 3–5/10/12–16.
M1 migration remains partial; broader M2, M3 and Linux parity remain unverified. This branch targets
Nimony directly, without dual-compiler source support. The main branch remains on Nim 2.2.12.
Protocol/dependency pins are unchanged. Branch Linux CI is now configured; actual Linux
execution remains pending the first workflow run.

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

`src/codec/state_layout.nim` now runs on the same pristine nightly. The scope remains Gray Paper
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

`src/codec/state_trie.nim` now runs on the same pristine nightly, retaining Gray Paper 0.8.0
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

`src/codec/state_safrole.nim` now runs on the same pristine nightly. It preserves Gray Paper
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

`src/codec/state_authorization.nim` now runs on the same pristine nightly, preserving Gray Paper
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

`src/codec/state_consensus.nim` now runs on the same pristine nightly, preserving Gray Paper
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
[trial workflow](../.github/workflows/nimony-linux.yml) targets pushes to `nimony`, PRs whose head
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

[Linux toolchain pins](../spec/nimony-ci-toolchain.json) select Ubuntu 24.04 x86_64, Python 3.12
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
compiler/environment metadata and uses `tools/setup_nimony_ci_linux.py` for verified installation.
Full Linux runtime evidence still awaits CI execution after publishing these changes.

## Twenty-third bounded increment: chapter-5 dispute judgment/offender state

`src/codec/state_disputes.nim` now targets the same pristine Nimony nightly. Gray Paper 0.8.0
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

`src/codec/state_history.nim` now targets the same pristine Nimony nightly, preserving Gray Paper
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

`src/codec/state_availability.nim` now runs on the same pristine Nimony nightly, preserving Gray
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

`src/codec/state_privileges.nim` now targets the same pristine Nimony nightly, preserving Gray
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

`src/codec/state_statistics.nim` now targets the same pristine Nimony nightly, preserving Gray
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

`src/codec/state_workqueues.nim` now targets the same pristine pinned Nimony nightly. Gray Paper
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

`src/codec/state_outputs.nim` now targets the same pristine pinned Nimony 0.6.3 nightly. Gray
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

## Remaining work and next bounded increment

Next: port M1 C(255, service) account metadata (`src/codec/state_accounts.nim`), preserving the
fixed version-zero record, nominal balance/gas/storage/time domains, chapter/service key layout,
whole-record preflight and the existing independent entry/root corpus.
Other state components remain later bounded chunks.

Further port work remains:

- M1: remaining record/state families still need compiler/runtime verification, guarded results
  and ownership coverage. Unsupported array slices, writable pointer views and `FieldDefect` catches
  need supported equivalents without reducing test coverage.
- M2: contextual JAM crypto and Bandersnatch/VRF runtime parity, including their FFI lifetimes,
  remain unverified. The raw primitive slice above does not establish those properties.
- M3: `std/nativesockets`, `std/selectors` and top-level `posix` imports do not resolve in the nightly.
  Its alternative networking facilities require a dispatcher port and the existing lifecycle,
  service, mesh, resilience and offload tests.
- Toolchain: branch Linux installation/pinning, formatter setup and trial CI are configured.
  Linux execution, normal build commands and main documentation/CI cutover remain gates until the
  port demonstrates equivalent safety.

No full migration or normal-CI compiler switch has occurred. The M1 request-namespace question
remains parked for Gray Paper 0.8.1/0.8.2 review; this trial does not reopen protocol decisions.

## Reproduce

Download the exact macOS ARM64 release asset above, verify its SHA-256 and extract under ignored
`build/nimony-trial/`. It supplies `nimony/bin/nimony` and libraries; no upstream build scripts
are required. A C/C++ compiler, CMake and the pinned BoringSSL/XKCP/Wycheproof submodules must be
available.
The runner rebuilds the maintained primitive ABI and separate test-only observer.

```sh
python3 tools/test_nimony.py --compiler build/nimony-trial/nimony/bin/nimony
python3 tools/format.py --check
```

The runner now targets **only Nimony**. It writes commands, compiler/nightly metadata, source/test
hashes and individual verdicts to `build/nimony-trial/verification/results.json`, with adjacent logs.
`protected_results_increment: passed`, `status: partial-checks-passed` and exit **0** record the
verified codec, owned-snapshot, report/extrinsic, package, header/block, packed-bit, collection and
C.2 slices, alongside raw crypto, state keys/node layouts, bounded trie, entropy/rosters/time,
authorization and state chapters 3–5/10/12–16. A missing check or failed guard still makes the runner
exit one. There is no claim of full-client parity or an already switched normal CI. Formatting passes.
Historical Nim 2 measurements are references, not an ongoing second source-support requirement.
