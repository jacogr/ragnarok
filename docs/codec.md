# Codec APIs and ownership

Production codec modules live under `src/codec/`. [Pinned normative contracts](../spec/codec.md)
and the other files under `spec/` define the exact wire rules, resource ceilings and failure precedence.

| Module | Scope |
| --- | --- |
| `natural.nim`, `fixed_unsigned.nim` | Canonical naturals and fixed unsigned widths 0..8 |
| `state_layout.nim` | State-key constructors, fixed branch/leaf node encodings and canonical node hashing |
| `state_composition.nim` | Exact typed chapter capture, profile-bound immutable whole mappings, typed service sources and bounded roots; width/domain gates remain open |
| `state_trie.nim` | Bounded roots over already serialized 31-byte-key mappings |
| `state_authorization.nim` | Core-indexed authorization pools/queues, bounded entries and immutable snapshots |
| `state_requests.nim` | E4-length/hash request keys and fixed tagged 0..3-slot histories; reserved-length cross-map policy remains pending |
| `state_service_values.nim` | Storage/preimage key namespaces, unframed raw values, immutable service/key-bound capture and atomic copies |
| `state_accounts.nim` | C(255, service) fixed version-zero account metadata; value-only copies, nominal fields and explicit version checks |
| `state_outputs.nim` | Chapter-16 count-prefixed ordered E4 service/output-commitment pairs with immutable snapshots |
| `state_workqueues.nim` | Chapters 14/15 fixed epoch rings, retained ordered reports, canonical dependency/accumulated package sets |
| `state_statistics.nim` | Chapter-13 E4 validator counters/service keys, natural core/service values and immutable snapshots; compact gas accepted per vectors, no fallback |
| `state_privileges.nim` | Chapter-12 E4 role services, fixed core assigners and canonical E4-service/E8-gas dictionary |
| `state_availability.nim` | Chapter-10 fixed optional core slots, full guarantees and E4 registration timestamps |
| `state_history.nim` | Chapter-3 recent records, package dictionaries and optional MMR belt peak encoding |
| `state_disputes.nim` | Chapter-5 canonical judgment/offender sets, whole-parent preflight and immutable snapshots |
| `state_consensus.nim` | Chapter-4 pending roster, ring commitment, tagged fixed schedule and ticket accumulator |
| `state_safrole.nim` | State entropy, full staging/active/previous validator rosters and E4 timeslot |
| `c2_records.nim` | Standalone availability, deferred transfers, immutable operands and tagged accumulation inputs |
| `collections.nim` | Canonical typed sets and dictionaries over natural/fixed unsigned/fixed-octet scalars |
| `bitstrings.nim` | Strict Boolean prefixes, fixed/variable packed bitstrings and immutable bit owners |
| `bounded.nim` | Bounded byte strings and homogeneous fixed-width sequences |
| `composite.nim` | Optional blobs, work-output variants and preimage extrinsics |
| `work_digest.nim`, `work_report.nim` | Complete nested work digests/reports |
| `tickets.nim`, `guarantees.nim` | Ticket records and immutable report guarantees |
| `block_codec.nim` | Complete extrinsics/blocks over schema-bound immutable child components |
| `header.nim` | Full/signing headers, epoch/winner markers, fixed tickets and retained views |
| `work_package.nim` | Context, packed import references, input commitments, items and retained packages |
| `disputes.nim` | Ordered verdicts/judgments and culprit/fault evidence with immutable snapshots |
| `assurances.nim` | Ordered validator indices, fixed profile bitfields and signatures |
| `owned.nim`, `report_owned.nim` | Immutable ARC snapshots and owner-bound extraction |

Use nominal wrappers for protocol indices, hashes, widths and resource limits. General naturals
select `ok` before value/consumed fields; container/composite/owned APIs select their successful
error branch before accessing data or progress. Failure/default branches expose only a reason.
On the Nimony port, completed families enforce this through private state and guarded accessors;
unported result families remain migration work. See [the trial record](nimony-trial.md).

Borrowed APIs require stable input/pools during the synchronous call. No detached span proves which
buffer it belongs to. For longer lifetimes, `decodeOwned*` snapshots copy and retain only the
validated prefix in private acyclic ARC storage. Metadata getters copy fixed fields/lengths;
`copyOwnedBlob` / `copyReportBlob` extract only through the matching owner. No public mutable wire
storage is exported. Last-owner destruction releases the snapshot automatically.

Encoder preflight validates all source fields, ordering, capacity, checked arithmetic and aliases
before committing any byte. Decoders consume one prefix; standalone consumers must separately
require full consumption. Assurances decode into fully owned fixed records supplied by the caller,
so no backing-buffer owner or release handle is needed for those fields. Tiny profile parameters
are 2 cores / 6 validators; full is 341 / 1023. Structural codec acceptance does not imply chain eligibility.

See `tests/test_codec.py`, `tests/test_work_report.py` and `tests/test_assurances.py` for independent
oracles, official vectors, boundary/fuzz inputs, alias probes and output atomicity checks.

[M1 coverage and scope boundaries](m1.md) distinguish implemented framing from remaining client work.

[Disputes](../spec/disputes.md) document variable judgment counts, per-section ordering, the
published sample ordering discrepancy and the contextual checks left to state validation.

[Work-package inputs](../spec/work-package.md) cover standalone components, package-wide
count/dependency/footprint/gas limits and child owners that retain their parent snapshot.

[Headers and markers](../spec/header.md) cover the exact signing prefix, variable epoch validator
counts, fixed configured winner tuples and retained views that outlive full header handles.

[Complete extrinsics and blocks](../spec/block.md) compose the existing child schemas without
an outer discriminator. Parent scans validate every child before capture; encoders revalidate
all retained children before any write. Child materialization can allocate a separate family
snapshot. The [coverage audit](codec-coverage.md) distinguishes complete published codec-family
coverage from broader state serialization and future collection schema extensions.

[General Boolean and bitstring APIs](../spec/bitstrings.md) pack bits least-significant first,
count logical bits in variable prefixes and enforce zero unused padding. Fixed framing omits the
count. Matching immutable owners expose copied metadata/indexed Booleans and support either
framing without exposing mutable packed bytes. Specialized assurance/dispute codecs retain their
existing APIs and semantics.

[Canonical collection APIs](../spec/collections.md) enforce logical numeric or lexicographic
octet order, reject duplicate keys, distinguish count-free fixed sets from explicitly variable
sets, and give dictionaries one pair-count prefix. Supported scalar families are general naturals,
E0..E8 unsigned values and fixed octets; each dictionary key/value schema is independent. Complete
preflight precedes allocation or output writes, and retained typed snapshots expose only copied
scalars/pairs. Additional child schemas require explicit codec and ownership work.

[Remaining specialized C.2 records](../spec/c2-records.md) separate fixed 104-byte availability
values from context, include the transfer/operand outer tags in their standalone wire, preserve
the 128-byte memo, and distinguish E8 transfer gas from natural operand gas. Fixed records are
independent copies; operand snapshots bind result/trace extraction to their owner. Caller blob and
wire ceilings are explicit. These codecs do not execute accumulation or verify state eligibility.

[State-layout foundation](../spec/state-layout.md) begins the separate state commitment scope:
31-byte keys, 64-byte node values and explicit partial left-child commitments. Results and metadata
are independent fixed copies, so these APIs return new values rather than mutate caller buffers.
Node hashing uses the existing Blake2b backend. The separate [trie-root API](../spec/state-trie.md)
constructs order-independent roots from borrowed serialized entries, rejects duplicate keys and
checks payload/topology budgets before hashing. Source storage must stay stable for the synchronous
call; returned roots are independent fixed copies. [State-component codecs](../spec/state-safrole.md)
cover chapters 6–9 and 11, with immutable decoded validator snapshots and copied field access.
[Authorization state codecs](../spec/state-authorization.md) add chapters 1–2 with per-core
pool framing, fixed queues and private owner-bound copied hashes.
[Safrole basic-state codecs](../spec/state-consensus.md) add chapter 4 with whole-parent preflight,
retained immutable children and selected-variant copied extraction.
[Dispute state codecs](../spec/state-disputes.md) add chapter 5 with four independently sorted sets
and nominally separate report/key extraction.
[Recent-history state codecs](../spec/state-history.md) add chapter 3 with whole-parent preflight,
key/value association and owner-bound optional peak copies.
[Availability state codecs](../spec/state-availability.md) add chapter 10 with shared standalone
guarantee records, whole-parent preflight and independently retained child reports.
Other state serialization, proofs and persistence remain future work. Run these native suites after
building the primitive bridge.

The Nimony owned-snapshot port and its retained-lifetime, result, metadata and copy contracts are
recorded in [owned snapshots](../spec/owned-snapshots.md). Complete work-report codecs and report-owned snapshots now pass their independent corpus and
lifetime/guard checks; see [the trial](nimony-trial.md). Assurance encoding, decoding and inspection
also pass their independent corpus with guarded progress results. Guarantee sequences and
standalone records now pass wire/semantic, inspection, parent/child lifetime and result checks.
Ticket encoding, decoding and inspection also pass their independent corpus, including lifetime,
atomicity, alias and guarded-progress checks. Dispute verdict/evidence snapshots, inspection,
result safety and release checks now pass as well. Work-package inputs and retained package/item
snapshots also pass their complete independent corpus, guarded import alternatives and release
checks. Full/signing headers, optional markers, retained views and selected-alternative guards now
pass their complete corpus and release checks. Complete extrinsic/block composition now passes
its independent corpus, nested cause/result guards, cross-child alias checks and retained-child
release workload. Strict Booleans and fixed/variable packed bitstrings now pass their independent
corpus, guarded results and snapshot release checks. Canonical scalar sets and dictionaries now
pass their complete corpus, closed schema checks, guarded results, private-storage aliases and
snapshot release workload. C.2 availability specifications, transfers and accumulation input
records now pass their complete corpus, guarded source/decoded alternatives and release checks.
The raw crypto primitive dependency now passes its vector, result, seed-erasure and thread checks.
State keys and fixed node layout/hashing now pass their complete independent corpus, fixed-copy,
result/variant, backend-failure and nominal-domain checks. Bounded trie roots now pass their
complete independent corpus, preflight, result, scratch-release and nominal-domain checks.
Entropy, validator rosters and timeslot state now pass their complete independent corpus,
guarded results, retained-owner/copy checks, arithmetic and scoped release workload.
Authorization pools and queues now pass their complete independent corpus, guarded results,
retained nested-owner/copy checks, kind validation, arithmetic and scoped release workload.
Chapter-4 Safrole basic state now passes its complete independent corpus, guarded chapter-local
results, closed source alternatives, retained parent/child copies, arithmetic and scoped release
workload. The next compiler-port increment is chapter-5 dispute judgment/offender state
(`state_disputes.nim`). M1 migration remains partial.

The experimental [Nimony Linux workflow](../.github/workflows/nimony-linux.yml) now runs the
migrated runtime slice and a strict all-source semantic compilation gate independently. Linux
execution is pending CI; passing the migrated slice does not establish full M1/M2/M3 parity.
