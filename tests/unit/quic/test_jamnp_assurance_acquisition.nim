# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_assurance_acquisition_arc_release"}

## Actual computed-chain pending guarantees select canonical CE137 shards before real durable retention; native Services/worker leases preserve unpublished results, counters and promises through cancellation and join.
import std/[assertions, syncio, dirs, paths, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/proof/[worker, assurance_storage, assurance_acquisition, network_read]
import ../../../src/jamnp-s/[assurance_store, assurance_record, assurance_duty, availability_proof,
    availability_read, read_stream]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, assurances]
import ../../../src/codec/work/report
import ../../../src/state/availability/specifier
import ../../../src/lib/atomic/file
import ../../../src/rpc/server
import ../../support/[jamnp_assurance_fixture, jamnp_assurance_audit_runtime,
    current_application_context, storage_io, arc_evidence]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Count actual crypto attempts and inject only explicitly selected maintained-backend failure.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observations are read only after synchronous execution or exact native retirement.
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield under bounded monotonic deadlines without touching leased graphs or mutable IO observers.
proc limits(): AssuranceAcquisitionLimits =
  ## Full source qualification and incoming proof work are independent of raw-wire and worst-case duplicate-restore/encoding workspace ceilings.
  AssuranceAcquisitionLimits(duty: AssuranceDutyLimits(chapterBytes: ByteLimit(1000000),
    readBytes: ByteLimit(4000000), reports: ElementLimit(341), requests: ElementLimit(341*1023)),
    verification: AvailabilityMerkleLimits(bytes: ByteLimit(64000000), hashes: ElementLimit(100000),
      hashBytes: ByteLimit(64000000)), wireBytes: ByteLimit(16000000), workspaceBytes: ByteLimit(128000000))
proc storageLimits(): AssuranceStoreLimits =
  ## One retained coordinate covers duplicate renewal and exposes accidental extra publication without evicting a promise.
  AssuranceStoreLimits(entries: ElementLimit(1), scanEntries: ElementLimit(260), bytes: ByteLimit(
      64000000),
    record: AssuranceRecordLimits(bytes: ByteLimit(16000000), verification: limits().verification))
proc clean(folder: string) =
  ## Only exact test-owned folders are removed after every borrower and descriptor has retired.
  try: removeDir(path(folder))
  except: assert false, "acquisition fixture cleanup"
proc frame(output: var seq[byte], payload: openArray[byte]) =
  ## Independent literal E4 framing witnesses the complete message order and empty export-list representation.
  for index in 0..<4: output.add(byte((uint32(payload.len) shr (8*index)) and 255))
  for octet in payload: output.add(octet)
proc wire(fixture: AssuranceAcquisitionFixture): seq[byte] =
  ## Retain availability only from the original genuinely admitted computation; expected request comes from the actual published parent.
  let duty = captureAssuranceDuty(fixture.source, fixture.local, limits().duty)
  assert duty.error == AssuranceDutyError.None, "genuine published canonical duty"
  let request = duty.value.shardRequest(CoreIndex(0), 0)
  assert request.error == AssuranceDutyError.None, "actual local canonical assignment"
  let prepared = prepareAvailabilityTransfer(fixture.availability, request.value, limits().verification)
  assert prepared.error == AvailabilityTransferError.None, "original admitted report erasure provenance"
  result = @[]
  frame(result, prepared.value.bundleShard)
  frame(result, prepared.value.segmentShards)
  frame(result, prepared.value.justification)
type AuditFixture = object ## Independently framed expected original audit bytes are never supplied to the serving worker.
  request: ReadRequest
  expected: seq[byte]
proc servingLimits(): AssuranceReadLimits =
  ## Restore and later audit derivation have independent finite budgets; neither policy loads a key or opens storage.
  AssuranceReadLimits(restore: AssuranceRestoreLimits(verification: limits().verification,
    ioBytes: ByteLimit(64000000), workspaceBytes: ByteLimit(128000000)),
    reply: AvailabilityReadLimits(computation: limits().verification, wireBytes: ByteLimit(8000000)))
proc auditFixture(fixture: AssuranceAcquisitionFixture): AuditFixture =
  ## Select an original canonical coordinate, then independently compute its two-frame audit response from the genuine original guarantor erasure source.
  var selected = captureAssuranceDuty(fixture.source, fixture.local,
    limits().duty).value.shardRequest(CoreIndex(0), 0).value
  selected.kind = AvailabilityTransferKind.Audit
  let prepared = prepareAvailabilityTransfer(fixture.availability, selected, limits().verification)
  assert prepared.error == AvailabilityTransferError.None, "original genuine audit derivation"
  var request = default(array[34, byte])
  for index in 0..<32: request[index] = selected.root.bytes[index]
  request[32] = byte(uint64(selected.shard) and 255)
  request[33] = byte((uint64(selected.shard) shr 8) and 255)
  var expected: seq[byte] = @[]
  frame(expected, prepared.value.bundleShard)
  frame(expected, prepared.value.justification)
  AuditFixture(request: decodeReadRequest(ReadKind.Audit, request).value, expected: expected)
proc captured(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture,
    input: openArray[byte], now: uint64, policy: AssuranceAcquisitionLimits): AssuranceAcquisitionJob =
  ## Temporary factory/result and source aliases retire before native submit moves this final private input.
  let admitted = captureAssuranceAcquisition(owner, fixture.source, fixture.chain, fixture.local,
    CoreIndex(0), 0, input, AssuranceTime(now), policy)
  assert admitted.error == AssuranceAcquisitionError.None, "complete acquisition capture"
  admitted.value
proc execute(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture,
    input: openArray[byte], now = 1000'u64, policy = limits()): AssuranceAcquisitionResult[
        AssuranceAcquisitionInfo] =
  ## Synchronous boundary tests never have a second thread touching any retained source, result or native owner.
  let job = captured(owner, fixture, input, now, policy)
  executeAssuranceAcquisition(job, default(AssuranceScanControl))
proc capturedProbe(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture,
    now: uint64, policy: AssuranceAcquisitionLimits): AssuranceAcquisitionJob =
  ## Retire every source/capture wrapper before the native owner may execute a closed existing-coordinate lookup.
  let staged = captureAssuranceProbe(owner, fixture.source, fixture.chain, fixture.local,
    CoreIndex(0), 0, AssuranceTime(now), policy)
  assert staged.error == AssuranceAcquisitionError.None, "complete canonical probe capture"
  staged.value
proc probe(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture,
    now: uint64, policy: AssuranceAcquisitionLimits): AssuranceAcquisitionResult[
        AssuranceAcquisitionInfo] =
  ## Direct checks execute the same closed operation used by the managed worker, with no substitute storage or possession marker.
  let job = capturedProbe(owner, fixture, now, policy)
  executeAssuranceAcquisition(job, default(AssuranceScanControl))
proc waitDone(worker: var StateProofWorker) =
  ## Only the synchronized phase is polled while the native worker owns all canonical/record aliases.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while worker.phase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded acquisition completion"
    discard pauseMicros(100)
proc waitDone(owner: var Services) =
  ## Cached scalar status and unrelated host ticks remain safe while the namespace/canonical lease is held.
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < deadline, "bounded managed acquisition completion"
    owner.tick(0)
    discard pauseMicros(100)
proc stopping(context: nil pointer): bool {.nimcall, raises: [].} =
  ## An explicitly stopped synchronous control cannot publish data or return partial possession.
  true
proc ordinary(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture, input: seq[byte]) =
  ## Deep raw input ownership, exact complete framing, whole preflight and actual proof refusal all precede publication.
  var copyBudget = limits()
  copyBudget.workspaceBytes = ByteLimit(uint64(input.len)*2-1)
  reset(0)
  assert captureAssuranceAcquisition(owner, fixture.source, fixture.chain, fixture.local, CoreIndex(
      0), 0,
    input, AssuranceTime(1000), copyBudget).error == AssuranceAcquisitionError.LimitExceeded, "both raw owners are charged before cloning even before frame verification"
  assert calls() == 0, "raw copy admission hashes nothing"
  block:
    # Exact clone admission is independent from the later, larger whole proof/storage buffer reservation.
    copyBudget.workspaceBytes = ByteLimit(uint64(input.len)*2)
    assert captureAssuranceAcquisition(owner, fixture.source, fixture.chain, fixture.local,
        CoreIndex(0), 0,
      input, AssuranceTime(1000), copyBudget).error == AssuranceAcquisitionError.None, "exact pair of raw buffers admitted"
  var owned = input
  let job = captured(owner, fixture, owned, 1000, limits())
  owned[4] = owned[4] xor 1 # The original raw owner is independent of the captured private frame.
  let accepted = executeAssuranceAcquisition(job, default(AssuranceScanControl))
  assert accepted.error == AssuranceAcquisitionError.None, "captured genuine raw response persisted"
  assert owner.len == 1 and array[32, byte](accepted.value.record.chain) == array[32, byte](
      fixture.chain), "one real chain-bound retained coordinate"
  assert uint16(accepted.value.validator) == 1, "actual original parent validator index"
  assert uint64(accepted.value.record.retainUntil) == 1000+AssuranceRetentionSeconds, "full 28-day promise before progress"
  assert array[32, byte](accepted.value.duty.anchor) == array[32, byte](
      fixture.source.value.blockHash), "exact canonical anchor"
  assert owner.loadAssuranceShard(accepted.value.record.specifier,
    AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
      root: accepted.value.record.specifier.erasureRoot,
      shard: accepted.value.record.shard)).error == AssuranceStoreError.None, "actual complete retained restore"
  assert uint64(accepted.value.record.shard) == 1, "literal core-zero/original-index-one coordinate"
  var wrongChain = array[32, byte](fixture.chain)
  wrongChain[0] = wrongChain[0] xor 1
  reset(0)
  assert captureAssuranceAcquisition(owner, fixture.source, AssuranceChainId(wrongChain),
      fixture.local,
    CoreIndex(0), 0, input, AssuranceTime(1000), limits()).error ==
        AssuranceAcquisitionError.WrongChain, "foreign namespace refused before capture"
  assert calls() == 0, "chain refusal hashes nothing"
  for kind in 0..<3:
    # Length-prefix, truncated-body and final-suffix failures cannot trigger proof hashing or renew a persisted promise.
    var altered = input
    if kind == 0: altered[0] = altered[0] xor 1
    elif kind == 1: altered.setLen(altered.len-1)
    else: altered.add(0)
    reset(0)
    assert execute(owner, fixture, altered).error == AssuranceAcquisitionError.InvalidInput, "exact three-message framing"
    assert calls() == 0, "malformed framing hashes nothing"
  let duty = captureAssuranceDuty(fixture.source, fixture.local, limits().duty).value
  let request = duty.shardRequest(CoreIndex(0), 0).value
  let plan = availabilityVerificationInfo(fixture.availability.availabilityInfo.value.specifier, request).value
  var probePolicy = limits()
  let recordWorkspace = plan.payloadBytes*3+uint64(AssuranceRecordHeaderBytes)
  probePolicy.workspaceBytes = ByteLimit(recordWorkspace-1)
  reset(0)
  assert probe(owner, fixture, 9000, probePolicy).error ==
      AssuranceAcquisitionError.LimitExceeded and calls() == 0, "probe workspace deficit refuses before stored hashing"
  probePolicy.workspaceBytes = ByteLimit(recordWorkspace)
  let existing = probe(owner, fixture, 9000, probePolicy)
  assert existing.error == AssuranceAcquisitionError.None and uint64(
      existing.value.record.promisedAt) == 1000, "verified existing coordinate does not renew or move the promise clock"
  assert uint64(calls()) == plan.hashes+1, "probe actually verifies metadata and complete payload proofs"
  reset(0)
  let missingJob = captureAssuranceProbe(owner, fixture.source, fixture.chain, fixture.other,
    CoreIndex(0), 0, AssuranceTime(9000), limits()).value
  let missing = executeAssuranceAcquisition(missingJob, default(AssuranceScanControl))
  assert missing.error == AssuranceAcquisitionError.StorageFailure and missing.storageError.error ==
      AssuranceStoreError.Missing, "absent canonical coordinate requests acquisition, never default possession"
  assert calls() == 0 and not owner.faulted, "missing lookup preserves the healthy namespace without proof work"
  let workspace = uint64(input.len)+plan.payloadBytes*4+uint64(AssuranceRecordHeaderBytes)*2
  var narrow = limits()
  narrow.workspaceBytes = ByteLimit(workspace-1)
  reset(0)
  assert execute(owner, fixture, input, policy = narrow).error ==
      AssuranceAcquisitionError.LimitExceeded, "whole workspace deficit before verification"
  assert calls() == 0, "aggregate deficit hashes nothing"
  narrow.workspaceBytes = ByteLimit(workspace)
  narrow.verification.hashes = ElementLimit(plan.hashes-1)
  reset(0)
  let work = execute(owner, fixture, input, policy = narrow)
  assert work.error == AssuranceAcquisitionError.TransferFailure, "actual incoming verifier work failure"
  assert work.transferError.error == AvailabilityTransferError.LimitExceeded and calls() == 0, "hash deficit before first primitive"
  narrow = limits()
  narrow.workspaceBytes = ByteLimit(workspace)
  assert execute(owner, fixture, input, policy = narrow).error == AssuranceAcquisitionError.None, "exact aggregate transfer workspace"
  var corrupted = input
  corrupted[4] = corrupted[4] xor 1
  reset(0)
  let bad = execute(owner, fixture, corrupted)
  assert bad.error == AssuranceAcquisitionError.TransferFailure and calls() > 0, "real invalid bundle proof rejected"
  reset(1)
  let backend = execute(owner, fixture, input)
  assert backend.error == AssuranceAcquisitionError.TransferFailure, "actual maintained primitive refusal"
  assert backend.transferError.error == AvailabilityTransferError.BackendFailure, "backend cause preserved"
  reset(0)
  let stopped = captured(owner, fixture, input, 1001, limits())
  assert executeAssuranceAcquisition(stopped, assuranceScanControl(stopping, nil)).error ==
      AssuranceAcquisitionError.Cancelled and calls() == 0, "stopped acquisition has no data result or proof work"
  var other = fixture
  other.local = fixture.other
  let extra = wire(other)
  let full = execute(owner, other, extra)
  assert full.error == AssuranceAcquisitionError.StorageFailure, "a different genuine assigned coordinate cannot evict the old promise"
  assert full.storageError.error == AssuranceStoreError.LimitExceeded, "actual store capacity refusal preserved"
  assert owner.len == 1 and not owner.faulted, "all late refusals preserve the original promise"
proc failures(fixture: AssuranceAcquisitionFixture, input: seq[byte], folder: string) =
  ## Real data/directory synchronization refusal cannot be converted into successful acquisition facts.
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  assert owner.createAssuranceStore(folder, fixture.chain, storageLimits()).error ==
      AssuranceStoreError.None, "fault fixture namespace"
  for boundary in 0..1:
    # The first failed barrier precedes publication; the second leaves visible bytes and must fault every future operation.
    resetIo()
    armIo(syncIo, cint(boundary), 1, failedIo)
    let failed = execute(owner, fixture, input)
    assert failed.error == AssuranceAcquisitionError.StorageFailure and pendingIo() == 0, "actual retention synchronization failure"
    assert failed.storageError.error == AssuranceStoreError.FileFailure, "actual filesystem child retained"
    if boundary == 0:
      assert failed.storageError.fileError == AtomicFileError.IoFailure and owner.len == 0 and
          not owner.faulted, "prepublication failure preserves usable empty prefix"
    else:
      assert failed.storageError.fileError == AtomicFileError.PublishedUnsynced and owner.faulted, "uncertain publication never grants acquisition"
  resetIo()
  assert owner.close().error == AssuranceStoreError.None, "close faulted native owner"
  assert owner.openAssuranceStore(folder, fixture.chain, storageLimits()).error ==
      AssuranceStoreError.None, "restart counts the actual visible record"
  assert owner.len == 1 and execute(owner, fixture, input, 1001).error ==
      AssuranceAcquisitionError.None, "full re-verification and resync recover retained acquisition"
proc probeFaults(owner: var AssuranceStore, fixture: AssuranceAcquisitionFixture, folder: string) =
  ## A real restore sync failure faults the owner; only exact close/reopen and full verification permit another fixed observation.
  resetIo()
  armIo(syncIo, 0, 1, failedIo)
  let failed = probe(owner, fixture, 9000, limits())
  assert failed.error == AssuranceAcquisitionError.StorageFailure and failed.storageError.error ==
      AssuranceStoreError.FileFailure, "actual probe restore durability refusal"
  assert pendingIo() == 0 and owner.faulted, "probe never hides a real namespace fault"
  resetIo()
  assert owner.close().error == AssuranceStoreError.None, "close faulted probe owner"
  assert owner.openAssuranceStore(folder, fixture.chain, storageLimits()).error ==
      AssuranceStoreError.None, "verified namespace restart after failed probe"
  assert probe(owner, fixture, 9000, limits()).error == AssuranceAcquisitionError.None, "actual record proof and sync recovery"
proc cycle(worker: var StateProofWorker, owner: var AssuranceStore,
    fixture: AssuranceAcquisitionFixture, input: seq[byte], index: int) =
  ## Native source/frame/record owners retire before the next capture; completed cancellation retains stored data without exposing a result.
  var job = captured(owner, fixture, input, uint64(2000+index), limits())
  let admitted = worker.submit(job)
  assert admitted.error == ProofWorkerError.None and not job.valid, "moved bounded acquisition"
  worker.waitDone()
  assert worker.collect(default(ProofWorkerTicket)).kind == ProofWorkerCompletionKind.Uninitialized, "foreign collection preserves acquisition lease"
  if index mod 2 == 0: assert worker.cancel(admitted.value), "exact Done cancellation"
  let completed = worker.collect(admitted.value)
  if index mod 2 == 0:
    assert completed.kind == ProofWorkerCompletionKind.Cancelled, "cancelled acquisition has no metadata prefix"
  else:
    assert completed.kind == ProofWorkerCompletionKind.AssuranceAcquired, "exact acquisition completion"
    assert completed.assuranceAcquisitionValue.error == AssuranceAcquisitionError.None, "genuine durable native acquisition"
    var checking = capturedProbe(owner, fixture, 9000, limits())
    let checked = worker.submit(checking)
    assert checked.error == ProofWorkerError.None and not checking.valid, "moved native existing-record job"
    worker.waitDone()
    if index mod 4 == 1: assert worker.cancel(checked.value), "Done probe cancellation"
    let verified = worker.collect(checked.value)
    if index mod 4 == 1:
      assert verified.kind == ProofWorkerCompletionKind.Cancelled, "cancelled probe metadata stays hidden"
    else:
      assert verified.kind == ProofWorkerCompletionKind.AssuranceAcquired and
          verified.assuranceAcquisitionValue.error == AssuranceAcquisitionError.None, "complete synchronized native stored-coordinate check"
      assert uint64(verified.assuranceAcquisitionValue.value.record.promisedAt) == uint64(
          2000+index), "probe has not renewed the last real acquisition promise"

  if index mod 2 != 0:
    # The same native pool borrows only the installed archive address and returns complete durable audit data after exact retirement.
    let audit = auditFixture(fixture)
    var read = captureAssuranceRead(owner, audit.request, servingLimits()).value
    let admittedRead = worker.submit(read)
    assert admittedRead.error == ProofWorkerError.None and not read.valid, "moved closed durable read input"
    worker.waitDone()
    if index mod 4 == 1: assert worker.cancel(admittedRead.value), "cancel completed durable read"
    let completedRead = worker.collect(admittedRead.value)
    if index mod 4 == 1:
      assert completedRead.kind == ProofWorkerCompletionKind.Cancelled, "cancelled durable read exposes no bytes"
    else:
      assert completedRead.kind == ProofWorkerCompletionKind.ReadCompleted and
        completedRead.readValue.error == ReadError.None and
        completedRead.readValue.value.bytes == audit.expected, "actual durable audit matches original two-frame proof"
  assert owner.len == 1 and not owner.faulted, "inspect namespace only after exact retirement"
proc managed(fixture: AssuranceAcquisitionFixture, input: seq[byte], suffix: string) {.raises.} =
  ## An independently configured trusted seed is the actual complete computed child; Services must select its own head and namespace identity rather than peer-provided facts.
  var chainFile = "assurance-acquisition-chain-" & suffix & ".json"
  let folder = "assurance-acquisition-managed-" & suffix
  writeFile(chainFile, currentApplicationText(fixture.source.value))
  clean(folder)
  defer:
    discard posix.unlink(chainFile.toCString())
    clean(folder)
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", chainFile, "--with-state",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(options, "genuine assurance acquisition"), "actual complete seeded Services"
  assert owner.beginAssuranceAcquisition(fixture.local, CoreIndex(0), 0, input,
    AssuranceTime(1000), limits()).error == AssuranceStorageStartError.Unavailable, "storage never implicitly enabled"
  assert not owner.configureAssuranceReads(default(AssuranceReadLimits)) and
    not owner.configureAssuranceReads(servingLimits()), "no implicit durable read policy or archive opening"
  let opened = owner.beginAssuranceStorage(folder, storageLimits(),
      AssuranceStorageMode.Create).value
  owner.waitDone()
  assert owner.collectStateProof(opened).assuranceStorageValue.error == AssuranceStoreError.None, "actual managed namespace creation"
  let absent = owner.beginAssuranceProbe(fixture.local, CoreIndex(0), 0, AssuranceTime(1000),
      limits())
  assert absent.error == AssuranceStorageStartError.None and owner.rpc.chainPaused, "managed probe owns namespace and canonical lease"
  owner.waitDone()
  let absentResult = owner.collectStateProof(absent.value).assuranceAcquisitionValue
  assert absentResult.error == AssuranceAcquisitionError.StorageFailure and
      absentResult.storageError.error == AssuranceStoreError.Missing, "missing native namespace coordinate is not possession"
  assert owner.assuranceStorageInfo.opened and not owner.assuranceStorageInfo.faulted and
      owner.assuranceStorageInfo.records == 0, "missing probe preserves installed empty archive"
  let admitted = owner.beginAssuranceAcquisition(fixture.local, CoreIndex(0), 0, input,
    AssuranceTime(1000), limits())
  assert admitted.error == AssuranceStorageStartError.None and owner.rpc.chainPaused, "managed canonical acquisition lease"
  assert owner.assuranceStorageInfo.records == 0, "host polls cached previous accounting"
  owner.waitDone()
  assert owner.assuranceStorageInfo.records == 0 and owner.stateProofActive, "Done preserves both mutable-owner and canonical exclusion"
  let completed = owner.collectStateProof(admitted.value)
  assert completed.kind == ProofWorkerCompletionKind.AssuranceAcquired, "actual managed acquisition completed"
  assert completed.assuranceAcquisitionValue.error == AssuranceAcquisitionError.None, "actual canonical bytes persisted"
  assert owner.assuranceStorageInfo.records == 1 and not owner.assuranceStorageInfo.faulted and
      not owner.rpc.chainPaused, "exact collection refreshes actual stored accounting"
  assert array[32, byte](completed.assuranceAcquisitionValue.value.record.chain) == array[32, byte](
      owner.assuranceStorageInfo.chain), "configured namespace identity, not caller-supplied original fixture domain"
  let audit = auditFixture(fixture)
  assert owner.beginNetworkRead(audit.request).error == StateProofAdmissionError.QueryFailure and
    owner.stateProofAvailable, "durable reads remain disabled after acquisition"
  assert owner.configureAssuranceReads(servingLimits()) and
    not owner.configureAssuranceReads(servingLimits()), "once-only explicit durable audit activation"
  let reading = owner.beginNetworkRead(audit.request).value
  assert owner.rpc.chainPaused and owner.assuranceStorageInfo.records == 1, "exact archive/read canonical lease"
  owner.waitDone()
  assert not owner.stateProofAvailable and owner.assuranceStorageInfo.records == 1, "Done keeps archive excluded with cached accounting"
  let served = owner.collectStateProof(reading)
  assert served.kind == ProofWorkerCompletionKind.ReadCompleted and
    served.readValue.error == ReadError.None and served.readValue.value.bytes == audit.expected,
    "managed durable audit serves exact original proof without a work session"
  assuranceAuditRuntime(owner, options, fixture, audit.request, audit.expected, suffix)
  let checking = owner.beginAssuranceProbe(fixture.local, CoreIndex(0), 0, AssuranceTime(9000),
      limits()).value
  owner.waitDone()
  let checked = owner.collectStateProof(checking).assuranceAcquisitionValue
  assert checked.error == AssuranceAcquisitionError.None and uint64(
      checked.value.record.promisedAt) == 1000, "managed probe returns actual unchanged stored promise"
  let cancelled = owner.beginAssuranceAcquisition(fixture.local, CoreIndex(0), 0, input,
    AssuranceTime(1001), limits()).value
  owner.waitDone()
  assert owner.cancelStateProof(cancelled), "Done cancellation after durable renewal"
  assert owner.collectStateProof(admitted.value).kind == ProofWorkerCompletionKind.Uninitialized and
      owner.rpc.chainPaused, "stale collection cannot retire newer acquisition"
  assert owner.collectStateProof(cancelled).kind == ProofWorkerCompletionKind.Cancelled, "cancelled metadata withheld"
  assert owner.assuranceStorageInfo.opened and owner.assuranceStorageInfo.records == 1, "cancelled completed acquisition preserves healthy retained data"
  discard owner.beginAssuranceAcquisition(fixture.local, CoreIndex(0), 0, input,
    AssuranceTime(1002), limits()).value
  owner.stopStateProofs()
  assert owner.assuranceStorageInfo.opened and owner.assuranceStorageInfo.records == 1 and
      not owner.rpc.chainPaused, "joined acquisition stop preserves installed namespace"
  let restarted = owner.beginAssuranceProbe(fixture.local, CoreIndex(0), 0, AssuranceTime(9000),
      limits())
  assert restarted.error == AssuranceStorageStartError.None, "ordinary probe restarts a joined worker while preserving its installed namespace"
  owner.waitDone()
  assert owner.collectStateProof(restarted.value).assuranceAcquisitionValue.error ==
      AssuranceAcquisitionError.None, "real stored data remains usable after worker restart"
  resetIo()
  armIo(syncIo, 1, 1, failedIo)
  let fault = owner.beginAssuranceAcquisition(fixture.local, CoreIndex(0), 0, input,
    AssuranceTime(1003), limits()).value
  owner.waitDone()
  let failed = owner.collectStateProof(fault)
  assert pendingIo() == 0 and failed.kind == ProofWorkerCompletionKind.AssuranceAcquired, "actual managed restore-sync refusal consumed"
  assert failed.assuranceAcquisitionValue.error == AssuranceAcquisitionError.StorageFailure, "managed durability failure preserved"
  assert owner.assuranceStorageInfo.faulted and owner.assuranceStorageInfo.records == 1, "exact collection refreshes actual archive fault gate without dropping promises"
  assert owner.beginAssuranceAcquisition(fixture.local, CoreIndex(0), 0, input,
    AssuranceTime(1004), limits()).error == AssuranceStorageStartError.Unavailable, "faulted namespace cannot admit another possession acquisition"
  resetIo()
  owner.close()
  assert owner.start(options, "restarted durable audit service"), "independent Services restart"
  assert owner.beginNetworkRead(audit.request).error == StateProofAdmissionError.QueryFailure,
    "restart clears optional durable serving activation"
  let reopening = owner.beginAssuranceStorage(folder, storageLimits(),
      AssuranceStorageMode.Open).value
  owner.waitDone()
  assert owner.collectStateProof(reopening).assuranceStorageValue.error == AssuranceStoreError.None,
    "restart recovers actual retained namespace without session or key"
  assert owner.configureAssuranceReads(servingLimits()), "explicit restart serving activation"
  let restoredRead = owner.beginNetworkRead(audit.request).value
  owner.waitDone()
  let restoredReply = owner.collectStateProof(restoredRead)
  assert restoredReply.kind == ProofWorkerCompletionKind.ReadCompleted and
    restoredReply.readValue.error == ReadError.None and
    restoredReply.readValue.value.bytes == audit.expected, "restart serves original durable audit proof"
  assuranceAuditRuntime(owner, options, fixture, audit.request, audit.expected, suffix & "-restart")
  resetIo()
  armIo(syncIo, 0, 1, failedIo)
  let failedRead = owner.beginNetworkRead(audit.request).value
  owner.waitDone()
  assert pendingIo() == 0 and not owner.assuranceStorageInfo.faulted,
    "real restore sync fault remains worker-owned until exact retirement"
  assert owner.cancelStateProof(failedRead), "cancel completed durable audit refusal"
  assert owner.collectStateProof(failedRead).kind == ProofWorkerCompletionKind.Cancelled and
    owner.assuranceStorageInfo.faulted and owner.assuranceStorageInfo.records == 1,
    "cancelled read refreshes actual archive fault without losing the retained promise"
  assert owner.beginNetworkRead(audit.request).error == StateProofAdmissionError.QueryFailure,
    "faulted durable namespace refuses subsequent read capture"
  assert not owner.assuranceSigningConfigured, "durable serving requires no private signer"
  resetIo()
proc main() {.raises.} =
  ## Original reports and pending assignments are genuinely executed/admitted/published before any network-like response is constructed.
  reset(0)
  resetIo()
  let fixture = assuranceAcquisitionFixture()
  let input = wire(fixture)
  let suffix = $storageProcessId()
  let folder = "assurance-acquisition-" & suffix
  clean(folder)
  defer: clean(folder)
  var owner = default(AssuranceStore)
  defer: discard owner.close()
  assert owner.createAssuranceStore(folder, fixture.chain, storageLimits()).error ==
      AssuranceStoreError.None, "independent configured chain namespace"
  ordinary(owner, fixture, input)
  probeFaults(owner, fixture, folder)
  failures(fixture, input, folder & "-faults")
  managed(fixture, input, suffix)
  var worker = default(StateProofWorker)
  defer: worker.close() # Join before namespace/source/input retirement in every exit path.
  assert worker.start(), "reusable native worker"
  cycle(worker, owner, fixture, input, 1)
  let before = getOccupiedMem()
  for index in 0..<1000:
    # Actual duplicate reads, re-verification, renewal, encoding and file/directory barriers release all transient data graphs.
    cycle(worker, owner, fixture, input, index+1)
  let after = getOccupiedMem()
  assert before == after, "canonical acquisition ARC release"
  recordArcRelease("jamnp_assurance_acquisition", 1000, before, after)
  echo "JAMNP-S assurance acquisition passed"
try:
  main()
except:
  quit(2)
