# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded detached light metadata and the shared RPC request namespace reject malformed, foreign and cancelled imports atomically.
# @@Verification={"arc":"light_rpc_protocol_arc_release"}
import std/[assertions, syncio, base64, strutils]
import ../../support/[application_checkpoint_context, arc_evidence]
import ../../../src/app/chain
import ../../../src/app/checkpoint/identity as checkpoint_identity
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, header]
import ../../../src/codec/state/trie as state_trie
import ../../../src/rpc/[protocol, proof_requests, light_source]
proc source(): RpcLightHead {.raises.} =
  ## Complete fixture context is transient test input; the resulting RPC owner retains only copied metadata.
  let owner = checkpointFixture()
  let head = owner.chainView.bestBlock.value
  var wire = newSeq[byte](head.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(head.header, wire).error == HeaderError.None
  let profile = HeaderConfig(cores: head.cores, authorValidators: head.activeValidators,
    epochSlots: head.epochSlots, maxBytes: ByteLimit(262144))
  var input = @[RpcLightHeaderInput(blockHash: head.blockHash, stateRoot: head.stateRoot,
    slot: head.slot, wire: wire)]
  result = captureRpcLightHead(input, profile, 0).value
  input[0].wire[0] = input[0].wire[0] xor 1 # Caller mutation cannot alter the captured sealed header.
  var output = newSeq[byte](wire.len)
  assert result.current.copyHeader(output) and output == wire
  var short = @[99'u8]
  assert not result.current.copyHeader(short) and short == @[99'u8]
  assert not result.headerAt(-1).valid and not result.headerAt(1).valid
  assert captureRpcLightHead(input, profile, 257).error == RpcLightSourceError.LimitExceeded
  assert captureRpcLightHead(newSeq[RpcLightHeaderInput](9), profile, 0).error ==
      RpcLightSourceError.LimitExceeded
  input[0].wire = wire
  input[0].slot = input[0].slot xor 1
  assert captureRpcLightHead(input, profile, 0).error == RpcLightSourceError.InvalidHeader
proc call(wire: openArray[byte]): string =
  ## RPV1 framing is transport-only; authenticating the proof belongs to the bounded CPU worker.
  "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ragnarok_importStateProof\",\"params\":[" &
    quote(base64.encode(default(array[32, byte]))) & "," & quote(base64.encode(wire)) & "]}"
proc cycle(info: ClientInfo) =
  ## Each complete request/session lifetime releases its detached wire, namespace and terminal notification.
  var session = default(RpcSession)
  let wire = @[byte('R'), byte('P'), byte('V'), byte('1'), 0'u8, 0, 0, 0]
  assert "\"result\":1" in respond(call(wire), info, session)
  let request = session.takeStateProofRequest
  assert request.isImport and request.importBytes == wire
  assert session.completeStateProofImport(request, info.light.stateRoot, 0)
  assert "ragnarok_stateProofImported" in session.nextUpdate
proc main() {.raises.} =
  ## Production public entry points preserve the same one-slot read/import namespace, cancellation and strict framing budgets.
  let light = source()
  let info = ClientInfo(light: light, proofs: true)
  var session, foreign = default(RpcSession)
  var wire = @[byte('R'), byte('P'), byte('V'), byte('1'), 0'u8, 0, 0, 0]
  let imported = call(wire)
  let full = ClientInfo(proofs: true)
  assert "-32601" in respond(imported, full, session)
  assert "-32601" in respond(imported, info) # A stateless adapter cannot reserve host work.
  assert "-32602" in respond(call(newSeq[byte](7)), info, session)
  assert "-32602" in respond(call(newSeq[byte](MaxRpcProofImportBytes+1)), info, session)
  assert respond(imported.replace(",\"id\":7", ""), info, session) == ""
  assert not session.takeStateProofRequest.valid
  assert "\"result\":1" in respond(imported, info, session)
  let selected = session.takeStateProofRequest
  assert selected.isImport and selected.importByteLength == 8
  var detached = selected.importBytes
  detached[0] = 0
  assert selected.importBytes[0] == byte('R') # Mutable output never aliases queued evidence.
  assert "\"code\":0" in respond(imported, info, session)
  assert "\"result\":1" in respond(imported, info, foreign)
  let other = foreign.takeStateProofRequest
  assert session.completeStateProofImport(other, default(StateRoot), 0)
  assert session.nextUpdate == "" # Equal numeric IDs in foreign namespaces cannot consume local intent.
  assert not session.completeStateProof(selected, default(StateRoot), [
      1'u8]) # Read completion cannot satisfy an import.
  assert session.completeStateProofImport(selected, info.light.stateRoot, 2)
  assert "\"knownFacts\":2" in session.nextUpdate
  assert "\"result\":2" in respond(imported, info, session)
  let cancelled = session.takeStateProofRequest
  let cancel = "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"ragnarok_cancelStateProof\",\"params\":[2]}"
  assert "\"result\":true" in respond(cancel, info, session)
  assert session.completeStateProofImport(cancelled, info.light.stateRoot, 2) and
      session.nextUpdate == ""
  var batch = default(RpcSession)
  let combined = respond("[" & imported & "," & cancel.replace("[2]", "[1]") & "]", info, batch)
  assert "\"result\":1" in combined and "\"result\":true" in combined and
      not batch.takeStateProofRequest.valid
  cycle(info)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(info) # Complete session lifetimes, not process/thread heaps, define this ARC assertion.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("light_rpc_protocol", 1000, before, after)
  echo "light RPC protocol: ok"
try:
  main()
except:
  quit(2) # Independent fixture setup errors fail the suite.
