# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published Genesis wire owns a full header and one complete opaque RawState, without implicit trust.
import std/assertions
import ./state as trace_state
import ../store
import ../../codec/[header, bounded]

type
  TraceGenesisError* {.pure.} = enum ## Failed fields contain their genuine typed refusal, never a trusted chain or successful prefix.
    Uninitialized, None, InvalidOwner, LimitExceeded, HeaderFailure, StateFailure
  TraceGenesisResult*[T] = object ## Private successful payloads retain only complete immutable owners or detached observations.
    case status: TraceGenesisError
    of None: completed: T
    of HeaderFailure: headerReason: HeaderResult[HeaderRead]
    of StateFailure: stateReason: TraceStateError
    else: discard # Default and ordinary failures carry no child or consumed extent.
  TraceGenesisData = ref object ## Acyclic immutable children preserve exact original header and RawState order.
    header: OwnedHeader
    state: TraceState
    consumed: int
  TraceGenesis* = object ## Framing alone does not select a genesis identity, posterior state or Parameters.
    data: nil TraceGenesisData
  TraceGenesisLimits* = object ## Caller-selected structural header domains, complete-map policy and aggregate byte ceiling remain independent.
    header*: HeaderConfig
    state*: StateStoreLimits
    bytes*: ByteLimit

func error*[T](outcome: TraceGenesisResult[T]): TraceGenesisError =
  ## Inspect only the selected immutable stage.
  outcome.status
func value*[T](outcome: TraceGenesisResult[T]): T {.inline,
    requires: outcome.status == TraceGenesisError.None.} =
  ## Extract only a completely validated owner, detached bytes or copied observation.
  outcome.completed
func headerFailure*[T](outcome: TraceGenesisResult[T]): HeaderResult[HeaderRead] {.inline,
    requires: outcome.status == TraceGenesisError.HeaderFailure.} =
  ## Preserve the original failed structural header result without authorizing a header prefix.
  outcome.headerReason
func stateFailure*[T](outcome: TraceGenesisResult[T]): TraceStateError {.inline,
    requires: outcome.status == TraceGenesisError.StateFailure.} =
  ## Preserve the genuine complete-map/root refusal without a successful state owner.
  outcome.stateReason
func fail[T](reason: TraceGenesisError): TraceGenesisResult[T] =
  ## Centralize plain failure construction without manufacturing a success-shaped prefix.
  TraceGenesisResult[T](status: reason)

proc newTraceGenesis*(header: OwnedHeader, state: TraceState,
    bytes: ByteLimit): TraceGenesisResult[TraceGenesis] =
  ## Retain validated immutable children only after proving their combined extent; infer no posterior-state commitment from the header.
  let first = header.headerInfo
  let last = state.traceStateInfo
  if first.error != HeaderError.None or last.error != TraceStateError.None:
    return fail[TraceGenesis](TraceGenesisError.InvalidOwner)
  let maximum = min(uint64(bytes), uint64(high(int)))
  let head = uint64(first.value.consumed)
  if head > maximum or uint64(last.value.consumed) > maximum-head:
    return fail[TraceGenesis](TraceGenesisError.LimitExceeded)
  TraceGenesisResult[TraceGenesis](status: TraceGenesisError.None, completed: TraceGenesis(
      data: TraceGenesisData(header: header, state: state, consumed: int(head+uint64(
          last.value.consumed)))))

proc decodeTraceGenesis*(input: openArray[byte], limits: TraceGenesisLimits): TraceGenesisResult[TraceGenesis] =
  ## Borrow stable input synchronously and own exactly one Header/RawState prefix under explicit independent domains and byte limits.
  var config = limits.header
  config.maxBytes = ByteLimit(min(uint64(config.maxBytes), uint64(limits.bytes)))
  let header = decodeHeader(input, config)
  if header.error != HeaderError.None:
    return TraceGenesisResult[TraceGenesis](status: TraceGenesisError.HeaderFailure,
        headerReason: header)
  let offset = header.value.consumed
  let remaining = uint64(limits.bytes)-uint64(offset)
  let state = if offset < input.len: decodeTraceState(input.toOpenArray(offset, input.high),
      limits.state, ByteLimit(remaining))
      else: decodeTraceState([], limits.state, ByteLimit(
          remaining)) # The absent final field retains a real RawState truncation rather than an initialized empty map.
  if state.error != TraceStateError.None:
    return TraceGenesisResult[TraceGenesis](status: TraceGenesisError.StateFailure,
        stateReason: state.error)
  newTraceGenesis(header.value.owner, state.value, limits.bytes)

proc traceGenesisBytes*(source: TraceGenesis): TraceGenesisResult[int] =
  ## Return the exact prefix extent only for this initialized immutable composition.
  let data = source.data
  if data == nil: return fail[int](TraceGenesisError.InvalidOwner)
  TraceGenesisResult[int](status: TraceGenesisError.None, completed: data.consumed)
proc traceGenesisHeader*(source: TraceGenesis): TraceGenesisResult[OwnedHeader] =
  ## Retain the original schema-qualified header after the enclosing genesis owner retires.
  let data = source.data
  if data == nil: return fail[OwnedHeader](TraceGenesisError.InvalidOwner)
  TraceGenesisResult[OwnedHeader](status: TraceGenesisError.None, completed: data.header)
proc traceGenesisState*(source: TraceGenesis): TraceGenesisResult[TraceState] =
  ## Retain the exact recomputed complete opaque map, without inventing raw logical namespace identities.
  let data = source.data
  if data == nil: return fail[TraceState](TraceGenesisError.InvalidOwner)
  TraceGenesisResult[TraceState](status: TraceGenesisError.None, completed: data.state)
proc copyTraceGenesis*(source: TraceGenesis, bytes: ByteLimit): TraceGenesisResult[seq[byte]] =
  ## Prove complete output capacity before copying either immutable child into detached wire.
  let data = source.data
  if data == nil: return fail[seq[byte]](TraceGenesisError.InvalidOwner)
  if uint64(data.consumed) > uint64(bytes): return fail[seq[byte]](TraceGenesisError.LimitExceeded)
  var output = newSeq[byte](data.consumed)
  let head = data.header.headerInfo.value.consumed
  let encoded = data.header.encodeOwnedHeader(output.toOpenArray(0, head-1))
  assert encoded.error == HeaderError.None and encoded.value == head
  let state = data.state.copyTraceState(bytes).value
  for index in 0..<state.len: output[head+index] = state[
      index] # Exact child extents fit the preflighted complete destination.
  TraceGenesisResult[seq[byte]](status: TraceGenesisError.None, completed: output)
