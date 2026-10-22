# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Sustained public repository operations retain exact complete maps across restart and reclamation.
import std/[assertions, syncio, cmdline, monotimes, times]
import std/posix/posix
import ../support/[storage_growth_samples, managed_storage_samples]
import ../../src/storage/[full_state_trie, node_records, node_repository, file_repository,
  managed_repository,
  database_identity, managed_manifest]
import ../../src/codec/[bounded, state_layout, state_trie]

proc elapsed(start: MonoTime): int64 =
  ## Positive monotonic nanoseconds describe only the requested public API operation batch.
  (getMonoTime()-start).inNanoseconds
proc main() {.raises.} =
  ## The orchestrator supplies fixed axes and thirteen samples; one-sample runs only check execution.
  assert paramCount() == 6
  let engine = paramStr(1)
  assert engine in ["memory", "journal", "managed"]
  assert paramStr(2) in ["1024", "8192"] and paramStr(3) in ["64", "256"]
  let count = if paramStr(2) == "1024": 1024 else: 8192
  let publications = if paramStr(3) == "64": 64 else: 256
  let folder = paramStr(4)
  assert paramStr(5) in ["1", "13"]
  let samples = if paramStr(5) == "1": 1 else: 13
  let pattern = paramStr(6)
  assert pattern in ["sweep", "hot"]
  let hot = pattern == "hot"
  let limits = growthLimits()
  let journal = JournalLimits(repository: limits, bytes: ByteLimit(33554432))
  let managed = ManagedLimits(repository: limits, roots: ElementLimit(9),
    snapshotBytes: ByteLimit(33554432), journalBytes: ByteLimit(33554432), contextBytes: ByteLimit(64))
  let fixture = prepareGrowth(count, publications, hot)
  let expected = fixture.roots[publications]
  var roots: seq[StateRoot] = @[fixture.roots[0]]
  for revision in publications-7..publications:
    roots.add(fixture.roots[revision]) # The seed plus eight latest complete maps are explicit synthetic retention.
  var seed = newNodeRepository(limits)
  let seedView = seed.publish(seed.snapshot.value, fixture.seed).value
  let selection = selectRepositoryRoots(seedView, [seedView.commitment.root], ElementLimit(1)).value
  for sample in 0..<samples:
    # Namespace creation, fixture preparation and complete-map checks stay outside all timed intervals.
    let path = folder & "/sample-" & $sample
    var memory = newNodeRepository(limits)
    var disk = default(FileRepository)
    defer:
      if disk.opened: discard disk.close # Failed assertions still release the exact native owner.
    if engine == "memory":
      discard memory.publish(memory.snapshot.value, fixture.seed).value
    elif engine == "journal":
      assert initializeFileRepository(disk, path, default(StorageChainId), journal) == FileError.None
      discard disk.publish(disk.snapshot.value, fixture.seed).value
    else:
      assert initializeManagedFileRepository(disk, path, default(StorageChainId), selection, [],
          managed) == FileError.None
    var latencies = newSeq[int64](publications)
    let publicationStart = getMonoTime()
    for index, change in fixture.changes:
      let revisionStart = getMonoTime()
      if engine == "memory":
        discard memory.publish(memory.snapshot.value, change).value
      else:
        discard disk.publish(disk.snapshot.value, change).value # Disk includes actual synchronization for every revision.
      latencies[index] = elapsed(revisionStart) # Retain each complete public call without formatting in timing.
    let publicationNs = elapsed(publicationStart)
    let held = if engine == "memory": memory.snapshot.value else: disk.snapshot.value
    assert uint64(held.generation) == uint64(publications+1)
    assert array[32, byte](held.commitment.root) == array[32, byte](expected)
    let extractionStart = getMonoTime()
    let extracted = restoreStateEntries(held, expected, limits.codec.trie).value
    let extractionBeforeNs = elapsed(extractionStart)
    checkGrowthEntries(extracted, count, publications, hot)
    var observed = newSeq[TrieRecord](4096)
    let readsStart = getMonoTime()
    for index in 0..<observed.len:
      observed[index] = held.lookupNode(fixture.reads[(index*2053) mod count]).value
    let readsBeforeNs = elapsed(readsStart)
    for index, record in observed:
      assert array[32, byte](record.digest) == array[32, byte](fixture.reads[(
          index*2053) mod count])
      checkGrowthRecord(record, count, publications, hot)
    var reopenNs = -1'i64
    if engine != "memory":
      assert disk.close == FileError.None
      let reopenStart = getMonoTime()
      if engine == "journal":
        assert openFileRepository(disk, path, default(StorageChainId), journal) == FileError.None
      else:
        assert openManagedFileRepository(disk, path, default(StorageChainId), managed) == FileError.None
      reopenNs = elapsed(reopenStart)
      assert uint64(disk.snapshot.value.generation) == uint64(publications+1)
      checkGrowthHead(disk.snapshot.value, expected, count, publications, hot)
    let storedNodes = held.storedNodes
    var snapshotBytes = -1'i64
    var journalBytes = -1'i64
    if engine == "journal":
      snapshotBytes = 0 # Single-file journals have no selected snapshot.
      journalBytes = int64(readFile(path).len)
    elif engine == "managed":
      let usage = disk.managedUsage.value
      assert usage.snapshotBytes <= uint64(high(int64)) and usage.journalBytes <= uint64(high(int64))
      snapshotBytes = int64(usage.snapshotBytes)
      journalBytes = int64(usage.journalBytes)
    var readsAfterNs = -1'i64
    var extractionAfterNs = -1'i64
    var retainedReopenNs = -1'i64
    var compactedReopenNs = -1'i64
    var retentionNs = -1'i64
    var maintenanceNs = -1'i64
    var retainedNodes = -1
    var currentNodes = -1
    var retainedSnapshotBytes = -1'i64
    var retainedJournalBytes = -1'i64
    var compactedSnapshotBytes = -1'i64
    var compactedJournalBytes = -1'i64
    if engine != "journal":
      # Retain the same explicit nine-root union in both backends, including all real managed barriers.
      let retentionStart = getMonoTime()
      if engine == "memory":
        let selected = selectRepositoryRoots(held, roots, ElementLimit(9)).value
        var clone = cloneRepositorySelection(selected, limits).value
        assert memory.close == RepositoryError.None
        memory = clone
        assert clone.close == RepositoryError.None
      else:
        let receipt = disk.compact(disk.snapshot.value, roots).value
        assert receipt.cleanup == FileError.None and uint64(receipt.epoch) == 2
      retentionNs = elapsed(retentionStart)
      let retained = if engine == "memory": memory.snapshot.value else: disk.snapshot.value
      retainedNodes = retained.storedNodes
      checkGrowth(retained, roots[0], count, 0, hot)
      for revision in publications-7..publications:
        checkGrowth(retained, fixture.roots[revision], count, revision, hot)
      if engine == "managed":
        let retainedUsage = disk.managedUsage.value
        assert retainedUsage.storedNodes == retainedNodes
        assert retainedUsage.journalBytes == uint64(ManagedJournalHeaderBytes)
        assert retainedUsage.snapshotBytes <= uint64(high(int64))
        retainedSnapshotBytes = int64(retainedUsage.snapshotBytes)
        retainedJournalBytes = int64(retainedUsage.journalBytes)
        # Reopen the nine-root epoch before current-only reclamation, validating every retained complete map.
        assert disk.close == FileError.None
        let retainedReopenStart = getMonoTime()
        assert openManagedFileRepository(disk, path, default(StorageChainId), managed) == FileError.None
        retainedReopenNs = elapsed(retainedReopenStart)
        checkGrowthHead(disk.snapshot.value, expected, count, publications, hot)
        checkGrowth(disk.snapshot.value, roots[0], count, 0, hot)
        for revision in publications-7..publications:
          checkGrowth(disk.snapshot.value, fixture.roots[revision], count, revision, hot)
      let maintenanceStart = getMonoTime()
      if engine == "memory":
        let selected = selectRepositoryRoots(retained, [expected], ElementLimit(1)).value
        var clone = cloneRepositorySelection(selected, limits).value
        assert memory.close == RepositoryError.None
        memory = clone
        assert clone.close == RepositoryError.None
      else:
        let receipt = disk.compact(disk.snapshot.value, [expected]).value
        assert receipt.cleanup == FileError.None and uint64(receipt.epoch) == 3
      maintenanceNs = elapsed(maintenanceStart)
      let current = if engine == "memory": memory.snapshot.value else: disk.snapshot.value
      currentNodes = current.storedNodes
      assert currentNodes < retainedNodes and retainedNodes <= storedNodes
      assert uint64(current.generation) == uint64(publications+1)
      let extractionAfterStart = getMonoTime()
      let extractedAfter = restoreStateEntries(current, expected, limits.codec.trie).value
      extractionAfterNs = elapsed(extractionAfterStart)
      checkGrowthEntries(extractedAfter, count, publications, hot)
      var observedAfter = newSeq[TrieRecord](4096)
      let readsAfterStart = getMonoTime()
      for index in 0..<observedAfter.len:
        observedAfter[index] = current.lookupNode(fixture.reads[(index*2053) mod count]).value
      readsAfterNs = elapsed(readsAfterStart)
      for index, record in observedAfter:
        assert array[32, byte](record.digest) == array[32, byte](fixture.reads[(
            index*2053) mod count])
        checkGrowthRecord(record, count, publications, hot)
      if engine == "managed":
        let usage = disk.managedUsage.value
        assert usage.journalBytes == uint64(ManagedJournalHeaderBytes)
        assert usage.snapshotBytes <= uint64(high(int64))
        compactedSnapshotBytes = int64(usage.snapshotBytes)
        compactedJournalBytes = int64(usage.journalBytes)
        assert disk.close == FileError.None
        let compactedReopenStart = getMonoTime()
        assert openManagedFileRepository(disk, path, default(StorageChainId), managed) == FileError.None
        compactedReopenNs = elapsed(compactedReopenStart)
        assert uint64(disk.snapshot.value.generation) == uint64(publications+1)
        checkGrowthHead(disk.snapshot.value, expected, count, publications, hot)
    if disk.opened:
      assert disk.close == FileError.None
      if engine == "journal":
        var nativePath = path
        assert posix.unlink(nativePath.toCString()) == 0
      else:
        removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3)])
    assert memory.close == RepositoryError.None
    checkGrowthHead(held, expected, count, publications,
        hot) # Retired files and owner close cannot revoke immutable readers.
    for index, duration in latencies:
      # Emit observations only after all complete-map/lifetime validation and native namespace cleanup.
      echo "publication\t", count, "\t", publications, "\t", pattern, "\t", sample,
        "\t", index+1, "\t", duration
    echo "growth\t", count, "\t", publications, "\t", pattern, "\t", sample, "\t", publicationNs, "\t",
      reopenNs, "\t", retentionNs, "\t", maintenanceNs, "\t", retainedReopenNs, "\t",
          compactedReopenNs, "\t", extractionBeforeNs, "\t", extractionAfterNs, "\t", readsBeforeNs,
              "\t", readsAfterNs, "\t", storedNodes, "\t", retainedNodes,
      "\t", currentNodes, "\t", snapshotBytes, "\t", journalBytes, "\t", retainedSnapshotBytes,
          "\t", retainedJournalBytes, "\t", compactedSnapshotBytes,
      "\t", compactedJournalBytes
  assert seed.close == RepositoryError.None
try:
  main()
except:
  quit(2)
