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
  var proofs = newSeq[LightStateProof](int(count))
  cursor = HeaderBytes
  # The stable borrowed input and complete first pass prove each exact copy/allocation extent.
  for index in 0..<proofs.len:
    let key = readKey(input, cursor)
    let count = int(number(input, cursor+31, 2))
    let size = int(number(input, cursor+33))
    cursor += EntryBytes
    var nodes = newSeq[EncodedStateNode](count)
    for slot in 0..<count:
      var raw = default(array[64, byte])
      for offset in 0..<64: raw[offset] = input[cursor+offset]
      nodes[slot] = EncodedStateNode(raw)
      cursor += 64
    var value = newSeq[byte](size)
    for offset in 0..<size: value[offset] = input[cursor+offset]
    cursor += size
    proofs[index] = LightStateProof(key: key, proof: StateProof(nodes: nodes, value: value))
  assert cursor == stop
  let admitted = newLightStateCache(expectedRoot, proofs, limits.cache)
  if admitted.error == LightCacheError.BackendFailure:
    return LightSnapshotResult[LightStateCache](status: LightSnapshotError.BackendFailure)
  if admitted.error != LightCacheError.None:
    return LightSnapshotResult[LightStateCache](status: LightSnapshotError.ProofFailure,
        proofReason: admitted.error)
  LightSnapshotResult[LightStateCache](status: LightSnapshotError.None, completed: admitted.value)
