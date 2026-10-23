# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restore an independently selected complete map from verified partial evidence only after full-map root equality proves completeness.
import ./[proof_view, trie_proof, store]
import ../codec/[bounded, state_trie]
type
  ProofStateImportLimits* = object ## Input lookup traversal and temporary entry copies are independent of the resulting complete store's inherited policies.
    lookups*: ElementLimit
    copyBytes*: ByteLimit
    store*: StateStoreLimits
  ProofStateImportError* {.pure.} = enum ## Partial evidence and root disagreement never become successful complete snapshots.
    Uninitialized, None, InvalidView, WrongRoot, LimitExceeded, Incomplete, StoreFailure
  ProofStateImportResult* = object ## No default/refused conversion exposes a partial store, candidate root or usable prefix.
    case status: ProofStateImportError
    of None: completed: StateStore
    of StoreFailure: storeReason: StateStoreError
    else: discard # Only recomputed expected-root equality grants complete-map ownership.
func error*(outcome: ProofStateImportResult): ProofStateImportError =
  ## Observe immutable conversion stages without granting their candidate storage.
  outcome.status
func value*(outcome: ProofStateImportResult): StateStore {.inline, requires: outcome.status ==
    ProofStateImportError.None.} =
  ## Extract only an independently owned complete map authenticated against the caller's expected root.
  outcome.completed
func storeFailure*(outcome: ProofStateImportResult): StateStoreError {.inline,
    requires: outcome.status == ProofStateImportError.StoreFailure.} =
  ## Preserve exact complete-store node/resource/backend refusal separately from local copy admission.
  outcome.storeReason
proc importProofState*(source: ProofView, expected: StateRoot,
    limits: ProofStateImportLimits): ProofStateImportResult =
  ## Never infer completeness from witness count or a view's own root; rebuild all present facts and compare to an independently supplied complete commitment.
  template fail(reason: ProofStateImportError) =
    return ProofStateImportResult(status: reason)
  if not source.valid: fail(ProofStateImportError.InvalidView)
  if array[32, byte](source.root) != array[32, byte](expected): fail(
      ProofStateImportError.WrongRoot)
  if uint64(source.len) > uint64(limits.lookups): fail(ProofStateImportError.LimitExceeded)
  var available = min(uint64(limits.copyBytes), uint64(high(int)))
  var valueBytes = uint64(limits.store.trie.totalValueBytes)
  var entries = 0
  for i in 0..<source.len:
    let lookup = source.lookupAt(i).value
    if lookup.present:
      if uint64(entries) >= uint64(limits.store.trie.items) or available < uint64(sizeof(StateEntry)):
        fail(ProofStateImportError.LimitExceeded) # Present-empty values consume real descriptors and map entries too.
      available -= uint64(sizeof(StateEntry))
      let size = uint64(lookup.byteLength)
      if size > uint64(limits.store.trie.perValue) or size > valueBytes or size > available:
        fail(ProofStateImportError.LimitExceeded) # Subtraction admits every copied payload before any allocation or hashing.
      valueBytes -= size
      available -= size
      inc entries # Input length already bounds the signed native counter.
  var copied = newSeq[StateEntry](entries)
  var next = 0
  for i in 0..<source.len:
    let lookup = source.lookupAt(i).value
    if lookup.present:
      copied[next] = StateEntry(key: lookup.key, value: lookup.bytes)
      inc next # Only admitted present facts contribute to a candidate complete map; absence adds no fabricated value.
  let made = newStateStore(copied, limits.store)
  if made.error != StateStoreError.None:
    return ProofStateImportResult(status: ProofStateImportError.StoreFailure,
        storeReason: made.error)
  if array[32, byte](made.value.snapshot.value.commitment.root) != array[32, byte](expected):
    fail(ProofStateImportError.Incomplete) # A valid partial view cannot substitute its witnessed subset for the original complete map.
  ProofStateImportResult(status: ProofStateImportError.None, completed: made.value)
