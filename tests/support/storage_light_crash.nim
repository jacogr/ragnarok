# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real light-file process death witnesses complete old/new selection, stable leases and explicit forensic cleanup.
import std/[assertions, syncio]
import std/posix/posix
import ./[storage_io, storage_crash]
import ../../src/storage/light/[snapshot as light_snapshot, file_cache as light_file_cache,
    state_cache as light_state_cache]
import ../../src/storage/state_proof
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/database_identity
import ../../src/storage/file/errors as file_errors
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
proc existsNative(path: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Test-only presence checks never establish authority for the production held-directory reader.
proc exists(path: string): bool =
  ## Preserve exact namespace observations without scanning or choosing alternate selected files.
  var name = path
  existsNative(name.toCString(), 0) == 0
proc key(first: byte): StateKey =
  ## Independent fixture branches distinguish a removed present value and newly authenticated absence.
  var raw = default(array[31, byte])
  raw[0] = first
  StateKey(raw)
proc policy(): LightSnapshotLimits =
  ## One combined batch changes two identities while file/proof/value ceilings stay explicit.
  LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(items: ElementLimit(3),
    writes: ElementLimit(2), valueBytes: ByteLimit(33),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))))
proc text(bytes: openArray[byte]): string =
  ## Copy independently prepared canonical bytes for exact selected/staged prefix comparison.
  result = ""
  for octet in bytes: result.add(char(octet))
proc lightPublicationCrash*(operation, skip: cint, shortWrites = false): uint64 {.raises.} =
  ## Every boundary follows real successful SDK IO; parent contention precedes exact-child kill/reap and strict reopen.
  resetIo()
  let entries = [StateEntry(key: key(0), value: newSeq[byte](33)), StateEntry(key: key(128))]
  let bounds = StateTrieLimits(items: ElementLimit(2), nodes: TrieNodeLimit(1000),
    perValue: ByteLimit(33), totalValueBytes: ByteLimit(33))
  let root = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](root)
  let a = LightStateProof(key: key(0), proof: trie.prove(key(0), policy().cache.proof).value)
  let b = LightStateProof(key: key(128), proof: trie.prove(key(128), policy().cache.proof).value)
  let absent = LightStateProof(key: key(255), proof: trie.prove(key(255), policy().cache.proof).value)
  let original = prepareLightSnapshot(default(StorageChainId), root, [a, b], policy()).value
  let replacement = prepareLightSnapshot(default(StorageChainId), root, [b, absent], policy()).value
  let oldBytes = text(original.encodedBytes)
  let newBytes = text(replacement.encodedBytes)
  let config = LightFileConfig(root: root, limits: policy())
  let path = "light-publication-crash-" & $operation & "-" & $skip & "-" & $shortWrites & "-" &
      $int(storageProcessId())
  var file = default(LightFileCache)
  var contender = default(LightFileCache)
  defer:
    abortCrash()
    resetIo()
    if contender.opened: discard contender.close
    if file.opened: discard file.close
  assert initializeLightFileCache(file, path, config, original).error == FileError.None
  let retained = file.snapshot.value
  assert file.close == FileError.None
  writeFile(path & "/KEEP", "unselected forensic sentinel")
  resetIo()
  let child = forkCrash(operation, skip)
  assert child >= 0
  if child == 0:
    # Setup/admission is excluded from the observed publication boundary; successful exit is an explicit control only.
    if openLightFileCache(file, path, config) != FileError.None: exitCrash(81)
    if shortWrites: limitWrites(64)
    if startCrash() != 0: exitCrash(82)
    let changed = file.update([absent], [key(0)])
    if changed.error != FileError.None: exitCrash(83)
    exitCrash(0)
  if skip != 4096:
    # The stopped child still owns LOCK; a separate parent descriptor cannot steal it before retirement.
    assert waitCrash() == crashStopped
    assert openLightFileCache(contender, path, config) == FileError.Busy
    assert not contender.opened
  let receipt = finishCrash()
  result = crashCount()
  if skip == 4096: assert receipt == crashCompleted and result > 0 and result < 4096
  else: assert receipt == crashKilled and result == uint64(skip)+1
  resetIo()
  let selected = readFile(path & "/CURRENT")
  let selectedOld = selected == oldBytes
  assert selectedOld or selected == newBytes
  if skip == 4096 or operation == renameIo or (operation == syncIo and skip == 1):
    assert not selectedOld # Rename and directory sync follow the atomic selection boundary.
  else: assert selectedOld # Write, staged-file sync and staged close cannot select their candidate.
  let pending = path & "/CURRENT.next"
  let staged = exists(pending)
  let stagedBytes = if staged: readFile(pending) else: ""
  assert staged == selectedOld
  if staged:
    # Every observed successful short write leaves exactly its authored prefix, including the final complete chunk.
    let extent = if shortWrites and operation == writeIo: min(newBytes.len, int(
        result)*64) else: newBytes.len
    assert stagedBytes.len == extent
    for index in 0..<extent: assert stagedBytes[index] == newBytes[index]
  assert openLightFileCache(file, path, config) == FileError.None
  let current = file.preparedSnapshot.value
  assert text(current.encodedBytes) == selected
  assert current.cache.lookup(key(128)).value.kind == StateLookupKind.Present
  if selectedOld:
    assert current.cache.lookup(key(0)).value.bytes.len == 33
    assert current.cache.lookup(key(255)).error == LightCacheError.UnknownKey
  else:
    assert current.cache.lookup(key(0)).error == LightCacheError.UnknownKey
    assert current.cache.lookup(key(255)).value.kind == StateLookupKind.Absent
  assert readFile(path & "/CURRENT") == selected and exists(pending) == staged
  if staged: assert readFile(pending) == stagedBytes
  assert ioCalls(writeIo) == 0 and ioCalls(renameIo) == 0
  assert file.discardPending == FileError.None
  assert not exists(pending) and readFile(path & "/CURRENT") == selected
  assert readFile(path & "/KEEP") == "unselected forensic sentinel"
  assert file.publish(replacement).error == FileError.None
  assert file.close == FileError.None
  assert openLightFileCache(file, path, config) == FileError.None
  assert text(file.preparedSnapshot.value.encodedBytes) == newBytes
  assert file.close == FileError.None
  assert retained.lookup(key(0)).value.bytes.len == 33
  assert retained.lookup(key(255)).error == LightCacheError.UnknownKey
  for name in ["CURRENT", "LOCK", "KEEP"]:
    # Exact fixture retirement follows all descriptor/child ownership checks; no generic directory deletion is used.
    var filePath = path & "/" & name
    assert posix.unlink(filePath.toCString()) == 0
  var directory = path
  assert posix.rmdir(directory.toCString()) == 0
