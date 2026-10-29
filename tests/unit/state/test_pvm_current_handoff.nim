# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_handoff_arc_release"}

## A genuine current update crosses one bounded slot once; canonical/RPC visibility and refusal survive until acknowledgment.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../../src/app/chain
import ../../../src/app/current/handoff as current_handoff
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/rpc/server
import ../../../src/state/store
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../support/[accumulation_current_chain_context, rpc_socket, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc listener(rpc: var Server, view: ChainView) =
  ## Bounded ephemeral-port retry keeps native RPC checks isolated from fixed-port assumptions.
  let parameters = decodeParameters(currentChainSettings().encodeParameters)
  for attempt in 0..<8:
    let port = reservation()
    discard posix.close(port.fd)
    if rpc.start(port.port, "current-handoff-test", parameters, view): return
  assert false, "current handoff RPC startup failed"
proc canonical(original: ApplicationChain, update: PreparedCurrentChainUpdate) =
  ## Busy/completed backpressure, cancellation and stale-source refusal never replace existing ownership.
  var owner = original
  var handoff = default(CurrentAccumulationHandoff)
  assert handoff.phase == CurrentHandoffPhase.Idle
  handoff.process(owner)
  assert not handoff.cancel
  var absent = default(ApplicationChain)
  assert handoff.enqueue(absent, update) == CurrentHandoffAdmission.Unavailable
  let invalid = default(PreparedCurrentChainUpdate)
  assert handoff.enqueue(owner, invalid) == CurrentHandoffAdmission.InvalidUpdate
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.None
  assert sameChainView(handoff.pendingUpdate.currentUpdateView, update.currentUpdateView)
  assert handoff.enqueue(owner, invalid) == CurrentHandoffAdmission.Busy
  assert handoff.cancel and handoff.phase == CurrentHandoffPhase.Idle
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.None
  failHash(3)
  handoff.process(owner)
  assert handoff.phase == CurrentHandoffPhase.Finished
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.Busy
  handoff.process(owner)
  assert not handoff.cancel
  let outcome = handoff.take
  assert outcome.error == CurrentHandoffError.None
  assert array[32, byte](outcome.value.blockHash) == array[32, byte](
      update.currentUpdateChild.blockHash)
  assert handoff.phase == CurrentHandoffPhase.Idle
  assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.StaleState
  assert hashCalls() == 0, "handoff never executes, composes, hashes or recaptures"
  failHash(0)
  owner = original
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.None
  owner.installPrepared(update)
  handoff.process(owner)
  assert handoff.take.error == CurrentHandoffError.StaleState
proc joint(original: ApplicationChain, update: PreparedCurrentChainUpdate) =
  ## RPC refusal is terminal and leaves canonical state unchanged; a subsequent admitted exact lease installs once.
  var owner = original
  var handoff = default(CurrentAccumulationHandoff)
  var rpc = default(Server)
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.None
  handoff.process(owner, rpc)
  assert handoff.take.error == CurrentHandoffError.RpcRefused
  assert sameStateSnapshot(owner.stateSnapshot.value, original.stateSnapshot.value)
  listener(rpc, owner.chainView)
  let lease = rpc.pauseChain()
  assert lease != nil
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.None
  handoff.process(owner, rpc)
  assert handoff.take.error == CurrentHandoffError.RpcRefused
  assert rpc.chainPaused and sameStateSnapshot(owner.stateSnapshot.value,
      original.stateSnapshot.value)
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.None
  failHash(3)
  handoff.process(owner, rpc, lease)
  assert handoff.take.error == CurrentHandoffError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
  assert hashCalls() == 0
  assert rpc.chainPaused and rpc.resumeChain(lease)
  failHash(0)
  rpc.close()
proc cycle(original: ApplicationChain, update: PreparedCurrentChainUpdate) =
  ## Both cancellation and complete acknowledgment release exactly their own retained immutable candidate aliases.
  var owner = original
  var handoff = default(CurrentAccumulationHandoff)
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.None
  assert handoff.cancel
  assert handoff.enqueue(owner, update) == CurrentHandoffAdmission.None
  handoff.process(owner)
  assert handoff.take.error == CurrentHandoffError.None
proc main() {.raises.} =
  ## Current production preparation supplies the exact owner; the handoff grants no preparation authority itself.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[index])
  let context = currentChainFixture(decodeOwnedReport(bytes, 2).value, available = true, blobs = true)
  let original = initApplicationChain(context.currentChainSeeded).value
  let update = original.prepareAccumulation(context.source, ByteLimit(100000)).value
  canonical(original, update)
  joint(original, update)
  cycle(original, update)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(original, update) # Every successful/refused ownership slot retires before the next activation.
  let after = getOccupiedMem()
  assert before == after, "current handoff releases"
  recordArcRelease("pvm_current_handoff", 1000, before, after)
  echo "PVM current handoff passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Missing signed fixtures or socket/native failures cannot pass the handoff witness.
except:
  quit(2)
