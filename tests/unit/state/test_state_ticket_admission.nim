# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published proof/selection projections plus authored transcript, ordering, policy and owner
## boundaries.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/envvars
import std/parseutils
import std/strutils
import std/syncio
import ../../../src/state/ticket_admission as state_ticket_admission
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_consensus as codec_state_consensus
import ../../../src/codec/tickets as codec_tickets
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../support/codec_validator_rotation_fixture

## Refuse setup (bit 2) or verification (bit 8) through the test-only native observer.
proc reset(flags: cint) {.importc: "bo_reset", cdecl.}
## Native setup allocations must be released before every success/refusal call returns.
proc liveSetups(): cint {.importc: "bo_live_setups", cdecl.}
## Observe proof work so early policy/order-state failures cannot conceal native verification.
proc verifies(): cint {.importc: "bo_verifies", cdecl.}
## Observe setup work independently from successful proof verification.
proc setups(): cint {.importc: "bo_setup_news", cdecl.}

## Parse complete unsigned trusted fixture fields before narrowing to native counts/slots.
proc number(text: string): uint64 =
  var parsed = 0'u64
  assert parseBiggestUInt(text, parsed) == text.len
  parsed

## Decode trusted hexadecimal transport without invoking production codec operations.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var octet = 0'u8
    assert parseHex(text[2*i..2*i+1], octet) == 2 # Complete octets only.
    result[i] = octet

## Inspect complete immutable C(4) bytes through copied public extraction APIs.
proc bytes(owner: SafroleStateSnapshot, policy: SafroleStateConfig): seq[byte] =
  let info = safroleInfo(owner).value
  var source = SafroleState(pending: newSeq[StateValidator](info.validators), root: info.root,
    schedule: ticketSchedule(@[]), accumulator: newSeq[WinningTicket](info.accumulated))
  for i in 0..<source.pending.len:
    source.pending[i] = pendingValidatorAt(owner, StateValidatorIndex(uint64(i))).value # Fixed copied records.
  for i in 0..<source.accumulator.len:
    source.accumulator[i] = accumulatedTicketAt(owner, SafroleStateIndex(uint64(
        i))).value # Retain exact order and attempts.
  case info.kind
  of SealerKind.Tickets:
    var values = newSeq[WinningTicket](info.slots) # Select only the active schedule variant.
    for i in 0..<values.len:
      values[i] = sealerTicketAt(owner, SafroleStateIndex(uint64(i))).value
    source.schedule = ticketSchedule(values)
  of SealerKind.Keys:
    var values = newSeq[StateBsKey](info.slots) # Preserve every fallback key without deduplication.
    for i in 0..<values.len:
      values[i] = sealerKeyAt(owner, SafroleStateIndex(uint64(i))).value
    source.schedule = keySchedule(values)
  safroleStateEntry(source, policy).value.value

## Replace only the accumulator in a separately encoded fixture chapter, keeping official keys/root and schedule.
proc withAccumulator(raw: seq[byte], values: seq[WinningTicket], policy: SafroleStateConfig): seq[byte] =
  let owner = decodeSafroleState(raw, policy).value.snapshot
  let info = safroleInfo(owner).value
  var pending = newSeq[StateValidator](info.validators)
  var keys = newSeq[StateBsKey](info.slots)
  for i in 0..<pending.len:
    pending[i] = pendingValidatorAt(owner, StateValidatorIndex(uint64(i))).value # Copy supplied source rows.
  for i in 0..<keys.len:
    keys[i] = sealerKeyAt(owner, SafroleStateIndex(uint64(
        i))).value # This authored family uses published fallback schedules.
  safroleStateEntry(SafroleState(pending: pending, root: info.root, schedule: keySchedule(keys),
    accumulator: values), policy).value.value

## Map named upstream rejection causes; no broad "any failure" verdict may hide a wrong path.
proc expected(text: string): TicketAdmissionError =
  case text
  of "ok": TicketAdmissionError.None # Accepted cases compare complete projected C(4) bytes.
  of "bad_ticket_attempt": TicketAdmissionError.InvalidAttempt # New population controls attempt eligibility.
  of "duplicate_ticket": TicketAdmissionError.Duplicate # Identifier already exists in prior accumulator.
  of "bad_ticket_order": TicketAdmissionError.BadOrder # Extrinsic must already be ordered.
  of "bad_ticket_proof": TicketAdmissionError.InvalidProof # Cryptographic rejection, not backend refusal.
  of "unexpected_ticket": TicketAdmissionError.UnexpectedTicket # Submission window has closed.
  else:
    assert false # New upstream rejection reasons require an explicit interpretation, never a fallback.
    TicketAdmissionError.Uninitialized

## A candidate returned from callee-local buffers survives their mutation and scope retirement.
proc escaped(raw: seq[byte], proofs: seq[Ticket], entropy: StateEntropyWord,
    policy: TicketAdmissionConfig): SafroleStateSnapshot =
  var local = newSeq[byte](raw.len)
  for i in 0..<raw.len: local[i] = raw[i] # Independent mutable source whose lifetime ends below.
  let outcome = admitSafroleTickets(local, StateTime(0), StateTime(1), entropy, proofs, policy)
  assert outcome.error == TicketAdmissionError.None
  let before = bytes(outcome.value, policy.state)
  local[0] = 0 # A source mutation cannot retag or invalidate the retained candidate's roster.
  assert bytes(outcome.value, policy.state) == before
  outcome.value

## Deliberately wrong transcripts/state/budgets must reject without retaining native setup allocations.
proc boundaries(raw: seq[byte], proofs: seq[Ticket], entropy: StateEntropyWord,
    policy: TicketAdmissionConfig, completed: SafroleStateSnapshot) =
  let before = raw
  for flags in [2, 8]:
    reset(cint(flags))
    assert admitSafroleTickets(raw, StateTime(0), StateTime(1), entropy, proofs,
      policy).error == TicketAdmissionError.BackendFailure
    assert liveSetups() == 0
  reset(0)
  var changedEntropy = array[32, byte](entropy)
  changedEntropy[0] = changedEntropy[0] xor 1
  assert admitSafroleTickets(raw, StateTime(0), StateTime(1), StateEntropyWord(changedEntropy),
    proofs, policy).error == TicketAdmissionError.InvalidProof # Domain binds the complete posterior entropy[2].
  var changedAttempt = proofs
  changedAttempt[0].attempt = TicketAttempt(uint8(changedAttempt[0].attempt) xor 1)
  assert admitSafroleTickets(raw, StateTime(0), StateTime(1), entropy, changedAttempt,
    policy).error == TicketAdmissionError.InvalidProof # A different still-eligible E1 attempt changes the transcript.
  var changedProof = proofs
  var encoded = array[784, byte](changedProof[0].proof)
  encoded[783] = encoded[783] xor 1
  changedProof[0].proof = TicketProof(encoded)
  assert admitSafroleTickets(raw, StateTime(0), StateTime(1), entropy, changedProof,
    policy).error == TicketAdmissionError.InvalidProof # Late proof-byte mutation cannot produce a score.
  assert admitSafroleTickets(raw, StateTime(0), StateTime(1), entropy, @[proofs[0], proofs[0]],
    policy).error == TicketAdmissionError.BadOrder # Equal identifiers in one extrinsic are not sorted/deduplicated.
  let first = accumulatedTicketAt(completed, SafroleStateIndex(0)).value
  let duplicate = WinningTicket(id: first.id, attempt: TicketAttempt(255))
  let occupied = withAccumulator(raw, @[duplicate], policy.state)
  assert admitSafroleTickets(occupied, StateTime(0), StateTime(1), entropy, proofs,
    policy).error == TicketAdmissionError.Duplicate # Different stored attempt cannot hide an existing identifier.
  var low = newSeq[WinningTicket](12)
  for i in 0..<low.len:
    var id = default(array[32, byte])
    id[31] = byte(i) # Literal scores below these official incoming tickets fill the contest.
    low[i] = WinningTicket(id: WinningTicketId(id), attempt: TicketAttempt(0))
  let full = withAccumulator(raw, low, policy.state)
  assert admitSafroleTickets(full, StateTime(0), StateTime(1), entropy, proofs,
    policy).error == TicketAdmissionError.NotRetained # No valid but useless incoming proof may be discarded silently.
  let crossed = admitSafroleTickets(full, StateTime(0), StateTime(36), entropy, [], policy)
  assert crossed.error == TicketAdmissionError.None and safroleInfo(
      crossed.value).value.accumulated == 0 # Skip resets once.
  assert admitSafroleTickets(occupied, StateTime(0), StateTime(12), entropy, proofs,
    policy).error == TicketAdmissionError.Duplicate # GP disjointness checks prior identifiers even across reset.
  reset(0)
  let badOld = withAccumulator(raw, @[duplicate, duplicate], policy.state)
  assert admitSafroleTickets(badOld, StateTime(0), StateTime(1), entropy, proofs,
    policy).error == TicketAdmissionError.InvalidState
  assert setups() == 0 and verifies() == 0 # Structural prior contest validation precedes crypto.
  var limited = policy
  limited.blockTickets = TicketLimit(uint64(proofs.len-1))
  assert admitSafroleTickets(raw, StateTime(0), StateTime(1), entropy, proofs,
    limited).error == TicketAdmissionError.LimitExceeded
  limited = policy
  limited.state.maxAccumulator = ElementLimit(2)
  assert admitSafroleTickets(raw, StateTime(0), StateTime(1), entropy, proofs,
    limited).error == TicketAdmissionError.LimitExceeded # Never accept a locally truncated two-ticket contest.
  limited = policy
  limited.state.maxBytes = ByteLimit(uint64(raw.len-1))
  assert admitSafroleTickets(raw, StateTime(0), StateTime(1), entropy, proofs,
    limited).error == TicketAdmissionError.LimitExceeded
  for epoch in [0'u64, high(uint64)]:
    limited = policy
    limited.state.epochSlots = EpochSlots(epoch)
    let outcome = admitSafroleTickets(raw, StateTime(0), StateTime(1), entropy, proofs, limited)
    assert outcome.error == (if epoch == 0: TicketAdmissionError.InvalidConfig else: TicketAdmissionError.LengthOverflow)
  for pair in [(1'u32, 1'u32), (high(uint32), 0'u32)]:
    assert admitSafroleTickets(raw, StateTime(pair[0]), StateTime(pair[1]), entropy, proofs,
      policy).error == TicketAdmissionError.InvalidSlot # No repeats or wrapping arithmetic.
  for damage in 0..<2:
    var broken = newSeq[byte](raw.len)
    for i in 0..<raw.len: broken[i] = raw[i] # Keep each malformed source independent.
    if damage == 0:
      broken.setLen(broken.len-1) # Truncate the final accumulator byte.
    else:
      broken.add 0 # Append an otherwise prefix-valid suffix.
    assert admitSafroleTickets(broken, StateTime(0), StateTime(1), entropy, proofs,
      policy).error == TicketAdmissionError.InvalidState # Exact framing rejects truncation and suffixes.
  reset(2)
  let empty = admitSafroleTickets(raw, StateTime(0), StateTime(10), entropy, [], policy)
  assert empty.error == TicketAdmissionError.None and bytes(empty.value, policy.state) == raw
  assert liveSetups() == 0 and setups() == 0 and verifies() ==
      0 # Empty admission needs no SRS/backend availability.
  reset(0)
  let retained = escaped(raw, proofs, entropy, policy)
  assert bytes(retained, policy.state) == bytes(completed, policy.state)
  assert raw == before # Borrowed source bytes remain unchanged through every accepted/refused call.

## Compare actual verification/selection against all twenty-eight source cases with exact projected state bytes.
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
    let source = unhex(fields[8])
    let submitted = if fields[9] == "-": newSeq[byte](0) else: unhex(fields[
        9]) # Empty extrinsic remains an explicit case.
    assert submitted.len mod 785 == 0
    var proofs = newSeq[Ticket](submitted.len div 785)
    for j in 0..<proofs.len:
      var proof = default(array[784, byte])
      for k in 0..<784: proof[k] = submitted[j*785+1+k] # Copy full fixed proof; never read its prefix as the identifier.
      proofs[j] = Ticket(attempt: TicketAttempt(submitted[j*785]), proof: TicketProof(proof))
    let entropyBytes = unhex(fields[7])
    assert entropyBytes.len == 32
    var entropy = default(array[32, byte])
    for j in 0..<32: entropy[j] = entropyBytes[j] # Bind every supplied entropy octet.
    assert number(fields[4]) <= uint64(high(uint32)) and number(fields[5]) <= uint64(high(uint32))
    reset(0)
    let outcome = admitSafroleTickets(source, StateTime(uint32(number(fields[4]))),
      StateTime(uint32(number(fields[5]))), StateEntropyWord(entropy), proofs, policy)
    assert outcome.error == expected(fields[6])
    assert liveSetups() == 0 # Every path releases real native setup owners before returning.
    if outcome.error == TicketAdmissionError.None:
      assert bytes(outcome.value, policy.state) == unhex(fields[10]) # All unchanged fields count too.
      if i == 1:
        boundaries(source, proofs, StateEntropyWord(entropy), policy,
            outcome.value) # Valid independent proofs drive authored negatives.
    else:
      assert fields[10] == "-" # No failed fixture carries a candidate-state expectation.
  reset(0)

try:
  published(readFile(getEnv("RAGNAROK_TICKET_ADMISSION"))) # Missing fixtures cannot silently skip published cases.
except:
  quit(2) # Preserve harness failure separately from an assertion/protocol verdict.
echo "PASS ticket admission: twenty-eight published projections, proof domains, canonical selection and bounds"
