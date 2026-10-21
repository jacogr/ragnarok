# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generate bounded witnesses from the existing complete immutable snapshot interface.
## No storage internals, database format or partial-state publication are involved.
import ./[store, trie_proof]
import ../codec/[bounded, state_layout, state_trie]

proc generateStateProof*(snapshot: StateStoreSnapshot, query: StateKey,
    mapLimits: StateTrieLimits, limits: StateProofLimits): StateProofResult[StateProof] =
  ## Preflight every retained value extent before copying a complete borrowed snapshot into scratch.
  if snapshot.keyAt(StateEntryIndex(0)).error == StateStoreError.Uninitialized:
    return proofFailure[StateProof](StateProofError.Uninitialized)
  let count = snapshot.commitment.entries
  if uint64(count) > uint64(mapLimits.items):
    return proofFailure[StateProof](StateProofError.LimitExceeded)
  if count > high(int) div sizeof(StateEntry):
    return proofFailure[StateProof](StateProofError.LengthOverflow)
  var total = 0'u64
  for i in 0..<count:
    # Inspect owner-bound sizes without allocating detached payloads.
    let key = snapshot.keyAt(StateEntryIndex(i))
    if key.error != StateStoreError.None:
      return proofFailure[StateProof](StateProofError.StoreFailure)
    let found = snapshot.lookup(key.value)
    if found.error != StateStoreError.None:
      return proofFailure[StateProof](StateProofError.StoreFailure)
    let size = uint64(found.value.byteLength)
    if size > uint64(mapLimits.perValue) or size > uint64(mapLimits.totalValueBytes)-total:
      return proofFailure[StateProof](StateProofError.LimitExceeded)
    total += size
  var entries = newSeq[StateEntry](count)
  for i in 0..<count:
    # All extents are bounded; immutable source identity cannot change between these synchronous reads.
    let key = snapshot.keyAt(StateEntryIndex(i)).value
    entries[i] = StateEntry(key: key, value: snapshot.lookup(key).value.bytes)
  generateStateProof(entries, query, mapLimits, limits)
