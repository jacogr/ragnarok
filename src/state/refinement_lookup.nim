# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 refinement host 7: read-only historical preimage lookup at a retained anchor time.
## Captures complete-state ownership and returns atomic guest responses; no block publication or invocation certification.

import ../codec/bounded as codec_bounded
import ../codec/state_accounts as codec_state_accounts
import ../codec/state_layout as codec_state_layout
import ../codec/state_service_values as codec_state_service_values
import ../codec/state_requests as codec_state_requests
import ../codec/work_report as codec_work_report
import ../pvm/machine as pvm_machine
import ../pvm/step as pvm_step
import ./store as state_store

type
  HistoricalLookupError* {.pure.} = enum ## Local refusals carry no response or captured context.
    Uninitialized, None, InvalidContext, InvalidMemory, MalformedState, LimitExceeded, BackendFailure
  LookupData = ref object ## Acyclic ownership binds immutable full-state data to the caller-selected service and anchor.
    state: StateStoreSnapshot
    service: ServiceIndex
    anchor: LookupSlot
  HistoricalLookupContext* = object ## Read-only host input; callers separately authenticate the state/anchor for refinement.
    data: nil LookupData
  HistoricalPreimage* = object ## An optional immutable value; absence has no fabricated byte payload.
    case selected: bool
    of true:
      stored: StateValue
    of false:
      discard # Includes the genuine absent alternative, independently of a present empty value.
  HistoricalLookupResult*[T] = object ## Default/refused alternatives have no accessible success payload.
    case status: HistoricalLookupError
    of None:
      completed: T
    else:
      discard # No fabricated empty preimage, memory or context on failure.

func error*[T](outcome: HistoricalLookupResult[T]): HistoricalLookupError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: HistoricalLookupResult[T]): T {.inline,
    requires: outcome.status == HistoricalLookupError.None.} =
  ## Extract only selected complete success, retaining its immutable children.
  outcome.completed

proc captureHistoricalLookup*(state: StateStoreSnapshot, service: ServiceIndex,
    anchor: LookupSlot): HistoricalLookupResult[HistoricalLookupContext] =
  ## Retain a complete snapshot without copying/hashing it; absent self is a valid optional lookup context.
  let checked = state.lookup(chapterServiceKey(StateChapter(255), service))
  if checked.error notin {StateStoreError.None, StateStoreError.MissingKey}:
    return HistoricalLookupResult[HistoricalLookupContext](
        status: HistoricalLookupError.InvalidContext)
  HistoricalLookupResult[HistoricalLookupContext](status: HistoricalLookupError.None,
    completed: HistoricalLookupContext(data: LookupData(state: state, service: service,
        anchor: anchor)))

func available(history: RequestHistory, anchor: LookupSlot): bool =
  ## Apply the pinned four-shape equation verbatim, without imposing extra chronological validation.
  let time = uint32(anchor)
  case history.state
  of RequestState.Requested:
    false # An empty history has never supplied the preimage.
  of RequestState.Available:
    uint32(history.since) <= time
  of RequestState.Unavailable:
    uint32(history.availableFrom) <= time and time < uint32(history.unavailableFrom)
  of RequestState.Reavailable:
    (uint32(history.originalFrom) <= time and time < uint32(history.removedAt)) or
      uint32(history.restoredAt) <= time

func present*(preimage: HistoricalPreimage): bool =
  ## Distinguish absence from an available zero-byte preimage.
  preimage.selected
func value*(preimage: HistoricalPreimage): StateValue {.requires: preimage.selected.} =
  ## Retain immutable bytes only for the present alternative; copying remains separately bounded.
  preimage.stored

proc historicalPreimage*(context: HistoricalLookupContext, service: ServiceIndex,
    hash: ServicePreimageHash): HistoricalLookupResult[HistoricalPreimage] =
  ## Resolve the pinned account/history equation once for both guest lookup and code bootstrap.
  ## No preimage copy or content rehash occurs here; callers authenticate supplied complete state separately.
  template fail(reason: HistoricalLookupError) =
    return HistoricalLookupResult[HistoricalPreimage](status: reason)
  template absent() =
    return HistoricalLookupResult[HistoricalPreimage](status: HistoricalLookupError.None,
      completed: HistoricalPreimage(selected: false))
  let data = context.data
  if data == nil: fail(HistoricalLookupError.InvalidContext)
  let account = data.state.lookup(chapterServiceKey(StateChapter(255), service))
  if account.error == StateStoreError.MissingKey: absent()
  if account.error != StateStoreError.None: fail(HistoricalLookupError.InvalidContext)
  if account.value.byteLength != ServiceMetadataBytes:
    fail(HistoricalLookupError.MalformedState) # Bound the fixed account copy before decoding.
  if decodeServiceMetadata(account.value.bytes, ByteLimit(ServiceMetadataBytes)).error !=
      ServiceMetadataError.None:
    fail(HistoricalLookupError.MalformedState)
  let preimageKey = servicePreimageKey(service, hash, ByteLimit(32))
  if preimageKey.error != ServiceValueError.None: fail(HistoricalLookupError.BackendFailure)
  let preimage = data.state.lookup(preimageKey.value)
  if preimage.error == StateStoreError.MissingKey: absent()
  if preimage.error != StateStoreError.None: fail(HistoricalLookupError.InvalidContext)
  let size = uint64(preimage.value.byteLength)
  if size > uint64(high(uint32)):
    fail(HistoricalLookupError.LimitExceeded) # The existing request-key codec's E4 domain must never truncate an actual length.
  let requestKey = serviceRequestKey(service, hash, RequestLength(uint32(size)), ByteLimit(32))
  if requestKey.error != RequestError.None: fail(HistoricalLookupError.BackendFailure)
  let request = data.state.lookup(requestKey.value)
  if request.error == StateStoreError.MissingKey:
    fail(HistoricalLookupError.MalformedState) # Every stored preimage requires its actual-length request by the account invariant.
  if request.error != StateStoreError.None: fail(HistoricalLookupError.InvalidContext)
  if request.value.byteLength > 13:
    fail(HistoricalLookupError.MalformedState) # One canonical natural count and at most three E4 timeslots.
  let bytes = request.value.bytes
  let decoded = decodeRequestHistory(bytes, RequestHistoryConfig(items: ElementLimit(3),
      maxBytes: ByteLimit(13)))
  if decoded.error != RequestError.None: fail(HistoricalLookupError.MalformedState)
  if decoded.value.consumed != bytes.len: fail(HistoricalLookupError.MalformedState)
  if not available(decoded.value.history, data.anchor): absent()
  HistoricalLookupResult[HistoricalPreimage](status: HistoricalLookupError.None,
    completed: HistoricalPreimage(selected: true, stored: preimage.value))

proc historicalLookupResponse*(context: HistoricalLookupContext, gas: MachineGas,
    registers: RegisterFile, memory: Memory, copyLimit: MemoryByteLimit):
    HistoricalLookupResult[HostResponse] =
  ## Evaluate Omega_H only; a trusted dispatcher selects host 7 and applies the response to its suspension.
  ## Fixed metadata/hash/history capture is independent of the selected suffix copy budget.
  template fail(reason: HistoricalLookupError) =
    return HistoricalLookupResult[HostResponse](status: reason)
  let data = context.data
  if data == nil: fail(HistoricalLookupError.InvalidContext)
  if memory.pageImage(PageIndex(0)).error != MachineError.None:
    fail(HistoricalLookupError.InvalidMemory) # Invalid local owners cannot masquerade as guest panic or OOG.
  let requested = uint64(registers[11])
  # Splitting at 1024 proves all multiplication/addition fits uint64; even the maximal cost is below 2^63.
  let cost = 1125'u64+(requested div 1024)*264+((requested mod 1024)*264+1023) div 1024
  let credit = uint64(gas)
  var response = HostResponse(action: HostAction.Continue, gas: MachineGas(0),
    gasDeficit: GasDeficit(0), registers: registers, memory: memory)
  if credit < cost:
    response.action = HostAction.OutOfGas
    response.gasDeficit = GasDeficit(0) # Zero-gas OutOfGas precedes reads, hashing and register changes.
    return HistoricalLookupResult[HostResponse](status: HistoricalLookupError.None,
        completed: response)
  response.gas = MachineGas(credit-cost)
  let input = readBytes(memory, MemoryAddress(uint64(registers[8])), MemoryLength(32),
      MemoryByteLimit(32))
  case input.error
  of MachineError.None:
    discard # A readable complete hash is required even for an absent or out-of-domain service.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic
    return HistoricalLookupResult[HostResponse](status: HistoricalLookupError.None,
        completed: response)
  else:
    fail(HistoricalLookupError.InvalidMemory) # The fixed read has no caller-variable allocation budget.
  template absent() =
    response.registers[7] = RegisterValue(high(uint64))
    return HistoricalLookupResult[HostResponse](status: HistoricalLookupError.None,
        completed: response)
  var service = data.service
  let target = uint64(registers[7])
  if target != high(uint64):
    if target > uint64(high(uint32)): absent() # Refuse truncation into an unrelated existing service.
    service = ServiceIndex(uint32(target))
  var rawHash = default(array[32, byte])
  for index in 0..<32:
    rawHash[index] = input.value[index] # The successful fixed read proves every index.
  let resolved = historicalPreimage(context, service, ServicePreimageHash(rawHash))
  if resolved.error != HistoricalLookupError.None: fail(resolved.error)
  if not resolved.value.present: absent()
  let preimage = resolved.value.value
  let size = uint64(preimage.byteLength)
  let offset = min(uint64(registers[10]), size)
  let count = min(requested, size-offset) # Clipping proves subtraction and every later native coordinate.
  let copied = preimage.copySlice(offset, count, ByteLimit(uint64(copyLimit)))
  if copied.error == StateStoreError.LimitExceeded: fail(HistoricalLookupError.LimitExceeded)
  if copied.error != StateStoreError.None: fail(HistoricalLookupError.InvalidContext)
  let written = writeBytes(memory, MemoryAddress(uint64(registers[9])), copied.value, copyLimit)
  case written.error
  of MachineError.None:
    response.memory = written.value
    response.registers[7] = RegisterValue(size) # Present empty returns zero, independently of absent NONE.
  of MachineError.Fault, MachineError.InvalidRange:
    response.action = HostAction.Panic # No prefix write or r7 update when any effective destination byte is invalid.
  of MachineError.LimitExceeded:
    fail(HistoricalLookupError.LimitExceeded)
  else:
    fail(HistoricalLookupError.InvalidMemory)
  HistoricalLookupResult[HostResponse](status: HistoricalLookupError.None, completed: response)
