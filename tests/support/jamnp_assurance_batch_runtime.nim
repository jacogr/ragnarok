# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine exported distributions outside current pending assignments exercise ordered durable CE139/140 snapshots, whole-request budgets and restarted ordinary TLS serving without canonical or signing authority.

import std/[assertions, monotimes, times, dirs, paths]
import ../../src/app/[services, options]
import ../../src/app/proof/[worker, network_read, assurance_storage]
import ../../src/jamnp-s/[assurance_store, assurance_record, availability_proof, availability_read,
  assurance_duty, read_stream]
import ../../src/codec/[bounded, assurances]
import ../../src/codec/work/report
import ../../src/state/availability/specifier
import ../../src/state/erasure/words
import "../../src/state/export/erasure" as export_erasure
import ./[jamnp_assurance_fixture, pvm_computed_report, jamnp_segment_batch_fixture,
  jamnp_assurance_read_runtime, storage_io]
type BatchFixture = object ## Original full erasure sources and expected bytes never enter the root-only serving job.
  source: AvailabilityCommitment
  packets: array[3, VerifiedAvailabilityTransfer]
  raw, proven: ReadRequest
  rawExpected, provenExpected: seq[byte]

proc frame(output: var seq[byte], payload: openArray[byte]) =
  ## Independent literal E4 framing preserves message boundaries and requested duplicate rows.
  for index in 0..<4: output.add(byte((uint32(payload.len) shr (index*8)) and 255))
  for octet in payload: output.add(octet)

proc policy(): AssuranceReadLimits =
  ## Restore totals apply to the whole request; the later output phase independently reserves its complete wire/proof workspace.
  let computation = AvailabilityMerkleLimits(bytes: ByteLimit(64000000), hashes: ElementLimit(100000),
    hashBytes: ByteLimit(64000000))
  AssuranceReadLimits(restore: AssuranceRestoreLimits(verification: computation,
    ioBytes: ByteLimit(64000000), workspaceBytes: ByteLimit(128000000)),
    reply: AvailabilityReadLimits(computation: computation, wireBytes: ByteLimit(16000000)),
    batchSources: ElementLimit(6144))

proc storagePolicy(): AssuranceStoreLimits =
  ## Three persisted coordinates have no eviction path and startup scans only their fixed namespace headers.
  AssuranceStoreLimits(entries: ElementLimit(3), scanEntries: ElementLimit(262),
    bytes: ByteLimit(64000000), record: AssuranceRecordLimits(bytes: ByteLimit(16000000),
      verification: policy().restore.verification))

proc batchFixture(): BatchFixture =
  ## Independently authored 65 exports make nonempty segment rows; original computation supplies each requested row and co-path.
  let source = computedAvailability(65)
  let specifier = source.availabilityInfo.value.specifier
  assert uint16(specifier.segmentCount) == 65 and uint16(specifier.erasureShards) == 6,
    "independent genuine nonempty export source"
  var packets = default(array[3, VerifiedAvailabilityTransfer])
  const shards = [0'u64, 4, 5]
  for index, shard in shards:
    # Only actual full distribution verification constructs each source to be persisted.
    let request = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
      root: specifier.erasureRoot, shard: ErasureShardIndex(shard))
    let prepared = prepareAvailabilityTransfer(source, request, policy().restore.verification).value
    packets[index] = verifyAvailabilityTransfer(specifier, request, prepared.bundleShard,
      prepared.segmentShards, prepared.justification, policy().restore.verification).value
  var payload = segmentGroup(ReadKind.SegmentShards, specifier.erasureRoot.bytes, 5, [64'u16, 0])
  for octet in segmentGroup(ReadKind.SegmentShards, specifier.erasureRoot.bytes, 0,
    [0'u16, 64, 0]): payload.add(octet)
  for octet in segmentGroup(ReadKind.SegmentShards, specifier.erasureRoot.bytes, 4,
    [1'u16]): payload.add(octet)
  var data: seq[byte] = @[]
  var proofs: seq[seq[byte]] = @[]
  const requestedShards = [5'u64, 5, 0, 0, 0, 4]
  const requestedRows = [64'u64, 0, 0, 64, 0, 1]
  for index in 0..<requestedShards.len:
    # The original guarantor erasure source is independent of the stored-proof reply builder being tested.
    let request = AvailabilityRequest(kind: AvailabilityTransferKind.Segment,
      root: specifier.erasureRoot, shard: ErasureShardIndex(requestedShards[index]),
      row: ExportErasureIndex(requestedRows[index]))
    let prepared = prepareAvailabilityTransfer(source, request, policy().reply.computation).value
    for octet in prepared.segmentShards: data.add(octet)
    proofs.add(prepared.justification)
  var rawExpected, provenExpected: seq[byte] = @[]
  frame(rawExpected, data)
  frame(provenExpected, data)
  for proof in proofs: frame(provenExpected, proof)
  BatchFixture(source: source, packets: move(packets),
    raw: decodeReadRequest(ReadKind.SegmentShards, payload).value,
    proven: decodeReadRequest(ReadKind.ProvenSegmentShards, payload).value,
    rawExpected: move(rawExpected), provenExpected: move(provenExpected))

proc waitDone(worker: var StateProofWorker) =
  ## Synchronized phase polling never observes or mutates leased archive graphs.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded durable batch completion"

proc waitDone(services: var Services) =
  ## Cached host state remains available until exact archive operation collection.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while services.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded batch namespace operation"

proc readBatch(worker: var StateProofWorker, store: var AssuranceStore,
    request: ReadRequest, limits: AssuranceReadLimits): ProofWorkerCompletion =
  ## Capture aliases retire before the existing worker owns its exact moved closed input.
  var job = captureAssuranceRead(store, request, limits).value
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid, "moved durable batch input"
  worker.waitDone()
  worker.collect(admitted.value)

proc direct(worker: var StateProofWorker, store: var AssuranceStore, fixture: BatchFixture) =
  ## Mixed shard order and duplicate rows survive one restore per distinct coordinate and ordinary proof derivation.
  let raw = readBatch(worker, store, fixture.raw, policy())
  assert raw.kind == ProofWorkerCompletionKind.ReadCompleted and raw.readValue.error ==
      ReadError.None and
    raw.readValue.value.bytes == fixture.rawExpected, "durable raw batch matches original requested rows"
  let proven = readBatch(worker, store, fixture.proven, policy())
  assert proven.kind == ProofWorkerCompletionKind.ReadCompleted and proven.readValue.error ==
      ReadError.None and
    proven.readValue.value.bytes == fixture.provenExpected, "durable proven batch matches original ordered co-paths"
  var disabled = policy()
  disabled.batchSources = ElementLimit(0)
  assert captureAssuranceRead(store, fixture.raw, disabled).error == ReadError.Unavailable,
    "audit-only activation never enables durable segment batches"
  var tooMany = policy()
  tooMany.batchSources = ElementLimit(6145)
  assert not tooMany.valid, "source policy cannot exceed NP stream item bound"
  let empty = decodeReadRequest(ReadKind.ProvenSegmentShards, []).value
  resetIo()
  let served = readBatch(worker, store, empty, policy())
  assert served.kind == ProofWorkerCompletionKind.ReadCompleted and served.readValue.error ==
      ReadError.None and
    served.readValue.value.bytes == @[0'u8, 0, 0, 0] and ioCalls(readIo) == 0,
    "empty enabled durable batch has one empty frame and no record IO"

proc exactPolicy(fixture: BatchFixture): AssuranceReadLimits =
  ## Independent total equations use real original geometry and the known three distinct sorted coordinates, including fixed206-byte header and174-byte checksum extents.
  result = policy()
  result.batchSources = ElementLimit(3)
  var io, hashes, hashBytes, resident, peak, verification = 0'u64
  for packet in fixture.packets:
    # Packets are deliberately ordered0/4/5, independently matching root/shard sort rather than requested row order.
    let work = availabilityVerificationInfo(packet.specifier, packet.request).value
    io += work.payloadBytes+413
    hashes += work.hashes+2
    hashBytes += work.hashBytes+348
    peak = max(peak, resident+work.payloadBytes*3+618)
    verification = max(verification, work.workspaceBytes)
    resident += work.payloadBytes
  let metadata = uint64(fixture.proven.itemCount)*128+3'u64*32 +
    uint64(fixture.proven.payloadLength)*2
  result.restore.ioBytes = ByteLimit(io)
  result.restore.verification.hashes = ElementLimit(hashes)
  result.restore.verification.hashBytes = ByteLimit(hashBytes)
  result.restore.verification.bytes = ByteLimit(verification)
  result.restore.workspaceBytes = ByteLimit(peak+metadata)

proc budgetChecks(worker: var StateProofWorker, store: var AssuranceStore,
    fixture: BatchFixture) =
  ## Exact totals accept a whole reply; each independent minus-one ceiling refuses the entire batch without faulting or evicting stored promises.
  let exact = exactPolicy(fixture)
  resetIo()
  limitReads(1)
  let positive = readBatch(worker, store, fixture.proven, exact)
  assert positive.kind == ProofWorkerCompletionKind.ReadCompleted and
    positive.readValue.error == ReadError.None and positive.readValue.value.bytes ==
        fixture.provenExpected,
    "exact whole-request durable restore limits"
  assert ioCalls(readIo) == uint64(exact.restore.ioBytes), "one-byte actual read count independently matches whole logical IO reservation"
  resetIo()
  for boundary in 0..<6:
    # Only one selected resource changes; no failed whole request may expose a data or proof prefix.
    var short = exact
    case boundary
    of 0: short.restore.ioBytes = ByteLimit(uint64(exact.restore.ioBytes)-1)
    of 1: short.restore.verification.hashes = ElementLimit(uint64(
        exact.restore.verification.hashes)-1)
    of 2: short.restore.verification.hashBytes = ByteLimit(uint64(
        exact.restore.verification.hashBytes)-1)
    of 3: short.restore.workspaceBytes = ByteLimit(uint64(exact.restore.workspaceBytes)-1)
    of 4: short.restore.verification.bytes = ByteLimit(uint64(exact.restore.verification.bytes)-1)
    else: short.batchSources = ElementLimit(2)
    let failed = readBatch(worker, store, fixture.proven, short)
    assert failed.kind == ProofWorkerCompletionKind.ReadCompleted and
      failed.readValue.error == ReadError.LimitExceeded, "whole durable batch refuses independent minus-one resource"
    assert store.len == 3 and not store.faulted, "batch policy refusal preserves healthy stored promises"
  var payload = fixture.proven.payload
  for octet in segmentGroup(ReadKind.ProvenSegmentShards, fixture.packets[0].request.root.bytes,
    6, [0'u16]): payload.add(octet)
  let missing = decodeReadRequest(ReadKind.ProvenSegmentShards, payload).value
  let failed = readBatch(worker, store, missing, policy())
  assert failed.kind == ProofWorkerCompletionKind.ReadCompleted and
    failed.readValue.error == ReadError.Unavailable and not store.faulted,
    "late missing sorted coordinate cannot return earlier restored batch prefix"
  var captureLimit = policy()
  captureLimit.restore.workspaceBytes = ByteLimit(uint64(fixture.proven.payloadLength)*2-1)
  resetIo()
  assert captureAssuranceRead(store, fixture.proven, captureLimit).error ==
      ReadError.LimitExceeded and
    ioCalls(readIo) == 0, "variable request pair is reserved before capture copying or record IO"

proc cancellation(worker: var StateProofWorker, store: var AssuranceStore, fixture: BatchFixture) =
  ## An atomic test gate pauses a real second read after one genuine byte; cancellation is installed before release, so cooperative early retirement is causal.
  let exact = exactPolicy(fixture)
  resetIo()
  limitReads(1)
  let positive = readBatch(worker, store, fixture.proven, exact)
  assert positive.kind == ProofWorkerCompletionKind.ReadCompleted and positive.readValue.error ==
      ReadError.None,
    "complete batch positive control before cancellation"
  let complete = ioCalls(readIo)
  resetIo()
  limitReads(1)
  assert holdReads(1) == 0, "quiescent one-shot read gate"
  defer: releaseReads() # Release precedes the caller's joined worker cleanup on every failure path.
  var job = captureAssuranceRead(store, fixture.proven, exact).value
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid, "moved controlled batch"
  let deadline = getMonoTime()+initDuration(seconds = 10)
  while readsHeld() == 0:
    # Only the atomic gate receipt is sampled while the IO thread is active; ordinary diagnostic counters remain untouched until join/collection.
    assert getMonoTime() < deadline, "actual read gate boundary reached"
  assert worker.phase == ProofWorkerPhase.Running and worker.cancel(admitted.value),
    "exact Running cancellation while actual archive read is held"
  releaseReads()
  worker.waitDone()
  assert worker.collect(admitted.value).kind == ProofWorkerCompletionKind.Cancelled,
    "cancelled durable snapshot exposes no complete or partial response"
  let partial = ioCalls(readIo)
  assert partial > 0 and partial < complete and store.len == 3 and not store.faulted,
    "cooperative cancellation stops before later records and preserves promises"
  resetIo()

proc maximumBatch(worker: var StateProofWorker, store: var AssuranceStore, fixture: BatchFixture) =
  ## Full6144-item reply order uses one actual record, with restore work capped to exactly one coordinate despite repeated requested rows.
  let packet = fixture.packets[0]
  var rows = newSeq[uint16](6144)
  let request = decodeReadRequest(ReadKind.ProvenSegmentShards,
    segmentGroup(ReadKind.ProvenSegmentShards, packet.request.root.bytes, 0, rows)).value
  let single = prepareAvailabilityTransfer(fixture.source,
    AvailabilityRequest(kind: AvailabilityTransferKind.Segment, root: packet.request.root,
      shard: packet.request.shard, row: ExportErasureIndex(0)), policy().reply.computation).value
  let chunk = single.segmentShards
  let proof = single.justification
  var data = newSeq[byte](chunk.len*6144)
  for ordinal in 0..<6144:
    for index in 0..<chunk.len: data[ordinal*chunk.len+index] = chunk[index]
  var expected: seq[byte] = @[]
  frame(expected, data)
  for ordinal in 0..<6144: frame(expected, proof)
  var exact = policy()
  assert expected.len <= 32*1024*1024, "full NP proof batch fits the independent32MiB method ceiling"
  exact.reply.wireBytes = ByteLimit(uint64(expected.len))
  exact.reply.computation.bytes = ByteLimit(128*1024*1024)
  let work = availabilityVerificationInfo(packet.specifier, packet.request).value
  exact.restore.ioBytes = ByteLimit(work.payloadBytes+413)
  exact.restore.verification.hashes = ElementLimit(work.hashes+2)
  exact.restore.verification.hashBytes = ByteLimit(work.hashBytes+348)
  let direct = serveSegmentShardBatch([packet], request, exact.reply)
  assert direct.error == ReadError.None, "maximum direct ordered reply: " & $direct.error
  let disk = store.restoreAssuranceShard(packet.request, exact.restore)
  assert disk.error == AssuranceStoreError.None, "maximum direct disk restore: " & $disk.error
  let served = readBatch(worker, store, request, exact)
  assert served.kind == ProofWorkerCompletionKind.ReadCompleted, "maximum batch read completion: " & $served.kind
  assert served.readValue.error == ReadError.None, "maximum batch read status: " &
      $served.readValue.error
  assert served.readValue.value.bytes == expected,
    "maximum batch proof bytes: actual " & $served.readValue.value.byteLength & " expected " & $expected.len

proc assuranceBatchRuntime*(settings: Options, canonical: AssuranceAcquisitionFixture,
    suffix: string) {.raises.} =
  ## An independently created namespace uses actual configured chain identity; public verified test roots need not appear among current pending reports.
  let folder = "assurance-batch-" & suffix
  try: removeDir(path(folder))
  except: assert false, "batch namespace initial cleanup"
  defer:
    try: removeDir(path(folder))
    except: assert false, "batch namespace joined cleanup"
  let fixture = batchFixture()
  let duty = captureAssuranceDuty(canonical.source, canonical.local,
    AssuranceDutyLimits(chapterBytes: ByteLimit(1000000), readBytes: ByteLimit(4000000),
      reports: ElementLimit(341), requests: ElementLimit(341*1023))).value
  for index in 0..<int(uint64(duty.dutyInfo.value.cores)):
    # Explicitly establish that serving this independently verified root does not borrow current C10 membership or claim historical GP admission.
    let assignment = duty.assignment(CoreIndex(index)).value
    if assignment.present:
      assert assignment.guarantee.report.ownedReportInfo.value.header.erasureRoot.bytes !=
        fixture.packets[0].request.root.bytes, "batch root is outside current canonical pending assignments"
  var services = default(Services)
  defer: services.close()
  assert services.start(settings, "durable batch namespace identity"), "independent full-state source"
  let creating = services.beginAssuranceStorage(folder, storagePolicy(),
      AssuranceStorageMode.Create).value
  services.waitDone()
  assert services.collectStateProof(creating).assuranceStorageValue.error ==
      AssuranceStoreError.None,
    "explicit namespace creation"
  let chain = services.assuranceStorageInfo.chain
  services.close() # Only the released native lock permits the independent test-owned population step.
  var store = default(AssuranceStore)
  defer: discard store.close()
  assert store.openAssuranceStore(folder, chain, storagePolicy()).error == AssuranceStoreError.None,
    "public exact namespace reopen"
  for packet in fixture.packets:
    assert store.rememberAssuranceShard(packet, AssuranceTime(1000)).error ==
        AssuranceStoreError.None,
      "only genuinely verified exported distributions enter persisted test data"
  var worker = default(StateProofWorker)
  defer: worker.close()
  assert worker.start(), "one bounded direct batch worker"
  direct(worker, store, fixture)
  budgetChecks(worker, store, fixture)
  cancellation(worker, store, fixture)
  maximumBatch(worker, store, fixture)
  worker.close()
  assert store.close().error == AssuranceStoreError.None, "direct borrowers retire before Services reacquires namespace"
  assert services.start(settings, "restarted durable segment server"), "full-state restart"
  let opening = services.beginAssuranceStorage(folder, storagePolicy(),
      AssuranceStorageMode.Open).value
  services.waitDone()
  assert services.collectStateProof(opening).assuranceStorageValue.error ==
      AssuranceStoreError.None and
    services.assuranceStorageInfo.records == 3, "actual three-root-coordinate restart accounting"
  assert services.beginNetworkRead(fixture.proven).error == StateProofAdmissionError.QueryFailure,
    "restart never silently activates durable segment serving"
  assert services.configureAssuranceReads(policy()), "explicit whole-request durable segment policy"
  assuranceReadRuntime(services, settings, canonical, fixture.raw, fixture.rawExpected,
    suffix & "-batch-raw", records = 3)
  assuranceReadRuntime(services, settings, canonical, fixture.proven, fixture.provenExpected,
    suffix & "-batch-proven", records = 3)
  assert not services.assuranceSigningConfigured, "public retained data grants no canonical signature authority"
  resetIo()
