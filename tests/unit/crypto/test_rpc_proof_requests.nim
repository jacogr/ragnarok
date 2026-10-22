# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise independent selectors, exact completion authority, cancellation/reset and nonwrapping IDs.
import std/[assertions, syncio]
include ../../../src/rpc/proof_requests

var state = default(RpcProofState)
var keys = [default(StateKey)]
let selected = default(BlockHash)
assert not state.take.valid
assert not state.cancel(0)
assert state.enqueue(selected, []).error == RpcProofError.InvalidSelectors
assert state.enqueue(selected, [keys[0], keys[0]]).error == RpcProofError.InvalidSelectors
let admitted = state.enqueue(selected, keys)
assert admitted.error == RpcProofError.None and admitted.value.id == 1
assert state.active
assert not state.finish(admitted.value) # Queued work has not yet been claimed by the host.
var changed = default(array[31, byte])
changed[0] = 9
keys[0] = StateKey(changed)
assert array[31, byte](admitted.value.plan.keyAt(0).value)[0] == 0
assert state.enqueue(selected, keys).error == RpcProofError.Busy
let claimed = state.take
assert claimed.valid and not state.take.valid
var foreign = default(RpcProofState)
let other = foreign.enqueue(selected, keys)
assert other.value.id == claimed.id
let foreignClaim = foreign.take
assert not foreign.finish(claimed) and not state.finish(foreignClaim)
assert state.cancel(1) and not state.finish(claimed)
let replacement = state.enqueue(selected, keys)
assert replacement.value.id == 2
assert not state.finish(claimed)
let second = state.take
assert state.finish(second) and not state.finish(second)
# A replacement connection may restart public IDs but cannot reuse retained completion authority.
state = default(RpcProofState)
assert state.enqueue(selected, keys).value.id == 1
let resetClaim = state.take
assert not state.finish(claimed) and state.finish(resetClaim)
# Boundary refusal preserves the final valid ID and never wraps to the reserved zero.
state.last = high(uint32) - 1
let last = state.enqueue(selected, keys)
assert last.value.id == high(uint32)
let lastClaim = state.take
assert state.finish(lastClaim)
assert state.enqueue(selected, keys).error == RpcProofError.Exhausted
assert not state.active
# Exact selector ceiling and duplicate rejection apply before retaining a namespace or ID.
var many = newSeq[StateKey](MaxRpcProofKeys + 1)
for index in 0..<many.len:
  var raw = default(array[31, byte])
  raw[0] = byte(index)
  many[index] = StateKey(raw) # Every selector is independent and unique.
var capped = default(RpcProofState)
assert capped.enqueue(selected, many).error == RpcProofError.InvalidSelectors
many.setLen(MaxRpcProofKeys)
assert capped.enqueue(selected, many).value.id == 1
assert capped.take.plan.len == MaxRpcProofKeys
assert foreign.finish(foreignClaim)
echo "RPC proof request checks passed"
