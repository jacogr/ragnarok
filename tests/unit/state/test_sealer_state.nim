## Published schedule pipelines, bounded atomic C(4) publication and immutable parent/working owners.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[sealer_state, sealer_schedule, ticket_state, ticket_admission, entropy, store]
import ../../../src/codec/[state_safrole, state_consensus, state_layout, state_trie, tickets, bounded]
import ../../support/[validator_rotation_fixture, arc_evidence]

## Refuse test-library Blake hashes without changing production primitives.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Refuse a selected hash after a successful private candidate prefix.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count hashes to distinguish preflight/no-op paths from candidate commitment work.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}

## Parse complete unsigned fixture fields before slot/count narrowing.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Decode trusted fixture transport, with exact octet validation rather than a protocol fallback.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var value = 0'u8
    assert parseHex(text[2*i..2*i+1], value) == 2 # No partial transport octets.
    result[i] = value

## Bound the five-entry sample mapping, including independent batch and complete-map ceilings.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(5), perValue: ByteLimit(400_000),
    totalValueBytes: ByteLimit(1000000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(2), writeValueBytes: ByteLimit(400_000))

## Capture every sample mapping value, including opaque unrelated state, as independent copied bytes.
proc entries(snapshot: StateStoreSnapshot): seq[StateEntry] =
  result = newSeq[StateEntry](0)
  for chapter in [4, 6, 11, 8, 1]:
    let key = chapterKey(StateChapter(chapter))
    result.add StateEntry(key: key, value: snapshot.lookup(key).value.bytes) # Fixed complete sample-key set.

## Assert complete root/value stability after any refusal, including historical snapshot retention.
proc unchanged(snapshot, before: StateStoreSnapshot, source: seq[StateEntry]) =
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](before.commitment.root)
  for entry in source:
    assert snapshot.lookup(entry.key).value.bytes == entry.value # No C(6)/C(11)/unrelated writes are permitted.

## Scope temporary candidate and snapshot owners independently of the retained caller map.
proc noopCycle(state: var StateStore, parent: StateStoreSnapshot, target: StateTime,
    policy: SealerScheduleConfig) =
  assert selectSafroleScheduleState(state, parent, target, policy).error == SealerScheduleError.None

## Exercise publication refusal/recovery and all required parent/staged chapter contracts.
proc boundaries(parent: StateStoreSnapshot, source: seq[StateEntry], target: StateTime,
    policy: SealerScheduleConfig, expected: seq[byte]) =
  let previous = decodeStateTime(parent.lookup(chapterKey(StateChapter(
      11))).value.bytes).value.value
  # This fixture uses outside-in tickets, so all observed hashes belong to private store commitment.
  assert uint32(target) div uint32(uint64(policy.state.epochSlots)) > uint32(previous) div uint32(
      uint64(policy.state.epochSlots))
  for successful in [0, 2]:
    failHash(0)
    var state = newStateStore(source, limits()).value
    let before = state.snapshot.value
    hashAfter(cint(successful))
    assert selectSafroleScheduleState(state, parent, target, policy).error ==
        SealerScheduleError.BackendFailure
    assert hashes() == cint(successful+1)
    unchanged(state.snapshot.value, before, source)
  failHash(0)
  var total = expected.len
  for i in 1..<source.len: total += source[i].value.len # Complete-map budget includes every unchanged chapter.
  for kind in 0..<4:
    for exact in 0..<2:
      var budget = limits()
      let allowance = expected.len-(if exact == 0: 1 else: 0)
      case kind
      of 0: budget.writes = ElementLimit(uint64(exact)) # Changed schedules require one atomic write.
      of 1: budget.writeValueBytes = ByteLimit(uint64(allowance)) # Bound the single-entry batch separately.
      of 2: budget.trie.perValue = ByteLimit(uint64(
          allowance)) # Posterior ticket width grows this fixture's C(4).
      else: budget.trie.totalValueBytes = ByteLimit(uint64(total-(if exact ==
          0: 1 else: 0))) # Bound the full candidate map.
      var state = newStateStore(source, budget).value
      let before = state.snapshot.value
      let outcome = selectSafroleScheduleState(state, parent, target, policy)
      if exact == 0:
        assert outcome.error == SealerScheduleError.LimitExceeded # No partial candidate becomes current.
        unchanged(state.snapshot.value, before, source)
      else:
        assert outcome.error == SealerScheduleError.None
        assert outcome.value.lookup(source[0].key).value.bytes == expected
  # Parent and staged maps have distinct required inputs; no missing/default chapter is synthesized.
  for parentSide in 0..<2:
    let original = if parentSide == 1: entries(parent) else: source
    let count = if parentSide == 1: 2 else: 4
    for index in 0..<count:
      let position = if parentSide == 1 and index == 1: 2 else: index
      for damage in 0..<3:
        var broken = newSeq[StateEntry](0)
        for i, entry in original:
          if i != position or damage != 0:
            var copy = StateEntry(key: entry.key, value: entry.value)
            if i == position:
              if damage == 1:
                copy.value.setLen(copy.value.len-1) # Truncations cannot become a default chapter.
              else:
                copy.value.add 0 # Exact chapters reject otherwise valid prefixes with suffixes.
            broken.add copy
        var state = newStateStore((if parentSide == 1: source else: broken), limits()).value
        let damagedParent = newStateStore(broken, limits()).value.snapshot.value
        let before = state.snapshot.value
        let outcome = selectSafroleScheduleState(state, (if parentSide ==
            1: damagedParent else: parent), target, policy)
        assert outcome.error == (if damage == 0: SealerScheduleError.MissingState else: SealerScheduleError.InvalidState)
        assert array[32, byte](state.snapshot.value.commitment.root) == array[32, byte](
            before.commitment.root)
  failHash(0)
  var state = newStateStore(source, limits()).value
  let recovered = selectSafroleScheduleState(state, parent, target, policy)
  assert recovered.error == SealerScheduleError.None
  var copy = recovered.value.lookup(source[0].key).value.bytes
  copy[0] = 0 # Extracted bytes cannot mutate either retained snapshot.
  state = default(StateStore)
  assert recovered.value.lookup(source[0].key).value.bytes == expected
  var wrongTime = source
  wrongTime[2] = timeEntry(previous)
  state = newStateStore(wrongTime, limits()).value
  let before = state.snapshot.value
  failHash(1)
  assert selectSafroleScheduleState(state, parent, target, policy).error ==
      SealerScheduleError.InvalidState
  assert hashes() == 0
  unchanged(state.snapshot.value, before, wrongTime)
  failHash(0)

## Run entropy/time and authenticated admission before schedule publication for all accepted upstream cases.
## Rotation's pending/root and active projections are supplied from the vector, not claimed as executed here.
proc published(text: string) =
  let lines = text.splitLines()
  assert lines.len == 34
  var testedBoundaries = false
  var testedNoop = false
  var testedFallback = false
  for i in 0..<33:
    let f = lines[i].splitWhitespace()
    assert f.len == 17
    let policy = SealerScheduleConfig(state: SafroleStateConfig(validators: rotationRosterConfig(
        int(number(f[1]))),
      epochSlots: EpochSlots(number(f[2])), maxAccumulator: ElementLimit(number(f[2])),
          maxBytes: ByteLimit(400000)),
      tailStart: EpochSlots(number(f[3])))
    let previous = StateTime(uint32(number(f[4])))
    let target = StateTime(uint32(number(f[5])))
    let parentEntries = @[
      StateEntry(key: chapterKey(StateChapter(4)), value: unhex(f[7])),
      StateEntry(key: chapterKey(StateChapter(6)), value: unhex(f[12])), timeEntry(previous),
      StateEntry(key: chapterKey(StateChapter(8)), value: unhex(f[9])),
      StateEntry(key: chapterKey(StateChapter(1)), value: @[98'u8, 76])]
    failHash(0)
    let parent = newStateStore(parentEntries, limits()).value.snapshot.value
    var rotated = parentEntries
    rotated[0] = StateEntry(key: parentEntries[0].key, value: unhex(f[11]))
    var state = newStateStore(rotated, limits()).value
    let randomBytes = unhex(f[13])
    assert randomBytes.len == 32
    var randomness = default(array[32, byte])
    for j in 0..<32: randomness[j] = randomBytes[j] # Actual upstream entropy-VRF output.
    assert advanceEntropyTimeState(state, target, EntropyInput(randomness),
        policy.state.epochSlots).error == EntropyTransitionError.None
    assert state.snapshot.value.lookup(parentEntries[1].key).value.bytes == unhex(f[14])
    let raw = if f[15] == "-": newSeq[byte](0) else: unhex(f[15]) # Empty extrinsics are explicit.
    assert raw.len mod 785 == 0
    var proofs = newSeq[Ticket](raw.len div 785)
    for j in 0..<proofs.len:
      var proof = default(array[784, byte])
      for k in 0..<784: proof[k] = raw[j*785+1+k] # Preserve the complete authenticated proof.
      proofs[j] = Ticket(attempt: TicketAttempt(raw[j*785]), proof: TicketProof(proof))
    let admission = TicketAdmissionConfig(state: policy.state, tailStart: policy.tailStart,
      blockTickets: TicketLimit(number(f[16])))
    assert admitSafroleTicketsState(state, previous, target, proofs, admission).error ==
        TicketAdmissionError.None
    assert state.snapshot.value.lookup(parentEntries[0].key).value.bytes == unhex(f[8])
    let before = state.snapshot.value
    let source = entries(before)
    let expected = unhex(f[10])
    let outcome = selectSafroleScheduleState(state, parent, target, policy)
    assert outcome.error == SealerScheduleError.None
    assert outcome.value.lookup(source[0].key).value.bytes == expected
    for j in 1..<source.len:
      assert outcome.value.lookup(source[j].key).value.bytes == source[
          j].value # Schedule publication changes only C(4).
    unchanged(before, before, source)
    unchanged(parent, parent, parentEntries)
    # Required dynamic byte ceilings reject before copying, selection or store hashing.
    if i == 0:
      for kind in 0..<3:
        var small = policy
        if kind == 0:
          small.state.maxBytes = ByteLimit(uint64(parentEntries[0].value.len-1)) # Parent chapter ceiling.
        elif kind == 1:
          small.state.maxBytes = ByteLimit(uint64(source[0].value.len-1)) # Staged chapter ceiling.
        else:
          small.state.validators.maxBytes = ByteLimit(uint64(source[
              3].value.len-1)) # Posterior active roster ceiling.
        var bounded = newStateStore(source, limits()).value
        failHash(1)
        assert selectSafroleScheduleState(bounded, parent, target, small).error ==
            SealerScheduleError.LimitExceeded
        assert hashes() == 0
        unchanged(bounded.snapshot.value, before, source)
        failHash(0)
      var empty = default(StateStore)
      assert selectSafroleScheduleState(empty, parent, target, policy).error ==
          SealerScheduleError.Uninitialized
      var valid = newStateStore(source, limits()).value
      assert selectSafroleScheduleState(valid, default(StateStoreSnapshot), target, policy).error ==
          SealerScheduleError.Uninitialized
    let crossed = uint32(previous) div uint32(number(f[2])) != uint32(target) div uint32(number(f[2]))
    let selectedKind = safroleInfo(decodeSafroleState(expected,
        policy.state).value.snapshot).value.kind
    if not testedFallback and crossed and selectedKind == SealerKind.Keys and expected != source[0].value:
      for prefix in [0, int(number(f[2])) div 2, int(number(f[2]))+2]:
        failHash(0)
        var refused = newStateStore(source, limits()).value
        hashAfter(cint(prefix))
        assert selectSafroleScheduleState(refused, parent, target, policy).error ==
            SealerScheduleError.BackendFailure
        assert hashes() == cint(prefix+1) # First/late fallback and post-fallback root refusal expose no prefix.
        unchanged(refused.snapshot.value, before, source)
        unchanged(parent, parent, parentEntries)
      failHash(0)
      testedFallback = true
    if not testedBoundaries and expected.len > source[0].value.len and number(f[1]) == 2:
      boundaries(parent, source, target, policy, expected)
      testedBoundaries = true
    if not testedNoop and uint32(previous) div uint32(number(f[2])) == uint32(target) div uint32(
        number(f[2])):
      var budget = limits()
      budget.writes = ElementLimit(0)
      state = newStateStore(source, budget).value
      failHash(1)
      let same = selectSafroleScheduleState(state, parent, target, policy)
      assert same.error == SealerScheduleError.None and hashes() == 0
      unchanged(same.value, before, source)
      for cycle in 0..<25: noopCycle(state, parent, target, policy) # Warm the temporary owner paths.
      let occupiedBefore = getOccupiedMem()
      for cycle in 0..<1000: noopCycle(state, parent, target, policy) # Retire every temporary candidate.
      let occupiedAfter = getOccupiedMem()
      assert occupiedBefore == occupiedAfter
      recordArcRelease("sealer_state", 1000, occupiedBefore, occupiedAfter)
      failHash(0)
      testedNoop = true
  assert testedBoundaries and testedNoop and testedFallback
  var missing = default(StateStore)
  assert selectSafroleScheduleState(missing, default(StateStoreSnapshot), StateTime(1), default(
      SealerScheduleConfig)).error == SealerScheduleError.Uninitialized

try:
  published(readFile(getEnv("RAGNAROK_SEALER_SCHEDULE"))) # Missing fixture transport must fail the harness.
except:
  quit(2) # Never silently skip upstream pipeline projections.
echo "PASS sealer state: thirty-three staged pipelines, atomic rollback, budgets and immutable history"
