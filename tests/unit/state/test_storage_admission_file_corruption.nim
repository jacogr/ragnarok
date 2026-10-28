# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Valid outer checksums never authorize corrupt inner records, implicit repair or leaked replay locks.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/storage_samples
import ../../support/app_managed_storage_samples
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/managed_repository as storage_managed_repository
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/journal_codec as storage_journal_codec
import ../../../src/storage/snapshot_codec as storage_snapshot_codec
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded
import ../../../src/crypto/primitives as crypto_primitives

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Give finite real-file fixtures a process-owned namespace.
type FrameSlice = object ## Exact source-owned final frame bounds are independent of the later mutated bytes.
  offset, extent: int
proc bytes(text: string): seq[byte] =
  ## Test-owned files preserve all binary octets, including embedded zeroes.
  result = newSeq[byte](text.len)
  for index, value in text: result[index] = byte(value)
proc text(input: openArray[byte]): string =
  ## Ordinary file helpers receive a detached binary string without changing encoding or extent.
  result = newString(input.len)
  for index, value in input: result[index] = char(value)
proc reseal(input: var seq[byte]): StorageChecksum =
  ## Refresh only the outer integrity envelope, deliberately granting no local-record or graph authority.
  assert input.len > 32
  let digest = blake2b256(input.toOpenArray(0, input.len-33))
  assert digest.error == CryptoError.None
  let checksum = array[32, byte](digest.value)
  for index in 0..<32: input[input.len-32+index] = checksum[index]
  StorageChecksum(checksum)
proc lastFrame(input: seq[byte], start: int, limit: ByteLimit): FrameSlice =
  ## Walk only the closed valid fixture, proving exact bounded progress before authoring corruption.
  assert start >= 0 and start < input.len
  var offset = start
  result = FrameSlice(offset: start, extent: 0)
  while offset < input.len:
    let extent = journalFrameExtent(input.toOpenArray(offset, input.len-1), limit)
    assert extent.error == FrameError.None and extent.value <= input.len-offset
    assert extent.value > 0
    result = FrameSlice(offset: offset, extent: extent.value)
    offset += extent.value
  assert offset == input.len and result.extent > 48
proc reopen(owner: var FileRepository, path: string, managed: bool, legacy: JournalLimits,
    policy: ManagedLimits, repair: bool, generation: RepositoryGeneration,
        root: StateRoot): FileError =
  ## Both layouts require explicit exact-prefix recovery; complete invalid records are never incomplete tails.
  if managed:
    if repair:
      recoverManagedFileRepository(owner, path, default(StorageChainId), policy, generation, root)
    else:
      openManagedFileRepository(owner, path, default(StorageChainId), policy)
  else:
    if repair:
      recoverFileRepository(owner, path, default(StorageChainId), legacy, generation, root)
    else:
      openFileRepository(owner, path, default(StorageChainId), legacy)
proc attempt(managed: bool) {.raises.} =
  ## Author late inner corruption after valid revisions and prove strict refusal, byte preservation and reusable locks.
  let policy = managedStorageLimits()
  let legacy = JournalLimits(repository: policy.repository, bytes: policy.journalBytes,
    contextBytes: ByteLimit(0))
  let prefix = if managed: "storage-inner-managed-" else: "storage-inner-legacy-"
  let process = int(processId())
  var path = prefix & $process
  var writer = default(FileRepository)
  var reader = default(FileRepository)
  var created = false
  defer:
    if reader.opened: discard reader.close
    if writer.opened: discard writer.close
    if created:
      if managed: removeManagedSample(path, [ManagedEpoch(1)])
      else: assert posix.unlink(path.toCString()) == 0
  let a = storageTrie(7)
  let b = storageTrie(8)
  let c = storageTrie(10)
  let full = exportFullTrie(a, policy.repository.codec.records).value
  var source = newNodeRepository(policy.repository)
  let seed = source.publish(source.snapshot.value, full).value
  if managed:
    let selected = selectRepositoryRoots(seed, [seed.commitment.root], ElementLimit(1)).value
    assert initializeManagedFileRepository(writer, path, default(StorageChainId), selected, [],
      policy) == FileError.None
  else:
    assert initializeFileRepository(writer, path, default(StorageChainId), legacy) == FileError.None
    discard writer.publish(writer.snapshot.value, full).value
  created = true
  let middle = writer.publish(writer.snapshot.value, exportTrieChanges(a, b,
    policy.repository.codec.records).value).value
  let held = writer.publish(middle, exportTrieChanges(b, c,
      policy.repository.codec.records).value).value
  assert uint64(middle.generation) == 2 and uint64(held.generation) == 3
  assert writer.close == FileError.None
  let journal = if managed: path & "/journal-0000000000000001.wal" else: path
  let snapshot = path & "/snapshot-0000000000000001.bin"
  let current = path & "/CURRENT"
  let original = readFile(journal)
  let originalSnapshot = if managed: readFile(snapshot) else: ""
  let originalCurrent = if managed: readFile(current) else: ""
  var forged = bytes(original)
  let start = if managed: ManagedJournalHeaderBytes else: StorageIdentityBytes
  let selected = lastFrame(forged, start, policy.journalBytes)
  var frame = newSeq[byte](selected.extent)
  for index in 0..<frame.len: frame[index] = forged[selected.offset+index]
  frame[frame.len-33] = frame[frame.len-33] xor 1
  discard reseal(frame)
  let rejected = decodeJournalFrame(frame, policy.repository.codec, policy.journalBytes)
  assert rejected.error == FrameError.InvalidRecords
  assert rejected.recordError == RecordError.HashMismatch
  for index in 0..<frame.len: forged[selected.offset+index] = frame[index]
  let forgedText = text(forged)
  for repair in [false, true]:
    writeFile(journal, forgedText)
    assert reopen(reader, path, managed, legacy, policy, repair,
      middle.generation, middle.commitment.root) == FileError.InvalidJournal
    assert not reader.opened and readFile(journal) == forgedText
    if managed:
      assert readFile(snapshot) == originalSnapshot and readFile(current) == originalCurrent
    writeFile(journal, original)
    assert reopen(reader, path, managed, legacy, policy, false,
      middle.generation, middle.commitment.root) == FileError.None
    assert uint64(reader.snapshot.value.generation) == 3
    assert reader.close == FileError.None # A new held-inode lock proves failed replay retired every earlier lock.
  if managed:
    var brokenSnapshot = bytes(originalSnapshot)
    brokenSnapshot[brokenSnapshot.len-33] = brokenSnapshot[brokenSnapshot.len-33] xor 1
    let snapshotChecksum = reseal(brokenSnapshot)
    let snapshotPolicy = SnapshotLimits(repository: policy.repository, roots: policy.roots,
      context: policy.contextBytes, bytes: policy.snapshotBytes)
    let invalid = decodeRepositorySnapshot(brokenSnapshot, default(StorageChainId),
      StorageSchema.FullNodesV1, snapshotPolicy)
    assert invalid.error == SnapshotError.RecordFailure
    assert invalid.recordError == RecordError.HashMismatch
    let manifest = decodeManagedManifest(bytes(originalCurrent), default(StorageChainId),
      StorageSchema.FullNodesV1, ByteLimit(ManagedManifestBytes)).value
    let replacement = encodeManagedManifest(default(StorageChainId), StorageSchema.FullNodesV1,
      manifest.epoch, manifest.generation, manifest.root, snapshotChecksum,
      ByteLimit(ManagedManifestBytes)).value
    let header = encodeManagedJournalHeader(replacement.checksum, ByteLimit(
        ManagedJournalHeaderBytes)).value
    var rebound = bytes(original)
    for index in 0..<header.len: rebound[index] = header[index]
    let newSnapshot = text(brokenSnapshot)
    let newCurrent = text(replacement.bytes)
    let newJournal = text(rebound)
    for repair in [false, true]:
      writeFile(snapshot, newSnapshot)
      writeFile(current, newCurrent)
      writeFile(journal, newJournal)
      assert reopen(reader, path, true, legacy, policy, repair,
        seed.generation, seed.commitment.root) == FileError.InvalidJournal
      assert not reader.opened
      assert readFile(snapshot) == newSnapshot and readFile(current) == newCurrent
      assert readFile(journal) == newJournal # Every outer binding is valid; inner corruption still grants no repair authority.
      writeFile(snapshot, originalSnapshot)
      writeFile(current, originalCurrent)
      writeFile(journal, original)
      assert reopen(reader, path, true, legacy, policy, false,
        seed.generation, seed.commitment.root) == FileError.None
      assert reader.close == FileError.None
  assert restoreStateEntries(middle, b.commitment.root, policy.repository.codec.trie).value[
      0].value == @[8'u8]
  assert restoreStateEntries(held, c.commitment.root, policy.repository.codec.trie).value[
      0].value == @[10'u8]
proc main() {.raises.} =
  ## Keep this real-fsync corruption matrix finite; pure staged owner suites carry the 1,000-cycle ARC proofs.
  attempt(false)
  attempt(true)

try:
  main()
except:
  quit(2) # Unexpected file/environment errors fail the fixture.
echo "PASS storage admission file corruption: valid outer bindings, strict inner refusal, preserved bytes and locks"
