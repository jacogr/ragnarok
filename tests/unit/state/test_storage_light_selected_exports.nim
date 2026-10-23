# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Selective canonical exports enforce explicit output policies without changing complete-root trust or source knowledge.
# @@Verification={"arc":"storage_light_selected_exports_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io]
import ../../../src/storage/[light_snapshot, light_state_cache, light_file_cache, state_proof,
  full_state_trie, database_identity, file_errors]
import ../../../src/codec/[bounded, state_layout, state_trie]
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## All selection/quota refusals precede encoding checksum and selected-proof restoration.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Every encoding checksum, restoration checksum and selected-proof hash can independently refuse.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Export deliberately revalidates its new image instead of adopting unchecked cached lookups.
proc key(first: byte): StateKey =
  ## Canonical query identities distinguish retained values, absence and local unknown evidence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc policy(): LightSnapshotLimits =
  ## The source image retains five queries at one independently trusted complete root.
  LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(items: ElementLimit(5),
    writes: ElementLimit(5), valueBytes: ByteLimit(68),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc cycle(image: PreparedLightSnapshot) =
  ## Selected images and failed restoration scratch retire together before occupied-memory observations.
  let selected = image.select([key(255), key(0)], policy(), ElementLimit(5)).value
  assert selected.cache.len == 2 and selected.cache.lookup(key(64)).error ==
      LightCacheError.UnknownKey
  refuseAfter(2)
  let failed = image.select([key(255), key(0)], policy(), ElementLimit(5))
  assert failed.error == LightSnapshotError.BackendFailure and calls() == 3
  resetHash(0)
  assert image.select([key(255), key(0)], policy(), ElementLimit(5)).value.bytes == selected.bytes
proc prepared(image: PreparedLightSnapshot, trie: FullStateTrie) =
  ## Every subset exports exact independent canonical bytes under a tightened read-only output policy.
  let identities = [key(0), key(64), key(128), key(192), key(255)]
  let original = image.bytes
  for mask in 0..<32:
    var keys: seq[StateKey] = @[]
    var proofs: seq[LightStateProof] = @[]
    var target = policy()
    var values = 0
    var path = 0
    var raw = 0
    for slot in 0..<5:
      # Reverse selection order must not change canonical output; only retained selected evidence is exported.
      let index = 4-slot
      if (mask and (1 shl index)) != 0:
        let query = identities[index]
        let proof = trie.prove(query, policy().cache.proof).value
        keys.add(query)
        proofs.add(LightStateProof(key: query, proof: proof))
        values += proof.value.len
        path = max(path, proof.nodes.len)
        raw = max(raw, proof.value.len)
    target.cache.items = ElementLimit(keys.len)
    target.cache.writes = ElementLimit(0)
    target.cache.valueBytes = ByteLimit(values)
    target.cache.proof = StateProofLimits(nodes: ElementLimit(path), valueBytes: ByteLimit(raw))
    let expected = prepareLightSnapshot(image.chainId, image.root, proofs, target).value
    target.bytes = ByteLimit(expected.byteLength)
    let selected = image.select(keys, target, ElementLimit(5)).value
    assert selected.bytes == expected.bytes and selected.cache.len == keys.len
    assert selected.byteLength == expected.byteLength
    assert uint64(selected.limits.bytes) == uint64(target.bytes)
    assert uint64(selected.limits.cache.writes) == 0
    assert array[32, byte](selected.chainId) == array[32, byte](image.chainId)
    assert array[32, byte](selected.root) == array[32, byte](trie.commitment.root)
    for index in 0..<5:
      # Omitted authenticated absence becomes unknown locally, just like an omitted present value.
      let lookup = selected.cache.lookup(identities[index])
      if (mask and (1 shl index)) != 0:
        assert lookup.error == LightCacheError.None
        assert lookup.value.kind == image.cache.lookup(identities[index]).value.kind
      else: assert lookup.error == LightCacheError.UnknownKey
    resetHash(1)
    var short = target
    short.bytes = ByteLimit(expected.byteLength-1)
    assert image.select(keys, short, ElementLimit(5)).error == LightSnapshotError.LimitExceeded
    assert calls() == 0 and image.bytes == original
    resetHash(0)
  resetHash(1)
  assert default(PreparedLightSnapshot).select([], policy(), ElementLimit(0)).error ==
      LightSnapshotError.Uninitialized
  assert image.select([key(0), key(224)], policy(), ElementLimit(5)).proofError ==
      LightCacheError.UnknownKey
  assert image.select([key(0), key(128), key(0)], policy(), ElementLimit(0)).proofError ==
      LightCacheError.DuplicateKey
  assert image.select([key(255)], policy(), ElementLimit(4)).error ==
      LightSnapshotError.LimitExceeded
  var short = policy()
  short.cache.items = ElementLimit(1)
  assert image.select([key(0), key(255)], short, ElementLimit(5)).error ==
      LightSnapshotError.LimitExceeded
  short = policy()
  short.cache.valueBytes = ByteLimit(32)
  assert image.select([key(0)], short, ElementLimit(5)).error == LightSnapshotError.LimitExceeded
  short = policy()
  short.cache.proof.valueBytes = ByteLimit(32)
  assert image.select([key(0)], short, ElementLimit(5)).error == LightSnapshotError.LimitExceeded
  short = policy()
  short.cache.proof.nodes = ElementLimit(0)
  assert image.select([key(255)], short, ElementLimit(5)).error == LightSnapshotError.LimitExceeded
  assert calls() == 0
  resetHash(0)
  let requested = [key(192), key(0), key(255)]
  let selected = image.select(requested, policy(), ElementLimit(5)).value
  let hashes = calls()
  assert hashes > 2
  for successful in 0..<int(hashes):
    refuseAfter(cint(successful))
    assert image.select(requested, policy(), ElementLimit(5)).error ==
        LightSnapshotError.BackendFailure
    assert calls() == cint(successful+1) and image.bytes == original
  resetHash(0)
  assert image.select(requested, policy(), ElementLimit(5)).value.bytes == selected.bytes
  var readOnly = policy()
  readOnly.cache.writes = ElementLimit(0)
  let frozen = restoreLightSnapshot(image.bytes, image.chainId, image.root, readOnly).value
  assert frozen.select(requested, policy(), ElementLimit(5)).value.bytes == selected.bytes
  assert image.cache.len == 5 and image.bytes == original
  for iteration in 0..<10: cycle(image)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(image)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_selected_exports", 1000, before, after)
proc empty() =
  ## Empty selection preserves a nonzero complete root; zero-node absence remains explicit retained evidence.
  let proofs = [LightStateProof(key: key(128)), LightStateProof(key: key(0))]
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), proofs, policy()).value
  var target = LightSnapshotLimits(bytes: ByteLimit(169), cache: LightCacheLimits(
      items: ElementLimit(1)))
  let one = image.select([key(128)], target, ElementLimit(2)).value
  assert one.byteLength == 169 and one.cache.lookup(key(128)).value.kind == StateLookupKind.Absent
  assert one.cache.lookup(key(0)).error == LightCacheError.UnknownKey
  target = LightSnapshotLimits(bytes: ByteLimit(128))
  let blank = image.select([], target, ElementLimit(0)).value
  assert blank.byteLength == 128 and blank.cache.len == 0
  assert blank.select([key(0)], policy(), ElementLimit(0)).proofError == LightCacheError.UnknownKey
proc files(image: PreparedLightSnapshot) {.raises.} =
  ## Explicit export policy needs its own namespace; a selected partial image retains its complete root after reopen.
  let path = "storage-light-selected-exports"
  let sourcePath = "storage-light-selected-source"
  var source = default(LightFileCache)
  var owner = default(LightFileCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
    if source.opened: discard source.close
  let sourceConfig = LightFileConfig(chain: image.chainId, root: image.root, limits: image.limits)
  assert initializeLightFileCache(source, sourcePath, sourceConfig, image).error == FileError.None
  var target = policy()
  target.cache.items = ElementLimit(2)
  target.cache.writes = ElementLimit(0)
  let selected = source.preparedSnapshot.value.select([key(255), key(0)], target, ElementLimit(5)).value
  resetIo()
  assert source.publish(selected).error == FileError.InvalidBatch
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0 and ioCalls(renameIo) == 0
  let config = LightFileConfig(chain: selected.chainId, root: selected.root, limits: target)
  assert initializeLightFileCache(owner, path, config, selected).error == FileError.None
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  let held = owner.preparedSnapshot.value
  assert held.bytes == selected.bytes and held.cache.len == 2
  assert held.cache.lookup(key(64)).error == LightCacheError.UnknownKey
  assert held.cache.lookup(key(255)).value.kind == StateLookupKind.Absent
  assert array[32, byte](held.root) == array[32, byte](image.root)
  assert owner.close == FileError.None and source.close == FileError.None
  for base in [path, sourcePath]:
    # Close original held leases before independently removing both exact private namespaces.
    var current = base & "/CURRENT"
    var lock = base & "/LOCK"
    var directory = base
    assert posix.unlink(current.toCString()) == 0
    assert posix.unlink(lock.toCString()) == 0
    assert posix.rmdir(directory.toCString()) == 0
  assert held.cache.lookup(key(0)).value.bytes.len == 33
proc main() {.raises.} =
  ## Complete independent flat-map hashing supplies root authority; export only changes local retained evidence.
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
  var chain = default(array[32, byte])
  chain[0] = 7
  let image = prepareLightSnapshot(StorageChainId(chain), root, proofs, policy()).value
  prepared(image, trie)
  empty()
  files(image)
try:
  main()
except:
  quit(2)
echo "PASS storage light selected exports: exact canonical subsets, explicit policy and unchanged complete-root trust"
