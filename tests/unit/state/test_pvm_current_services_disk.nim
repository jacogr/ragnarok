# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed current preparation crosses native durable publication, exact RPC exclusion and strict complete-map reopen.
import std/[assertions, syncio, envvars, monotimes, times, base64, strutils]
import std/posix/posix
import ../../../src/app/[services, options, preparation_worker, audit_branches]
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/app/[candidate, handoff, chain]
import ../../../src/app/disk/[worker as disk_worker, chain as disk_chain]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/store
import ../../../src/state/accumulation/current/[update as accumulation_current_update,
    consensus as accumulation_current_consensus]
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/report/admission as report_admission
import ../../../src/state/accumulation/[finalization as accumulation_finalization,
    completion as accumulation_completion]
import ../../../src/storage/managed/manifest as managed_manifest
import ../../support/[accumulation_current_chain_context, accumulation_current_candidate_context,
  current_application_context, current_services_disk_samples, managed_storage_samples, rpc_socket]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Enable failure only after synchronized Done, when the worker no longer calls hashing primitives.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe the post-collection host installation independently of status flags.
proc prepareAuditChild(owner: var Services, input: var CurrentBlockInput,
    parent: genesis.BlockHash, wire: openArray[byte]): PreparedCurrentChainUpdate {.raises.} =
  ## Real bounded intake reaches the same current STF worker through an independently retained parent.
  let resources = CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)),
      ancestorBytes: ByteLimit(10000), ancestors: ElementLimit(4))
  let limits = currentCandidateLimits()
  let unknown = owner.beginAuditBranchInput(input, default(genesis.BlockHash),
      ByteLimit(uint64(wire.len)), [], resources, limits)
  assert unknown.error != CurrentBlockInputError.None
  let admitted = owner.beginAuditBranchInput(input, parent, ByteLimit(uint64(wire.len)),
      [], resources, limits)
  assert admitted.error == CurrentBlockInputError.None
  assert input.append(admitted.value, wire, true) == CurrentBlockInputError.None
  let ticket = owner.beginAuditBranchPreparation(input, admitted.value, parent)
  assert ticket.error == PreparationError.None and owner.rpc.chainPaused
  let deadline = getMonoTime()+initDuration(seconds = 20)
  while owner.preparationPhase != PreparationPhase.Done:
    # Only scalar state is observed while the worker owns the retained parent.
    assert getMonoTime() < deadline
    owner.tick(0)
    yieldCurrentDiskThread()
  assert owner.collectPreparation(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized and owner.rpc.chainPaused
  let finished = owner.collectPreparation(ticket.value)
  assert finished.kind == PreparationCompletionKind.CurrentCompleted
  assert finished.currentValue.error == CurrentBlockInputError.None and not owner.rpc.chainPaused
  finished.currentValue.value
proc scenario(context: CurrentChainFixture, managed, network: bool) {.raises.} =
  ## Each layout/RPC combination publishes once, acknowledges once, and strictly reopens its actual durable child.
  var path = "pvm-current-services-disk-chain"
  var database = "pvm-current-services-disk-state"
  writeFile(path, context.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if managed:
      removeManagedSample(database, [ManagedEpoch(1)])
    else:
      discard posix.unlink(database.toCString()) # Only exact test-owned storage names are retired after joined close.
  let wire = context.currentDiskChildBytes
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close() # The receiver remains stable until both native worker lifetimes have joined.
  var port = 0'u16
  if network:
    let reserved = reservation()
    port = reserved.port
    discard posix.close(reserved.fd)
  let options = currentDiskOptions(path, database, managed, port)
  assert owner.start(options, "current durable Services")
  let parent = owner.stateSnapshot.value
  let parentHash = owner.chainView.bestBlock.value.blockHash
  let update = if not managed and not network:
      prepareAuditChild(owner, input, parentHash, wire)
    else: prepareCurrentServicesUpdate(owner, input, wire)
  assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  assert array[32, byte](parentHash) == array[32, byte](owner.chainView.bestBlock.value.blockHash)
  if not managed and not network:
    # A fully prepared child can be retained without adopting it or changing selected state.
    assert owner.configureAuditBranches(AuditBranchLimits(branches: ElementLimit(2),
        bytes: ByteLimit(64000000)))
    let parentBranch = owner.auditBranchParent(parentHash)
    assert parentBranch.error == ApplicationChainError.None
    assert sameStateSnapshot(parentBranch.value.stateSnapshot.value, parent)
    assert owner.retainAuditBranch(default(PreparedCurrentChainUpdate)) ==
        AuditBranchError.Uninitialized
    assert owner.retainAuditBranch(update) == AuditBranchError.None
    assert owner.retainAuditBranch(update) == AuditBranchError.Duplicate
    let sideHash = update.currentUpdateChildContext.hash
    let branch = owner.auditBranchParent(sideHash).value
    let next = owner.nextAuditBranch(0)
    assert owner.auditBranchCount == 1 and next.serial == 1 and
        array[32, byte](next.hash) == array[32, byte](sideHash)
    assert owner.nextAuditBranch(next.serial).serial == 0
    assert sameStateSnapshot(branch.stateSnapshot.value, update.currentUpdateState)
    assert owner.chainView.blockAt(sideHash).error == GenesisError.Unavailable and
        sameStateSnapshot(owner.stateSnapshot.value, parent)
  equalCurrentDiskMap(update.currentUpdateState, context.source.currentConsensusState.value)
  var peer = -1.cint
  var pending = ""
  if network:
    peer = client(port)
    upgrade(owner.rpc, peer, pending)
    sendText(peer, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}""")
    assert "\"result\":1" in readPacket(owner.rpc, peer, pending)
    assert "\"slot\":1" in readPacket(owner.rpc, peer, pending)
  assert owner.currentDiskPreparationOutcome.error == DiskChainError.Uninitialized
  assert owner.diskPublicationOutcome.error == DiskChainError.Uninitialized
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
  let legacy = default(PreparedFinalAccumulation)
  assert owner.enqueueAccumulation(legacy, default(AccumulationCompositionLimits)) ==
      AccumulationEnqueueError.Busy
  owner.tick(0)
  assert owner.currentDiskPublicationAdmissionError == DiskWorkerError.None
  assert owner.diskPublicationActive and owner.rpc.chainPaused
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Publishing
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  assert not owner.cancelCurrentAccumulation() and not owner.beginDiskMaintenance()
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.Busy
  owner.waitCurrentDiskDone()
  assert owner.diskPublicationActive and owner.rpc.chainPaused
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  failHash(1)
  owner.tick(0) # Collection, receipt confirmation and installation consume cached owners without hashing.
  assert hashCalls() == 0, "current durable host completion does no hashing"
  failHash(0)
  assert not owner.diskPublicationActive and not owner.rpc.chainPaused
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  assert owner.diskPublicationOutcome.error == DiskChainError.None
  assert owner.currentDiskPreparationOutcome.error == DiskChainError.Uninitialized
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.Busy
  let installed = owner.takeCurrentAccumulation()
  assert installed.error == CurrentHandoffError.None
  let childHash = installed.value.blockHash
  if not managed and not network:
    # Once the side copy is redundant, explicitly installed finality releases its reservation.
    assert owner.publishFinalized(childHash) == ViewFinalizeError.None
    assert owner.auditBranchCount == 0 and owner.nextAuditBranch(0).serial == 0

  assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  assert owner.preparationAvailable and owner.stateProofAvailable
  if network:
    let expected = base64.encode(array[32, byte](childHash))
    assert expected in readPacket(owner.rpc, peer, pending)
    sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
    assert expected in readPacket(owner.rpc, peer, pending)
    discard posix.close(peer) # Listener shutdown follows retirement of the actual test-owned socket.
  owner.close()
  assert owner.diskPublicationOutcome.error == DiskChainError.None
  assert owner.start(options, "strict current durable restart")
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](childHash)
  equalCurrentDiskMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  owner.close() # Close joins before the deferred exact namespace cleanup runs.
proc main() {.raises.} =
  ## Signed fixture execution and all four durable combinations must complete without fixture/runtime exceptions.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true)
  scenario(context, false, false)
  scenario(context, false, true)
  scenario(context, true, false)
  scenario(context, true, true)
try:
  main()
except:
  quit(2) # Execution, disk, RPC or reopen failure cannot satisfy durable publication evidence.
echo "PVM current Services disk passed"
