# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published schedule projections and authored epoch, transcript, budget, ownership and backend
## boundaries.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

# @@Verification={"arc": "sealer_schedule_arc_release"}

import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/sealer_schedule
import ../../../src/codec/[state_safrole, state_consensus, bounded, assurances]
import ../../support/[validator_rotation_fixture, arc_evidence]

## Observer-linked primitives expose exact call counts and controlled first/late hash refusal only in tests.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Permit a known prefix of Blake2b calls before refusing the next call.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count primitive attempts so ticket/same-epoch/preflight paths prove they do no fallback work.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}

## Parse a whole trusted unsigned decimal fixture field before narrowing.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Decode exact trusted hexadecimal transport without calling a production parser.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var value = 0'u8
    assert parseHex(text[2*i..2*i+1], value) == 2 # Every supplied octet is complete.
    result[i] = value

## Append one explicit suffix byte without changing the original trusted fixture buffer.
proc suffixed(raw: seq[byte]): seq[byte] =
  result = newSeq[byte](raw.len+1)
  for i in 0..<raw.len: result[i] = raw[i] # Preserve every original byte before the extra trailing value.
  result[raw.len] = 0

## Finite chain policy bounds every parent/posterior chapter and active roster independently.
proc policy(epoch = 12, tail = 10): SealerScheduleConfig =
  SealerScheduleConfig(state: SafroleStateConfig(validators: rotationRosterConfig(),
    epochSlots: EpochSlots(uint64(epoch)), maxAccumulator: ElementLimit(uint64(epoch)),
    maxBytes: ByteLimit(1000000)), tailStart: EpochSlots(uint64(tail)))

## Copy an immutable result to canonical C(4), also enabling authored accumulator/schedule changes.
proc source(owner: SafroleStateSnapshot): SafroleState =
  let info = safroleInfo(owner).value
  result = SafroleState(pending: newSeq[StateValidator](info.validators), root: info.root,
    accumulator: newSeq[WinningTicket](info.accumulated), schedule: ticketSchedule(@[]))
  for i in 0..<result.pending.len:
    result.pending[i] = pendingValidatorAt(owner, StateValidatorIndex(uint64(
        i))).value # Preserve each full fixed record.
  for i in 0..<result.accumulator.len:
    result.accumulator[i] = accumulatedTicketAt(owner, SafroleStateIndex(uint64(
        i))).value # Preserve identifier and attempt.
  case info.kind
  of SealerKind.Tickets:
    var values = newSeq[WinningTicket](info.slots) # Read only the selected schedule alternative.
    for i in 0..<values.len: values[i] = sealerTicketAt(owner, SafroleStateIndex(uint64(i))).value
    result.schedule = ticketSchedule(values)
  of SealerKind.Keys:
    var values = newSeq[StateBsKey](info.slots) # Fixed copies cannot mutate the retained owner.
    for i in 0..<values.len: values[i] = sealerKeyAt(owner, SafroleStateIndex(uint64(i))).value
    result.schedule = keySchedule(values)

## Inspect complete result bytes rather than only comparing schedule lengths or selected indices.
proc bytes(owner: SafroleStateSnapshot, config: SealerScheduleConfig): seq[byte] =
  safroleStateEntry(source(owner), config.state).value.value

## Build simple independently distinguishable scores; attempts intentionally survive every permutation.
proc contest(count: int): seq[WinningTicket] =
  result = newSeq[WinningTicket](count)
  for i in 0..<count:
    var id = default(array[32, byte])
    id[0] = byte(i+1) # Distinct increasing first octets make expected order visible without a sort.
    result[i] = WinningTicket(id: WinningTicketId(id), attempt: TicketAttempt(byte(200+i)))

## Construct complete structural C(4) values from bounded fixed authored records.
proc chapter(values: seq[WinningTicket], epoch: int): seq[byte] =
  var keys = newSeq[StateBsKey](epoch)
  for i in 0..<keys.len:
    var value = default(array[32, byte])
    value[0] = byte(90+i) # A distinctive prior fallback sequence exposes incorrect same-epoch regeneration.
    keys[i] = StateBsKey(value)
  safroleStateEntry(SafroleState(pending: rotationRecords(6, 17), root: default(StateRingRoot),
    schedule: keySchedule(keys), accumulator: values), policy(epoch, epoch-2).state).value.value

## Callee-local input and extracted source mutations must not affect an escaped immutable candidate.
proc escaped(parent, staged, active: seq[byte], config: SealerScheduleConfig): SafroleStateSnapshot =
  var localParent = newSeq[byte](parent.len)
  var localStaged = newSeq[byte](staged.len)
  var localActive = newSeq[byte](active.len)
  for i in 0..<parent.len: localParent[i] = parent[
      i] # Independent mutable buffers cannot corrupt retained authored fixtures.
  for i in 0..<staged.len: localStaged[i] = staged[i]
  for i in 0..<active.len: localActive[i] = active[i]
  let selected = selectSafroleSchedule(localParent, localStaged, localActive, StateTime(10),
    StateTime(12), default(StateEntropyWord), config)
  assert selected.error == SealerScheduleError.None
  let expected = bytes(selected.value, config)
  localParent[0] = 0
  localStaged[0] = 0
  localActive[0] = 0
  var copied = source(selected.value)
  copied.accumulator.setLen(0) # Mutable extracted source is independent of the stored owner.
  assert bytes(selected.value, config) == expected
  selected.value

## Retire both successful and refused generated candidates inside a separate ARC scope.
proc cycle(parent, staged, active: seq[byte], config: SealerScheduleConfig) =
  failHash(0)
  let selected = selectSafroleSchedule(parent, staged, active, StateTime(1), StateTime(12),
    default(StateEntropyWord), config)
  assert selected.error == SealerScheduleError.None
  failAfter(3)
  assert selectSafroleSchedule(parent, staged, active, StateTime(1), StateTime(12),
    default(StateEntropyWord), config).error == SealerScheduleError.BackendFailure

## Check branch boundaries, exact policies, transcript byte order and owner retirement independently of projections.
proc boundaries() =
  let config = policy()
  let parent = chapter(contest(12), 12)
  let staged = chapter(contest(2), 12) # A new admitted contest differs from the parent winners on purpose.
  var activeRecords = rotationRecords(6, 31)
  for i in 0..<activeRecords.len:
    var key = default(array[32, byte])
    key[0] = byte(i+31) # Different active keys expose wrong-roster, modulo and endian choices.
    activeRecords[i].bandersnatch = StateBsKey(key)
  activeRecords[5] = default(StateValidator) # Null records remain in the modulo population; no extra filtering.
  let active = rotationBytes(rotationOwner(activeRecords))
  failHash(1)
  let selected = selectSafroleSchedule(parent, staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), config)
  assert selected.error == SealerScheduleError.None and hashes() == 0 # Ticket mode never hashes fallback data.
  let info = safroleInfo(selected.value).value
  assert info.kind == SealerKind.Tickets and info.accumulated == 2
  let expected = [1, 12, 2, 11, 3, 10, 4, 9, 5, 8, 6, 7]
  for i, ordinal in expected:
    let ticket = sealerTicketAt(selected.value, SafroleStateIndex(uint64(i))).value
    assert array[32, byte](ticket.id)[0] == byte(ordinal)
    assert uint8(ticket.attempt) == byte(199+ordinal) # Permutation retains the attempt associated with each identifier.
  let same = selectSafroleSchedule(parent, staged, active, StateTime(10), StateTime(11),
    default(StateEntropyWord), config)
  assert same.error == SealerScheduleError.None and hashes() == 0
  assert safroleInfo(same.value).value.kind == SealerKind.Keys # Saturation alone cannot replace a same-epoch schedule.
  let ticketBytes = bytes(selected.value, config)
  let sameTickets = selectSafroleSchedule(ticketBytes, staged, active, StateTime(12), StateTime(13),
    default(StateEntropyWord), config)
  assert sameTickets.error == SealerScheduleError.None and hashes() == 0
  assert uint8(sealerTicketAt(sameTickets.value, SafroleStateIndex(1)).value.attempt) == 211
  for slots in [(9'u32, 12'u32), (10'u32, 24'u32)]:
    assert selectSafroleSchedule(parent, staged, active, StateTime(slots[0]), StateTime(slots[1]),
      default(StateEntropyWord), config).error == SealerScheduleError.BackendFailure # Early crossing and skipped epochs require fallback.
  let unsaturated = chapter(contest(11), 12)
  assert selectSafroleSchedule(unsaturated, staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), config).error == SealerScheduleError.BackendFailure # Tail alone cannot supply missing tickets.
  failAfter(11)
  assert selectSafroleSchedule(parent, staged, active, StateTime(9), StateTime(12),
    default(StateEntropyWord), config).error == SealerScheduleError.BackendFailure
  assert hashes() == 12 # A refusal after eleven completed hashes publishes no prefix.
  failHash(0)
  let fallback = selectSafroleSchedule(parent, staged, active, StateTime(9), StateTime(12),
    default(StateEntropyWord), config)
  assert fallback.error == SealerScheduleError.None and hashes() == 12
  let roster = decodeStateValidators(active, config.state.validators).value.value
  # Frozen hashlib.blake2b(digest_size=32) E4-index answers independently cover the first/last slots.
  assert array[32, byte](sealerKeyAt(fallback.value, SafroleStateIndex(0)).value) ==
    array[32, byte](validatorAt(roster, StateValidatorIndex(5)).value.bandersnatch)
  assert array[32, byte](sealerKeyAt(fallback.value, SafroleStateIndex(11)).value) ==
    array[32, byte](validatorAt(roster, StateValidatorIndex(1)).value.bandersnatch)
  var changedSeed = default(array[32, byte])
  changedSeed[0] = 1
  let changedFallback = selectSafroleSchedule(parent, staged, active, StateTime(9), StateTime(12),
    StateEntropyWord(changedSeed), config)
  assert changedFallback.error == SealerScheduleError.None
  assert array[32, byte](sealerKeyAt(changedFallback.value, SafroleStateIndex(0)).value) ==
    array[32, byte](validatorAt(roster, StateValidatorIndex(
        1)).value.bandersnatch) # Frozen nonzero-entropy answer rejects an ignored seed.
  failHash(1)
  var zero = config
  zero.state.epochSlots = EpochSlots(0)
  assert selectSafroleSchedule([], [], [], StateTime(0), StateTime(1), default(StateEntropyWord),
    zero).error == SealerScheduleError.InvalidConfig
  zero = config
  zero.tailStart = EpochSlots(12)
  assert selectSafroleSchedule([], [], [], StateTime(0), StateTime(1), default(StateEntropyWord),
    zero).error == SealerScheduleError.InvalidConfig
  zero = config
  zero.state.epochSlots = EpochSlots(high(uint64))
  assert selectSafroleSchedule([], [], [], StateTime(0), StateTime(1), default(StateEntropyWord),
    zero).error == SealerScheduleError.LengthOverflow
  zero.state.epochSlots = EpochSlots(uint64(high(uint32))+2)
  assert selectSafroleSchedule([], [], [], StateTime(0), StateTime(1), default(StateEntropyWord),
    zero).error == SealerScheduleError.LengthOverflow # An E4 index cannot name every slot.
  for slots in [(10'u32, 10'u32), (11'u32, 10'u32), (high(uint32), 0'u32)]:
    assert selectSafroleSchedule(parent, staged, active, StateTime(slots[0]), StateTime(slots[1]),
      default(StateEntropyWord), config).error == SealerScheduleError.InvalidSlot # Repeat, reverse and wrap are distinct invalid inputs.
  for raw in [parent[0..parent.len-2], suffixed(parent)]:
    assert selectSafroleSchedule(raw, staged, active, StateTime(10), StateTime(12),
      default(StateEntropyWord), config).error == SealerScheduleError.InvalidState # Exact parent extent is mandatory.
    assert selectSafroleSchedule(parent, raw, active, StateTime(10), StateTime(12),
      default(StateEntropyWord), config).error == SealerScheduleError.InvalidState # Staged extent is also exact.
  assert selectSafroleSchedule(parent, staged, suffixed(active), StateTime(10), StateTime(12),
    default(StateEntropyWord), config).error == SealerScheduleError.InvalidState
  assert selectSafroleSchedule(parent, staged, active[0..active.len-2], StateTime(10), StateTime(12),
    default(StateEntropyWord), config).error == SealerScheduleError.InvalidState
  assert selectSafroleSchedule(parent, staged, [], StateTime(10), StateTime(12),
    default(StateEntropyWord), config).error == SealerScheduleError.InvalidState
  zero = config
  zero.state.validators.cores = CoreCount(1)
  assert selectSafroleSchedule(parent, staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), zero).error == SealerScheduleError.InvalidConfig
  zero = config
  zero.state.validators.validators = ElementLimit(5)
  assert selectSafroleSchedule(parent, staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), zero).error == SealerScheduleError.LimitExceeded
  zero = config
  zero.state.validators.maxBytes = ByteLimit(uint64(active.len-1))
  assert selectSafroleSchedule(parent, staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), zero).error == SealerScheduleError.LimitExceeded
  assert selectSafroleSchedule(parent, staged, active, StateTime(high(uint32)-1), StateTime(high(uint32)),
    default(StateEntropyWord), config).error == SealerScheduleError.None # Last representable slots do not wrap epoch arithmetic.
  var invalid = contest(12)
  let duplicateSource = contest(12)
  invalid[1] = WinningTicket(id: duplicateSource[0].id, attempt: TicketAttempt(
      255)) # Distinct attempt cannot make an equal identifier canonical.
  assert selectSafroleSchedule(chapter(invalid, 12), staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), config).error == SealerScheduleError.InvalidState # Duplicate score is not fixed by a different attempt.
  let ordered = contest(2)
  invalid = @[ordered[1], ordered[0]] # Copy into a separate sequence rather than mutate under a live borrow.
  assert selectSafroleSchedule(parent, chapter(invalid, 12), active, StateTime(10), StateTime(12),
    default(StateEntropyWord), config).error == SealerScheduleError.InvalidState # Staged contests also remain canonical.
  var bounded = config
  bounded.state.maxBytes = ByteLimit(uint64(parent.len))
  assert selectSafroleSchedule(parent, staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), bounded).error == SealerScheduleError.None
  assert selectSafroleSchedule(parent, parent, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), bounded).error == SealerScheduleError.LimitExceeded # Complete output is twelve bytes wider than both key-mode inputs.
  bounded.state.maxBytes = ByteLimit(uint64(parent.len-1))
  assert selectSafroleSchedule(parent, staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), bounded).error == SealerScheduleError.LimitExceeded
  bounded = config
  bounded.state.maxAccumulator = ElementLimit(11)
  assert selectSafroleSchedule(parent, staged, active, StateTime(10), StateTime(12),
    default(StateEntropyWord), bounded).error == SealerScheduleError.LimitExceeded
  assert hashes() == 0 # Invalid configuration/extents and all ticket/same-epoch paths precede fallback work.
  let escapedOwner = escaped(parent, staged, active, config)
  assert bytes(escapedOwner, config) == ticketBytes # Survives source mutation and source-scope retirement.
  let odd = policy(3, 2)
  let oddParent = chapter(contest(3), 3)
  let oddResult = selectSafroleSchedule(oddParent, oddParent, active, StateTime(2), StateTime(3),
    default(StateEntropyWord), odd)
  assert oddResult.error == SealerScheduleError.None
  for i, ordinal in [1, 3, 2]:
    assert array[32, byte](sealerTicketAt(oddResult.value, SafroleStateIndex(uint64(i))).value.id)[
        0] == byte(ordinal)
  for warmup in 0..<25: cycle(parent, staged, active,
      config) # Warm temporary codec/hash paths before observing live occupancy.
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(parent, staged, active,
      config) # Each success and late refusal retires all local owners.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("sealer_schedule", 1000, before, after)
  failHash(0)

## Match complete published posterior C(4); no marker, proof or other-stage verdict is claimed here.
proc published(text: string) =
  let rows = text.strip.splitLines
  assert rows.len == 33
  for line in rows:
    let fields = line.splitWhitespace
    assert fields.len == 17
    var config = policy(int(number(fields[2])), int(number(fields[3])))
    config.state.validators = rotationRosterConfig(int(number(fields[1])))
    let seed = unhex(fields[6])
    assert seed.len == 32
    var entropy = default(array[32, byte])
    for i in 0..<32: entropy[i] = seed[i] # Preserve the supplied posterior entropy word exactly.
    failHash(0)
    let selected = selectSafroleSchedule(unhex(fields[7]), unhex(fields[8]), unhex(fields[9]),
      StateTime(uint32(number(fields[4]))), StateTime(uint32(number(fields[5]))),
      StateEntropyWord(entropy), config)
    assert selected.error == SealerScheduleError.None, fields[0]
    assert bytes(selected.value, config) == unhex(fields[10]), fields[
        0] # Every schedule entry and all unrelated C(4) bytes match.

boundaries()
try:
  published(readFile(getEnv("RAGNAROK_SEALER_SCHEDULE"))) # Missing fixtures cannot turn external-vector coverage into a skip.
except:
  quit(2) # Preserve trusted fixture I/O failures separately from assertion/protocol verdicts.
echo "PASS sealer schedule: thirty-three published projections, outside-in, fallback, bounds and ownership"
