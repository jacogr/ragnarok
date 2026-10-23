# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Incremental evidence edits preserve canonical bytes, exact quotas, immutable owners and durable reopen authority.
# @@Verification={"arc":"storage_light_updates_arc_release"}
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[arc_evidence, storage_io]
import ../../../src/storage/[light_snapshot, light_file_cache, light_state_cache, state_proof,
  full_state_trie, database_identity, file_errors, durability]
import ../../../src/codec/[bounded, state_layout, state_trie]
import ../../../src/crypto/primitives
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Shape/duplicate/quota refusal must precede any actual hash call.
proc refuseAfter(successes: cint) {.importc: "ro_blake_after", cdecl.}
  ## Each incoming proof and final checksum can independently fail after earlier private work.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Retained proof bytes must not be hashed again during an edit.
proc key(first: byte): StateKey =
  ## Fixed distinct identities select present-long, present-empty and independent absent queries.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc policy(): LightSnapshotLimits =
  ## Three two-node proofs and one33-byte value exactly fill the item/value/file limits.
  LightSnapshotLimits(bytes: ByteLimit(668), cache: LightCacheLimits(items: ElementLimit(3),
    writes: ElementLimit(2), valueBytes: ByteLimit(33),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc proof(trie: FullStateTrie, first: byte): LightStateProof =
  ## Complete-trie producers provide transport; a separate flat-map root determines expected authority.
  LightStateProof(key: key(first), proof: trie.prove(key(first), policy().cache.proof).value)
proc cycle(first: PreparedLightSnapshot, additions: openArray[LightStateProof]) =
  ## Every successful edit, private partial verification failure and recovery must release ARC ownership.
  resetHash(0)
  let next = first.admit(additions).value
  assert next.cache.len == 3
  let trimmed = next.forget([key(128)]).value
  assert trimmed.cache.len == 2
  refuseAfter(2)
  let failed = first.admit(additions)
  assert failed.error == LightSnapshotError.BackendFailure and calls() == 3
  resetHash(0)
  assert first.admit(additions).value.cache.len == 3
proc edits(trie: FullStateTrie, root: StateRoot) =
  ## Canonical incremental output equals independent full preparation, without rehashing old evidence.
  resetHash(0)
  let a = proof(trie, 0)
  let b = proof(trie, 128)
  let c = proof(trie, 255)
  let d = proof(trie, 64)
  let first = prepareLightSnapshot(default(StorageChainId), root, [a], policy()).value
  let expected = prepareLightSnapshot(default(StorageChainId), root, [c, a, b], policy()).value
  assert expected.byteLength == 668
  resetHash(0)
  let next = first.admit([c, b]).value
  assert calls() == 5 # Four new path nodes and one checksum; no old long-value hash is attempted.
  assert next.bytes == expected.bytes and first.cache.len == 1 and next.cache.len == 3
  assert next.cache.lookup(key(128)).value.kind == StateLookupKind.Present
  assert next.cache.lookup(key(128)).value.bytes.len == 0
  assert next.cache.lookup(key(255)).value.kind == StateLookupKind.Absent
  resetHash(0)
  let replaced = next.admit([a]).value
  assert calls() == 4 and replaced.bytes == next.bytes # Replacement releases all old item/value/byte charges first.
  let retained = next.cache
  let expectedTrim = prepareLightSnapshot(default(StorageChainId), root, [a, c], policy()).value
  resetHash(0)
  let trimmed = next.forget([key(128)]).value
  assert calls() == 1 and trimmed.bytes == expectedTrim.bytes
  assert trimmed.cache.lookup(key(128)).error == LightCacheError.UnknownKey
  assert retained.lookup(key(128)).value.kind == StateLookupKind.Present
  resetHash(1)
  assert next.admit([]).value.bytes == next.bytes
  assert next.forget([]).value.bytes == next.bytes
  assert next.forget([key(64)]).value.bytes == next.bytes
  assert calls() == 0
  assert next.admit([d]).error == LightSnapshotError.LimitExceeded
  let duplicate = first.admit([b, b])
  assert duplicate.error == LightSnapshotError.ProofFailure
  assert duplicate.proofError == LightCacheError.DuplicateKey
  let duplicateForget = first.forget([key(128), key(128)])
  assert duplicateForget.proofError == LightCacheError.DuplicateKey
  assert first.admit([a, b, c]).error == LightSnapshotError.LimitExceeded
  assert first.forget([key(0), key(128), key(255)]).error == LightSnapshotError.LimitExceeded
  assert calls() == 0
  resetHash(0)
  var tight = policy()
  tight.bytes = ByteLimit(667)
  let bounded = prepareLightSnapshot(default(StorageChainId), root, [a], tight).value
  resetHash(1)
  assert bounded.admit([b, c]).error == LightSnapshotError.LimitExceeded and calls() == 0
  resetHash(0)
  tight = policy()
  tight.cache.writes = ElementLimit(0)
  let readOnly = prepareLightSnapshot(default(StorageChainId), root, [a], tight).value
  resetHash(1)
  assert readOnly.admit([b]).error == LightSnapshotError.LimitExceeded
  assert readOnly.forget([key(0)]).error == LightSnapshotError.LimitExceeded
  assert calls() == 0
  resetHash(0)
  var over = b
  over.proof.nodes = newSeq[EncodedStateNode](250)
  resetHash(1)
  assert first.admit([over]).error == LightSnapshotError.LimitExceeded and calls() == 0
  resetHash(0)
  over = a
  over.proof.value = newSeq[byte](34)
  resetHash(1)
  assert first.admit([over]).error == LightSnapshotError.LimitExceeded and calls() == 0
  resetHash(0)
  over = a
  over.proof.value = newSeq[byte](33)
  over.proof.value[0] = 1
  let falseValue = first.admit([over])
  assert falseValue.error == LightSnapshotError.ProofFailure
  assert falseValue.proofError == LightCacheError.ValueMismatch
  assert first.bytes == prepareLightSnapshot(default(StorageChainId), root, [a], policy()).value.bytes
  for successful in 0..<5:
    refuseAfter(cint(successful))
    assert first.admit([c, b]).error == LightSnapshotError.BackendFailure
    assert calls() == cint(successful+1)
  resetHash(1)
  assert next.forget([key(128)]).error == LightSnapshotError.BackendFailure and calls() == 1
  resetHash(0)
  var encoded = next.bytes
  let restored = restoreLightSnapshot(encoded, default(StorageChainId), root, policy()).value
  encoded[0] = 0
  assert restored.bytes == next.bytes
  assert restored.forget([key(128)]).value.bytes == trimmed.bytes
  assert restoreLightSnapshot(encoded, default(StorageChainId), root, policy()).error ==
      LightSnapshotError.InvalidFormat
  assert default(PreparedLightSnapshot).admit([a]).error == LightSnapshotError.Uninitialized
  assert default(PreparedLightSnapshot).forget([key(0)]).error == LightSnapshotError.Uninitialized
  for iteration in 0..<10: cycle(first, [c, b]) # Warm exactly the same successful and partially failed paths.
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(first, [c, b])
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_updates", 1000, before, after)
proc model(trie: FullStateTrie, root: StateRoot) =
  ## A tiny independent known-key model checks every merge position, empty set and complete removal across48 edits.
  resetHash(0)
  let evidence = [proof(trie, 0), proof(trie, 128), proof(trie, 255)]
  var known = default(array[3, bool])
  var current = prepareLightSnapshot(default(StorageChainId), root, [], policy()).value
  for step in 0..<48:
    let slot = (step*7+step div 4) mod 3
    if step mod 4 < 2:
      current = current.admit([evidence[slot]]).value
      known[slot] = true
    else:
      current = current.forget([evidence[slot].key]).value
      known[slot] = false
    var expected: seq[LightStateProof] = @[]
    for index in 0..<3:
      if known[index]: expected.add(evidence[index]) # The flat model has no encoded-cursor or sorted-merge logic.
    let canonical = prepareLightSnapshot(default(StorageChainId), root, expected, policy()).value
    assert current.bytes == canonical.bytes and current.cache.len == expected.len
    for index in 0..<3:
      let found = current.cache.lookup(evidence[index].key)
      if known[index]: assert found.error == LightCacheError.None
      else: assert found.error == LightCacheError.UnknownKey
  # A rechecksummed false raw value reaches the restore wrapper's selected proof-failure arm, never a prepared payload.
  var corrupt = prepareLightSnapshot(default(StorageChainId), root, [evidence[0]], policy()).value.bytes
  corrupt[96+41+128] = 1
  let digest = array[32, byte](blake2b256(corrupt.toOpenArray(0, corrupt.len-33)).value)
  for index in 0..<32: corrupt[corrupt.len-32+index] = digest[index]
  let failed = restoreLightSnapshot(corrupt, default(StorageChainId), root, policy())
  assert failed.error == LightSnapshotError.ProofFailure
  assert failed.proofError == LightCacheError.ValueMismatch
proc files(trie: FullStateTrie, root: StateRoot) {.raises.} =
  ## Opening retains proof bytes for later edits; unsuccessful preparation and uncertain publication have distinct lifetimes.
  resetHash(0)
  resetIo()
  let a = proof(trie, 0)
  let b = proof(trie, 128)
  let c = proof(trie, 255)
  let first = prepareLightSnapshot(default(StorageChainId), root, [a], policy()).value
  let config = LightFileConfig(root: root, limits: policy())
  let path = "storage-light-proof-updates"
  var owner = default(LightFileCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
  assert owner.admit([a]).error == FileError.Uninitialized
  assert owner.forget([key(0)]).error == FileError.Uninitialized
  assert initializeLightFileCache(owner, path, config, first).value ==
      StorageDurability.FileAndDirectorySynced
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  let held = owner.snapshot.value
  let original = readFile(path & "/CURRENT")
  assert owner.admit([b, b]).error == FileError.InvalidFrame
  resetHash(1)
  assert owner.admit([b]).error == FileError.BackendFailure
  resetHash(0)
  assert owner.snapshot.value.len == 1 and readFile(path & "/CURRENT") == original
  assert owner.admit([c, b]).value == StorageDurability.FileAndDirectorySynced
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  assert owner.snapshot.value.len == 3 and held.len == 1
  assert owner.admit([a]).error == FileError.None
  armIo(syncIo, 1, 1, failedIo)
  assert owner.forget([key(128)]).error == FileError.PublishedUnsynced
  assert pendingIo() == 0
  resetIo()
  assert owner.snapshot.error == FileError.RecoveryRequired
  assert owner.admit([b]).error == FileError.RecoveryRequired
  assert owner.forget([key(0)]).error == FileError.RecoveryRequired
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  assert owner.snapshot.value.len == 2
  assert owner.snapshot.value.lookup(key(128)).error == LightCacheError.UnknownKey
  assert owner.admit([b]).value == StorageDurability.FileAndDirectorySynced
  assert owner.forget([key(0), key(255)]).error == FileError.None
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, config) == FileError.None
  assert owner.snapshot.value.len == 1
  assert owner.snapshot.value.lookup(key(128)).value.kind == StateLookupKind.Present
  assert owner.close == FileError.None and held.lookup(key(0)).value.bytes.len == 33
  var current = path & "/CURRENT"
  var lock = path & "/LOCK"
  var directory = path
  assert posix.unlink(current.toCString()) == 0
  assert posix.unlink(lock.toCString()) == 0
  assert posix.rmdir(directory.toCString()) == 0
proc main() {.raises.} =
  ## The independent flat map establishes the complete root before any partial-cache operation.
  resetHash(0)
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)), StateEntry(key: key(128))]
  let bounds = StateTrieLimits(items: ElementLimit(3), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(33))
  let root = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  edits(trie, root)
  model(trie, root)
  files(trie, root)
try:
  main()
except:
  quit(2)
echo "PASS storage light updates: canonical evidence merge, exact quotas, incoming-only hashes and durable edits"
