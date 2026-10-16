## GP 0.8.0 state serialization T chapter 4, Safrole basic state and C.2 ticket records.
## This codec preserves state sequences; cryptographic validity and epoch transitions remain external.
import ./[natural, bounded, assurances, state_layout, state_trie, state_safrole]
from ./header import WinningTicket, WinningTicketId, EpochSlots
from ./tickets import TicketAttempt
export WinningTicket, WinningTicketId, EpochSlots, TicketAttempt

type
  ## Opaque serialized ring commitment, distinct from a trie root or validator BLS key of equal width.
  StateRingRoot* = distinct array[144, byte]
  ## Exact chapter-4 discriminator: zero for tickets, one for fallback Bandersnatch keys.
  SealerKind* {.pure.} = enum
    Tickets, Keys
  ## Borrowed schedule source; only the selected alternative has backing sequence storage.
  SealerSchedule* = object
    case kind*: SealerKind
    of SealerKind.Tickets:
      tickets*: seq[WinningTicket] # Slot order is preserved, never score-sorted here.
    of SealerKind.Keys:
      keys*: seq[StateBsKey]       # Fallback keys remain opaque and may repeat.
  ## Synchronous borrowed source; every source sequence must remain stable throughout encoding.
  SafroleState* = object
    pending*: seq[StateValidator]
    root*: StateRingRoot
    schedule*: SealerSchedule
    accumulator*: seq[WinningTicket]
  ## Explicit roster policy, chain epoch length, accumulator ceiling and complete chapter byte ceiling.
  SafroleStateConfig* = object
    validators*: ValidatorStateConfig
    epochSlots*: EpochSlots
    maxAccumulator*: ElementLimit
    maxBytes*: ByteLimit
  ## Owner-bound ordinal for schedule/accumulator extraction, distinct from a pending validator index.
  SafroleStateIndex* = distinct uint64
  ## Fixed copied metadata identifies the selected schedule without exporting mutable storage.
  SafroleStateInfo* = object
    root*: StateRingRoot
    kind*: SealerKind
    validators*, slots*, accumulated*: int
  ## Private acyclic ARC owner composes the immutable roster with privately copied schedule/accumulator arrays.
  SafroleStateData = ref object
    pending: ValidatorStateSnapshot
    root: StateRingRoot
    schedule: SealerSchedule
    accumulator: seq[WinningTicket]
  ## Value handles share private immutable data; default handles contain no valid state.
  SafroleStateSnapshot* = object
    data: SafroleStateData
  ## Only complete decoding publishes a snapshot plus its exact prefix extent.
  SafroleStateRead* = object
    snapshot*: SafroleStateSnapshot
    consumed*: int
  ## Private no-allocation layout proof contains offsets only during the stable synchronous call.
  Layout = object
    pending, schedule, accumulator, count, consumed: int
    kind: SealerKind

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
proc count(input: openArray[byte]): StateComponentResult[tuple[value: uint64, size: int]] =
  let parsed = natural.decode(input)
  if not parsed.ok:
    # Preserve primitive framing failures before interpreting population/resource constraints.
    if parsed.error == DecodeError.truncated:
      return StateComponentResult[tuple[value: uint64, size: int]](
          error: StateComponentError.Truncated) # Count not complete.
    else:
      return StateComponentResult[tuple[value: uint64, size: int]](
          error: StateComponentError.NonCanonical) # Reject overlong forms.
  StateComponentResult[tuple[value: uint64, size: int]](error: StateComponentError.None,
    value: (uint64(parsed.value), int(parsed.consumed)))

## Validate a whole borrowed chapter before creating any child or parent owner.
proc scan(input: openArray[byte], config: SafroleStateConfig): StateComponentResult[Layout] =
  let valid = validate(config)
  if valid != StateComponentError.None: return StateComponentResult[Layout](
      error: valid) # Configuration precedes traversal.
  let roster = stateValidatorPrefixSize(input, config.validators)
  if roster.error != StateComponentError.None: return StateComponentResult[Layout](
      error: roster.error) # No roster allocation yet.
  var layout = Layout(pending: roster.value)
  var cursor = roster.value
  var error = grow(cursor, 145, 1, config.maxBytes)
  if error != StateComponentError.None: return StateComponentResult[Layout](
      error: error) # Include ring root plus tag.
  if input.len < cursor: return StateComponentResult[Layout](
      error: StateComponentError.Truncated) # Require fixed fields before tag access.
  if input[cursor-1] > 1: return StateComponentResult[Layout](
      error: StateComponentError.InvalidTag) # No third schedule representation exists.
  layout.kind = SealerKind(input[cursor-1])
  layout.schedule = cursor
  let width = if layout.kind == SealerKind.Tickets: 33 else: 32 # C.2 ticket identifier plus E1 attempt, or raw key.
  error = grow(cursor, uint64(config.epochSlots), width, config.maxBytes)
  if error != StateComponentError.None: return StateComponentResult[Layout](
      error: error) # Prove schedule extent before indexing.
  if input.len < cursor: return StateComponentResult[Layout](
      error: StateComponentError.Truncated) # No partial schedule accepted.
  let accumulated = count(input.toOpenArray(cursor, input.len-1))
  if accumulated.error != StateComponentError.None: return StateComponentResult[Layout](
      error: accumulated.error) # Framing precedes count policy.
  if accumulated.value.value > uint64(config.epochSlots):
    return StateComponentResult[Layout](error: StateComponentError.InvalidCount) # Accumulator cannot exceed an epoch's slots.
  if accumulated.value.value > uint64(config.maxAccumulator):
    return StateComponentResult[Layout](error: StateComponentError.LimitExceeded) # Caller may impose a stricter accumulator ceiling.
  error = grow(cursor, uint64(accumulated.value.size), 1, config.maxBytes)
  if error != StateComponentError.None: return StateComponentResult[Layout](
      error: error) # Count prefix is part of the parent bytes.
  layout.accumulator = cursor
  layout.count = int(accumulated.value.value)
  error = grow(cursor, accumulated.value.value, 33, config.maxBytes)
  if error != StateComponentError.None: return StateComponentResult[Layout](
      error: error) # Typed count was bounded by checked epoch size.
  if input.len < cursor: return StateComponentResult[Layout](
      error: StateComponentError.Truncated) # Validate final record before allocation.
  layout.consumed = cursor
  StateComponentResult[Layout](error: StateComponentError.None, value: layout)

## Copy a fixed field after complete extent validation, retaining no input alias.
proc fixed[N: static int](input: openArray[byte], offset: int): array[N, byte] =
  # Callers prove the complete selected field before copying its octets.
  for i in 0..<N: result[i] = input[offset+i]

## Read one complete ticket into a fixed independent value after whole-parent preflight.
proc ticket(input: openArray[byte], offset: int): WinningTicket =
  WinningTicket(id: WinningTicketId(fixed[32](input, offset)), attempt: TicketAttempt(input[offset+32]))

## Decode chapter 4 into immutable private storage only after the entire source prefix is valid.
proc decodeSafroleState*(input: openArray[byte], config: SafroleStateConfig): StateComponentResult[
    SafroleStateRead] =
  let checked = scan(input, config)
  if checked.error != StateComponentError.None:
    return StateComponentResult[SafroleStateRead](
        error: checked.error) # Failure returns neither partial child owners nor progress.
  let layout = checked.value
  let pending = decodeStateValidators(input.toOpenArray(0, layout.pending-1), config.validators)
  doAssert pending.error == StateComponentError.None # Stable input and the first scan proved the exact roster prefix.
  let data = SafroleStateData(pending: pending.value.value, root: StateRingRoot(fixed[144](input,
      layout.pending)),
    accumulator: newSeq[WinningTicket](layout.count))
  case layout.kind
  of SealerKind.Tickets:
    # Keep schedule order exactly as supplied, including its E1 attempt values.
    data.schedule = SealerSchedule(kind: SealerKind.Tickets, tickets: newSeq[WinningTicket](int(
        uint64(config.epochSlots))))
    for i in 0..<data.schedule.tickets.len: data.schedule.tickets[i] = ticket(input,
        layout.schedule+i*33)
  of SealerKind.Keys:
    # Fallback keys are copied as opaque fixed bytes, with no cryptographic validation.
    data.schedule = SealerSchedule(kind: SealerKind.Keys, keys: newSeq[StateBsKey](int(uint64(
        config.epochSlots))))
    for i in 0..<data.schedule.keys.len: data.schedule.keys[i] = StateBsKey(fixed[32](input,
        layout.schedule+i*32))
  # Accumulator order is serialization input; score ordering and eligibility are state-transition responsibilities.
  for i in 0..<layout.count: data.accumulator[i] = ticket(input, layout.accumulator+i*33)
  StateComponentResult[SafroleStateRead](error: StateComponentError.None,
    value: SafroleStateRead(snapshot: SafroleStateSnapshot(data: data), consumed: layout.consumed))

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

## Encode a stable borrowed chapter source into an independent C(4) entry after complete source preflight.
proc safroleStateEntry*(source: SafroleState, config: SafroleStateConfig): StateComponentResult[StateEntry] =
  let valid = validate(config)
  if valid != StateComponentError.None: return StateComponentResult[StateEntry](
      error: valid) # No allocation for invalid epoch policy.
  let roster = stateValidatorSize(ValidatorCount(source.pending.len), config.validators)
  if roster.error != StateComponentError.None: return StateComponentResult[StateEntry](
      error: roster.error) # Reuse pending population policy.
  let slots = if source.schedule.kind == SealerKind.Tickets: source.schedule.tickets.len else: source.schedule.keys.len # Select active storage only.
  if uint64(slots) != uint64(config.epochSlots) or uint64(source.accumulator.len) > uint64(
      config.epochSlots):
    return StateComponentResult[StateEntry](error: StateComponentError.InvalidCount) # Schedule is fixed; accumulator is epoch-bounded.
  if uint64(source.accumulator.len) > uint64(config.maxAccumulator):
    return StateComponentResult[StateEntry](error: StateComponentError.LimitExceeded) # Apply stricter caller policy before allocating children.
  let prefix = natural.encode(JamNatural(source.accumulator.len))
  var size = roster.value
  var error = grow(size, 145, 1, config.maxBytes)
  if error != StateComponentError.None: return StateComponentResult[StateEntry](
      error: error) # Root and discriminator are always present.
  let width = if source.schedule.kind == SealerKind.Tickets: 33 else: 32 # Fixed slot count has no serialized count.
  error = grow(size, uint64(slots), width, config.maxBytes)
  if error != StateComponentError.None: return StateComponentResult[StateEntry](
      error: error) # Bound schedule bytes before multiplication.
  error = grow(size, uint64(prefix.len), 1, config.maxBytes)
  if error != StateComponentError.None: return StateComponentResult[StateEntry](
      error: error) # Account for canonical accumulator framing.
  error = grow(size, uint64(source.accumulator.len), 33, config.maxBytes)
  if error != StateComponentError.None: return StateComponentResult[StateEntry](
      error: error) # Final size is known before any allocation.
  let pending = validatorEntry(ValidatorChapter.Staging, source.pending, config.validators)
  doAssert pending.error == StateComponentError.None # Reused no-allocation sizing proved the stable roster source.
  var entry = StateEntry(key: chapterKey(StateChapter(4)), value: newSeq[byte](size))
  var cursor = 0
  put(pending.value.value, entry.value, cursor)
  put(array[144, byte](source.root), entry.value, cursor)
  entry.value[cursor] = byte(ord(source.schedule.kind))
  inc cursor
  case source.schedule.kind
  of SealerKind.Tickets:
    # Preserve exact slot sequence; no outside-in permutation occurs during serialization.
    for value in source.schedule.tickets: putTicket(value, entry.value, cursor)
  of SealerKind.Keys:
    # No variable inner count is emitted for fixed fallback slots.
    for value in source.schedule.keys: put(array[32, byte](value), entry.value, cursor)
  put(prefix.bytes.toOpenArray(0, prefix.len-1), entry.value, cursor)
  # The accumulator has its own canonical variable count but shares C.2 ticket layout.
  for value in source.accumulator: putTicket(value, entry.value, cursor)
  StateComponentResult[StateEntry](error: StateComponentError.None, value: entry)

## Inspect copied metadata without exporting either schedule branch or private backing arrays.
proc safroleInfo*(owner: SafroleStateSnapshot): StateComponentResult[SafroleStateInfo] =
  if owner.data.isNil: return StateComponentResult[SafroleStateInfo](
      error: StateComponentError.InvalidOwner) # Default handles are not state.
  let validators = validatorCount(owner.data.pending)
  doAssert validators.error == StateComponentError.None # Only a fully validated roster can be stored in this owner.
  let slots = if owner.data.schedule.kind == SealerKind.Tickets: owner.data.schedule.tickets.len else: owner.data.schedule.keys.len # Read selected branch only.
  StateComponentResult[SafroleStateInfo](error: StateComponentError.None, value: SafroleStateInfo(
    root: owner.data.root,
    kind: owner.data.schedule.kind, validators: validators.value, slots: slots,
    accumulated: owner.data.accumulator.len))

## Extract one fixed pending validator copy through its immutable parent and nested roster owner.
proc pendingValidatorAt*(owner: SafroleStateSnapshot,
    index: StateValidatorIndex): StateComponentResult[StateValidator] =
  if owner.data.isNil: return StateComponentResult[StateValidator](
      error: StateComponentError.InvalidOwner) # Never dereference default handles.
  validatorAt(owner.data.pending, index)

## Extract a fixed winning ticket only from a ticket schedule, after checking its nominal slot ordinal.
proc sealerTicketAt*(owner: SafroleStateSnapshot, index: SafroleStateIndex): StateComponentResult[
    WinningTicket] =
  if owner.data.isNil: return StateComponentResult[WinningTicket](
      error: StateComponentError.InvalidOwner) # No source owner.
  if owner.data.schedule.kind != SealerKind.Tickets: return StateComponentResult[WinningTicket](
      error: StateComponentError.WrongVariant) # Never access inactive fields.
  if uint64(index) >= uint64(owner.data.schedule.tickets.len): return StateComponentResult[
      WinningTicket](error: StateComponentError.InvalidIndex) # Check before narrowing.
  StateComponentResult[WinningTicket](error: StateComponentError.None,
      value: owner.data.schedule.tickets[int(uint64(index))])

## Extract a copied fallback key only from the key schedule, without interpreting point validity.
proc sealerKeyAt*(owner: SafroleStateSnapshot, index: SafroleStateIndex): StateComponentResult[StateBsKey] =
  if owner.data.isNil: return StateComponentResult[StateBsKey](
      error: StateComponentError.InvalidOwner) # No source owner.
  if owner.data.schedule.kind != SealerKind.Keys: return StateComponentResult[StateBsKey](
      error: StateComponentError.WrongVariant) # No fabricated key on ticket mode.
  if uint64(index) >= uint64(owner.data.schedule.keys.len): return StateComponentResult[StateBsKey](
      error: StateComponentError.InvalidIndex) # Check before indexing.
  StateComponentResult[StateBsKey](error: StateComponentError.None, value: owner.data.schedule.keys[
      int(uint64(index))])

## Extract one copied accumulator ticket without exposing or reordering the private sequence.
proc accumulatedTicketAt*(owner: SafroleStateSnapshot,
    index: SafroleStateIndex): StateComponentResult[WinningTicket] =
  if owner.data.isNil: return StateComponentResult[WinningTicket](
      error: StateComponentError.InvalidOwner) # No default progress or data.
  if uint64(index) >= uint64(owner.data.accumulator.len): return StateComponentResult[
      WinningTicket](error: StateComponentError.InvalidIndex) # Bound before narrowing.
  StateComponentResult[WinningTicket](error: StateComponentError.None,
      value: owner.data.accumulator[int(uint64(index))])
