# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authorization/store publication failures use only the existing test-owned crypto observer.
import std/[assertions, syncio]
import ../../support/[authorization_transition_fixture, arc_evidence]
import ../../../src/state/[authorization, store]
import ../../../src/codec/[state_trie, state_layout]

## Reset primitive counters or refuse the first hash; the production profile contains no observer.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
## Refuse after a complete child has been committed privately, before publishing the new store head.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count only attempted hash operations to distinguish validation/policy failure from backend refusal.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Finite limits independently bound the store map and one C(1) write.
proc policy(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(3), perValue: ByteLimit(6000),
    totalValueBytes: ByteLimit(12000), nodes: TrieNodeLimit(747)), writes: ElementLimit(1),
        writeValueBytes: ByteLimit(6000))

## Valid working state already contains posterior queues; repeated hashes are real ordered pool entries.
proc entries(): seq[StateEntry] =
  let config = authConfig()
  let pools = authorizationEntry(AuthorizationKind.Pools,
    @[@[authHash(1), authHash(2), authHash(1)], newSeq[AuthorizerHash](0)], config)
  let queues = authorizationEntry(AuthorizationKind.Queues, authQueues(), config)
  assert pools.error == AuthorizationError.None and queues.error == AuthorizationError.None
  @[pools.value, queues.value, StateEntry(key: chapterKey(StateChapter(11)), value: @[77'u8])]

## Verify failed publication preserves every entry and the complete prior commitment.
proc unchanged(state: StateStore, before: StateStoreSnapshot, source: seq[StateEntry]) =
  let current = state.snapshot.value
  assert array[32, byte](current.commitment.root) == array[32, byte](before.commitment.root)
  assert current.commitment.entries == source.len
  for entry in source:
    assert current.lookup(entry.key).value.bytes == entry.value # C(2) and unrelated chapters stay untouched too.

## Drop all owners through success, first/late refusal and recovery in each isolated ARC scope.
proc cycle() =
  fail(0)
  let source = entries()
  let made = newStateStore(source, policy())
  assert made.error == StateStoreError.None
  var state = made.value
  let before = state.snapshot.value
  let usage = @[CoreAuthorizer(core: AuthorizationCoreIndex(0), authorizer: authHash(1))]
  fail(1)
  assert advanceAuthorizationState(state, usage, AuthorizationSlot(79), authConfig()).error ==
      AuthorizationTransitionError.BackendFailure
  assert hashCalls() == 1
  unchanged(state, before, source)
  failAfter(3)
  assert advanceAuthorizationState(state, usage, AuthorizationSlot(79), authConfig()).error ==
      AuthorizationTransitionError.BackendFailure
  assert hashCalls() == 4
  unchanged(state, before, source)
  fail(0)
  let committed = advanceAuthorizationState(state, usage, AuthorizationSlot(79), authConfig())
  assert committed.error == AuthorizationTransitionError.None
  assert committed.value.lookup(source[0].key).value.bytes != source[0].value
  assert committed.value.lookup(source[1].key).value.bytes == source[1].value
  assert before.lookup(source[0].key).value.bytes == source[0].value

## Missing/malformed state and denied writes fail before hashing, never repairing or partially updating state.
proc invalidStates() =
  var uninitialized = default(StateStore)
  assert advanceAuthorizationState(uninitialized, [], AuthorizationSlot(0), authConfig()).error ==
      AuthorizationTransitionError.Uninitialized
  let source = entries()
  for which in 0..<3:
    fail(0)
    let subset = if which == 0: newSeq[StateEntry](0) elif which == 1: @[source[0]] else: @[source[1]]
    let made = newStateStore(subset, policy())
    assert made.error == StateStoreError.None
    var state = made.value
    let before = state.snapshot.value
    fail(1)
    assert advanceAuthorizationState(state, [], AuthorizationSlot(0), authConfig()).error ==
        AuthorizationTransitionError.MissingState
    assert hashCalls() == 0
    unchanged(state, before, subset)
  for which in 0..<3:
    fail(0)
    var malformed = entries()
    if which == 0:
      malformed[0].value.add 0 # A valid prefix with a suffix is not a complete C(1) value.
    elif which == 1:
      malformed[1].value.setLen(malformed[1].value.len-1) # A truncated fixed queue must not be padded.
    else:
      malformed[1].value.add 0 # A queue prefix with an extra octet is not a complete chapter either.
    let made = newStateStore(malformed, policy())
    assert made.error == StateStoreError.None
    var state = made.value
    let before = state.snapshot.value
    fail(1)
    assert advanceAuthorizationState(state, [], AuthorizationSlot(0), authConfig()).error ==
        AuthorizationTransitionError.InvalidState
    assert hashCalls() == 0
    unchanged(state, before, malformed)
  fail(0)
  var short = policy()
  short.writes = ElementLimit(0)
  let made = newStateStore(source, short)
  assert made.error == StateStoreError.None
  var state = made.value
  let before = state.snapshot.value
  fail(1)
  assert advanceAuthorizationState(state, [], AuthorizationSlot(0), authConfig()).error ==
      AuthorizationTransitionError.LimitExceeded
  assert hashCalls() == 0
  unchanged(state, before, source)
  var decoderLimit = authConfig()
  decoderLimit.maxBytes = ByteLimit(1)
  assert advanceAuthorizationState(state, [], AuthorizationSlot(0), decoderLimit).error ==
      AuthorizationTransitionError.LimitExceeded
  assert hashCalls() == 0
  unchanged(state, before, source)
  fail(0)

invalidStates()
# Warm native/allocator initialization before measuring repeated complete owner lifecycles.
for i in 0..<25: cycle()
let beforeRelease = getOccupiedMem()
# Each scope retires decoder owners, plans, proposed bytes, failed candidates and retained prior heads.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
recordArcRelease("authorization_transition_failure", 1000, beforeRelease, afterRelease)
fail(0)
echo "PASS authorization transition failures: malformed state, atomic rollback, backend recovery and ARC release"
