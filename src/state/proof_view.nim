# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable partial verified read evidence. Unknown keys never become absent state.
## These owners cannot substitute for complete StateStore snapshots or certify a new state root.
import std/[algorithm, assertions]
import ./trie_proof
import ../codec/[bounded, state_layout, state_trie]
type
  ProofViewLimits* = object ## Count and retained logical value bytes bound this partial evidence collection.
    items*: ElementLimit
    valueBytes*: ByteLimit
  ProofViewError* {.pure.} = enum ## Missing witnesses are distinct from a successfully verified absent lookup.
    Uninitialized, None, WrongRoot, DuplicateKey, LimitExceeded, MissingWitness,
    InvalidIndex, ConflictingEvidence, InvalidValue
  ViewData = ref object ## Sorted immutable verified lookups share only already immutable witness owners.
    root: StateRoot
    entries: seq[VerifiedStateLookup]
  ProofView* = object ## Partial read authority is nominally separate from a complete-map snapshot.
    data: nil ViewData
  ProofViewResult*[T] = object ## No failure exposes a partially captured view or lookup.
    case status: ProofViewError
    of None:
      completed: T
    else:
      discard                  # Default and failed results retain only their reason.
func error*[T](outcome: ProofViewResult[T]): ProofViewError =
  ## Inspect a reason without granting payload access.
  outcome.status
func value*[T](outcome: ProofViewResult[T]): T {.inline, requires:
    outcome.status == ProofViewError.None.} =
  ## Require explicit successful selection before extracting immutable evidence.
  outcome.completed
func valid*(view: ProofView): bool =
  ## A default collection has no root authority.
  view.data != nil
func len*(view: ProofView): int =
  ## No entries are fabricated for an uninitialized owner.
  let data = view.data
  if data == nil: 0 else: data.entries.len
proc root*(view: ProofView): StateRoot {.requires: view.data != nil.} =
  ## Return the exact independently selected root common to every retained witness.
  let data = view.data
  assert data != nil
  data.root
func compareKey(left, right: StateKey): int =
  ## Fixed-key lexicographic order supports deterministic enumeration and exact lookup.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for i in 0..<31:
    # Compare only copied identities; payload bytes do not participate in ordering.
    if a[i] < b[i]: return -1
    if a[i] > b[i]: return 1
  0
proc compare(left, right: VerifiedStateLookup): int =
  ## Adapt sorting without copying or decoding retained values.
  compareKey(left.key, right.key)
proc captureProofView*(batch: VerifiedStateProofBatch, expectedRoot: StateRoot,
    limits: ProofViewLimits): ProofViewResult[ProofView] =
  ## Accept only genuinely verified evidence under the exact caller-supplied root.
  if not batch.valid:
    return ProofViewResult[ProofView](status: ProofViewError.Uninitialized)
  if uint64(batch.len) > uint64(limits.items) or batch.len > high(int) div sizeof(VerifiedStateLookup):
    return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
  var bytes = 0'u64
  for i in 0..<batch.len:
    # Current root/value budgets precede sorting scratch allocation and publication.
    let lookup = batch.lookupAt(i).value
    if array[32, byte](lookup.root) != array[32, byte](expectedRoot):
      return ProofViewResult[ProofView](status: ProofViewError.WrongRoot)
    if lookup.present:
      let size = uint64(lookup.byteLength)
      if size > uint64(limits.valueBytes)-bytes:
        return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
      bytes += size
  var entries = newSeq[VerifiedStateLookup](batch.len)
  for i in 0..<batch.len:
    entries[i] = batch.lookupAt(i).value # Retain only immutable existing witness owners.
  entries.sort(compare)
  for i in 1..<entries.len:
    # A view has one fact per key; callers must resolve duplicate requests explicitly.
    if compareKey(entries[i-1].key, entries[i].key) == 0:
      return ProofViewResult[ProofView](status: ProofViewError.DuplicateKey)
  ProofViewResult[ProofView](status: ProofViewError.None,
    completed: ProofView(data: ViewData(root: expectedRoot, entries: entries)))
proc lookupAt*(view: ProofView, index: int): ProofViewResult[VerifiedStateLookup] =
  ## Sorted ordinals stay bound to this exact retained partial owner.
  let data = view.data
  if data == nil:
    return ProofViewResult[VerifiedStateLookup](status: ProofViewError.Uninitialized)
  if index < 0 or index >= data.entries.len:
    return ProofViewResult[VerifiedStateLookup](status: ProofViewError.InvalidIndex)
  ProofViewResult[VerifiedStateLookup](status: ProofViewError.None, completed: data.entries[index])
