# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated light-delta framing preserves canonical edits, exact predecessors and atomic owned restoration.
# @@Verification={"arc":"storage_light_delta_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/light/[delta as light_delta, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../../src/storage/state_proof
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/database_identity
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/crypto/primitives
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Invalid framing, identity and source-policy refusals must not reach the provider.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Every frame/proof/successor checksum boundary can independently refuse.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Distinguish strict verification from merely accepting matching encoded bytes.
proc key(first: byte): StateKey =
  ## Fixture queries separate retained presence, authenticated absence and unknown evidence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc policy(): LightSnapshotLimits =
  ## Both initial and final knowledge fit exact independent mutation, image and proof ceilings.
  LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(items: ElementLimit(3),
    writes: ElementLimit(3), valueBytes: ByteLimit(66),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc limits(): LightDeltaLimits =
  ## One frame cannot widen the source cache's mutation or proof policy.
  LightDeltaLimits(items: ElementLimit(3), bytes: ByteLimit(4096))
proc put(input: var seq[byte], offset: int, value: uint64) =
  ## Tests author exact little-endian malformed fields without native overflow or unchecked offsets.
  for index in 0..<8: input[offset+index] = byte((value shr (index*8)) and 255)
proc seal(input: var seq[byte]) =
  ## A valid frame checksum cannot authorize an invalid transition, noncanonical body or bad proof.
  resetHash(0)
  let checksum = array[32, byte](blake2b256(input.toOpenArray(0, input.len-33)).value)
  for index in 0..<32: input[input.len-32+index] = checksum[index]
proc checkError(before: PreparedLightSnapshot, input: seq[byte], reason: LightDeltaError) =
  ## Copying and consuming restoration share strict refusals; failed ownership transfer preserves every byte.
  assert decodeLightDelta(input, before, LightDeltaSequence(1), limits()).error == reason
  var owned = input
  assert takeLightDelta(owned, before, LightDeltaSequence(1), limits()).error == reason
  assert owned == input
proc cycle(before: PreparedLightSnapshot, incoming: LightStateProof, encoded: seq[byte]) =
  ## Retire success, late provider refusal and retry, including all opaque transition/successor owners.
  resetHash(0)
  let decoded = decodeLightDelta(encoded, before, LightDeltaSequence(1), limits()).value
  assert decoded.snapshot.cache.lookup(key(0)).error == LightCacheError.UnknownKey
  var owned = encoded
  let adopted = takeLightDelta(owned, before, LightDeltaSequence(1), limits()).value
  assert owned.len == 0 and adopted.bytes == encoded
  refuseAfter(2)
  var failedInput = encoded
  assert takeLightDelta(failedInput, before, LightDeltaSequence(1), limits()).error ==
      LightDeltaError.BackendFailure
  assert failedInput == encoded
  resetHash(0)
  let prepared = prepareLightDelta(before, LightDeltaSequence(1), [incoming], [key(0)], limits()).value
  assert prepared.bytes == encoded
proc golden() =
  ## Independent Python hashlib/struct construction fixes the complete empty-transition wire image.
  resetHash(0)
  let before = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy()).value
  let encoded = prepareLightDelta(before, LightDeltaSequence(1), [], [], limits()).value
  const Golden = "5241474e41524f4b2d4c494748542d44454c54412d56310a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b0062d2eceea5d0d77cc73cf089516b5c93da78a780306862793f28089f26835b0062d2eceea5d0d77cc73cf089516b5c93da78a780306862793f28089f26835010000000000000000000000000000000000000000000000a751514a56cc0b86bec24626da4a0fcda7476b050a46d8d8adbaca39779d65bf"
  var actual = ""
  for octet in encoded.encodedBytes:
    actual.add("0123456789abcdef"[int(octet shr 4)])
    actual.add("0123456789abcdef"[int(octet and 15)])
  assert actual == Golden and encoded.byteLength == 208 and LightDeltaHeaderBytes == 176
  let restored = decodeLightDelta(encoded.encodedBytes, before, LightDeltaSequence(1), limits()).value
  assert restored.snapshot.bytes == before.bytes and uint64(restored.sequence) == 1
  assert decodeLightDelta(encoded.encodedBytes, before, LightDeltaSequence(2), limits()).error ==
      LightDeltaError.WrongSequence
  var readOnly = policy()
  readOnly.cache.writes = ElementLimit(0)
  let frozen = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], readOnly).value
  assert prepareLightDelta(frozen, LightDeltaSequence(high(uint64)), [], [], limits()).error ==
      LightDeltaError.None
proc exercise(before: PreparedLightSnapshot, incoming: LightStateProof) =
  ## Strict complete transitions match independent preparation and preserve original knowledge on every refusal.
  resetHash(0)
  let prepared = prepareLightDelta(before, LightDeltaSequence(1), [incoming], [key(0)], limits()).value
  let encoded = prepared.bytes
  let expected = before.update([incoming], [key(0)]).value
  assert prepared.initialized and not default(PreparedLightDelta).initialized
  assert prepared.snapshot.bytes == expected.bytes and prepared.byteLength == 420
  assert array[32, byte](prepared.baseChecksum) == array[32, byte](before.checksum)
  let restored = decodeLightDelta(encoded, before, LightDeltaSequence(1), limits()).value
  assert restored.bytes == encoded and restored.snapshot.bytes == expected.bytes
  assert restored.snapshot.cache.lookup(key(255)).value.kind == StateLookupKind.Absent
  assert restored.snapshot.cache.lookup(key(0)).error == LightCacheError.UnknownKey
  assert before.cache.lookup(key(0)).value.bytes.len == 33
  assert lightDeltaExtent(encoded, limits()).value == encoded.len
  var alias = encoded
  var input = encoded
  let taken = takeLightDelta(input, before, LightDeltaSequence(1), limits()).value
  assert input.len == 0
  alias[0] = 0
  assert taken.bytes == encoded
  var detached = taken.bytes
  detached[LightDeltaHeaderBytes] = 77
  assert taken.bytes == encoded and taken.snapshot.bytes == expected.bytes
  resetHash(1)
  for length in 0..<encoded.len:
    var prefix = newSeq[byte](length)
    for index in 0..<length: prefix[index] = encoded[index]
    checkError(before, prefix, LightDeltaError.IncompleteFrame)
  var bad = encoded
  bad.add(0)
  checkError(before, bad, LightDeltaError.InvalidFormat)
  bad = encoded
  bad[0] = 0
  checkError(before, bad, LightDeltaError.InvalidFormat)
  bad = encoded
  bad[24] = 1
  checkError(before, bad, LightDeltaError.WrongChain)
  bad = encoded
  bad[56] = bad[56] xor 1
  checkError(before, bad, LightDeltaError.WrongRoot)
  bad = encoded
  bad[88] = bad[88] xor 1
  checkError(before, bad, LightDeltaError.WrongBase)
  bad = encoded
  put(bad, 152, 2)
  checkError(before, bad, LightDeltaError.WrongSequence)
  bad = encoded
  put(bad, 168, high(uint64))
  checkError(before, bad, LightDeltaError.LimitExceeded)
  bad = encoded
  put(bad, 160, high(uint64))
  checkError(before, bad, LightDeltaError.LimitExceeded)
  bad = encoded
  bad[LightDeltaHeaderBytes+31] = 2
  checkError(before, bad, LightDeltaError.InvalidFormat)
  bad = encoded
  bad[LightDeltaHeaderBytes+32] = 1
  checkError(before, bad, LightDeltaError.InvalidFormat)
  let conflict = prepareLightDelta(before, LightDeltaSequence(1), [incoming], [incoming.key],
      limits())
  assert conflict.proofError == LightCacheError.DuplicateKey
  var tight = limits()
  tight.bytes = ByteLimit(encoded.len-1)
  assert prepareLightDelta(before, LightDeltaSequence(1), [incoming], [key(0)], tight).error ==
      LightDeltaError.LimitExceeded
  assert decodeLightDelta(encoded, before, LightDeltaSequence(1), tight).error ==
      LightDeltaError.LimitExceeded
  assert prepareLightDelta(before, LightDeltaSequence(0), [], [], limits()).error ==
      LightDeltaError.WrongSequence
  assert default(PreparedLightDelta).initialized == false
  let uninitialized = decodeLightDelta(encoded, default(PreparedLightSnapshot), LightDeltaSequence(
      1), limits())
  assert uninitialized.error == LightDeltaError.Uninitialized
  assert calls() == 0
  resetHash(0)
  bad = encoded
  bad[bad.len-1] = bad[bad.len-1] xor 1
  checkError(before, bad, LightDeltaError.ChecksumMismatch)
  bad = encoded
  bad[120] = bad[120] xor 1
  seal(bad)
  checkError(before, bad, LightDeltaError.InvalidTransition)
  bad = encoded
  bad[LightDeltaHeaderBytes+42] = 0 # Repeated canonical key now conflicts with the first forget key.
  seal(bad)
  checkError(before, bad, LightDeltaError.InvalidFormat)
  bad = encoded
  bad[LightDeltaHeaderBytes+84] = bad[LightDeltaHeaderBytes+84] xor 1
  seal(bad)
  let wrongProof = decodeLightDelta(bad, before, LightDeltaSequence(1), limits())
  assert wrongProof.proofError == LightCacheError.InvalidProof
  var invalid = incoming
  invalid.proof.nodes[0] = default(EncodedStateNode)
  let refused = prepareLightDelta(before, LightDeltaSequence(1), [invalid], [key(0)], limits())
  assert refused.proofError == LightCacheError.InvalidProof
  let stale = decodeLightDelta(encoded, expected, LightDeltaSequence(1), limits())
  assert stale.error == LightDeltaError.WrongBase
  resetHash(0)
  discard decodeLightDelta(encoded, before, LightDeltaSequence(1), limits()).value
  let attempts = calls()
  assert attempts == 4
  for successful in 0..<int(attempts):
    refuseAfter(cint(successful))
    var owned = encoded
    assert takeLightDelta(owned, before, LightDeltaSequence(1), limits()).error ==
        LightDeltaError.BackendFailure
    assert owned == encoded and calls() == cint(successful+1)
  resetHash(0)
  discard prepareLightDelta(before, LightDeltaSequence(1), [incoming], [key(0)], limits()).value
  let preparations = calls()
  assert preparations == 4
  for successful in 0..<int(preparations):
    refuseAfter(cint(successful))
    assert prepareLightDelta(before, LightDeltaSequence(1), [incoming], [key(0)], limits()).error ==
        LightDeltaError.BackendFailure
  resetHash(0)
  for iteration in 0..<10: cycle(before, incoming, encoded)
  let baseline = getOccupiedMem()
  for iteration in 0..<1000: cycle(before, incoming, encoded)
  let retired = getOccupiedMem()
  assert baseline == retired
  recordArcRelease("storage_light_delta", 1000, baseline, retired)
proc main() =
  ## Complete independent map hashing, rather than partial-cache serialization, fixes the trusted root.
  golden()
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)), StateEntry(key: key(128))]
  let bounds = StateTrieLimits(items: ElementLimit(2), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(33))
  let root = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  assert array[32, byte](root) == array[32, byte](trie.commitment.root)
  let a = LightStateProof(key: key(0), proof: trie.prove(key(0), policy().cache.proof).value)
  let b = LightStateProof(key: key(128), proof: trie.prove(key(128), policy().cache.proof).value)
  let incoming = LightStateProof(key: key(255), proof: trie.prove(key(255), policy().cache.proof).value)
  let before = prepareLightSnapshot(default(StorageChainId), root, [a, b], policy()).value
  exercise(before, incoming)
main()
echo "PASS storage light delta: canonical bounded frames, exact predecessor/sequence and atomic owned transitions"
