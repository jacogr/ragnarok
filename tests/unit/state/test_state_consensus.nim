# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole-parent ownership, variant and copied-child regression checks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/codec/state/[consensus as state_consensus, safrole as state_safrole]
import ../../../src/codec/[bounded, assurances]

## Confirm complete parent snapshots retain only independent private copies of every selected field.
proc main() =
  assert sizeof(int) == 8 and sizeof(WinningTicket) == 33
  let config = SafroleStateConfig(validators: ValidatorStateConfig(cores: CoreCount(2),
    validators: ElementLimit(6), maxBytes: ByteLimit(2017)), epochSlots: EpochSlots(2),
    maxAccumulator: ElementLimit(2), maxBytes: ByteLimit(10_000))
  let impossible = ValidatorStateConfig(cores: CoreCount(high(uint64)), validators: ElementLimit(
      high(uint64)),
    maxBytes: ByteLimit(high(uint64)))
  assert stateValidatorSize(ValidatorCount(high(uint64)), impossible).error ==
      StateComponentError.LengthOverflow
  var id = default(array[32, byte])
  id[0] = 17
  let ticket = WinningTicket(id: WinningTicketId(id), attempt: TicketAttempt(255))
  var ticketSource = @[ticket, ticket]
  var source = SafroleState(pending: newSeq[StateValidator](6),
    schedule: ticketSchedule(ticketSource), accumulator: @[ticket])
  let encoded = safroleStateEntry(source, config)
  assert encoded.error == StateComponentError.None
  assert array[31, byte](encoded.value.key)[0] == 4
  ticketSource[0].attempt = TicketAttempt(128)
  assert encoded.value.value[2017+145+32] == 255
  var wire = encoded.value.value
  let parsed = decodeSafroleState(wire, config)
  assert parsed.error == StateComponentError.None
  let retained = parsed.value.snapshot
  source = default(SafroleState)
  # Destroy the original wire after capturing the entire parent and its nested roster.
  for i in 0..<wire.len: wire[i] = 0
  assert safroleInfo(retained).value.validators == 6
  assert safroleInfo(retained).value.slots == 2
  assert pendingValidatorAt(retained, StateValidatorIndex(5)).error == StateComponentError.None
  let first = sealerTicketAt(retained, SafroleStateIndex(0))
  assert first.error == StateComponentError.None and byte(first.value.attempt) == 255
  var copied = first.value
  copied.id = WinningTicketId(default(array[32, byte]))
  assert array[32, byte](sealerTicketAt(retained, SafroleStateIndex(0)).value.id)[0] == 17
  assert array[32, byte](accumulatedTicketAt(retained, SafroleStateIndex(0)).value.id)[0] == 17
  let wrong = sealerKeyAt(retained, SafroleStateIndex(0))
  assert wrong.error == StateComponentError.WrongVariant
  let index = accumulatedTicketAt(retained, SafroleStateIndex(high(uint64)))
  assert index.error == StateComponentError.InvalidIndex
  assert pendingValidatorAt(retained, StateValidatorIndex(high(uint64))).error ==
      StateComponentError.InvalidIndex
  var replaced = retained
  replaced = default(SafroleStateSnapshot)
  assert safroleInfo(retained).value.slots == 2
  source = SafroleState(pending: newSeq[StateValidator](6), schedule: keySchedule(@[StateBsKey(id),
      StateBsKey(id)]))
  let fallback = safroleStateEntry(source, config)
  assert fallback.error == StateComponentError.None
  let keys = decodeSafroleState(fallback.value.value, config)
  assert keys.error == StateComponentError.None
  assert array[32, byte](sealerKeyAt(keys.value.snapshot, SafroleStateIndex(0)).value)[0] == 17
  assert sealerTicketAt(keys.value.snapshot, SafroleStateIndex(0)).error ==
      StateComponentError.WrongVariant
  let short = decodeSafroleState(fallback.value.value.toOpenArray(0, fallback.value.value.len-2), config)
  assert short.error == StateComponentError.Truncated
  echo "PASS Safrole basic state: retained parent/children, copied fields, selected variants and failure guards"

main()
