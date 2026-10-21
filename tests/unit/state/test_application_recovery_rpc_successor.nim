# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Recovered canonical/RPC owners publish one freshly executed child and one matching notification together.
import std/[assertions, syncio, envvars, strutils, base64]
import std/posix/posix
import ../../../src/app/[services, chain, candidate, handoff]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/report_owned
import ../../../src/state/store
import ../../support/application_candidate_context as candidate_context
import ../../support/accumulation_completion_context
import ../../support/[application_recovery_execution, rpc_socket]
proc request(owner: var Services, peer: cint, pending: var string, text: string): string =
  ## Raw RPC ticks cannot consume pending application adoption, so pre-publication reads remain meaningful.
  sendText(peer, text)
  readPacket(owner.rpc, peer, pending)
proc main() {.raises.} =
  ## A genuine signed child is queued against the newly restored snapshot, independently of its original source graph.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw:
    report[index] = byte(octet) # Bound initialized fixture bytes before owned decoding.
  let fixture = recoveryFixture(decodeOwnedReport(report, 2).value)
  let reserved = reservation()
  discard posix.close(reserved.fd)
  var path = "application-recovery-rpc-successor-chain"
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  defer: owner.close()
  startRecoveredExecution(owner, fixture, path, candidate_context.policy(), reserved.port)
  let before = owner.stateSnapshot.value
  let anchor = base64.encode(array[32, byte](fixture.expected.blockHash))
  let peer = client(reserved.port)
  defer: discard posix.close(peer)
  var pending = ""
  upgrade(owner.rpc, peer, pending)
  let subscribed = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":1}""")
  assert "\"result\":1" in subscribed
  assert anchor in readPacket(owner.rpc, peer, pending)
  let queued = owner.enqueueCandidate(candidate_context.candidateBlock(fixture.origin), [],
      candidate_context.preparationLimits(), completionLimits().composition)
  assert queued.error == ApplicationCandidateError.None
  let old = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"bestBlock","id":2}""")
  assert "\"id\":2" in old and anchor in old
  assert sameStateSnapshot(before, owner.stateSnapshot.value) # RPC-only ticks cannot publish private execution output.
  owner.tick(0)
  assert owner.accumulationStage == AccumulationHandoffStage.Finished
  let adopted = owner.takeAccumulation()
  assert adopted.error == ApplicationChainError.None
  let head = base64.encode(array[32, byte](adopted.value.blockHash))
  assert head != anchor
  let notification = readPacket(owner.rpc, peer, pending)
  assert head in notification and "\"slot\":2" in notification
  let best = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"bestBlock","id":3}""")
  assert "\"id\":3" in best and head in best
  let parent = request(owner, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"parent\",\"params\":[\"" &
      head & "\"],\"id\":4}")
  assert "\"id\":4" in parent and anchor in parent
  let root = request(owner, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" &
      head & "\"],\"id\":5}")
  assert base64.encode(array[32, byte](adopted.value.stateRoot)) in root
  let oldRoot = request(owner, peer, pending, "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" &
      anchor & "\"],\"id\":6}")
  assert base64.encode(array[32, byte](fixture.expected.stateRoot)) in oldRoot
  let finality = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"finalizedBlock","id":7}""")
  assert "Finalized chain view unavailable" in finality
  let current = owner.stateSnapshot.value
  let replay = owner.applyAccumulation(queued.value, completionLimits().composition)
  assert replay.error == ApplicationChainError.RpcFailure
  assert sameStateSnapshot(current, owner.stateSnapshot.value)
  let after = request(owner, peer, pending, """{"jsonrpc":"2.0","method":"bestBlock","id":8}""")
  assert "\"id\":8" in after and head in after # No replay notification may precede the next genuine reply.
  assert owner.chainView.retainedCount == 2 and owner.chainView.finalizedBlock.error !=
      GenesisError.None
  echo "PASS application recovery RPC successor: deferred atomic views, exact notification, retained parent and replay silence"
try:
  main() # Native/transport failures cannot masquerade as an accepted canonical child.
except:
  quit(2)
