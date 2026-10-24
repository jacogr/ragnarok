# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The complete disk facade preserves exact owned state/context, retained application history and native uncertainty on paged storage.
# @@Verification={"arc":"paged_disk_state_store_arc_release"}
import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/disk_worker
import ../../support/[arc_evidence, storage_io, full_paged_reference, full_paged_native_fixture,
  disk_history_context]
import ../../../src/state/[store, paged_state, disk_store]
import ../../../src/app/[chain, disk_history]
import ../../../src/chain/[genesis, provider]
import ../../../src/storage/[full_paged_codec, full_paged_store, full_paged_stream,
  full_paged_build,
  node_records, node_repository, paged_codec, managed_manifest, file_errors, durability,
  database_identity]
import ../../../src/codec/[bounded, state_trie]
func statePolicy(): StateStoreLimits =
  ## Full-map limits remain separate from native context, export and physical working policies.
  StateStoreLimits(trie: policy().trie, writes: ElementLimit(10), writeValueBytes: ByteLimit(10000))
proc state(value: byte): StateStoreSnapshot =
  ## Independent ordinary complete maps contain one changed value and a present-empty value.
  newStateStore(@[StateEntry(key: key(0), value: @[value]), StateEntry(key: key(128), value: @[])],
      statePolicy()).value.snapshot.value
proc path(label: string): string =
  ## Every native workload owns its exact test namespace without a cleanup sweep.
  "paged-disk-state-" & $storageProcessId() & "-" & label
proc configuration(source: StateStoreSnapshot, stateLimits: StateStoreLimits): FullPagedNativeConfig =
  ## Finite application-sized policies admit nine retained roots and independently bounded opaque history context.
  result = sample(5).config
  result.root = source.commitment.root
  result.limits.trie = stateLimits.trie
  result.limits.roots = ElementLimit(9)
  result.limits.dataset = PagedLimits(entries: ElementLimit(1000000), bytes: ByteLimit(64000000))
  result.limits.contextBytes = ByteLimit(4194304)
  result.limits.workingBytes = ByteLimit(32000000)
  result.limits.scratchBytes = ByteLimit(8000000)
  result.limits.work.ioCalls = ElementLimit(10000000)
  result.limits.work.hashes = ElementLimit(10000000)
  result.limits.work.visits = ElementLimit(10000000)
  result.limits.work.readBytes = ByteLimit(1000000000)
  result.limits.work.writeBytes = ByteLimit(64000000)
  result.construction = FullPagedConstructionLimits(producerCalls: ElementLimit(10000000),
    ioCalls: ElementLimit(10000000), hashes: ElementLimit(10000000),
    readBytes: ByteLimit(1000000000), writeBytes: ByteLimit(64000000))
proc transport(config: FullPagedNativeConfig): PagedStateLimits =
  ## Aggregate staging charges every retained map before physical record deduplication.
  PagedStateLimits(roots: ElementLimit(9), staging: TrieExportLimits(records: TrieNodeLimit(
      10000000),
    valueBytes: ByteLimit(64000000)), dataset: config.limits.dataset)
proc normal() =
  ## Successful publication adopts the exact target owner only after one durable complete-root/context selection.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  let directory = path("normal")
  var disk = default(DiskStateStore)
  var other = default(DiskStateStore)
  defer:
    # Native retirement remains explicit across successful, busy and uncertain owners.
    resetIo()
    if other.opened: discard other.close
    if disk.opened: discard disk.close
  assert initializePagedDiskStateStore(disk, directory, source, config, limits, [7'u8]).error ==
      DiskStoreError.None
  assert sameStateSnapshot(disk.snapshot.value, source)
  assert uint64(disk.generation.value) == 1 and disk.snapshotContext.value == @[7'u8]
  assert disk.synchronize.value == StorageDurability.FileAndDirectorySynced
  assert disk.managedDiskUsage.error == FileError.UnsupportedLayout
  assert disk.cleanupManagedDiskFiles == FileError.UnsupportedLayout
  let busy = openLocalPagedDiskStateStore(other, directory, config.chain, statePolicy(), config, limits)
  assert busy.error == DiskStoreError.FileFailure and busy.fileError == FileError.Busy
  assert not other.opened
  assert disk.commit(target, source, [9'u8]).error == DiskStoreError.StaleSnapshot
  assert disk.commit(source, target).error == DiskStoreError.ContextRequired
  assert disk.commit(source, target, [9'u8], [source]).error == DiskStoreError.None
  assert sameStateSnapshot(disk.snapshot.value, target)
  assert uint64(disk.generation.value) == 2 and disk.snapshotContext.value == @[9'u8]
  assert disk.restoreDiskSnapshot(source.commitment.root, statePolicy()).value.lookup(key(
      0)).value.bytes == @[5'u8]
  let retained = disk.snapshot.value
  assert disk.close == FileError.None
  assert retained.lookup(key(0)).value.bytes == @[9'u8]
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
      limits).error == DiskStoreError.None
  assert disk.snapshot.value.lookup(key(0)).value.bytes == @[9'u8]
  assert uint64(disk.generation.value) == 2 and disk.snapshotContext.value == @[9'u8]
  assert disk.restoreDiskSnapshot(source.commitment.root, statePolicy()).value.lookup(key(
      0)).value.bytes == @[5'u8]
  let retirement = preparePagedRetirement(disk).value
  assert disk.commitPagedRetirement(retirement).error == DiskStoreError.None
  assert not disk.pagedRetirementPending # Historical maps below must now come entirely from the selected union, not the removed artifact.
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Independent historical complete maps and detached context values must release every temporary owner.
    assert disk.restoreDiskSnapshot(source.commitment.root, statePolicy()).value.lookup(key(
        0)).value.bytes == @[5'u8]
    assert disk.snapshotContext.value == @[9'u8]
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("paged_disk_state_store", 1000, before, after)
  assert disk.close == FileError.None
proc history() {.raises.} =
  ## Existing application restoration binds rolling headers, nine complete roots and older explicit finality on the paged facade.
  let fixture = diskHistoryFixture()
  let owner = initApplicationChain(fixture.view).value
  let source = owner.stateSnapshot.value
  let config = configuration(source, fixture.policy)
  var retained: seq[StateStoreSnapshot] = @[]
  for index in 0..<fixture.view.retainedCount-1:
    # The exact current owner is supplied separately; every older rolling snapshot remains complete.
    retained.add(fixture.view.retainedBlockAt(RetainedBlockIndex(index)).value.stateSnapshot)
  retained.add(fixture.view.finalizedBlock.value.stateSnapshot)
  let context = encodeDiskHistory(owner, config.chain, RepositoryGeneration(1),
      config.limits.contextBytes).value
  let directory = path("history")
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Failed context binding never abandons the native writer lease.
  assert initializePagedDiskStateStore(disk, directory, source, config, transport(config), context,
      retained).error == DiskStoreError.None
  assert disk.close == FileError.None
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, fixture.policy, config,
      transport(config)).error == DiskStoreError.None
  let restored = restoreDiskHistory(disk.snapshotContext.value, config.chain, disk.generation.value,
    fixture.view.bestBlock.value.chainParameters, disk, fixture.policy, config.limits.contextBytes)
  assert restored.error == DiskHistoryError.None
  assert sameStateSnapshot(restored.value.stateSnapshot.value, disk.snapshot.value)
  assert encodeDiskHistory(restored.value, config.chain, disk.generation.value,
      config.limits.contextBytes).value == context
  assert restored.value.chainView.retainedCount == MaxRetainedBlocks
  assert array[32, byte](restored.value.chainView.finalizedBlock.value.blockHash) == array[32,
      byte](fixture.view.finalizedBlock.value.blockHash)
  assert disk.close == FileError.None
proc faults() =
  ## Real publication rename and fresh durability failures retain old owned memory without claiming a successful writable head.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  for operation in [renameIo, syncIo]:
    # Each fault gets an independently synchronized source namespace and a fresh explicit native incarnation.
    let directory = path("fault-" & $operation)
    var disk = default(DiskStateStore)
    assert initializePagedDiskStateStore(disk, directory, source, config, limits, [7'u8]).error ==
        DiskStoreError.None
    armIo(operation, 0, 1, failedIo)
    let failed = if operation == renameIo: disk.commit(source, target, [9'u8], [source])
      else:
        # A failed explicit barrier is a file failure, not a publication result with a fabricated snapshot.
        let synced = disk.synchronize
        assert synced.error != FileError.None
        disk.snapshot
    assert pendingIo() == 0
    resetIo()
    assert failed.error == DiskStoreError.FileFailure
    assert source.lookup(key(0)).value.bytes == @[5'u8]
    assert disk.snapshot.error != DiskStoreError.None
    assert disk.close == FileError.None
    assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
        limits).error == DiskStoreError.None
    assert disk.snapshot.value.lookup(key(0)).value.bytes == @[5'u8]
    assert disk.snapshotContext.value == @[7'u8] and uint64(disk.generation.value) == 1
    assert disk.close == FileError.None
proc lateBarrier() =
  ## A failed final directory barrier leaves old memory private while fresh recovery resolves the actual new CURRENT/context pair.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  var disk = default(DiskStateStore)
  let baseline = path("barrier-baseline")
  assert initializePagedDiskStateStore(disk, baseline, source, config, limits, [7'u8]).error ==
      DiskStoreError.None
  resetIo()
  assert disk.commit(source, target, [9'u8], [source]).error == DiskStoreError.None
  let calls = ioCalls(syncIo)
  assert calls > 0 and calls <= uint64(high(cint))
  assert disk.close == FileError.None
  let directory = path("late-barrier")
  assert initializePagedDiskStateStore(disk, directory, source, config, limits, [7'u8]).error ==
      DiskStoreError.None
  armIo(syncIo, cint(calls-1), 1, failedIo)
  let failed = disk.commit(source, target, [9'u8], [source])
  assert failed.error == DiskStoreError.FileFailure and failed.fileError ==
      FileError.PublishedUnsynced
  assert pendingIo() == 0
  resetIo()
  assert disk.snapshot.error != DiskStoreError.None
  assert source.lookup(key(0)).value.bytes == @[5'u8]
  assert disk.close == FileError.None
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
      limits).error == DiskStoreError.None
  assert disk.snapshot.value.lookup(key(0)).value.bytes == @[9'u8]
  assert disk.snapshotContext.value == @[9'u8] and uint64(disk.generation.value) == 2
  assert disk.close == FileError.None
proc cachedMetadata() =
  ## Dispatcher metadata never consumes a native read fault; the excluded commit must still fence the actual disk source.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  let directory = path("cached-metadata")
  var disk = default(DiskStateStore)
  assert initializePagedDiskStateStore(disk, directory, source, config, limits, [7'u8]).error ==
      DiskStoreError.None
  resetIo() # Observe only passive getters and the following actual worker fence.
  armIo(readIo, 0, 1, failedIo)
  assert sameStateSnapshot(disk.snapshot.value, source)
  assert uint64(disk.generation.value) == 1
  var detached = disk.snapshotContext.value
  detached[0] = 99
  assert disk.snapshotContext.value == @[7'u8]
  assert pendingIo() == 1 and ioCalls(readIo) == 0 # Passive captures perform no stat, read or source-repair operation.
  let refused = disk.commit(source, target, [9'u8], [source])
  assert refused.error == DiskStoreError.FileFailure and refused.fileError == FileError.IoFailure
  assert pendingIo() == 0
  resetIo()
  assert disk.snapshot.fileError == FileError.RecoveryRequired
  assert disk.generation.fileError == FileError.RecoveryRequired
  assert disk.snapshotContext.error == FileError.RecoveryRequired
  assert ioCalls(readIo) == 0
  assert source.lookup(key(0)).value.bytes == @[5'u8]
  assert disk.close == FileError.None
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
      limits).error == DiskStoreError.None
  assert disk.snapshotContext.value == @[7'u8] and uint64(disk.generation.value) == 1
  assert disk.close == FileError.None
proc contextEnvelope(context: seq[byte], previous: string): seq[byte] =
  ## Independent application-envelope bytes use only literal framing and captured actual old CURRENT bytes.
  result = @[]
  for character in "RAGNAROK-STATE-PAGED-CONTEXT-V1\n": result.add(byte(character))
  result.add(if previous.len == 0: 0'u8 else: 1'u8)
  for index in 0..<8: result.add(byte((uint64(context.len) shr (8*index)) and 255)) # Exact E8 inner extent.
  for character in previous: result.add(byte(character)) # Every old manifest octet must remain bound, including its tree digest.
  for octet in context: result.add(octet) # Unwrapped public context remains caller-owned metadata.
proc envelopeWitness() {.raises.} =
  ## Actual native V2 context contains the exact authenticated previous descriptor, while facade callers receive detached inner bytes.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  let directory = path("envelope")
  var disk = default(DiskStateStore)
  var reader = default(FullPagedReader)
  defer:
    if reader.opened: discard reader.close # Native source observations never prolong the facade's retirement lease.
    if disk.opened: discard disk.close
  assert initializePagedDiskStateStore(disk, directory, source, config, limits, [7'u8]).error ==
      DiskStoreError.None
  let previous = readFile(directory & "/CURRENT")
  assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  assert reader.readContext(config.limits.work).value.bytes == contextEnvelope(@[7'u8], "")
  assert reader.close == FileError.None
  assert disk.commit(source, target, [9'u8], [source]).error == DiskStoreError.None
  var selected = config
  selected.root = target.commitment.root
  assert openFullPagedReader(reader, directory, selected).error == FullPagedNativeError.None
  assert reader.readContext(selected.limits.work).value.bytes == contextEnvelope(@[9'u8], previous)
  assert disk.snapshotContext.value == @[9'u8]
  assert reader.close == FileError.None
  assert disk.close == FileError.None
proc malformedEnvelope() {.raises.} =
  ## Fully valid storage-only V2 artifacts cannot bypass the explicit application schema, tagged source identity or bounded inner length.
  let source = state(5)
  let config = configuration(source, statePolicy())
  let limits = transport(config)
  let prepared = preparePagedState(source, [], limits).value
  let correct = contextEnvelope(@[7'u8], "")
  for kind in 0..<6:
    # Each mutation is authenticated by the unchanged native backend, so refusal belongs to the application envelope decoder.
    var raw = clone(correct)
    case kind
    of 0: raw[0] = raw[0] xor 1
    of 1: raw["RAGNAROK-STATE-PAGED-CONTEXT-V1\n".len] = 2
    of 2:
      for index in 0..<8: raw["RAGNAROK-STATE-PAGED-CONTEXT-V1\n".len+1+index] = 255 # Huge E8 cannot cause allocation or narrowing.
    of 3: raw.add(0) # Exact framing rejects unaccounted trailing transport.
    of 4: raw = @[7'u8] # An opaque storage-only V2 context is not an application envelope.
    else:
      raw["RAGNAROK-STATE-PAGED-CONTEXT-V1\n".len] = 1 # A predecessor tag requires a complete fixed manifest and a successor generation.
      for index in 0..<192: raw.add(0)
    let directory = path("bad-envelope-" & $kind)
    var native = default(FullPagedWriter)
    var disk = default(DiskStateStore)
    let initialized = initializePagedStateStore(native, directory, config, prepared, raw)
    assert initialized.error == PagedStateError.None
    assert native.close == FileError.None
    let before = readFile(directory & "/CURRENT")
    let rejected = openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(),
        config, limits)
    assert rejected.error == DiskStoreError.FileFailure and rejected.fileError ==
        FileError.WrongIdentity
    assert not disk.opened and readFile(directory & "/CURRENT") == before
proc retirementBackpressure() =
  ## Pending retirement blocks the next artifact; stale and reopened jobs cannot mutate a valid later incarnation.
  let source = state(5)
  let target = state(9)
  let successor = state(11)
  let config = configuration(source, statePolicy())
  let directory = path("retirement-backpressure")
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Every admitted native owner is explicitly retired.
  assert initializePagedDiskStateStore(disk, directory, source, config, transport(config), [
      7'u8]).error == DiskStoreError.None
  assert not disk.pagedRetirementPending
  assert preparePagedRetirement(disk).error == DiskStoreError.RetirementNotPending
  assert disk.commit(source, target, [9'u8], [source]).error == DiskStoreError.None
  let job = preparePagedRetirement(disk).value
  assert job.ready and disk.pagedRetirementPending
  resetIo()
  assert disk.commit(target, successor, [11'u8], [target]).error == DiskStoreError.RetirementPending
  assert ioCalls(readIo) == 0 and ioCalls(writeIo) == 0
  assert disk.commitPagedRetirement(default(PreparedPagedRetirement)).error ==
      DiskStoreError.StaleSnapshot
  assert disk.commitPagedRetirement(job).error == DiskStoreError.None
  assert not disk.pagedRetirementPending
  assert disk.commit(target, successor, [11'u8], [target]).error == DiskStoreError.None
  resetIo()
  assert disk.commitPagedRetirement(job).error == DiskStoreError.StaleSnapshot
  assert ioCalls(readIo) == 0 and sameStateSnapshot(disk.snapshot.value, successor)
  let next = preparePagedRetirement(disk).value
  assert disk.close == FileError.None
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
      transport(config)).error == DiskStoreError.None
  assert disk.commitPagedRetirement(next).error == DiskStoreError.StaleSnapshot
  assert disk.commitPagedRetirement(preparePagedRetirement(disk).value).error == DiskStoreError.None
  assert disk.close == FileError.None
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
      transport(config)).error == DiskStoreError.None
  let absent = disk.commitPagedRetirement(preparePagedRetirement(disk).value)
  assert absent.error == DiskStoreError.None and absent.value.alreadyAbsent
  assert not disk.pagedRetirementPending and disk.snapshot.value.lookup(key(0)).value.bytes == @[11'u8]
proc waitRetirement(worker: var DiskPublicationWorker) =
  ## The host observes only synchronized scalars while the worker borrows every store/job alias.
  let started = getMonoTime()
  while worker.phase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield under a bounded monotonic test deadline.
proc retirementWorker(mode, failure: int) {.raises.} =
  ## Collect/join/immediate shutdown preserve a typed retirement receipt for success, Busy and actual IO failure.
  let source = state(5)
  let target = state(9)
  let config = configuration(source, statePolicy())
  let directory = path("retirement-worker-" & $mode & "-" & $failure)
  var disk = default(DiskStateStore)
  var reader = default(FullPagedReader)
  var worker = default(DiskPublicationWorker)
  defer:
    discard worker.close() # Join before any borrowed store/job graph can retire, even after an assertion path.
    resetIo()
    if reader.opened: discard reader.close
    if disk.opened: discard disk.close
  assert initializePagedDiskStateStore(disk, directory, source, config, transport(config), [
      7'u8]).error == DiskStoreError.None
  if failure == 1:
    # The independent old reader physically excludes unlink without borrowing the facade's resident graph.
    assert openFullPagedReader(reader, directory, config).error == FullPagedNativeError.None
  assert disk.commit(source, target, [9'u8], [source]).error == DiskStoreError.None
  var job = preparePagedRetirement(disk).value
  let retained = disk.snapshot.value
  assert worker.start()
  resetIo()
  if failure == 2: armIo(readIo, 0, 1, failedIo) # The first actual retirement source fence refuses on the IO worker.
  let admitted = worker.submitRetirement(disk, job)
  assert admitted.error == DiskWorkerError.None
  var unready = default(PreparedPagedRetirement)
  assert worker.submitRetirement(disk, unready).error == DiskWorkerError.Busy
  assert worker.collect(default(DiskPublicationTicket)).kind == DiskCompletionKind.Uninitialized
  var completion = default(DiskPublicationCompletion)
  if mode == 2:
    completion = worker.close() # Only queued shutdown may report NotExecuted; entered IO must retain its actual result.
  else:
    waitRetirement(worker)
    if mode == 0:
      completion = worker.collect(admitted.value)
      assert worker.collect(admitted.value).kind == DiskCompletionKind.Uninitialized
      assert worker.close.kind == DiskCompletionKind.Uninitialized
    else:
      completion = worker.close() # Joined Done shutdown must route retirement, never a default ordinary publication result.
  if completion.kind == DiskCompletionKind.Retired:
    # Actual retirement outcomes stay in their own guarded variant after either collect or joined close.
    let outcome = completion.retirementValue
    if failure == 0:
      assert outcome.error == DiskStoreError.None and not disk.pagedRetirementPending
    elif failure == 1:
      assert outcome.error == DiskStoreError.FileFailure and outcome.fileError == FileError.Busy
      assert disk.pagedRetirementPending and sameStateSnapshot(disk.snapshot.value, target)
    else:
      assert outcome.error == DiskStoreError.FileFailure and outcome.fileError ==
          FileError.IoFailure
      assert pendingIo() == 0 and disk.snapshot.error == DiskStoreError.FileFailure
  else:
    assert mode == 2 and completion.kind == DiskCompletionKind.NotExecuted
    assert disk.pagedRetirementPending # No IO entry cannot claim cleanup or fabricate a successful publication.
  resetIo()
  assert retained.lookup(key(0)).value.bytes == @[9'u8]
  if reader.opened: assert reader.close == FileError.None
  assert disk.close == FileError.None
  assert openLocalPagedDiskStateStore(disk, directory, config.chain, statePolicy(), config,
      transport(config)).error == DiskStoreError.None
  assert disk.commitPagedRetirement(preparePagedRetirement(disk).value).error == DiskStoreError.None
  assert disk.snapshot.value.lookup(key(0)).value.bytes == @[9'u8]
proc main() {.raises.} =
  ## Native facade behavior and complete application context restoration share one supported runner and exact fixture contract.
  normal()
  history()
  faults()
  lateBarrier()
  cachedMetadata()
  envelopeWitness()
  malformedEnvelope()
  retirementBackpressure()
  for mode in 0..2:
    # Every receipt path has success, genuine foreign-pin backpressure and actual IO refusal controls.
    for failure in 0..2: retirementWorker(mode, failure)
  echo "paged disk state store PASS"
try:
  main()
except:
  quit(2) # Fixture IO failure cannot masquerade as a passing history-restoration witness.
