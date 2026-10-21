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
full/light semantics and layout/reclamation changes still require their own scope.

## Complete-state revisions

`newFullStateTrie(entries, limits)` copies serialized 31-byte keys and raw values into an
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

`recoverFileRepository` is an explicit operator action for an interrupted final append. It
requires the independently trusted generation and root of the complete prefix before truncating
anything; complete corrupt frames and complete successor revisions are never discarded. Strict
open remains unchanged. Real child-process short-write checks exercise recovery and resumed append.

`revision_retention.nim` provides bounded explicit pins for immutable repository views. Catalog
copies update independently; release/close never revoke held views. Tokens also retain their
selected view until dropped. There is no automatic eviction, finality policy or disk reclamation.

`synchronize` uses `StorageDurability` receipts: memory confirms only process lifetime; disk
confirms a successful file and directory barrier. Both owners share snapshot/publication/view
semantics while preserving their typed error distinctions. Run `storage_backend_contract` and
`storage_disk_replay` for the common scenarios and published full/delta/inverse mapping roundtrips.

The authorized complete-state memory/disk consumer boundary is recorded above. Full/light startup
and workload-driven layout/reclamation remain separate work. Availability of these primitives does
not authorize unrelated consumers to change their state or trust contracts.

`selectRepositoryRoots` builds an immutable reachability inventory for explicitly selected roots,
including the current head. It validates each complete graph and counts shared records once, exposing
retained and reclaimable node/value-byte totals without deleting anything. Plans bind the exact
source view and remain usable after publication or close. Root membership is physical reachability,
not block/finality authority. Run `storage_retention_plan` for its ownership and limit checks.

`exportRepositorySelection` copies a plan's retained physical union under explicit record/value
ceilings. The sorted detached result is maintenance transport, not an ordinary single-root batch.
It performs no file replacement, generation reset, context rewrite or reclamation.

Unchanged-root zero-record publications share their validated immutable physical table while
creating a new exact view identity and generation. Ordinary changed-root admission, frame bytes
and durability barriers retain their contracts. See `storage_unchanged_publication` and the
[maintenance measurements](../../spec/disk-state-store.md#maintenance-measurement-scope).

`managed_repository.nim` owns a stable directory lease and exactly the snapshot/journal pair
selected by CURRENT. Creation takes a complete immutable root selection; strict reopen checks the
chain, schema, snapshot binding, retained graphs and every contiguous journal frame. It never
scans for a fallback head. Retained views and detached context survive explicit owner close.
This standalone component is not yet used by StateStore or application startup. Managed append,
reclamation, explicit migration and consumer adoption are subsequent storage-owned layers; other
workstreams should continue through their existing APIs until a coordinated integration lands.
