# Codec coverage audit and historical qualification records

Current implementation status and exact pins are recorded in
[the serialization status](../spec/jam-serialization-status.md) and [M1 checklist](m1.md).
C.1/C.2 framing and reviewed current state layouts are implemented. Accounts are
105 bytes, deferred transfers 154 bytes, and request-domain adoption is complete.
Independent [GP-derived serialization qualification](../spec/serialization-gp-qualification.md)
is covered within the declared contracts. Original published current-schema whole maps
remain additional corroboration; full JAM/STF parity is separate.

The family-by-family records below preserve earlier qualification evidence and
historical revisions. Their old chapter/namespace/proof/storage “next” paragraphs
are not a current backlog. In particular, old 89-byte account observations must
not be presented as unmodified current-schema metadata or current-root parity.
[The source audit](../spec/state-current-source-audit.md) and
[profile matrix](../spec/state-serialization-profiles.md) separate historical,
derived and authored current evidence.

## General encodings (C.1)

| Term | Status and evidence |
| --- | --- |
| Empty value, octet, tuple concatenation | Used by typed codecs; no general tuple combinator API. |
| General natural, fixed-width unsigned | Implemented in `natural.nim` / `fixed_unsigned.nim`; independent boundaries and nominal tests. |
| Byte strings, fixed-width sequences | Implemented in `bounded.nim`; explicit resource budgets and atomic borrowed operations. |
| Optional/tagged alternatives | Implemented for optional blobs, work results and header markers; not a generic schema framework. |
| Boolean | General strict 0/1 prefix API in `bitstrings.nim`, plus existing typed dispute paths. |
| Bitstrings | General fixed/variable bitstrings in `bitstrings.nim`, immutable owners, logical bit limits and canonical padding; specialized assurance bitfields remain available. |
| Canonical sets | Reusable fixed/explicitly variable typed sets in `collections.nim`; naturals, E0..E8 unsigned values and fixed octets, with strict logical order and immutable snapshots. |
| Canonical dictionaries | Reusable typed key/value tuples in `collections.nim` with one pair-count prefix, logical key order and immutable snapshots; the same scalar schema families are supported. |

General Boolean/bitstring validation: 11,274 deterministic independent requests, six oracle
known-answer checks, native lifetime/atomicity/alias/field-guard regressions, two nominal compiler
rejections and one privacy rejection. Existing pinned tiny/full assurance bitfields and distinct
dispute Boolean values are cross-checked through these APIs. See the
[bitstring contract](../spec/bitstrings.md) for framing and padding rules.

Canonical collection validation: 13,161 deterministic independent requests, seven oracle
known-answer checks, native retention/copy/alias/atomicity/variant-guard regressions, three nominal,
one unsupported-schema, two invalid-width and two privacy compiler rejections. The published
report prerequisite/lookup samples are empty, so their checks establish empty framing only;
authored nonempty numeric/octet cases provide the substantive order/association tests. See the
[collection contract](../spec/collections.md) for schema scope and framing.

## Specialized records (C.2)

| Term | Current implementation |
| --- | --- |
| Work outputs, digests and complete reports | `composite.nim`, `work_digest.nim`, `work_report.nim`, retained `report_owned.nim`. |
| Availability specification | Standalone 104-byte value codec in `c2_records.nim`, using existing nominal report fields and explicit core/byte policy. |
| Refinement context, imports, input commitments, work items/packages | `work_package.nim`, standalone components and package aggregate policy. |
| Tickets, preimages, guarantees, assurances, disputes | Dedicated family modules, exact framing and structural policies. |
| Safrole winning ticket, epoch/winner markers, full/signing headers | `header.nim`, distinct sealed/unsigned owners and retained marker access. |
| Complete extrinsic and block | `block_codec.nim`, typed components, complete preflight and retained children. |
| Deferred transfers (`defxfer`) | `c2_records.nim`: outer tag one, fixed service/balance/memo/gas fields and independent value copies. |
| Accumulation operands (`operandtuple`) | `c2_records.nim`: outer tag zero, natural gas, all work-result alternatives, bounded trace/payloads and retained snapshots; union framing also implemented. |

The concrete C.2 record gaps recorded by the earlier audit are now covered. Collection schemas beyond
the supported value-only scalar families need explicit future adapters and ownership contracts;
this increment does not provide an arbitrary child-codec framework. State-dependent eligibility,
hashing, signature/point validation, execution and authorization are not properties of the framing
layer.

Availability/accumulation validation: 26,090 independent requests, eight literal oracle checks,
three nominal and one private-owner rejection, plus native retention, copied fields, stricter
limits, aliases, atomicity and variant-guard checks. The exact availability prefixes are published
report bytes; accumulator operands derived from named report fields are not published standalone
operand vectors. No standalone transfer/operand codec fixture family exists at the pin. See
[the record contract](../spec/c2-records.md) for source and state-validation boundaries.

## State-layout extension

`state_layout.nim` implements the three 31-byte key constructors and 64-byte branch/leaf
encodings from the pinned state-merklization chapter. It copies fixed metadata and hashes canonical
node bytes through the existing primitive bridge. A decoded left child is a nominal **255-bit
commitment**, never a fabricated full node hash. Root construction is covered separately below;
proofs and persistence remain separate; component serializers are covered below.

Validation: 12,233 independent requests, six literal harness checks, three nominal compiler
rejections and fixed-value/variant-guard tests. The pinned historical trie JSON uses 32-byte keys;
only five singleton roots are used, with an explicit projection to the first 31 bytes. Those are
compatibility evidence, not modern full-trie vectors. Original data remains an unmodified pinned
Git blob; its generator is never executed. See [the contract](../spec/state-layout.md).

## Serialized state trie roots

`state_trie.nim` calculates M over already serialized 31-byte key/value entries. It preserves every
MSB-first unary branch, uses the zero empty identity, rejects duplicate keys and checks exact
nonempty-node work plus individual/aggregate payload ceilings before hashing. Inputs remain
borrowed only for the call; returned roots are independent fixed values.

Validation: 2,308 independent requests, six literal oracle checks, two nominal compiler rejections
and native source-preservation/copied-root/variant-guard checks. All 11 frozen historical roots
match only after explicit collision-free key projection; current authored 31-byte maps and the
pinned equations remain authoritative. Other state serialization, proofs and persistence are
separate. See [the root contract](../spec/state-trie.md).

## Safrole-related state serialization

`state_safrole.nim` implements T chapters 6–9 and 11: four entropy words, full 336-byte validator
rosters for staging/active/previous, and E4 timeslot. Variable rosters enforce canonical count
framing, protocol population and explicit resource ceilings before allocation. Decoder snapshots
retain private immutable copied records; owner-bound field extraction returns independent values.

Validation: 3,068 independent requests, six literal harness checks, two nominal and one privacy
compiler rejections, native retention/copy/field-guard checks and three partial trie integrations.
Four published tiny/full pre/post JSON states provide derived component fixtures, not standalone
published state encodings or passing STF claims. Other T chapters and service-account entries
remain open. See [the component contract](../spec/state-safrole.md).

## Authorization state serialization

`state_authorization.nim` implements T chapters 1–2: ordered per-core pools with canonical inner
counts (0..8 hashes) and fixed queues (80 hashes), with no outer core count. Explicit core/hash/byte
ceilings precede allocation; decoded snapshots retain private immutable core-bound rows and expose
only independent fixed hash copies. Sequence order and repeated values remain unchanged.

Validation: 7,059 independent requests, six literal harness checks, two nominal and one privacy
compiler rejections, native ownership/copy/index/result guards and two partial trie integrations.
Four published tiny/full pre/post JSON sources provide derived component fixtures. Other chapters
and authorization transitions remain separate. See [the contract](../spec/state-authorization.md).

## Safrole basic-state serialization

`state_consensus.nim` implements T chapter 4: pending full validators, opaque 144-byte ring
commitment, tagged ticket/key sealer schedule and bounded ticket accumulator. Fixed schedules omit
counts; tickets use C.2's identifier/E1-attempt record. Whole-parent preflight precedes child/parent
allocation. Immutable parent owners retain nested roster/schedule/accumulator storage privately.
Sequence order is preserved; epoch transitions, score selection and proof/key validation remain
separate responsibilities.

Validation: 7,298 independent requests, six literal oracle checks, two nominal and one privacy
compiler rejections, native ownership/copy/variant/index/result guards and ten partial single-entry
trie integrations. Eight published tiny/full pre/post JSON sources provide derived component
fixtures. Chapter 5 is now covered separately below; other state chapters remain open. See
[the contract](../spec/state-consensus.md) and [M1 parity checklist](m1.md#m1-parity-checklist).

## Dispute judgment/offender state serialization

`state_disputes.nim` implements T chapter 5's canonical good/bad/wonky report sets and offender-key
set. Each has its own canonical natural count and strictly increasing fixed-octet order. Per-set,
aggregate item and complete-byte ceilings precede allocation; no owner is constructed until all
four sets are valid. Extraction retains nominal report/key separation and immutable copied values.

Validation: 2,766 independent requests, six literal harness checks, two nominal and one privacy
compiler rejections, native ownership/copy/index/failure guards and twelve partial C(5) root
integrations. Twelve published pre/post JSON sources provide explicitly sorted derived set
fixtures; no dispute-transition or signature-validity claim is made. Chapter 3 is now covered
separately below. See [the contract](../spec/state-disputes.md).

## Recent history and accumulation-output belt serialization

`state_history.nim` implements T chapter 3's ordered recent records, canonical package/segment
root dictionaries, E4 slots and variable optional belt peaks. It follows T's explicit
header/super-peak/state-root order. Empty versus present-zero peaks retain distinct tagged values;
holes and trailing absences remain unchanged. Whole-parent preflight precedes all retained storage.

Validation: 1,985 independent requests, six literal harness checks, two nominal and one privacy
compiler rejections, native retention/copy/index/result/optional-field guards and nine partial C(3)
root integrations. Eight published tiny/full pre/post JSON sources supply explicitly derived named
field/dictionary/peak cases. No history-transition, MMR algorithm or commitment-consistency claim
is made. Chapter 10 is now covered below. See [the contract](../spec/state-history.md).

## Availability-assignment state serialization

`state_availability.nim` implements T chapter 10's fixed core sequence of optional full guarantees
and separate E4 registration times. Standalone scan/measure/capture/encoding helpers share the
existing guarantee record rules; extrinsic inter-record core ordering remains intact. Every slot
and nested child validates before parent/child allocation. Extracted guarantees retain immutable
reports independently of the parent lifetime; no mutable backing arrays are exposed.

Validation: 2,949 independent requests, six literal oracle checks, two nominal and one privacy
compiler rejections, native lifetime/copy/presence/index/result guards and four partial C(10) roots.
Twelve derived published JSON-state observations preserve eight successful assurance states and
four expected raw dispute-state decoder rejections. No child policy or fixture field is weakened.
Assignment transitions and cryptographic verification remain separate. Chapter 12 is now covered
below. See [the contract](../spec/state-availability.md).

## Privileged-service configuration state extension

`state_privileges.nim` implements T chapter 12: fixed E4 manager/core assigners/delegator/registrar
and a count-prefixed dictionary of E4 service IDs and E8 gas allowances. Strict numeric key
order, uint32 service bounds, full uint64 gas, resource policy and whole-parent preflight precede
allocation. Private ARC snapshots expose copied roles, nominal core extraction and fixed copied
service/gas pairs. No caller-owned arrays or detached spans escape.

Validation: 1,354 independent requests, six literal oracle checks, two nominal and one privacy
compiler rejections, retained-scope/copy/index/result guards and 24 partial C(12) roots. Sixteen
published pre/post/profile observations derive exact component bytes from eight pinned accumulation
JSON fixtures, preserving fields and explicitly sorting dictionary keys numerically. These are
serialization checks, not STF execution or whole-state-root evidence. Chapter 13 is now covered
below. See [the contract](../spec/state-privileges.md).

## Activity statistics state extension

`state_statistics.nim` implements pinned T chapter 13: separate count-prefixed current/previous
validator arrays with six E4 counters per record, fixed core tuples of eight naturals, and a
numeric-key service dictionary with eleven natural fields per value. Separate roster populations
support epoch resizing. Full preflight precedes allocation; private ARC owners expose copied,
nominally indexed records. No statistics updates, accounting or epoch transitions are executed.

Validation: 2,547 independent requests, seven literal oracle checks, two nominal and one privacy
compiler rejections, retained-scope/copy/index/result guards and eight partial roots. Eight published
validator-pair observations have explicit authored completion for their missing core/service fields.
The initial six-entry raw trace probe exposed the natural-key mismatch. The subsequent dictionary
migration now uses E4 service keys and retains compact core/service fields, including gas, with
no fallback. All 224 selected chapter captures reproduce their bytes through typed composition;
the original key-width implementation gate is closed. Upstream open #564 supports these choices
but proposes a separate validator-record format change, not adopted here. See
[the current upstream disposition](../spec/state-clarifications.md). Chapters 14–15 are covered below.
See [the contract and exact trace evidence](../spec/state-statistics.md).

## Ready and accumulated work state extension

`state_workqueues.nim` implements T chapters 14/15 as fixed epoch rings without an outer count.
Ready slots contain count-prefixed ordered report/dependency-set pairs; accumulated slots contain
count-prefixed canonical package-hash sets. Each report retains the existing child structural
policy. Independent row/aggregate item, dependency, child-byte and parent-byte ceilings preflight
the complete ring before any retained parent/child allocation. Private ARC owners expose copied
hashes/counts and report handles that survive parent release.

Validation: 2,904 independent requests, six literal oracle checks, three nominal and two privacy
compiler rejections, native lifetime/copy/index/result guards and 48 partial C(14/15) roots.
Twenty-four JSON-derived tiny/full component observations include dependency chains and wraparound;
all set sorting is explicit transport derivation. Twelve unchanged trace entries match completely
and re-emit identically; their ready rings are empty, and some accumulated sets are populated.
Transitions/dependency resolution and full-state roots remain separate. The chapter-13 gate is
unchanged. Chapter 16 is now covered below.
See [the contract](../spec/state-workqueues.md).

## Last accumulation output state extension

`state_outputs.nim` implements T chapter 16 as one count-prefixed ordered sequence of E4 service
IDs and fixed 32-byte output commitments. The complete count/extent/byte policy is checked before
allocation or payload access. Private acyclic ARC owners expose only copied fixed pairs/counts
through nominal indices. Encoding preserves supplied sequence order and duplicates structurally;
it does not infer accumulation transitions or turn the sequence into a canonical dictionary.

Validation: 1,901 independent requests, six literal oracle checks, two nominal and one privacy
compiler rejections, scope/copy/index/result guards and 21 partial C(16) roots. Eight unchanged
trace entries consume completely and re-emit identically, but all are empty. Nonempty sequence,
E4/commitment, order, count, policy, truncation and mutation coverage is explicitly authored.
No nonempty published conformance, accumulation execution or whole-state-root claim is made.
Service-account metadata is now covered below; keyed service entries and whole-state integration
remain. The chapter-13 parity gate is unchanged.
See [the contract](../spec/state-outputs.md).

## Service-account metadata extension

`state_accounts.nim` implements C(255, service): version zero, code hash, five E8 fields and four
E4 fields in a fixed 89-byte payload. Service identity remains in the interleaved chapter key.
The decoder returns independent fixed values without heap ownership after complete policy/version/
payload checks. Distinct balance, gas, storage-size/item, timeslot and service types preserve roles;
unknown versions, malformed discriminators, truncation and insufficient budget return typed failure.

Validation: 1,794 independent requests, six literal oracle checks, three nominal compiler
rejections, fixed scope/source/input/value-copy and result guards, and 51 partial entry roots.
Twenty pinned JSON-derived records and twenty exact trace key/value entries match, preserving all
metadata fields, including nonzero service IDs. No account-validity, footprint/deposit/chronology,
code-preimage or whole-state-root claim follows from metadata framing. Storage/preimage entries
are now covered below; request history and whole-state composition remain. The chapter-13
parity gate is unchanged. See [the contract](../spec/state-accounts.md).

## Service storage and preimage entry extension

`state_service_values.nim` implements C(service, E4(uint32-max) || raw key) storage mappings and
C(service, E4(uint32-max-1) || hash) preimage mappings, with unframed raw values. Logical key/value
policy and native scratch extent precede key hashing/output copying. Capture of an existing key
retains independent raw bytes and checks its interleaved service identity, requiring no original
storage key or guessed hashed namespace. Copy/re-emission APIs preserve private immutable storage,
atomic failure and empty-value presence. Hash/content and request-history validity remain contextual.

Validation: 2,047 independent requests, six literal oracle checks, two nominal and one privacy
compiler rejections, retained-scope/key/value/result/atomic/alias checks and 83 partial roots.
Twelve storage and sixteen preimage JSON-derived mappings preserve all source bytes. Sixteen exact
trace captures test opaque existing-key/raw-value retention only; their namespaces cannot be
recovered and are not claimed as classified storage/preimage conformance. Request-history framing is now covered below; whole-state composition remains. The dictionary-width work is complete; see the current upstream disposition below.
See [the contract](../spec/state-service-values.md).

## Service request-history extension

`state_requests.nim` implements C(service, E4(length) || lookup hash) and count-prefixed 0..3 E4
history slots. Fixed tagged alternatives expose only actual mode fields; defaults/failures remain
separate. Complete count/item/byte preflight precedes copying, key hashing and output allocation.
No chronology, availability, request lifecycle or preimage/context invariant is inferred.

Validation: 2,273 independent requests, six passing literal checks and one pending namespace-policy
check, two nominal compiler rejections, fixed-copy/tagged-field/result guards and 98 partial roots.
Twenty-eight JSON histories cover counts 0/1/2; twenty exact trace histories with proven matching
preimage identities cover count 1. Count 3 is authored evidence. Full E4 lengths fffffffe/ffffffff
reproduce preimage/storage namespace overlaps; trie composition rejects duplicate keys, and no
admissibility restriction is invented against the current pin. Whole-state composition/root
evidence and dictionary-width migration are implemented; adoption of merged upstream #542
remains for the next compatible release/vector upgrade. See [current status](../spec/state-clarifications.md). See [the contract](../spec/state-requests.md).

## Published codec fixture inventory

Both `codec/tiny` and `codec/full` contain the following 15 JSON/binary pairs. These are all current
published codec basenames at the pin, not a claim that the corpus exhausts Appendix C.

| Published basename(s) | Verification and outcome |
| --- | --- |
| `work_result_0`, `work_result_1`, `preimages_extrinsic` | `tests/composite_checks.py`; original bytes plus independent field/boundary tests. |
| `work_report` | `tests/report_oracle.py`; exact JSON/wire observation and documented tiny core policy. |
| `assurances_extrinsic` | `tests/assurances_oracle.py`; original profile bitfield framing/order. |
| `tickets_extrinsic`, `guarantees_extrinsic` | `tests/tickets_oracle.py`, `tests/guarantees_oracle.py`; original bytes and explicit tiny guarantee core-bound rejection, plus derived valid source. |
| `disputes_extrinsic` | `tests/disputes_oracle.py`; both raw samples reject descending verdict order; sorted authored counterparts pass. |
| `refine_context`, `work_item`, `work_package` | `tests/package_oracle.py`; exact named-field reconstruction and existing package policies. |
| `header_0`, `header_1` | `tests/header_oracle.py`; all four exact headers and signing prefixes pass. |
| `extrinsic`, `block` | `tests/block_oracle.py`; all originals reconstruct exactly, tiny rejects guarantee core 3, full rejects descending disputes; authored counterparts pass structural tests. |

Composite counterparts retain opaque header hashes/proofs/signatures unchanged, so are not
chain-valid examples. See [composition](../spec/block.md), [guarantees](../spec/guarantees.md) and
[disputes](../spec/disputes.md) for the exact rejection/derivation contracts. Vendor files remain
untouched. Specialized tests add independent boundaries, malformed inputs, ownership, atomicity
and negative compilation coverage beyond these finite published examples.

The source-of-truth migration and unresolved crypto gates remain recorded in the
[migration audit](../spec/graypaper-0.8.0.md). This audit does not close those gates or certify a
complete consensus implementation.
