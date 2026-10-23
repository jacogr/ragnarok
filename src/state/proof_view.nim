# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable partial verified read evidence. Unknown keys never become absent state.
## These owners cannot substitute for complete StateStore snapshots or certify a new state root.
import std/[algorithm, assertions]
import ./trie_proof
import ./proof_plan
import ../codec/[bounded, state_layout, state_trie, state_safrole]
type
  ProofViewLimits* = object ## Count and retained logical value bytes bound this partial evidence collection.
    items*: ElementLimit
    valueBytes*: ByteLimit
  ProofViewError* {.pure.} = enum ## Missing witnesses are distinct from a successfully verified absent lookup.
    Uninitialized, None, WrongRoot, DuplicateKey, LimitExceeded, MissingWitness,
    InvalidIndex, ConflictingEvidence, InvalidValue, AbsentValue, ProofFailure, NonCanonical,
      Truncated, LengthOverflow
  ViewData = ref object ## Sorted immutable verified lookups share only already immutable witness owners.
    root: StateRoot
    entries: seq[VerifiedStateLookup]
  ProofView* = object ## Partial read authority is nominally separate from a complete-map snapshot.
    data: nil ViewData
  ProofViewResult*[T] = object ## No failure exposes a partially captured view or lookup.
    case status: ProofViewError
    of None:
      completed: T
    of ProofFailure:
      proofReason: StateProofError
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

proc lookup*(view: ProofView, query: StateKey): ProofViewResult[VerifiedStateLookup] =
  ## Resolve exact retained evidence; an unknown key is not a proof of absence.
  let data = view.data
  if data == nil:
    return ProofViewResult[VerifiedStateLookup](status: ProofViewError.Uninitialized)
  var first = 0
  var stop = data.entries.len
  while first < stop:
    # Overflow-safe binary search never decodes or copies authenticated payloads.
    let middle = first + (stop-first) div 2
    let order = compareKey(data.entries[middle].key, query)
    if order < 0: first = middle+1
    elif order > 0: stop = middle
    else:
      return ProofViewResult[VerifiedStateLookup](status: ProofViewError.None,
        completed: data.entries[middle])
  ProofViewResult[VerifiedStateLookup](status: ProofViewError.MissingWitness)

proc mergeProofViews*(left, right: ProofView, limits: ProofViewLimits): ProofViewResult[ProofView] =
  ## Form a bounded immutable union under one root; preserve both inputs on every failure.
  let a = left.data
  let b = right.data
  if a == nil:
    return ProofViewResult[ProofView](status: ProofViewError.Uninitialized)
  if b == nil:
    return ProofViewResult[ProofView](status: ProofViewError.Uninitialized)
  if array[32, byte](a.root) != array[32, byte](b.root):
    return ProofViewResult[ProofView](status: ProofViewError.WrongRoot)
  var first = 0
  var second = 0
  var bytes = 0'u64
  var entries: seq[VerifiedStateLookup] = @[]
  while first < a.entries.len or second < b.entries.len:
    # Select one sorted key, coalescing repeated facts only after checking consistency.
    let order = if first >= a.entries.len: 1
      elif second >= b.entries.len: -1
      else: compareKey(a.entries[first].key, b.entries[second].key)
    let chosen = if order <= 0: a.entries[first] else: b.entries[second]
    if uint64(entries.len) >= uint64(limits.items) or entries.len >= high(int) div sizeof(VerifiedStateLookup):
      return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
    if chosen.present:
      let size = uint64(chosen.byteLength)
      if size > uint64(limits.valueBytes)-bytes:
        return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
      bytes += size
    if order == 0:
      # Duplicate keys must agree on presence and exact bytes, never last-writer-wins.
      let other = b.entries[second]
      if not sameVerifiedLookup(chosen, other).value:
        return ProofViewResult[ProofView](status: ProofViewError.ConflictingEvidence) # Exact immutable fact comparison copies no potentially large duplicate payload.
      inc first
      inc second
    elif order < 0:
      inc first # Only the left input contributed this unique key.
    else:
      inc second # Only the right input contributed this unique key.
    entries.add(chosen) # Retain an immutable owner after its current output budget passes.
  ProofViewResult[ProofView](status: ProofViewError.None,
    completed: ProofView(data: ViewData(root: a.root, entries: entries)))

proc projectProofView*(source: ProofView, queries: openArray[StateKey],
    limits: ProofViewLimits): ProofViewResult[ProofView] =
  ## Retain only explicitly requested existing evidence, without widening source root authority.
  if not source.valid:
    return ProofViewResult[ProofView](status: ProofViewError.Uninitialized)
  if uint64(queries.len) > uint64(limits.items) or queries.len > high(int) div sizeof(VerifiedStateLookup):
    return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
  var bytes = 0'u64
  var entries = newSeq[VerifiedStateLookup](queries.len)
  for i, query in queries:
    # Missing evidence refuses atomically; the requested key is never inferred absent.
    let found = source.lookup(query)
    if found.error != ProofViewError.None:
      return ProofViewResult[ProofView](status: found.error)
    let lookup = found.value
    if lookup.present:
      let size = uint64(lookup.byteLength)
      if size > uint64(limits.valueBytes)-bytes:
        return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
      bytes += size
    entries[i] = lookup
  entries.sort(compare)
  for i in 1..<entries.len:
    # Projections preserve the unique-key collection contract regardless of request order.
    if compareKey(entries[i-1].key, entries[i].key) == 0:
      return ProofViewResult[ProofView](status: ProofViewError.DuplicateKey)
  ProofViewResult[ProofView](status: ProofViewError.None,
    completed: ProofView(data: ViewData(root: source.root, entries: entries)))

proc exportProofQueries*(view: ProofView, limits: ProofViewLimits): ProofViewResult[seq[
    StateProofQuery]] =
  ## Export detached request records with immutable raw witnesses under an explicitly rechecked policy.
  let data = view.data
  if data == nil:
    return ProofViewResult[seq[StateProofQuery]](status: ProofViewError.Uninitialized)
  if uint64(data.entries.len) > uint64(limits.items) or
      data.entries.len > high(int) div sizeof(StateProofQuery):
    return ProofViewResult[seq[StateProofQuery]](status: ProofViewError.LimitExceeded)
  var bytes = 0'u64
  for lookup in data.entries:
    # Tightened value ceilings refuse before allocating the output request array.
    if lookup.present:
      let size = uint64(lookup.byteLength)
      if size > uint64(limits.valueBytes)-bytes:
        return ProofViewResult[seq[StateProofQuery]](status: ProofViewError.LimitExceeded)
      bytes += size
  var queries = newSeq[StateProofQuery](data.entries.len)
  for i, lookup in data.entries:
    queries[i] = StateProofQuery(key: lookup.key, proof: lookup.witness) # No verified discriminator crosses transport.
  ProofViewResult[seq[StateProofQuery]](status: ProofViewError.None, completed: queries)

func proofError*[T](outcome: ProofViewResult[T]): StateProofError {.requires:
    outcome.status == ProofViewError.ProofFailure.} =
  ## Preserve only an actual underlying proof refusal, never a default nested cause.
  outcome.proofReason
proc encodeProofView*(view: ProofView, limits: ProofViewLimits, perProof: StateProofLimits,
    wireBytes: ByteLimit): ProofViewResult[seq[byte]] =
  ## Encode sorted partial evidence in local RPV1 framing; root trust remains outside the envelope.
  let exported = exportProofQueries(view, limits)
  if exported.error != ProofViewError.None:
    return ProofViewResult[seq[byte]](status: exported.error)
  let queries = exported.value
  if uint64(queries.len) > uint64(high(uint32)):
    return ProofViewResult[seq[byte]](status: ProofViewError.LengthOverflow)
  var total = 8'u64
  if total > uint64(wireBytes):
    return ProofViewResult[seq[byte]](status: ProofViewError.LimitExceeded)
  for query in queries:
    # Preflight individual path/value policies and every outer record addition before output allocation.
    let size = uint64(query.proof.suppliedByteLength.value)
    if uint64(query.proof.len) > uint64(perProof.nodes) or size > uint64(perProof.valueBytes):
      return ProofViewResult[seq[byte]](status: ProofViewError.ProofFailure,
        proofReason: StateProofError.LimitExceeded)
    let encodedSize = 10'u64 + uint64(query.proof.len)*64'u64 + size
    if encodedSize > uint64(high(uint32)):
      return ProofViewResult[seq[byte]](status: ProofViewError.LengthOverflow)
    let record = 35'u64+encodedSize
    if record > uint64(wireBytes)-total:
      return ProofViewResult[seq[byte]](status: ProofViewError.LimitExceeded)
    total += record
  if total > uint64(high(int)):
    return ProofViewResult[seq[byte]](status: ProofViewError.LengthOverflow)
  var output = newSeq[byte](int(total))
  output[0] = byte('R')
  output[1] = byte('P')
  output[2] = byte('V')
  output[3] = byte('1')
  for i in 0..<4:
    output[4+i] = byte((uint64(queries.len) shr (8*i)) and 255) # Fixed E4 record count.
  var offset = 8
  for query in queries:
    # Canonical sorted unique keys come from the immutable view, not mutable exported records.
    let key = array[31, byte](query.key)
    let encoded = encodeStateProof(query.proof, perProof, wireBytes)
    if encoded.error != StateProofError.None:
      return ProofViewResult[seq[byte]](status: ProofViewError.ProofFailure,
        proofReason: encoded.error)
    let wire = encoded.value
    for i in 0..<31: output[offset+i] = key[i]
    for i in 0..<4: output[offset+31+i] = byte((uint64(wire.len) shr (8*i)) and 255)
    offset += 35
    for i, octet in wire: output[offset+i] = octet
    offset += wire.len
  ProofViewResult[seq[byte]](status: ProofViewError.None, completed: output)

proc decodeProofViewImpl(input: openArray[byte], expectedRoot: StateRoot,
    limits: ProofViewLimits, perProof: StateProofLimits, aggregate: StateProofBatchLimits,
    wireBytes: ByteLimit, expected: StateProofPlan): ProofViewResult[ProofView] =
  ## Authenticate an exact local collection under caller trust only after complete structural/budget preflight.
  if uint64(input.len) > uint64(wireBytes):
    return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
  if input.len < 8: return ProofViewResult[ProofView](status: ProofViewError.Truncated)
  if input[0] != byte('R') or input[1] != byte('P') or input[2] != byte('V') or input[3] != byte('1'):
    return ProofViewResult[ProofView](status: ProofViewError.NonCanonical)
  var count = 0'u64
  for i in 0..<4:
    count = count or (uint64(input[4+i]) shl (8*i)) # Widen before shifts in the untrusted E4 domain.
  if expected.valid and count != uint64(expected.len):
    return ProofViewResult[ProofView](status: ProofViewError.NonCanonical)
  if count > uint64(limits.items) or count > uint64(aggregate.items):
    return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
  if count > uint64((input.len-8) div 45):
    return ProofViewResult[ProofView](status: ProofViewError.Truncated)
  if count > uint64(high(int) div sizeof(StateProofQuery)):
    return ProofViewResult[ProofView](status: ProofViewError.LengthOverflow)
  var queries = newSeq[StateProofQuery](int(count))
  var offset = 8
  var bytes = 0'u64
  var nodes = 0'u64
  for i in 0..<int(count):
    # Every fixed record header and variable witness extent is checked before access or slicing.
    if input.len-offset < 35:
      return ProofViewResult[ProofView](status: ProofViewError.Truncated)
    var key = default(array[31, byte])
    for j in 0..<31: key[j] = input[offset+j]
    var size = 0'u64
    for j in 0..<4: size = size or (uint64(input[offset+31+j]) shl (8*j))
    offset += 35
    if size > uint64(input.len-offset):
      return ProofViewResult[ProofView](status: ProofViewError.Truncated)
    if size < 10:
      return ProofViewResult[ProofView](status: ProofViewError.NonCanonical)
    let query = StateKey(key)
    if expected.valid and array[31, byte](query) != array[31, byte](expected.keyAt(i).value):
      return ProofViewResult[ProofView](status: ProofViewError.NonCanonical) # Scope precedes witness copying and all crypto.
    if i > 0 and compareKey(queries[i-1].key, query) >= 0:
      return ProofViewResult[ProofView](status: ProofViewError.NonCanonical)
    # Preflight remaining aggregate allowances from the fixed inner header before copying this witness.
    let declaredNodes = uint64(input[offset+4]) or (uint64(input[offset+5]) shl 8)
    var declaredBytes = 0'u64
    for j in 0..<4:
      declaredBytes = declaredBytes or (uint64(input[offset+6+j]) shl (8*j))
    if declaredNodes > uint64(aggregate.nodes)-nodes or
        declaredBytes > uint64(aggregate.valueBytes)-bytes:
      return ProofViewResult[ProofView](status: ProofViewError.ProofFailure,
        proofReason: StateProofError.LimitExceeded)
    if declaredBytes > uint64(limits.valueBytes)-bytes:
      return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
    nodes += declaredNodes
    let decoded = decodeStateProof(input.toOpenArray(offset, offset+int(size)-1), perProof, wireBytes)
    if decoded.error != StateProofError.None:
      return ProofViewResult[ProofView](status: ProofViewError.ProofFailure,
          proofReason: decoded.error)
    let valueBytes = uint64(decoded.value.suppliedByteLength.value)
    if valueBytes > uint64(limits.valueBytes)-bytes:
      return ProofViewResult[ProofView](status: ProofViewError.LimitExceeded)
    bytes += valueBytes
    queries[i] = StateProofQuery(key: query, proof: decoded.value)
    offset += int(size)
  if offset != input.len:
    return ProofViewResult[ProofView](status: ProofViewError.NonCanonical)
  let verified = verifyStateProofs(queries, expectedRoot, perProof, aggregate)
  if verified.error != StateProofError.None:
    return ProofViewResult[ProofView](status: ProofViewError.ProofFailure,
        proofReason: verified.error)
  captureProofView(verified.value, expectedRoot, limits) # No policy can widen after the shared atomic verifier.

proc decodeProofView*(input: openArray[byte], expectedRoot: StateRoot,
    limits: ProofViewLimits, perProof: StateProofLimits, aggregate: StateProofBatchLimits,
    wireBytes: ByteLimit): ProofViewResult[ProofView] =
  ## Preserve the existing unplanned decoder through the same canonical framing and verifier.
  decodeProofViewImpl(input, expectedRoot, limits, perProof, aggregate, wireBytes, default(StateProofPlan))

proc decodeProofView*(input: openArray[byte], expectedRoot: StateRoot,
    limits: ProofViewLimits, perProof: StateProofLimits, aggregate: StateProofBatchLimits,
    wireBytes: ByteLimit, expected: StateProofPlan): ProofViewResult[ProofView] =
  ## Match every declared identity before any witness hashing; invalid expected plans grant no scope.
  if not expected.valid:
    return ProofViewResult[ProofView](status: ProofViewError.Uninitialized)
  decodeProofViewImpl(input, expectedRoot, limits, perProof, aggregate, wireBytes, expected)

proc readProofTime*(view: ProofView): ProofViewResult[StateTime] =
  ## Decode only authenticated C(11) bytes, distinguishing unknown, absent and malformed evidence.
  let found = view.lookup(chapterKey(StateChapter(11)))
  if found.error != ProofViewError.None:
    return ProofViewResult[StateTime](status: found.error)
  if not found.value.present:
    return ProofViewResult[StateTime](status: ProofViewError.AbsentValue)
  if found.value.byteLength != 4:
    return ProofViewResult[StateTime](status: ProofViewError.InvalidValue)
  let decoded = decodeStateTime(found.value.bytes)
  if decoded.error != StateComponentError.None or decoded.value.consumed != 4:
    return ProofViewResult[StateTime](status: ProofViewError.InvalidValue)
  ProofViewResult[StateTime](status: ProofViewError.None, completed: decoded.value.value)
