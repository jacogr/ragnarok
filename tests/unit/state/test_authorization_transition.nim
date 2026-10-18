# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 authorization STF vectors plus literal oldest-removal, queue-cycle and atomic-store tests.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../support/authorization_transition_fixture
import ../../../src/state/[authorization, store]
import ../../../src/codec/[state_trie, state_layout]

## Parse exact trusted fixture hex; malformed fixture transport fails independently from transition results.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    for c in pair: assert c in {'0'..'9', 'a'..'f'} # Preserve lowercase fixture byte identities.
    var octet = 0'u8
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Parse the complete unsigned transport domain without signed narrowing.
proc unsigned(text: string): uint64 =
  var number = 0'u64
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

## Observe output through the public codec owner API, preserving every sequence position and duplicate.
proc pool(entry: StateEntry, core: int, config: AuthorizationConfig): AuthorizerRow =
  assert array[31, byte](entry.key) == array[31, byte](chapterKey(StateChapter(1)))
  let decoded = decodeAuthorization(AuthorizationKind.Pools, entry.value, config)
  assert decoded.error == AuthorizationError.None and decoded.value.consumed == entry.value.len
  let owner = decoded.value.snapshot
  let count = authorizerCount(owner, AuthorizationCoreIndex(uint64(core)))
  assert count.error == AuthorizationError.None
  result = newSeq[AuthorizerHash](count.value)
  for i in 0..<result.len:
    let hash = authorizerAt(owner, AuthorizationCoreIndex(uint64(core)), AuthorizationIndex(uint64(i)))
    assert hash.error == AuthorizationError.None
    result[i] = hash.value

## Check literal expected row bytes without implementing a second transition algorithm.
proc expect(entry: StateEntry, core: int, expected: openArray[byte]) =
  let actual = pool(entry, core, authConfig())
  assert actual.len == expected.len
  for i, number in expected: assert actual[i].bytes == authHash(number).bytes # Exact ordered duplicates matter.

## Complete-map storage policy is separate from the authorization codec's own component budgets.
proc storePolicy(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(3), perValue: ByteLimit(1000000),
    totalValueBytes: ByteLimit(2000000), nodes: TrieNodeLimit(747)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(1000000))

## Cover oldest-only subtraction, suffix truncation, input ownership and post-accumulation queue selection.
proc literals() =
  let config = authConfig()
  var rows = @[@[authHash(1), authHash(2), authHash(1), authHash(3), authHash(4), authHash(5),
      authHash(6), authHash(7)],
    @[authHash(10), authHash(11), authHash(12), authHash(13), authHash(14), authHash(15), authHash(
        16), authHash(17)]]
  var queues = authQueues()
  queues[0][79] = authHash(1)
  queues[1][79] = authHash(99)
  let pools = authOwner(AuthorizationKind.Pools, rows)
  let posterior = authOwner(AuthorizationKind.Queues, queues)
  let usage = @[CoreAuthorizer(core: AuthorizationCoreIndex(0), authorizer: authHash(1))]
  let advanced = advanceAuthorization(pools, posterior, usage, AuthorizationSlot(79), config)
  assert advanced.error == AuthorizationTransitionError.None
  expect(advanced.value, 0, [2'u8, 1, 3, 4, 5, 6, 7, 1])
  expect(advanced.value, 1, [11'u8, 12, 13, 14, 15, 16, 17, 99])
  assert authorizerAt(pools, AuthorizationCoreIndex(0), AuthorizationIndex(0)).value.bytes ==
      authHash(1).bytes
  rows[0][0] = authHash(200)
  queues[0][79] = authHash(201)
  assert authorizerAt(posterior, AuthorizationCoreIndex(0), AuthorizationIndex(79)).value.bytes ==
      authHash(1).bytes
  expect(advanced.value, 0, [2'u8, 1, 3, 4, 5, 6, 7, 1])
  let empty = authOwner(AuthorizationKind.Pools, @[newSeq[AuthorizerHash](0), newSeq[
      AuthorizerHash](0)])
  let cycle = authOwner(AuthorizationKind.Queues, authQueues())
  let slots = [0'u32, 79, 80, 81, high(uint32)]
  let positions = [0'u8, 79, 0, 1, 15]
  for i in 0..<slots.len:
    let moved = advanceAuthorization(empty, cycle, [], AuthorizationSlot(slots[i]), config)
    assert moved.error == AuthorizationTransitionError.None
    expect(moved.value, 0, [positions[i]]) # Includes E4 maximum without wrapping before modulo.
  let repeated = authOwner(AuthorizationKind.Pools, @[@[authHash(1), authHash(2), authHash(1)],
      newSeq[AuthorizerHash](0)])
  let oldest = advanceAuthorization(repeated, cycle, usage, AuthorizationSlot(0), config)
  assert oldest.error == AuthorizationTransitionError.None
  expect(oldest.value, 0, [2'u8, 1, 0]) # Removing the last match, every match or no match all give different rows.
  let absent = advanceAuthorization(pools, posterior,
    @[CoreAuthorizer(core: AuthorizationCoreIndex(0), authorizer: authHash(250))],
        AuthorizationSlot(79), config)
  assert absent.error == AuthorizationTransitionError.None
  expect(absent.value, 0, [2'u8, 1, 3, 4, 5, 6, 7,
      1]) # Absent subtraction leaves the original prefix until suffix capping.
  let defaultResult = default(AuthorizationTransitionResult[StateEntry])
  assert defaultResult.error == AuthorizationTransitionError.Uninitialized
  assert advanceAuthorization(default(AuthorizationSnapshot), posterior, [], AuthorizationSlot(0),
      config).error == AuthorizationTransitionError.InvalidState
  assert advanceAuthorization(pools, default(AuthorizationSnapshot), [], AuthorizationSlot(0),
      config).error == AuthorizationTransitionError.InvalidState
  assert advanceAuthorization(posterior, pools, [], AuthorizationSlot(0), config).error ==
      AuthorizationTransitionError.InvalidState
  let duplicate = @[usage[0], usage[0]]
  assert advanceAuthorization(pools, posterior, @[usage[0], usage[0], usage[0]], AuthorizationSlot(
      0), config).error == AuthorizationTransitionError.DuplicateCore
  assert advanceAuthorization(pools, posterior, duplicate, AuthorizationSlot(0), config).error ==
      AuthorizationTransitionError.DuplicateCore
  for ordinal in [2'u64, high(uint64)]:
    let invalid = @[CoreAuthorizer(core: AuthorizationCoreIndex(ordinal), authorizer: authHash(1))]
    assert advanceAuthorization(pools, posterior, invalid, AuthorizationSlot(0), config).error ==
        AuthorizationTransitionError.InvalidCore
  var bad = config
  bad.cores = CoreCount(1)
  assert advanceAuthorization(pools, posterior, [], AuthorizationSlot(0), bad).error ==
      AuthorizationTransitionError.InvalidConfig
  bad.cores = CoreCount(high(uint64))
  assert advanceAuthorization(pools, posterior, [], AuthorizationSlot(0), bad).error ==
      AuthorizationTransitionError.InvalidConfig
  bad = config
  bad.maxHashes = ElementLimit(1)
  assert advanceAuthorization(pools, posterior, [], AuthorizationSlot(0), bad).error ==
      AuthorizationTransitionError.LimitExceeded
  bad = config
  bad.maxBytes = ByteLimit(65)
  assert advanceAuthorization(empty, posterior, [], AuthorizationSlot(0), bad).error ==
      AuthorizationTransitionError.LimitExceeded
  # The last core can exhaust either output budget after earlier rows preflight successfully.
  bad = config
  bad.maxHashes = ElementLimit(15)
  assert advanceAuthorization(pools, posterior, [], AuthorizationSlot(0), bad).error ==
      AuthorizationTransitionError.LimitExceeded
  bad = config
  bad.maxBytes = ByteLimit(513)
  assert advanceAuthorization(pools, posterior, [], AuthorizationSlot(0), bad).error ==
      AuthorizationTransitionError.LimitExceeded
  bad.maxBytes = ByteLimit(514)
  bad.maxHashes = ElementLimit(16)
  assert advanceAuthorization(pools, posterior, [], AuthorizationSlot(0), bad).error ==
      AuthorizationTransitionError.None
  bad.maxBytes = ByteLimit(high(uint64))
  bad.maxHashes = ElementLimit(high(uint64))
  assert advanceAuthorization(pools, posterior, [], AuthorizationSlot(0), bad).error ==
      AuthorizationTransitionError.None

## Accumulation may replace C(2) before this stage; only its current posterior value supplies new pool entries.
proc posteriorQueueState() =
  let config = authConfig()
  let pools = authorizationEntry(AuthorizationKind.Pools, @[newSeq[AuthorizerHash](0), newSeq[
      AuthorizerHash](0)], config)
  let oldQueues = authorizationEntry(AuthorizationKind.Queues, authQueues(), config)
  assert pools.error == AuthorizationError.None and oldQueues.error == AuthorizationError.None
  let made = newStateStore(@[pools.value, oldQueues.value], storePolicy())
  assert made.error == StateStoreError.None
  var state = made.value
  let original = state.snapshot.value
  var posterior = authQueues()
  posterior[0][0] = authHash(200)
  posterior[1][0] = authHash(201)
  let changed = authorizationEntry(AuthorizationKind.Queues, posterior, config)
  assert changed.error == AuthorizationError.None
  assert state.apply(@[StateWrite(key: changed.value.key, kind: StateWriteKind.Put,
      value: changed.value.value)]).error == StateStoreError.None
  let advanced = advanceAuthorizationState(state, [], AuthorizationSlot(0), config)
  assert advanced.error == AuthorizationTransitionError.None
  let encodedPools = StateEntry(key: pools.value.key, value: advanced.value.lookup(
      pools.value.key).value.bytes)
  expect(encodedPools, 0, [200'u8])
  expect(encodedPools, 1, [201'u8])
  assert advanced.value.lookup(oldQueues.value.key).value.bytes == changed.value.value
  assert original.lookup(oldQueues.value.key).value.bytes == oldQueues.value.value

## Run every published tiny/full STF case directly against native transition and store entry points.
proc published() {.raises.} =
  let path = getEnv("RAGNAROK_AUTHORIZATION_STF")
  assert path.len > 0
  let lines = readFile(path).splitLines()
  assert lines.len == 25 and lines[24] == ""
  for caseIndex in 0..<6:
    let input = lines[4*caseIndex].splitWhitespace()
    assert input.len >= 3
    let cores = unsigned(input[0])
    assert cores == (if caseIndex < 3: 2'u64 else: 341'u64)
    let config = authConfig(int(cores))
    let slot = unsigned(input[1])
    assert slot <= uint64(high(uint32))
    let count = unsigned(input[2])
    assert count <= cores and uint64(input.len) == 3+count*2
    var uses = newSeq[CoreAuthorizer](int(count))
    for i in 0..<uses.len:
      let core = unsigned(input[3+2*i])
      let raw = unhex(input[4+2*i])
      assert raw.len == 32 and core < cores
      var hash = default(array[32, byte])
      for j in 0..<32: hash[j] = raw[j] # Preserve the exact projected authorizer bytes.
      uses[i] = CoreAuthorizer(core: AuthorizationCoreIndex(core), authorizer: AuthorizerHash(bytes: hash))
    let poolBytes = unhex(lines[4*caseIndex+1])
    let queueBytes = unhex(lines[4*caseIndex+2])
    let expected = unhex(lines[4*caseIndex+3])
    let pools = decodeAuthorization(AuthorizationKind.Pools, poolBytes, config)
    let queues = decodeAuthorization(AuthorizationKind.Queues, queueBytes, config)
    assert pools.error == AuthorizationError.None and pools.value.consumed == poolBytes.len
    assert queues.error == AuthorizationError.None and queues.value.consumed == queueBytes.len
    let advanced = advanceAuthorization(pools.value.snapshot, queues.value.snapshot, uses,
        AuthorizationSlot(uint32(slot)), config)
    assert advanced.error == AuthorizationTransitionError.None and advanced.value.value == expected
    let entries = @[StateEntry(key: chapterKey(StateChapter(1)), value: poolBytes),
      StateEntry(key: chapterKey(StateChapter(2)), value: queueBytes),
      StateEntry(key: chapterKey(StateChapter(11)), value: @[99'u8])]
    let initialized = newStateStore(entries, storePolicy())
    assert initialized.error == StateStoreError.None
    var state = initialized.value
    let before = state.snapshot.value
    let committed = advanceAuthorizationState(state, uses, AuthorizationSlot(uint32(slot)), config)
    assert committed.error == AuthorizationTransitionError.None
    assert committed.value.lookup(entries[0].key).value.bytes == expected
    assert committed.value.lookup(entries[1].key).value.bytes == queueBytes
    assert committed.value.lookup(entries[2].key).value.bytes == @[99'u8]
    assert before.lookup(entries[0].key).value.bytes == poolBytes
    # Integration roots are derived partial-map commitments, not published full-state roots.
    let expectedRoot = stateTrieRoot(@[StateEntry(key: entries[0].key, value: expected), entries[1],
        entries[2]], storePolicy().trie)
    assert expectedRoot.error == StateTrieError.None
    assert array[32, byte](committed.value.commitment.root) == array[32, byte](
        expectedRoot.value.root)
    var short = storePolicy()
    short.writes = ElementLimit(0)
    let limited = newStateStore(entries, short)
    assert limited.error == StateStoreError.None
    var blocked = limited.value
    assert advanceAuthorizationState(blocked, uses, AuthorizationSlot(uint32(slot)),
        config).error == AuthorizationTransitionError.LimitExceeded
    assert blocked.snapshot.value.lookup(entries[0].key).value.bytes == poolBytes

try:
  literals()
  posteriorQueueState()
  published()
  echo "PASS authorization transition: six published STF cases, oldest removal, posterior queues and atomic updates"
except:
  # Trusted fixture/transport failures are distinct from supported transition rejection evidence.
  quit(2)
