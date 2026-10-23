# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable bounded partial lookup retention at one caller-trusted complete root, with explicit unknown keys.
## Admission verifies whole batches before publication; forgetting never claims protocol absence.
import std/[algorithm, assertions]
import ./state_proof
import ../codec/[state_layout, state_trie, bounded]

type
  LightCacheLimits* = object ## Bound retained logical entries/values, batch keys and individual proof work independently.
    items*, writes*: ElementLimit
    valueBytes*: ByteLimit
    proof*: StateProofLimits
  LightStateProof* = object ## Stable borrowed input binds an untrusted detached proof to its exact query.
    key*: StateKey
    proof*: StateProof
  LightProofReader* = proc(index: int): LightStateProof {.closure.}
    ## Borrowed synchronous transport source; restoration never retains this closure or its captured backing input.
  LightCacheError* {.pure.} = enum ## Unknown local data is distinct from an authenticated Absent lookup.
    Uninitialized, None, UnknownKey, LimitExceeded, LengthOverflow, DuplicateKey,
    InvalidProof, IncompleteProof, ValueMismatch, BackendFailure
  CacheEntry = object ## Sorted immutable entries retain verified lookup owners without copying raw values.
    key: StateKey
    lookup: VerifiedStateLookup
    valueBytes: uint64
  CacheData = ref object ## One acyclic snapshot owns its fixed root, inherited policy and exact sorted entry buffer.
    root: StateRoot
    limits: LightCacheLimits
    entries: seq[CacheEntry]
    valueBytes: uint64
  LightStateCache* = object ## Copies retain one immutable partial cache; no complete-state commitment API is provided.
    data: nil CacheData
  LightCacheResult*[T] = object ## Default/failure alternatives contain only their reason.
    case status: LightCacheError
    of None:
      completed: T
    else:
      discard
  KeyIndex = object ## Fixed key/source positions keep sorting independent of borrowed payload ownership.
    key: StateKey
    index: int

func error*[T](outcome: LightCacheResult[T]): LightCacheError =
  ## Read a typed reason without granting access to an incomplete lookup or cache revision.
  outcome.status
func value*[T](outcome: LightCacheResult[T]): T {.inline,
    requires: outcome.status == LightCacheError.None.} =
  ## Only completed success authorizes immutable cache/lookup extraction.
  outcome.completed
proc newLightStateCache*(root: StateRoot, limits: LightCacheLimits): LightStateCache =
  ## Bind an empty partial cache to a caller-trusted root; all caller policies permit an empty cache.
  LightStateCache(data: CacheData(root: root, limits: limits, entries: @[], valueBytes: 0))
proc root*(cache: LightStateCache): StateRoot {.requires: cache.data != nil.} =
  ## Return the exact external trust binding, never a recomputed partial-map root.
  let data = cache.data
  assert data != nil
  data.root
proc len*(cache: LightStateCache): int {.requires: cache.data != nil.} =
  ## Count retained authenticated positive and negative lookups equally.
  let data = cache.data
  assert data != nil
  data.entries.len
proc valueBytes*(cache: LightStateCache): uint64 {.requires: cache.data != nil.} =
  ## Report retained logical present bytes, excluding allocator classes and per-entry metadata.
  let data = cache.data
  assert data != nil
  data.valueBytes
proc limits*(cache: LightStateCache): LightCacheLimits {.requires: cache.data != nil.} =
  ## Return copied policy metadata; updates/forgetting inherit it exactly.
  let data = cache.data
  assert data != nil
  data.limits
func compareKey(left, right: StateKey): int =
  ## Lexicographic fixed-key order supplies deterministic exact lookup and batch merging.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for index in 0..<31:
    if a[index] < b[index]: return -1 # Later bytes cannot reverse this first difference.
    if a[index] > b[index]: return 1
  0
proc compareIndex(left, right: KeyIndex): int =
  ## Sort fixed identities without touching borrowed proof nodes or raw values.
  compareKey(left.key, right.key)
proc find(entries: openArray[CacheEntry], key: StateKey): int =
  ## A bounded binary search distinguishes missing local evidence from a stored negative lookup.
  var lower = 0
  var upper = entries.len
  while lower < upper:
    let middle = lower+(upper-lower) div 2
    if compareKey(entries[middle].key, key) < 0: lower = middle+1
    else: upper = middle
  if lower < entries.len and compareKey(entries[lower].key, key) == 0: lower else: -1
proc lookup*(cache: LightStateCache, key: StateKey): LightCacheResult[VerifiedStateLookup] =
  ## Return retained authenticated evidence or an explicit unknown/default reason, never invented absence.
  let data = cache.data
  if data == nil:
    return LightCacheResult[VerifiedStateLookup](status: LightCacheError.Uninitialized)
  let index = find(data.entries, key)
  if index < 0:
    return LightCacheResult[VerifiedStateLookup](status: LightCacheError.UnknownKey)
  LightCacheResult[VerifiedStateLookup](status: LightCacheError.None, completed: data.entries[index].lookup)
func batchError(count: int, limits: LightCacheLimits): LightCacheError =
  ## Bound both sorted indices and validated lookup scratch before either native allocation.
  if uint64(count) > uint64(limits.writes): return LightCacheError.LimitExceeded
  if count > high(int) div sizeof(KeyIndex) or count > high(int) div sizeof(CacheEntry):
    return LightCacheError.LengthOverflow
  LightCacheError.None
proc unique(ordered: openArray[KeyIndex]): bool =
  ## Even identical repeated requests violate the atomic unique-key batch contract.
  for index in 1..<ordered.len:
    if compareKey(ordered[index-1].key, ordered[index].key) == 0: return false
  true
func proofError(reason: StateProofError): LightCacheError =
  ## Preserve operational proof failure classes without exposing partial validation progress.
  case reason
  of StateProofError.None: LightCacheError.None
  of StateProofError.Uninitialized, StateProofError.InvalidProof: LightCacheError.InvalidProof
  of StateProofError.LimitExceeded: LightCacheError.LimitExceeded
  of StateProofError.IncompleteProof: LightCacheError.IncompleteProof
  of StateProofError.ValueMismatch: LightCacheError.ValueMismatch
  of StateProofError.BackendFailure: LightCacheError.BackendFailure
proc admit*(cache: LightStateCache, updates: openArray[LightStateProof]): LightCacheResult[
    LightStateCache] =
  ## Verify one unique-key batch at the fixed root, then publish an exact immutable sorted replacement.
  let data = cache.data
  if data == nil:
    return LightCacheResult[LightStateCache](status: LightCacheError.Uninitialized)
  let bounded = batchError(updates.len, data.limits)
  if bounded != LightCacheError.None: return LightCacheResult[LightStateCache](status: bounded)
  if updates.len == 0:
    return LightCacheResult[LightStateCache](status: LightCacheError.None, completed: cache)
  let proofPolicy = data.limits.proof
  for update in updates:
    let nodes = uint64(update.proof.nodes.len)
    let size = uint64(update.proof.value.len)
    if nodes > 249 or nodes > uint64(proofPolicy.nodes) or size > uint64(proofPolicy.valueBytes):
      # Bound every proof's shape and payload before sorting or any hash attempt.
      return LightCacheResult[LightStateCache](status: LightCacheError.LimitExceeded)
  var ordered = newSeq[KeyIndex](updates.len)
  for index, update in updates: ordered[index] = KeyIndex(key: update.key, index: index)
  ordered.sort(compareIndex)
  if not unique(ordered):
    return LightCacheResult[LightStateCache](status: LightCacheError.DuplicateKey)
  var count = data.entries.len
  var bytes = data.valueBytes
  # Release every overwritten allowance before checking new values, independent of query order.
  for index in ordered:
    let old = find(data.entries, index.key)
    if old >= 0:
      dec count
      bytes -= data.entries[old].valueBytes
  for index in ordered:
    if uint64(count) >= uint64(data.limits.items):
      return LightCacheResult[LightStateCache](status: LightCacheError.LimitExceeded)
    if count >= high(int) div sizeof(CacheEntry):
      return LightCacheResult[LightStateCache](status: LightCacheError.LengthOverflow) # Prove the final exact descriptor extent before increment.
    let size = uint64(updates[index.index].proof.value.len)
    if size > uint64(data.limits.valueBytes)-bytes:
      return LightCacheResult[LightStateCache](status: LightCacheError.LimitExceeded) # Existing invariant makes subtraction and addition safe.
    inc count
    bytes += size
  var verified = newSeq[CacheEntry](updates.len)
  # Private completed lookup scratch retires as a whole if any later proof/provider fails.
  for slot, index in ordered:
    let checked = verifyStateProof(data.root, index.key, updates[index.index].proof,
        data.limits.proof)
    if checked.error != StateProofError.None:
      return LightCacheResult[LightStateCache](status: proofError(checked.error))
    verified[slot] = CacheEntry(key: index.key, lookup: checked.value,
      valueBytes: uint64(updates[index.index].proof.value.len))
  var entries = newSeq[CacheEntry](count)
  var old = 0
  var fresh = 0
  var next = 0
  # Merge exact sorted maps once, sharing unchanged lookup owners and replacing equal keys.
  while old < data.entries.len or fresh < verified.len:
    assert next < entries.len
    if fresh == verified.len or (old < data.entries.len and compareKey(data.entries[old].key,
        verified[fresh].key) < 0):
      entries[next] = data.entries[old]
      inc old
    else:
      if old < data.entries.len and compareKey(data.entries[old].key, verified[fresh].key) == 0: inc old
      entries[next] = verified[fresh]
      inc fresh
    inc next
  assert next == entries.len
  LightCacheResult[LightStateCache](status: LightCacheError.None,
    completed: LightStateCache(data: CacheData(root: data.root, limits: data.limits,
      entries: entries, valueBytes: bytes)))
proc contains(ordered: openArray[KeyIndex], key: StateKey): bool =
  ## Binary-search forgotten keys without allocating a second mutable membership structure.
  var lower = 0
  var upper = ordered.len
  while lower < upper:
    let middle = lower+(upper-lower) div 2
    if compareKey(ordered[middle].key, key) < 0: lower = middle+1
    else: upper = middle
  lower < ordered.len and compareKey(ordered[lower].key, key) == 0
proc forget*(cache: LightStateCache, keys: openArray[StateKey]): LightCacheResult[LightStateCache] =
  ## Drop selected local evidence atomically; absence of a retained entry remains UnknownKey.
  let data = cache.data
  if data == nil:
    return LightCacheResult[LightStateCache](status: LightCacheError.Uninitialized)
  let bounded = batchError(keys.len, data.limits)
  if bounded != LightCacheError.None: return LightCacheResult[LightStateCache](status: bounded)
  if keys.len == 0:
    return LightCacheResult[LightStateCache](status: LightCacheError.None, completed: cache)
  var ordered = newSeq[KeyIndex](keys.len)
  for index, key in keys: ordered[index] = KeyIndex(key: key, index: index)
  ordered.sort(compareIndex)
  if not unique(ordered):
    return LightCacheResult[LightStateCache](status: LightCacheError.DuplicateKey)
  var count = data.entries.len
  var bytes = data.valueBytes
  for index in ordered:
    let old = find(data.entries, index.key)
    if old >= 0:
      dec count
      bytes -= data.entries[old].valueBytes # Stored authenticated absences consume zero logical value bytes.
  if count == data.entries.len:
    return LightCacheResult[LightStateCache](status: LightCacheError.None,
        completed: cache) # Unknown-only removal reuses the snapshot without output allocation or hashing.
  var entries = newSeq[CacheEntry](count)
  var next = 0
  for index in 0..<data.entries.len:
    let entry = data.entries[index] # Keep retained proof access indexed through the immutable cache owner.
    if not contains(ordered, entry.key):
      assert next < entries.len
      entries[next] = entry # Retained views share immutable proof results rather than raw mutable buffers.
      inc next
  assert next == entries.len
  LightCacheResult[LightStateCache](status: LightCacheError.None,
    completed: LightStateCache(data: CacheData(root: data.root, limits: data.limits,
      entries: entries, valueBytes: bytes)))

proc newLightStateCache*(root: StateRoot, updates: openArray[LightStateProof],
    limits: LightCacheLimits): LightCacheResult[LightStateCache] =
  ## Restore a complete bounded proof set independently of future mutation-batch ceilings.
  ## The fresh unpublished owner receives the original exact policy only after full proof admission.
  var initial = limits
  initial.writes = ElementLimit(updates.len)
  let empty = newLightStateCache(root, initial)
  let admitted = empty.admit(updates)
  if admitted.error != LightCacheError.None: return admitted # Failures expose no partially restored cache.
  let data = admitted.value.data
  assert data != nil # Every owner reference is still local to this constructor until return.
  data.limits = limits
  admitted

proc restoreLightStateCache*(root: StateRoot, count: int,
    reader: nil LightProofReader,
    limits: LightCacheLimits): LightCacheResult[LightStateCache] =
  ## Verify a synchronous canonical proof stream into one private final cache, publishing no partial prefix.
  if reader == nil: return LightCacheResult[LightStateCache](status: LightCacheError.Uninitialized)
  if count < 0 or uint64(count) > uint64(limits.items):
    return LightCacheResult[LightStateCache](status: LightCacheError.LimitExceeded)
  if count > high(int) div sizeof(CacheEntry):
    return LightCacheResult[LightStateCache](status: LightCacheError.LengthOverflow)
  var entries = newSeq[CacheEntry](count)
  var total = 0'u64
  var previous = default(StateKey)
  for index in 0..<count:
    # Each borrowed callback returns only untrusted transport; no caller-selected success can bypass proof verification.
    let update = reader(index)
    let nodes = uint64(update.proof.nodes.len)
    let size = uint64(update.proof.value.len)
    if nodes > 249 or nodes > uint64(limits.proof.nodes) or size > uint64(limits.proof.valueBytes):
      return LightCacheResult[LightStateCache](status: LightCacheError.LimitExceeded)
    if index > 0:
      let comparison = compareKey(previous, update.key)
      if comparison == 0: return LightCacheResult[LightStateCache](
          status: LightCacheError.DuplicateKey)
      if comparison > 0: return LightCacheResult[LightStateCache](
          status: LightCacheError.InvalidProof)
    if size > uint64(limits.valueBytes)-total:
      return LightCacheResult[LightStateCache](status: LightCacheError.LimitExceeded)
    let checked = verifyStateProof(root, update.key, update.proof, limits.proof)
    if checked.error != StateProofError.None:
      return LightCacheResult[LightStateCache](status: proofError(checked.error))
    entries[index] = CacheEntry(key: update.key, lookup: checked.value, valueBytes: size)
    total += size # The remaining aggregate quota proves this addition before the next callback.
    previous = update.key
  LightCacheResult[LightStateCache](status: LightCacheError.None,
    completed: LightStateCache(data: CacheData(root: root, limits: limits, entries: entries,
        valueBytes: total)))
