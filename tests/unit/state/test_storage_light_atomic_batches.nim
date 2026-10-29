# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Atomic proof/forget batches replace evidence at exact capacity through one canonical image and one durable selection.
# @@Verification={"arc":"storage_light_atomic_batches_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io]
import ../../../src/storage/light/[snapshot as light_snapshot, file_cache as light_file_cache,
    state_cache as light_state_cache]
import ../../../src/storage/state_proof
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/database_identity
import ../../../src/storage/file/errors as file_errors
import ../../../src/storage/durability
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Combined quotas and cross-list conflicts must refuse before proof or checksum hashes.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Each incoming proof node, long value and final checksum can independently refuse.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Only the incoming proof and one checksum are hashed during a prepared combined edit.
proc key(first: byte): StateKey =
  ## Fixed identities cover two long values, empty presence and authenticated absence at one complete root.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc limits(): LightSnapshotLimits =
  ## Both initial and replacement images exactly fill item/value/file allowances; one combined batch permits two keys.
  LightSnapshotLimits(bytes: ByteLimit(732), cache: LightCacheLimits(items: ElementLimit(3),
    writes: ElementLimit(2), valueBytes: ByteLimit(33),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc proof(trie: FullStateTrie, first: byte): LightStateProof =
  ## Only a complete trie produces transport; partial cache state never calculates root authority.
  LightStateProof(key: key(first), proof: trie.prove(key(first), limits().cache.proof).value)
proc prepare(root: StateRoot, proofs: openArray[LightStateProof],
    policy: LightSnapshotLimits): PreparedLightSnapshot =
  ## Full preparation supplies an independent canonical-output reference for every incremental combined edit.
  prepareLightSnapshot(default(StorageChainId), root, proofs, policy).value
proc cycle(initial: PreparedLightSnapshot, incoming: LightStateProof) =
  ## Private forgetting/admission prefixes retire together on success, later provider refusal and retry.
  resetHash(0)
  let next = initial.update([incoming], [key(0)]).value
  assert next.cache.len == 3 and next.cache.lookup(key(0)).error == LightCacheError.UnknownKey
  refuseAfter(3)
  let failed = initial.update([incoming], [key(0)])
  assert failed.error == LightSnapshotError.BackendFailure and calls() == 4
  assert initial.cache.lookup(key(0)).value.bytes == newSeq[byte](33)
  resetHash(0)
  assert initial.update([incoming], [key(0)]).value.cache.lookup(key(64)).value.bytes[0] == 7
proc prepared(trie: FullStateTrie) =
  ## Released final-set charges permit a swap that ordinary admission rejects, without exposing an evicted intermediate view.
  resetHash(0)
  let a = proof(trie, 0)
  let b = proof(trie, 64)
  let c = proof(trie, 128)
  let d = proof(trie, 255)
  let root = trie.commitment.root
  let initial = prepare(root, [a, c, d], limits())
  let expected = prepare(root, [d, b, c], limits())
  assert initial.byteLength == 732 and expected.byteLength == 732
  resetHash(1)
  assert initial.admit([b]).error == LightSnapshotError.LimitExceeded and calls() == 0
  resetHash(0)
  let next = initial.update([b], [key(0)]).value
  assert calls() == 5 and next.bytes == expected.bytes
  assert initial.cache.lookup(key(0)).value.bytes == newSeq[byte](33)
  assert next.cache.lookup(key(64)).value.bytes[0] == 7
  assert next.cache.lookup(key(0)).error == LightCacheError.UnknownKey
  assert next.cache.lookup(key(128)).value.kind == StateLookupKind.Present
  assert next.cache.lookup(key(255)).value.kind == StateLookupKind.Absent
  resetHash(1)
  let conflict = initial.update([b], [key(64)])
  assert conflict.proofError == LightCacheError.DuplicateKey
  assert initial.update([a, b], [key(255)]).error == LightSnapshotError.LimitExceeded
  assert initial.update([a, a], []).proofError == LightCacheError.DuplicateKey
  assert initial.update([], [key(0), key(0)]).proofError == LightCacheError.DuplicateKey
  assert initial.update([], []).value.bytes == initial.bytes
  assert initial.update([], [key(64)]).value.bytes == initial.bytes
  assert calls() == 0
  resetHash(0)
  var readOnly = limits()
  readOnly.cache.writes = ElementLimit(0)
  let frozen = prepare(root, [a, c, d], readOnly)
  resetHash(1)
  assert frozen.update([b], [key(0)]).error == LightSnapshotError.LimitExceeded and calls() == 0
  resetHash(0)
  var tight = limits()
  tight.bytes = ByteLimit(828)
  tight.cache.items = ElementLimit(4)
  tight.cache.valueBytes = ByteLimit(66)
  let bounded = prepare(root, [a, c], tight)
  resetHash(1)
  assert bounded.update([b], [key(63)]).error == LightSnapshotError.LimitExceeded and calls() == 0
  resetHash(0)
  tight.bytes = ByteLimit(829)
  let exact = prepare(root, [a, c], tight)
  assert exact.update([b], [key(63)]).value.byteLength == 829
  var invalid = b
  invalid.proof.value = newSeq[byte](33)
  let failed = initial.update([invalid], [key(0)])
  assert failed.proofError == LightCacheError.ValueMismatch
  assert initial.bytes == prepare(root, [a, c, d], limits()).bytes
  for successful in 0..<5:
    refuseAfter(cint(successful))
    assert initial.update([b], [key(0)]).error == LightSnapshotError.BackendFailure
    assert calls() == cint(successful+1)
  resetHash(0)
  assert default(PreparedLightSnapshot).update([b], [key(0)]).error ==
      LightSnapshotError.Uninitialized
  # A flat known-key model checks complete canonical output after mixed, add-only and forget-only transactions.
  let evidence = [a, b, c, d]
  var known = [true, false, true, true]
  var current = initial
  for step in 0..<32:
    case step mod 4
    of 0:
      current = current.update([b], [key(0)]).value
      known[0] = false
      known[1] = true
    of 1:
      current = current.update([], [key(255)]).value
      known[3] = false
    of 2:
      current = current.update([d], []).value
      known[3] = true
    else:
      current = current.update([a], [key(64)]).value
      known[0] = true
      known[1] = false
    var selected: seq[LightStateProof] = @[]
    for index in 0..<4:
      if known[index]: selected.add(evidence[index])
    assert current.bytes == prepare(root, selected, limits()).bytes
  for iteration in 0..<10: cycle(initial, b)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(initial, b)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_atomic_batches", 1000, before, after)
proc files(trie: FullStateTrie) {.raises.} =
  ## One real selection replaces evidence at capacity; preparation failures do no IO and uncertain writes require reopen.
  resetHash(0)
  resetIo()
  let a = proof(trie, 0)
  let b = proof(trie, 64)
  let initial = prepare(trie.commitment.root, [a, proof(trie, 128), proof(trie, 255)], limits())
  let config = LightFileConfig(root: trie.commitment.root, limits: limits())
  let path = "storage-light-atomic-batches"
  var owner = default(LightFileCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert owner.update([b], [key(0)]).error == FileError.Uninitialized
  assert initializeLightFileCache(owner, path, config, initial).error == FileError.None
  let held = owner.snapshot.value
  resetIo()
  assert owner.update([b], [key(64)]).error == FileError.InvalidFrame
  assert ioCalls(writeIo) == 0 and ioCalls(syncIo) == 0 and ioCalls(renameIo) == 0
  assert owner.update([b], [key(0)]).value == StorageDurability.FileAndDirectorySynced
  assert ioCalls(writeIo) == 1 and ioCalls(syncIo) == 2 and ioCalls(renameIo) == 1
  assert owner.snapshot.value.lookup(key(0)).error == LightCacheError.UnknownKey
  assert held.lookup(key(0)).value.bytes[0] == 0
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  let replacement = owner.snapshot.value
  let selected = readFile(path & "/CURRENT")
  resetHash(1)
  assert owner.update([a], [key(64)]).error == FileError.BackendFailure
  resetHash(0)
  assert readFile(path & "/CURRENT") == selected
  assert owner.snapshot.value.lookup(key(64)).value.bytes[0] == 7
  resetIo()
  armIo(writeIo, 0, 1, failedIo)
  assert owner.update([a], [key(64)]).error == FileError.IoFailure
  assert pendingIo() == 0
  resetIo()
  assert owner.snapshot.error == FileError.RecoveryRequired
  assert owner.update([a], [key(64)]).error == FileError.RecoveryRequired
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  assert owner.snapshot.value.lookup(key(64)).value.bytes[0] == 7
  assert owner.discardPending == FileError.None
  armIo(syncIo, 1, 1, failedIo)
  assert owner.update([a], [key(64)]).error == FileError.PublishedUnsynced
  assert pendingIo() == 0
  resetIo()
  assert owner.snapshot.error == FileError.RecoveryRequired
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  assert owner.snapshot.value.lookup(key(0)).value.bytes[0] == 0
  assert owner.snapshot.value.lookup(key(64)).error == LightCacheError.UnknownKey
  assert replacement.lookup(key(64)).value.bytes[0] == 7 and held.lookup(key(0)).value.bytes[0] == 0
  assert owner.close == FileError.None
  var currentPath = path & "/CURRENT"
  var lock = path & "/LOCK"
  var directory = path
  assert posix.unlink(currentPath.toCString()) == 0
  assert posix.unlink(lock.toCString()) == 0
  assert posix.rmdir(directory.toCString()) == 0
proc main() {.raises.} =
  ## Independent complete-map hashing fixes authority while cache ceilings intentionally hold only one long value.
  resetHash(0)
  var other = newSeq[byte](33)
  for index in 0..<33: other[index] = 7
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)),
    StateEntry(key: key(64), value: other), StateEntry(key: key(128))]
  let bounds = StateTrieLimits(items: ElementLimit(3), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(66))
  let expected = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](expected)
  prepared(trie)
  files(trie)
try:
  main()
except:
  quit(2)
echo "PASS storage light atomic batches: exact-capacity evidence replacement, one publication and atomic recovery"
