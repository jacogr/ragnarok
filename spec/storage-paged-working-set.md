# Paged storage and bounded working sets

Status: storage-only codecs, streamed construction/admission/lookup and native immutable epoch
ownership/publication with pinned readers, captured retired-epoch reclamation, source-derived
compaction, explicit replay cleanup/bootstrap resume and process-death qualification.
Controlled Linux resource qualification is complete for the measured profile below. Application
adoption and full-node paging remain separately gated. The backend is a disk-indexed **light-evidence** store designed for selected datasets
that may exceed RAM while its
private working set remains explicitly bounded. Existing complete-image/cache and full-node
repository APIs keep their current contracts.

Authority remains the pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`
Merklization M/B/L and the [proof/trust contract](storage-light-state-proofs.md). Local page hashes,
file indexes and checksums establish storage integrity, never root provenance, finality or a
complete-state map derived from partial knowledge. Compiler, provider, allocator and upstream
pins remain unchanged. This is a local schema, not a network proof format.

## First boundary and full-node gate

The [storage direction](../docs/design/state-storage.md) separates protocol commitments from
physical layout and requires distinct full/light semantics. The current
[streaming light reopen](storage-light-streaming-reopen.md) still materializes a selected image
and cache. The [retained-layout evidence](storage-retained-layout.md) likewise leaves a complete
full-node graph resident. Neither establishes a bounded working set.

| Boundary | Paged light backend | Full-node paging |
| --- | --- | --- |
| Root authority | Independently supplied chain and well-formed complete-state root | Independently supplied complete root plus complete graph authority |
| Local key missing | UnknownKey after a checked disk-index search | Missing physical data is corruption; protocol absence requires a complete checked route |
| Admitted content | Canonical root-bound query proofs, including explicit absence | Every reachable physical record, route, child identity and retained-root inventory |
| Initial working set | Fixed page pool, bounded metadata, one proof/value at a time | Requires a separate bounded graph/visited-inventory design |
| Consumer surface | New explicit-close paged resources and owned verified lookups | No adoption by StateStore, PVM or checkpoint consumers in this tranche |

A future full-node backend must preserve full physical child identities, including the left
child bit that JAM B masks in its protocol commitment. It must verify routing, counts,
availability, duplicate/cycle rules and the complete retained-root union with bounded memory and
explicit disk scratch. A page checksum, valid root field or lazy visited subset cannot replace
those checks. This contract does not authorize a partial implementation of that full-state API.

## Chosen local V1 layout

The first layout uses **4,096-byte logical data pages**, independently of OS page size. This is
a bounded buffered-IO baseline, not a page-size performance claim. The codec implementation must
freeze independent golden bytes and reject every other schema; it may not silently reinterpret
existing light snapshots, light journals or full-node files.

All integers below are unsigned fixed little endian. E8 means eight bytes; E2 means two.
The schema strings use one LF byte for `\n`. Page digests, page ordinals, file offsets and
protocol StateRoot values retain distinct nominal roles; a page digest cannot become a StateRoot.
Let P = 4096, N be retained query count, and S be total encoded proof-record bytes.

- Page zero contains `RAGNAROK-LIGHT-PAGED-V1\n`, 32 chain bytes, 32 complete-root bytes,
  E8 positive physical epoch, E8 ordinary-update sequence, E8 N and E8 S, then zero padding.
  The fixed prefix is 120 bytes. An empty cache has N = S = 0 at any independently expected root.
- The index follows page zero: N fixed **64-byte descriptors**, strictly increasing by the full
  31-byte query key. Each descriptor is key, E8 payload-relative offset, E8 record length and
  17 zero reserved bytes. Its final page has zero padding.
- The payload follows the padded index. Each record is the existing canonical query transport:
  31-byte key, E2 node count, E8 raw-value length, canonical 64-byte path nodes and raw value.
  Descriptor and payload keys agree. Records occupy exact consecutive, nonoverlapping extents
  in index order, with no holes or aliases; only the last payload page may have zero padding.
- A complete binary digest tree follows all data pages. With G = 1 + ceil(64N/P) + ceil(S/P),
  let T be the smallest power of two at least G. Store (2T - 1) 32-byte digests in canonical
  postorder: complete left subtree, complete right subtree, then parent. Root is the final slot.
  Subtree extents and child/sibling positions are computed from T and bounded depth, without an
  in-memory tree/index. This order permits sequential tree construction with bounded carry scratch.

For Blake2b-256 H, data-page leaf i is
`H("RAGNAROK-LIGHT-PAGED-LEAF-V1\n" || E8(i) || page[P])`. Padding leaf i, for G <= i < T,
is `H("RAGNAROK-LIGHT-PAGED-PAD-V1\n" || E8(i))` and has no physical data page. An internal
node is `H("RAGNAROK-LIGHT-PAGED-NODE-V1\n" || left[32] || right[32])`. These local domains
are distinct from JAM's B/L domains. The logical file length is G*P + 32*(2T - 1), exactly.

`CURRENT` has its own exact schema: `RAGNAROK-LIGHT-PAGED-MANIFEST-V1\n`, chain[32], root[32],
E8 epoch, E8 sequence, E8 G, E8 file length, page-tree root[32], then H(all preceding manifest
bytes). It selects only `paged-<16 lowercase hexadecimal epoch digits>.bin` in the held directory.
All manifest/header/actual-length claims agree. The manifest checksum is not a trusted JAM root.
`LOCK` remains a stable regular writer-lease file; `CURRENT.next` is exclusive manifest staging.
The builder exclusively creates the immediate next canonical epoch file. Until sealing and
selection it is unselected; an existing name is never overwritten or opened as a fallback.

Count products, ceiling division, next-power-of-two growth, tree slots, relative offsets,
file offsets and native conversions must be checked **before** arithmetic, allocation or IO.
Zero entries require zero payload; each nonempty record has at least 41 bytes and at most 249
proof nodes. Reserved/padding bytes are canonical zeros. Unsupported schema, overflow, short
files, wrong extents and extra EOF bytes refuse; sparse-file holes grant no admission authority.

The independent empty witness uses zero chain/root, epoch one, sequence zero and N = S = 0.
It has one data page, T = 1, a 4,128-byte container and 193-byte manifest. All queries
are UnknownKey until evidence is explicitly retained, including at the empty complete root.
Python hashlib/struct produce:

- Page-tree root: `4fc34f4e3d1af70566cfc84c0f513c2f538adeb511f93f890df921bd85d1f093`.
- Manifest checksum: `d0a672190bbc37ce48e0944a04cabd5dfaca4a8ae87ca4477221f2b4ca573146`.
- Container SHA-256: `96196bf96f8ebc1a662a0e7bf7212c8bd751f0c5fad856a2d9bed22d87b0bfaf`.

These are independent format witnesses, not native-code execution or paging qualification.

A nonempty witness retains zero-node authenticated absence for keys beginning 0 and 128, all
remaining key bytes zero, at the independently expected empty root. N = 2, S = 82, G = 3 and
T = 4. Index descriptors occupy 128 bytes before padding. Its seven tree slots are leaf 0,
leaf 1, their parent, leaf 2, padding leaf 3, their parent, then root. The container is 12,512
bytes and the manifest is 193 bytes. Unknown key 64 remains UnknownKey. Independent values:

- Page-tree root: `65c398a5724e8de74a7e253676a8fe75e490df05318f2b0e898525e0a87fb1a1`.
- Manifest checksum: `0b685aad6b4cb1cba9a4fc4c5dead2d70bdd31423fde37f53a4281d89d296aa6`.
- Container SHA-256: `b8980831d10ff6a361b8caeb9cfca44838f9aee3c3e5ed377d32867480b31dda`.

## Logical limits and private memory

Dataset limits independently bound total file bytes, entries and logical retained values.
They may exceed the working-set allowance. Per-proof node/value ceilings remain independent
of dataset size and future mutation-batch allowances, including zero future writes.

The reader owns a finite page pool and fixed-capacity slot metadata. All cached, pinned and
in-flight buffers are charged, including index and digest-tree IO. The implementation must
preflight the pool's byte/descriptor extents, hash-input buffers, tree-depth scratch and native
handle allowance. No full descriptor table, query inventory, decoded cache, whole-file buffer
or whole-file mapping may hide outside that accounting.

A lookup reconstructs at most one bounded proof into node/value transport, verifies it, and
returns one independent owned lookup. Charge concurrent transport and verified-value copies:
up to 64*proofNodes + 2*valueBytes, plus explicit page/hash/traversal/ownership scratch. A page
hash's domain-prefix buffer is additional scratch, not an uncounted page copy. Actual native
object headers/allocation rounding must be measured separately from these logical payload bounds.
Backend allocation exhaustion retains the existing fail-stop policy; this adds no recoverable allocator.

Cache capacity zero means uncached reads through a finite IO workspace. It never means unlimited
retention. The first replacement policy is deterministic round-robin over eligible private slots;
failed/unverified pages are never installed. Limit checks precede allocation and disk work. One
owner's bounds do not cap process RSS: caller-retained owned results, simultaneous reader owners,
provider/runtime allocation and kernel page cache require separate accounting and qualification.

## Strict open and authenticated disk lookup

The public paged reader is distinct from PreparedLightSnapshot and LightStateCache. Opening it
must not construct either complete representation internally. The caller supplies the expected
chain/root and all policies; file metadata never supplies those expectations.

Strict open performs a complete **bounded-memory** pass before returning a usable reader. It
checks format/shape, all index ordering and coverage, every proof at the expected root, every
page/tree digest, counts, padding and actual EOF. Tree verification uses bounded traversal/carry
scratch, not an O(G) visited/hash array. One proof and bounded windows retire before the next.
Open work scales with the dataset; it is neither constant-time nor a lazy trust shortcut. A late refusal exposes no
reader or partially authenticated cache and retires acquired resources without changing bytes.

After open, fixed-width disk binary search finds a query without loading the index. Every
fetched data page is authenticated through the on-disk digest path to the reader's cached root;
that root binds the already checked header, index and payload. File offsets and page roles are
checked before each read. A cache hit remains tied to that exact epoch/root/file incarnation.
Held inode/name/extent and final EOF checks detect replacement, shrinkage and growth. Recomputed
checksums in modified files cannot replace the cached digest root or the caller's state root.

A cache miss performs bounded IO. It is not UnknownKey. Only a checked index search that finds
no retained query returns UnknownKey. A located entry must still verify against the exact query
and independently expected complete root before returning Present, present-empty or authenticated
Absent. The first cache retains authenticated page bytes, not an unbounded table of verified
lookup owners. Proof/provider/IO failure never becomes local missing data or protocol absence.

Default/closed resources return Uninitialized. Typed reasons distinguish UnknownKey, policy/work
limits, unsupported schema, identity mismatch, corruption/proof refusal, provider refusal, native
IO, Busy and stale position. Pure quota/provider refusal installs no partial output. Integrity,
inode/extent or native-read uncertainty poisons further fresh reads until explicit close and strict
reopen; previously returned owned lookups remain valid. Failed/default result payloads and
selected proof-reason accessors remain private and success-guarded.

## Reader pins and reclamation

Paged readers are explicit-close, move-only native owners. They own their immutable epoch handle,
read pin and bounded cache independently of the writer. They remain bound to the captured root,
sequence and epoch across publication and writer close. They do not silently follow a new CURRENT.
Lookup/proof byte extraction is owned; no borrowed cache page can escape a call or pin a slot.
Returned owned lookups survive reader close and file removal.

Use a shared advisory pin on the immutable epoch file and an exclusive, nonblocking pin for
reclamation. Before deleting an old file, the writer holds the stable directory writer lease,
revalidates CURRENT/selected data, refuses the selected/future epoch, and acquires the old epoch's
exclusive pin. Any live reader makes cleanup Busy without unlinking that epoch. Independent
readers hold independent descriptors; no resource-owner copy duplicates close authority. Native
lock/retirement behavior must be qualified on supported Linux/macOS; unsupported platforms refuse.

To open a current reader, read/validate CURRENT, open and pin that exact regular no-follow epoch,
and reread CURRENT. If the selection changed during acquisition, return StaleView and release
resources, without fallback/retry. Successful acquisition fixes that immutable selection; later
publication may advance CURRENT while the bounded verification pass completes. Final validation
still checks the pinned epoch and its complete extent. Writer cleanup honors the pin throughout.
No selected file is modified in place, and no in-place shared-to-exclusive lock upgrade is assumed.

Closing retires handles even after poison and reports native failures without retrying a reused
fd number. Resources/leases remain acyclic; cached pages own no writer, callback or reader cycle.
The implementation must prove actual ARC copy/move/lowering behavior, not only semantic checking.

## Streamed construction and atomic selection

The initial writer builds full immutable replacements, not an incremental paged journal. A bounded
replayable producer supplies a declared count/payload extent and strictly sorted query proofs,
one stable borrowed input at a time. Every pass binds the same canonical stream with bounded
streaming-digest scratch; changed input refuses sealing. Actual counts, every proof and the
exact final extent must agree; an early end, extra entry, duplicate/out-of-order key or late provider failure refuses the whole build.
The builder cannot stage a complete detached proof batch, cache or in-memory sort. Large fixture
production must likewise be streamed or kept outside the measured reader process.

Build IO is explicit. With N/S known and bounded, write the complete header and index in one
producer pass, then matching payload in another, and finally the postorder tree through bounded
body reads/carry scratch. Emitted file bytes are always a canonical prefix: no reserved sparse
holes, header rewrites or random tree writes. Validate each emitted proof before its payload and
fully check the completed file/tree before sealing. Only synchronized file/directory completion
produces an opaque sealed-artifact owner. This owner retains its exclusive native artifact pin;
sealing is not CURRENT publication. Raw bytes, a ready flag or a checksum cannot manufacture it.
A failed result never carries a partial artifact: an acquired authoring owner must be closed
explicitly, preserving its unselected forensic files.

Publication binds the exact source selection, root/chain, epoch/sequence, file incarnation/extent,
all inherited policies and one live sealed-artifact incarnation. Passive prepared metadata never
duplicates native ownership. Closing/reopening an artifact requires fresh validation/preparation;
it cannot revive an old capability through equal counters or a reused descriptor. Before selection,
revalidate held source and candidate bytes against their cached complete page roots with bounded
reads and actual EOF. A live checked seal may avoid repeating target proof verification when its
exact bytes still match; freshly opening an artifact requires full proof verification.

All selected data and the complete digest tree become durable before the bounded manifest is
staged, synchronized, atomically renamed to CURRENT and the directory synchronized. Only confirmed
selection changes the writer's visible head. IO uncertainty yields no fresh head/receipt and poisons
fresh writer observations until explicit close/reopen. Post-confirmation artifact/old-handle
retirement is reported separately and cannot erase a confirmed selection. Retained reader pins
remain bound to old epochs; cleanup is explicit and bounded, with synchronized absent-name retries.

Initialization starts at epoch one/sequence zero. Full same-root evidence replacement advances
sequence once, including a requested no-op. Explicit compaction preserves root, exact knowledge
and sequence, and must derive its stream from a held checked source reader; equal state roots
alone do not prove equal retained knowledge. A root change requires a separate explicit destination
root and wholly reverified destination evidence, preserving the ordinary-update sequence as in
[light-root advancement](storage-light-root-advancement.md). Every selection advances physical
epoch once. Exhaustion refuses before build IO/hash; no counter wraps or implicit root/proof carry.

Ordinary open consults only CURRENT and never adopts a staged candidate. Unknown/unsealed build
files block conflicting creation and remain forensic evidence. Partial-build cleanup requires
an explicit expected source position, independently expected destination root/counts/policy and
a replayable fully verified target producer. Reconstruct its canonical bytes/digests with bounded
passes, and compare the actual held candidate against exactly that complete-file prefix, including
possible partial page/digest bytes. Root and target shape are never inferred from the candidate.
Hold its exclusive pin, revalidate name/inode/extent/EOF and source selection, and preflight the
bounded CURRENT.next prefix against the reconstructed final manifest before any unlink. The
opaque cleanup owner retains that validated inode/position, not the producer or whole dataset.
Already-absent names still receive final synchronization. Without matching producer authority,
or on any unknown prefix/policy/provider/IO mismatch, preserve all candidates and return a typed
refusal. Invalid or nonreproducible builds may therefore need separately authorized administration.
Complete sealed-candidate cleanup uses its checked capability with the same source/pin/preflight
rules. Directory scans, arbitrary epoch deletion, in-place page reuse and conversion of existing
databases are outside this first layout.

## Completion and evidence gates

The contract formed layer eleven on native stack #1395, after ten earlier published layers.
The total cap remains **15 PRs**, including this contract. Subsequent coherent units cover the
paged codec/digest/index boundary, streamed construction and bounded reads, native publication/
reader-pin lifetime, and grouped process/resource qualification. Supporting guards/tests/docs stay
with their implementation concern. Each ready unit is published before starting the next; the cap
never licenses dropping validation or fragmenting cases into individual PRs.

Required implementation evidence:

1. Independent byte witnesses for empty and nonempty artifacts/manifests; every truncation,
   trailing byte, reserved field, ordering/descriptor/page/tree error, count/offset/power-of-two
   overflow and recomputed-checksum false proof. Wrong-mode/root/chain and preallocation limits
   refuse without hidden conversion. Include 249-node paths and values crossing page boundaries.
2. Independent complete-map proofs and cache/image comparisons on small fixtures. All resident
   page capacities, including zero cache, agree on Present/empty/Absent/Unknown, root, sequence
   and canonical proof bytes. Exact/short work budgets, provider refusal at each observed stage,
   caller/output mutation and cold-lookup IO faults expose no partial successful prefix.
3. Actual resource-owner copy/lowering rejection, private/default result guards and positive
   controls. Run at least 1,000 open/read/evict/refuse/close cycles after all extraction temporaries
   retire. Check native handles, locks and ARC occupancy; no retained page or whole-index growth.
4. Real concurrent reader pins versus replacement, writer close and old-epoch reclamation,
   including another process. Qualify every observed build/selection/close/cleanup syscall boundary
   and positive short-write chunk with exact stopped-child/kill/reap controls, unchanged forensic
   bytes, strict independently expected-root reopen and explicit permitted recovery. Process death
   remains distinct from hardware/filesystem power loss; cleanup needs explicit matching producer
   or sealed-artifact authority.
5. Serial fresh-process resource panels with fixture production excluded, exact source/compiler/
   provider/binary identities, independent query results and native bytes/pages/hash/cache counters.
   Bound private buffers and metadata as N grows under a fixed working budget. Qualify any actual
   larger-than-RAM claim on controlled native Linux with a populated selected dataset larger than
   the enforced no-swap allowance, spread/cyclic reads, deadlines and exact kernel receipts.
   Distinguish completion, typed resource refusal, OOM kill and timeout; fresh processes alone do
   not prove cold filesystem/device caches. Keep optional pressure work out of routine CI defaults.

No performance or deployment-ceiling conclusion follows from this contract or a small functional
fixture. Existing M1 framing/implemented-scope completion remains distinct from complete JAM state
serialization and whole-client parity. Startup, StateStore/PVM/checkpoint adoption, network proof
fetching, trust selection and full-node paged graph validation retain their separate scope gates.

## Implemented format boundary

`src/storage/paged_codec.nim` implements checked scalar geometry, exact header/descriptor/CURRENT
codecs, one-record proof-transport framing, a constant-space first-error index scan and fixed-depth
postorder digest-path planning/verification. Dataset arithmetic checks unsigned overflow and signed
native addressability before evaluating offsets. CURRENT can be decoded against independently
expected chain/root before opening an epoch; `validatePagedBinding` subsequently compares every
shared header/selection field. Header counts and proof limits remain mandatory separate checks.

All successful metadata/results have private fields and success/initialization-guarded accessors.
Encoded transport is detached; page ordinals, offsets and local digests retain distinct nominal
roles. The hash adapter uses 4,133 bytes of explicit page/domain scratch, with bounded scalar/path
state and primitive-owned scratch additional. These are algorithmic codec extents, not a measured
backend working set or process RSS ceiling. No native resources or dataset-sized arrays are owned.

The native `storage_paged_codec` suite reproduces the independent empty/two-absence witnesses,
checks every fixed-header/descriptor/manifest prefix and reserved byte, exact/trailing widths,
identity/geometry/counter mismatches, count/page/power-of-two/offset limits and one-record framing
through 249 nodes and cross-page values. An independent explicit postorder-tree oracle checks
all real leaf/sibling positions across fifteen geometries; scalar-only deep geometry covers
2^60 payload bytes without allocating the dataset. Changed pages/siblings/roots and provider
refusal at each observed hash stage produce typed failure. Full-key ordering, gaps, aliases,
missing/extra rows, empty and sticky failed scans are covered.

Local verification uses `make unit SUITE=storage_paged_codec`, `make check-inventory` and the
pinned formatter check. The selected strict guard runners cover ten runtime refusals with nine
successful controls, five private-field rejections and two exact nominal call/position rejections.
The native suite includes 1,000 complete codec/release cycles with all transport retired before
ARC samples; observed live occupancy remains 192 bytes before/after in the checked ARC/Clang
release build on macOS arm64. No Linux paging or above-RAM result follows.

The format codecs establish scalar shape and local integrity. Complete query-proof and artifact
admission belong to the dependent synchronous stream boundary below. Native publication, reader
pins, recovery and process/resource qualification remain separate gates.

## Implemented synchronous stream boundary

`src/storage/paged_stream.nim` builds, completely validates and searches paged-light bytes through
borrowed synchronous exact-read/actual-EOF callbacks and an append-only sink. No callback, native
handle, directory, lease or resident descriptor inventory is retained in `CheckedPagedArtifact`.
This opaque copied metadata binds complete admission, exact header/manifest, captured tree root
and inherited policies; it is **not** a sealed native artifact, pinned reader or publication plan.

Construction starts only from an empty sink and checked declared geometry. Pass zero writes the
header and sorted descriptors; pass one writes canonical payload records. Each proof is verified,
each pass has an exact explicit end marker, and consecutive proof extents cover the whole declared
payload. Canonical padding and iterative postorder carry construction follow. The completed file
is then completely re-read under the same finite operation budget before success. No temporary
full image, sorting inventory, sparse reservation, header rewrite or random tree write is used.
Failed construction preserves its emitted bytes and returns no partial artifact or implicit repair.

The private producer fingerprint starts at zero; for each canonical record R, the next fingerprint
is Blake2b-256(`RAGNAROK-LIGHT-PAGED-STREAM-V1\n` || previous[32] || Blake2b-256(R)[32]).
Both producer passes **and the authenticated completed-file record stream** must agree. Equal
complete-state roots alone cannot authorize a different retained knowledge set or changed proof
transport. The fingerprint is private construction metadata, not another stored/network schema.

Complete admission checks actual EOF, header/manifest binding, every descriptor in strict key
order, exact consecutive coverage, every canonical proof at the independent root, all zero padding,
every actual/synthetic leaf and stored postorder digest, the complete captured tree root and final
actual EOF. Proof-scan bytes authenticate to that captured root **before** proof verification;
a raw proof pass followed by a hash pass cannot combine inconsistent source views. One bounded
record fingerprint buffer is allocated only after proof/verified-value temporaries retire.

`lookupPaged` authenticates the captured header and fixed-row binary-search pages without loading
the index. It returns UnknownKey only after a checked missing-key search and final EOF check.
Located records are framed before allocation, reconstructed one at a time and fully proof-verified;
owned results distinguish Present, present-empty and Absent and outlive all source callbacks.
Changed bytes, read/EOF uncertainty and provider failures never become local missing data or
protocol absence. Native wrappers must additionally enforce immutable file identity/pins and
latch uncertainty; these synchronous metadata algorithms do not own a poisonable native resource.

This first buffered engine explicitly supports zero or one private cache slot per operation;
larger cache policies refuse. Zero means transient buffered IO, not unlimited retention. Every
cache miss authenticates before installation. There is no cross-call cache or borrowed-page result.
A conservative 32,768-byte logical fixed-workspace reservation plus
`41 + 2*(64*proofNodes + rawValueBytes)` bounds algorithmic proof/transport payloads before their
allocation. Runtime/object/allocator/provider overhead and caller-retained results remain separate;
this reservation is not a measured native RSS ceiling. Dataset bytes/entries and per-proof bounds
are independent from aggregate IO-call/read/write, producer-call, local-hash, proof/node and value
work limits. Known dataset/total-write/fixed-workspace refusals precede IO; each later operation reserves
its own quotas before the corresponding IO, allocation or cryptographic work. Successful passive
counters separate local layout/record-binding hashes from proof-node/value cryptography.

The `storage_paged_stream` native suite uses an independent resident test-only byte/tree oracle,
an independent complete-map root and existing resident cache/image semantics. It covers empty and
nonempty artifacts, present empty values, cross-page 4,097-byte values, actual 249-node proofs,
250-node refusal, both supported cache policies and sorted fixtures through 1,000 queries.
It rejects every proper prefix of the 12,512-byte absence fixture, extra EOF bytes, rehashed false
proofs, malformed descriptors/counts/padding and every stored tree slot mutation. Changed producer
knowledge and a different valid same-root on-disk knowledge set refuse. Hostile mixed proof/hash
views cannot bypass admission. Every observed append/read/EOF boundary, positive short-append
prefix and provider-hash failure is exercised, including missing-key search failures and final-EOF
growth. Exact observed budgets pass and one-short positive channels refuse for build/admit/lookup;
workspace exact/short and dataset refusal before IO have separate controls.

Local verification uses `make unit SUITE=storage_paged_stream`, inventory/format checks and the
selected strict runtime/privacy runners: seven runtime refusals, five actual successful controls
and six private-field compiler rejections. The checked ARC/Clang release run on macOS arm64
completes 1,000 build/admit/lookup/refuse/release cycles with live occupancy unchanged at 9,296
bytes before/after, after all per-cycle source/callback/transport/lookup owners retire. Native IO
syscall ownership, process crashes, publication,
reader pins, replay-bound partial cleanup and controlled Linux working-set/RSS qualification are
still required. Resident callback fixtures and successful algorithm tests do not establish disk
lifetime, power-loss durability or larger-than-RAM operation. Existing M1 framing completion
remains distinct from complete state serialization and whole-client parity.


## Native owners, selection and captured reclamation

`src/storage/paged_io.nim` and `paged_store.nim` add the native storage-only boundary. The supported
local filesystem profile is Linux/macOS with directory-relative no-follow regular-file opens,
independent open-file-description `flock` pins, atomic same-directory rename and file/directory
`fsync`. One caller serializes operations on each owner; callbacks remain synchronous and cannot
retain the borrowed IO. Filesystem mutation by an external noncooperating writer during an
operation is outside this ownership profile. Named-inode/held-inode, namespace, tracked extent,
actual EOF and sealed nanosecond modification-time checks detect substitution or uncertainty
before reuse. No directory walk, full artifact read, mmap, whole index or whole dataset is owned.

`PagedDirectory`, `PagedFile`, `PagedWriter`, `PagedCandidate` and `PagedReader` are move-only,
explicit-close owners. Failed authoring may leave a live candidate and failed bootstrap may leave
a live writer; callers must test `opened` and explicitly `close` on every exit. Closing preserves
forensic files, marks retirement before native close, reports failure and never retries a retired
fd number. Candidates retain a stable private writer incarnation, not a reusable fd number or a
lease after writer close. Reopening the same root/epoch cannot revive that candidate capability.

`initializePagedWriter` exclusively creates a private namespace, persistent LOCK and epoch one at
ordinary sequence zero. `openPagedWriter` takes LOCK exclusively and admits CURRENT only under
independently supplied `PagedNativeConfig` chain/root and exact stream policies. `openPagedReader`
reads CURRENT, opens an independent shared epoch pin, rereads CURRENT for exact equality and fully
verifies all bytes and proofs. A changed selection refuses admission without retry. Temporary
namespace handles retire before reader success. Each reader owns its own epoch and directory
handles; writer selection/close does not revoke old readers or independently owned lookup bytes.
Readers expose retained absence, present-empty and `UnknownKey` with their existing distinctions.

`preparePagedReplacement` creates epoch+1 with sequence+1, including requested equal evidence.
`preparePagedAdvance` requires an explicit different destination root, fresh complete evidence and
preserves ordinary sequence. Epoch/sequence exhaustion refuses before producer/hash/build IO.
The replay-bound streaming engine authors and checks the file; file and directory barriers precede
sealing. Failed authoring is never a seal, never overwrites an epoch, and leaves an explicit-close
forensic owner. Work budgets apply independently to each synchronous stream phase, including the
finite number of complete source/candidate revalidations in a composite native operation; they
are not a single aggregate native-operation quota or a measured process RSS cap.

`publish` requires the live sealed candidate, exact original writer incarnation/source position,
namespace and policies. It completely revalidates source and candidate, writes/fsyncs/closes
CURRENT.next, rechecks source and candidate identity, renames and fsyncs the directory. Failure
before confirmation grants no new head/receipt; publication uncertainty poisons the writer until
explicit close and strict reopen. An existing CURRENT.next blocks selection and remains intact.
After confirmed rename/directory sync, `PagedPublication` always retains the confirmed manifest and
`FileAndDirectorySynced` durability, even if subsequent candidate/old-head retirement or new-head
pin acquisition fails. Its separate `retirementError` and `writerUsable` report that outcome; an
unusable writer requires close/reopen. Pure provider/quota refusal preserves an otherwise checked
reader/source; inode/extent/read uncertainty latches until strict reopen.

`epochReceipt` captures a reader's checked epoch, exact inode/namespace and inherited policies.
`reclaim` takes that passive receipt plus the independently expected current manifest. It refuses
selected/future epochs, another directory/policy, stale current positions and unknown staging files.
It revalidates the current source, acquires an independent exclusive nonblocking old-epoch pin,
checks the receipt's actual inode/version and all old bytes/proofs, rechecks CURRENT, then unlinks
only that canonical captured old name and syncs the directory. Busy readers prevent deletion.
Already-absent retries still synchronize the captured namespace. A post-confirmation close error
is a separate successful-reclamation diagnostic; uncertain unlink/barriers require strict reopen.

The initial native layer does **not** implement sealed/unsealed candidate recovery or replay-bound
partial-build cleanup. Source-derived compaction is implemented by the subsequent boundary below. Ordinary open never adopts or deletes candidates;
conflicting next-epoch and staging names remain forensic and block creation/publication. The
contract's producer-bound cleanup, process crash schedules, Linux descriptor/RSS/page/cache
accounting and populated larger-than-RAM qualification remain completion gates. No consumer,
full-node graph authority, compiler/provider pin or complete-state serialization scope changes.

The `storage_paged_native` checked ARC/Clang native suite covers independent rooted fixtures,
same-root and root-advance selection, retained readers/lookups, unknown versus proved absence,
writer exclusivity, stale-incarnation candidates, namespace/pending collisions, provider/quota
refusal versus IO poison, every observed publication read/write/fsync/rename/close/pin fault,
short progress/EINTR, reused-fd close, independently rehashed max counters, reclamation fault
boundaries and 1,000 open/verify/lookup/move/close release cycles. An exact stopped-child shared
pin blocks parent reclamation across publication until the child is killed/reaped. Native runtime
result/receipt and live-owner guards, private-state rejection fixtures and actual ARC lowering
rejections constrain the exported owner/result surface.

`tests/models/storage_paged_epoch_pins.nif` checks the specific reader-admission/publication/cleanup
race with separate CURRENT reads, lock acquisitions, rename, unlink and close steps. Its base
invariant passes; removing either exclusive-pin exclusion or the post-pin CURRENT recheck produces
an invariant counterexample. A reachability witness admits an old pinned reader before a later
publication. Serial and four-worker exploration agree. This bounded lifecycle evidence does not
model power loss, hostile filesystem mutation, complete proof semantics or process resource bounds.

Reproduce with `make unit SUITE=storage_paged_native`, `make check-inventory`, the discovered
`storage_paged_native` runtime/compiler guards and the `storage_paged_epoch_pins` model cases.
Local macOS results are distinct from exact-head Linux CI and future memory qualification.
Documented M1 framing completion remains separate from complete JAM state serialization.


## Source-derived compaction

`preparePagedCompaction` derives the target only from the writer's held, shared-pinned, completely
checked source epoch. It accepts no replacement producer, root, count, payload or sequence from
the caller. A physical epoch increment preserves chain, root, exact retained knowledge and ordinary
sequence, including an exhausted ordinary sequence. Physical epoch exhaustion refuses before
hash/build IO. This canonical immutable format does not promise fewer bytes after rewriting;
compaction is an explicit physical rewrite with unchanged logical knowledge.

The synchronous `compactPagedArtifact` engine authenticates source header/index/payload pages
against the captured complete page root, copies only those bounded pages, rebuilds the digest tree
for the new physical header, completely admits the finished output and compares its canonical
evidence-stream fingerprint with the captured source fingerprint. Equal JAM roots alone never
justify a different retained query set. Each operation uses the inherited dataset/proof/workspace/
cache/work limits; no producer, resident index or dataset-sized transport escapes. Source and target
native callbacks remain borrowed during the operation. Sealing and publication use the existing
explicit-close candidate, durability, source-incarnation and post-confirmation diagnostic rules.

The native `storage_paged_compaction` suite checks an independent rehashed exact artifact/manifest
witness after dropping retained absence under an unchanged root, sequence preservation, old-reader
retention, every observed preparation read/write/barrier/pin refusal, strict reopen of the original
head and 1,000 complete compaction/publication/close cycles with all transport retired before ARC
samples. Stream tests independently change the destination to another valid same-root knowledge
set, change sequence, exhaust the write budget and corrupt the captured source; all refuse without
a successful target. Existing native publication and result/ownership guards remain applicable.
Reproduce with `make unit SUITE=storage_paged_compaction`, `make unit SUITE=storage_paged_stream`
and `make unit SUITE=storage_paged_native`. This does not qualify process crashes, bounded Linux
RSS, larger-than-RAM data or candidate recovery. Those remain separate completion gates.

All fourteen layers of the original native stack #1395 were merged before this continuation.
New coherent outstanding-work units start from merged master in a new native stack, capped at
fifteen simultaneously stacked PRs; completed/merged history is preserved without branch pruning.


## Explicit sealed and replay-bound candidate cleanup

`discardPagedCandidate(writer, candidate, expectedSource)` consumes a live sealed candidate only
under its exact source selection and original writer incarnation. It revalidates source and target,
preflights any staging prefix against the complete seal, checks held inode/version/namespace/extent and rechecks CURRENT before
unlink. It never follows an equal root to a new physical head. Failed authoring is not a seal and
cannot be discarded by this path without independent replay authority.

`preparePagedCleanup` takes an independently expected source manifest, target header and stable
replayable proof producer. Target root, chain, epoch, sequence, counts and geometry are never read
from the candidate. Exact inherited limits come from the writer. A target is source epoch+1;
replacement advances sequence once, root advancement preserves it, and same-root/same-sequence
compaction additionally requires the exact admitted source evidence fingerprint. Source exhaustion,
invalid transitions and stale expected positions refuse before replay/build IO.

The producer is completely verified into bounded anonymous temporary transport. libc `tmpfile`,
an independent atomic-CLOEXEC descriptor and checked FILE retirement leave no database scratch
name; descriptor-local append flags preserve canonical builder output across verification seeks.
Scratch bytes are bounded by the dataset/write policy and resident state remains fixed scratch plus
one bounded proof/value. This uses temporary disk space up to the complete expected artifact; it
does not materialize the artifact in RAM or require scratch durability. Scratch filesystem/IO or
retirement failure refuses preparation. Unnamed scratch is retired on all failures/process deaths.

An independent exclusive pin captures the optional next-epoch file. Every actual byte must equal
the corresponding complete expected-file prefix, including zero bytes, a partial page, proof or
digest word; overlong/foreign bytes refuse. The optional fixed CURRENT.next file also needs an
exclusive pin, bounded extent and exact reconstructed manifest-prefix match, including partial
checksum bytes. Prefix comparisons have explicit read/call preflights under inherited work limits.
Every file is preflighted before either can be unlinked. Successful preparation returns only an
opaque explicit-close `PagedCandidate` cleanup capability; it retains captured pins/metadata and
original writer incarnation, not the producer or scratch file, and cannot be published as a seal.

Discard rechecks all retained inode/version/extent bindings and the source selection. Captured
absence cannot authorize a subsequently created epoch or staging file. It removes only the exact
captured next epoch and optional staging name, synchronizes their directory and performs a final
barrier even on already-absent retries. Partial unlink/barrier uncertainty returns no successful
cleanup receipt and requires explicit close/strict reopen/fresh replay. Confirmed cleanup survives
subsequent descriptor-retirement failure through the receipt's separate `retirementError`.
`alreadyAbsent` describes the target epoch; a staging prefix may still have been removed.

`resumePagedInitialization` is a separate explicit operation for an existing interrupted bootstrap
namespace with persistent LOCK and absent CURRENT. Independent config/root/counts/producer define
epoch one/sequence zero. It reproduces and checks the initial candidate/staging prefixes, captures
absence again before unlink, rebuilds and publishes only after the new complete manifest matches
the replay witness. A producer changing to different valid same-root knowledge between builds
refuses publication. Existing CURRENT always refuses this operation; callers must use strict open
with independent expectations. A namespace interrupted before its persistent LOCK exists, invalid
or nonreproducible files, and unrelated unknown files retain their forensic/admin boundary. Ordinary
open never invokes any recovery, deletes a prefix, adopts staging or infers a root.

The checked native `storage_paged_cleanup` suite covers sealed discard, every manifest-prefix length,
page/digest fragments, independent mismatches, unchanged forensic bytes on refusal, stale writer
incarnations, captured-absence substitution, late staging mutation, explicit root advancement and
compaction knowledge checks, every observed prepare/discard syscall refusal, early/late provider
refusal, write quota preflight, bootstrap resume, changing producers and selected-target protection
after uncertain publication. It includes 1,000 replay/prepare/discard lifetimes with complete ARC
release. Existing owner/result runtime guards, privacy and actual ownership lowering remain part
of this boundary. Reproduce with `make unit SUITE=storage_paged_cleanup` and the affected paged
stream/native/compaction suites. This source-owned evidence does not yet establish process-crash
or Linux RSS/larger-than-RAM qualification; those are the next grouped validation units.


## Process-death qualification

`storage_paged_crashes` supervises exact forked children with the existing successful-syscall
observer. A private witness, verified stopped status, exact SIGKILL and reap distinguish every
crash from a positive completion control or timeout. The parent proves writer-lease contention
while each child remains stopped. Namespace construction and strict source reopen precede the
armed region, except explicit bootstrap operations whose complete lifecycle is under test.

The suite schedules every observed successful write, fsync, rename, unlink and descriptor close
for initialization, replacement, independent-root advancement, exact-source compaction, replay-bound
candidate/staging cleanup, interrupted-initialization resume and captured retired-epoch cleanup.
Positive short writes additionally stop inside pages and digest words. Independent oracle bytes
constrain CURRENT to the old or complete new manifest, every candidate to its exact authored
prefix, and every surviving old file to its original bytes. Wrong-root and correct strict reopen
preserve all known forensic files and perform no repair. Explicit complete replay cleans an
unselected target before reauthoring; absent bootstrap CURRENT requires explicit initialization
resume. Selected files can never become cleanup candidates. Already-absent retirement retries
synchronize the directory, independent retained readers still serve old-root values, and unrelated
siblings survive.

Reproduce with `make unit SUITE=storage_paged_crashes`. This checked native suite qualifies
process death on the tested filesystem, including all actually observed operation boundaries; it
does not simulate power loss, device caches or storage reordering. The serial fresh-process Linux
RSS/descriptor/cache panel and populated dataset larger than enforced no-swap RAM remain the
remaining working-set completion gate. Consumer adoption remains separately gated.


## Serial populated-data resource panel

`make build-storage-paged-resources` builds the optional checked ARC/Clang ThinLTO probe.
The dedicated Docker `paged-resources` target provisions the same pinned tools and frozen
probe without building unrelated transport code. `make bench-storage-paged-resources` runs the
host observer against `PAGED_STORAGE_IMAGE` (default `ragnarok:paged-probe`). Python, compiler
verification and full provenance checks remain outside pressure; only native storage processes
and a tiny persistent native supervisor live in the constrained container. This optional panel
stays outside ordinary CI defaults and speed benchmarks.

The observer resolves an immutable image ID, verifies its complete source/compiler/provider/
observer/binary closure outside pressure and compares every source identity with this checkout.
It creates a randomly named private Linux cgroup2 container with exactly 64 MiB memory.max and
zero swap allowance. Actual exec membership, mount roots, memory controls/current usage/events,
Docker state and bounded native RSS/fault observations remain raw report evidence. Missing
controls, typed native refusal, OOM and timeout cannot produce a successful result. Cleanup stops
only that owned container after retaining available failure evidence. A local direct run using
`--run-only --local` records measurements without Linux/larger-than-RAM claims.

The source plan runs 16,384 and 327,680 records with both zero and one page of backend cache under
the same 65,536-byte logical workspace and finite dataset/proof/work budgets. An independently
computed complete two-entry nonempty JAM map anchors three constant-size proof templates. One
present value has 4,097 bytes and crosses pages; a separate present-empty leaf and spread absent
queries cover positive/empty/negative evidence. A numeric sorted producer changes only each
query key, with no dataset-sized sequence, resident index or complete proof batch.

Each private selected namespace is first written inside the same persistent constrained cgroup
that later admits it, preserving page-cache charge ownership across fresh native writer/reader
processes. The writer fully verifies/publishes, closes and exits before the fresh reader starts.
Strict admission verifies the whole populated artifact; 1,028 deterministic spread/cyclic queries
check retained presence/absence, plus present-empty and unretained UnknownKey. Selected bytes
remain identical through fixed 64 KiB streamed SHA-256 comparisons on the external observer.
The small artifact has 3,895,264 bytes/935 body pages; the large artifact has 78,458,848 bytes/18,643
body pages, exceeding the enforced 67,108,864-byte no-swap allowance.

Native receipts record selected bytes/pages, actual IO/crypto calls, ARC live bytes, descriptors,
and SDK getrusage RSS/fault samples after all storage work and retirement, before final receipt
formatting. The kernel hard limit also covers that fixed telemetry postlude. Every measured heap
allocation and descriptor must retire, and retained native heap stays below the same fixed bound
at both cardinalities. Native RSS includes runtime/provider/translator resources; it is separate
from ARC, logical scratch/cache reservations and kernel file cache. Fresh processes establish a
cold backend cache; OS/device caches remain unchanged. The report records observer and Docker
engine/target architectures. Emulated Linux results establish no bare-metal speed or deployment
ceiling, and successful process-death tests do not establish power-loss durability.

To reproduce from the current checkout:

```sh
docker build --platform linux/amd64 --target paged-resources -t ragnarok:paged-probe .
make bench-storage-paged-resources PAGED_STORAGE_IMAGE=ragnarok:paged-probe
```

Raw commands, exact frozen inputs, native receipts, kernel context, file hashes and success/failure
reports are retained in a unique `build/tests/storage-paged-resources/docker-*/` folder. Full image
build and provenance verification run outside the constrained scope; build failures must be fixed
before the measurement. The initial attempt placing Python inside 64 MiB was correctly classified
as OOM before measurements; it grants no successful resource claim. The native-only design retains
the original backend limits and populated workload while excluding observer overhead.

## Measured Linux completion evidence

The complete serial panel passed on Linux cgroup2, with x86-64 ELF execution under QEMU on an
aarch64 Docker engine. Ubuntu/Rust/Nimony/provider pins and checked ARC/Clang ThinLTO flags stayed
unchanged. A separate bounded positive allocation completed; an isolated 128 MiB allocation under
64 MiB produced both exit 137 and a confirmed Docker OOMKilled receipt. The earlier Python-inside-
pressure attempt was an observed OOM before storage measurements and is excluded from success.

| Records | Backend cache pages | Selected file bytes | Writer sampled peak RSS bytes | Reader sampled peak RSS bytes |
| ---: | ---: | ---: | ---: | ---: |
|16,384 |0 |3,895,264 |13,426,688 |11,616,256 |
|16,384 |1 |3,895,264 |13,357,056 |11,759,616 |
|327,680 |0 |78,458,848 |12,623,872 |12,247,040 |
|327,680 |1 |78,458,848 |12,300,288 |12,587,008 |

Every native process ran in the same persistent 67,108,864-byte cgroup with zero swap allowance/
usage and no OOM events. Independent SDK stat observations confirmed all four physical selected
file extents, including both files larger than the imposed RAM allowance. Actual memory.max
pressure events increased during the larger cases; the final observed cumulative max-event count
was 6,683, with oom/oom_kill both zero. Each selected namespace stayed byte-identical across writer
retirement and fresh strict reader admission. All 1,028 spread/cyclic queries plus present-empty
and UnknownKey checks passed in every reader.

Writer retained ARC occupancy was 10,480 bytes and reader occupancy 1,168 bytes at both
cardinalities/cache settings. Native descriptor counts went 3→7→3 for writers and 3→5→3 for readers;
all measured heap bytes returned exactly to baseline after complete retirement. These are observed
profile results, not arbitrary caller/concurrency RSS promises, cold-device measurements or
bare-metal speed/deployment ceilings. Backend IO/crypto counters and complete raw kernel receipts
remain attached to each native phase. The checked Linux process-death suite also passed all 32
completion controls and 306 exact stopped-child kill/reap cases against the same production source.

Evidence for this run is retained under
`build/tests/storage-paged-resources/docker-7eba57de21f04f839055ebb2bd3745c7/`, with the frozen image
`sha256:af51aa1d458a28241670707cd2686a33daf51248e59ec8c88eb4ea9f271fe9cb`.
Independent physical extents, interpreter identity, OOM/positive controls and Linux crash logs
are retained under `build/storage-db5-linux-*`. Source/compiler/provider/observer/binary identities
were checked before and after the panel, including exact host/image source agreement.

The outstanding storage-only paged implementation/qualification gates are complete for this
recorded profile. StateStore/PVM/checkpoint/application adoption, full-node graph paging and
hardware/filesystem power-loss qualification remain separate work. Documented M1 framing
completion remains distinct from complete JAM state serialization and whole-client parity.
