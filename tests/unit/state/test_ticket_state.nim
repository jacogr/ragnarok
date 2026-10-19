# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published admission projections after actual entropy/time staging; atomic C(4) rollback and
## lifetimes.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

## Verification: {"arc": "ticket_state_arc_release"}

import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[ticket_state, ticket_admission, entropy, store]
import ../../../src/codec/[state_safrole, state_consensus, state_layout, state_trie, tickets, bounded]
import ../../support/[validator_rotation_fixture, arc_evidence]

## Refuse only test-library Blake hashes; maintained production primitives are unchanged.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Refuse a selected private candidate-root hash after a successful prefix.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count hashes to prove early refusal/no-op paths perform no store commitment work.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
## Refuse setup or proof verification through the existing test-only Rust observer.
proc failRing(flags: cint) {.importc: "bo_reset", cdecl.}
## Live native setup counts cannot be reset away by the observer.
proc liveSetups(): cint {.importc: "bo_live_setups", cdecl.}
## Inspect setup work independently of successful verification.
proc setups(): cint {.importc: "bo_setup_news", cdecl.}

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

## Bound the four-entry sample mapping, including independent batch and complete-map ceilings.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(400_000),
    totalValueBytes: ByteLimit(500_000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(2), writeValueBytes: ByteLimit(400_000))

## Capture every sample mapping value, including opaque unrelated state, as independent copied bytes.
proc entries(snapshot: StateStoreSnapshot): seq[StateEntry] =
  result = newSeq[StateEntry](0)
  for chapter in [4, 6, 11, 1]:
    let key = chapterKey(StateChapter(chapter))
    result.add StateEntry(key: key, value: snapshot.lookup(key).value.bytes) # Fixed complete sample-key set.

## Assert complete root/value stability after any refusal, including historical snapshot retention.
proc unchanged(snapshot, before: StateStoreSnapshot, source: seq[StateEntry]) =
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](before.commitment.root)
  for entry in source:
    assert snapshot.lookup(entry.key).value.bytes == entry.value # No C(6)/C(11)/unrelated writes are permitted.

## Create an independently observable ticket schedule while preserving the supplied pending/root/accumulator.
proc ticketScheduleEntry(raw: seq[byte], policy: SafroleStateConfig): StateEntry =
  let owner = decodeSafroleState(raw, policy).value.snapshot
  let info = safroleInfo(owner).value
  var source = SafroleState(pending: newSeq[StateValidator](info.validators), root: info.root,
    schedule: ticketSchedule(@[]), accumulator: newSeq[WinningTicket](info.accumulated))
  for i in 0..<source.pending.len:
    source.pending[i] = pendingValidatorAt(owner, StateValidatorIndex(uint64(
        i))).value # Keep actual published ring members.
  for i in 0..<source.accumulator.len:
    source.accumulator[i] = accumulatedTicketAt(owner, SafroleStateIndex(uint64(
        i))).value # Expected admission selection stays independent.
  var schedule = newSeq[WinningTicket](info.slots)
  for i in 0..<schedule.len:
    var id = default(array[32, byte])
    id[0] = byte(i mod 255) # Observable slot order with an independent schedule, not new winner generation.
    schedule[i] = WinningTicket(id: WinningTicketId(id), attempt: TicketAttempt(byte(i mod 4)))
  source.schedule = ticketSchedule(schedule)
  safroleStateEntry(source, policy).value

## Require exact upstream protocol causes through the store adapter, not merely any refusal.
proc protocolError(name: string): TicketAdmissionError =
  case name
  of "bad_ticket_attempt": TicketAdmissionError.InvalidAttempt # Eligibility refusal.
  of "duplicate_ticket": TicketAdmissionError.Duplicate # Prior identifier membership.
  of "bad_ticket_order": TicketAdmissionError.BadOrder # Strict extrinsic order.
  of "bad_ticket_proof": TicketAdmissionError.InvalidProof # Cryptographic input rejection.
  of "unexpected_ticket": TicketAdmissionError.UnexpectedTicket # Closed submission window.
  else:
    assert false # New fixture verdicts require explicit interpretation.
    TicketAdmissionError.Uninitialized

## Scope all temporary no-op candidate owners while retaining only the caller's original store.
proc noopCycle(state: var StateStore, previous, target: StateTime, policy: TicketAdmissionConfig) =
  let outcome = admitSafroleTicketsState(state, previous, target, [], policy)
  assert outcome.error == TicketAdmissionError.None # No setup/hash work is possible with refusal flags armed.

## Every failed private candidate must preserve the original full sample mapping and all retained owners.
proc failures(source: seq[StateEntry], previous, target: StateTime, proofs: seq[Ticket],
    policy: TicketAdmissionConfig, expected: seq[byte]) =
  for successful in [0, 2]:
    failHash(0)
    failRing(0)
    var state = newStateStore(source, limits()).value
    let before = state.snapshot.value
    hashAfter(cint(successful))
    assert admitSafroleTicketsState(state, previous, target, proofs, policy).error ==
        TicketAdmissionError.BackendFailure
    assert hashes() == cint(successful+1) and liveSetups() ==
        0 # Proofs completed before first/late store hash refusal.
    unchanged(state.snapshot.value, before, source)
  for flags in [2, 8]:
    failHash(0)
    var state = newStateStore(source, limits()).value
    let before = state.snapshot.value
    failRing(cint(flags))
    assert admitSafroleTicketsState(state, previous, target, proofs, policy).error ==
        TicketAdmissionError.BackendFailure
    assert liveSetups() == 0
    unchanged(state.snapshot.value, before, source)
  failRing(0)
  failHash(0)
  var total = expected.len
  for i in 1..<source.len: total += source[i].value.len # The complete map includes unchanged fixed/opaque values too.
  for kind in 0..<4:
    for exact in 0..<2:
      var budget = limits()
      let allowance = expected.len-(if exact == 0: 1 else: 0) # Exact byte extent passes; one byte below rejects.
      case kind
      of 0: budget.writes = ElementLimit(uint64(exact)) # Zero writes cannot publish a changed C(4).
      of 1: budget.writeValueBytes = ByteLimit(uint64(allowance)) # Aggregate one-entry batch bytes.
      of 2: budget.trie.perValue = ByteLimit(uint64(
          allowance)) # Posterior value must fit independently of batch policy.
      else: budget.trie.totalValueBytes = ByteLimit(uint64(total-(if exact ==
          0: 1 else: 0))) # Complete-map ceiling.
      var state = newStateStore(source, budget).value
      let before = state.snapshot.value
      let outcome = admitSafroleTicketsState(state, previous, target, proofs, policy)
      if exact == 0:
        assert outcome.error == TicketAdmissionError.LimitExceeded # No local budget fallback or partial new accumulator.
        unchanged(state.snapshot.value, before, source)
      else:
        assert outcome.error == TicketAdmissionError.None
        assert outcome.value.lookup(source[0].key).value.bytes == expected
      assert liveSetups() == 0
  # Missing, truncated and suffixed required chapters reject before publishing anything.
  for index in 0..<3:
    for damage in 0..<3:
      var broken = newSeq[StateEntry](0)
      for i, entry in source:
        if i != index or damage != 0:
          var copy = StateEntry(key: entry.key, value: entry.value)
          if i == index:
            if damage == 1:
              copy.value.setLen(copy.value.len-1) # Truncated C(4)/entropy/time is not repaired.
            else:
              copy.value.add 0 # Prefix-valid values with suffixes reject too.
          broken.add copy
      var state = newStateStore(broken, limits()).value
      let before = state.snapshot.value
      let outcome = admitSafroleTicketsState(state, previous, target, proofs, policy)
      assert outcome.error == (if damage == 0: TicketAdmissionError.MissingState else: TicketAdmissionError.InvalidState)
      unchanged(state.snapshot.value, before, broken)
  failHash(0)
  var state = newStateStore(source, limits()).value
  let original = state.snapshot.value
  # The same valid proof batch can recover after refusal; its snapshot survives caller/store replacement.
  let recovered = admitSafroleTicketsState(state, previous, target, proofs, policy)
  assert recovered.error == TicketAdmissionError.None
  var copied = recovered.value.lookup(source[0].key).value.bytes
  copied[0] = 0 # Explicit extraction copies must not retag retained state.
  state = default(StateStore)
  assert recovered.value.lookup(source[0].key).value.bytes == expected
  unchanged(original, original, source)
  # Both schedule alternatives are preserved during authentication, candidate capture and publication.
  var variant = source
  variant[0] = ticketScheduleEntry(source[0].value, policy.state)
  state = newStateStore(variant, limits()).value
  let withTickets = admitSafroleTicketsState(state, previous, target, proofs, policy)
  assert withTickets.error == TicketAdmissionError.None
  assert withTickets.value.lookup(source[0].key).value.bytes == ticketScheduleEntry(expected,
      policy.state).value
  # Out-of-order staging fails without a hash or native setup even when the primitive backend refuses work.
  variant = source
  variant[2] = timeEntry(previous)
  state = newStateStore(variant, limits()).value
  let unstaged = state.snapshot.value
  failHash(1)
  failRing(2)
  assert admitSafroleTicketsState(state, previous, target, proofs, policy).error ==
      TicketAdmissionError.InvalidState
  assert hashes() == 0 and setups() == 0
  unchanged(state.snapshot.value, unstaged, variant)
  failHash(0)
  failRing(0)
  state = newStateStore(source, limits()).value
  let boundedBefore = state.snapshot.value
  var small = policy
  small.state.maxBytes = ByteLimit(uint64(source[0].value.len-1))
  failHash(1)
  failRing(2)
  assert admitSafroleTicketsState(state, previous, target, proofs, small).error ==
      TicketAdmissionError.LimitExceeded
  assert hashes() == 0 and setups() == 0 # C(4) byte ceiling is checked before copying or native work.
  unchanged(state.snapshot.value, boundedBefore, source)
  failHash(0)
  failRing(0)

## Stage the real entropy/time implementation, then verify published proof/accumulator projections and unchanged chapters.
proc published(text: string) =
  let lines = text.splitLines()
  assert lines.len == 29
  for i in 0..<28:
    let fields = lines[i].splitWhitespace()
    assert fields.len == 14
    let policy = TicketAdmissionConfig(state: SafroleStateConfig(validators: rotationRosterConfig(
        int(number(fields[0]))),
      epochSlots: EpochSlots(number(fields[1])), maxAccumulator: ElementLimit(number(fields[1])),
          maxBytes: ByteLimit(400_000)),
      tailStart: EpochSlots(number(fields[2])), blockTickets: TicketLimit(number(fields[3])))
    assert number(fields[4]) <= uint64(high(uint32)) and number(fields[5]) <= uint64(high(uint32))
    let previous = StateTime(uint32(number(fields[4])))
    let target = StateTime(uint32(number(fields[5])))
    let raw = if fields[9] == "-": newSeq[byte](0) else: unhex(fields[9]) # Empty extrinsics remain explicit.
    assert raw.len mod 785 == 0
    var proofs = newSeq[Ticket](raw.len div 785)
    for j in 0..<proofs.len:
      var proof = default(array[784, byte])
      for k in 0..<784: proof[k] = raw[j*785+1+k] # Full supplied proofs, never unauthenticated score prefixes.
      proofs[j] = Ticket(attempt: TicketAttempt(raw[j*785]), proof: TicketProof(proof))
    let randomBytes = unhex(fields[12])
    assert randomBytes.len == 32
    var randomness = default(array[32, byte])
    for j in 0..<32: randomness[j] = randomBytes[j] # Actual upstream entropy-VRF output supplied to the prior stage.
    let parent = @[
      StateEntry(key: chapterKey(StateChapter(4)), value: unhex(fields[8])),
      StateEntry(key: chapterKey(StateChapter(6)), value: unhex(fields[11])), timeEntry(previous),
      StateEntry(key: chapterKey(StateChapter(1)), value: @[98'u8, 76])]
    failHash(0)
    failRing(0)
    var state = newStateStore(parent, limits()).value
    let staged = advanceEntropyTimeState(state, target, EntropyInput(randomness),
        policy.state.epochSlots)
    assert staged.error == EntropyTransitionError.None
    let before = state.snapshot.value
    let source = entries(before)
    if fields[6] == "ok":
      assert source[1].value == unhex(fields[13]) # Actual entropy handoff equals all four supplied posterior words.
    let outcome = admitSafroleTicketsState(state, previous, target, proofs, policy)
    assert liveSetups() == 0
    if fields[6] == "ok":
      assert outcome.error == TicketAdmissionError.None
      let expected = unhex(fields[10])
      assert outcome.value.lookup(source[0].key).value.bytes == expected
      for j in 1..<source.len:
        assert outcome.value.lookup(source[j].key).value.bytes == source[j].value # Only C(4) changes.
      unchanged(before, before, source)
      if i == 1:
        failures(source, previous, target, proofs, policy,
            expected) # Independent valid tiny proofs drive refusal/budget tests.
      if i == 7:
        # Same-epoch empty tail is a validated no-op, including with zero writes and refusing native/hash backends.
        var budget = limits()
        budget.writes = ElementLimit(0)
        state = newStateStore(source, budget).value
        let initial = state.snapshot.value
        failHash(1)
        failRing(2)
        let same = admitSafroleTicketsState(state, previous, target, [], policy)
        assert same.error == TicketAdmissionError.None and hashes() == 0 and setups() == 0
        unchanged(same.value, initial, source)
        for cycle in 0..<25: noopCycle(state, previous, target,
            policy) # Warm temporary codec/serialization paths.
        let occupiedBefore = getOccupiedMem()
        for cycle in 0..<1000: noopCycle(state, previous, target,
            policy) # Retire each call's temporary owned candidates.
        let occupiedAfter = getOccupiedMem()
        assert occupiedBefore == occupiedAfter
        recordArcRelease("ticket_state", 1000, occupiedBefore, occupiedAfter)
        failHash(0)
        failRing(0)
    else:
      assert outcome.error == protocolError(fields[
          6]) # Preserve the exact core refusal through the publication API.
      unchanged(state.snapshot.value, before, source)
  var missing = default(StateStore)
  assert admitSafroleTicketsState(missing, StateTime(0), StateTime(1), [], default(
      TicketAdmissionConfig)).error == TicketAdmissionError.Uninitialized
  failHash(0)
  failRing(0)

try:
  published(readFile(getEnv("RAGNAROK_TICKET_ADMISSION"))) # Missing source transport is an explicit harness failure.
except:
  quit(2) # Never silently omit published admission or entropy-stage projections.
echo "PASS ticket state: twenty-eight staged projections, atomic rollback, budgets and immutable history"
