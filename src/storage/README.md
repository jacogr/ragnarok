# Storage primitives

This folder owns the standalone incremental complete-state trie described in
[the storage direction](../../docs/design/state-storage.md). The initial module is
[`full_state_trie.nim`](full_state_trie.nim); its exact contract and verification live in
[`spec/full-state-trie.md`](../../spec/full-state-trie.md).

## Parallel work and integration boundary

Storage and state development are independent workstreams until the maintainer explicitly
authorizes integration. The storage workstream owns this folder and its dedicated trie tests and
feature contract. State/checkpoint work continues with the existing `StateStore` and checkpoint
APIs and must neither modify nor consume the new trie. This restriction also applies after the
standalone PR merges; availability on master does not authorize adoption.

State, PVM, checkpoint and application implementations must not import this module, add adapters
or route execution through it yet. Storage work must likewise leave those implementations alone.
Neither workstream should refactor the other's code in anticipation of integration. Sharing status
or design information is welcome and grants no implementation authority across this boundary.

“Future integration” describes a possible later, separately scoped task. It is not the next task
for the state agent or permission for the storage agent to begin wiring consumers. The maintainer
must explicitly open that task and agree its owner, current API/snapshot contracts and validation
scope before either side crosses the boundary. See the [folder instructions](AGENTS.md).

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

`StateStore` integration is deferred under the explicit coordination boundary above. Existing
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
