# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Owned in-memory serialized JAM state with atomic sorted mappings and incremental GP 0.8.0 commitments.
## Single-threaded handles publish complete immutable snapshots; borrowed write inputs stay
## stable for apply. Snapshot retention is caller-controlled; storage remains in memory.
##
## Exposes StateStore/StateStoreSnapshot handles, snapshot, lookup, sorted keyAt, commitment and atomic apply over
## complete serialized mappings, bounded owner-bound copySlice, plus forkStateStore with inherited ceilings for private working branches.

import std/[algorithm, assertions]
import ../codec/[state_trie, state_layout, bounded]
import ../storage/[full_state_trie, node_records]

type
  StateEntryIndex* = distinct int ## Sorted ordinal interpreted only against the supplied immutable complete-map snapshot.
  StateStoreLimits* = object ## Independent batch ceilings supplement the existing complete-map Merklization limits.
    trie*: StateTrieLimits
    writes*: ElementLimit
    writeValueBytes*: ByteLimit
  StateWriteKind* {.pure.} = enum ## Put inserts or replaces; Delete removes an existing key and is a no-op for an absent key.
    Put, Delete
  StateWrite* = object ## A synchronous borrowed mutation. Delete requires an empty value; batch keys must be unique.
    key*: StateKey
    kind*: StateWriteKind
    value*: seq[byte]
  StateStoreError* {.pure.} = enum ## Failure alternatives expose no snapshots, values, counts or partially computed roots.
    Uninitialized, None, MissingKey, InvalidWrite, LimitExceeded, DuplicateKey,
    LengthOverflow, BackendFailure, InvalidRange
  ## Acyclic ARC-owned map. Values become immutable before this owner is published.
  SnapshotData = ref object
    entries: seq[StateEntry]
    trie: FullStateTrie # Independently immutable path-copied Merkle state, published with the sorted map.
    commitment: StateTrieCommitment
    limits: StateStoreLimits
  StateStoreSnapshot* = object ## Read-only retained map identity; copies preserve the same immutable historical state.
    data: nil SnapshotData
  StateStore* = object ## An independently updateable handle; copying it shares only immutable prior snapshots.
    head: nil SnapshotData
    limits: StateStoreLimits
  StateValue* = object ## Retained lookup view binds its position to the exact snapshot, including a present-empty value.
    owner: StateStoreSnapshot
    position: int
  StateStoreResult*[T] = object ## Select success explicitly before reading its private, contract-guarded payload.
    case status: StateStoreError
    of None:
      completed: T # Only complete operations expose payloads.
    else:
      discard      # Defaults and errors contain their reason alone.
  ## Fixed write identities and original indices bound sorting scratch without retaining inputs.
  WriteIndex = object
    key: StateKey
    position: int

func error*[T](outcome: StateStoreResult[T]): StateStoreError =
  ## Read an operation's reason without exposing its payload or granting mutation access.
  outcome.status

func value*[T](outcome: StateStoreResult[T]): T {.inline,
    requires: outcome.status == StateStoreError.None.} =
  ## Extract a successful payload only; failed/default results have no readable payload.
  outcome.completed

## Compare full serialized key identities in the same lexicographic/MSB order as the trie.
func compareKey(left, right: StateKey): int =
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  # The first differing byte determines the complete fixed key's order.
  for i in 0..<31:
    if a[i] < b[i]: return -1 # Zero bits sort before one bits.
    elif a[i] > b[i]: return 1 # Larger bytes follow smaller bytes.
  0

## Adapt entry sorting without comparing or copying payloads in the comparator.
proc compareEntry(left, right: StateEntry): int = compareKey(left.key, right.key)

## Keep sorted writes attached to their original borrowed payload positions.
proc compareWrite(left, right: WriteIndex): int = compareKey(left.key, right.key)

## Deep-copy caller bytes; no later source mutation can affect a committed snapshot.
proc copyBytes(source: openArray[byte]): seq[byte] =
  result = newSeq[byte](source.len)
  # Copy individual bytes rather than exporting or sharing caller-owned mutable backing storage.
  for i, octet in source: result[i] = octet

## Translate the private incremental implementation's reasons without exposing its handles.
func storeError(reason: TrieError): StateStoreError =
  case reason
  of TrieError.None: StateStoreError.None # A completed root is the only successful case.
  of TrieError.Uninitialized: StateStoreError.Uninitialized # Preserve default failure.
  of TrieError.MissingKey: StateStoreError.MissingKey # Complete-map absence remains explicit.
  of TrieError.InvalidWrite: StateStoreError.InvalidWrite # Malformed borrowed mutations never become deletes.
  of TrieError.LimitExceeded: StateStoreError.LimitExceeded # Preserve complete-map and batch ceilings.
  of TrieError.DuplicateKey: StateStoreError.DuplicateKey # Never select an arbitrary duplicate.
  of TrieError.LengthOverflow: StateStoreError.LengthOverflow # Keep native extent failures distinct.
  of TrieError.BackendFailure: StateStoreError.BackendFailure # Required primitive refusal is an error.

func trieLimits(limits: StateStoreLimits): FullStateTrieLimits =
  ## Preserve every caller-selected limit, including future writes after snapshot forks.
  FullStateTrieLimits(trie: limits.trie, writes: limits.writes,
    writeValueBytes: limits.writeValueBytes)

proc newStateStore*(entries: openArray[StateEntry], limits: StateStoreLimits): StateStoreResult[StateStore] =
  ## Initialize from a borrowed mapping after complete root/resource validation. Duplicates reject.
  ## Allocation exhaustion follows the project's fail-stop policy; the store owns all published bytes.
  let committed = newFullStateTrie(entries, trieLimits(limits))
  if committed.error != TrieError.None:
    # Reject before constructing the sorted map; private trie candidates retire on failure.
    return StateStoreResult[StateStore](status: storeError(committed.error))
  var owned = newSeq[StateEntry](entries.len)
  # Root validation has already bounded entry and value extents before owned allocation.
  for i, entry in entries:
    owned[i] = StateEntry(key: entry.key, value: copyBytes(entry.value))
  owned.sort(compareEntry)
  let data = SnapshotData(entries: owned, trie: committed.value,
    commitment: committed.value.commitment,
    limits: limits)
  StateStoreResult[StateStore](status: StateStoreError.None,
    completed: StateStore(head: data, limits: limits))

func sameStateSnapshot*(left, right: StateStoreSnapshot): bool =
  ## Compare initialized immutable versions by owner identity without hashing or copying.
  ## Copied handles match; defaults and independently built equal roots do not.
  left.data != nil and left.data == right.data

proc snapshot*(store: StateStore): StateStoreResult[StateStoreSnapshot] =
  ## Retain the current immutable version independently of future store updates or handle destruction.
  if store.head == nil:
    # A default handle cannot masquerade as an initialized empty map.
    return StateStoreResult[StateStoreSnapshot](status: StateStoreError.Uninitialized)
  StateStoreResult[StateStoreSnapshot](status: StateStoreError.None,
    completed: StateStoreSnapshot(data: store.head))

proc forkStateStore*(source: StateStoreSnapshot): StateStoreResult[StateStore] =
  ## Start an independently updateable complete-map branch from this retained version, without hashing.
  ## Inherit its original resource policy; future writes cannot mutate the source or loosen its ceilings.
  let data = source.data
  if data == nil:
    # Default snapshots cannot authorize a store with a fabricated empty map or default policy.
    return StateStoreResult[StateStore](status: StateStoreError.Uninitialized)
  StateStoreResult[StateStore](status: StateStoreError.None,
    completed: StateStore(head: data, limits: data.limits))

proc commitment*(snapshot: StateStoreSnapshot): StateTrieCommitment {.requires: snapshot.data != nil.} =
  ## Return copied root/count metadata, never a mutable reference into the retained map.
  let data = snapshot.data
  assert data != nil # Retain one stable owner for the contract-proved access.
  data.commitment

proc keyAt*(snapshot: StateStoreSnapshot, index: StateEntryIndex): StateStoreResult[StateKey] =
  ## Copy one sorted serialized key; reject defaults and invalid ordinals without exposing map storage.
  let data = snapshot.data
  if data == nil:
    return StateStoreResult[StateKey](status: StateStoreError.Uninitialized) # No default map exists.
  if int(index) < 0 or int(index) >= data.entries.len:
    return StateStoreResult[StateKey](status: StateStoreError.InvalidRange) # Never clip or wrap a coordinate.
  StateStoreResult[StateKey](status: StateStoreError.None, completed: data.entries[int(index)].key)

proc lookup*(snapshot: StateStoreSnapshot, key: StateKey): StateStoreResult[StateValue] =
  ## Find a full key in a published sorted map. Missing and present-empty values are distinct.
  let data = snapshot.data
  if data == nil:
    # A default snapshot cannot supply an absent/present verdict.
    return StateStoreResult[StateValue](status: StateStoreError.Uninitialized)
  var lo = 0
  var hi = data.entries.len
  # Binary search uses a subtraction-based midpoint to avoid address arithmetic overflow.
  while lo < hi:
    let middle = lo + (hi-lo) div 2
    let order = compareKey(data.entries[middle].key, key)
    if order < 0:
      lo = middle+1 # Only larger keys can still match the query.
    elif order > 0:
      hi = middle # Only smaller keys can still match the query.
    else:
      # Retain the owner along with its index, never a detached coordinate or mutable sequence.
      return StateStoreResult[StateValue](status: StateStoreError.None,
        completed: StateValue(owner: snapshot, position: middle))
  StateStoreResult[StateValue](status: StateStoreError.MissingKey)

proc byteLength*(view: StateValue): int {.requires: view.owner.data != nil.} =
  ## Read the exact retained value length, including zero; default views are not valid values.
  let data = view.owner.data
  assert data != nil # Bind the validated view owner once before accessing its immutable storage.
  data.entries[view.position].value.len

proc bytes*(view: StateValue): seq[byte] {.requires: view.owner.data != nil.} =
  ## Copy bytes out of the retained view; callers can mutate the copy without changing any snapshot.
  let data = view.owner.data
  assert data != nil # Bind the validated view owner once before copying its immutable storage.
  copyBytes(data.entries[view.position].value)

proc copySlice*(view: StateValue, offset, length: uint64,
    limit: ByteLimit): StateStoreResult[seq[byte]] =
  ## Copy exactly one owner-bound raw byte interval without materializing the remaining value.
  ## Generic storage coordinates are uint64; validate by subtraction before narrowing or allocation.
  ## Default owners, invalid ranges and policy refusal expose no bytes or partial progress.
  let data = view.owner.data
  if data == nil:
    return StateStoreResult[seq[byte]](status: StateStoreError.Uninitialized) # Empty copies still need an owner.
  let size = uint64(data.entries[view.position].value.len)
  if offset > size or length > size-offset:
    return StateStoreResult[seq[byte]](status: StateStoreError.InvalidRange) # Never clip an invalid caller range silently.
  if length > uint64(limit):
    return StateStoreResult[seq[byte]](status: StateStoreError.LimitExceeded) # Bound the exact copied interval before allocation.
  var copied = newSeq[byte](int(length)) # Range validation proves both coordinates fit the source's native length.
  for i in 0..<copied.len:
    copied[i] = data.entries[view.position].value[int(offset)+i] # offset+length<=size proves every native index.
  StateStoreResult[seq[byte]](status: StateStoreError.None, completed: copied)

proc apply*(store: var StateStore, writes: openArray[StateWrite]): StateStoreResult[
    StateStoreSnapshot] =
  ## Merge unique sorted mutations into a private candidate, then publish only after the root succeeds.
  ## Empty batches retain the existing version. Failure leaves the store and every old snapshot unchanged.
  let head = store.head
  if head == nil:
    # Initialization is required even for a no-op batch.
    return StateStoreResult[StateStoreSnapshot](status: StateStoreError.Uninitialized)
  if uint64(writes.len) > uint64(store.limits.writes):
    # Bound input-derived sorting scratch before allocating it.
    return StateStoreResult[StateStoreSnapshot](status: StateStoreError.LimitExceeded)
  if writes.len > high(int) div sizeof(WriteIndex) or
      writes.len > high(int) div sizeof(TrieWrite):
    # A count representable as int still must fit its typed scratch extent.
    return StateStoreResult[StateStoreSnapshot](status: StateStoreError.LengthOverflow)
  var writeBytes = 0'u64
  # Validate all input payloads and tags before allocating scratch or copying values.
  for write in writes:
    if write.kind notin {StateWriteKind.Put, StateWriteKind.Delete}:
      # Invalid discriminators must not fall through to a deletion or insertion.
      return StateStoreResult[StateStoreSnapshot](status: StateStoreError.InvalidWrite)
    if write.kind == StateWriteKind.Delete and write.value.len != 0:
      # Delete carries no payload; reject ambiguous input instead of silently discarding bytes.
      return StateStoreResult[StateStoreSnapshot](status: StateStoreError.InvalidWrite)
    let size = uint64(write.value.len)
    if size > uint64(store.limits.trie.perValue) or size > uint64(
        store.limits.writeValueBytes)-writeBytes:
      # Subtract the running total before addition because Nimony arithmetic intentionally wraps.
      return StateStoreResult[StateStoreSnapshot](status: StateStoreError.LimitExceeded)
    writeBytes += size
  if writes.len == 0:
    # No changes require neither a replacement owner nor a backend invocation.
    return snapshot(store)
  var ordered = newSeq[WriteIndex](writes.len)
  # Sorting copies fixed identities only; caller order and backing values remain untouched.
  for i, write in writes: ordered[i] = WriteIndex(key: write.key, position: i)
  ordered.sort(compareWrite)
  # Each key has one mutation; reject duplicates even when the writes or values are identical.
  for i in 1..<ordered.len:
    if compareKey(ordered[i-1].key, ordered[i].key) == 0:
      return StateStoreResult[StateStoreSnapshot](status: StateStoreError.DuplicateKey)
  var count = 0
  var total = 0'u64
  var source = 0
  var change = 0
  # First merge pass counts the final map and bytes without allocating candidate payloads.
  while source < head.entries.len or change < ordered.len:
    let order = if source == head.entries.len: 1
      elif change == ordered.len: -1
      else: compareKey(head.entries[source].key, ordered[change].key)
    var keep = true
    var size = 0
    if order < 0:
      size = head.entries[source].value.len # Untouched entries remain in the candidate.
      inc source
    else:
      let write = writes[ordered[change].position]
      keep = write.kind == StateWriteKind.Put # Deletes omit either an existing or an absent key.
      size = write.value.len
      inc change
      if order == 0: inc source # Replacement/deletion consumes the matching original entry.
    if keep:
      # Bound exact final storage, including overwritten/deleted entries releasing their old budgets.
      if count >= high(int) div sizeof(StateEntry) or uint64(count) >= uint64(
          store.limits.trie.items):
        return StateStoreResult[StateStoreSnapshot](status: StateStoreError.LimitExceeded)
      if uint64(size) > uint64(store.limits.trie.totalValueBytes)-total:
        return StateStoreResult[StateStoreSnapshot](status: StateStoreError.LimitExceeded)
      inc count
      total += uint64(size)
  var adapted = newSeq[TrieWrite](writes.len)
  for i, write in writes:
    # Borrow payload descriptors only until synchronous trie apply privately copies changed leaf bytes.
    adapted[i] = TrieWrite(key: write.key,
      kind: (if write.kind == StateWriteKind.Put: TrieWriteKind.Put else: TrieWriteKind.Delete),
      value: write.value)
  let committed = head.trie.apply(adapted)
  if committed.error != TrieError.None:
    # Exact node policy and required hashing complete before constructing/publishing the sorted map.
    return StateStoreResult[StateStoreSnapshot](status: storeError(committed.error))
  var candidate = newSeq[StateEntry](count)
  source = 0
  change = 0
  var destination = 0
  # Second merge pass builds exactly the preflighted candidate; old immutable bytes may be shared.
  while source < head.entries.len or change < ordered.len:
    let order = if source == head.entries.len: 1
      elif change == ordered.len: -1
      else: compareKey(head.entries[source].key, ordered[change].key)
    if order < 0:
      candidate[destination] = head.entries[source] # Sharing is private and permanently read-only.
      inc destination
      inc source
    else:
      let write = writes[ordered[change].position]
      if write.kind == StateWriteKind.Put:
        # Copy new caller bytes only after the complete batch and final map have passed preflight.
        candidate[destination] = StateEntry(key: write.key, value: copyBytes(write.value))
        inc destination
      inc change
      if order == 0: inc source # Consume the original only on an equal full key.
  let data = SnapshotData(entries: candidate, trie: committed.value,
    commitment: committed.value.commitment, limits: store.limits)
  store.head = data # This is the sole publication point, reached only after complete success.
  StateStoreResult[StateStoreSnapshot](status: StateStoreError.None,
    completed: StateStoreSnapshot(data: data))

proc exportStateSnapshot*(snapshot: StateStoreSnapshot,
    limits: TrieExportLimits): TrieResult[TrieExport] =
  ## Copy bounded full physical records from the cached immutable trie without rehashing state.
  let data = snapshot.data
  if data == nil: return default(TrieResult[TrieExport])
  exportFullTrie(data.trie, limits)

proc exportStateChanges*(base, target: StateStoreSnapshot,
    limits: TrieExportLimits): TrieResult[TrieExport] =
  ## Export detached changed nodes; the caller must separately authorize the selected base owner.
  let before = base.data
  let after = target.data
  if before == nil or after == nil: return default(TrieResult[TrieExport])
  exportTrieChanges(before.trie, after.trie, limits)

func sameStateStorePolicy*(left, right: StateStoreSnapshot): bool =
  ## Compare every inherited complete-map and mutation ceiling; defaults never authorize policy adoption.
  let before = left.data
  let after = right.data
  if before == nil or after == nil: return false
  let a = before.limits
  let b = after.limits
  uint64(a.trie.items) == uint64(b.trie.items) and
    uint64(a.trie.perValue) == uint64(b.trie.perValue) and
    uint64(a.trie.totalValueBytes) == uint64(b.trie.totalValueBytes) and
    uint64(a.trie.nodes) == uint64(b.trie.nodes) and
    uint64(a.writes) == uint64(b.writes) and
    uint64(a.writeValueBytes) == uint64(b.writeValueBytes)
