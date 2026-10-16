# M1 coverage audit — Gray Paper 0.8.0

This audit follows Appendix C.1/C.2 at the exact source/vector revisions in `spec/pins.json`.
The **C.1/C.2 framing baseline is implemented within the scope listed below**. Complete published
fixture-family coverage does not mean every general
encoding or specialized C.2 tuple has a reusable public API. A separate state-layout foundation
now covers key construction/node encoding, roots over serialized entries and state chapters
1–2/4–9/11; remaining state serialization, trie proofs and persistence remain open. PVM execution and
state transitions are separate client work.

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
fixtures; no dispute-transition or signature-validity claim is made. Next planned: chapter 3
recent history and accumulation-output belt. See [the contract](../spec/state-disputes.md).

## Published codec fixture inventory

Both `codec/tiny` and `codec/full` contain the following 15 JSON/binary pairs. These are all current
published codec basenames at the pin, not a claim that the corpus exhausts Appendix C.

| Published basename(s) | Verification and outcome |
| --- | --- |
| `work_result_0`, `work_result_1`, `preimages_extrinsic` | `tests/test_codec.py`; original bytes plus independent field/boundary tests. |
| `work_report` | `tests/test_work_report.py`; exact JSON/wire observation and documented tiny core policy. |
| `assurances_extrinsic` | `tests/test_assurances.py`; original profile bitfield framing/order. |
| `tickets_extrinsic`, `guarantees_extrinsic` | `tests/test_tickets.py`, `tests/test_guarantees.py`; original bytes and explicit tiny guarantee core-bound rejection, plus derived valid source. |
| `disputes_extrinsic` | `tests/test_disputes.py`; both raw samples reject descending verdict order; sorted authored counterparts pass. |
| `refine_context`, `work_item`, `work_package` | `tests/test_work_package.py`; exact named-field reconstruction and existing package policies. |
| `header_0`, `header_1` | `tests/test_header.py`; all four exact headers and signing prefixes pass. |
| `extrinsic`, `block` | `tests/test_block.py`; all originals reconstruct exactly, tiny rejects guarantee core 3, full rejects descending disputes; authored counterparts pass structural tests. |

Composite counterparts retain opaque header hashes/proofs/signatures unchanged, so are not
chain-valid examples. See [composition](../spec/block.md), [guarantees](../spec/guarantees.md) and
[disputes](../spec/disputes.md) for the exact rejection/derivation contracts. Vendor files remain
untouched. Specialized tests add independent boundaries, malformed inputs, ownership, atomicity
and negative compilation coverage beyond these finite published examples.

The source-of-truth migration and unresolved crypto gates remain recorded in the
[migration audit](../spec/graypaper-0.8.0.md). This audit does not close those gates or certify a
complete consensus implementation.
