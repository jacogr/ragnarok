# Storage primitives

This folder owns the standalone incremental complete-state trie described in
[the storage direction](../../docs/design/state-storage.md). The initial module is
[`full_state_trie.nim`](full_state_trie.nim); its exact contract and verification live in
[`spec/full-state-trie.md`](../../spec/full-state-trie.md).

## Parallel work and integration boundary

The maintainer authorized db #1 to integrate the incremental trie into the in-memory
`StateStore`, coordinated with idle state #5. The [integration contract](../../spec/state-store-incremental.md)
limits this task to three PRs: public contract coverage, atomic incremental commitments with the
existing API, and consumer validation/measurements. The storage workstream owns this folder;
state #5 has no overlapping changes and leaves this tranche to db #1.

The maintainer subsequently authorized db #1's disk backend and application flag, coordinated
against state #5's now-merged checkpoint startup work. Disk owners, exact durable chain context,
native publication and memory/disk startup are covered by the [disk contract](../../spec/disk-state-store.md)
and [operator guide](../../docs/disk-storage.md). External checkpoint trust remains independent;
normal local restart preserves bounded history and explicit finality. Unrelated state/PVM work,
full/light semantics remain separate work. The subsequently authorized managed layout and
reclamation are described in the [managed operator guide](../../docs/managed-storage.md).

## Complete-state revisions

`newFullStateTrie(entries, limits)` borrows entries directly during construction, copying serialized
31-byte keys and raw values only into final immutable leaves. The
[constructor memory evidence](../../spec/storage-trie-construction-memory.md) records checked
peak-memory reductions and unchanged retained graphs. It publishes an
immutable, acyclic ARC-owned trie. Each initialized `FullStateTrie` represents a complete
full-node mapping. Copying a revision retains its identity; `revision.apply(writes)` returns
an independently retained revision. Source revisions and lookup values survive subsequent
updates and destruction of their originating handles.

`lookup(key)` distinguishes a missing key from a present empty value. A successful
`TrieValue` retains its immutable leaf and provides `byteLength` and copied `bytes`.
`commitment` returns the complete root, entry count and exact nonempty node count.
Check every `TrieResult.error` before extracting its `value`; default handles have no state.

```nim
import storage/full_state_trie
import codec/[bounded, state_layout, state_trie]

let limits = FullStateTrieLimits(
  trie: StateTrieLimits(items: ElementLimit(64), perValue: ByteLimit(4096),
    totalValueBytes: ByteLimit(65536), nodes: TrieNodeLimit(16000)),
  writes: ElementLimit(16), writeValueBytes: ByteLimit(8192))
let initial = newFullStateTrie([], limits)
if initial.error == TrieError.None:
  let changed = initial.value.apply([
    TrieWrite(key: default(StateKey), kind: TrieWriteKind.Put, value: @[1'u8])])
  if changed.error == TrieError.None:
    discard changed.value.commitment
```

Batches borrow stable input for the synchronous call. Keys must be unique even when writes
are identical. Delete requires an empty payload; deleting an absent key is a no-op. The whole
batch is validated before hashing. Updates copy affected paths and share unchanged immutable
subtrees; cached complete hashes keep root work on newly created paths. Failure exposes only a
reason and leaves all retained revisions unchanged.

## Root-bound lookup proofs

`FullStateTrie.prove(key, limits)` copies a bounded detached path directly from a retained complete
revision, preflighting exact node/value extents before allocation or hashing. Cached branches need
no hashing; a terminal long leaf needs one raw-value hash. `state_proof.nim` verifies these
root-to-terminal node paths for one serialized key against
an independently trusted complete-state root. Successful `VerifiedStateLookup` values retain
the exact root/key binding and distinguish Present from Absent; incomplete local evidence is a
failure rather than absence. Present-byte extraction copies private immutable storage. The
[light proof/trust contract](../../spec/storage-light-state-proofs.md) defines the canonical path,
left-edge 255-bit comparison, resource ceilings and trust requirements. This is a local storage
primitive; light startup, trusted heads, database identity/schema, cache policy and network formats
remain separate work. It never hashes a partial mapping into a complete state root.

## Authenticated light lookup retention

`light_state_cache.nim` retains bounded verified key lookups at one caller-trusted complete root.
Atomic `admit` batches verify all proofs before returning a new immutable cache; `forget` drops
local evidence without changing retained views. Missing entries return UnknownKey, distinct from
a stored authenticated Absent result and a present empty value. A different root requires a new
empty cache. Counts, batch work and logical raw-value bytes have separate inherited limits.
The [cache contract](../../spec/storage-light-cache.md) records ownership, refusal ordering and
local evidence. This in-memory partial cache supplies no full-state API, database schema, startup
mode or consensus/trusted-head selection.

## Light proof-cache snapshots

`light_snapshot.nim` prepares opaque immutable canonical images and restores cache state only
against independently expected chain/root arguments. Its distinct V1 format stores proof evidence,
not trusted lookup results; every restored proof is verified after bounded shape/checksum checks.
Read-only mutation policy can be restored independently of complete-snapshot entry count.
The [snapshot contract](../../spec/storage-light-snapshots.md) records exact widths, trust/refusal
ordering, golden bytes and lifetime coverage. Checksums do not select trusted roots or authorize
full/light schema conversion. File publication and application trust selection remain separate work.

Retained canonical evidence can be read with `PreparedLightSnapshot.prove` under explicit
entry-scan and proof-output budgets. Missing evidence remains `UnknownKey`; retained absence
returns a successful proof. `LightFileCache.preparedSnapshot` retains the selected immutable
image independently of the native lease, refusing fresh access after IO uncertainty.
See the [retrieval contract](../../spec/storage-light-proof-retrieval.md) for ownership,
resource bounds and recovery coverage.

Batch `prove(keys, LightProofBatchLimits)` scans canonical headers once and returns detached
proofs in request order. It bounds query scratch, traversal, individual proofs and aggregate
output, refusing the whole batch for unknown/duplicate evidence or exceeded limits.
See the [batch retrieval contract](../../spec/storage-light-proof-batches.md).

`proofCursor` and `readPage` enumerate canonical retained evidence under page-sized item/path/value
limits. Immutable continuations retain the original image, support deterministic retry and survive
writer retirement. See the [pagination contract](../../spec/storage-light-proof-pagination.md).

`select(keys, limits, entries)` exports exactly retained queries as a separately validated canonical
image under explicit output limits. It preserves the original chain/complete root, revalidates
selected proofs and leaves omitted evidence unknown. See the
[selective export contract](../../spec/storage-light-selected-exports.md).

## Boundaries and ownership

The trie reuses GP 0.8.0 key/node encodings and crypto primitives. The existing complete-map
root calculator remains an independent cross-check. Resource ceilings bound a complete revision
and a borrowed batch; callers control the number and lifetime of retained revisions. All allocation
failure follows the project's fail-stop policy. Handles belong to the single-threaded ARC execution
contract; this module adds no cross-thread ownership protocol.

The authorized in-memory `StateStore` tranche follows the coordination boundary above. Existing
whole-map checkpoints remain the recovery/export
baseline; this module performs no disk I/O. Partial light state needs its own proof/trust contract
and separate database. Future byte-storage backends can live beside this module while preserving
the distinction between physical storage and protocol Merkle commitments.

Run the native checks with:

```sh
make unit SUITE=full_state_trie
make unit SUITE=full_state_trie_private
make unit SUITE=full_state_trie_replay
```

## Standalone persistence work

`node_records.nim` defines detached physical transport records. The trie can export a complete
revision or just records missing from an explicit base, with no extra hashing. See
[the record contract](../../spec/storage-records.md). These storage-only APIs do not authorize
state/checkpoint integration.

`record_codec.nim` validates versioned physical batches. `node_repository.nim` provides atomic
in-memory publication, immutable reads and independently trusted restoration to the standalone
`FullStateTrie`. Restoration preserves caller-selected mutation limits and never constructs a
`StateStore` or changes a canonical consumer. These are storage workstream APIs only.

`database_identity.nim` binds the full-state physical schema to an independently selected chain.
`journal_codec.nim` defines checksummed revision frames. `file_repository.nim` adds an explicitly
closed, noncopyable append-only owner: each durable frame contains changed records and its root.
Strict reopen validates the whole journal and refuses partial tails. Retained read views remain
valid after file close. All calls are synchronous storage work; run them outside networking
callbacks. See the record contract for bounded IO, cooperative inode locking and uncertainty rules.

Unordered record duplicate preflight first proves uniqueness with compact digest prefixes when
possible; every collision falls back to the full32-byte identity check before any integrity hash.
No prefix becomes a physical identity or graph authority. See the
[duplicate preflight contract](../../spec/storage-duplicate-prefix-preflight.md).

`encodeFramedTrieExport` strictly validates raw batches before writing them into one owned buffer
with checked zero-filled frame reservations. Both journal formats fill metadata/context and their
new checksum around that body without retaining another encoded body. See the
[journal framing contract](../../spec/storage-journal-framing.md).

`recoverFileRepository` is an explicit operator action for an interrupted final append. It
requires the independently trusted generation and root of the complete prefix before truncating
anything; complete corrupt frames and complete successor revisions are never discarded. Strict
open remains unchanged. Real child-process short-write checks exercise recovery and resumed append.

Physical trie full/delta/inverse exports provision exactly the preflighted record count. Their
payloads remain detached mutable copies. `TrieResult.takeValue` transfers an owned export, revision
or retained value once and leaves `Uninitialized`; the copying `.value` accessor remains available.
See the [owning export contract](../../spec/storage-owned-trie-exports.md).

`matches(view, otherView)` compares exact initialized immutable source owners without allocation,
graph traversal or IO. Default views never match; equal roots/generations in a cloned owner do not
authorize maintenance. Managed compaction uses this check before requested-root traversal; see the
[compaction authority contract](../../spec/storage-compaction-authority.md).

`revision_retention.nim` provides bounded explicit pins for immutable repository views. Catalog
copies update independently; release/close never revoke held views. Tokens also retain their
selected view until dropped. The pin catalog itself provides no automatic eviction, finality
policy or disk reclamation; managed consumers select an explicit complete-root union.

`synchronize` uses `StorageDurability` receipts: memory confirms only process lifetime; disk
confirms a successful file and directory barrier. Both owners share snapshot/publication/view
semantics while preserving their typed error distinctions. Run `storage_backend_contract` and
`storage_disk_replay` for the common scenarios and published full/delta/inverse mapping roundtrips.

The authorized complete-state memory/disk consumer boundary is recorded above. Managed layout,
reclamation and explicit migration use the same state and trust contracts. Full/light startup and
unrelated consumer changes remain separate work.

`selectRepositoryRoots` builds an immutable reachability inventory for explicitly selected roots,
including the current head. It validates each complete graph and counts shared records once, exposing
retained and reclaimable node/value-byte totals without deleting anything. Plans bind the exact
source view and remain usable after publication or close. Root membership is physical reachability,
not block/finality authority. Run `storage_retention_plan` for its ownership and limit checks.

`exportRepositorySelection` copies a plan's retained physical union under explicit record/value
ceilings. The sorted detached result is maintenance transport, not an ordinary single-root batch.
It performs no file replacement, generation reset, context rewrite or reclamation.

Selection traversal uses independent per-root seen bits, a retained union bitmap and sparse dirty-word
reset; the final exact inventory follows physical order without sorting selected indices. See the
[bitmap construction contract](../../spec/storage-selection-bitmaps.md).

`encodeRepositorySelection` serializes an opaque admitted union directly into owned canonical
collection bytes. It avoids detached record/value copies and repeated hashes; raw mutable record
encoders remain strict. Snapshot encoding uses this path and hashes its new outer frame once.
`RepositoryResult.takeValue` transfers a successful owner and leaves the result uninitialized.
See the [selection encoding contract and measurements](../../spec/storage-selection-encoding.md).
`encodeFramedRepositorySelection` reserves checked zero-filled prefix/suffix space and writes the
canonical body directly into its final buffer. Snapshot encoding fills those reservations without
retaining a second whole-body buffer. See the [framing contract](../../spec/storage-snapshot-framing.md).

Unchanged-root zero-record publications share their validated immutable physical table while
creating a new exact view identity and generation. Ordinary changed-root admission, frame bytes
and durability barriers retain their contracts. See `storage_unchanged_publication` and the
[maintenance measurements](../../spec/disk-state-store.md#maintenance-measurement-scope).

`managed_repository.nim` owns a stable directory lease and exactly the snapshot/journal pair
selected by CURRENT. Creation takes a complete immutable root selection; strict reopen checks the
chain, schema, snapshot binding, retained graphs and every contiguous journal frame. It never
scans for a fallback head. Retained views and detached context survive explicit owner close.
Explicit managed DiskStateStore and application startup entry points now adopt this component.
The existing StateStore API and default single-file journal layout remain unchanged. Application
maintenance uses the same native worker and an exact canonical root/history selection; see the
[integration contract](../../spec/managed-disk-integration.md).

Managed `publish` exposes a prepared revision only after its paired journal frame is synchronized.
IO uncertainty requires reopening. `recoverManagedRepository` is an explicit operation requiring an
independent exact generation/root token; normal startup never repairs a tail or rolls back a
complete successor. Context and retained readers follow the existing immutable publication contract.

Managed `compact(expected, roots)` replaces the physical epoch while preserving the current state
root, generation and context. It retains the explicit complete-root union, durably switches CURRENT,
then retires the previous selected files. Its receipt distinguishes confirmed selection from deferred
cleanup. Old readers remain valid; callers obtain a fresh physical view before another publication.
Compaction does not choose canonical roots/finality or schedule application maintenance.

`discardManagedStaging` explicitly removes only the next unselected epoch and pending manifest.
`cleanupRetiredEpoch` retries cleanup of one earlier epoch. Both require a validated live owner,
refuse the selected pair and avoid directory scanning. Unknown epochs remain untouched.

`file_migration.nim` explicitly copies a locked legacy single-file repository into a new managed
directory, preserving admitted chain/schema, generation, selected context and explicit retained
roots. The source remains unchanged and independently usable. Startup never implicitly migrates an
existing file, and migration supplies no external checkpoint trust.

Managed `usage` reports cached selected-file extents and revision metadata without IO or graph
copying. It excludes unknown/staged/retired files and retained reader memory. The fixed native
`storage_managed_usage` workload records reclamation and elapsed cost for 64 commits retaining nine
explicit roots; its measurements are descriptive local evidence, not performance thresholds.

The authorized managed adoption keeps `FileRepository` as the existing public publication/result
facade. `initializeManagedFileRepository`, `openManagedFileRepository` and
`recoverManagedFileRepository` explicitly select managed ownership; legacy entry points remain
single-file operations. `opened` reads scalar lifecycle state, so worker polling does not touch ARC
graphs. Managed compaction and selected usage return `UnsupportedLayout` for legacy owners.


`cloneRepositorySelection` copies an opaque validated selection into an independent repository,
assigning a fresh view identity while enforcing inherited complete-state policy and physical
budgets. It accepts no serialized input. Managed creation and compaction use it after snapshot
encoding; strict disk reopen still independently validates every record and complete graph.
The measured hash counts and unchanged byte/root evidence are in the integration contract.

At application startup, enabled managed maintenance cleans only the immediate predecessor and
unselected successor of the validated selected epoch, plus CURRENT.next. It never scans unknown
files or falls back to another head. Explicit zero maintenance preserves staged forensic files.
Online maintenance runs after confirmed publication and before producer acknowledgement; failure
preserves the confirmed canonical prefix and prevents further mutation until fresh startup.

## Consuming checked transport results

`ManagedIoResult`, `RecordResult`, `SnapshotResult` and `FrameResult` support `takeValue`
when the result is mutable and successful. Check the result's error first. A successful call
moves the owned payload and changes the source status to `Uninitialized`; do not extract from
that source again. Use `value` when an independent copy is required. Immutable private repository
cells and retained views keep their existing ownership contracts; other result types do not gain
this consuming API implicitly.

Bounded read metadata controls capacity only. Actual short reads, EOF and the excess growth probe
remain authoritative, and strict format admission still runs after loading. For matched peak-RSS
observations, the checked comparison rules and Linux qualification, see the
[read-memory record](../../spec/storage-read-memory-qualification.md).

## Light proof-cache files

`light_file_cache.nim` owns an explicitly selected separate directory and stable lock.
It publishes opaque light images through synchronized atomic `CURRENT` replacement and
reopens only after bounded proof verification against independently supplied chain/root.
Immutable readers survive publication and close; uncertain IO requires explicit close
and validated reopen. Pending cleanup revalidates the selected image before removal.
See [the lifecycle and durability contract](../../spec/storage-light-files.md).
Application startup and consensus root selection remain separately scoped work.

Prepared light images support bounded `admit` and `forget` edits at the same independently
selected root. File owners retain verified proof evidence after reopen and expose the same
operations through synchronized atomic publication. Exact final image quotas precede hashing;
unchanged proofs are retained without rehashing. See [incremental light evidence](../../spec/storage-light-updates.md).

Light-file reopening transfers its owned read buffer into the validated prepared image.
The public `takeLightSnapshot` consumes only on success; failed validation preserves
the caller buffer, and borrowed restoration retains its copying contract. See the
[ownership and measured memory record](../../spec/storage-light-restore-memory.md).

Light snapshot decoding preflights the complete image and checksum, then verifies one
proof at a time through a synchronous canonical reader into a private final cache.
The reader is never retained and a failed suffix exposes no partial cache. See the
[streaming verification and memory contract](../../spec/storage-light-streaming.md).

Light file initialization and replacement borrow `encodedBytes` for the existing
synchronous writer, avoiding a temporary full-image copy. This owner-bound read-only
view rejects mutation and escaping a local owner; mutable extraction and `.bytes`
remain independent copies. See [publication memory and IO evidence](../../spec/storage-light-publication-memory.md).

Prepared images and file owners expose `update(proofs, forgottenKeys)` for atomic
combined changes. This replaces evidence at exact capacity in one publication, with
no visible eviction prefix. See [atomic evidence batches](../../spec/storage-light-atomic-batches.md).

The [light churn baseline](../../spec/storage-light-churn.md) measures real one-key evidence
forget/admit publication, strict reopen, completed write extents, durability calls and ARC
retirement with producer memory excluded. It motivates bounded incremental light persistence;
its local timings do not establish cold-cache or physical-device behavior.

`light_delta.nim` encodes bounded canonical proof-cache edits with exact chain/root,
predecessor/successor checksums and expected local sequence. Opaque results retain an immutable
successor; consuming decode transfers bytes only after complete verification. See
[authenticated update frames](../../spec/storage-light-deltas.md). Durable journal ownership
and partial-tail recovery remain separate work.

`light_journal_manifest.nim` selects a positive physical light-journal epoch and its checkpoint
sequence using a distinct `CURRENT` schema. A checksummed journal anchor binds that exact
selection; old light-image and full-state formats have no fallback. See the
[selection and anchor contract](../../spec/storage-light-journal-selection.md).

`light_journal_replay.nim` strictly verifies a bounded selected checkpoint/anchor/frame stream
before exposing its final immutable image. Separate explicit partial-tail plans bind only a
fully authenticated prefix to all original journal bytes and selection; complete corruption
never yields salvage authority. See [replay and tail planning](../../spec/storage-light-journal-replay.md).

`light_journal_cache.nim` owns a separate locked light directory, synchronized checkpoint/anchor
bootstrap and strict replay on reopen. Opaque authenticated updates append only a bounded frame;
uncertain I/O refuses fresh observations until explicit close and strict reopen. See the
[durable journal lifecycle](../../spec/storage-light-journal-cache.md).

Explicit `LightJournalRecovery` inspection holds the selected journal inode and directory
lease. Repair revalidates CURRENT, checkpoint, exact original bytes and selected inode/extent
before synchronized prefix truncation transfers one writable owner. Complete corruption is
never salvaged. See [held-inode repair](../../spec/storage-light-journal-repair.md).

Prepared light journal compaction binds an exact epoch/sequence/image, writes a new synchronized
checkpoint and empty anchor, then atomically selects that epoch without advancing update sequence.
A confirmed receipt reports old-handle retirement separately; old files remain untouched. See
[atomic checkpoint compaction](../../spec/storage-light-journal-compaction.md).

Explicit light journal reclamation revalidates the exact selected checkpoint and held journal
before removing earlier canonical epochs or fixed staging. Prepared abandoned candidates must
match every expected canonical prefix before any unlink; idempotent retries synchronize even
already absent names. See [guarded reclamation](../../spec/storage-light-journal-reclamation.md).

Grouped [replacement process-crash qualification](../../spec/storage-light-replacement-crashes.md)
checks every observed compaction and cleanup boundary, exact old/new selection, forensic bytes,
lease release and explicit synchronized cleanup/retry before the next authenticated append.

The maintained [matched light churn panel](../../spec/storage-light-journal-churn.md) compares
full-image publication and journal append on identical query/proof workloads, including actual
write/barrier work, strict reopen, retained-reader lifetime and fresh-process peak memory.

Managed journal [attachment and bounded windows](../../spec/storage-held-journal-ranges.md)
retain the exact append inode without loading the entire log. Caller-owned reads recheck
selected name/inode/extent and actual EOF, with explicit uncertainty and retirement.

Strict light [streaming reopen](../../spec/storage-light-streaming-reopen.md) shares immutable
anchor/frame verification with whole-buffer replay, sizes buffers from checked headers, and
publishes its owner only after the complete held extent and final EOF revalidate.

Prepared [light journal update batches](../../spec/storage-light-journal-batches.md) authenticate
bounded consecutive edits privately, retain only their final image, and publish with one append
barrier. Interrupted groups preserve complete earlier frames for explicit prefix recovery.
