# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact upstream roster/root projections, untouched C(4) fields and atomic primitive/store
## refusals.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../support/validator_rotation_fixture
import ../../../src/state/[validator_state, store]
import ../../../src/codec/[state_consensus, state_trie, state_layout]

## Refuse only test-library hashes; production ABI and protocol behavior remain unchanged.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Refuse a selected private candidate-root hash after earlier hashes have succeeded.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count attempted hashes to prove invalid/same-epoch paths perform none.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
## Refuse setup (bit 2) or ring commitment (bit 4), retaining real destruction.
proc failRing(flags: cint) {.importc: "bo_reset", cdecl.}
## Inspect live native setup owners without resetting their count.
proc liveSetups(): cint {.importc: "bo_live_setups", cdecl.}
## Count setup attempts independently of ring commitment.
proc setupCalls(): cint {.importc: "bo_setup_news", cdecl.}

## Parse complete unsigned fixture transport, independent of any production protocol representation.
proc number(text: string): uint64 =
  var parsed = 0'u64
  assert parseBiggestUInt(text, parsed) == text.len
  parsed

## Decode exact fixture octets with explicit width validation.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet = 0'u8
    assert parseHex(text[2*i..2*i+1], octet) == 2 # Never accept a partial fixture octet.
    result[i] = octet

## Give each chapter a finite budget; resizing may move three independent allowed populations.
proc config(cores: int, epoch: uint64): ValidatorTransitionConfig =
  ValidatorTransitionConfig(safrole: SafroleStateConfig(validators: rotationRosterConfig(cores),
    epochSlots: EpochSlots(epoch), maxAccumulator: ElementLimit(epoch), maxBytes: ByteLimit(
        400_000)),
    offenders: ElementLimit(1023))

## Independent aggregate store limits cover six fixture values and a three-write candidate.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(6), perValue: ByteLimit(400_000),
    totalValueBytes: ByteLimit(1_500_000), nodes: TrieNodeLimit(1600)),
    writes: ElementLimit(3), writeValueBytes: ByteLimit(1_500_000))

## Compare the complete root and every original value after a refused update or on a retained snapshot.
proc unchanged(snapshot, original: StateStoreSnapshot, entries: seq[StateEntry]) =
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](original.commitment.root)
  for entry in entries:
    assert snapshot.lookup(entry.key).value.bytes == entry.value # Includes C(7), C(11) and unrelated state.

## Source blobs provide posterior roots/rosters, while schedule and accumulator deliberately retain prior bytes.
proc published(text: string) =
  let lines = text.splitLines()
  let count = int(number(lines[0]))
  assert count > 0 and count < 100 and lines.len == count+18
  var pools = newSeq[seq[byte]](count)
  for i in 0..<count:
    pools[i] = unhex(lines[i+1]) # Whole-roster pooling never removes or sorts a protocol record.
  for i in 0..<16:
    let fields = lines[count+1+i].splitWhitespace()
    assert fields.len == 15
    let policy = config(int(number(fields[0])), number(fields[1]))
    var ids = default(array[7, int])
    for j in 0..<7:
      assert number(fields[6+j]) < uint64(count)
      ids[j] = int(number(fields[6+j]))
    let raw = if fields[5] == "-": newSeq[byte](0) else: unhex(fields[
        5]) # Empty posterior offender set is explicit.
    var offenders = newSeq[OffenderKey](raw.len div 32)
    assert raw.len mod 32 == 0
    for j in 0..<offenders.len:
      var key = default(array[32, byte])
      for k in 0..<32: key[k] = raw[j*32+k] # Exact canonical upstream Ed25519 identity.
      offenders[j] = OffenderKey(key)
    assert number(fields[2]) <= uint64(high(uint32)) and number(fields[3]) <= uint64(high(uint32))
    var entries = @[
      StateEntry(key: chapterKey(StateChapter(4)), value: unhex(fields[13])),
      StateEntry(key: chapterKey(StateChapter(7)), value: pools[ids[0]]),
      StateEntry(key: chapterKey(StateChapter(8)), value: pools[ids[2]]),
      StateEntry(key: chapterKey(StateChapter(9)), value: pools[ids[3]]),
      timeEntry(StateTime(uint32(number(fields[2])))),
      StateEntry(key: chapterKey(StateChapter(1)), value: @[98'u8, 76])]
    failHash(0)
    failRing(0)
    var state = newStateStore(entries, limits()).value
    let before = state.snapshot.value
    let target = StateTime(uint32(number(fields[3])))
    let outcome = rotateValidatorState(state, target, offenders, policy)
    assert liveSetups() == 0 # Setup scope ends on every successful/error return, not at process exit.
    if fields[4] == "0":
      assert outcome.error == ValidatorStateError.InvalidSlot # Repeated slots reject without a ring or writes.
      assert setupCalls() == 0
      unchanged(state.snapshot.value, before, entries)
    else:
      assert outcome.error == ValidatorStateError.None
      assert outcome.value.lookup(entries[0].key).value.bytes == unhex(fields[14])
      assert outcome.value.lookup(entries[2].key).value.bytes == pools[ids[5]]
      assert outcome.value.lookup(entries[3].key).value.bytes == pools[ids[6]]
      for index in [1, 4, 5]:
        assert outcome.value.lookup(entries[index].key).value.bytes == entries[
            index].value # No staging/time/unrelated writes.
      unchanged(before, before, entries)
    if i == 3:
      # One tiny official source supplies valid keys for deterministic refusal, budget and recovery checks.
      for flags in [2, 4]:
        state = newStateStore(entries, limits()).value
        let original = state.snapshot.value
        failRing(cint(flags))
        assert rotateValidatorState(state, target, offenders, policy).error ==
            ValidatorStateError.BackendFailure
        assert liveSetups() == 0
        unchanged(state.snapshot.value, original, entries)
      failRing(0)
      for successful in [0, 2]:
        failHash(0)
        state = newStateStore(entries, limits()).value
        let original = state.snapshot.value
        hashAfter(cint(successful))
        assert rotateValidatorState(state, target, offenders, policy).error ==
            ValidatorStateError.BackendFailure
        assert hashCalls() == cint(successful+1) and liveSetups() == 0
        unchanged(state.snapshot.value, original, entries)
      failHash(0)
      # Single-batch policy is essential: two writable chapters must never produce a partial rotation.
      var budget = limits()
      budget.writes = ElementLimit(2)
      state = newStateStore(entries, budget).value
      let limited = state.snapshot.value
      assert rotateValidatorState(state, target, offenders, policy).error ==
          ValidatorStateError.LimitExceeded
      unchanged(state.snapshot.value, limited, entries)
      # Every required chapter rejects missing, truncated and suffixed data, including a late previous roster.
      for index in 0..<5:
        for damage in 0..<3:
          var broken = newSeq[StateEntry](0)
          for j, entry in entries:
            if j != index or damage != 0:
              var copy = StateEntry(key: entry.key, value: entry.value)
              if j == index:
                if damage == 1:
                  copy.value.setLen(copy.value.len-1) # Exact entry truncation is never repaired.
                else:
                  copy.value.add 0 # Prefix-valid values with suffixes still reject.
              broken.add copy
          state = newStateStore(broken, limits()).value
          let original = state.snapshot.value
          failRing(2)
          let rejected = rotateValidatorState(state, target, offenders, policy)
          assert rejected.error == (if damage == 0: ValidatorStateError.MissingState elif index ==
              4 and damage ==
              2: ValidatorStateError.LimitExceeded else: ValidatorStateError.InvalidState)
          assert setupCalls() == 0
          unchanged(state.snapshot.value, original, broken)
      failRing(0)
      state = newStateStore(entries, limits()).value
      let initial = state.snapshot.value
      failRing(2)
      failHash(1)
      let same = rotateValidatorState(state, StateTime(uint32(number(fields[2]))+1), offenders, policy)
      assert same.error == ValidatorStateError.None and setupCalls() == 0 and hashCalls() == 0
      unchanged(same.value, initial, entries)
      failHash(0)
      failRing(0)
      let recovered = rotateValidatorState(state, target, offenders, policy)
      assert recovered.error == ValidatorStateError.None and liveSetups() == 0
      assert recovered.value.lookup(entries[0].key).value.bytes == unhex(fields[14])
      # Independent authored tickets exercise the other C(4) schedule branch and a nonempty accumulator.
      let captured = decodeSafroleState(entries[0].value, policy.safrole).value.snapshot
      let info = safroleInfo(captured).value
      var pending = newSeq[StateValidator](info.validators)
      for j in 0..<pending.len:
        pending[j] = pendingValidatorAt(captured, StateValidatorIndex(uint64(
            j))).value # Keep published old pending keys.
      var tickets = newSeq[WinningTicket](12)
      for j in 0..<tickets.len:
        var id = default(array[32, byte])
        id[0] = byte(j+1) # Deliberately observable slot order and attempt bytes, not a generated schedule algorithm.
        tickets[j] = WinningTicket(id: WinningTicketId(id), attempt: TicketAttempt(byte(j)))
      var variant = SafroleState(pending: pending, root: info.root, schedule: ticketSchedule(
          tickets),
        accumulator: @[tickets[11], tickets[0]])
      entries[0] = safroleStateEntry(variant, policy.safrole).value
      state = newStateStore(entries, limits()).value
      let priorTickets = state.snapshot.value
      let ticketUpdate = rotateValidatorState(state, target, offenders, policy)
      assert ticketUpdate.error == ValidatorStateError.None
      let expected = decodeSafroleState(unhex(fields[14]), policy.safrole).value.snapshot
      let expectedInfo = safroleInfo(expected).value
      variant.root = expectedInfo.root
      variant.pending = newSeq[StateValidator](expectedInfo.validators)
      for j in 0..<variant.pending.len:
        variant.pending[j] = pendingValidatorAt(expected, StateValidatorIndex(uint64(
            j))).value # Root and pending come directly from upstream.
      let expectedTicketBytes = safroleStateEntry(variant, policy.safrole).value.value
      assert ticketUpdate.value.lookup(entries[0].key).value.bytes == expectedTicketBytes
      unchanged(priorTickets, priorTickets, entries)
      # Exact combined C(4)+C(8)+C(9) bytes pass; one byte below refuses all three after root computation.
      let total = expectedTicketBytes.len+pools[ids[5]].len+pools[ids[6]].len
      for allowance in [total-1, total]:
        var bounded = limits()
        bounded.writeValueBytes = ByteLimit(uint64(allowance))
        state = newStateStore(entries, bounded).value
        let original = state.snapshot.value
        let attempted = rotateValidatorState(state, target, offenders, policy)
        if allowance == total:
          assert attempted.error == ValidatorStateError.None # Exact aggregate extent includes every serialized byte.
        else:
          assert attempted.error == ValidatorStateError.LimitExceeded # No partially published roster/root.
          unchanged(state.snapshot.value, original, entries)
      # Replacing caller-owned bytes and store handles cannot invalidate a retained historical result.
      entries[0].value = @[0'u8]
      state = default(StateStore)
      assert recovered.value.lookup(chapterKey(StateChapter(4))).value.bytes == unhex(fields[14])
  failHash(0)
  failRing(0)

try:
  published(readFile(getEnv("RAGNAROK_VALIDATOR_STF"))) # Missing transport is an explicit harness failure.
except:
  quit(2) # Never count missing official projections as passing tests.
echo "PASS validator state: sixteen published roster/root projections, preserved fields and atomic failures"
