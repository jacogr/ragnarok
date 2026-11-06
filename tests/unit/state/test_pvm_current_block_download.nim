# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_block_download_arc_release"}

## Current-only CE128 framing, exact worker handoff, ancestry suspension and stable receiver retirement use genuine signed children.
import std/[assertions, syncio, envvars, monotimes, times]
import std/posix/posix
import ../../../src/app/services
import ../../../src/app/proof/[worker, work_submission]
import ../../../src/jamnp-s/audit_context
import ../../../src/codec/state/[accounts, service_values, layout, outputs, privileges]
import ../../../src/crypto/primitives
import ../../../src/pvm/step as pvm_step
import "../../../src/app/current/block/download" as current_block_download
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/app/[preparation_worker, candidate, chain, options]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, report_owned, block_codec]
import ../../../src/state/store
import ../../../src/state/accumulation/current/[update as accumulation_current_update,
    consensus as accumulation_current_consensus]
import ../../../src/state/report/anchors as report_anchors
import ../../support/jamnp_audit_runtime
import ../../support/[current_services_disk_samples, current_application_context,
  accumulation_current_chain_context, accumulation_current_candidate_context, arc_evidence,
  current_consecutive_context, accumulation_current_round_context, pvm_accumulation_program,
  current_preimage_sequence_context, accumulation_execution_context, accumulation_activity_context]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Native reception and resumption must do no hashing or execution.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count primitive work independently of receiver status.
proc frame(context: CurrentChainFixture): seq[byte] =
  ## Independent E4 framing retains exactly one signed current block without an element-count prefix.
  let wire = context.currentDiskChildBytes
  assert uint64(wire.len) <= 0xffffffff'u64 and wire.len <= high(int)-4
  result = newSeq[byte](wire.len+4)
  for index in 0..<4: result[index] = byte((uint64(wire.len) shr (8*index)) and 255)
  for index, octet in wire: result[index+4] = octet
proc resources(size: int, discover = false): CurrentBlockInputLimits =
  ## All retained payload and ancestor ceilings are explicit local choices.
  CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(size)), ancestorBytes: ByteLimit(10000),
    ancestors: ElementLimit(4), discoverAncestors: discover)
proc begin(download: var CurrentBlockDownload, owner: Services, wire: seq[byte],
    discover = false): CurrentBlockDownloadId =
  ## Admit the current policy against the exact captured complete canonical parent.
  let admitted = download.begin(owner, [], resources(wire.len, discover), currentCandidateLimits())
  assert admitted.error == CurrentBlockDownloadError.None
  admitted.value
proc ready(download: var CurrentBlockDownload, owner: Services, wire: seq[byte],
    discover = false): CurrentBlockDownloadId =
  ## Both actual FIN observations are required before lending stable raw storage to a worker.
  result = download.begin(owner, wire, discover)
  assert download.append(result, wire, true) == CurrentBlockDownloadError.None
  assert download.stage == CurrentBlockDownloadStage.Receiving
  assert download.requestFinished(result) == CurrentBlockDownloadError.None
  assert download.stage == CurrentBlockDownloadStage.Ready
proc waitDone(owner: var Services) =
  ## Only scalar/dispatcher operations run while the current worker owns its exact RPC/graph lease.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    yieldCurrentDiskThread() # The shared wait helper retains no canonical/raw aliases.
proc framing(owner: Services, wire: seq[byte]) =
  ## Every split, defensive request copy, both FIN orders and malformed E4 outcomes are checked without guest work.
  var download = default(CurrentBlockDownload)
  let parent = array[32, byte](owner.chainView.bestBlock.value.blockHash)
  failHash(1)
  for split in 0..wire.len:
    let id = download.begin(owner, wire)
    let request = download.request(id).value
    assert request[0] == 128 and request[1] == 37 and request[37] == 0 and request[38] == 1
    for index in 0..<32: assert request[index+5] == parent[index]
    var scratch = request
    scratch[0] = 0
    assert download.request(id).value[0] == 128
    assert download.requestFinished(id) == CurrentBlockDownloadError.None
    assert download.append(id, wire.toOpenArray(0, split-1), false) ==
        CurrentBlockDownloadError.None
    assert download.append(id, wire.toOpenArray(split, wire.high), true) ==
        CurrentBlockDownloadError.None
    assert download.stage == CurrentBlockDownloadStage.Ready
    assert download.append(id, [], true) == CurrentBlockDownloadError.Busy
    assert download.cancel(id)
    assert download.append(id, [], true) == CurrentBlockDownloadError.StaleDownload
  let empty = download.begin(owner, wire)
  assert download.append(empty, [0'u8, 0, 0, 0], true) == CurrentBlockDownloadError.None
  assert download.requestFinished(empty) == CurrentBlockDownloadError.None
  assert download.stage == CurrentBlockDownloadStage.Empty and download.cancel(empty)
  for cut in [0, 1, 2, 3, 4, wire.len-1]:
    let id = download.begin(owner, wire)
    assert download.append(id, wire.toOpenArray(0, cut-1), true) ==
        CurrentBlockDownloadError.Truncated
    assert download.failure.error == CurrentBlockDownloadError.Truncated
    assert download.cancel(id)
  let huge = download.begin(owner, wire)
  assert download.append(huge, [255'u8, 255, 255, 255], false) ==
      CurrentBlockDownloadError.LimitExceeded
  assert download.cancel(huge)
  let extra = download.begin(owner, wire)
  var trailing = wire
  trailing.add(0)
  assert download.append(extra, trailing, true) == CurrentBlockDownloadError.Trailing
  assert download.cancel(extra)
  assert hashCalls() == 0
  failHash(0)
proc jobs(owner: var Services, wire: seq[byte], executed: bool) =
  ## Completed cancellation and joined retirement retain stable input/parent ownership and never enqueue unwanted work.
  var download = default(CurrentBlockDownload)
  let parent = owner.stateSnapshot.value
  for cancelled in [false, true]:
    let id = download.ready(owner, wire)
    assert download.beginPreparation(id, owner).error == CurrentBlockDownloadError.None
    assert not download.cancel(id) and owner.rpc.chainPaused
    owner.waitDone()
    assert owner.preparationActive and owner.rpc.chainPaused
    if cancelled: assert download.cancelPreparation(id, owner)
    let completed = download.collectPreparation(id, owner)
    if cancelled:
      assert completed.error == CurrentBlockDownloadError.Cancelled
      assert download.cancel(id)
    else:
      assert completed.error == CurrentBlockDownloadError.None
      assert sameStateSnapshot(owner.stateSnapshot.value, parent)
      assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
      assert owner.cancelCurrentAccumulation()
      assert download.stage == CurrentBlockDownloadStage.Idle
    assert not owner.preparationActive and not owner.rpc.chainPaused
    assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
    if executed:
      # Both collected success and Done cancellation retain authenticated code after actual execution.
      assert owner.residentServiceCount > 0
    else:
      # The original missing-code fixture cannot populate a resident guest entry.
      assert owner.residentServiceCount == 0
  let retained = owner.residentServiceCount
  let joined = download.ready(owner, wire)
  assert download.beginPreparation(joined, owner).error == CurrentBlockDownloadError.None
  owner.waitDone()
  assert download.retirePreparation(joined, owner)
  assert not owner.preparationActive and download.stage == CurrentBlockDownloadStage.Idle
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  assert owner.residentServiceCount == retained # retirePreparation joined the worker without closing Services.
proc scenario(context: CurrentChainFixture, ancestry = false, executed = false) {.raises.} =
  ## Complete independent parent startup supplies real current execution and original-history ancestry resumption.
  var path = "pvm-current-block-download-chain"
  writeFile(path, context.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var download = default(CurrentBlockDownload)
  var owner = default(Services)
  defer:
    discard download.retirePreparation(CurrentBlockDownloadId(1), owner)
    owner.close() # No outstanding worker may outlive its receiver even on exceptional test exit.
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "current receiver")
  let wire = context.frame
  if not ancestry:
    if not executed:
      framing(owner, wire) # Preserve original no-work framing coverage without duplicating it for positive execution.
    jobs(owner, wire, executed)
  let id = download.ready(owner, wire, ancestry)
  assert download.beginPreparation(id, owner).error == CurrentBlockDownloadError.None
  owner.waitDone()
  var completed = download.collectPreparation(id, owner)
  if ancestry:
    assert completed.error == CurrentBlockDownloadError.NeedsAncestors
    assert download.stage == CurrentBlockDownloadStage.AwaitingAncestors
    assert download.ancestorDemand(id).value.missingLookups.value > 0
    failHash(1)
    assert download.resumeAncestors(id, owner, [default(OwnedHeader)]).error ==
        CurrentBlockDownloadError.InputFailure
    assert download.resumeAncestors(id, owner, context.older).error ==
        CurrentBlockDownloadError.None
    assert hashCalls() == 0
    failHash(0)
    assert download.beginPreparation(id, owner).error == CurrentBlockDownloadError.None
    owner.waitDone()
    completed = download.collectPreparation(id, owner)
  assert completed.error == CurrentBlockDownloadError.None
  if executed:
    # Both direct and ancestor-completed positive cases consume the Services-owned context.
    assert owner.residentServiceCount > 0
  else:
    # Successful missing-code preparation still produces no resident guest entry.
    assert owner.residentServiceCount == 0
  equalCurrentDiskMap(completed.value.currentUpdateState,
      context.source.currentConsensusState.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
  owner.tick(0)
  let installed = owner.takeCurrentAccumulation()
  assert installed.error == CurrentHandoffError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, completed.value.currentUpdateState)
  assert download.stage == CurrentBlockDownloadStage.Idle
  owner.close()
  assert owner.residentServiceCount == 0 # Full close releases code after joined preparation.
proc cycle(context: CurrentChainFixture, wire: seq[byte]) =
  ## Isolated reception-only cycles release their bounded raw bytes and captured immutable owners without worker allocator claims.
  var download = default(CurrentBlockDownload)
  let owner = initApplicationChain(context.currentChainSeeded).value
  let admitted = download.begin(owner, [], resources(wire.len), currentCandidateLimits())
  assert admitted.error == CurrentBlockDownloadError.None
  assert download.requestFinished(admitted.value) == CurrentBlockDownloadError.None
  assert download.append(admitted.value, wire, true) == CurrentBlockDownloadError.None
  assert download.cancel(admitted.value)
proc slotOutput(state: StateStoreSnapshot): array[32, byte] =
  ## Decode the real published output; this guest yields its current compact slot byte and31 zeros.
  let read = decodeOutputLog(state.lookup(chapterKey(StateChapter(16))).value.bytes,
    OutputLogConfig(items: ElementLimit(4), maxBytes: ByteLimit(1000)))
  assert read.error == OutputLogError.None
  let values = read.value.snapshot
  for index in 0..<values.outputLogCount.value:
    let item = values.outputLogAt(OutputLogIndex(uint64(index))).value
    if uint32(item.service) == 42:
      return array[32, byte](item.commitment)
  assert false, "real slot-dependent yield must be present"
  default(array[32, byte])

proc consecutiveResidency(base: OwnedReport) {.raises.} =
  ## Two genuinely adopted children change parent maps and guest arguments while preserving one prepared service identity.
  let seed = currentChainFixture(base, available = true)
  var state = seed.parent.value.stateSnapshot.forkStateStore.value
  var metadata = decodeServiceMetadata(state.snapshot.value.lookup(chapterServiceKey(
    StateChapter(255), ServiceIndex(42))).value.bytes, ByteLimit(
        ServiceMetadataBytes)).value.metadata
  let privilegePolicy = PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(2),
    maxBytes: ByteLimit(1000))
  let privileges = decodePrivilegeState(state.snapshot.value.lookup(chapterKey(
    StateChapter(12))).value.bytes, privilegePolicy).value.snapshot
  let roles = privileges.privilegeInfo.value
  assert roles.always == 0, "original empty-child seed schedules no services"
  var assigners = newSeq[ServiceIndex](roles.cores)
  for index in 0..<roles.cores:
    # Preserve every existing role while explicitly scheduling the literal guest on empty children.
    assigners[index] = privileges.privilegeAssignerAt(PrivilegeCoreIndex(index)).value
  let scheduled = privilegeStateEntry(PrivilegeState(manager: roles.manager,
    delegator: roles.delegator, registrar: roles.registrar, assigners: assigners,
    always: @[AlwaysAccumulate(service: ServiceIndex(42), gas: PrivilegeGas(10000))]),
    privilegePolicy).value
  assert state.apply([StateWrite(key: scheduled.key, kind: StateWriteKind.Put,
    value: scheduled.value)]).error == StateStoreError.None
  # Read arg[0] from the fresh argument page, store it in fresh RW memory, and yield all32 bytes.
  let preimage = currentRoundServiceCode(@[@[124'u8, 115], registerImmediate(4, 196608),
    @[120'u8, 67], registerImmediate(7, 196608), @[10'u8, 27], @[50'u8, 0]])
  let hashed = blake2b256(preimage)
  assert hashed.error == CryptoError.None
  metadata.codeHash = CodeHash(array[32, byte](hashed.value))
  let account = serviceMetadataEntry(ServiceIndex(42), metadata, ByteLimit(
      ServiceMetadataBytes)).value
  let code = servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(array[32, byte](
      hashed.value)),
    preimage, ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
        preimage.len))).value
  assert state.apply([StateWrite(key: account.key, kind: StateWriteKind.Put, value: account.value),
    StateWrite(key: code.key, kind: StateWriteKind.Put, value: code.value)]).error ==
        StateStoreError.None
  let captured = captureBlockSnapshot(currentChainBytes(seed.parent.value.header),
      state.snapshot.value,
    seed.parent.value.chainParameters)
  assert captured.error == GenesisError.None
  var reference = initApplicationChain(genesisView(captured)).value
  var path = "pvm-resident-consecutive-services-chain"
  writeFile(path, captured.value.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close() # The context and every retained historical output outlive joined preparation.
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", path], options)
  assert owner.start(options, "resident consecutive")
  let policy = currentConsecutiveLimits()
  let selected = policy.completion.execution.initial.guests.backend
  var previousHits = 0'u64
  var priorOutputs: seq[StateStoreSnapshot] = @[]
  for index in 0..<2:
    let before = owner.chainView.bestBlock.value
    let child = currentEmptyChild(reference.chainView.bestBlock.value)
    # One-shot phase composition independently establishes every expected map/output byte.
    let expected = phaseCurrentUpdate(reference, child, [], policy)
    assert reference.canInstallPrepared(expected)
    reference.installPrepared(expected)
    var wire = newSeq[byte](child.blockInfo.value.consumed)
    assert child.encodeOwnedBlock(wire).error == FrameError.None
    let prepared = owner.prepareCurrentServicesUpdate(input, wire)
    equalCurrentDiskMap(prepared.currentUpdateState, expected.currentUpdateState)
    let info = owner.residentServiceInfo(ServiceIndex(42), metadata.codeHash, selected)
    assert info.error == pvm_step.PreparationError.None
    assert info.value.preparations == 1 # Both blocks use the actual existing worker counter.
    assert info.value.prepared.streamNodes > 0
    if index == 1:
      assert info.value.hits > previousHits
      assert owner.chainView.bestBlock.value.slot == uint32(captured.value.slot)+1
    previousHits = info.value.hits
    assert owner.enqueueCurrentAccumulation(prepared) == CurrentHandoffAdmission.None
    owner.tick(0)
    assert owner.takeCurrentAccumulation.error == CurrentHandoffError.None
    let actual = owner.stateSnapshot.value
    equalCurrentDiskMap(actual, reference.stateSnapshot.value)
    assert owner.chainView.bestBlock.value.slot == before.slot+1
    assert array[32, byte](owner.chainView.bestBlock.value.blockHash) ==
      array[32, byte](reference.chainView.bestBlock.value.blockHash)
    assert owner.chainView.bestBlock.value.slot < 128 # Compact slot arguments are exactly one byte in this witness.
    var expectedOutput = default(array[32, byte])
    expectedOutput[0] = byte(owner.chainView.bestBlock.value.slot)
    assert slotOutput(actual) == expectedOutput
    priorOutputs.add(actual)
    owner.stopPreparation() # Joined restart preserves the same residency and full canonical lifetime.
    let idle = owner.residentServiceInfo(ServiceIndex(42), metadata.codeHash, selected)
    assert idle.error == pvm_step.PreparationError.None and idle.value.preparations == 1
    assert idle.value.hits == previousHits
  assert slotOutput(priorOutputs[0])[0] == byte(uint32(captured.value.slot)+1)
  assert slotOutput(priorOutputs[1])[0] == byte(uint32(captured.value.slot)+2)
  let auditHead = owner.chainView.bestBlock.value
  assert auditHead.hasBlockBody, "actual full-current adoption retains its committed body for auditing"
  let rules = currentCandidateLimits().reporting
  let auditPolicy = AuditContextLimits(admission: rules.admission, disputes: rules.disputes,
    safrole: rules.safrole, availability: rules.availability, bodyBytes: ByteLimit(1000000),
    chapterBytes: ByteLimit(1000000), readBytes: ByteLimit(8000000), workspaceBytes: ByteLimit(
        128000000),
    outputBytes: ByteLimit(8000000), reports: ElementLimit(2), hashes: ElementLimit(4),
        hashBytes: ByteLimit(1000000))
  let audit = owner.beginAuditPlanning(auditHead.blockHash, auditPolicy)
  assert audit.error == StateProofAdmissionError.None and owner.rpc.chainPaused,
    "real current canonical history enters the managed audit worker"
  let auditDeadline = getMonoTime()+initDuration(seconds = 10)
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert getMonoTime() < auditDeadline, "bounded full-current audit context"
    yieldCurrentDiskThread() # Retained canonical/source/output aliases remain untouched until exact collection.
  let auditCompleted = owner.collectStateProof(audit.value)
  assert auditCompleted.kind == ProofWorkerCompletionKind.WorkSubmitted,
    "exact managed current-body audit completion"
  let auditResult = auditCompleted.workSubmissionValue
  assert auditResult.kind == WorkJobResultKind.AuditPlanned,
    "genuine full-current published history qualifies the actual audit context"
  let auditContext = auditResult.plannedAuditContext
  assert owner.auditContextCurrent(auditContext) and auditContext.contextInfo.value.reports == 0,
    "no available reports in these genuine empty children means no fabricated audit obligation"
  assert not owner.rpc.chainPaused, "successful context collection resumes canonical RPC"
  auditReceiptRuntime(owner, options, auditContext, auditPolicy)
  owner.close()
  assert owner.residentServiceCount == 0
  assert owner.residentServiceInfo(ServiceIndex(42), metadata.codeHash, selected).error !=
      pvm_step.PreparationError.None

proc executedFixture(base: OwnedReport, uses = 0): CurrentChainFixture =
  ## Real authenticated code and explicit allowances make the direct/ancestor cache checks nonvacuous.
  currentExecutionSeed(executionFixture(base, activityOptions(available = true,
    executed = true, guarantees = uses)), currentConsecutiveLimits())

proc main() {.raises.} =
  ## Independent current state and signed report inputs qualify actual execution separately from callback/ARC work.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let base = decodeOwnedReport(bytes, 2).value
  let context = currentChainFixture(base, available = true)
  let wire = context.frame
  cycle(context, wire)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context, wire)
  let after = getOccupiedMem()
  assert before == after, "current download reception releases"
  recordArcRelease("pvm_current_block_download", 1000, before, after)
  consecutiveResidency(base)
  scenario(context)
  scenario(currentChainFixture(base, uses = 2, available = true), true)
  scenario(executedFixture(base), executed = true) # Positive code retention stays outside reception ARC stress.
  scenario(executedFixture(base, uses = 2), ancestry = true, executed = true)
  echo "PVM current block download passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit(2) # Current execution, signed fixture or worker failure cannot satisfy successful reception evidence.
