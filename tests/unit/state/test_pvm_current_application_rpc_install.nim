# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_application_rpc_install_arc_release"}

## Genuine current prepared updates join canonical/RPC ownership under exact leases and deliver actual WebSocket best-head events.
import std/assertions
import std/envvars
import std/syncio
import std/base64
import std/strutils
import std/posix/posix
import ../../../src/app/chain as app_chain
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/rpc/server as rpc_server
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_current_consensus as state_accumulation_current_consensus
import ../../../src/state/accumulation_current_chain as state_accumulation_current_chain
import ../../../src/state/store as state_store
import ../../support/state_accumulation_current_chain_context
import ../../support/rpc_socket
import ../../support/testing_arc_evidence
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
const Subscribe = """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}"""
const Best = """{"jsonrpc":"2.0","method":"bestBlock","id":1}"""
proc listener(rpc: var Server, view: ChainView): uint16 =
  ## Retry only the bounded ephemeral reservation/start race; never use fixed ports or private server fields.
  let parameters = decodeParameters(currentChainSettings().encodeParameters)
  for attempt in 0..<8:
    let selected = reservation()
    discard posix.close(selected.fd)
    if rpc.start(selected.port, "current-pvm-test", parameters, view): return selected.port
  assert false, "current RPC ephemeral startup failed"
  0
proc canonical(context: CurrentChainFixture) =
  ## Canonical-only preparation stays private; install/ack retain the exact child without hashing or replay.
  var owner = initApplicationChain(context.currentChainSeeded).value
  let before = owner
  let prepared = owner.prepareAccumulation(context.source, ByteLimit(100000))
  assert prepared.error == CurrentChainPreparationError.None
  let update = prepared.value
  assert owner.canInstallPrepared(update)
  assert sameStateSnapshot(owner.stateSnapshot.value, before.stateSnapshot.value)
  failHash(3)
  owner.installPrepared(update)
  let acknowledged = owner.installedPrepared(update)
  assert acknowledged.error == ApplicationChainError.None
  assert sameStateSnapshot(acknowledged.value.stateSnapshot, update.currentUpdateState)
  assert sameChainView(owner.chainView, update.currentUpdateView)
  assert sameStateSnapshot(before.stateSnapshot.value, context.parent.value.stateSnapshot)
  assert hashCalls() == 0
  assert not owner.canInstallPrepared(update), "replay retains original-parent refusal"
  failHash(0)
proc joint(context, foreign: CurrentChainFixture) =
  ## Real subscription frames observe the current child only after canonical/RPC ownership joins under its exact lease.
  let original = context.currentChainSeeded
  var owner = initApplicationChain(original).value
  let before = owner
  let prepared = owner.prepareAccumulation(context.source, ByteLimit(100000)).value
  var closed = default(Server)
  assert not owner.canInstallPrepared(closed, prepared), "closed RPC cannot join current installation"
  var mismatched = default(Server)
  discard listener(mismatched, foreign.currentChainSeeded)
  assert not owner.canInstallPrepared(mismatched, prepared), "foreign RPC history cannot join canonical ownership"
  mismatched.close()
  var rpc = default(Server)
  let port = listener(rpc, original)
  let peer = client(port)
  defer: discard posix.close(peer) # Caller retains descriptor ownership through bounded packet polling.
  var pending = ""
  upgrade(rpc, peer, pending)
  sendText(peer, Subscribe)
  assert "\"result\":1" in readPacket(rpc, peer, pending)
  assert "\"slot\":1" in readPacket(rpc, peer, pending)
  let lease = rpc.pauseChain()
  assert lease != nil and rpc.chainPaused
  var other = default(Server)
  let foreignLease = other.pauseChain()
  assert foreignLease != nil
  assert not owner.canInstallPrepared(rpc, prepared)
  assert not owner.canInstallPrepared(rpc, prepared, foreignLease)
  assert not rpc.resumeChain(foreignLease), "same marker cannot substitute a different lease identity"
  assert other.resumeChain(foreignLease)
  assert owner.canInstallPrepared(rpc, prepared, lease)
  let alternate = initApplicationChain(foreign.currentChainSeeded).value
  assert not alternate.canInstallPrepared(rpc, prepared, lease)
  failHash(3)
  owner.installPrepared(rpc, prepared, lease)
  let acknowledgment = owner.installedPrepared(prepared)
  assert acknowledgment.error == ApplicationChainError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, prepared.currentUpdateState)
  assert sameChainView(owner.chainView, prepared.currentUpdateView)
  assert sameChainView(before.chainView, original), "historical canonical alias remains unchanged"
  assert rpc.chainPaused and not owner.canInstallPrepared(rpc, prepared, lease)
  assert hashCalls() == 0, "joint installation and acknowledgment do not hash or recapture"
  assert rpc.resumeChain(lease)
  failHash(0)
  let identity = base64.encode(array[32, byte](prepared.currentUpdateChild.blockHash))
  let event = readPacket(rpc, peer, pending)
  assert "subscribeBestBlock" in event and identity in event, "subscriber receives actual current child identity"
  sendText(peer, Best)
  assert identity in readPacket(rpc, peer, pending), "RPC selected head agrees with canonical current state"
  rpc.close()
proc cycle(context: CurrentChainFixture) =
  ## Scoped canonical preparation/install/acknowledgment releases every new immutable child and view.
  var owner = initApplicationChain(context.currentChainSeeded).value
  let update = owner.prepareAccumulation(context.source, ByteLimit(100000)).value
  owner.installPrepared(update)
  assert owner.installedPrepared(update).error == ApplicationChainError.None
proc main() {.raises.} =
  ## The launcher supplies signed report bytes; every child uses genuine current execution and composition.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact transport bytes.
  let base = decodeOwnedReport(wire, 2).value
  let quiet = currentChainFixture(base)
  let combined = currentChainFixture(base, uses = 2, available = true, blobs = true)
  canonical(quiet)
  canonical(combined)
  joint(combined, quiet)
  var absent = default(ApplicationChain)
  let refused = absent.prepareAccumulation(quiet.source, ByteLimit(100000))
  assert refused.error == CurrentChainPreparationError.ChainFailure
  assert refused.chainFailure.error == CurrentAccumulationChainError.StateFailure
  cycle(combined)
  let occupied = getOccupiedMem()
  for iteration in 0..<1000: cycle(combined) # Every canonical candidate/view lifetime stays within one cycle.
  let after = getOccupiedMem()
  assert occupied == after, "current application update ownership releases"
  recordArcRelease("pvm_current_application_rpc_install", 1000, occupied, after)
  echo "PVM current application RPC install passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected native/socket/source failures fail the suite.
except:
  quit(2)
