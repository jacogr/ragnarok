# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded retained proof extraction preserves evidence identity, detached ownership and file recovery rules.
# @@Verification={"arc":"storage_light_proof_retrieval_arc_release"}
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_file_cache as storage_light_file_cache
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Retained evidence extraction must work even when every provider hash would refuse.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Prove retrieval performs no authentication or checksum hashing.
proc key(first: byte): StateKey =
  ## Ordered identities separate retained presence, retained absence and locally unknown keys.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc policy(): LightSnapshotLimits =
  ## Fixture ceilings admit complete evidence while keeping every encoded image bounded.
  LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(items: ElementLimit(4),
    writes: ElementLimit(4), valueBytes: ByteLimit(66),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc budget(entries = 4): LightProofReadLimits =
  ## Per-call traversal and output limits may be narrower than the image's preparation policy.
  LightProofReadLimits(entries: ElementLimit(entries), proof: policy().cache.proof)
proc same(actual, expected: StateProof) =
  ## Compare exact producer transport, including terminal evidence for authenticated absence.
  assert actual.value == expected.value and actual.nodes.len == expected.nodes.len
  for index in 0..<actual.nodes.len:
    assert array[64, byte](actual.nodes[index]) == array[64, byte](expected.nodes[index])
proc detached(image: PreparedLightSnapshot) =
  ## Independently mutable output cannot corrupt the image, other extractions or verified lookup readers.
  var extracted = image.prove(key(0), budget()).value
  extracted.value[0] = 77
  extracted.nodes[0] = default(EncodedStateNode)
  let again = image.prove(key(0), budget()).value
  assert again.value[0] == 0
  assert image.cache.lookup(key(0)).value.bytes[0] == 0
  assert array[64, byte](again.nodes[0]) != default(array[64, byte])
proc owned(image: PreparedLightSnapshot): PreparedLightSnapshot =
  ## Transfer a temporary image, drop its mutable source and retain only validated immutable ownership.
  var encoded = image.bytes
  let restored = takeLightSnapshot(encoded, image.chainId, image.root, image.limits)
  assert restored.error == LightSnapshotError.None and encoded.len == 0
  restored.value
proc independentProof(image: PreparedLightSnapshot): StateProof =
  ## A detached proof outlives the transferred image from which it was extracted.
  let temporary = owned(image)
  temporary.prove(key(0), budget()).value
proc cycle(image: PreparedLightSnapshot) =
  ## Retire detached proof buffers, successful transferred images and failed reads before measuring ARC.
  let restored = owned(image)
  detached(restored)
  assert restored.prove(key(255), budget(2)).error == LightSnapshotError.LimitExceeded
  assert restored.prove(key(64), budget()).proofError == LightCacheError.UnknownKey
proc prepared(trie: FullStateTrie, image: PreparedLightSnapshot) =
  ## Exact scan/output bounds and canonical proofs distinguish unobserved keys from authenticated absence.
  let identities = [key(0), key(128), key(255)]
  for index in 0..<identities.len:
    let query = identities[index]
    let expected = trie.prove(query, policy().cache.proof).value
    resetHash(1)
    let found = image.prove(query, budget(index+1))
    assert found.error == LightSnapshotError.None and calls() == 0
    same(found.value, expected)
    assert image.prove(query, budget(index)).error == LightSnapshotError.LimitExceeded
    var exact = budget()
    exact.proof.nodes = ElementLimit(expected.nodes.len)
    exact.proof.valueBytes = ByteLimit(expected.value.len)
    same(image.prove(query, exact).value, expected)
    if expected.nodes.len > 0:
      # A one-node deficit refuses without producing a partial path.
      var short = exact
      short.proof.nodes = ElementLimit(expected.nodes.len-1)
      assert image.prove(query, short).error == LightSnapshotError.LimitExceeded
    if expected.value.len > 0:
      # Value limits are checked before either of the output allocations.
      var short = exact
      short.proof.valueBytes = ByteLimit(expected.value.len-1)
      assert image.prove(query, short).error == LightSnapshotError.LimitExceeded
    assert calls() == 0
    resetHash(0)
    let verified = verifyStateProof(image.root, query, found.value, policy().cache.proof).value
    let expectedKind = if index == 2: StateLookupKind.Absent else: StateLookupKind.Present
    assert verified.kind == expectedKind
  resetHash(1)
  assert image.prove(key(64), budget(1)).error == LightSnapshotError.LimitExceeded
  assert image.prove(key(64), budget(2)).proofError == LightCacheError.UnknownKey
  assert image.prove(key(254), budget()).proofError == LightCacheError.UnknownKey
  assert default(PreparedLightSnapshot).prove(key(0), budget()).error ==
      LightSnapshotError.Uninitialized
  var afterLast = default(array[31, byte])
  afterLast[0] = 255
  afterLast[1] = 1
  let beyond = StateKey(afterLast)
  assert image.prove(beyond, budget(3)).proofError == LightCacheError.UnknownKey
  assert image.prove(beyond, budget(2)).error == LightSnapshotError.LimitExceeded
  assert calls() == 0
  detached(image)
  resetHash(0)
  let independent = independentProof(image)
  same(independent, trie.prove(key(0), policy().cache.proof).value)
  let forgotten = image.forget([key(255)]).value
  assert forgotten.prove(key(255), budget()).proofError == LightCacheError.UnknownKey
  assert image.prove(key(255), budget()).error == LightSnapshotError.None
  # Zero-node empty-root absence remains a retained proof; no evidence in an empty image means unknown.
  let emptyRoot = default(StateRoot)
  let empty = prepareLightSnapshot(default(StorageChainId), emptyRoot, [], policy()).value
  let absent = LightStateProof(key: key(128))
  let zero = prepareLightSnapshot(default(StorageChainId), emptyRoot, [absent], policy()).value
  var none = budget(1)
  none.proof = StateProofLimits()
  resetHash(1)
  let zeroProof = zero.prove(key(128), none).value
  assert zeroProof.nodes.len == 0 and zeroProof.value.len == 0
  assert zero.prove(key(0), none).proofError == LightCacheError.UnknownKey
  assert empty.prove(key(128), budget(0)).proofError == LightCacheError.UnknownKey
  assert calls() == 0
  resetHash(0)
  for iteration in 0..<10: cycle(image)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(image)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_proof_retrieval", 1000, before, after)
proc retainedFile(image: PreparedLightSnapshot): PreparedLightSnapshot {.raises.} =
  ## A selected image owns no native lease and survives writer poisoning, close, reopen and file removal.
  let path = "storage-light-proof-retrieval"
  let config = LightFileConfig(root: image.root, limits: image.limits)
  var owner = default(LightFileCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert owner.preparedSnapshot.error == FileError.Uninitialized
  assert initializeLightFileCache(owner, path, config, image).error == FileError.None
  resetIo()
  resetHash(1)
  let held = owner.preparedSnapshot.value
  same(held.prove(key(0), budget()).value, image.prove(key(0), budget()).value)
  assert calls() == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0
  resetHash(0)
  assert owner.close == FileError.None
  assert owner.preparedSnapshot.error == FileError.Uninitialized
  assert openLightFileCache(owner, path, config) == FileError.None
  let reopened = owner.preparedSnapshot.value
  same(reopened.prove(key(255), budget()).value, held.prove(key(255), budget()).value)
  let next = image.forget([key(255)]).value
  armIo(syncIo, 1, 1, failedIo)
  assert owner.publish(next).error == FileError.PublishedUnsynced and pendingIo() == 0
  resetIo()
  assert owner.preparedSnapshot.error == FileError.RecoveryRequired
  assert held.prove(key(255), budget()).error == LightSnapshotError.None
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  assert owner.preparedSnapshot.value.prove(key(255), budget()).proofError ==
      LightCacheError.UnknownKey
  assert owner.close == FileError.None
  var current = path & "/CURRENT"
  var lock = path & "/LOCK"
  var directory = path
  assert posix.unlink(current.toCString()) == 0
  assert posix.unlink(lock.toCString()) == 0
  assert posix.rmdir(directory.toCString()) == 0
  held
proc main() {.raises.} =
  ## Independent complete-map hashing fixes the trusted root; only selected query evidence enters the image.
  resetHash(0)
  resetIo()
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)), StateEntry(key: key(128))]
  let bounds = StateTrieLimits(items: ElementLimit(2), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(33))
  let root = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  assert array[32, byte](root) == array[32, byte](trie.commitment.root)
  var proofs: seq[LightStateProof] = @[]
  for first in [255'u8, 0'u8, 128'u8]:
    proofs.add(LightStateProof(key: key(first), proof: trie.prove(key(first), policy().cache.proof).value))
  let image = prepareLightSnapshot(default(StorageChainId), root, proofs, policy()).value
  prepared(trie, image)
  let held = retainedFile(image)
  same(held.prove(key(255), budget()).value, trie.prove(key(255), policy().cache.proof).value)
try:
  main()
except:
  quit(2)
echo "PASS storage light proof retrieval: bounded detached evidence, unknown/absence and retained file images"
