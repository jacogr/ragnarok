# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generate bounded witnesses from the existing complete immutable snapshot interface.
## No storage internals, database format or partial-state publication are involved.
import ./[store, trie_proof]
import ../codec/[bounded, state_layout, state_trie]

proc copySnapshotEntries(snapshot: StateStoreSnapshot, mapLimits: StateTrieLimits,
    entries: var seq[StateEntry]): StateProofError =
  ## Preflight every retained value extent before copying a complete borrowed snapshot into scratch.
  if snapshot.keyAt(StateEntryIndex(0)).error == StateStoreError.Uninitialized:
    return StateProofError.Uninitialized
  let count = snapshot.commitment.entries
  if uint64(count) > uint64(mapLimits.items):
    return StateProofError.LimitExceeded
  if count > high(int) div sizeof(StateEntry):
    return StateProofError.LengthOverflow
  var total = 0'u64
  for i in 0..<count:
    # Inspect owner-bound sizes without allocating detached payloads.
    let key = snapshot.keyAt(StateEntryIndex(i))
    if key.error != StateStoreError.None:
      return StateProofError.StoreFailure
    let found = snapshot.lookup(key.value)
    if found.error != StateStoreError.None:
      return StateProofError.StoreFailure
    let size = uint64(found.value.byteLength)
    if size > uint64(mapLimits.perValue) or size > uint64(mapLimits.totalValueBytes)-total:
      return StateProofError.LimitExceeded
    total += size
  entries = newSeq[StateEntry](count)
  for i in 0..<count:
    # All extents are bounded; immutable source identity cannot change between these synchronous reads.
    let key = snapshot.keyAt(StateEntryIndex(i)).value
    entries[i] = StateEntry(key: key, value: snapshot.lookup(key).value.bytes)
  StateProofError.None

proc generateStateProof*(snapshot: StateStoreSnapshot, query: StateKey,
    mapLimits: StateTrieLimits, limits: StateProofLimits): StateProofResult[StateProof] =
  ## Single paths retain the same preflighted complete snapshot contract as batch generation.
  var entries: seq[StateEntry] = @[]
  let copied = copySnapshotEntries(snapshot, mapLimits, entries)
  if copied != StateProofError.None:
    return proofFailure[StateProof](copied)
  generateStateProof(entries, query, mapLimits, limits)

proc generateStateProofs*(snapshot: StateStoreSnapshot, queries: openArray[StateKey],
    mapLimits: StateTrieLimits, limits: StateProofLimits,
    aggregate: StateProofBatchLimits): StateProofResult[StateProofSet] =
  ## Copy the bounded complete map once per atomic batch, preserving requested order and duplicates.
  if uint64(queries.len) > uint64(aggregate.items) or queries.len > high(int) div sizeof(StateProofQuery):
    return proofFailure[StateProofSet](StateProofError.LimitExceeded)
  var entries: seq[StateEntry] = @[]
  let copied = copySnapshotEntries(snapshot, mapLimits, entries)
  if copied != StateProofError.None:
    return proofFailure[StateProofSet](copied)
  generateStateProofs(entries, queries, mapLimits, limits, aggregate)
