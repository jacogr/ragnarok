# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Listener routing binds completions to original sessions and isolates slow consumers without canonical access.

import std/[assertions, syncio, base64]

include ../../../src/rpc/server
include ../../support/rpc_stream_fixture

proc main() =
  ## Live streams carry proof requests and completion notifications through the dispatcher.
  var owner = default(Server)
  assert not owner.enableStateProofs()
  assert owner.start(fixturePort(), "proof routing")
  assert owner.enableStateProofs()
  let firstPeer = owner.fixtureConnect(0)
  let secondPeer = owner.fixtureConnect(1)
  defer:
    discard posix.close(firstPeer)
    discard posix.close(secondPeer)
  let info = ClientInfo(proofs: true)
  let hashText = base64.encode(default(array[32, byte]))
  let keyText = base64.encode(default(array[31, byte]))
  let call = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_requestStateProof\",\"id\":7,\"params\":[\"" &
      hashText & "\",[\"" & keyText & "\"]]}"
  fixture_socket.sendText(firstPeer, call)
  fixture_socket.sendText(secondPeer, call)
  assert "\"result\":1" in owner.fixtureFrame(firstPeer)
  assert "\"result\":1" in owner.fixtureFrame(secondPeer)
  let first = owner.takeStateProofRequest
  assert first.valid and first.index == 0
  assert owner.finishStateProof(first, default(StateRoot), [1'u8])
  fixture_socket.sendText(firstPeer, call)
  # The first completion is ahead of the new request only if it already left the FIFO.
  let next = owner.fixtureFrame(firstPeer)
  if "\"request\":1" in next:
    assert "\"result\":2" in owner.fixtureFrame(firstPeer)
  else:
    assert "\"result\":2" in next
    assert "\"request\":1" in owner.fixtureFrame(firstPeer)
  let second = owner.takeStateProofRequest
  assert second.index == 1 # A new request from the previous winner cannot starve the other consumer.
  let third = owner.takeStateProofRequest
  assert third.index == 0 and third.proofRequest.id == 2
  assert not owner.takeStateProofRequest.valid
  assert owner.finishStateProof(second, default(StateRoot), [], "Unavailable selected block")
  assert owner.finishStateProof(third, default(StateRoot), [2'u8])
  assert "\"request\":2" in owner.fixtureFrame(firstPeer)
  assert "\"error\":\"Unavailable selected block\"" in owner.fixtureFrame(secondPeer)
  # Reusing the slot and wire ID cannot reuse the retained private completion namespace.
  owner.connections[0].close()
  owner.fixtureEof(firstPeer)
  let replacementPeer = owner.fixtureConnect(0)
  defer: discard posix.close(replacementPeer)
  fixture_socket.sendText(replacementPeer, call)
  assert "\"result\":1" in owner.fixtureFrame(replacementPeer)
  let replacement = owner.takeStateProofRequest
  assert replacement.proofRequest.id == 1
  assert owner.finishStateProof(first, default(StateRoot), [3'u8])
  assert owner.connections[0].session.nextUpdate == ""
  let pause = owner.pauseChain()
  assert not owner.enableStateProofs()
  assert not owner.takeStateProofRequest.valid
  assert not owner.finishStateProof(replacement, default(StateRoot), [4'u8])
  assert owner.resumeChain(pause)
  assert owner.finishStateProof(replacement, default(StateRoot), [4'u8])
  assert "\"proof\":\"BA==\"" in owner.fixtureFrame(replacementPeer)
  # Terminal notifications use the shared FIFO: overflow closes only the originating consumer.
  owner.connections[0].session = default(RpcSession)
  for count in 1..MaxSubscriptionUpdates:
    discard respond(call, info, owner.connections[0].session)
    let selected = owner.takeStateProofRequest
    assert selected.index == 0 and selected.proofRequest.id == uint32(count)
    assert owner.finishStateProof(selected, default(StateRoot), [1'u8])
  discard respond(call, info, owner.connections[0].session)
  let overflowing = owner.takeStateProofRequest
  assert not owner.finishStateProof(overflowing, default(StateRoot), [1'u8])
  assert not owner.connections[0].opened and owner.connections[1].opened
  owner.fixtureEof(replacementPeer)
  owner.close()
  assert not owner.proofs and not owner.takeStateProofRequest.valid
  assert not owner.finishStateProof(second, default(StateRoot), [1'u8])

main()
shutdown()
echo "RPC proof transport checks passed"
