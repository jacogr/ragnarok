# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real light-file leases preserve root-bound evidence, atomic selection, explicit uncertainty and immutable readers.
# @@Verification={"arc":"storage_light_file_cache_arc_release"}
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/testing_arc_evidence
import ../../support/storage_io
import ../../../src/storage/light_file_cache as storage_light_file_cache
import ../../../src/storage/light_snapshot as storage_light_snapshot
import ../../../src/storage/light_state_cache as storage_light_state_cache
import ../../../src/storage/state_proof as storage_state_proof
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/storage/durability as storage_durability
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/crypto/primitives as crypto_primitives
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Real provider refusal must release an acquired directory lease on unsuccessful reopen.
proc renamePath(source, destination: cstring): cint {.importc: "rename", cdecl,
    header: "<stdio.h>".}
  ## Namespace relocation witnesses descriptor-relative publication without changing production IO.
proc key(first: byte): StateKey =
  ## Two query identities suffice to distinguish a retained reader from its replacement.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc config(root: StateRoot): LightFileConfig =
  ## Complete restoration may contain more entries than the caller's ordinary zero-write allowance.
  LightFileConfig(root: root, limits: LightSnapshotLimits(bytes: ByteLimit(4096),
    cache: LightCacheLimits(items: ElementLimit(4), writes: ElementLimit(0), valueBytes: ByteLimit(64),
      proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(64)))))
proc prepared(config: LightFileConfig, trie: FullStateTrie, both: bool): PreparedLightSnapshot =
  ## Evidence always comes from a complete trie; partial light-cache contents never calculate a root.
  var entries = @[LightStateProof(key: key(0), proof: trie.prove(key(0),
      config.limits.cache.proof).value)]
  if both:
    entries.add(LightStateProof(key: key(128), proof: trie.prove(key(128),
        config.limits.cache.proof).value))
  prepareLightSnapshot(config.chain, config.root, entries, config.limits).value
proc text(bytes: openArray[byte]): string =
  ## Test fixture writes retain every binary octet, including zero-valued payloads.
  result = newString(bytes.len)
  for index, octet in bytes: result[index] = char(octet)
proc unlink(path: string) =
  ## Cleanup owns only exact test fixture names, never recursive or production-selected paths.
  var name = path
  assert posix.unlink(name.toCString()) == 0
proc remove(path: string) =
  ## Remove the retired selected file and persistent lock after all owners close.
  unlink(path & "/CURRENT")
  unlink(path & "/LOCK")
  var name = path
  assert posix.rmdir(name.toCString()) == 0
proc cycle(path: string, policy: LightFileConfig) =
  ## Each iteration must release native leases and all decoded proof/cache scratch.
  var owner = default(LightFileCache)
  assert openLightFileCache(owner, path, policy) == FileError.None
  assert owner.snapshot.value.len == 2
  assert owner.close == FileError.None
proc lifecycle(policy: LightFileConfig, first, second: PreparedLightSnapshot) {.raises.} =
  ## Root/chain/policy refusal precedes IO; only confirmed publication advances fresh immutable readers.
  let path = "storage-light-file-cache"
  var owner = default(LightFileCache)
  var other = default(LightFileCache)
  defer:
    resetIo()
    resetHash(0)
    if owner.opened: discard owner.close
    if other.opened: discard other.close
  assert owner.close == FileError.Uninitialized
  assert owner.snapshot.error == FileError.Uninitialized
  assert owner.publish(first).error == FileError.Uninitialized
  assert owner.discardPending == FileError.Uninitialized
  let absent = initializeLightFileCache(owner, path, policy, default(PreparedLightSnapshot))
  assert absent.error == FileError.Uninitialized and not owner.opened
  let initial = initializeLightFileCache(owner, path, policy, first)
  assert initial.value == StorageDurability.FileAndDirectorySynced
  assert openLightFileCache(other, path, policy) == FileError.Busy
  let repeated = initializeLightFileCache(other, path, policy, first)
  assert repeated.error == FileError.AlreadyExists
  let held = owner.snapshot.value
  assert held.len == 1 and held.lookup(key(0)).value.bytes == newSeq[byte](33)
  assert held.lookup(key(128)).error == LightCacheError.UnknownKey
  var wrong = policy
  wrong.limits.cache.writes = ElementLimit(1)
  let mismatched = prepareLightSnapshot(policy.chain, policy.root, [], wrong.limits).value
  assert owner.publish(mismatched).error == FileError.InvalidBatch
  var badChain = default(array[32, byte])
  badChain[0] = 1
  let foreign = prepareLightSnapshot(StorageChainId(badChain), policy.root, [], policy.limits).value
  assert owner.publish(foreign).error == FileError.WrongIdentity
  writeFile(path & "/CURRENT.next", "forensic")
  let selected = readFile(path & "/CURRENT")
  assert owner.publish(second).error == FileError.AlreadyExists
  assert readFile(path & "/CURRENT") == selected and owner.snapshot.value.len == 1
  assert owner.discardPending == FileError.None
  let updated = owner.publish(second)
  assert updated.value == StorageDurability.FileAndDirectorySynced
  assert owner.snapshot.value.len == 2 and held.len == 1
  assert owner.snapshot.value.lookup(key(128)).value.kind == StateLookupKind.Absent
  # Native moves must transfer exactly one authority and leave the source usable as a closed owner.
  var moved = move(owner)
  assert not owner.opened and moved.opened
  assert owner.snapshot.error == FileError.Uninitialized
  assert moved.close == FileError.None
  wrong = policy
  wrong.chain = StorageChainId(badChain)
  assert openLightFileCache(owner, path, wrong) == FileError.WrongIdentity
  wrong = policy
  wrong.root = StateRoot(badChain)
  assert openLightFileCache(owner, path, wrong) == FileError.WrongIdentity
  wrong = policy
  wrong.limits.bytes = ByteLimit(127)
  assert openLightFileCache(owner, path, wrong) == FileError.LimitExceeded
  resetHash(1)
  assert openLightFileCache(owner, path, policy) == FileError.BackendFailure
  resetHash(0)
  assert not owner.opened
  for iteration in 0..<10: cycle(path, policy) # Warm the exact reopen path before measuring ARC ownership.
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(path, policy)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_light_file_cache", 1000, before, after)
  assert held.lookup(key(0)).value.bytes.len == 33
  let good = readFile(path & "/CURRENT")
  let full = encodeManagedManifest(policy.chain, StorageSchema.FullStateV1, ManagedEpoch(1),
    RepositoryGeneration(1), policy.root, default(StorageChecksum), ByteLimit(4096)).value.bytes
  var fullBytes = newString(full.len)
  for index, octet in full: fullBytes[index] = char(octet)
  var falseProof = second.bytes
  falseProof[96+41+64] = 1 # First canonical query's long raw value no longer matches its stored leaf.
  let digest = array[32, byte](blake2b256(falseProof.toOpenArray(0, falseProof.len-33)).value)
  for index in 0..<32: falseProof[falseProof.len-32+index] = digest[index]
  var corrupt = good
  corrupt[corrupt.len-1] = char(ord(corrupt[corrupt.len-1]) xor 1)
  for malformed in [fullBytes, good & "suffix", good[0..<good.len-1], corrupt, text(falseProof)]:
    writeFile(path & "/CURRENT", malformed)
    assert openLightFileCache(owner, path, policy) == FileError.InvalidFrame
    assert not owner.opened
  writeFile(path & "/CURRENT", good)
  assert openLightFileCache(owner, path, policy) == FileError.None
  assert owner.close == FileError.None
  remove(path)
proc namespace(policy: LightFileConfig, first, second: PreparedLightSnapshot) {.raises.} =
  ## Refuse symlink cleanup and revalidate selected bytes before removing forensic staging evidence.
  var path = "storage-light-file-namespace"
  var owner = default(LightFileCache)
  defer:
    if owner.opened: discard owner.close
  assert initializeLightFileCache(owner, path, policy, first).error == FileError.None
  var moved = path & "-moved"
  assert renamePath(path.toCString(), moved.toCString()) == 0
  assert owner.publish(second).error == FileError.None
  assert owner.close == FileError.None
  assert renamePath(moved.toCString(), path.toCString()) == 0
  assert openLightFileCache(owner, path, policy) == FileError.None
  var pending = path & "/CURRENT.next"
  var target = "CURRENT"
  assert posix.symlink(target.toCString(), pending.toCString()) == 0
  assert owner.publish(first).error == FileError.AlreadyExists
  assert owner.discardPending == FileError.IoFailure
  assert owner.snapshot.error == FileError.RecoveryRequired
  assert owner.close == FileError.None
  unlink(pending)
  assert openLightFileCache(owner, path, policy) == FileError.None
  writeFile(pending, "forensic")
  let good = readFile(path & "/CURRENT")
  writeFile(path & "/CURRENT", text(first.bytes))
  assert owner.discardPending == FileError.RecoveryMismatch
  assert readFile(pending) == "forensic"
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, policy) == FileError.None
  assert owner.discardPending == FileError.None
  assert owner.publish(second).error == FileError.None
  writeFile(pending, "forensic")
  writeFile(path & "/CURRENT", "corrupt")
  assert owner.discardPending == FileError.InvalidFrame
  assert readFile(pending) == "forensic"
  assert owner.snapshot.error == FileError.RecoveryRequired
  assert owner.close == FileError.None
  writeFile(path & "/CURRENT", good)
  assert openLightFileCache(owner, path, policy) == FileError.None
  assert owner.discardPending == FileError.None
  assert owner.close == FileError.None
  remove(path)
proc fault(policy: LightFileConfig, first, second: PreparedLightSnapshot, operation, skip: cint,
    uncertain: bool, number: int) {.raises.} =
  ## Test observers refuse actual syscall boundaries; restart selection is checked after every consumed fault.
  resetIo()
  let path = "storage-light-file-fault-" & $number
  var owner = default(LightFileCache)
  defer:
    resetIo()
    if owner.opened: discard owner.close
  assert initializeLightFileCache(owner, path, policy, first).error == FileError.None
  let held = owner.snapshot.value
  armIo(operation, skip, 1, failedIo)
  let outcome = owner.publish(second)
  assert pendingIo() == 0
  resetIo()
  assert outcome.error == (if uncertain: FileError.PublishedUnsynced else: FileError.IoFailure)
  assert owner.snapshot.error == FileError.RecoveryRequired
  assert owner.publish(first).error == FileError.RecoveryRequired
  assert owner.discardPending == FileError.RecoveryRequired
  assert held.len == 1
  assert owner.close == FileError.None
  assert openLightFileCache(owner, path, policy) == FileError.None
  assert owner.snapshot.value.len == (if uncertain: 2 else: 1)
  assert owner.discardPending == FileError.None
  assert owner.publish(second).value == StorageDurability.FileAndDirectorySynced
  assert owner.close == FileError.None
  remove(path)
proc main() {.raises.} =
  ## A complete single-leaf trie supplies independently selected evidence for present-long and absent queries.
  resetIo()
  resetHash(0)
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33))]
  let bounds = StateTrieLimits(items: ElementLimit(4), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(64), totalValueBytes: ByteLimit(64))
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  let policy = config(stateTrieRoot(entries, bounds).value.root)
  let first = prepared(policy, trie, false)
  let second = prepared(policy, trie, true)
  lifecycle(policy, first, second)
  namespace(policy, first, second)
  fault(policy, first, second, writeIo, 0, false, 0)
  fault(policy, first, second, syncIo, 0, false, 1)
  fault(policy, first, second, renameIo, 0, false, 2)
  fault(policy, first, second, syncIo, 1, true, 3)
try:
  main()
except:
  quit(2)
echo "PASS storage light files: locked root-bound reopen, atomic receipts, immutable readers and IO recovery"
