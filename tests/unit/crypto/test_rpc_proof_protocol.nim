# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict asynchronous proof method framing, transactional admission and bounded terminal notifications.
import std/assertions
import std/syncio
include ../../../src/rpc/protocol

let enabled = ClientInfo(proofs: true)
let disabled = ClientInfo()
var session = default(RpcSession)
let hashText = base64.encode(default(array[32, byte]))
var rawKey = default(array[31, byte])
rawKey[0] = 11
let keyText = base64.encode(rawKey)
let prefix = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_requestStateProof\",\"id\":7,\"params\":[" &
    quote(hashText) & ","
let call = prefix & "[" & quote(keyText) & "]]}"
let cancelCall = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_cancelStateProof\",\"id\":8,\"params\":[1]}"
assert "-32601" in respond(call, enabled)
assert "-32601" in respond(call, disabled, session)
assert not session.proofRequests.active
let diagnostic = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_clientInfo\",\"id\":1}"
assert "\"stateProofs\":true" in respond(diagnostic, enabled, session)
assert "ragnarok_requestStateProof" notin respond(diagnostic,
    enabled) # Stateless adapters cannot advertise a host bridge.
for malformed in ["[]", "null", "[1]", "[[" & quote(keyText) & "]]", "[\"bad\"]",
    "[" & quote(keyText) & "," & quote(keyText) & "]"]:
  assert "-32602" in respond(prefix & malformed & "]}", enabled, session) # Refusal cannot allocate a request ID.
assert not session.takeStateProofRequest.valid
assert respond(call.replace(",\"id\":7", ""), enabled, session) == ""
assert not session.takeStateProofRequest.valid
assert respond(call, enabled, session) == "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":1}"
assert "\"code\":0" in respond(call, enabled, session)
let first = session.takeStateProofRequest
assert first.valid and first.plan.len == 1
assert array[31, byte](first.plan.keyAt(0).value) == rawKey
assert not session.takeStateProofRequest.valid
assert respond(cancelCall, enabled, session) == "{\"jsonrpc\":\"2.0\",\"id\":8,\"result\":true}"
assert session.completeStateProof(first, default(StateRoot), [1'u8])
assert session.nextUpdate == "" # Cancelled completion grants no new terminal message.
assert "\"result\":false" in respond(cancelCall, enabled, session)
assert "\"result\":2" in respond(call, enabled, session)
let second = session.takeStateProofRequest
assert session.completeStateProof(second, default(StateRoot), [1'u8, 2, 3])
let message = session.nextUpdate
assert message == "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_stateProof\",\"params\":{\"request\":2,\"result\":{\"header_hash\":" &
    quote(hashText) &
  ",\"state_root\":" & quote(hashText) & ",\"format\":\"RPV1\",\"proof\":\"AQID\"}}}"
assert session.completeStateProof(second, default(StateRoot), [1'u8]) and session.nextUpdate == ""
# Cancellation in an ordered batch removes intent before the host can dispatch it.
var batched = default(RpcSession)
let batch = respond("[" & call & "," & cancelCall & "]", enabled, batched)
assert "\"result\":1" in batch and "\"result\":true" in batch
assert not batched.takeStateProofRequest.valid
# A reply-budget refusal rolls back the selector/ID reservation with the rest of the candidate session.
var tokens: seq[JsonToken] = @[]
assert parseValues(call, tokens)
var budgetSession = default(RpcSession)
assert "output budget" in dispatch(tokens, 0, enabled, budgetSession, true, 1)
assert not budgetSession.proofRequests.active
assert "\"result\":1" in respond(call, enabled, budgetSession)
let pending = budgetSession.takeStateProofRequest
for index in 0..<MaxSubscriptionUpdates:
  budgetSession.enqueueUpdate(SubscriptionId(99), "{}") # Exhaust real shared FIFO slots without mutating counters.
assert not budgetSession.completeStateProof(pending, default(StateRoot), [1'u8])
assert budgetSession.proofRequests.active and budgetSession.pendingCount == MaxSubscriptionUpdates
assert budgetSession.nextUpdate == "{}"
assert budgetSession.completeStateProof(pending, default(StateRoot), [1'u8])
assert not budgetSession.proofRequests.active
# Native wire oversize produces a terminal error, never Base64 allocation for a truncated prefix.
var oversized = default(RpcSession)
discard respond(call, enabled, oversized)
let oversizedRequest = oversized.takeStateProofRequest
assert oversized.completeStateProof(oversizedRequest, default(StateRoot), newSeq[byte](
    MaxRpcProofBytes + 1))
let refused = oversized.nextUpdate
assert "\"error\":\"State proof exceeds RPC output budget\"" in refused
assert "\"result\"" notin refused and "\"proof\"" notin refused
# Byte capacity refusal preserves both selectors and exact queue accounting until the listener disconnects.
var bytesFull = default(RpcSession)
discard respond(call, enabled, bytesFull)
let bytesRequest = bytesFull.takeStateProofRequest
bytesFull.enqueueUpdate(SubscriptionId(99), quote(repeat("x", MaxSubscriptionQueueBytes - 4)))
let retainedBytes = bytesFull.pendingBytes
assert not bytesFull.completeStateProof(bytesRequest, default(StateRoot), [1'u8])
assert bytesFull.pendingCount == 1 and bytesFull.pendingBytes == retainedBytes
assert bytesFull.proofRequests.active
# Full selector width/count validation applies before any immutable plan or host work is retained.
var selectedKeys = JsonArray()
for index in 0..MaxRpcProofKeys:
  var raw = default(array[31, byte])
  raw[0] = byte(index)
  selectedKeys.add(json(base64.encode(raw))) # Seventeen distinct fixed-width keys exceed the request ceiling.
var countSession = default(RpcSession)
assert "-32602" in respond(prefix & $json(selectedKeys) & "]}", enabled, countSession)
assert not countSession.proofRequests.active
assert "-32602" in respond(call.replace(hashText, "bad"), enabled, countSession)
echo "RPC proof protocol checks passed"
