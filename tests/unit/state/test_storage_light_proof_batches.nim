# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Batch proof retrieval preflights one bounded canonical scan and returns detached evidence in request order.
# @@Verification={"arc":"storage_light_proof_batches_arc_release"}
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/light_file_cache as storage_light_file_cache
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Batch reads must remain usable when all authentication/checksum hashing would refuse.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Only preparation and explicit verification may invoke the provider.
proc key(first: byte): StateKey =
  ## Fixed ordered query identities distinguish small/long/empty presence, absence and unknown evidence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc policy(): LightSnapshotLimits =
  ## Bound the independently authenticated fixture and all retained image copies.
  LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(items: ElementLimit(5),
    writes: ElementLimit(5), valueBytes: ByteLimit(68),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc budget(): LightProofBatchLimits =
  ## Bound sort descriptors, examined headers, aggregate payload and individual proof output separately.
  LightProofBatchLimits(queries: ElementLimit(5), entries: ElementLimit(5),
    nodes: ElementLimit(1245), valueBytes: ByteLimit(68), proof: policy().cache.proof)
proc same(actual, expected: StateProof) =
  ## Exact path/value comparisons check transport identity independently of cache lookup results.
  assert actual.nodes.len == expected.nodes.len and actual.value == expected.value
  for index in 0..<actual.nodes.len:
    assert array[64, byte](actual.nodes[index]) == array[64, byte](expected.nodes[index])
proc compare(image: PreparedLightSnapshot, trie: FullStateTrie, keys: openArray[StateKey],
    bounds: LightProofBatchLimits) =
  ## Arbitrary request order must survive private sorting while every returned proof verifies at the independent root.
  resetHash(1)
  let found = image.prove(keys, bounds)
  assert found.error == LightSnapshotError.None and found.value.len == keys.len and calls() == 0
  resetHash(0)
  for index, query in keys:
    let retained = found.value[index]
    assert array[31, byte](retained.key) == array[31, byte](query)
    same(retained.proof, trie.prove(query, policy().cache.proof).value)
    let one = image.prove(query, LightProofReadLimits(entries: ElementLimit(5),
      proof: policy().cache.proof)).value
    same(retained.proof, one)
    let verified = verifyStateProof(image.root, query, retained.proof, policy().cache.proof).value
    assert verified.kind == image.cache.lookup(query).value.kind
proc detached(image: PreparedLightSnapshot) =
  ## Independently mutable output cannot change retained evidence or another extraction.
  var found = image.prove([key(255), key(0)], budget()).value
  found[1].proof.value[0] = 99
  found[1].proof.nodes[0] = default(EncodedStateNode)
  found[0].key = key(1)
  let again = image.prove([key(0), key(255)], budget()).value
  assert again[0].proof.value[0] == 0 and image.cache.lookup(key(0)).value.bytes[0] == 0
  assert array[64, byte](again[0].proof.nodes[0]) != default(array[64, byte])
  assert array[31, byte](again[1].key) == array[31, byte](key(255))
proc restoredProofs(image: PreparedLightSnapshot): seq[LightStateProof] =
  ## All batch proof buffers outlive a temporary transferred image and its consumed source bytes.
  var bytes = image.bytes
  let restored = takeLightSnapshot(bytes, image.chainId, image.root, image.limits).value
  assert bytes.len == 0
  restored.prove([key(0), key(255)], budget()).value
proc cycle(image: PreparedLightSnapshot) =
  ## Retire successful output and sorted scratch for late unknown/aggregate failures within an isolated scope.
  detached(image)
  let unknown = image.prove([key(0), key(64), key(224)], budget())
  assert unknown.proofError == LightCacheError.UnknownKey
  var short = budget()
  short.valueBytes = ByteLimit(34)
  let limited = image.prove([key(0), key(64)], short)
  assert limited.error == LightSnapshotError.LimitExceeded
  let complete = image.prove([key(192), key(128), key(0)], budget()).value
  assert complete.len == 3 and complete[1].proof.value.len == 0
proc prepared(image: PreparedLightSnapshot, trie: FullStateTrie) =
  ## All subset sizes and reversed order share one header budget, with exact aggregate boundary witnesses.
  let identities = [key(0), key(64), key(128), key(192), key(255)]
  for mask in 0..<32:
    var selected: seq[StateKey] = @[]
    var exact = budget()
    var nodes = 0
    var values = 0
    var examined = 0
    for slot in 0..<5:
      # Reverse caller order exercises sorting and output-position restoration for every subset.
      let index = 4-slot
      if (mask and (1 shl index)) != 0:
        selected.add(identities[index])
        let proof = trie.prove(identities[index], policy().cache.proof).value
        nodes += proof.nodes.len
        values += proof.value.len
        examined = max(examined, index+1)
    exact.queries = ElementLimit(selected.len)
    exact.entries = ElementLimit(examined)
    exact.nodes = ElementLimit(nodes)
    exact.valueBytes = ByteLimit(values)
    compare(image, trie, selected, exact)
    resetHash(1)
    if examined > 0:
      # A batch needs each header only once, but cannot skip the final requested entry's header.
      var short = exact
      short.entries = ElementLimit(examined-1)
      assert image.prove(selected, short).error == LightSnapshotError.LimitExceeded
    if nodes > 0:
      var short = exact
      short.nodes = ElementLimit(nodes-1)
      assert image.prove(selected, short).error == LightSnapshotError.LimitExceeded
    if values > 0:
      var short = exact
      short.valueBytes = ByteLimit(values-1)
      assert image.prove(selected, short).error == LightSnapshotError.LimitExceeded
    assert calls() == 0
    resetHash(0)
  var small = budget()
  small.proof.valueBytes = ByteLimit(2)
  compare(image, trie, [key(64)], small)
  let maximum = high(uint64)
  let unlimited = LightProofBatchLimits(queries: ElementLimit(maximum), entries: ElementLimit(maximum),
    nodes: ElementLimit(maximum), valueBytes: ByteLimit(maximum),
    proof: StateProofLimits(nodes: ElementLimit(maximum), valueBytes: ByteLimit(maximum)))
  compare(image, trie, [key(255), key(192), key(128), key(64), key(0)], unlimited)
  resetHash(1)
  var afterLast = default(array[31, byte])
  afterLast[0] = 255
  afterLast[1] = 1
  assert image.prove([key(0), StateKey(afterLast)], budget()).proofError ==
      LightCacheError.UnknownKey
  var short = budget()
  short.queries = ElementLimit(1)
  assert image.prove([key(0), key(64)], short).error == LightSnapshotError.LimitExceeded
  short = budget()
  short.proof.valueBytes = ByteLimit(32)
  assert image.prove([key(128), key(192)], short).error == LightSnapshotError.LimitExceeded
  short = budget()
  short.proof.nodes = ElementLimit(0)
  assert image.prove([key(0)], short).error == LightSnapshotError.LimitExceeded
  short = budget()
  short.entries = ElementLimit(0)
  assert image.prove([key(255), key(0), key(255)], short).proofError == LightCacheError.DuplicateKey
  assert image.prove([key(0), key(224)], budget()).proofError == LightCacheError.UnknownKey
  assert image.prove([key(1)], budget()).proofError == LightCacheError.UnknownKey
  assert default(PreparedLightSnapshot).prove([], budget()).error ==
      LightSnapshotError.Uninitialized
  assert image.prove([], default(LightProofBatchLimits)).value.len == 0
  assert calls() == 0
  resetHash(0)
  let held = restoredProofs(image)
  same(held[0].proof, trie.prove(key(0), policy().cache.proof).value)
  same(held[1].proof, trie.prove(key(255), policy().cache.proof).value)
  let forgotten = image.forget([key(255)]).value
  assert forgotten.prove([key(0), key(255)], budget()).proofError == LightCacheError.UnknownKey
  assert image.prove([key(0), key(255)], budget()).value.len == 2
  # Read-only images retain evidence independently of their zero mutation allowance.
  var readOnly = policy()
  readOnly.cache.writes = ElementLimit(0)
  let frozen = restoreLightSnapshot(image.bytes, image.chainId, image.root, readOnly).value
  compare(frozen, trie, [key(255), key(0), key(128)], budget())
  for iteration in 0..<10: cycle(image)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(image)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_proof_batches", 1000, before, after)
proc empty() =
  ## Zero-node authenticated absence, empty knowledge and unknown queries never collapse into one result.
  let chain = default(StorageChainId)
  let root = default(StateRoot)
  let blank = prepareLightSnapshot(chain, root, [], policy()).value
  let absent = [LightStateProof(key: key(128)), LightStateProof(key: key(0))]
  let image = prepareLightSnapshot(chain, root, absent, policy()).value
  let zero = LightProofBatchLimits(queries: ElementLimit(2), entries: ElementLimit(2))
  resetHash(1)
  let found = image.prove([key(128), key(0)], zero).value
  assert found.len == 2 and found[0].proof.nodes.len == 0 and found[1].proof.value.len == 0
  assert image.prove([key(0), key(1)], zero).proofError == LightCacheError.UnknownKey
  assert blank.prove([key(0)], zero).proofError == LightCacheError.UnknownKey
  assert blank.prove([], default(LightProofBatchLimits)).value.len == 0
  assert calls() == 0
  resetHash(0)
proc files(image: PreparedLightSnapshot) {.raises.} =
  ## Batch evidence from a real reopened file remains usable after closing the directory lease and removing files.
  var owner = default(LightFileCache)
  let config = LightFileConfig(root: image.root, limits: image.limits)
  let path = "storage-light-proof-batches"
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert initializeLightFileCache(owner, path, config, image).error == FileError.None
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  let held = owner.preparedSnapshot.value
  assert owner.close == FileError.None
  var current = path & "/CURRENT"
  var lock = path & "/LOCK"
  var directory = path
  assert posix.unlink(current.toCString()) == 0
  assert posix.unlink(lock.toCString()) == 0
  assert posix.rmdir(directory.toCString()) == 0
  resetHash(1)
  resetIo()
  let found = held.prove([key(255), key(192), key(0)], budget()).value
  assert found.len == 3 and found[1].proof.value[0] == 7 and found[2].proof.value[0] == 0
  assert calls() == 0 and ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0 and ioCalls(renameIo) == 0
  resetHash(0)
proc main() {.raises.} =
  ## Complete-map hashing establishes an independent root before selecting retained query evidence.
  resetHash(0)
  resetIo()
  var other = newSeq[byte](33)
  for index in 0..<33: other[index] = 7
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)),
    StateEntry(key: key(64), value: @[1'u8, 2'u8]), StateEntry(key: key(128)),
    StateEntry(key: key(192), value: other)]
  let bounds = StateTrieLimits(items: ElementLimit(4), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(68))
  let root = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  assert array[32, byte](root) == array[32, byte](trie.commitment.root)
  var proofs: seq[LightStateProof] = @[]
  for first in [255'u8, 0'u8, 128'u8, 64'u8, 192'u8]:
    proofs.add(LightStateProof(key: key(first), proof: trie.prove(key(first), policy().cache.proof).value))
  let image = prepareLightSnapshot(default(StorageChainId), root, proofs, policy()).value
  prepared(image, trie)
  empty()
  files(image)
try:
  main()
except:
  quit(2)
echo "PASS storage light proof batches: one bounded scan, atomic aggregate limits and detached ordered evidence"
