# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded local light-update frames bind canonical edits to one independently trusted root and exact predecessor.
import std/[algorithm, assertions]
import ./[light_snapshot, light_state_cache, state_proof, database_identity]
import ../codec/[bounded, state_layout, state_trie]
import ../crypto/primitives
const
  Magic = "RAGNAROK-LIGHT-DELTA-V1\n"
  LightDeltaHeaderBytes* = Magic.len+152 ## Fixed metadata precedes every variable-width edit.
  LightDeltaOverhead* = LightDeltaHeaderBytes+32 ## A complete frame includes its corruption checksum.
  EditBytes = 42
type
  LightDeltaSequence* = distinct uint64 ## Zero is a checkpoint baseline; encoded updates require a positive exact sequence.
  LightDeltaLimits* = object ## Bound mutation descriptors and one encoded frame independently of the retained image.
    items*: ElementLimit
    bytes*: ByteLimit
  LightDeltaError* {.pure.} = enum ## Incomplete input grants no transition or repair authority by itself.
    Uninitialized, None, IncompleteFrame, InvalidFormat, LimitExceeded, LengthOverflow,
    WrongChain, WrongRoot, WrongBase, WrongSequence, ChecksumMismatch, InvalidTransition,
    ProofFailure, BackendFailure
  DeltaData = ref object ## Immutable publication retains only the successor, not a chain of predecessor images.
    image: PreparedLightSnapshot
    base: StorageChecksum
    sequence: LightDeltaSequence
    encoded: seq[byte]
    checksum: StorageChecksum
  PreparedLightDelta* = object ## Copies retain one authenticated transition and its exact immutable encoded bytes.
    owner: nil DeltaData
  LightDeltaResult*[T] = object ## Failed/default alternatives expose only reasons; no partial transition escapes.
    case status: LightDeltaError
    of None: completed: T
    of ProofFailure: proofReason: LightCacheError
    else: discard
  EditIndex = object ## Sorting fixed identities never copies borrowed proof payloads.
    key: StateKey
    index: int
    admit: bool
func error*[T](outcome: LightDeltaResult[T]): LightDeltaError =
  ## Inspect the selected typed reason without granting completed-data authority.
  outcome.status
func value*[T](outcome: LightDeltaResult[T]): T {.inline,
    requires: outcome.status == LightDeltaError.None.} =
  ## Only success authorizes an encoded frame, extent or authenticated successor.
  outcome.completed
func proofError*[T](outcome: LightDeltaResult[T]): LightCacheError {.requires:
    outcome.status == LightDeltaError.ProofFailure.} =
  ## Preserve only a selected proof/admission failure.
  outcome.proofReason
func failed[T](reason: LightDeltaError): LightDeltaResult[T] =
  ## Private typed refusal never initializes an inactive payload.
  LightDeltaResult[T](status: reason)
func proofFailed[T](reason: LightCacheError): LightDeltaResult[T] =
  ## Preserve the selected cache cause without retaining its failed scratch.
  LightDeltaResult[T](status: LightDeltaError.ProofFailure, proofReason: reason)
func initialized*(delta: PreparedLightDelta): bool =
  ## Default handles safely report that they carry no transition authority.
  delta.owner != nil
proc snapshot*(delta: PreparedLightDelta): PreparedLightSnapshot {.requires: delta.owner != nil.} =
  ## Retain the exact privately verified successor independently of frame lifetime.
  let owner = delta.owner
  assert owner != nil
  owner.image
proc sequence*(delta: PreparedLightDelta): LightDeltaSequence {.requires: delta.owner != nil.} =
  ## Read the explicit frame sequence; it is not a consensus generation.
  let owner = delta.owner
  assert owner != nil
  owner.sequence
proc baseChecksum*(delta: PreparedLightDelta): StorageChecksum {.requires: delta.owner != nil.} =
  ## Bind publication to the complete predecessor evidence image, not just its trusted root.
  let owner = delta.owner
  assert owner != nil
  owner.base
proc checksum*(delta: PreparedLightDelta): StorageChecksum {.requires: delta.owner != nil.} =
  ## Return copied local corruption-detection metadata without granting root trust.
  let owner = delta.owner
  assert owner != nil
  owner.checksum
proc byteLength*(delta: PreparedLightDelta): int {.requires: delta.owner != nil.} =
  ## Inspect exact frame extent without copying output.
  let owner = delta.owner
  assert owner != nil
  owner.encoded.len
proc encoded(owner: nil DeltaData): lent seq[byte] {.requires: owner != nil.} =
  ## Keep nullable-owner borrow provenance through a checked parameter.
  assert owner != nil
  owner.encoded
proc encodedBytes*(delta: PreparedLightDelta): lent seq[byte] {.requires: delta.owner != nil.} =
  ## Borrow immutable bytes only while their owner remains alive during the synchronous operation.
  encoded(delta.owner)
proc copyBytes(input: openArray[byte]): seq[byte] =
  ## Copy only an already bounded stable input, retaining no caller-owned mutable storage.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index]
proc bytes*(delta: PreparedLightDelta): seq[byte] {.requires: delta.owner != nil.} =
  ## Return independently mutable transport bytes; editing them cannot change successor authority.
  copyBytes(delta.encodedBytes)
func number(input: openArray[byte], offset: int, width = 8): uint64 =
  ## Callers establish each complete fixed-width little-endian field before reading.
  result = 0
  for index in 0..<width: result = result or (uint64(input[offset+index]) shl (8*index))
proc put(output: var seq[byte], offset: int, value: uint64, width = 8) =
  ## Exact encoded extent proves every fixed field write.
  for index in 0..<width: output[offset+index] = byte((value shr (8*index)) and 255)
func readKey(input: openArray[byte], offset: int): StateKey =
  ## Complete edit-header preflight proves these fixed query bytes.
  var raw = default(array[31, byte])
  for index in 0..<31: raw[index] = input[offset+index]
  StateKey(raw)
func compareKey(a, b: StateKey): int =
  ## Canonical ordering compares every serialized query octet.
  let left = array[31, byte](a)
  let right = array[31, byte](b)
  for index in 0..<31:
    if left[index] < right[index]: return -1
    if left[index] > right[index]: return 1
  0
proc compareEdit(a, b: EditIndex): int =
  ## Sort fixed identities while borrowed proof buffers remain stable.
  compareKey(a.key, b.key)
proc grow(total: var uint64, amount, maximum: uint64): bool =
  ## Prove native addressing and policy before addition or later narrowing.
  if total > maximum or amount > maximum-total: return false
  total += amount
  true
func prefix(input: openArray[byte], offset: int, expected: openArray[byte]): bool =
  ## Even partial known metadata must match before incomplete input can be classified as an unfinished frame.
  for index in 0..<expected.len:
    if offset+index >= input.len: return true
    if input[offset+index] != expected[index]: return false
  true
proc lightDeltaExtent*(input: openArray[byte], limits: LightDeltaLimits): LightDeltaResult[int] =
  ## Identify one complete bounded frame, never accepting trailing bytes as part of its checksum.
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  if maximum < uint64(LightDeltaOverhead): return failed[int](LightDeltaError.LimitExceeded)
  for index in 0..<min(input.len, Magic.len):
    if input[index] != byte(Magic[index]): return failed[int](LightDeltaError.InvalidFormat)
  if input.len < LightDeltaHeaderBytes: return failed[int](LightDeltaError.IncompleteFrame)
  let body = number(input, Magic.len+144)
  let count = number(input, Magic.len+136)
  if body > maximum-uint64(LightDeltaOverhead) or count > uint64(limits.items):
    return failed[int](LightDeltaError.LimitExceeded)
  if count > body div uint64(EditBytes): return failed[int](LightDeltaError.InvalidFormat)
  let extent = body+uint64(LightDeltaOverhead)
  if extent > uint64(input.len): return failed[int](LightDeltaError.IncompleteFrame)
  LightDeltaResult[int](status: LightDeltaError.None, completed: int(extent))
proc snapshotFailure[T](outcome: LightSnapshotResult[PreparedLightSnapshot]): LightDeltaResult[T] =
  ## Translate only the already selected atomic admission refusal, retaining no candidate image.
  case outcome.error
  of LightSnapshotError.ProofFailure: proofFailed[T](outcome.proofError)
  of LightSnapshotError.BackendFailure: failed[T](LightDeltaError.BackendFailure)
  of LightSnapshotError.LimitExceeded: failed[T](LightDeltaError.LimitExceeded)
  of LightSnapshotError.LengthOverflow: failed[T](LightDeltaError.LengthOverflow)
  else: failed[T](LightDeltaError.InvalidTransition)
proc prepareLightDelta*(before: PreparedLightSnapshot, sequence: LightDeltaSequence,
    proofs: openArray[LightStateProof], forgotten: openArray[StateKey],
    limits: LightDeltaLimits): LightDeltaResult[PreparedLightDelta] =
  ## Preflight canonical frame size, authenticate one complete atomic edit, then encode its predecessor/successor binding.
  if not before.initialized: return failed[PreparedLightDelta](LightDeltaError.Uninitialized)
  if uint64(sequence) == 0: return failed[PreparedLightDelta](LightDeltaError.WrongSequence)
  let allowance = min(uint64(limits.items), uint64(before.limits.cache.writes))
  let p = uint64(proofs.len)
  let f = uint64(forgotten.len)
  if p > allowance or f > allowance-p: return failed[PreparedLightDelta](
      LightDeltaError.LimitExceeded)
  let native = uint64(high(int) div sizeof(EditIndex))
  if p > native or f > native-p: return failed[PreparedLightDelta](LightDeltaError.LengthOverflow)
  let count = proofs.len+forgotten.len
  let maximum = min(uint64(limits.bytes), uint64(high(int)))
  var size = uint64(LightDeltaOverhead)
  if not grow(size, uint64(count)*uint64(EditBytes), maximum):
    return failed[PreparedLightDelta](LightDeltaError.LimitExceeded)
  for proof in proofs:
    # Shape and exact transport bounds precede sorting, allocation and proof/backend work.
    let nodes = uint64(proof.proof.nodes.len)
    let raw = uint64(proof.proof.value.len)
    if nodes > 249 or nodes > uint64(before.limits.cache.proof.nodes) or raw > uint64(
        before.limits.cache.proof.valueBytes):
      return failed[PreparedLightDelta](LightDeltaError.LimitExceeded)
    if not grow(size, nodes*64+raw, maximum): return failed[PreparedLightDelta](
        LightDeltaError.LimitExceeded)
  var ordered = newSeq[EditIndex](count)
  for index, proof in proofs: ordered[index] = EditIndex(key: proof.key, index: index, admit: true)
  for index, key in forgotten: ordered[proofs.len+index] = EditIndex(key: key, index: index)
  ordered.sort(compareEdit)
  for index in 1..<ordered.len:
    if compareKey(ordered[index-1].key, ordered[index].key) == 0:
      return proofFailed[PreparedLightDelta](LightCacheError.DuplicateKey)
  let changed = before.update(proofs, forgotten)
  if changed.error != LightSnapshotError.None: return snapshotFailure[PreparedLightDelta](changed)
  var output = newSeq[byte](int(size))
  for index in 0..<Magic.len: output[index] = byte(Magic[index])
  let chain = array[32, byte](before.chainId)
  let root = array[32, byte](before.root)
  let base = array[32, byte](before.checksum)
  let after = array[32, byte](changed.value.checksum)
  for index in 0..<32:
    output[Magic.len+index] = chain[index]
    output[Magic.len+32+index] = root[index]
    output[Magic.len+64+index] = base[index]
    output[Magic.len+96+index] = after[index]
  put(output, Magic.len+128, uint64(sequence))
  put(output, Magic.len+136, uint64(count))
  put(output, Magic.len+144, size-uint64(LightDeltaOverhead))
  var cursor = LightDeltaHeaderBytes
  for edit in ordered:
    # Complete exact sizing proves every canonical fixed header and selected proof payload write.
    let key = array[31, byte](edit.key)
    for index in 0..<31: output[cursor+index] = key[index]
    if edit.admit:
      output[cursor+31] = 1
      let proof = proofs[edit.index].proof
      put(output, cursor+32, uint64(proof.nodes.len), 2)
      put(output, cursor+34, uint64(proof.value.len))
      cursor += EditBytes
      for node in proof.nodes:
        let raw = array[64, byte](node)
        for index in 0..<64: output[cursor+index] = raw[index]
        cursor += 64
      for index in 0..<proof.value.len: output[cursor+index] = proof.value[index]
      cursor += proof.value.len
    else: cursor += EditBytes # Zero-initialized reserved forget fields have one canonical representation.
  assert cursor == output.len-32
  let hashed = blake2b256(output.toOpenArray(0, cursor-1))
  if hashed.error != CryptoError.None: return failed[PreparedLightDelta](
      LightDeltaError.BackendFailure)
  let checksum = StorageChecksum(array[32, byte](hashed.value))
  for index in 0..<32: output[cursor+index] = array[32, byte](checksum)[index]
  LightDeltaResult[PreparedLightDelta](status: LightDeltaError.None,
    completed: PreparedLightDelta(owner: DeltaData(image: changed.value, base: before.checksum,
      sequence: sequence, encoded: output, checksum: checksum)))
proc verified(input: openArray[byte], before: PreparedLightSnapshot, expected: LightDeltaSequence,
    limits: LightDeltaLimits): LightDeltaResult[DeltaData] =
  ## Strict shape/checksum/proof verification creates only private candidate metadata; output ownership follows success.
  if not before.initialized: return failed[DeltaData](LightDeltaError.Uninitialized)
  if uint64(expected) == 0: return failed[DeltaData](LightDeltaError.WrongSequence)
  if uint64(input.len) > uint64(limits.bytes): return failed[DeltaData](
      LightDeltaError.LimitExceeded)
  if not prefix(input, Magic.len, array[32, byte](before.chainId)): return failed[DeltaData](
      LightDeltaError.WrongChain)
  if not prefix(input, Magic.len+32, array[32, byte](before.root)): return failed[DeltaData](
      LightDeltaError.WrongRoot)
  if not prefix(input, Magic.len+64, array[32, byte](before.checksum)): return failed[DeltaData](
      LightDeltaError.WrongBase)
  var seqBytes = default(array[8, byte])
  for index in 0..<8: seqBytes[index] = byte((uint64(expected) shr (index*8)) and 255)
  if not prefix(input, Magic.len+128, seqBytes): return failed[DeltaData](
      LightDeltaError.WrongSequence)
  let extent = lightDeltaExtent(input, limits)
  if extent.error != LightDeltaError.None: return failed[DeltaData](extent.error)
  if extent.value != input.len: return failed[DeltaData](LightDeltaError.InvalidFormat)
  let count = number(input, Magic.len+136)
  if count > uint64(before.limits.cache.writes): return failed[DeltaData](
      LightDeltaError.LimitExceeded)
  if count > uint64(high(int) div sizeof(LightStateProof)) or count > uint64(high(int) div sizeof(StateKey)):
    return failed[DeltaData](LightDeltaError.LengthOverflow)
  let stop = input.len-32
  var cursor = LightDeltaHeaderBytes
  var previous = default(StateKey)
  var admitted = 0
  var removed = 0
  for index in 0..<int(count):
    # Validate every header, canonical key, reserved field and payload extent before hashing or input-derived allocation.
    if stop-cursor < EditBytes: return failed[DeltaData](LightDeltaError.InvalidFormat)
    let key = readKey(input, cursor)
    if index > 0 and compareKey(previous, key) >= 0: return failed[DeltaData](
        LightDeltaError.InvalidFormat)
    previous = key
    let tag = input[cursor+31]
    let nodes = number(input, cursor+32, 2)
    let size = number(input, cursor+34)
    cursor += EditBytes
    if tag > 1 or (tag == 0 and (nodes != 0 or size != 0)): return failed[DeltaData](
        LightDeltaError.InvalidFormat)
    if nodes > 249 or nodes > uint64(before.limits.cache.proof.nodes) or size > uint64(
        before.limits.cache.proof.valueBytes):
      return failed[DeltaData](LightDeltaError.LimitExceeded)
    if nodes > uint64((stop-cursor) div 64): return failed[DeltaData](LightDeltaError.InvalidFormat)
    let nodeBytes = int(nodes)*64
    if size > uint64(stop-cursor-nodeBytes): return failed[DeltaData](LightDeltaError.InvalidFormat)
    cursor += nodeBytes+int(size)
    if tag == 1: inc admitted
    else: inc removed
  if cursor != stop: return failed[DeltaData](LightDeltaError.InvalidFormat)
  let hashed = blake2b256(input.toOpenArray(0, stop-1))
  if hashed.error != CryptoError.None: return failed[DeltaData](LightDeltaError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  for index in 0..<32:
    if input[stop+index] != checksum[index]: return failed[DeltaData](
        LightDeltaError.ChecksumMismatch)
  var proofs = newSeq[LightStateProof](admitted)
  var forgotten = newSeq[StateKey](removed)
  var fresh = 0
  var old = 0
  cursor = LightDeltaHeaderBytes
  for index in 0..<int(count):
    # Only bounded shape-validated checksum-authenticated transport is materialized for atomic proof admission.
    let key = readKey(input, cursor)
    let tag = input[cursor+31]
    let count = int(number(input, cursor+32, 2))
    let size = int(number(input, cursor+34))
    cursor += EditBytes
    if tag == 0:
      forgotten[old] = key
      inc old
    else:
      var nodes = newSeq[EncodedStateNode](count)
      for slot in 0..<count:
        var raw = default(array[64, byte])
        for offset in 0..<64: raw[offset] = input[cursor+offset]
        nodes[slot] = EncodedStateNode(raw)
        cursor += 64
      var value = newSeq[byte](size)
      for offset in 0..<size: value[offset] = input[cursor+offset]
      cursor += size
      proofs[fresh] = LightStateProof(key: key, proof: StateProof(nodes: nodes, value: value))
      inc fresh
  assert cursor == stop and fresh == admitted and old == removed
  let changed = before.update(proofs, forgotten)
  if changed.error != LightSnapshotError.None: return snapshotFailure[DeltaData](changed)
  let after = array[32, byte](changed.value.checksum)
  for index in 0..<32:
    if input[Magic.len+96+index] != after[index]: return failed[DeltaData](
        LightDeltaError.InvalidTransition)
  LightDeltaResult[DeltaData](status: LightDeltaError.None,
    completed: DeltaData(image: changed.value, base: before.checksum, sequence: expected,
      checksum: StorageChecksum(checksum)))
proc decodeLightDelta*(input: openArray[byte], before: PreparedLightSnapshot,
    expected: LightDeltaSequence, limits: LightDeltaLimits): LightDeltaResult[PreparedLightDelta] =
  ## Copy stable transport only after every frame, predecessor and proof check has completed.
  let checked = verified(input, before, expected, limits)
  if checked.error == LightDeltaError.ProofFailure: return proofFailed[PreparedLightDelta](
      checked.proofError)
  if checked.error != LightDeltaError.None: return failed[PreparedLightDelta](checked.error)
  let data = checked.value
  data.encoded = copyBytes(input)
  LightDeltaResult[PreparedLightDelta](status: LightDeltaError.None, completed: PreparedLightDelta(owner: data))
proc takeLightDelta*(input: var seq[byte], before: PreparedLightSnapshot,
    expected: LightDeltaSequence, limits: LightDeltaLimits): LightDeltaResult[PreparedLightDelta] =
  ## Consume one owned transport buffer only on success; all refusals preserve the caller's original bytes.
  let checked = verified(input, before, expected, limits)
  if checked.error == LightDeltaError.ProofFailure: return proofFailed[PreparedLightDelta](
      checked.proofError)
  if checked.error != LightDeltaError.None: return failed[PreparedLightDelta](checked.error)
  let data = checked.value
  data.encoded = move(input)
  LightDeltaResult[PreparedLightDelta](status: LightDeltaError.None, completed: PreparedLightDelta(owner: data))
