# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical light proof-cache images bind explicit chain/root expectations and reverify every stored proof.
## Opaque prepared images retain immutable bytes/cache; file checksums never establish root trust.
import std/[algorithm, assertions]
import ./[light_state_cache, state_proof, database_identity]
import ../codec/[bounded, state_layout, state_trie]
import ../crypto/primitives
const
  Magic = "RAGNAROK-LIGHT-CACHE-V1\n"
  HeaderBytes = Magic.len+72
  EntryBytes = 41
  Overhead = HeaderBytes+32
type
  LightSnapshotLimits* = object ## Bound complete encoded images and restored cache contents independently of ordinary batches.
    cache*: LightCacheLimits
    bytes*: ByteLimit
  LightSnapshotError* {.pure.} = enum ## Default/refused images expose no bytes, cache or partial proof prefix.
    Uninitialized, None, InvalidFormat, WrongChain, WrongRoot, LimitExceeded,
    LengthOverflow, ChecksumMismatch, ProofFailure, BackendFailure
  SnapshotData = ref object ## Private immutable preparation owns canonical bytes and fully admitted cache state.
    chain: StorageChainId
    root: StateRoot
    limits: LightSnapshotLimits
    encoded: seq[byte]
    cache: LightStateCache
    checksum: StorageChecksum
  PreparedLightSnapshot* = object ## Copies retain one immutable validated local image, never a root-trust decision.
    owner: nil SnapshotData
  LightSnapshotResult*[T] = object ## Selected proof failures carry a reason, never a completed prefix.
    case status: LightSnapshotError
    of None: completed: T
    of ProofFailure: proofReason: LightCacheError
    else: discard
  KeyIndex = object ## Fixed key/source positions sort untrusted transport without copying proof buffers.
    key: StateKey
    index: int
func error*[T](outcome: LightSnapshotResult[T]): LightSnapshotError =
  ## Inspect only a completed operation's reason.
  outcome.status
func value*[T](outcome: LightSnapshotResult[T]): T {.inline,
    requires: outcome.status == LightSnapshotError.None.} =
  ## Defaults and failures cannot authorize snapshot/cache extraction.
  outcome.completed
func proofError*[T](outcome: LightSnapshotResult[T]): LightCacheError {.requires:
    outcome.status == LightSnapshotError.ProofFailure.} =
  ## Preserve the exact selected proof-admission failure without exposing its private scratch.
  outcome.proofReason
func initialized*(snapshot: PreparedLightSnapshot): bool =
  ## Safely distinguish a default handle before selecting any guarded metadata or bytes.
  snapshot.owner != nil
proc chainId*(snapshot: PreparedLightSnapshot): StorageChainId {.requires: snapshot.owner != nil.} =
  ## Return the explicit chain binding, not an independently authenticated identity.
  let owner = snapshot.owner
  assert owner != nil
  owner.chain
proc root*(snapshot: PreparedLightSnapshot): StateRoot {.requires: snapshot.owner != nil.} =
  ## Return the caller-supplied complete-root binding, never a root calculated from partial cache state.
  let owner = snapshot.owner
  assert owner != nil
  owner.root
proc limits*(snapshot: PreparedLightSnapshot): LightSnapshotLimits {.requires: snapshot.owner != nil.} =
  ## Copy the exact policy under which all private bytes and cached lookups were validated.
  let owner = snapshot.owner
  assert owner != nil
  owner.limits
proc cache*(snapshot: PreparedLightSnapshot): LightStateCache {.requires: snapshot.owner != nil.} =
  ## Retain immutable admitted lookup state independently of the encoded image's lifetime.
  let owner = snapshot.owner
  assert owner != nil
  owner.cache
proc checksum*(snapshot: PreparedLightSnapshot): StorageChecksum {.requires: snapshot.owner != nil.} =
  ## Read copied corruption-detection metadata without granting root provenance.
  let owner = snapshot.owner
  assert owner != nil
  owner.checksum
proc byteLength*(snapshot: PreparedLightSnapshot): int {.requires: snapshot.owner != nil.} =
  ## Inspect the complete canonical image extent without copying bytes.
  let owner = snapshot.owner
  assert owner != nil
  owner.encoded.len
proc encodedView(owner: nil SnapshotData): lent seq[byte] {.requires: owner != nil.} =
  ## A checked parameter borrow retains its provenance through the prepared handle's nullable owner field.
  assert owner != nil
  owner.encoded
proc encodedBytes*(snapshot: PreparedLightSnapshot): lent seq[byte] {.requires: snapshot.owner != nil.} =
  ## Borrow immutable canonical bytes for an immediate operation; the snapshot owner must outlive the view.
  encodedView(snapshot.owner)
proc bytes*(snapshot: PreparedLightSnapshot): seq[byte] {.requires: snapshot.owner != nil.} =
  ## Copy canonical output; no mutable backing storage can change a prepared image's authority.
  let owner = snapshot.owner
  assert owner != nil
  result = newSeq[byte](owner.encoded.len)
  for index, octet in owner.encoded: result[index] = octet
func compareKey(left, right: StateKey): int =
  ## Canonical ordering uses every serialized query-key octet.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for index in 0..<31:
    if a[index] < b[index]: return -1
    if a[index] > b[index]: return 1
  0
proc compareIndex(left, right: KeyIndex): int =
  ## Sort identities only; borrowed node/value buffers stay untouched.
  compareKey(left.key, right.key)
func number(input: openArray[byte], offset: int, width = 8): uint64 =
  ## Callers prove the exact two/eight-byte field before any access or shift.
  result = 0
  for index in 0..<width: result = result or (uint64(input[offset+index]) shl (index*8))
proc putNumber(output: var seq[byte], offset: int, value: uint64, width = 8) =
  ## Complete output preflight proves every fixed little-endian field.
  for index in 0..<width: output[offset+index] = byte((value shr (index*8)) and 255)
func readKey(input: openArray[byte], offset: int): StateKey =
  ## Shape preflight proves a complete fixed query identity.
  var raw = default(array[31, byte])
  for index in 0..<31: raw[index] = input[offset+index]
  StateKey(raw)
proc grow(size: var uint64, amount, maximum: uint64): bool =
  ## Prove both file policy and host addressing before addition or later narrowing.
  if size > maximum or amount > maximum-size: return false
  size += amount
  true
proc prepareLightSnapshot*(chain: StorageChainId, root: StateRoot,
    proofs: openArray[LightStateProof], limits: LightSnapshotLimits): LightSnapshotResult[
        PreparedLightSnapshot] =
  ## Preflight exact extents, admit every proof, then encode one canonical checksummed image.
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  if uint64(proofs.len) > uint64(limits.cache.items):
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.LimitExceeded)
  if proofs.len > high(int) div sizeof(KeyIndex) or proofs.len > high(int) div sizeof(LightStateProof):
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.LengthOverflow)
  var size = uint64(Overhead)
  if size > maximum: return LightSnapshotResult[PreparedLightSnapshot](
      status: LightSnapshotError.LimitExceeded)
  var values = 0'u64
  for proof in proofs:
    let count = uint64(proof.proof.nodes.len)
    let raw = uint64(proof.proof.value.len)
    if count > 249 or count > uint64(limits.cache.proof.nodes) or raw > uint64(
        limits.cache.proof.valueBytes):
      return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.LimitExceeded)
    if not grow(values, raw, uint64(limits.cache.valueBytes)) or
        not grow(size, uint64(EntryBytes)+count*64, maximum) or not grow(size, raw, maximum):
      return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.LimitExceeded)
  var ordered = newSeq[KeyIndex](proofs.len)
  for index, proof in proofs: ordered[index] = KeyIndex(key: proof.key, index: index)
  ordered.sort(compareIndex)
  let admitted = newLightStateCache(root, proofs, limits.cache)
  if admitted.error == LightCacheError.BackendFailure:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.BackendFailure)
  if admitted.error != LightCacheError.None:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.ProofFailure,
        proofReason: admitted.error)
  var output = newSeq[byte](int(size))
  for index, character in Magic: output[index] = byte(character)
  let chainBytes = array[32, byte](chain)
  let rootBytes = array[32, byte](root)
  for index in 0..<32:
    output[Magic.len+index] = chainBytes[index]
    output[Magic.len+32+index] = rootBytes[index]
  putNumber(output, Magic.len+64, uint64(proofs.len))
  var cursor = HeaderBytes
  for index in ordered:
    let proof = proofs[index.index]
    let key = array[31, byte](proof.key)
    for offset in 0..<31: output[cursor+offset] = key[offset]
    putNumber(output, cursor+31, uint64(proof.proof.nodes.len), 2)
    putNumber(output, cursor+33, uint64(proof.proof.value.len))
    cursor += EntryBytes
    for node in proof.proof.nodes:
      let raw = array[64, byte](node)
      for offset in 0..<64: output[cursor+offset] = raw[offset]
      cursor += 64
    for octet in proof.proof.value:
      output[cursor] = octet
      inc cursor
  assert cursor == output.len-32 # Exact preflight fills the canonical body and leaves only its checksum.
  let hashed = blake2b256(output.toOpenArray(0, cursor-1))
  if hashed.error != CryptoError.None:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for index in 0..<32: output[cursor+index] = checksum[index]
  LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.None,
    completed: PreparedLightSnapshot(owner: SnapshotData(chain: chain, root: root, limits: limits,
      encoded: output, cache: admitted.value, checksum: StorageChecksum(checksum))))
proc decodeLightSnapshot*(input: openArray[byte], expectedChain: StorageChainId,
    expectedRoot: StateRoot, limits: LightSnapshotLimits): LightSnapshotResult[LightStateCache] =
  ## File metadata/checksum cannot establish trust: every bounded proof is checked against the independent expected root.
  if uint64(input.len) > uint64(limits.bytes):
    return LightSnapshotResult[LightStateCache](status: LightSnapshotError.LimitExceeded)
  if input.len < Overhead: return LightSnapshotResult[LightStateCache](
      status: LightSnapshotError.InvalidFormat)
  for index, character in Magic:
    if input[index] != byte(character): return LightSnapshotResult[LightStateCache](
        status: LightSnapshotError.InvalidFormat)
  let chain = array[32, byte](expectedChain)
  let root = array[32, byte](expectedRoot)
  for index in 0..<32:
    if input[Magic.len+index] != chain[index]: return LightSnapshotResult[LightStateCache](
        status: LightSnapshotError.WrongChain)
  for index in 0..<32:
    if input[Magic.len+32+index] != root[index]: return LightSnapshotResult[LightStateCache](
        status: LightSnapshotError.WrongRoot)
  let count = number(input, Magic.len+64)
  if count > uint64(limits.cache.items): return LightSnapshotResult[LightStateCache](
      status: LightSnapshotError.LimitExceeded)
  if count > uint64(high(int) div sizeof(LightStateProof)):
    return LightSnapshotResult[LightStateCache](status: LightSnapshotError.LengthOverflow)
  let stop = input.len-32
  if count > uint64((stop-HeaderBytes) div EntryBytes):
    return LightSnapshotResult[LightStateCache](status: LightSnapshotError.InvalidFormat) # Bound loop work by actual fixed entry bytes.
  var cursor = HeaderBytes
  var previous = default(StateKey)
  var total = 0'u64
  # Complete shape validation precedes hashing and all input-derived proof allocations.
  for index in 0..<int(count):
    if stop-cursor < EntryBytes: return LightSnapshotResult[LightStateCache](
        status: LightSnapshotError.InvalidFormat)
    let key = readKey(input, cursor)
    if index > 0 and compareKey(previous, key) >= 0:
      return LightSnapshotResult[LightStateCache](
          status: LightSnapshotError.InvalidFormat) # Unsorted or repeated queries have no alternate representation.
    previous = key
    let nodes = number(input, cursor+31, 2)
    let size = number(input, cursor+33)
    cursor += EntryBytes
    if nodes > 249 or nodes > uint64(limits.cache.proof.nodes) or size > uint64(
        limits.cache.proof.valueBytes):
      return LightSnapshotResult[LightStateCache](status: LightSnapshotError.LimitExceeded)
    if not grow(total, size, uint64(limits.cache.valueBytes)):
      return LightSnapshotResult[LightStateCache](status: LightSnapshotError.LimitExceeded)
    let nodeBytes = nodes*64 # The hard path bound proves this multiplication and its native narrowing.
    if nodeBytes > uint64(stop-cursor): return LightSnapshotResult[LightStateCache](
        status: LightSnapshotError.InvalidFormat)
    cursor += int(nodeBytes)
    if size > uint64(stop-cursor): return LightSnapshotResult[LightStateCache](
        status: LightSnapshotError.InvalidFormat)
    cursor += int(size)
  if cursor != stop: return LightSnapshotResult[LightStateCache](
      status: LightSnapshotError.InvalidFormat)
  let hashed = blake2b256(input.toOpenArray(0, stop-1))
  if hashed.error != CryptoError.None: return LightSnapshotResult[LightStateCache](
      status: LightSnapshotError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for index in 0..<32:
    if input[stop+index] != checksum[index]: return LightSnapshotResult[LightStateCache](
        status: LightSnapshotError.ChecksumMismatch)
  cursor = HeaderBytes
  proc readProof(index: int): LightStateProof {.closure.} =
    ## The synchronous constructor calls each index once; complete shape preflight proves every cursor and allocation extent.
    assert index >= 0 and index < int(count)
    let key = readKey(input, cursor)
    let count = int(number(input, cursor+31, 2))
    let size = int(number(input, cursor+33))
    cursor += EntryBytes
    var nodes = newSeq[EncodedStateNode](count)
    for slot in 0..<count:
      # Copy only the selected bounded path, then retire it before the next proof-reader call.
      var raw = default(array[64, byte])
      for offset in 0..<64: raw[offset] = input[cursor+offset]
      nodes[slot] = EncodedStateNode(raw)
      cursor += 64
    var value = newSeq[byte](size)
    for offset in 0..<size: value[offset] = input[cursor+offset]
    cursor += size
    LightStateProof(key: key, proof: StateProof(nodes: nodes, value: value))
  let admitted = restoreLightStateCache(expectedRoot, int(count), readProof, limits.cache)
  if admitted.error == LightCacheError.BackendFailure:
    return LightSnapshotResult[LightStateCache](status: LightSnapshotError.BackendFailure)
  if admitted.error != LightCacheError.None:
    return LightSnapshotResult[LightStateCache](status: LightSnapshotError.ProofFailure,
        proofReason: admitted.error)
  assert cursor == stop # Only complete successful stream consumption authorizes the cache result.
  LightSnapshotResult[LightStateCache](status: LightSnapshotError.None, completed: admitted.value)

proc ownedSnapshot(encoded: sink seq[byte], chain: StorageChainId, root: StateRoot,
    limits: LightSnapshotLimits, cache: LightStateCache): PreparedLightSnapshot =
  ## Only fully validated bytes may enter this private immutable owner; the last 32 bytes carry their checked checksum.
  assert encoded.len >= Overhead
  var checksum = default(array[32, byte])
  for index in 0..<32: checksum[index] = encoded[encoded.len-32+index]
  PreparedLightSnapshot(owner: SnapshotData(chain: chain, root: root, limits: limits,
    encoded: encoded, cache: cache, checksum: StorageChecksum(checksum)))
proc restoreLightSnapshot*(input: openArray[byte], expectedChain: StorageChainId,
    expectedRoot: StateRoot, limits: LightSnapshotLimits): LightSnapshotResult[
        PreparedLightSnapshot] =
  ## Validate untrusted bytes fully before retaining canonical proof evidence for later bounded edits.
  let decoded = decodeLightSnapshot(input, expectedChain, expectedRoot, limits)
  if decoded.error == LightSnapshotError.ProofFailure:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.ProofFailure,
        proofReason: decoded.proofError)
  if decoded.error != LightSnapshotError.None:
    return LightSnapshotResult[PreparedLightSnapshot](status: decoded.error)
  var encoded = newSeq[byte](input.len)
  for index, octet in input: encoded[index] = octet
  LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.None,
    completed: ownedSnapshot(encoded, expectedChain, expectedRoot, limits, decoded.value))
proc takeLightSnapshot*(input: var seq[byte], expectedChain: StorageChainId,
    expectedRoot: StateRoot, limits: LightSnapshotLimits): LightSnapshotResult[
        PreparedLightSnapshot] =
  ## Consume an owned image only after full validation; every refusal preserves the original input unchanged.
  let decoded = decodeLightSnapshot(input, expectedChain, expectedRoot, limits)
  if decoded.error == LightSnapshotError.ProofFailure:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.ProofFailure,
      proofReason: decoded.proofError)
  if decoded.error != LightSnapshotError.None:
    return LightSnapshotResult[PreparedLightSnapshot](status: decoded.error)
  LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.None,
    completed: ownedSnapshot(move(input), expectedChain, expectedRoot, limits, decoded.value))

type
  EditKind {.pure.} = enum ## Distinguish incoming proof evidence from explicit local-evidence removal.
    Admit, Forget
  EditIndex = object ## Sorted disjoint operation identities keep payloads borrowed and make each transition explicit.
    key: StateKey
    index: int
    kind: EditKind
  EntrySource = object ## A merge cursor borrows either a trusted encoded entry or an incoming transport index.
    offset, index: int
    extent, valueBytes: uint64
proc compareEdit(left, right: EditIndex): int =
  ## One canonical order detects conflicts across both operation lists before any proof hashing.
  compareKey(left.key, right.key)
proc nextSource(encoded: openArray[byte], ordered: openArray[EditIndex],
    old: var int, fresh: var int, source: var EntrySource): bool =
  ## Scan canonical evidence and unique sorted edits, skipping only explicitly forgotten query identities.
  let stop = encoded.len-32
  while old < stop or fresh < ordered.len:
    # Existing private image validity proves each old entry, while incoming descriptors were bounded before sorting.
    let comparison = if old == stop: 1 elif fresh == ordered.len: -1
      else: compareKey(readKey(encoded, old), ordered[fresh].key)
    if comparison > 0:
      let change = ordered[fresh]
      source = EntrySource(offset: -1, index: change.index)
      inc fresh
      if change.kind == EditKind.Admit: return true # Forgetting an unknown query consumes only its operation.
    else:
      assert stop-old >= EntryBytes
      let nodes = number(encoded, old+31, 2)
      let size = number(encoded, old+33)
      assert nodes <= 249 and nodes*64 <= uint64(stop-old-EntryBytes)
      let fixed = uint64(EntryBytes)+nodes*64
      assert size <= uint64(stop-old)-fixed
      let extent = fixed+size
      source = EntrySource(offset: old, index: -1, extent: extent, valueBytes: size)
      old += int(extent) # Complete owned-image invariants prove this native cursor advance.
      if comparison < 0: return true
      let change = ordered[fresh]
      source = EntrySource(offset: -1, index: change.index)
      inc fresh
      if change.kind == EditKind.Admit: return true # Equal-key admission replaces evidence; forgetting emits nothing.
  false
proc edit(snapshot: PreparedLightSnapshot, updates: openArray[LightStateProof],
    keys: openArray[StateKey]): LightSnapshotResult[PreparedLightSnapshot] =
  ## Preflight the final canonical set before proof hashing or output allocation; old proof bytes need no revalidation.
  let owner = snapshot.owner
  if owner == nil: return LightSnapshotResult[PreparedLightSnapshot](
      status: LightSnapshotError.Uninitialized)
  let policy = owner.limits
  let proofs = uint64(updates.len)
  let forgotten = uint64(keys.len)
  let allowance = uint64(policy.cache.writes)
  if proofs > allowance or forgotten > allowance-proofs:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.LimitExceeded)
  let maximumEdits = uint64(high(int) div sizeof(EditIndex))
  if proofs > maximumEdits or forgotten > maximumEdits-proofs:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.LengthOverflow)
  let count = updates.len+keys.len # Both sum and descriptor multiplication were proved before native addition.
  if count == 0: return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.None,
      completed: snapshot)
  for update in updates:
    # Bound all incoming transport before sorting, final-set traversal or proof hashing.
    let nodes = uint64(update.proof.nodes.len)
    let raw = uint64(update.proof.value.len)
    if nodes > 249 or nodes > uint64(policy.cache.proof.nodes) or raw > uint64(
        policy.cache.proof.valueBytes):
      return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.LimitExceeded)
  var ordered = newSeq[EditIndex](count)
  for index, update in updates:
    ordered[index] = EditIndex(key: update.key, index: index, kind: EditKind.Admit)
  for index, key in keys:
    ordered[updates.len+index] = EditIndex(key: key, index: 0, kind: EditKind.Forget)
  ordered.sort(compareEdit)
  for index in 1..<count:
    if compareKey(ordered[index-1].key, ordered[index].key) == 0:
      return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.ProofFailure,
        proofReason: LightCacheError.DuplicateKey)
  var size = uint64(Overhead)
  var values = 0'u64
  var entries = 0'u64
  var old = HeaderBytes
  var fresh = 0
  var source = default(EntrySource)
  let maximum = min(uint64(policy.bytes), uint64(high(int)))
  # A complete merged-set first pass releases replacements before counting the selected final quotas.
  while nextSource(owner.encoded, ordered, old, fresh, source):
    var extent = source.extent
    var raw = source.valueBytes
    if source.offset < 0:
      let proof = updates[source.index].proof
      raw = uint64(proof.value.len)
      extent = uint64(EntryBytes)+uint64(proof.nodes.len)*64+raw # Hard node and native input bounds prove uint64 arithmetic.
    let valuesFit = grow(values, raw, uint64(policy.cache.valueBytes))
    let bytesFit = grow(size, extent, maximum)
    if entries >= uint64(policy.cache.items) or not valuesFit or not bytesFit:
      return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.LimitExceeded)
    inc entries # File byte bounds already bound the number of nonempty fixed descriptors.
  if updates.len == 0 and entries == uint64(owner.cache.len):
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.None,
        completed: snapshot)
  let reduced = owner.cache.forget(keys)
  if reduced.error != LightCacheError.None:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.ProofFailure,
        proofReason: reduced.error)
  let admitted = reduced.value.admit(updates)
  if admitted.error == LightCacheError.BackendFailure:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.BackendFailure)
  if admitted.error != LightCacheError.None:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.ProofFailure,
        proofReason: admitted.error)
  var output = newSeq[byte](int(size))
  for index in 0..<HeaderBytes: output[index] = owner.encoded[index]
  putNumber(output, Magic.len+64, entries)
  var cursor = HeaderBytes
  old = HeaderBytes
  fresh = 0
  # The same stable inputs fill exactly the preflighted image; retained canonical evidence is copied as a byte span.
  while nextSource(owner.encoded, ordered, old, fresh, source):
    if source.offset >= 0:
      for index in 0..<int(source.extent): output[cursor+index] = owner.encoded[source.offset+index]
      cursor += int(source.extent)
    else:
      let update = updates[source.index]
      let key = array[31, byte](update.key)
      for index in 0..<31: output[cursor+index] = key[index]
      putNumber(output, cursor+31, uint64(update.proof.nodes.len), 2)
      putNumber(output, cursor+33, uint64(update.proof.value.len))
      cursor += EntryBytes
      for node in update.proof.nodes:
        let raw = array[64, byte](node)
        for index in 0..<64: output[cursor+index] = raw[index]
        cursor += 64
      for octet in update.proof.value:
        output[cursor] = octet
        inc cursor
  assert cursor == output.len-32
  let hashed = blake2b256(output.toOpenArray(0, cursor-1))
  if hashed.error != CryptoError.None:
    return LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for index in 0..<32: output[cursor+index] = checksum[index]
  LightSnapshotResult[PreparedLightSnapshot](status: LightSnapshotError.None,
    completed: PreparedLightSnapshot(owner: SnapshotData(chain: owner.chain, root: owner.root,
      limits: policy, encoded: output, cache: admitted.value, checksum: StorageChecksum(checksum))))
proc admit*(snapshot: PreparedLightSnapshot, updates: openArray[
    LightStateProof]): LightSnapshotResult[PreparedLightSnapshot] =
  ## Retain old evidence and authenticate only the incoming unique-key batch at the original complete root.
  edit(snapshot, updates, [])
proc forget*(snapshot: PreparedLightSnapshot, keys: openArray[StateKey]): LightSnapshotResult[
    PreparedLightSnapshot] =
  ## Forget local evidence without inventing authenticated absence or discarding the independently expected root.
  edit(snapshot, [], keys)
proc update*(snapshot: PreparedLightSnapshot, proofs: openArray[LightStateProof],
    forgottenKeys: openArray[StateKey]): LightSnapshotResult[PreparedLightSnapshot] =
  ## Validate one disjoint combined batch and prepare its final canonical image without exposing intermediate knowledge.
  edit(snapshot, proofs, forgottenKeys)
