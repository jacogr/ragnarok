# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real child-process exits and kernel-limited native writes verify the canonical durability boundary.
import std/assertions
import std/envvars
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../support/chain_durable_chain_context
import ../../support/state_accumulation_completion_context
import ../../support/state_accumulation_provision_integration
import ../../../src/app/chain as app_chain
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/app/disk_history as app_disk_history
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
import ../../../src/state/accumulation_publication as state_accumulation_publication
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/storage/journal_codec as storage_journal_codec
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/report_owned as codec_report_owned
type
  ResourceLimit {.importc: "struct rlimit", header: "<sys/resource.h>", bycopy.} = object
    ## Exact supported 64-bit SDK fields constrain only the forked writer.
    current {.importc: "rlim_cur".}: uint64
    maximum {.importc: "rlim_max".}: uint64
  SignalHandler = proc(value: cint) {.cdecl, raises: [].} ## Nonallocating callback keeps kernel refusal observable.
let fileLimit {.importc: "RLIMIT_FSIZE", header: "<sys/resource.h>".}: cint
let sizeSignal {.importc: "SIGXFSZ", header: "<signal.h>".}: cint
let signalError {.importc: "SIG_ERR", header: "<signal.h>".}: SignalHandler
proc getLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "getrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Inspect the inherited hard ceiling before selecting a smaller soft limit.
proc setLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "setrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Change only the isolated child, never the native runner's resource budget.
proc install(signal: cint, handler: SignalHandler): SignalHandler {.importc: "signal", cdecl,
    header: "<signal.h>".}
  ## Keep SIGXFSZ as a typed write error rather than accepting signal termination as evidence.
proc ignore(value: cint) {.cdecl, raises: [].} =
  ## Signal handling performs no allocation, output or storage operation.
  discard

proc journalLimits(): JournalLimits =
  ## Explicit broad fixture ceilings bound all physical records, individual batches and history context.
  JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(
    items: ElementLimit(100000), perValue: ByteLimit(1048576), totalValueBytes: ByteLimit(16777216),
    nodes: TrieNodeLimit(1000000)), records: TrieExportLimits(records: TrieNodeLimit(1000000),
      valueBytes: ByteLimit(16777216)), encoded: ByteLimit(33554432)),
    records: ElementLimit(2000000), valueBytes: ByteLimit(67108864)),
    bytes: ByteLimit(134217728), contextBytes: ByteLimit(1048576))
proc waitDone(worker: var DiskPublicationWorker) =
  ## Only scalar worker state is touched while every leased ARC alias remains frozen.
  let started = getMonoTime()
  while worker.phase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20, "bounded native completion"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield under a monotonic bounded test deadline.
proc attempt(seed: ApplicationChain, prepared: PreparedChainUpdate, mode: int) {.raises.} =
  ## No parent thread exists at fork; each child independently reopens its exclusive journal lock.
  let chain = default(StorageChainId)
  let limits = journalLimits()
  let policy = integrationStoreLimits()
  var path = "disk-publication-crash.db"
  var setup = default(DiskStateStore)
  defer:
    if setup.opened: discard setup.close # Parent cleanup never relies on child destructors.
  let before = initializeDiskChain(setup, path, chain, seed, limits).value
  assert setup.close == FileError.None
  defer: discard posix.unlink(path.toCString())
  let original = readFile(path)
  let target = initApplicationChain(prepared.chainView).value
  let context = encodeDiskHistory(target, chain, RepositoryGeneration(uint64(before)+1),
    limits.contextBytes).value
  let batch = exportStateChanges(seed.stateSnapshot.value, prepared.stateSnapshot,
    limits.repository.codec.records).value
  let frame = encodeContextJournalFrame(RepositoryGeneration(uint64(before)+1), batch, context,
    limits.contextBytes, limits.repository.codec, limits.bytes).value
  let extra = if mode == 4: 0 elif mode == 5: 1 elif mode == 6: frame.len div 2
    elif mode == 7: frame.len-1 else: frame.len
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var disk = default(DiskStateStore)
    # Source certificates retain their original immutable parent owner across fork. The child
    # acquires a fresh journal and publishes the same deterministic seed before native IO starts.
    if posix.unlink(path.toCString()) != 0: posix.exitnow(3)
    var owner = seed
    discard initializeDiskChain(disk, path, chain, owner, limits).value
    var publication = prepareDiskPublication(disk, owner, prepared, chain,
        limits.contextBytes).value
    if mode == 0: posix.exitnow(0) # Staged context alone has made no successor durable.
    if mode >= 4:
      var selected = default(ResourceLimit)
      let ceiling = uint64(original.len)+uint64(extra)
      if getLimit(fileLimit, addr selected) != 0 or ceiling > selected.maximum: posix.exitnow(4)
      if install(sizeSignal, ignore) == signalError: posix.exitnow(5)
      selected.current = ceiling
      if setLimit(fileLimit, addr selected) != 0: posix.exitnow(6)
    var worker = default(DiskPublicationWorker)
    if not worker.start(): posix.exitnow(7)
    let ticket = worker.submit(disk, publication).value
    worker.waitDone()
    if mode == 1: posix.exitnow(0) # Durable Done survives even though the host never collects its receipt.
    let completion = worker.collect(ticket)
    if completion.kind != DiskCompletionKind.Completed: posix.exitnow(8)
    if mode in 4..7:
      if completion.value.error != DiskChainError.StoreFailure: posix.exitnow(9)
      if completion.value.storeFailure.error != DiskStoreError.FileFailure or
          completion.value.storeFailure.fileError != FileError.IoFailure: posix.exitnow(10)
      if disk.snapshot.fileError != FileError.RecoveryRequired: posix.exitnow(11)
    else:
      if completion.value.error != DiskChainError.None: posix.exitnow(12)
      if mode == 3: owner.installPrepared(publication.chainUpdate)
    posix.exitnow(0) # Deliberately bypass worker/disk/canonical destructors to exercise process durability.
  var joined = false
  defer:
    if not joined:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0)
  var statusCode = 0.cint
  assert posix.waitpid(child, statusCode, 0) == child
  joined = true
  assert WIFEXITED(statusCode) and WEXITSTATUS(statusCode) == 0, "child boundary " & $mode &
      " status " & $statusCode
  let interrupted = readFile(path)
  assert interrupted[0..<original.len] == original
  var disk = default(DiskStateStore)
  defer:
    if disk.opened: discard disk.close # Every parent-side validation refusal releases ownership.
  if mode in 5..7:
    let refused = openDiskChain(disk, path, chain, seed.chainView.bestBlock.value.chainParameters,
      policy, limits)
    assert refused.error == DiskChainError.StoreFailure
    assert refused.storeFailure.fileError == FileError.InvalidJournal
    assert not disk.opened and readFile(path) == interrupted
    discard recoverDiskStateStore(disk, path, chain, seed.stateSnapshot.value.commitment.root,
      before, policy, limits, StorageSchema.FullStateV1).value
    assert disk.close == FileError.None
    assert readFile(path) == original
  let succeeds = mode in 1..3 or mode == 8
  if succeeds:
    let refused = recoverDiskStateStore(disk, path, chain, seed.stateSnapshot.value.commitment.root,
      before, policy, limits, StorageSchema.FullStateV1)
    assert refused.error == DiskStoreError.FileFailure
    assert refused.fileError == FileError.RecoveryMismatch
    assert not disk.opened and readFile(path) == interrupted # A complete successor can never be rolled back as a tail.
  let restored = openDiskChain(disk, path, chain, seed.chainView.bestBlock.value.chainParameters,
    policy, limits).value
  let expected = if succeeds: prepared.stateSnapshot else: seed.stateSnapshot.value
  assert array[32, byte](restored.stateSnapshot.value.commitment.root) == array[32, byte](
      expected.commitment.root)
  assert restored.chainView.retainedCount == (if succeeds: 2 else: 1)
  assert uint64(disk.generation.value) == uint64(before)+(if succeeds: 1'u64 else: 0'u64)
  assert sameStateSnapshot(restored.stateSnapshot.value, disk.snapshot.value)
proc main() {.raises.} =
  ## Native file limits are isolated to child processes; the runner's file and signal policies stay intact.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let fixture = durableFixture(decodeOwnedReport(bytes, 2).value)
  let seed = initApplicationChain(genesisView(fixture.parent)).value
  let prepared = seed.prepareAccumulation(fixture.source, completionLimits().composition).value
  for mode in 0..8: attempt(seed, prepared, mode)
try:
  main()
except:
  quit(2) # Missing fixtures and failed child setup cannot satisfy crash-boundary witnesses.
echo "PASS disk publication crash: staged/durable/install exits, real partial writes, exact repair and no complete rollback"
