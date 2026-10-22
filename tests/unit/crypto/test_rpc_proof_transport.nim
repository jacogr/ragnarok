# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Listener routing binds completions to original sessions and isolates slow consumers without canonical access.
import std/[assertions, syncio, base64]
include ../../../src/rpc/server

proc descriptor(): cint =
  ## Use an actual owned native descriptor so every close path exercises real listener/slot retirement.
  result = socket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert result >= 0
proc attach(owner: var Server, index: int) =
  ## Routing-only tests bypass HTTP framing; the integration suite uses real WebSocket upgrades.
  owner.connections[index].fd = descriptor()
  owner.connections[index].opened = true
  owner.connections[index].upgraded = true

var owner = default(Server)
assert not owner.enableStateProofs()
owner.fd = descriptor()
owner.opened = true
assert owner.enableStateProofs()
owner.attach(0)
owner.attach(1)
let info = ClientInfo(proofs: true)
let hashText = base64.encode(default(array[32, byte]))
let keyText = base64.encode(default(array[31, byte]))
let call = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_requestStateProof\",\"id\":7,\"params\":[\"" &
    hashText & "\",[\"" & keyText & "\"]]}"
discard respond(call, info, owner.connections[0].session)
discard respond(call, info, owner.connections[1].session)
let first = owner.takeStateProofRequest
assert first.valid and first.index == 0
assert owner.finishStateProof(first, default(StateRoot), [1'u8])
discard respond(call, info, owner.connections[0].session)
let second = owner.takeStateProofRequest
assert second.index == 1 # A new request from the previous winner cannot starve the other consumer.
let third = owner.takeStateProofRequest
assert third.index == 0 and third.proofRequest.id == 2
assert not owner.takeStateProofRequest.valid
assert owner.finishStateProof(second, default(StateRoot), [], "Unavailable selected block")
assert owner.finishStateProof(third, default(StateRoot), [2'u8])
assert "\"request\":1" in owner.connections[0].session.nextUpdate
assert "\"request\":2" in owner.connections[0].session.nextUpdate
assert "\"error\":\"Unavailable selected block\"" in owner.connections[1].session.nextUpdate
# Reusing the slot and wire ID cannot reuse the retained private completion namespace.
owner.connections[0].session = default(RpcSession)
discard respond(call, info, owner.connections[0].session)
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
assert "\"proof\":\"BA==\"" in owner.connections[0].session.nextUpdate
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
owner.close()
assert not owner.proofs and not owner.takeStateProofRequest.valid
assert not owner.finishStateProof(second, default(StateRoot), [1'u8])
echo "RPC proof transport checks passed"
