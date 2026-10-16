## Project-only ownership, source-alternative and arithmetic checks; no private compiler/runtime interface is used.
import std/[assertions, syncio]
include ../../src/codec/state_consensus

# Use the exact tiny structural widths with independently configurable source bytes.
proc policy(): SafroleStateConfig =
  SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
    maxBytes: ByteLimit(2017)), epochSlots: EpochSlots(2), maxAccumulator: ElementLimit(2),
        maxBytes: ByteLimit(10000))
# Construct borrowed sources directly; no decoder supplies their expected field values.
proc source(kind: SealerKind, marker: byte): SafroleState =
  var word = default(array[32, byte])
  word[0] = marker
  let item = WinningTicket(id: WinningTicketId(word), attempt: TicketAttempt(255))
  result = SafroleState(pending: newSeq[StateValidator](6), root: default(StateRingRoot),
    schedule: default(SealerSchedule), accumulator: @[item])
  result.pending[0].bandersnatch = StateBsKey(word)
  var root = default(array[144, byte])
  root[0] = marker
  result.root = StateRingRoot(root)
  case kind
  of Tickets:
    # Ticket sources preserve source order and all E1 attempt values.
    result.schedule = ticketSchedule(@[item, item])
  of Keys:
    # Fallback sources preserve opaque repeated keys.
    result.schedule = keySchedule(@[StateBsKey(word), StateBsKey(word)])
# Return a complete parent after local typed sources, entry and mutable wire aliases retire.
proc escaped(kind: SealerKind, marker: byte): SafroleStateSnapshot =
  var original = source(kind, marker)
  let encoded = safroleStateEntry(original, policy())
  assert encoded.error == StateComponentError.None
  var wire = encoded.value.value
  let decoded = decodeSafroleState(wire, policy())
  assert decoded.error == StateComponentError.None
  result = decoded.value.snapshot
  original = default(SafroleState)
  # Private capture must survive destructive mutation of all original wire bytes.
  for i in 0..<wire.len: wire[i] = 0
# Retain only the child roster after the callee-local parent and every schedule/accumulator field are released.
proc escapedChild(): ValidatorStateSnapshot =
  let parent = escaped(SealerKind.Tickets, 61)
  let data = parent.data
  assert data != nil
  data.pending
# Every scope releases both parent modes, replaced handles, child aliases and all failed/extracted temporaries.
proc cycle() =
  var parent = escaped(SealerKind.Tickets, 17)
  let alias = parent
  parent = escaped(SealerKind.Tickets, 29)
  let keys = escaped(SealerKind.Keys, 43)
  assert array[32, byte](sealerTicketAt(alias, SafroleStateIndex(0)).value.id)[0] == 17
  assert array[32, byte](sealerTicketAt(parent, SafroleStateIndex(0)).value.id)[0] == 29
  assert array[32, byte](sealerKeyAt(keys, SafroleStateIndex(1)).value)[0] == 43
  assert sealerKeyAt(alias, SafroleStateIndex(0)).error == StateComponentError.WrongVariant
  assert sealerTicketAt(keys, SafroleStateIndex(0)).error == StateComponentError.WrongVariant
  var info = safroleInfo(alias).value
  info.root = default(StateRingRoot)
  info.kind = SealerKind.Keys
  assert array[144, byte](safroleInfo(alias).value.root)[0] == 17
  assert safroleInfo(alias).value.kind == SealerKind.Tickets
  var item = sealerTicketAt(alias, SafroleStateIndex(0)).value
  item.id = default(WinningTicketId)
  item.attempt = TicketAttempt(0)
  assert byte(sealerTicketAt(alias, SafroleStateIndex(0)).value.attempt) == 255
  assert array[32, byte](accumulatedTicketAt(alias, SafroleStateIndex(0)).value.id)[0] == 17
  parent = default(SafroleStateSnapshot)
  assert safroleInfo(parent).error == StateComponentError.InvalidOwner
  assert safroleInfo(alias).value.validators == 6
  let child = escapedChild()
  assert validatorCount(child).value == 6
  assert array[32, byte](validatorAt(child, StateValidatorIndex(0)).value.bandersnatch)[0] == 61
  assert pendingValidatorAt(alias, StateValidatorIndex(high(uint64))).error ==
      StateComponentError.InvalidIndex
  assert sealerTicketAt(alias, SafroleStateIndex(high(uint64))).error ==
      StateComponentError.InvalidIndex
  assert accumulatedTicketAt(alias, SafroleStateIndex(high(uint64))).error ==
      StateComponentError.InvalidIndex
  var original = source(SealerKind.Tickets, 71)
  var copy = original.schedule.tickets
  copy[0].attempt = TicketAttempt(0)
  assert byte(original.schedule.tickets[0].attempt) == 255
  original = source(SealerKind.Keys, 83)
  var keyCopy = original.schedule.keys
  keyCopy[0] = default(StateBsKey)
  assert array[32, byte](original.schedule.keys[0])[0] == 83
  let encoded = safroleStateEntry(original, policy())
  assert encoded.error == StateComponentError.None
  let wire = encoded.value.value
  assert decodeSafroleState(wire.toOpenArray(0, wire.len-2), policy()).error ==
      StateComponentError.Truncated
  original.accumulator = newSeq[WinningTicket](3)
  assert safroleStateEntry(original, policy()).error == StateComponentError.InvalidCount

# Probe arithmetic defenses directly without fabricating impossible untrusted sequences or allocating advertised extents.
var cursor = high(int)-1
assert grow(cursor, 1, 1, ByteLimit(high(uint64))) == StateComponentError.None
assert cursor == high(int)
assert grow(cursor, 1, 1, ByteLimit(high(uint64))) == StateComponentError.LengthOverflow
assert cursor == high(int)
assert grow(cursor, 0, 33, ByteLimit(high(uint64))) == StateComponentError.None
cursor = high(int)-32
assert grow(cursor, 1, 33, ByteLimit(high(uint64))) == StateComponentError.LengthOverflow
assert cursor == high(int)-32
cursor = 0
assert grow(cursor, high(uint64), 33, ByteLimit(high(uint64))) == StateComponentError.LengthOverflow
assert cursor == 0
# Warmup excludes allocator initialization from the isolated live-occupancy comparison.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Each scope retires every nested owner, borrowed source, copied sequence and failed parent temporary.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
echo "CONSENSUS_ARC_RELEASE cycles=1000 occupied_before=", beforeRelease, " occupied_after=", afterRelease
echo "Nimony chapter 4: escaped/replaced parents, retained children, source/field copies and scoped ARC release passed"
