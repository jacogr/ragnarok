# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published RawState prefix framing, detached ownership and atomic resource/root refusals.
import std/[assertions, syncio]
import ../../../src/state/[trace_state, store]
import ../../../src/codec/[state_layout, state_trie, bounded]

proc policy(): StateStoreLimits =
  ## Tiny independent limits isolate descriptor, value and trie refusal paths.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(200),
      totalValueBytes: ByteLimit(300), nodes: TrieNodeLimit(1024)),
      writes: ElementLimit(4), writeValueBytes: ByteLimit(300))
proc key(value: byte): StateKey =
  ## Authored complete keys differ in their first octet.
  var bytes = default(array[31, byte])
  bytes[0] = value
  StateKey(bytes)
proc main() =
  ## Wire and map owners survive destructive input/output mutations; no failed alternative grants an owner.
  let absentOutcome = default(TraceStateResult[TraceState])
  assert absentOutcome.error == TraceStateError.Uninitialized
  let absent = default(TraceState)
  assert absent.traceStateInfo.error == TraceStateError.InvalidOwner
  assert absent.traceStateSnapshot.error == TraceStateError.InvalidOwner
  assert absent.copyTraceState(ByteLimit(1000)).error == TraceStateError.InvalidOwner
  assert encodeTraceState(default(StateStoreSnapshot), ByteLimit(1000)).error ==
      TraceStateError.InvalidOwner
  let original = newStateStore([StateEntry(key: key(2), value: @[1'u8, 2]),
      StateEntry(key: key(1), value: @[])], policy()).value.snapshot.value
  let expected = encodeTraceState(original, ByteLimit(1000)).value
  assert expected.len == 99 and expected[32] == 2 and expected[64] == 0
  for ceiling in 0..<expected.len:
    assert encodeTraceState(original, ByteLimit(ceiling)).error ==
        TraceStateError.LimitExceeded # Every one-short output extent fails before allocation.
  var input = expected
  input.add(99)
  let decoded = decodeTraceState(input, policy(), ByteLimit(expected.len))
  assert decoded.error == TraceStateError.None
  let owner = decoded.value
  assert owner.traceStateInfo.value.consumed == expected.len
  for index in 0..<input.len: input[index] = 0 # The validated prefix is detached from caller storage.
  var copied = owner.copyTraceState(ByteLimit(1000)).value
  assert copied == expected
  copied[0] = copied[0] xor 1
  assert owner.copyTraceState(ByteLimit(1000)).value == expected
  assert owner.traceStateSnapshot.value.lookup(key(1)).value.bytes.len == 0
  assert owner.copyTraceState(ByteLimit(expected.len-1)).error == TraceStateError.LimitExceeded
  var badRoot = expected
  badRoot[0] = badRoot[0] xor 1
  assert decodeTraceState(badRoot, policy(), ByteLimit(1000)).error == TraceStateError.RootMismatch
  for length in 0..<expected.len:
    var short = newSeq[byte](length)
    for index in 0..<length: short[index] = expected[index] # Cut every fixed field, natural and payload boundary.
    assert decodeTraceState(short, policy(), ByteLimit(1000)).error != TraceStateError.None
  let empty = newStateStore([], policy()).value.snapshot.value
  let emptyWire = encodeTraceState(empty, ByteLimit(1000)).value
  assert emptyWire == newSeq[byte](33)
  assert decodeTraceState(emptyWire, policy(), ByteLimit(33)).error == TraceStateError.None
  assert decodeTraceState(expected, policy(), ByteLimit(98)).error == TraceStateError.LimitExceeded
  var limited = policy()
  limited.trie.items = ElementLimit(1)
  assert decodeTraceState(expected, limited, ByteLimit(1000)).error == TraceStateError.LimitExceeded
  limited = policy()
  limited.trie.totalValueBytes = ByteLimit(1)
  assert decodeTraceState(expected, limited, ByteLimit(1000)).error == TraceStateError.LimitExceeded
  limited = policy()
  limited.trie.nodes = TrieNodeLimit(0)
  assert decodeTraceState(expected, limited, ByteLimit(1000)).error == TraceStateError.LimitExceeded
  echo "PASS published RawState wire: complete roots, bounded prefixes and detached immutable ownership"
main()
