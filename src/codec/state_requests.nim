## GP 0.8.0 T service request history: C(service,E4(length)||hash) maps to a count and up to three E4 timeslots.
## Tagged fixed histories model shape only; chronology, availability and cross-map invariants remain contextual.
import std/assertions
import ./[natural, bounded, state_layout, state_trie, state_service_values]
export ServiceIndex, ServicePreimageHash

type
  ## Advertised preimage length has the complete E4 domain and is distinct from timeslots or byte-policy ceilings.
  RequestLength* = distinct uint32
  ## Absolute request-history timeslots are independent from service IDs and advertised lengths.
  RequestSlot* = distinct uint32
  ## Count determines the history mode exactly: requested, supplied, removed, or restored.
  RequestState* {.pure.} = enum
    Requested, Available, Unavailable, Reavailable
  ## Fixed tagged alternatives contain only their actual timeslots; default is the valid empty requested history.
  RequestHistory* = object
    case mode: RequestState
    of Requested:
      discard                                     # A not-yet-supplied request has no fabricated availability time.
    of Available:
      sinceSlot: RequestSlot                      # One supplied-at timeslot.
    of Unavailable:
      availableSlot, unavailableSlot: RequestSlot # Original supply and later removal timeslots.
    of Reavailable:
      originalSlot, removedSlot, restoredSlot: RequestSlot # Original supply/removal and latest restoration.
  ## Caller policy can be stricter than the protocol's fixed three-slot maximum.
  RequestHistoryConfig* = object
    items*: ElementLimit
    maxBytes*: ByteLimit
  ## Logical lookup hash bytes and encoded history bytes have independent resource policy.
  RequestEntryConfig* = object
    keyBytes*: ByteLimit
    history*: RequestHistoryConfig
  ## Default and failed results expose reasons alone, never default histories, keys or partial progress.
  RequestError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, InvalidCount, LimitExceeded, BackendFailure
  ## Only selected complete success exposes its application payload.
  RequestResult*[T] = object
    case status: RequestError
    of None:
      completed: T # Success is selected through the guarded accessor.
    else:
      discard      # Failed decode cannot appear to be a successful empty requested history.
  ## Complete prefix decoding returns independent fixed tagged fields and exact consumed extent without a heap owner.
  RequestHistoryRead* = object
    history*: RequestHistory
    consumed*: int
  ## Private bounded field staging has no input-derived allocation or public unused timeslots.
  Fields = object
    count: int
    slots: array[3, RequestSlot]

## Read-only reasons never authorize a default history, key or completed progress.
func error*[T](value: RequestResult[T]): RequestError = value.status
## Complete public payloads and private extent proofs require successful selection.
func value*[T](value: RequestResult[T]): T
    {.inline, requires: value.status == RequestError.None.} = value.completed

## Construct the valid zero-slot Requested shape without any inactive timestamp payload.
func requestedHistory*(): RequestHistory = RequestHistory(mode: Requested)
## Construct the one-slot Available shape, preserving the full unsigned supplied-at value.
func availableHistory*(since: RequestSlot): RequestHistory = RequestHistory(mode: Available,
    sinceSlot: since)
## Construct the two-slot Unavailable shape in supplied order, without chronology validation.
func unavailableHistory*(availableFrom, unavailableFrom: RequestSlot): RequestHistory =
  RequestHistory(mode: Unavailable, availableSlot: availableFrom, unavailableSlot: unavailableFrom)
## Construct the three-slot Reavailable shape without sorting or repairing its source timeslots.
func reavailableHistory*(originalFrom, removedAt, restoredAt: RequestSlot): RequestHistory =
  RequestHistory(mode: Reavailable, originalSlot: originalFrom, removedSlot: removedAt,
      restoredSlot: restoredAt)
## Inspect the read-only shape; callers cannot retag a history or manufacture inactive fields.
func state*(history: RequestHistory): RequestState = history.mode
## Extract a fixed copied since timestamp only from the selected Available alternative.
func since*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Available.} = history.sinceSlot
## Extract a fixed copied availableFrom timestamp only from the selected Unavailable alternative.
func availableFrom*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Unavailable.} = history.availableSlot
## Extract a fixed copied unavailableFrom timestamp only from the selected Unavailable alternative.
func unavailableFrom*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Unavailable.} = history.unavailableSlot
## Extract a fixed copied originalFrom timestamp only from the selected Reavailable alternative.
func originalFrom*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Reavailable.} = history.originalSlot
## Extract a fixed copied removedAt timestamp only from the selected Reavailable alternative.
func removedAt*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Reavailable.} = history.removedSlot
## Extract a fixed copied restoredAt timestamp only from the selected Reavailable alternative.
func restoredAt*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Reavailable.} = history.restoredSlot

## Project each tagged source alternative into a private fixed array only for sizing and final commit.
proc fields(value: RequestHistory): Fields =
  result = default(Fields)
  case value.state
  of RequestState.Requested: discard # Empty requested state needs only its count byte.
  of RequestState.Available:
    result.count = 1
    result.slots[0] = value.since # Select only the active one-slot payload.
  of RequestState.Unavailable:
    result.count = 2
    result.slots[0] = value.availableFrom # Retain original sequence order without chronology inference.
    result.slots[1] = value.unavailableFrom
  of RequestState.Reavailable:
    result.count = 3
    result.slots[0] = value.originalFrom # All three supplied/removal/restoration positions are serialized explicitly.
    result.slots[1] = value.removedAt
    result.slots[2] = value.restoredAt

## Protocol count precedes caller item/byte policy; accepted counts bound all native arithmetic to thirteen bytes.
proc extent(count: uint64, config: RequestHistoryConfig): RequestResult[int] =
  if count > 3:
    return RequestResult[int](status: RequestError.InvalidCount) # Never allocate or guess a fourth history mode.
  if count > uint64(config.items):
    return RequestResult[int](status: RequestError.LimitExceeded) # Caller may bound history work more tightly than protocol shape.
  let bytes = 1+int(count)*4
  if uint64(bytes) > uint64(config.maxBytes):
    return RequestResult[int](status: RequestError.LimitExceeded) # Empty requested state still needs one count discriminator.
  RequestResult[int](status: RequestError.None, completed: bytes)

## Decode one complete canonical fixed-domain history prefix before reading any of its timeslots.
proc decodeRequestHistory*(input: openArray[byte], config: RequestHistoryConfig): RequestResult[
    RequestHistoryRead] =
  let count = natural.decode(input)
  if not count.ok:
    if count.error == DecodeError.truncated:
      return RequestResult[RequestHistoryRead](status: RequestError.Truncated) # Missing count is not requested mode.
    else:
      return RequestResult[RequestHistoryRead](status: RequestError.NonCanonical) # Overlong 0..3 count encodings are invalid.
  let checked = extent(uint64(count.value), config)
  if checked.error != RequestError.None:
    return RequestResult[RequestHistoryRead](status: checked.error) # Shape/policy checks precede payload access.
  if input.len < checked.value:
    return RequestResult[RequestHistoryRead](status: RequestError.Truncated) # Require the final slot octet before copying earlier fields.
  var slots = default(array[3, RequestSlot])
  for i in 0..<int(uint64(count.value)):
    var value = 0'u32
    for j in 0..<4: value = value or (uint32(input[1+i*4+j]) shl (
        j*8)) # Accepted canonical 0..3 counts occupy exactly one byte.
    slots[i] = RequestSlot(value)
  var history = requestedHistory()
  case int(uint64(count.value))
  of 0: history = requestedHistory() # No inactive timestamp on the empty mode.
  of 1: history = availableHistory(slots[0]) # Exactly one supplied-at timestamp.
  of 2: history = unavailableHistory(slots[0], slots[1]) # Preserve both original positions.
  else: history = reavailableHistory(slots[0], slots[1], slots[
      2]) # Extent proved the only remaining count is three.
  RequestResult[RequestHistoryRead](status: RequestError.None,
    completed: RequestHistoryRead(history: history, consumed: checked.value))

## Derive the exact request key with a fixed E4 advertised length and opaque lookup hash, without length framing.
proc serviceRequestKey*(service: ServiceIndex, hash: ServicePreimageHash, length: RequestLength,
    maxKeyBytes: ByteLimit): RequestResult[StateKey] =
  if uint64(maxKeyBytes) < 32:
    return RequestResult[StateKey](status: RequestError.LimitExceeded) # Logical lookup identity is exactly 32 bytes; E4 prefix is fixed overhead.
  var preimage = default(array[36, byte])
  for i in 0..<4: preimage[i] = byte((uint32(length) shr (i*8)) and
      255) # Use the full stated E4 domain without inventing reserved-length restrictions.
  let bytes = array[32, byte](hash)
  for i in 0..<32: preimage[i+4] = bytes[i] # Hash bytes are not recomputed from a preimage or separately prefixed.
  let derived = hashedServiceKey(service, preimage, ByteLimit(preimage.len))
  if derived.error != StateLayoutError.None:
    return RequestResult[StateKey](status: RequestError.BackendFailure) # No default key after native hash failure.
  RequestResult[StateKey](status: RequestError.None, completed: derived.value)

## Construct one request mapping after complete history/key preflight; returned payload is independent caller storage.
proc serviceRequestEntry*(service: ServiceIndex, hash: ServicePreimageHash, length: RequestLength,
    history: RequestHistory, config: RequestEntryConfig): RequestResult[StateEntry] =
  let source = fields(history)
  let checked = extent(uint64(source.count), config.history)
  if checked.error != RequestError.None:
    return RequestResult[StateEntry](status: checked.error) # Do not perform key work or allocate output under invalid history policy.
  let derived = serviceRequestKey(service, hash, length, config.keyBytes)
  if derived.error != RequestError.None:
    return RequestResult[StateEntry](status: derived.error) # Key policy/backend failure publishes no entry.
  var entry = StateEntry(key: derived.value, value: newSeq[byte](checked.value))
  entry.value[0] = byte(source.count) # Canonical accepted counts are exactly one discriminator byte.
  for i in 0..<source.count:
    for j in 0..<4: entry.value[1+i*4+j] = byte((uint32(source.slots[i]) shr (j*8)) and
        255) # Fixed E4 timeslots preserve supplied sequence positions.
  RequestResult[StateEntry](status: RequestError.None, completed: entry)
