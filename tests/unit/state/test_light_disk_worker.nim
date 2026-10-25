# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual shared disk-worker light operations retain exclusive graph leases, typed outcomes and joined native ownership.
import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../support/[arc_evidence, disk_history_context, application_checkpoint_context, storage_io]
import ../../../src/app/[disk_worker, light_store, light_head, checkpoint_identity,
    checkpoint_trust, chain]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, assurances, state_layout, state_trie]
import ../../../src/crypto/primitives
import ../../support/full_paged_native_fixture as fullfixture
import ../../../src/state/[disk_store, paged_state, store, trie_proof, proof_view, paged_proof_view]
import ../../../src/storage/light_state_cache as nativecache
import ../../../src/storage/[paged_store, paged_codec, paged_stream, paged_io, node_records,
    durability, file_errors]
proc headerWire(sourceBlock: BlockSnapshotResult): seq[byte] =
  ## Test-only complete snapshots supply independently chosen canonical header bytes, never partial-root inference.
  let selected = sourceBlock.value.header
  result = newSeq[byte](selected.headerInfo.value.consumed)
  assert encodeOwnedHeader(selected, result).error == HeaderError.None
proc trust(sourceBlock: BlockSnapshotResult): TrustedApplicationCheckpoint =
  ## Caller-selected identity/header inputs are captured before the light owner sees proof evidence.
  let owner = initApplicationChain(genesisView(sourceBlock)).value
  let identity = captureApplicationCheckpointIdentity(owner).value
  let encoded = encodeApplicationCheckpointIdentity(identity, ByteLimit(4096)).value
  let captured = captureCheckpointTrust(encoded, sourceBlock.headerWire, ByteLimit(1048576))
  assert captured.error == CheckpointTrustError.None
  captured.value
proc policy(sourceBlock: BlockSnapshotResult): LightHeadLimits =
  ## Active validator geometry is selected independently from complete genesis context, never inferred from fetch parameters or partial facts.
  LightHeadLimits(header: HeaderConfig(cores: sourceBlock.value.cores,
    authorValidators: sourceBlock.value.activeValidators, epochSlots: sourceBlock.value.epochSlots,
    maxBytes: ByteLimit(262144)), headers: ElementLimit(3), headerBytes: ByteLimit(1048576),
    view: ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(4194304)))
proc entries(snapshot: StateStoreSnapshot): seq[StateEntry] =
  ## An independent complete fixture map is used only to author genuine membership/absence proofs.
  result = @[]
  for index in 0..<snapshot.commitment.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    result.add(StateEntry(key: key, value: snapshot.lookup(key).value.bytes))
proc batch(snapshot: StateStoreSnapshot, keys: openArray[StateKey],
    limits: StateStoreLimits): VerifiedStateProofBatch =
  ## Full fixture generation and exact-root verification precede every partial view used by the application API.
  let perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(4194304))
  let aggregate = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(4096),
      valueBytes: ByteLimit(4194304))
  let generated = generateStateProofs(snapshot.entries, keys, limits.trie, perProof, aggregate)
  assert generated.error == StateProofError.None
  var queries = newSeq[StateProofQuery](generated.value.len)
  for index in 0..<queries.len: queries[index] = generated.value.queryAt(
      index).value # Immutable raw witnesses carry no trust until verified.
  let checked = verifyStateProofs(queries, snapshot.commitment.root, perProof, aggregate)
  assert checked.error == StateProofError.None
  checked.value
func key(value: byte): StateKey =
  ## High-byte fixture keys distinguish genuine absent witnesses from unrequested unknown facts.
  var bytes = default(array[31, byte])
  for index in 0..<bytes.len: bytes[index] = value
  StateKey(bytes)
proc path(label: string): string =
  ## Every trial owns a fresh ignored process namespace.
  "light-disk-worker-" & $storageProcessId() & "-" & label
proc limits(source: BlockSnapshotResult): LightPagedLimits =
  ## Finite native stream work and retention ceilings are independent from logical header/proof policy.
  let elements = ElementLimit(1000000)
  let bytes = ByteLimit(268435456)
  let work = PagedWorkLimits(ioCalls: elements, producerCalls: elements, pageHashes: elements,
    proofs: elements, nodes: elements, readBytes: bytes, writeBytes: bytes, valueBytes: bytes)
  result = default(LightPagedLimits)
  result.head = source.policy
  result.native.root = source.trust.identity.stateRoot
  result.native.limits = PagedStreamLimits(dataset: PagedLimits(entries: ElementLimit(16),
      bytes: bytes),
    workingBytes: ByteLimit(33554432), cachePages: ElementLimit(1), contextBytes: ByteLimit(
        4194304), work: work)
  result.native.limits.proof.nodes = ElementLimit(249)
  result.native.limits.proof.valueBytes = ByteLimit(4194304)
  result.contextBytes = ByteLimit(1048576)
  result.proofs.proof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(4194304))
  result.proofs.batch = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(4096),
      valueBytes: ByteLimit(4194304))
  result.proofs.view = source.policy.view
  result.proofs.work = work
  result.inventory = work
proc facts(fixture: DiskHistoryFixture, ordinal: int): VerifiedStateProofBatch =
  ## Only independent complete fixture snapshots author raw evidence; the light owner retains no complete store.
  batch(fixture.blocks[ordinal].value.stateSnapshot, [chapterKey(StateChapter(11)), key(255)],
      fixture.policy)
proc empty(source: BlockSnapshotResult): LightApplicationHead =
  ## Bootstrap knows no state facts until independently verified evidence is supplied.
  captureLightHead(source.trust, source.policy).value
proc noIo() =
  ## Passive dispatcher operations must not hide synchronous native work.
  for operation in [readIo, writeIo, syncIo, lockIo, closeIo, renameIo, unlinkIo]:
    assert ioCalls(operation) == 0 # Each syscall family remains independently observable.
proc check(snapshot: LightStorageSnapshot, count: int) =
  ## Missing witnesses never turn into authenticated absence, including after native close.
  assert snapshot.valid and snapshot.head.valid
  assert snapshot.head.proofView.len == count
  assert snapshot.head.proofView.lookup(key(254)).error == ProofViewError.MissingWitness
  if count > 0:
    # A successful absent lookup is available only after that exact query was supplied and verified.
    assert snapshot.head.proofView.lookup(chapterKey(StateChapter(11))).value.present
    assert not snapshot.head.proofView.lookup(key(255)).value.present
proc waitDone(worker: var DiskPublicationWorker) =
  ## Only synchronized scalar lifecycle state is touched while every borrowed ARC alias remains frozen.
  let started = getMonoTime()
  while worker.phase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 30 # Monotonic finite waits cannot silently accept a stranded borrow.
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield without observing any leased application/native owner.
proc publication(fixture: DiskHistoryFixture, mode: int, failure: bool, ordinal: int) {.raises.} =
  ## Normal collect, joined Done and immediate joined shutdown retain every actual light publication result.
  let source = fixture.blocks[0]
  let selected = source.limits
  let added = fixture.facts(0)
  let directory = path("publication-" & $mode & "-" & $failure & "-" & $ordinal)
  var disk = default(LightPagedStore)
  var worker = default(DiskPublicationWorker)
  defer:
    discard worker.close # Join before any job, store, head, view or witness alias retires.
    resetIo()
    if disk.opened: discard disk.close
  let retained = initializeLightPagedStore(disk, directory, source.empty, selected).value
  var job = prepareLightProofMerge(retained, added).value
  var emptyJob = default(PreparedLightPublication)
  assert job.ready and not emptyJob.ready
  assert worker.submit(disk, job).error == DiskWorkerError.Closed
  assert worker.start()
  assert worker.submit(disk, emptyJob).error == DiskWorkerError.NotReady
  if failure: armIo(writeIo, 0, 1, failedIo) # The first actual candidate write refuses on the excluded worker.
  let admitted = worker.submit(disk, job)
  assert admitted.error == DiskWorkerError.None
  assert worker.submit(disk, emptyJob).error == DiskWorkerError.Busy # Capacity refusal precedes any leased graph read.
  assert worker.collect(default(DiskPublicationTicket)).kind == DiskCompletionKind.Uninitialized
  var completion = default(DiskPublicationCompletion)
  if mode == 2:
    completion = worker.close # Only genuinely unexecuted queued work may omit an actual IO receipt.
  else:
    waitDone(worker)
    assert worker.submit(disk, emptyJob).error == DiskWorkerError.Busy # Done still owns capacity and the graph lease.
    if mode == 1:
      completion = worker.close # Joined Done preserves the distinct light outcome variant.
    else:
      completion = worker.collect(admitted.value)
      assert worker.collect(admitted.value).kind == DiskCompletionKind.Uninitialized # Tickets retire once.
  check(retained, 0)
  if completion.kind == DiskCompletionKind.LightCompleted:
    # Entered IO always returns its actual typed publication result, even when shutdown raced it.
    let outcome = completion.lightValue
    if failure:
      assert outcome.error == LightStoreError.NativeFailure and pendingIo() == 0
      assert disk.snapshot.error == LightStoreError.RecoveryRequired
    else:
      check(outcome.value, 2)
      check(disk.snapshot.value, 2)
      assert disk.retirementPending
      if mode == 0:
        # Reusing the fixed slot cannot turn a stale source job into another physical publication.
        resetIo()
        let stale = worker.submit(disk, job).value
        waitDone(worker)
        assert worker.collect(stale).lightValue.error == LightStoreError.StaleView
        noIo()
  else:
    assert mode == 2 and completion.kind == DiskCompletionKind.NotExecuted # No execution cannot grant publication authority.
    check(disk.snapshot.value, 0)
    assert not disk.retirementPending
  resetIo()
  discard worker.close
  assert worker.start()
  assert worker.collect(admitted.value).kind == DiskCompletionKind.Uninitialized # A restarted worker has a fresh ticket namespace.
  assert worker.close.kind == DiskCompletionKind.Uninitialized
  discard disk.close
  let restored = openLightPagedStore(disk, directory, source.trust, selected).value
  assert restored.head.proofView.len == 0 or restored.head.proofView.len == 2
  check(restored, restored.head.proofView.len)
proc retirement(fixture: DiskHistoryFixture, mode, failure, ordinal: int) {.raises.} =
  ## Separate cleanup outcomes preserve Busy, actual IO failure and absence success without granting a core publication receipt.
  let source = fixture.blocks[0]
  let selected = source.limits
  let added = fixture.facts(0)
  let directory = path("retirement-" & $mode & "-" & $failure & "-" & $ordinal)
  var disk = default(LightPagedStore)
  var reader = default(PagedReader)
  var worker = default(DiskPublicationWorker)
  defer:
    discard worker.close # Every source/target/cache alias stays frozen until actual native execution has joined.
    resetIo()
    if reader.opened: discard reader.close
    if disk.opened: discard disk.close
  let first = initializeLightPagedStore(disk, directory, source.empty, selected).value
  if failure == 1:
    # A separate physical old-reader pin excludes unlink independently of resident partial snapshots.
    assert openPagedReader(reader, directory, selected.native).error == PagedNativeError.None
  let retained = disk.commit(prepareLightProofMerge(first, added).value).value
  var job = disk.prepareLightRetirement.value
  var emptyJob = default(PreparedLightRetirement)
  assert job.ready and not emptyJob.ready
  assert worker.start()
  assert worker.submitRetirement(disk, emptyJob).error == DiskWorkerError.NotReady
  if failure == 2: armIo(readIo, 0, 1, failedIo) # Actual source-fence read uncertainty belongs to this worker operation.
  let admitted = worker.submitRetirement(disk, job)
  assert admitted.error == DiskWorkerError.None
  assert worker.submitRetirement(disk, emptyJob).error == DiskWorkerError.Busy
  var completion = default(DiskPublicationCompletion)
  if mode == 2:
    completion = worker.close # Joined queued work is NotExecuted; an entered cleanup retains its actual receipt.
  else:
    waitDone(worker)
    if mode == 1:
      completion = worker.close # Done cleanup remains LightRetired through joined shutdown.
    else:
      completion = worker.collect(admitted.value)
      assert worker.collect(admitted.value).kind == DiskCompletionKind.Uninitialized
  check(retained, 2)
  if completion.kind == DiskCompletionKind.LightRetired:
    # Cleanup has its own guarded result; failure never invalidates the earlier core publication outcome.
    let outcome = completion.lightRetirementValue
    if failure == 0:
      assert outcome.error == LightStoreError.None and not disk.retirementPending
      check(disk.snapshot.value, 2)
      if mode == 0:
        # A completed cleanup cannot be replayed through a stale passive job without fresh preparation.
        resetIo()
        let stale = worker.submitRetirement(disk, job).value
        waitDone(worker)
        assert worker.collect(stale).lightRetirementValue.error == LightStoreError.StaleView
        noIo()
    elif failure == 1:
      assert outcome.error == LightStoreError.NativeFailure and outcome.nativeFailure.fileError == FileError.Busy
      assert disk.retirementPending
      check(disk.snapshot.value, 2)
    else:
      assert outcome.error == LightStoreError.NativeFailure and pendingIo() == 0
      assert disk.snapshot.error == LightStoreError.RecoveryRequired
  else:
    assert mode == 2 and completion.kind == DiskCompletionKind.NotExecuted
    assert disk.retirementPending # A queued shutdown grants neither absence nor core publication authority.
  resetIo()
  discard worker.close
  if reader.opened: assert reader.close == FileError.None
  discard disk.close
  let restored = openLightPagedStore(disk, directory, source.trust, selected).value
  check(restored, 2)
  assert disk.retire(disk.prepareLightRetirement.value).error == LightStoreError.None
proc mixedOperations(fixture: DiskHistoryFixture) {.raises.} =
  ## One fixed worker reuses its slot across light publication, full retirement, light retirement and a different-root light advance.
  let source = fixture.blocks[0]
  let selected = source.limits
  let added = fixture.facts(0)
  let nextFacts = fixture.facts(1)
  let nextTrust = fixture.blocks[1].trust
  let nextView = captureProofView(nextFacts, nextTrust.identity.stateRoot, selected.head.view).value
  var light = default(LightPagedStore)
  var full = default(DiskStateStore)
  var worker = default(DiskPublicationWorker)
  defer:
    discard worker.close # Native execution must join before either distinct full/light database or any job retires.
    if light.opened: discard light.close
    if full.opened: discard full.close
  let lightDirectory = path("mixed-light")
  let first = initializeLightPagedStore(light, lightDirectory, source.empty, selected).value
  let fullPolicy = StateStoreLimits(trie: fullfixture.sample(5).config.limits.trie,
    writes: ElementLimit(4), writeValueBytes: ByteLimit(10000))
  let oldFull = newStateStore(@[StateEntry(key: key(0), value: @[5'u8])],
      fullPolicy).value.snapshot.value
  let nextFull = newStateStore(@[StateEntry(key: key(0), value: @[9'u8])],
      fullPolicy).value.snapshot.value
  var native = fullfixture.sample(5).config
  native.root = oldFull.commitment.root
  native.limits.contextBytes = ByteLimit(1024)
  let transport = PagedStateLimits(roots: ElementLimit(2), dataset: native.limits.dataset,
    staging: TrieExportLimits(records: TrieNodeLimit(10000), valueBytes: ByteLimit(10000)))
  assert initializePagedDiskStateStore(full, path("mixed-full"), oldFull, native,
    transport, [7'u8]).error == DiskStoreError.None
  assert full.commit(oldFull, nextFull, [9'u8], [oldFull]).error == DiskStoreError.None
  var fullJob = preparePagedRetirement(full).value
  var lightJob = prepareLightProofMerge(first, added).value
  assert worker.start()
  let lightTicket = worker.submit(light, lightJob).value
  waitDone(worker)
  let second = worker.collect(lightTicket).lightValue.value
  check(second, 2)
  let fullTicket = worker.submitRetirement(full, fullJob).value
  waitDone(worker)
  let fullCompletion = worker.collect(fullTicket)
  assert fullCompletion.kind == DiskCompletionKind.Retired and
      fullCompletion.retirementValue.error == DiskStoreError.None
  assert full.snapshot.value.lookup(key(0)).value.bytes == @[9'u8]
  var cleanup = light.prepareLightRetirement.value
  let cleanTicket = worker.submitRetirement(light, cleanup).value
  waitDone(worker)
  assert worker.collect(cleanTicket).lightRetirementValue.error == LightStoreError.None
  var advanced = prepareLightHeadAdvance(second, nextTrust, nextView).value
  let nextTicket = worker.submit(light, advanced).value
  waitDone(worker)
  let latest = worker.collect(nextTicket).lightValue.value
  check(latest, 2)
  assert latest.head.len == 2 and sameApplicationCheckpoint(latest.head.current.value.identity,
      nextTrust.identity)
  assert uint64(latest.manifest.sequence) == uint64(second.manifest.sequence)
  assert array[32, byte](latest.head.stateRoot) != array[32, byte](second.head.stateRoot)
  assert worker.close.kind == DiskCompletionKind.Uninitialized
  assert light.close == FileError.None
  check(openLightPagedStore(light, lightDirectory, nextTrust, fixture.blocks[1].limits).value, 2)
proc main() {.raises.} =
  ## Repeated native start/operation/collect-or-join/reopen cycles exercise actual resource lifetimes, not per-thread ARC counter sums.
  let fixture = diskHistoryFixture(1, false)
  mixedOperations(fixture)
  for mode in 0..2:
    # Every shutdown mode observes both successful and failed publication and all cleanup outcomes.
    publication(fixture, mode, false, 0)
    publication(fixture, mode, true, 0)
    for failure in 0..2: retirement(fixture, mode, failure, 0) # Success, independent Busy and native uncertainty.
  for ordinal in 1..24:
    # Reusing bounded workers and ticket namespaces cannot leave a native descriptor or borrowed graph live.
    publication(fixture, ordinal mod 3, false, ordinal)
    retirement(fixture, ordinal mod 3, ordinal mod 3, ordinal)
  echo "light disk worker PASS"
try:
  main()
except:
  quit(2) # Fixture/native/thread failures cannot count as passing exclusive ownership evidence.
