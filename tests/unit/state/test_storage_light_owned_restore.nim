# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Owned light restore consumes only validated buffers, preserves every refusal and isolates safe aliases/readers.
# @@Verification={"arc":"storage_light_owned_restore_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/[light_snapshot, light_state_cache, state_proof, full_state_trie, database_identity]
import ../../../src/codec/[bounded, state_layout, state_trie]
import ../../../src/crypto/primitives
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Resource/shape refusal and provider recovery retain the same original owned input.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Exercise partial checksum/proof admission without consuming caller ownership.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Adoption retains the existing eight checksum/proof attempts without skipping validation.
proc key(first: byte): StateKey =
  ## Fixed queries cover long and empty present values plus authenticated absence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc limits(): LightSnapshotLimits =
  ## Preserve future mutation and all logical/image ceilings exactly after adoption.
  LightSnapshotLimits(bytes: ByteLimit(8192), cache: LightCacheLimits(items: ElementLimit(4),
    writes: ElementLimit(2), valueBytes: ByteLimit(33),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc image(): PreparedLightSnapshot =
  ## A separate flat-map calculator supplies the root before complete-trie proofs are retained.
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)), StateEntry(key: key(128))]
  let bounds = StateTrieLimits(items: ElementLimit(4), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(33))
  let expected = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  var proofs: seq[LightStateProof] = @[]
  for number in [255'u8, 128, 0]:
    proofs.add(LightStateProof(key: key(number), proof: trie.prove(key(number), limits().cache.proof).value))
  prepareLightSnapshot(default(StorageChainId), expected, proofs, limits()).value
proc unchanged(input: var seq[byte], expected: LightSnapshotError, root: StateRoot,
    chain: StorageChainId, policy: LightSnapshotLimits) =
  ## Every non-success leaves all input octets and length available for independent retry or inspection.
  let original = input
  let failed = takeLightSnapshot(input, chain, root, policy)
  assert failed.error == expected
  assert input == original
proc success(prepared: PreparedLightSnapshot) =
  ## Consumed slots and safe independent aliases cannot mutate the resulting opaque image or retained cache readers.
  resetHash(0)
  var input = prepared.bytes
  var alias = input
  let restored = takeLightSnapshot(input, prepared.chainId, prepared.root, limits()).value
  assert input.len == 0 and calls() == 8
  assert restored.bytes == prepared.bytes and restored.cache.len == 3
  alias[0] = 0
  assert restored.bytes == prepared.bytes # A safe sequence copy retains independent backing bytes across transfer.
  input = @[9'u8, 8, 7]
  assert restored.bytes == prepared.bytes
  let retained = restored.cache
  let trimmed = restored.forget([key(128)]).value
  assert trimmed.cache.len == 2 and retained.len == 3
  assert trimmed.cache.lookup(key(128)).error == LightCacheError.UnknownKey
  assert retained.lookup(key(128)).value.kind == StateLookupKind.Present
  assert retained.lookup(key(255)).value.kind == StateLookupKind.Absent
  assert retained.lookup(key(0)).value.bytes == newSeq[byte](33)
  assert uint64(restored.limits.cache.writes) == 2
  var copiedInput = prepared.bytes
  let copied = restoreLightSnapshot(copiedInput, prepared.chainId, prepared.root, limits()).value
  assert copiedInput == prepared.bytes
  copiedInput[0] = 0
  assert copied.bytes == prepared.bytes # Borrowed restore continues to copy rather than taking its caller's buffer.
proc failures(prepared: PreparedLightSnapshot) =
  ## Truncation, identity, quota, checksum, proof and backend refusal must never consume untrusted input.
  resetHash(0)
  let complete = prepared.bytes
  for length in 0..<complete.len:
    var prefix = newSeq[byte](length)
    for index in 0..<length: prefix[index] = complete[index]
    unchanged(prefix, LightSnapshotError.InvalidFormat, prepared.root, prepared.chainId, limits())
  var corrupt = prepared.bytes
  corrupt[0] = 0
  unchanged(corrupt, LightSnapshotError.InvalidFormat, prepared.root, prepared.chainId, limits())
  var rawIdentity = default(array[32, byte])
  rawIdentity[0] = 1
  corrupt = prepared.bytes
  resetHash(1)
  unchanged(corrupt, LightSnapshotError.WrongChain, prepared.root, StorageChainId(rawIdentity),
      limits())
  unchanged(corrupt, LightSnapshotError.WrongRoot, StateRoot(rawIdentity), prepared.chainId, limits())
  var short = limits()
  short.bytes = ByteLimit(complete.len-1)
  unchanged(corrupt, LightSnapshotError.LimitExceeded, prepared.root, prepared.chainId, short)
  var oversizedCount = prepared.bytes
  for index in 88..<96: oversizedCount[index] = 255 # Maximal serialized count cannot select a native descriptor extent.
  var broad = limits()
  broad.cache.items = ElementLimit(high(uint64))
  unchanged(oversizedCount, LightSnapshotError.LengthOverflow, prepared.root, prepared.chainId, broad)
  assert calls() == 0
  resetHash(0)
  corrupt[corrupt.len-1] = corrupt[corrupt.len-1] xor 1
  unchanged(corrupt, LightSnapshotError.ChecksumMismatch, prepared.root, prepared.chainId, limits())
  corrupt = prepared.bytes
  corrupt[96+41+128] = 1 # Recomputed integrity cannot authorize a long value inconsistent with the independent root.
  let digest = array[32, byte](blake2b256(corrupt.toOpenArray(0, corrupt.len-33)).value)
  for index in 0..<32: corrupt[corrupt.len-32+index] = digest[index]
  let falseValue = takeLightSnapshot(corrupt, prepared.chainId, prepared.root, limits())
  assert falseValue.error == LightSnapshotError.ProofFailure
  assert falseValue.proofError == LightCacheError.ValueMismatch
  assert corrupt.len == complete.len and corrupt[96+41+128] == 1
  for successful in 0..<8:
    # Earlier private verified lookups must retire without taking or changing the retryable source buffer.
    corrupt = prepared.bytes
    refuseAfter(cint(successful))
    unchanged(corrupt, LightSnapshotError.BackendFailure, prepared.root, prepared.chainId, limits())
    assert calls() == cint(successful+1)
  resetHash(0)
  corrupt = prepared.bytes
  assert takeLightSnapshot(corrupt, prepared.chainId, prepared.root, limits()).value.bytes == complete
  assert corrupt.len == 0
proc cycle(prepared: PreparedLightSnapshot) =
  ## Successful take, partial failure, retry and immutable extraction release all input/result/cache owners.
  resetHash(0)
  var input = prepared.bytes
  let restored = takeLightSnapshot(input, prepared.chainId, prepared.root, limits()).value
  assert input.len == 0 and restored.cache.len == 3
  input = prepared.bytes
  refuseAfter(3)
  let failed = takeLightSnapshot(input, prepared.chainId, prepared.root, limits())
  assert failed.error == LightSnapshotError.BackendFailure and input.len == prepared.byteLength
  resetHash(0)
  assert takeLightSnapshot(input, prepared.chainId, prepared.root, limits()).value.cache.len == 3
  assert input.len == 0
proc main() =
  ## The supported runner records exact release after a warmed success/partial-refusal/retry path.
  resetHash(0)
  let prepared = image()
  success(prepared)
  failures(prepared)
  for iteration in 0..<10: cycle(prepared)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(prepared)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_owned_restore", 1000, before, after)
main()
echo "PASS storage light owned restore: consume on success, preserve failures, independent aliases and ARC retirement"
