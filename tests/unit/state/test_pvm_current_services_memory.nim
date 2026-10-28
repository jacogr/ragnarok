# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real managed current execution crosses Services exclusion and deferred canonical/RPC installation with bounded acknowledgment.
import std/[assertions, syncio, envvars, monotimes, times, base64, strutils]
import std/posix/posix
import ../../../src/app/[services, options, preparation_worker, current_block_input,
  current_handoff, candidate, handoff, chain]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/[store, accumulation_current_update, accumulation_current_consensus,
  block_admission, report_admission, accumulation_finalization, accumulation_completion]
import ../../support/[accumulation_current_chain_context, accumulation_current_candidate_context,
  current_application_context, rpc_socket]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Prove the current host handoff does not repeat hashing or guest work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe primitive calls independently of API status.
proc config(path: string, port = 0'u16): Options =
  ## Canonical startup and any listener remain explicit local policy.
  var args = @["server", "--with-state", "--chain", path]
  if port != 0:
    args.add("--with-rpc")
    args.add("--rpc-port")
    args.add($port) # A test-only ephemeral reservation selects the actual loopback listener.
  result = default(Options)
  assert parseCanonicalOptions(args, result)
proc receive(owner: Services, input: var CurrentBlockInput, wire: openArray[byte],
    discover = false): CurrentBlockInputId =
  ## Bind the actual Services head before any exclusive native lease begins.
  let admitted = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [],
    CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)), ancestorBytes: ByteLimit(10000),
      ancestors: ElementLimit(4), discoverAncestors: discover), currentCandidateLimits())
  assert admitted.error == CurrentBlockInputError.None
  result = admitted.value
  assert input.append(result, wire, true) == CurrentBlockInputError.None
proc waitDone(owner: var Services) =
  ## Only scalar worker state and permitted independent dispatcher work are observed during exclusion.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20, "bounded current managed preparation"
    owner.tick(0)
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Yield without touching any retained input/canonical alias.
proc childBytes(context: CurrentChainFixture): seq[byte] =
  ## Retain the actual signed child wire bytes before startup or native borrowing.
  let child = context.source.currentChainAdmission.reportBlockStage.value.value.admitted.admittedBlock
  result = newSeq[byte](child.blockInfo.value.consumed)
  assert child.encodeOwnedBlock(result).error == FrameError.None
proc scenario(context: CurrentChainFixture, network: bool, refuseRpc = false) {.raises.} =
  ## Startup reconstructs the complete original map; only the Services-owned graph is leased to its worker.
  var path = "pvm-current-services-memory-chain"
  writeFile(path, context.currentApplicationText)
  defer: discard posix.unlink(path.toCString())
  let wire = context.childBytes
  var input = default(CurrentBlockInput)
  var owner = default(Services)
  defer: owner.close() # Input and all idle fixture aliases outlive joined worker retirement.
  var port = 0'u16
  if network:
    let reserved = reservation()
    port = reserved.port
    discard posix.close(reserved.fd) # Services owns the actual listener after this bounded local reservation.
  assert owner.start(config(path, port), "current Services memory")
  let before = owner.stateSnapshot.value
  let originalHead = owner.chainView.bestBlock.value.blockHash
  assert owner.preparationAvailable and owner.stateProofAvailable
  assert owner.beginPreparation(input, CurrentBlockInputId(0)).error == PreparationError.NotReady
  assert not owner.preparationActive and not owner.rpc.chainPaused
  var peer = -1.cint
  var pending = ""
  if network and not refuseRpc:
    peer = client(port)
    upgrade(owner.rpc, peer, pending)
    sendText(peer, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}""")
    assert "\"result\":1" in readPacket(owner.rpc, peer, pending)
    assert "\"slot\":1" in readPacket(owner.rpc, peer, pending)
  let id = receive(owner, input, wire)
  let admitted = owner.beginPreparation(input, id)
  assert admitted.error == PreparationError.None
  assert owner.preparationActive and owner.rpc.chainPaused
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  let absent = default(PreparedCurrentChainUpdate)
  assert owner.enqueueCurrentAccumulation(absent) == CurrentHandoffAdmission.Busy
  assert not owner.cancelCurrentAccumulation()
  assert owner.collectPreparation(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized
  owner.waitDone()
  assert owner.preparationActive and owner.rpc.chainPaused
  let completion = owner.collectPreparation(admitted.value)
  assert completion.kind == PreparationCompletionKind.CurrentCompleted
  assert completion.currentValue.error == CurrentBlockInputError.None
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](originalHead)
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  let update = completion.currentValue.value
  assert array[32, byte](update.currentUpdateState.commitment.root) ==
    array[32, byte](context.source.currentConsensusState.value.commitment.root)
  if refuseRpc:
    owner.rpc.close() # Enabled RPC refusal must not become canonical-only installation.
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.Busy
  let legacy = default(PreparedFinalAccumulation)
  assert owner.enqueueAccumulation(legacy, default(AccumulationCompositionLimits)) ==
      AccumulationEnqueueError.Busy
  assert owner.cancelCurrentAccumulation() and owner.currentAccumulationPhase ==
      CurrentHandoffPhase.Idle
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  failHash(1)
  owner.tick(0)
  assert hashCalls() == 0, "current Services host installation does no hashing"
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  assert not owner.cancelCurrentAccumulation()
  let installed = owner.takeCurrentAccumulation()
  failHash(0)
  if refuseRpc:
    assert installed.error == CurrentHandoffError.RpcRefused
    assert sameStateSnapshot(before, owner.stateSnapshot.value)
  else:
    assert installed.error == CurrentHandoffError.None
    assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
    if network:
      let expected = base64.encode(array[32, byte](installed.value.blockHash))
      assert expected in readPacket(owner.rpc, peer, pending)
      sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
      assert expected in readPacket(owner.rpc, peer, pending)
      discard posix.close(peer) # Actual subscription/query ownership ends before listener close.
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  assert owner.preparationAvailable and owner.stateProofAvailable
  let next = receive(owner, input, [255'u8])
  let cancelled = owner.beginPreparation(input, next).value
  assert owner.cancelPreparation(cancelled)
  owner.waitDone()
  assert owner.preparationActive and owner.rpc.chainPaused
  assert owner.collectPreparation(cancelled).kind == PreparationCompletionKind.Cancelled
  assert not owner.preparationActive and not owner.rpc.chainPaused
  discard input.cancel(next) # A skipped queued job still owns its raw receiver until collection ends exclusion.
  let joined = receive(owner, input, [255'u8])
  assert owner.beginPreparation(input, joined).error == PreparationError.None
  owner.close() # Join precedes canonical/raw/RPC alias retirement, including on immediate shutdown.
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  discard input.cancel(joined)
proc main() {.raises.} =
  ## Exact signed fixtures exercise disabled/enabled RPC and enabled-listener refusal through actual Services.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index]) # Initialize the pinned fixture's byte extent.
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true)
  scenario(context, false)
  scenario(context, true)
  scenario(context, true, true)
  echo "PVM current Services memory passed"
try:
  main() # Actual startup, native execution and RPC failures cannot count as current publication evidence.
except:
  quit(2)
