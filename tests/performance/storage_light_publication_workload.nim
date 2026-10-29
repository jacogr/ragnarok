# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Separate bounded fixture producers from fresh light-file reopen consumers and exact ARC/hash witnesses.
import std/[assertions, cmdline, syncio, monotimes]
import std/posix/posix
import ../support/storage_io
import ../../src/storage/managed/[io as managed_io, manifest as managed_manifest]
import ../../src/storage/light/journal/[cache as light_journal_cache,
    replay as light_journal_replay]
import ../../src/storage/light/delta as light_delta
import ../../src/storage/light/[file_cache as light_file_cache, snapshot as light_snapshot,
    state_cache as light_state_cache]
import ../../src/storage/full/state_trie as full_state_trie
import ../../src/storage/[state_proof, database_identity]
import ../../src/storage/file/errors as file_errors
import ../../src/storage/durability
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## A clean observer counts only actual reopen proof/checksum attempts, excluding fixture production.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Every consumer must authenticate exactly the same complete evidence set.
const Count = 4096
proc key(index: int): StateKey =
  ## Leading big-endian two-byte ordinals create exactly17-node proof paths for these4096 entries.
  var raw = default(array[31, byte])
  raw[0] = byte(index shr 8)
  raw[1] = byte(index and 255)
  StateKey(raw)
proc policy(size: int): LightSnapshotLimits =
  ## The benchmark fixes all production limits; command arguments cannot widen the workload.
  LightSnapshotLimits(bytes: ByteLimit(16777216), cache: LightCacheLimits(items: ElementLimit(Count),
    writes: ElementLimit(1), valueBytes: ByteLimit(Count*size),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(size))))
proc hex(root: StateRoot): string =
  ## Serialize only the independently calculated expected root passed explicitly to later consumer processes.
  result = ""
  for octet in array[32, byte](root):
    result.add("0123456789abcdef"[int(octet shr 4)])
    result.add("0123456789abcdef"[int(octet and 15)])
proc root(text: string): StateRoot =
  ## Parse exactly64 trusted benchmark argument characters without accepting alternate encodings.
  assert text.len == 64
  var raw = default(array[32, byte])
  for index in 0..<32:
    var value = 0
    for offset in 0..<2:
      let character = text[index*2+offset]
      assert character in {'0'..'9', 'a'..'f'}
      let digit = if character <= '9': ord(character)-ord('0') else: ord(character)-ord('a')+10
      value = value*16+digit
    raw[index] = byte(value)
  StateRoot(raw)
proc produce(path: string, size: int) =
  ## Producer RSS is excluded from every consumer observation; flat-map hashing independently sets root authority.
  var entries = newSeq[StateEntry](Count)
  for index in 0..<Count:
    var value = newSeq[byte](size)
    for offset in 0..<size: value[offset] = byte((index+offset) and 255)
    entries[index] = StateEntry(key: key(index), value: value)
  let bounds = StateTrieLimits(items: ElementLimit(Count), nodes: TrieNodeLimit(100000),
    perValue: ByteLimit(size), totalValueBytes: ByteLimit(Count*size))
  let expected = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](expected)
  var proofs = newSeq[LightStateProof](Count)
  for index in 0..<Count:
    proofs[index] = LightStateProof(key: key(index), proof: trie.prove(key(index), policy(
        size).cache.proof).value)
    assert proofs[index].proof.nodes.len == 17
  let prepared = prepareLightSnapshot(default(StorageChainId), expected, proofs, policy(size)).value
  var file = default(LightFileCache)
  let config = LightFileConfig(root: expected, limits: policy(size))
  assert initializeLightFileCache(file, path, config, prepared).value ==
      StorageDurability.FileAndDirectorySynced
  assert file.close == FileError.None
  echo hex(expected), "\t", prepared.byteLength
type
  Observation = object ## Copied scalar checkpoints outlive all native/cache resources.
    hashes: cint
    opened, closed: int
proc observe(path: string, size: int, expected: StateRoot): Observation =
  ## Whole-child RSS includes reopen and lookup validation; ARC checkpoints describe only simultaneously live owners.
  var file = default(LightFileCache)
  resetHash(0)
  let config = LightFileConfig(root: expected, limits: policy(size))
  assert openLightFileCache(file, path, config) == FileError.None
  let hashes = calls()
  assert hashes == Count*18+1, "reopen hashes: " & $hashes
  let opened = getOccupiedMem()
  var view = file.snapshot.value
  assert view.len == Count and view.valueBytes == uint64(Count*size)
  for index in 0..<Count:
    let found = view.lookup(key(index)).value
    let value = found.bytes
    assert value.len == size and value[0] == byte(index and 255)
    assert value[size-1] == byte((index+size-1) and 255)
  assert file.close == FileError.None
  let closed = getOccupiedMem()
  assert view.lookup(key(Count-1)).value.bytes.len == size
  Observation(hashes: hashes, opened: opened, closed: closed)
proc consume(path: string, size: int, expected: StateRoot) =
  ## Sample final ARC retirement only after all extraction temporaries and result owners leave their scope.
  let baseline = getOccupiedMem()
  let measured = observe(path, size, expected)
  let released = getOccupiedMem()
  assert released == baseline, "ARC release: " & $baseline & " -> " & $released
  echo "reopen\t", size, "\t", measured.hashes, "\t", baseline, "\t", measured.opened, "\t",
      measured.closed, "\t", released
proc load(path: string, size: int, expected: StateRoot): PreparedLightSnapshot =
  ## The existing held-directory reader transfers one validated source image; proof production remains a separate process.
  var directory = default(ManagedDirectory)
  assert openManagedDirectory(directory, path) == FileError.None
  var loaded = readManagedFile(directory, ManagedFileKind.Current, ManagedEpoch(0), policy(size).bytes)
  assert loaded.error == FileError.None
  var encoded = loaded.takeValue
  resetHash(0)
  let restored = takeLightSnapshot(encoded, default(StorageChainId), expected, policy(size)).value
  assert calls() == Count*18+1
  assert directory.close == FileError.None
  restored
type
  PublishObservation = object ## Only copied scalar witnesses cross the resource scope boundary.
    writes, syncs, renames: uint64
    before, after: int
proc publishCycle(source, target: string, size: int, expected: StateRoot): PublishObservation =
  ## Repeated full-image publication performs identical writes/barriers/renames while all prepared/cache owners stay alive.
  let prepared = load(source, size, expected)
  let config = LightFileConfig(root: expected, limits: policy(size))
  var file = default(LightFileCache)
  resetIo()
  resetHash(0)
  assert initializeLightFileCache(file, target, config, prepared).value ==
      StorageDurability.FileAndDirectorySynced
  let retained = file.snapshot.value
  resetIo()
  let before = getOccupiedMem()
  for iteration in 0..<8:
    assert file.publish(prepared).value == StorageDurability.FileAndDirectorySynced
  let after = getOccupiedMem()
  let writes = ioCalls(writeIo)
  let syncs = ioCalls(syncIo)
  let renames = ioCalls(renameIo)
  assert before == after and writes == 8 and syncs == 16 and renames == 8
  assert calls() == 0
  assert file.close == FileError.None
  assert retained.len == Count and retained.valueBytes == uint64(Count*size)
  for index in 0..<Count:
    # Immutable readers preserve every independently specified value after all actual file publications and close.
    let value = retained.lookup(key(index)).value.bytes
    assert value.len == size and value[0] == byte(index and 255)
    assert value[size-1] == byte((index+size-1) and 255)
  assert calls() == 0
  PublishObservation(writes: writes, syncs: syncs, renames: renames, before: before, after: after)
proc publish(source, target: string, size: int, expected: StateRoot) =
  ## Observe final ARC release only after all result and reader temporaries leave scope, the parent observer validates selected file bytes and removes exact owned fixture names.
  let baseline = getOccupiedMem()
  let observed = publishCycle(source, target, size, expected)
  let released = getOccupiedMem()
  assert released == baseline, "publication ARC release: " & $baseline & " -> " & $released
  echo "publication\t", size, "\t", observed.writes, "\t", observed.syncs, "\t", observed.renames,
      "\t", observed.before, "\t", observed.after
type
  ChurnObservation = object ## Scalar witnesses separate durable update work, strict reopen and retained ownership.
    imageBytes, writtenBytes, writes, syncs, renames: uint64
    updateHashes, reopenHashes: cint
    updateNs, reopenNs: int64
    before, after: int
proc churnCycle(source, target: string, size: int, expected: StateRoot): ChurnObservation =
  ## Eight single-key forget/admit pairs change only knowledge at one complete root and perform real durable publications.
  let prepared = load(source, size, expected)
  let proof = LightStateProof(key: key(0), proof: prepared.prove(key(0), LightProofReadLimits(
    entries: ElementLimit(1), proof: policy(size).cache.proof)).value)
  let config = LightFileConfig(root: expected, limits: policy(size))
  var file = default(LightFileCache)
  assert initializeLightFileCache(file, target, config, prepared).value ==
      StorageDurability.FileAndDirectorySynced
  let retained = file.snapshot.value
  let imageBytes = uint64(prepared.byteLength)
  let omittedBytes = imageBytes-uint64(41+17*64+size)
  resetIo()
  resetHash(0)
  let before = getOccupiedMem()
  var written = 0'u64
  let started = getMonoTime().ticks
  for cycle in 0..<8:
    # Each successful one-write replacement supplies its exact complete encoded extent, not physical device traffic.
    assert file.forget([key(0)]).value == StorageDurability.FileAndDirectorySynced
    assert file.snapshot.value.lookup(key(0)).error == LightCacheError.UnknownKey
    assert uint64(file.preparedSnapshot.value.byteLength) == omittedBytes
    written += omittedBytes
    assert file.admit([proof]).value == StorageDurability.FileAndDirectorySynced
    assert uint64(file.preparedSnapshot.value.byteLength) == imageBytes
    written += imageBytes
  let elapsed = getMonoTime().ticks-started
  let after = getOccupiedMem()
  let writes = ioCalls(writeIo)
  let syncs = ioCalls(syncIo)
  let renames = ioCalls(renameIo)
  let hashes = calls()
  assert writes == 16 and syncs == 32 and renames == 16 and hashes == 160
  assert written == 8*(imageBytes+omittedBytes) and elapsed >= 0
  assert file.close == FileError.None
  resetHash(0)
  let reopenStarted = getMonoTime().ticks
  assert openLightFileCache(file, target, config) == FileError.None
  let reopenElapsed = getMonoTime().ticks-reopenStarted
  let reopenHashes = calls()
  assert reopenHashes == Count*18+1 and reopenElapsed >= 0
  let final = file.preparedSnapshot.value
  assert final.encodedBytes == prepared.encodedBytes
  for index in 0..<Count:
    # Independent fixture bytes and a retained pre-edit reader survive every publication and strict reopen.
    let value = file.snapshot.value.lookup(key(index)).value.bytes
    assert value.len == size and value[0] == byte(index and 255)
    assert value[size-1] == byte((index+size-1) and 255)
  assert retained.len == Count and retained.lookup(key(0)).value.bytes.len == size
  assert file.close == FileError.None
  ChurnObservation(imageBytes: imageBytes, writtenBytes: written, writes: writes, syncs: syncs,
    renames: renames, updateHashes: hashes, reopenHashes: reopenHashes, updateNs: elapsed,
    reopenNs: reopenElapsed, before: before, after: after)
proc journalCycle(source, target: string, size: int, expected: StateRoot): ChurnObservation =
  ## Match the full-image workload exactly while sparse frames preserve every actual update and strict-reopen witness.
  let prepared = load(source, size, expected)
  let proof = LightStateProof(key: key(0), proof: prepared.prove(key(0), LightProofReadLimits(
    entries: ElementLimit(1), proof: policy(size).cache.proof)).value)
  let config = LightJournalConfig(root: expected, snapshot: policy(size),
      journal: LightReplayLimits(
    bytes: ByteLimit(131072), frames: ElementLimit(16), frame: LightDeltaLimits(
      items: ElementLimit(1), bytes: ByteLimit(8192))))
  var file = default(LightJournalCache)
  assert initializeLightJournalCache(file, target, config, prepared).value ==
      StorageDurability.FileAndDirectorySynced
  let retained = file.snapshot.value
  let imageBytes = uint64(prepared.byteLength)
  resetIo()
  resetHash(0)
  let before = getOccupiedMem()
  var written = 0'u64
  let started = getMonoTime().ticks
  for cycle in 0..<8:
    # Each successful append extends the actual held journal by one canonical frame; report completed application bytes.
    assert file.update([], [key(0)]).value == StorageDurability.FileAndDirectorySynced
    assert file.snapshot.value.lookup(key(0)).error == LightCacheError.UnknownKey
    assert file.update([proof], []).value == StorageDurability.FileAndDirectorySynced
    assert uint64(file.preparedSnapshot.value.byteLength) == imageBytes
    written = file.journalBytes.value-98
  let elapsed = getMonoTime().ticks-started
  let after = getOccupiedMem()
  let writes = ioCalls(writeIo)
  let syncs = ioCalls(syncIo)
  let renames = ioCalls(renameIo)
  let hashes = calls()
  assert writes == 16 and syncs == 16 and renames == 0 and hashes == 176
  assert written == uint64(8*(500+17*64+size)) and elapsed >= 0
  assert file.close == FileError.None
  resetHash(0)
  let reopenStarted = getMonoTime().ticks
  assert openLightJournalCache(file, target, config) == FileError.None
  let reopenElapsed = getMonoTime().ticks-reopenStarted
  let reopenHashes = calls()
  assert reopenHashes == Count*18+179 and reopenElapsed >= 0
  let final = file.preparedSnapshot.value
  assert final.encodedBytes == prepared.encodedBytes
  for index in 0..<Count:
    # Independent fixture bytes and a retained pre-edit reader survive every publication and strict reopen.
    let value = file.snapshot.value.lookup(key(index)).value.bytes
    assert value.len == size and value[0] == byte(index and 255)
    assert value[size-1] == byte((index+size-1) and 255)
  assert retained.len == Count and retained.lookup(key(0)).value.bytes.len == size
  assert file.close == FileError.None
  ChurnObservation(imageBytes: imageBytes, writtenBytes: written, writes: writes, syncs: syncs,
    renames: renames, updateHashes: hashes, reopenHashes: reopenHashes, updateNs: elapsed,
    reopenNs: reopenElapsed, before: before, after: after)
proc batchCycle(source, target: string, size: int, expected: StateRoot): ChurnObservation =
  ## Prepare the same sixteen sparse updates as one bounded group and synchronize only after its complete append.
  let prepared = load(source, size, expected)
  let proof = LightStateProof(key: key(0), proof: prepared.prove(key(0), LightProofReadLimits(
    entries: ElementLimit(1), proof: policy(size).cache.proof)).value)
  let config = LightJournalConfig(root: expected, snapshot: policy(size),
      journal: LightReplayLimits(
    bytes: ByteLimit(131072), frames: ElementLimit(16), frame: LightDeltaLimits(
      items: ElementLimit(1), bytes: ByteLimit(8192))))
  var file = default(LightJournalCache)
  assert initializeLightJournalCache(file, target, config, prepared).value ==
      StorageDurability.FileAndDirectorySynced
  let retained = file.snapshot.value
  let imageBytes = uint64(prepared.byteLength)
  var edits = newSeq[LightJournalEdit](16)
  for cycle in 0..<8:
    # Caller-authored update inputs are outside the measured phase, just like the shared source proof.
    edits[cycle*2] = LightJournalEdit(forgotten: @[key(0)])
    edits[cycle*2+1] = LightJournalEdit(proofs: @[proof])
  resetIo()
  resetHash(0)
  let before = getOccupiedMem()
  var written = 0'u64
  let started = getMonoTime().ticks
  block:
    # Retire the prepared candidate before reopen, matching ordinary per-update preparation lifetime.
    let batch = prepareLightJournalBatch(file, edits).value
    assert batch.frameCount == 16 and uint64(batch.sequence) == 16
    assert file.append(batch).value == StorageDurability.FileAndDirectorySynced
  written = file.journalBytes.value-98
  let elapsed = getMonoTime().ticks-started
  let after = getOccupiedMem()
  let writes = ioCalls(writeIo)
  let syncs = ioCalls(syncIo)
  let renames = ioCalls(renameIo)
  let hashes = calls()
  assert writes == 1 and syncs == 1 and renames == 0 and hashes == 176
  assert written == uint64(8*(500+17*64+size)) and elapsed >= 0
  assert file.close == FileError.None
  resetHash(0)
  let reopenStarted = getMonoTime().ticks
  assert openLightJournalCache(file, target, config) == FileError.None
  let reopenElapsed = getMonoTime().ticks-reopenStarted
  let reopenHashes = calls()
  assert reopenHashes == Count*18+179 and reopenElapsed >= 0
  let final = file.preparedSnapshot.value
  assert final.encodedBytes == prepared.encodedBytes
  for index in 0..<Count:
    # Independent fixture bytes and a retained pre-edit reader survive every publication and strict reopen.
    let value = file.snapshot.value.lookup(key(index)).value.bytes
    assert value.len == size and value[0] == byte(index and 255)
    assert value[size-1] == byte((index+size-1) and 255)
  assert retained.len == Count and retained.lookup(key(0)).value.bytes.len == size
  assert file.close == FileError.None
  ChurnObservation(imageBytes: imageBytes, writtenBytes: written, writes: writes, syncs: syncs,
    renames: renames, updateHashes: hashes, reopenHashes: reopenHashes, updateNs: elapsed,
    reopenNs: reopenElapsed, before: before, after: after)
proc churn(source, target: string, size: int, expected: StateRoot) =
  ## Final ARC retirement is sampled after every result, proof, retained image and native owner leaves scope.
  let baseline = getOccupiedMem()
  let observed = churnCycle(source, target, size, expected)
  let retired = getOccupiedMem()
  assert retired == baseline
  echo "churn\t", size, "\t8\t", observed.imageBytes, "\t", observed.writtenBytes, "\t",
      observed.writes,
    "\t", observed.syncs, "\t", observed.renames, "\t", observed.updateHashes, "\t",
        observed.reopenHashes,
    "\t", observed.updateNs, "\t", observed.reopenNs, "\t", baseline, "\t", observed.before,
    "\t", observed.after, "\t", retired
proc journal(source, target: string, size: int, expected: StateRoot) =
  ## Final ARC retirement is sampled after every result, proof, retained image and native owner leaves scope.
  let baseline = getOccupiedMem()
  let observed = journalCycle(source, target, size, expected)
  let retired = getOccupiedMem()
  assert retired == baseline
  echo "journal\t", size, "\t8\t", observed.imageBytes, "\t", observed.writtenBytes, "\t",
      observed.writes,
    "\t", observed.syncs, "\t", observed.renames, "\t", observed.updateHashes, "\t",
        observed.reopenHashes,
    "\t", observed.updateNs, "\t", observed.reopenNs, "\t", baseline, "\t", observed.before,
    "\t", observed.after, "\t", retired
proc journalBatch(source, target: string, size: int, expected: StateRoot) =
  ## Final ARC retirement is sampled after every result, proof, retained image and native owner leaves scope.
  let baseline = getOccupiedMem()
  let observed = batchCycle(source, target, size, expected)
  let retired = getOccupiedMem()
  assert retired == baseline
  echo "journal-batch\t", size, "\t8\t", observed.imageBytes, "\t", observed.writtenBytes, "\t",
      observed.writes,
    "\t", observed.syncs, "\t", observed.renames, "\t", observed.updateHashes, "\t",
        observed.reopenHashes,
    "\t", observed.updateNs, "\t", observed.reopenNs, "\t", baseline, "\t", observed.before,
    "\t", observed.after, "\t", retired
proc main() =
  ## Fixed fixture extents and explicit independent roots keep producer, reopen and publication modes distinct.
  assert paramCount() in [3, 4, 5]
  let mode = paramStr(1)
  let extent = paramStr(2)
  assert extent in ["64", "1024"]
  let size = if extent == "64": 64 else: 1024
  let path = paramStr(3)
  if mode == "produce":
    assert paramCount() == 3
    produce(path, size)
  elif mode == "consume":
    assert paramCount() == 4
    consume(path, size, root(paramStr(4)))
  else:
    assert mode in ["publish", "churn", "journal", "journal-batch"] and paramCount() == 5
    if mode == "publish": publish(path, paramStr(5), size, root(paramStr(4)))
    elif mode == "churn": churn(path, paramStr(5), size, root(paramStr(4)))
    elif mode == "journal": journal(path, paramStr(5), size, root(paramStr(4)))
    else: journalBatch(path, paramStr(5), size, root(paramStr(4)))
main()
