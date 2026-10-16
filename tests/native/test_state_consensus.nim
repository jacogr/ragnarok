## Whole-parent ownership, variant and copied-child regression checks.
import ../../src/[state_consensus, state_safrole, bounded, assurances]

## Failed/default alternatives must retain checked Nim inactive-field protection.
proc guarded[T](parsed: StateComponentResult[T]) =
  var caught = false
  try:
    discard parsed.value # No fabricated owner, record or progress on failure/default.
  except FieldDefect:
    caught = true # Optimized builds retain runtime field guards.
  doAssert caught

## Confirm complete parent snapshots retain only independent private copies of every selected field.
proc main() =
  doAssert sizeof(int) == 8 and sizeof(WinningTicket) == 33
  let config = SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(2),
    validators: ElementLimit(6), maxBytes: ByteLimit(2017)), epochSlots: EpochSlots(2),
    maxAccumulator: ElementLimit(2), maxBytes: ByteLimit(10_000))
  let impossible = ValidatorStateConfig(cores: CoreCount(high(uint64)), validators: ElementLimit(
      high(uint64)),
    maxBytes: ByteLimit(high(uint64)))
  doAssert stateValidatorSize(ValidatorCount(high(uint64)), impossible).error ==
      StateComponentError.LengthOverflow
  var id: array[32, byte]
  id[0] = 17
  let ticket = WinningTicket(id: WinningTicketId(id), attempt: TicketAttempt(255))
  var source = SafroleState(pending: newSeq[StateValidator](6),
    schedule: SealerSchedule(kind: SealerKind.Tickets, tickets: @[ticket, ticket]), accumulator: @[ticket])
  let encoded = safroleStateEntry(source, config)
  doAssert encoded.error == StateComponentError.None
  doAssert array[31, byte](encoded.value.key)[0] == 4
  source.schedule.tickets[0].attempt = TicketAttempt(128)
  doAssert encoded.value.value[2017+145+32] == 255
  var wire = encoded.value.value
  let parsed = decodeSafroleState(wire, config)
  doAssert parsed.error == StateComponentError.None
  let retained = parsed.value.snapshot
  source = default(SafroleState)
  # Destroy the original wire after capturing the entire parent and its nested roster.
  for i in 0..<wire.len: wire[i] = 0
  doAssert safroleInfo(retained).value.validators == 6
  doAssert safroleInfo(retained).value.slots == 2
  doAssert pendingValidatorAt(retained, StateValidatorIndex(5)).error == StateComponentError.None
  let first = sealerTicketAt(retained, SafroleStateIndex(0))
  doAssert first.error == StateComponentError.None and byte(first.value.attempt) == 255
  var copied = first.value
  copied.id = WinningTicketId(default(array[32, byte]))
  doAssert array[32, byte](sealerTicketAt(retained, SafroleStateIndex(0)).value.id)[0] == 17
  doAssert array[32, byte](accumulatedTicketAt(retained, SafroleStateIndex(0)).value.id)[0] == 17
  let wrong = sealerKeyAt(retained, SafroleStateIndex(0))
  doAssert wrong.error == StateComponentError.WrongVariant
  guarded(wrong)
  let index = accumulatedTicketAt(retained, SafroleStateIndex(high(uint64)))
  doAssert index.error == StateComponentError.InvalidIndex
  guarded(index)
  doAssert pendingValidatorAt(retained, StateValidatorIndex(high(uint64))).error ==
      StateComponentError.InvalidIndex
  var replaced = retained
  replaced = default(SafroleStateSnapshot)
  doAssert safroleInfo(retained).value.slots == 2
  guarded(safroleInfo(replaced))
  guarded(sealerTicketAt(replaced, SafroleStateIndex(0)))
  guarded(default(StateComponentResult[SafroleStateRead]))
  source = SafroleState(pending: newSeq[StateValidator](6), schedule: SealerSchedule(
    kind: SealerKind.Keys,
    keys: @[StateBsKey(id), StateBsKey(id)]))
  let fallback = safroleStateEntry(source, config)
  doAssert fallback.error == StateComponentError.None
  let keys = decodeSafroleState(fallback.value.value, config)
  doAssert keys.error == StateComponentError.None
  doAssert array[32, byte](sealerKeyAt(keys.value.snapshot, SafroleStateIndex(0)).value)[0] == 17
  doAssert sealerTicketAt(keys.value.snapshot, SafroleStateIndex(0)).error ==
      StateComponentError.WrongVariant
  let short = decodeSafroleState(fallback.value.value.toOpenArray(0, fallback.value.value.len-2), config)
  doAssert short.error == StateComponentError.Truncated
  guarded(short)
  echo "PASS Safrole basic state: retained parent/children, copied fields, selected variants and failure guards"

main()
