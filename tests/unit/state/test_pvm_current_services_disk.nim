# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed current preparation crosses native durable publication, exact RPC exclusion and strict complete-map reopen.
import std/[assertions, syncio, envvars, monotimes, times, base64, strutils]
import std/posix/posix
import ../../../src/app/[services, options, preparation_worker, current_block_input,
  current_handoff, candidate, handoff, chain, disk_worker, disk_chain]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/[store, accumulation_current_update, accumulation_current_consensus,
  block_admission, report_admission, accumulation_finalization, accumulation_completion]
import ../../../src/storage/managed_manifest
import ../../support/[accumulation_current_chain_context, accumulation_current_candidate_context,
  current_application_context, managed_storage_samples, rpc_socket]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Enable failure only after synchronized Done, when the worker no longer calls hashing primitives.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe the post-collection host installation independently of status flags.
proc yieldThread() =
  ## Yield within bounded waits without creating or retiring any leased graph alias.
  var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(requested, remaining)
proc config(path, database: string, managed: bool, port: uint16): Options =
  ## Explicit local startup selects either strict disk layout and the original complete parent map.
  var args = @["server", "--with-state", "--chain", path, "--state-storage", "disk",
    "--state-db", database]
  if managed:
    args.add("--state-layout")
    args.add("managed")
    args.add("--state-compact-bytes")
    args.add("0") # Publication tests keep automatic maintenance out of the selected physical lifetime.
  if port != 0:
    args.add("--with-rpc")
    args.add("--rpc-port")
    args.add($port) # Only the test-owned loopback reservation chooses this listener.
  result = default(Options)
  assert parseOptions(args, result)
proc childBytes(context: CurrentChainFixture): seq[byte] =
  ## Capture signed wire bytes before native Services ownership can be borrowed.
  let child = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  result = newSeq[byte](child.blockInfo.value.consumed)
  assert child.encodeOwnedBlock(result).error == FrameError.None
proc prepare(owner: var Services, input: var CurrentBlockInput,
    wire: openArray[byte]): PreparedCurrentChainUpdate {.raises.} =
  ## Actual execution returns a current update without installing or changing the durable parent.
  let admitted = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [],
    CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)), ancestorBytes: ByteLimit(10000),
      ancestors: ElementLimit(4), discoverAncestors: false), currentCandidateLimits())
  assert admitted.error == CurrentBlockInputError.None
  assert input.append(admitted.value, wire, true) == CurrentBlockInputError.None
  let ticket = owner.beginPreparation(input, admitted.value)
  assert ticket.error == PreparationError.None
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    yieldThread() # Only dispatcher/scalar state is touched until collection ends preparation exclusion.
  assert owner.preparationActive and owner.rpc.chainPaused
  let completion = owner.collectPreparation(ticket.value)
  assert completion.kind == PreparationCompletionKind.CurrentCompleted
  assert completion.currentValue.error == CurrentBlockInputError.None
  completion.currentValue.value
proc waitDiskDone(owner: var Services) =
  ## Done alone never releases the exclusive native lease; deliberately do not tick/collect here.
  let started = getMonoTime()
  while owner.diskPublicationPhase != DiskWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    yieldThread()
proc equalMap(actual, expected: StateStoreSnapshot) =
  ## Every reopened entry and byte value is compared against independently composed current state.
  assert actual.commitment.entries == expected.commitment.entries
  assert array[32, byte](actual.commitment.root) == array[32, byte](expected.commitment.root)
  for index in 0..<expected.commitment.entries:
    let key = expected.keyAt(StateEntryIndex(index)).value
    assert actual.lookup(key).error == StateStoreError.None
    assert actual.lookup(key).value.bytes == expected.lookup(key).value.bytes
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
  let wire = context.childBytes
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close() # The receiver remains stable until both native worker lifetimes have joined.
  var port = 0'u16
  if network:
    let reserved = reservation()
    port = reserved.port
    discard posix.close(reserved.fd)
  let options = config(path, database, managed, port)
  assert owner.start(options, "current durable Services")
  let parent = owner.stateSnapshot.value
  let parentHash = owner.chainView.bestBlock.value.blockHash
  let update = prepare(owner, input, wire)
  assert sameStateSnapshot(parent, owner.stateSnapshot.value)
  assert array[32, byte](parentHash) == array[32, byte](owner.chainView.bestBlock.value.blockHash)
  equalMap(update.currentUpdateState, context.source.currentConsensusState.value)
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
  owner.waitDiskDone()
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
  equalMap(owner.stateSnapshot.value, context.source.currentConsensusState.value)
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
