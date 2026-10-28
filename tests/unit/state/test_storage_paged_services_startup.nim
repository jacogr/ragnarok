# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual full Services startup selects a paged directory explicitly and binds only its intact V2 local state/context.
import std/assertions
import std/syncio
import std/envvars
import std/monotimes
import std/times
import std/posix/posix
import ../../support/storage_io
import ../../../src/app/disk_chain as app_disk_chain
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/app/disk_history as app_disk_history
import ../../../src/app/paged_policy as app_paged_policy
import ../../../src/state/disk_store as state_disk_store
import ../../../src/storage/file_repository as storage_file_repository
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/full_paged_store as storage_full_paged_store
import ../../../src/storage/database_identity as storage_database_identity
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/chain/parameters as chain_parameters
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/chain as app_chain
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
import ../../../src/app/checkpoint_codec as app_checkpoint_codec
import ../../../src/app/checkpoint_recovery as app_checkpoint_recovery
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/state/store as state_store
import ../../support/app_checkpoint_context
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
proc appPid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Process-private application namespaces preserve earlier forensic artifacts without stale test collisions.
proc configured(path: string, layout: string, resume = false, readOnly = false): Options =
  ## Harness-owned configured genesis and explicit replay policy are captured before listeners or storage become observable.
  var arguments = @["server", "--with-state", "--chain", getEnv("RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-storage", "disk", "--state-db", path, "--state-layout", layout]
  if resume: arguments.add("--state-paged-resume") # Test authority must be explicitly present in the actual CLI request.
  if readOnly:
    arguments.add("--state-writes"); arguments.add("0")
    arguments.add("--state-write-bytes"); arguments.add(
        "0") # Independent imports retain their exact zero-budget recovery policy.
  result = default(Options)
  assert parseCanonicalOptions(arguments, result)
proc imported() {.raises.} =
  ## Independently trusted checkpoint import creates exclusively; ordinary local restart preserves its selected header instead of genesis.
  let source = checkpointFixture(CheckpointFixtureVariant.Header)
  let expected = captureApplicationCheckpointIdentity(source).value
  let original = captureApplicationCheckpointIdentity(checkpointFixture()).value
  assert not sameApplicationCheckpoint(expected, original)
  let envelope = encodeApplicationCheckpoint(source, ByteLimit(4194304)).value
  let selectedHeader = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](selectedHeader.headerInfo.value.consumed)
  assert encodeOwnedHeader(selectedHeader, wire).error == HeaderError.None
  let recovered = decodeRecoveryCheckpoint(envelope, wire, expected, genesisStoreLimits(),
      ByteLimit(4194304))
  let path = "paged-services-import-" & $appPid()
  var selected = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-storage", "disk", "--state-layout", "paged", "--state-db", path,
    "--state-writes", "0", "--state-write-bytes", "0"], selected)
  var owner = default(Services)
  defer: owner.close() # Every rejected or successful recovery startup joins every worker and retires its lease.
  let absent = default(ApplicationRecoveryResult)
  assert not owner.startRecovered(selected, "missing independent trust", absent)
  assert owner.startRecovered(selected, "trusted paged import", recovered)
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
  assert owner.start(selected, "local paged import restart")
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
  assert not owner.startRecovered(selected, "no imported overwrite", recovered)
  owner.close()
  assert owner.start(selected, "preserved imported head")
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
proc waitRetirement(owner: var Services) =
  ## Scalar polling waits for worker completion before tick resumes any graph-bearing canonical/RPC access.
  let started = getMonoTime()
  while owner.diskPublicationPhase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield under an independent monotonic harness deadline.
  owner.tick(0)
proc retirement(mode: int) {.raises.} =
  ## Startup reconstructs one exact pending predecessor; cleanup preserves canonical identity and core publication receipts.
  let path = "paged-services-retirement-" & $appPid() & "-" & $mode
  let selected = configured(path, "paged")
  var owner = default(Services)
  var disk = default(DiskStateStore)
  var reader = default(FullPagedReader)
  defer:
    owner.close() # Join first, then release any independent old reader and test-only writer lease.
    resetIo()
    if reader.opened: discard reader.close
    if disk.opened: discard disk.close
  assert owner.start(selected, "paged retirement seed")
  let seed = initApplicationChain(owner.chainView).value
  let trusted = captureApplicationCheckpointIdentity(seed).value
  owner.close()
  var policy = genesisStoreLimits()
  policy.writes = selected.stateWrites
  policy.writeValueBytes = selected.stateWriteBytes
  var identity: seq[byte] = @[]
  for character in "RAGNAROK-CHAIN-V1\n": identity.add(byte(
      character)) # Independent fixture chain identity uses configured genesis authority.
  for octet in array[32, byte](seed.chainView.bestBlock.value.blockHash): identity.add(octet)
  for octet in array[32, byte](seed.stateSnapshot.value.commitment.root): identity.add(octet)
  for octet in seed.chainView.bestBlock.value.chainParameters.encodeParameters: identity.add(octet)
  let chain = StorageChainId(array[32, byte](blake2b256(identity).value))
  let journal = JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: policy.trie,
    records: TrieExportLimits(records: TrieNodeLimit(1048576), valueBytes: ByteLimit(4194304)),
    encoded: ByteLimit(67108864)), records: ElementLimit(4194304), valueBytes: ByteLimit(
        134217728)),
    bytes: ByteLimit(268435456), contextBytes: ByteLimit(4194304))
  let bounded = pagedApplicationPolicy(chain, seed.stateSnapshot.value.commitment.root, journal)
  assert openLocalPagedDiskStateStore(disk, path, chain, policy, bounded.native,
      bounded.transport).error == DiskStoreError.None
  if mode == 1:
    # This independent physical pin survives publication and startup; resident application snapshots hold no such pins.
    assert openFullPagedReader(reader, path, bounded.native).error == FullPagedNativeError.None
  let before = disk.snapshot.value
  let context = encodeDiskHistory(seed, chain, RepositoryGeneration(2), bounded.contextBytes).value
  assert disk.commit(before, before, context).error == DiskStoreError.None
  assert disk.close == FileError.None
  assert owner.start(selected, "pending paged retirement restart")
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, trusted)
  let current = readFile(path & "/CURRENT")
  resetIo()
  if mode == 2: armIo(readIo, 0, 1, failedIo) # Only the worker's actual retirement source fence consumes this failure.
  if mode == 3:
    assert owner.beginDiskRetirement()
    owner.stopDiskPublication() # Joined shutdown retains actual retirement or queued NotExecuted; no fabricated core publication.
    assert owner.diskRetirementCompletion.kind in {DiskCompletionKind.Retired,
        DiskCompletionKind.NotExecuted}
  else:
    owner.tick(0) # Automatic retirement has priority before staging any new paged publication.
    assert owner.diskPublicationActive
    waitRetirement(owner)
    let completion = owner.diskRetirementCompletion
    assert completion.kind == DiskCompletionKind.Retired
    let outcome = completion.retirementValue
    if mode == 0:
      assert outcome.error == DiskStoreError.None
      assert not owner.beginDiskRetirement() # No second unlink attempt is scheduled after confirmed retirement.
    elif mode == 1:
      assert outcome.error == DiskStoreError.FileFailure and outcome.fileError == FileError.Busy
      owner.tick(0)
      assert not owner.diskPublicationActive # Immediate ticks respect the one-second retry delay instead of spinning on the pin.
      assert reader.close == FileError.None
      assert owner.beginDiskRetirement() # Explicit retry uses the same slot and exact authenticated target.
      waitRetirement(owner)
      assert owner.diskRetirementCompletion.retirementValue.error == DiskStoreError.None
    else:
      assert outcome.error == DiskStoreError.FileFailure and outcome.fileError ==
          FileError.IoFailure
      assert pendingIo() == 0 and not owner.beginDiskRetirement() # Cleanup uncertainty stops further writes until fresh startup.
  resetIo()
  assert not owner.diskPublicationActive
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, trusted)
  assert owner.diskPublicationOutcome.error == DiskChainError.Uninitialized
  assert readFile(path & "/CURRENT") == current # Cleanup never changes the already confirmed canonical selection.
  owner.close()
  assert owner.start(selected, "retirement restart retry")
  owner.tick(0)
  assert owner.diskPublicationActive # The durable descriptor survives; exact old absence is resolved with a real barrier.
  waitRetirement(owner)
  assert owner.diskRetirementCompletion.retirementValue.error == DiskStoreError.None
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, trusted)
proc replayPresentNative(name: cstring, mode: cint): cint {.importc: "access", cdecl,
    header: "<unistd.h>".}
  ## Fixture-only metadata distinguishes a missing CURRENT from an existing partial bootstrap child.
proc replayPresent(path: string): bool =
  ## Known test paths are checked individually; no directory discovery grants recovery permission.
  var owned = path
  replayPresentNative(owned.toCString(), 0) == 0
proc recoveredFixture(variant: CheckpointFixtureVariant): ApplicationRecoveryResult {.raises.} =
  ## Independent caller-selected checkpoint identity/header authority remains separate from local forensic bytes.
  let source = checkpointFixture(variant)
  let identity = captureApplicationCheckpointIdentity(source).value
  let envelope = encodeApplicationCheckpoint(source, ByteLimit(4194304)).value
  let selected = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](selected.headerInfo.value.consumed)
  assert encodeOwnedHeader(selected, wire).error == HeaderError.None
  decodeRecoveryCheckpoint(envelope, wire, identity, genesisStoreLimits(), ByteLimit(4194304))
proc resumedStartup(importing: bool) {.raises.} =
  ## Only explicit resume can complete matching interrupted genesis/import; wrong independent context and existing CURRENT remain protected.
  let path = "paged-services-resume-" & $appPid() & "-" & $importing
  let plain = configured(path, "paged", readOnly = importing)
  let resumed = configured(path, "paged", resume = true, readOnly = importing)
  let variant = if importing: CheckpointFixtureVariant.Header else: CheckpointFixtureVariant.Original
  let expected = captureApplicationCheckpointIdentity(checkpointFixture(variant)).value
  let recovered = recoveredFixture(variant)
  var owner = default(Services)
  defer:
    owner.close() # Every partial or complete startup joins workers before source aliases and the writer lease retire.
    resetIo()
  resetIo()
  armIo(renameIo, 0, 1, failedIo)
  let created = if importing: owner.startRecovered(plain, "interrupted trusted import", recovered)
    else: owner.start(plain, "interrupted configured genesis")
  assert not created and pendingIo() == 0
  owner.close()
  resetIo()
  assert not replayPresent(path & "/CURRENT")
  let candidate = path & "/paged-0000000000000001.bin"
  let staging = path & "/CURRENT.next"
  let bytes = readFile(candidate)
  let next = readFile(staging)
  let ordinary = if importing: owner.startRecovered(plain, "ordinary import refuses overwrite", recovered)
    else: owner.start(plain, "ordinary startup preserves bootstrap forensics")
  assert not ordinary
  owner.close()
  assert readFile(candidate) == bytes and readFile(staging) == next
  if importing:
    # Same complete map/root and equal-sized headers still require the exact independently chosen application context.
    let wrong = recoveredFixture(CheckpointFixtureVariant.Original)
    assert not owner.startRecovered(resumed, "wrong independent imported header", wrong)
    owner.close()
    assert not replayPresent(path & "/CURRENT")
    assert readFile(candidate) == bytes and readFile(staging) == next
  let completed = if importing: owner.startRecovered(resumed, "explicit trusted import resume", recovered)
    else: owner.start(resumed, "explicit configured genesis resume")
  assert completed and sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
  let current = readFile(path & "/CURRENT")
  assert owner.start(plain, "ordinary strict startup after explicit resume")
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
  if importing:
    # Explicit resume remains bootstrap-only and cannot replace an already selected imported head.
    assert not owner.startRecovered(resumed, "no selected database overwrite", recovered)
    owner.close()
    assert readFile(path & "/CURRENT") == current
  else:
    # The same explicit flag remains usable for a fresh destination; ordinary exclusive initialization succeeds first.
    let fresh = configured(path & "-fresh", "paged", resume = true)
    assert owner.start(fresh, "fresh explicit paged run")
    owner.close()
proc main() {.raises.} =
  ## Exclusive locking and wrong-layout/corrupt-CURRENT refusals never replace an existing selected epoch.
  let path = "paged-services-startup-" & $appPid()
  var owner = default(Services)
  var competitor = default(Services)
  defer:
    competitor.close()
    owner.close()
  let selected = configured(path, "paged")
  assert owner.start(selected, "validator")
  let before = owner.chainView.bestBlock.value
  assert not competitor.start(selected, "validator")
  competitor.close()
  owner.close()
  assert owner.start(selected, "validator")
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      before.blockHash)
  assert array[32, byte](owner.chainView.bestBlock.value.stateRoot) == array[32, byte](
      before.stateRoot)
  assert owner.chainView.retainedCount == 1
  assert owner.chainView.finalizedBlock.error == GenesisError.Unavailable
  owner.close()
  let current = path & "/CURRENT"
  let intact = readFile(current)
  assert not owner.start(configured(path, "journal"), "validator")
  owner.close()
  assert readFile(current) == intact
  assert not owner.start(configured(path, "managed"), "validator")
  owner.close()
  assert readFile(current) == intact
  var corrupt = intact
  corrupt[corrupt.high] = char(ord(corrupt[corrupt.high]) xor 1)
  writeFile(current, corrupt)
  assert not owner.start(selected, "validator")
  owner.close()
  assert readFile(current) == corrupt # Normal startup cannot reset or fall back after integrity refusal.
  writeFile(current, intact)
  assert owner.start(selected, "validator")
  owner.close()
  imported()
  resumedStartup(false)
  resumedStartup(true)
  for mode in 0..3: retirement(mode) # Genuine startup and the shared excluded worker cover all cleanup outcomes.
  # Exact native directories remain under the ignored runner working path for inspection.
try:
  main()
except:
  quit(2)
echo "PASS paged services startup: V2 full context, local restart, lock and wrong-layout/corrupt-head refusal"
