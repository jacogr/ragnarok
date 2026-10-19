# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Owned in-memory serialized JAM state, using GP 0.8.0 M/B/L through stateTrieRoot.
## Single-threaded handles publish complete immutable snapshots; borrowed write inputs stay
## stable for apply. Snapshot retention is caller-controlled, with no disk storage or
## incremental trie yet.
##
## Exposes StateStore/StateStoreSnapshot handles, snapshot, lookup, commitment and atomic apply over
## complete serialized mappings, plus forkStateStore with inherited ceilings for private working branches.

import std/[algorithm, assertions]
import ../codec/[state_trie, state_layout, bounded]

type
  ## Independent batch ceilings supplement the existing complete-map Merklization limits.
  StateStoreLimits* = object
    trie*: StateTrieLimits
    writes*: ElementLimit
    writeValueBytes*: ByteLimit
  ## Put inserts or replaces; Delete removes an existing key and is a no-op for an absent key.
  StateWriteKind* {.pure.} = enum
    Put, Delete
  ## A synchronous borrowed mutation. Delete requires an empty value; batch keys must be unique.
  StateWrite* = object
    key*: StateKey
    kind*: StateWriteKind
    value*: seq[byte]
  ## Failure alternatives expose no snapshots, values, counts or partially computed roots.
  StateStoreError* {.pure.} = enum
    Uninitialized, None, MissingKey, InvalidWrite, LimitExceeded, DuplicateKey,
    LengthOverflow, BackendFailure
  ## Acyclic ARC-owned map. Values become immutable before this owner is published.
  SnapshotData = ref object
    entries: seq[StateEntry]
    commitment: StateTrieCommitment
    limits: StateStoreLimits
  ## Read-only retained map identity; copies preserve the same immutable historical state.
  StateStoreSnapshot* = object
    data: nil SnapshotData
  ## An independently updateable handle; copying it shares only immutable prior snapshots.
  StateStore* = object
    head: nil SnapshotData
    limits: StateStoreLimits
  ## Retained lookup view binds its position to the exact snapshot, including a present-empty value.
  StateValue* = object
    owner: StateStoreSnapshot
    position: int
  ## Select success explicitly before reading its private, contract-guarded payload.
  StateStoreResult*[T] = object
    case status: StateStoreError
    of None:
      completed: T # Only complete operations expose payloads.
    else:
      discard      # Defaults and errors contain their reason alone.
  ## Fixed write identities and original indices bound sorting scratch without retaining inputs.
  WriteIndex = object
    key: StateKey
    position: int

## Read an operation's reason without exposing its payload or granting mutation access.
func error*[T](outcome: StateStoreResult[T]): StateStoreError = outcome.status

## Extract a successful payload only; failed/default results have no readable payload.
func value*[T](outcome: StateStoreResult[T]): T {.inline,
    requires: outcome.status == StateStoreError.None.} = outcome.completed

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

## Translate Merklization errors without synthesizing a successful zero/default commitment.
func storeError(reason: StateTrieError): StateStoreError =
  case reason
  of StateTrieError.None: StateStoreError.None # A completed root is the only successful case.
  of StateTrieError.Uninitialized: StateStoreError.Uninitialized # Preserve default failure.
  of StateTrieError.LimitExceeded: StateStoreError.LimitExceeded # Map policy budgets directly.
  of StateTrieError.DuplicateKey: StateStoreError.DuplicateKey # Never select an arbitrary duplicate.
  of StateTrieError.LengthOverflow: StateStoreError.LengthOverflow # Keep addressing failures distinct.
  of StateTrieError.BackendFailure: StateStoreError.BackendFailure # Native primitive refusal is an error.

## Initialize from a borrowed mapping after complete root/resource validation. Duplicates reject.
## Allocation exhaustion follows the project's fail-stop policy; the store owns all published bytes.
proc newStateStore*(entries: openArray[StateEntry], limits: StateStoreLimits): StateStoreResult[StateStore] =
  let committed = stateTrieRoot(entries, limits.trie)
  if committed.error != StateTrieError.None:
    # Reject limits/duplicates/backend failures before retaining or copying any caller value.
    return StateStoreResult[StateStore](status: storeError(committed.error))
  var owned = newSeq[StateEntry](entries.len)
  # Root validation has already bounded entry and value extents before owned allocation.
  for i, entry in entries:
    owned[i] = StateEntry(key: entry.key, value: copyBytes(entry.value))
  owned.sort(compareEntry)
  let data = SnapshotData(entries: owned, commitment: committed.value, limits: limits)
  StateStoreResult[StateStore](status: StateStoreError.None,
    completed: StateStore(head: data, limits: limits))

## Retain the current immutable version independently of future store updates or handle destruction.
proc snapshot*(store: StateStore): StateStoreResult[StateStoreSnapshot] =
  if store.head == nil:
    # A default handle cannot masquerade as an initialized empty map.
    return StateStoreResult[StateStoreSnapshot](status: StateStoreError.Uninitialized)
  StateStoreResult[StateStoreSnapshot](status: StateStoreError.None,
    completed: StateStoreSnapshot(data: store.head))

## Start an independently updateable complete-map branch from this retained version, without hashing.
## Inherit its original resource policy; future writes cannot mutate the source or loosen its ceilings.
proc forkStateStore*(source: StateStoreSnapshot): StateStoreResult[StateStore] =
  let data = source.data
  if data == nil:
    # Default snapshots cannot authorize a store with a fabricated empty map or default policy.
    return StateStoreResult[StateStore](status: StateStoreError.Uninitialized)
  StateStoreResult[StateStore](status: StateStoreError.None,
    completed: StateStore(head: data, limits: data.limits))

## Return copied root/count metadata, never a mutable reference into the retained map.
proc commitment*(snapshot: StateStoreSnapshot): StateTrieCommitment {.requires: snapshot.data != nil.} =
  let data = snapshot.data
  assert data != nil # Retain one stable owner for the contract-proved access.
  data.commitment

## Find a full key in a published sorted map. Missing and present-empty values are distinct.
proc lookup*(snapshot: StateStoreSnapshot, key: StateKey): StateStoreResult[StateValue] =
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

## Read the exact retained value length, including zero; default views are not valid values.
proc byteLength*(view: StateValue): int {.requires: view.owner.data != nil.} =
  let data = view.owner.data
  assert data != nil # Bind the validated view owner once before accessing its immutable storage.
  data.entries[view.position].value.len

## Copy bytes out of the retained view; callers can mutate the copy without changing any snapshot.
proc bytes*(view: StateValue): seq[byte] {.requires: view.owner.data != nil.} =
  let data = view.owner.data
  assert data != nil # Bind the validated view owner once before copying its immutable storage.
  copyBytes(data.entries[view.position].value)

## Merge unique sorted mutations into a private candidate, then publish only after the root succeeds.
## Empty batches retain the existing version. Failure leaves the store and every old snapshot unchanged.
proc apply*(store: var StateStore, writes: openArray[StateWrite]): StateStoreResult[
    StateStoreSnapshot] =
  let head = store.head
  if head == nil:
    # Initialization is required even for a no-op batch.
    return StateStoreResult[StateStoreSnapshot](status: StateStoreError.Uninitialized)
  if uint64(writes.len) > uint64(store.limits.writes):
    # Bound input-derived sorting scratch before allocating it.
    return StateStoreResult[StateStoreSnapshot](status: StateStoreError.LimitExceeded)
  if writes.len > high(int) div sizeof(WriteIndex):
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
  let committed = stateTrieRoot(candidate, store.limits.trie)
  if committed.error != StateTrieError.None:
    # Node-policy or late hash failure drops the private candidate; the old head is still published.
    return StateStoreResult[StateStoreSnapshot](status: storeError(committed.error))
  let data = SnapshotData(entries: candidate, commitment: committed.value, limits: store.limits)
  store.head = data # This is the sole publication point, reached only after complete success.
  StateStoreResult[StateStoreSnapshot](status: StateStoreError.None,
    completed: StateStoreSnapshot(data: data))
