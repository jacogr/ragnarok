# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T service request history: C(service,E4(length)||hash) maps to a count and up to
## three E4 timeslots. Tagged fixed histories model shape only; chronology, availability and
## cross-map invariants remain contextual.
##
## Exposes explicit request-history states, checked timestamp access, decoding and service
## request key/entry construction.

import std/assertions
import ./[natural, bounded, state_layout, state_trie, state_service_values]
export ServiceIndex, ServicePreimageHash

type
  RequestLength* = distinct uint32 ## Advertised preimage length has the complete E4 domain and is distinct from timeslots or byte-policy ceilings.
  RequestSlot* = distinct uint32 ## Absolute request-history timeslots are independent from service IDs and advertised lengths.
  RequestState* {.pure.} = enum ## Count determines the history mode exactly: requested, supplied, removed, or restored.
    Requested, Available, Unavailable, Reavailable
  RequestHistory* = object ## Fixed tagged alternatives contain only their actual timeslots; default is the valid empty requested history.
    case mode: RequestState
    of Requested:
      discard                                     # A not-yet-supplied request has no fabricated availability time.
    of Available:
      sinceSlot: RequestSlot                      # One supplied-at timeslot.
    of Unavailable:
      availableSlot, unavailableSlot: RequestSlot # Original supply and later removal timeslots.
    of Reavailable:
      originalSlot, removedSlot, restoredSlot: RequestSlot # Original supply/removal and latest restoration.
  RequestHistoryConfig* = object ## Caller policy can be stricter than the protocol's fixed three-slot maximum.
    items*: ElementLimit
    maxBytes*: ByteLimit
  RequestEntryConfig* = object ## Logical lookup hash bytes and encoded history bytes have independent resource policy.
    keyBytes*: ByteLimit
    history*: RequestHistoryConfig
  RequestError* {.pure.} = enum ## Default and failed results expose reasons alone, never default histories, keys or partial progress.
    Uninitialized, None, Truncated, NonCanonical, InvalidCount, InvalidLength, LimitExceeded, BackendFailure
  RequestResult*[T] = object ## Only selected complete success exposes its application payload.
    case status: RequestError
    of None:
      completed: T           # Success is selected through the guarded accessor.
    else:
      discard                # Failed decode cannot appear to be a successful empty requested history.
  RequestHistoryRead* = object ## Complete prefix decoding returns independent fixed tagged fields and exact consumed extent without a heap owner.
    history*: RequestHistory
    consumed*: int
  ## Private bounded field staging has no input-derived allocation or public unused timeslots.
  Fields = object
    count: int
    slots: array[3, RequestSlot]

func error*[T](value: RequestResult[T]): RequestError =
  ## Read-only reasons never authorize a default history, key or completed progress.
  value.status
func value*[T](value: RequestResult[T]): T
    {.inline, requires: value.status == RequestError.None.} =
  ## Complete public payloads and private extent proofs require successful selection.
  value.completed

func requestedHistory*(): RequestHistory =
  ## Construct the valid zero-slot Requested shape without any inactive timestamp payload.
  RequestHistory(mode: Requested)
func availableHistory*(since: RequestSlot): RequestHistory =
  ## Construct the one-slot Available shape, preserving the full unsigned supplied-at value.
  RequestHistory(mode: Available,
    sinceSlot: since)
func unavailableHistory*(availableFrom, unavailableFrom: RequestSlot): RequestHistory =
  ## Construct the two-slot Unavailable shape in supplied order, without chronology validation.
  RequestHistory(mode: Unavailable, availableSlot: availableFrom, unavailableSlot: unavailableFrom)
func reavailableHistory*(originalFrom, removedAt, restoredAt: RequestSlot): RequestHistory =
  ## Construct the three-slot Reavailable shape without sorting or repairing its source timeslots.
  RequestHistory(mode: Reavailable, originalSlot: originalFrom, removedSlot: removedAt,
      restoredSlot: restoredAt)
func state*(history: RequestHistory): RequestState =
  ## Inspect the read-only shape; callers cannot retag a history or manufacture inactive fields.
  history.mode
func since*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Available.} =
  ## Extract a fixed copied since timestamp only from the selected Available alternative.
  history.sinceSlot
func availableFrom*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Unavailable.} =
  ## Extract a fixed copied availableFrom timestamp only from the selected Unavailable alternative.
  history.availableSlot
func unavailableFrom*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Unavailable.} =
  ## Extract a fixed copied unavailableFrom timestamp only from the selected Unavailable alternative.
  history.unavailableSlot
func originalFrom*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Reavailable.} =
  ## Extract a fixed copied originalFrom timestamp only from the selected Reavailable alternative.
  history.originalSlot
func removedAt*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Reavailable.} =
  ## Extract a fixed copied removedAt timestamp only from the selected Reavailable alternative.
  history.removedSlot
func restoredAt*(history: RequestHistory): RequestSlot
    {.inline, requires: history.mode == RequestState.Reavailable.} =
  ## Extract a fixed copied restoredAt timestamp only from the selected Reavailable alternative.
  history.restoredSlot

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

proc decodeRequestHistory*(input: openArray[byte], config: RequestHistoryConfig): RequestResult[
    RequestHistoryRead] =
  ## Decode one complete canonical fixed-domain history prefix before reading any of its timeslots.
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

proc serviceRequestKey*(service: ServiceIndex, hash: ServicePreimageHash, length: RequestLength,
    maxKeyBytes: ByteLimit): RequestResult[StateKey] =
  ## Derive the exact request key with a fixed E4 advertised length and opaque lookup hash, without length framing.
  if uint64(maxKeyBytes) < 32:
    return RequestResult[StateKey](status: RequestError.LimitExceeded) # Logical lookup identity is exactly 32 bytes; E4 prefix is fixed overhead.
  if uint32(length) >= high(uint32)-1:
    return RequestResult[StateKey](status: RequestError.InvalidLength) # The current preimagelen domain excludes both reserved namespace prefixes.
  var preimage = default(array[36, byte])
  for i in 0..<4: preimage[i] = byte((uint32(length) shr (i*8)) and
      255) # The current paper reserves the two highest E4 values for storage and preimages.
  let bytes = array[32, byte](hash)
  for i in 0..<32: preimage[i+4] = bytes[i] # Hash bytes are not recomputed from a preimage or separately prefixed.
  let derived = hashedServiceKey(service, preimage, ByteLimit(preimage.len))
  if derived.error != StateLayoutError.None:
    return RequestResult[StateKey](status: RequestError.BackendFailure) # No default key after native hash failure.
  RequestResult[StateKey](status: RequestError.None, completed: derived.value)

proc serviceRequestEntry*(service: ServiceIndex, hash: ServicePreimageHash, length: RequestLength,
    history: RequestHistory, config: RequestEntryConfig): RequestResult[StateEntry] =
  ## Construct one request mapping after complete history/key preflight; returned payload is independent caller storage.
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
