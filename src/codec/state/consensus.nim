# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 state serialization T chapter 4, Safrole basic state and C.2 ticket records. This
## codec preserves state sequences; cryptographic validity and epoch transitions remain
## external.
##
## Exposes explicit ticket/key schedules, Safrole state codecs and copied
## pending-validator/sealer/accumulated-ticket access.

import std/assertions
import ../[natural, bounded, assurances]
import ./[layout as state_layout, trie as state_trie, safrole as state_safrole]
from ../header import WinningTicket, WinningTicketId, EpochSlots
from ../tickets import TicketAttempt
export WinningTicket, WinningTicketId, EpochSlots, TicketAttempt

type
  SafroleStateResult*[T] = object ## Chapter-local result keeps successful construction private while child-roster outcomes are converted explicitly.
    case status: StateComponentError
    of None:
      # Only successful chapter operations carry data or completed progress.
      completed: T
    else:
      # Defaults/failures expose only the shared typed reason.
      discard
  StateRingRoot* = distinct array[144, byte] ## Opaque serialized ring commitment, distinct from a trie root or validator BLS key of equal width.
  SealerKind* {.pure.} = enum ## Exact chapter-4 discriminator: zero for tickets, one for fallback Bandersnatch keys.
    Tickets, Keys
  SealerSchedule* = object ## Borrowed schedule source; only the selected alternative has backing sequence storage.
    case mode: SealerKind
    of Tickets:
      ticketValues: seq[WinningTicket] # Slot order is preserved, never score-sorted here.
    of Keys:
      keyValues: seq[StateBsKey]       # Fallback keys remain opaque and may repeat.
  SafroleState* = object ## Synchronous borrowed source; every source sequence must remain stable throughout encoding.
    pending*: seq[StateValidator]
    root*: StateRingRoot
    schedule*: SealerSchedule
    accumulator*: seq[WinningTicket]
  SafroleStateConfig* = object ## Explicit roster policy, chain epoch length, accumulator ceiling and complete chapter byte ceiling.
    validators*: ValidatorStateConfig
    epochSlots*: EpochSlots
    maxAccumulator*: ElementLimit
    maxBytes*: ByteLimit
  SafroleStateIndex* = distinct uint64 ## Owner-bound ordinal for schedule/accumulator extraction, distinct from a pending validator index.
  SafroleStateInfo* = object ## Fixed copied metadata identifies the selected schedule without exporting mutable storage.
    root*: StateRingRoot
    kind*: SealerKind
    validators*, slots*, accumulated*: int
  ## Private acyclic ARC owner composes the immutable roster with privately copied schedule/accumulator arrays.
  SafroleStateData = ref object
    pending: ValidatorStateSnapshot
    root: StateRingRoot
    schedule: SealerSchedule
    accumulator: seq[WinningTicket]
  SafroleStateSnapshot* = object ## Value handles share private immutable data; default handles contain no valid state.
    data: nil SafroleStateData
  SafroleStateRead* = object ## Only complete decoding publishes a snapshot plus its exact prefix extent.
    snapshot*: SafroleStateSnapshot
    consumed*: int
  ## Private no-allocation layout proof contains offsets only during the stable synchronous call.
  Layout = object
    pending, schedule, accumulator, count, consumed: int
    kind: SealerKind

func error*[T](value: SafroleStateResult[T]): StateComponentError =
  ## Read only the reason until the caller has selected successful completion.
  value.status
func value*[T](value: SafroleStateResult[T]): T {.inline, requires: value.status ==
    StateComponentError.None.} =
  ## No default/failed chapter result may expose an owner, entry, metadata, record or cursor.
  value.completed
func kind*(source: SealerSchedule): SealerKind =
  ## Tags are read-only; default source schedules retain the existing empty ticket alternative.
  source.mode
func ticketSchedule*(values: seq[WinningTicket]): SealerSchedule =
  ## Borrow caller ticket storage synchronously during encoding; tag and selected storage are constructed together.
  SealerSchedule(mode: Tickets, ticketValues: values)
func keySchedule*(values: seq[StateBsKey]): SealerSchedule =
  ## Borrow caller key storage synchronously during encoding without allowing caller retagging.
  SealerSchedule(mode: Keys, keyValues: values)
proc tickets*(source: SealerSchedule): seq[WinningTicket] {.requires: source.mode ==
    SealerKind.Tickets.} =
  ## Inspect an independent ticket sequence copy only from the active source alternative.
  result = newSeq[WinningTicket](source.ticketValues.len)
  # Copy fixed records so inspecting/editing returned values cannot modify the original source.
  for i in 0..<result.len: result[i] = source.ticketValues[i]
proc keys*(source: SealerSchedule): seq[StateBsKey] {.requires: source.mode == SealerKind.Keys.} =
  ## Inspect an independent key sequence copy only from the active source alternative.
  result = newSeq[StateBsKey](source.keyValues.len)
  # Each copied fixed key remains independent of caller/source backing sequences.
  for i in 0..<result.len: result[i] = source.keyValues[i]

## Extend a bounded parent extent without unchecked multiplication, addition or native narrowing.
proc grow(cursor: var int, count: uint64, width: int, limit: ByteLimit): StateComponentError =
  if count > uint64((high(int)-cursor) div width):
    return StateComponentError.LengthOverflow # Prove the complete fixed-stride extent before multiplication.
  cursor += int(count)*width
  if uint64(cursor) > uint64(limit):
    return StateComponentError.LimitExceeded # Every count, discriminator and fixed field consumes the parent ceiling.
  StateComponentError.None

## Positive epoch cardinality must fit both schedule wire and typed sequence indexing before any allocation.
proc validate(config: SafroleStateConfig): StateComponentError =
  if uint64(config.epochSlots) == 0:
    return StateComponentError.InvalidConfig # A fixed sealer schedule cannot have a zero-length epoch.
  if uint64(config.epochSlots) > uint64(high(int) div sizeof(WinningTicket)):
    return StateComponentError.LengthOverflow # Ticket storage bounds cover the narrower fallback-key storage too.
  StateComponentError.None

## Read one canonical accumulator count without allocating or publishing partial parser progress.
proc count(input: openArray[byte]): SafroleStateResult[tuple[value: uint64, size: int]] =
  let parsed = natural.decode(input)
  if not parsed.ok:
    # Preserve primitive framing failures before interpreting population/resource constraints.
    if parsed.error == DecodeError.truncated:
      return SafroleStateResult[tuple[value: uint64, size: int]](
          status: StateComponentError.Truncated) # Count not complete.
    else:
      return SafroleStateResult[tuple[value: uint64, size: int]](
          status: StateComponentError.NonCanonical) # Reject overlong forms.
  SafroleStateResult[tuple[value: uint64, size: int]](status: StateComponentError.None,
    completed: (uint64(parsed.value), int(parsed.consumed)))

## Validate a whole borrowed chapter before creating any child or parent owner.
proc scan(input: openArray[byte], config: SafroleStateConfig): SafroleStateResult[Layout] =
  let valid = validate(config)
  if valid != StateComponentError.None: return SafroleStateResult[Layout](
      status: valid) # Configuration precedes traversal.
  let roster = stateValidatorPrefixSize(input, config.validators)
  if roster.error != StateComponentError.None: return SafroleStateResult[Layout](
      status: roster.error) # No roster allocation yet.
  var layout = Layout(pending: roster.value)
  var cursor = roster.value
  var error = grow(cursor, 145, 1, config.maxBytes)
  if error != StateComponentError.None: return SafroleStateResult[Layout](
      status: error) # Include ring root plus tag.
  if input.len < cursor: return SafroleStateResult[Layout](
      status: StateComponentError.Truncated) # Require fixed fields before tag access.
  if input[cursor-1] > 1: return SafroleStateResult[Layout](
      status: StateComponentError.InvalidTag) # No third schedule representation exists.
  layout.kind = SealerKind(input[cursor-1])
  layout.schedule = cursor
  let width = if layout.kind == SealerKind.Tickets: 33 else: 32 # C.2 ticket identifier plus E1 attempt, or raw key.
  error = grow(cursor, uint64(config.epochSlots), width, config.maxBytes)
  if error != StateComponentError.None: return SafroleStateResult[Layout](
      status: error) # Prove schedule extent before indexing.
  if input.len < cursor: return SafroleStateResult[Layout](
      status: StateComponentError.Truncated) # No partial schedule accepted.
  let accumulated = count(input.toOpenArray(cursor, input.len-1))
  if accumulated.error != StateComponentError.None: return SafroleStateResult[Layout](
      status: accumulated.error) # Framing precedes count policy.
  if accumulated.value.value > uint64(config.epochSlots):
    return SafroleStateResult[Layout](status: StateComponentError.InvalidCount) # Accumulator cannot exceed an epoch's slots.
  if accumulated.value.value > uint64(config.maxAccumulator):
    return SafroleStateResult[Layout](status: StateComponentError.LimitExceeded) # Caller may impose a stricter accumulator ceiling.
  error = grow(cursor, uint64(accumulated.value.size), 1, config.maxBytes)
  if error != StateComponentError.None: return SafroleStateResult[Layout](
      status: error) # Count prefix is part of the parent bytes.
  layout.accumulator = cursor
  layout.count = int(accumulated.value.value)
  error = grow(cursor, accumulated.value.value, 33, config.maxBytes)
  if error != StateComponentError.None: return SafroleStateResult[Layout](
      status: error) # Typed count was bounded by checked epoch size.
  if input.len < cursor: return SafroleStateResult[Layout](
      status: StateComponentError.Truncated) # Validate final record before allocation.
  layout.consumed = cursor
  SafroleStateResult[Layout](status: StateComponentError.None, completed: layout)

## Copy a fixed field after complete extent validation, retaining no input alias.
proc fixed[N: static[int]](input: openArray[byte], offset: int): array[N, byte] =
  result = default(array[N, byte])
  # Callers prove the complete selected field before copying its octets.
  for i in 0..<N: result[i] = input[offset+i]

## Read one complete ticket into a fixed independent value after whole-parent preflight.
proc ticket(input: openArray[byte], offset: int): WinningTicket =
  WinningTicket(id: WinningTicketId(fixed[32](input, offset)), attempt: TicketAttempt(input[offset+32]))

proc decodeSafroleState*(input: openArray[byte], config: SafroleStateConfig): SafroleStateResult[
    SafroleStateRead] =
  ## Decode chapter 4 into immutable private storage only after the entire source prefix is valid.
  let checked = scan(input, config)
  if checked.error != StateComponentError.None:
    return SafroleStateResult[SafroleStateRead](
        status: checked.error) # Failure returns neither partial child owners nor progress.
  let layout = checked.value
  let pending = decodeStateValidators(input.toOpenArray(0, layout.pending-1), config.validators)
  assert pending.error == StateComponentError.None # Stable input and the first scan proved the exact roster prefix.
  let data = SafroleStateData(pending: pending.value.value, root: StateRingRoot(fixed[144](input,
      layout.pending)),
    accumulator: newSeq[WinningTicket](layout.count))
  case layout.kind
  of Tickets:
    # Keep schedule order exactly as supplied, including its E1 attempt values.
    data.schedule = SealerSchedule(mode: SealerKind.Tickets, ticketValues: newSeq[WinningTicket](
        int(uint64(config.epochSlots))))
    for i in 0..<data.schedule.ticketValues.len: data.schedule.ticketValues[i] = ticket(input,
        layout.schedule+i*33)
  of Keys:
    # Fallback keys are copied as opaque fixed bytes, with no cryptographic validation.
    data.schedule = SealerSchedule(mode: SealerKind.Keys, keyValues: newSeq[StateBsKey](int(uint64(
        config.epochSlots))))
    for i in 0..<data.schedule.keyValues.len: data.schedule.keyValues[i] = StateBsKey(fixed[32](
        input, layout.schedule+i*32))
  # Accumulator order is serialization input; score ordering and eligibility are state-transition responsibilities.
  for i in 0..<layout.count: data.accumulator[i] = ticket(input, layout.accumulator+i*33)
  SafroleStateResult[SafroleStateRead](status: StateComponentError.None,
    completed: SafroleStateRead(snapshot: SafroleStateSnapshot(data: data),
        consumed: layout.consumed))

## Copy bytes into a privately allocated and completely preflighted payload.
proc put(input: openArray[byte], output: var seq[byte], cursor: var int) =
  # Whole-parent sizing establishes every destination access.
  for b in input:
    output[cursor] = b
    inc cursor

## Commit C.2's fixed ticket encoding without using the proof-bearing extrinsic ticket schema.
proc putTicket(value: WinningTicket, output: var seq[byte], cursor: var int) =
  put(array[32, byte](value.id), output, cursor)
  output[cursor] = byte(value.attempt)
  inc cursor

proc safroleStateEntry*(source: SafroleState, config: SafroleStateConfig): SafroleStateResult[StateEntry] =
  ## Encode a stable borrowed chapter source into an independent C(4) entry after complete source preflight.
  let valid = validate(config)
  if valid != StateComponentError.None: return SafroleStateResult[StateEntry](
      status: valid) # No allocation for invalid epoch policy.
  let roster = stateValidatorSize(ValidatorCount(source.pending.len), config.validators)
  if roster.error != StateComponentError.None: return SafroleStateResult[StateEntry](
      status: roster.error) # Reuse pending population policy.
  let slots = if source.schedule.kind == SealerKind.Tickets: source.schedule.ticketValues.len else: source.schedule.keyValues.len # Select active storage only.
  if uint64(slots) != uint64(config.epochSlots) or uint64(source.accumulator.len) > uint64(
      config.epochSlots):
    return SafroleStateResult[StateEntry](status: StateComponentError.InvalidCount) # Schedule is fixed; accumulator is epoch-bounded.
  if uint64(source.accumulator.len) > uint64(config.maxAccumulator):
    return SafroleStateResult[StateEntry](status: StateComponentError.LimitExceeded) # Apply stricter caller policy before allocating children.
  let prefix = natural.encode(JamNatural(source.accumulator.len))
  var size = roster.value
  var error = grow(size, 145, 1, config.maxBytes)
  if error != StateComponentError.None: return SafroleStateResult[StateEntry](
      status: error) # Root and discriminator are always present.
  let width = if source.schedule.kind == SealerKind.Tickets: 33 else: 32 # Fixed slot count has no serialized count.
  error = grow(size, uint64(slots), width, config.maxBytes)
  if error != StateComponentError.None: return SafroleStateResult[StateEntry](
      status: error) # Bound schedule bytes before multiplication.
  error = grow(size, uint64(prefix.len), 1, config.maxBytes)
  if error != StateComponentError.None: return SafroleStateResult[StateEntry](
      status: error) # Account for canonical accumulator framing.
  error = grow(size, uint64(source.accumulator.len), 33, config.maxBytes)
  if error != StateComponentError.None: return SafroleStateResult[StateEntry](
      status: error) # Final size is known before any allocation.
  let pending = validatorEntry(ValidatorChapter.Staging, source.pending, config.validators)
  assert pending.error == StateComponentError.None # Reused no-allocation sizing proved the stable roster source.
  var entry = StateEntry(key: chapterKey(StateChapter(4)), value: newSeq[byte](size))
  var cursor = 0
  put(pending.value.value, entry.value, cursor)
  put(array[144, byte](source.root), entry.value, cursor)
  entry.value[cursor] = byte(ord(source.schedule.kind))
  inc cursor
  case source.schedule.kind
  of Tickets:
    # Preserve exact slot sequence; no outside-in permutation occurs during serialization.
    for value in source.schedule.ticketValues: putTicket(value, entry.value, cursor)
  of Keys:
    # No variable inner count is emitted for fixed fallback slots.
    for value in source.schedule.keyValues: put(array[32, byte](value), entry.value, cursor)
  put(prefix.bytes.toOpenArray(0, prefix.len-1), entry.value, cursor)
  # The accumulator has its own canonical variable count but shares C.2 ticket layout.
  for value in source.accumulator: putTicket(value, entry.value, cursor)
  SafroleStateResult[StateEntry](status: StateComponentError.None, completed: entry)

proc safroleInfo*(owner: SafroleStateSnapshot): SafroleStateResult[SafroleStateInfo] =
  ## Inspect copied metadata without exporting either schedule branch or private backing arrays.
  let data = owner.data
  if data == nil: return SafroleStateResult[SafroleStateInfo](
      status: StateComponentError.InvalidOwner) # Default handles are not state.
  let validators = validatorCount(data.pending)
  assert validators.error == StateComponentError.None # Only a fully validated roster can be stored in this owner.
  let slots = if data.schedule.kind == SealerKind.Tickets: data.schedule.ticketValues.len else: data.schedule.keyValues.len # Read selected branch only.
  SafroleStateResult[SafroleStateInfo](status: StateComponentError.None,
    completed: SafroleStateInfo(
    root: data.root,
    kind: data.schedule.kind, validators: validators.value, slots: slots,
    accumulated: data.accumulator.len))

proc pendingValidatorAt*(owner: SafroleStateSnapshot,
    index: StateValidatorIndex): SafroleStateResult[StateValidator] =
  ## Extract one fixed pending validator copy through its immutable parent and nested roster owner.
  let data = owner.data
  if data == nil: return SafroleStateResult[StateValidator](
      status: StateComponentError.InvalidOwner) # Never dereference default handles.
  let child = validatorAt(data.pending, index)
  # Convert only a selected child success; preserve its failure reason without opening private child storage.
  if child.error != StateComponentError.None:
    return SafroleStateResult[StateValidator](status: child.error)
  SafroleStateResult[StateValidator](status: StateComponentError.None, completed: child.value)

proc sealerTicketAt*(owner: SafroleStateSnapshot, index: SafroleStateIndex): SafroleStateResult[
    WinningTicket] =
  ## Extract a fixed winning ticket only from a ticket schedule, after checking its nominal slot ordinal.
  let data = owner.data
  if data == nil: return SafroleStateResult[WinningTicket](
      status: StateComponentError.InvalidOwner) # No source owner.
  if data.schedule.kind != SealerKind.Tickets: return SafroleStateResult[WinningTicket](
      status: StateComponentError.WrongVariant) # Never access inactive fields.
  if uint64(index) >= uint64(data.schedule.ticketValues.len): return SafroleStateResult[
      WinningTicket](status: StateComponentError.InvalidIndex) # Check before narrowing.
  SafroleStateResult[WinningTicket](status: StateComponentError.None,
      completed: data.schedule.ticketValues[int(uint64(index))])

proc sealerKeyAt*(owner: SafroleStateSnapshot, index: SafroleStateIndex): SafroleStateResult[StateBsKey] =
  ## Extract a copied fallback key only from the key schedule, without interpreting point validity.
  let data = owner.data
  if data == nil: return SafroleStateResult[StateBsKey](
      status: StateComponentError.InvalidOwner) # No source owner.
  if data.schedule.kind != SealerKind.Keys: return SafroleStateResult[StateBsKey](
      status: StateComponentError.WrongVariant) # No fabricated key on ticket mode.
  if uint64(index) >= uint64(data.schedule.keyValues.len): return SafroleStateResult[StateBsKey](
      status: StateComponentError.InvalidIndex) # Check before indexing.
  SafroleStateResult[StateBsKey](status: StateComponentError.None,
      completed: data.schedule.keyValues[int(uint64(index))])

proc accumulatedTicketAt*(owner: SafroleStateSnapshot,
    index: SafroleStateIndex): SafroleStateResult[WinningTicket] =
  ## Extract one copied accumulator ticket without exposing or reordering the private sequence.
  let data = owner.data
  if data == nil: return SafroleStateResult[WinningTicket](
      status: StateComponentError.InvalidOwner) # No default progress or data.
  if uint64(index) >= uint64(data.accumulator.len): return SafroleStateResult[
      WinningTicket](status: StateComponentError.InvalidIndex) # Bound before narrowing.
  SafroleStateResult[WinningTicket](status: StateComponentError.None,
      completed: data.accumulator[int(uint64(index))])
