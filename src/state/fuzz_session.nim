# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fuzzer-v1 session ordering and bounded incremental frames are independent of sockets and STF execution.
import std/assertions
import ./fuzz_protocol as state_fuzz_protocol
import ../codec/bounded as codec_bounded

type
  FuzzSessionError* {.pure.} = enum ## Protocol and host failures terminate locally without manufacturing consensus Error replies.
    Uninitialized, None, Closed, InvalidConfiguration, InvalidMessage, UnexpectedMessage,
    IncompatiblePeer, Busy, StaleRequest, InvalidResponse, LimitExceeded
  FuzzSessionResult*[T] = object ## Failure carries only its reason; no partial frame or execution ticket escapes.
    case status: FuzzSessionError
    of None: completed: T
    else: discard # Failed alternatives contain no success-shaped prefix.
  SessionPhase = enum ## Default sessions are inert and cannot admit a handshake.
    Dormant, Handshake, Initialization, Active, Pending, Terminated
  RequestData = ref object ## Unique immutable identity binds a backend reply to this exact outstanding request.
    message: FuzzMessage
  FuzzRequest* = object ## Copying a ticket shares immutable identity, not mutable session authority.
    data: nil RequestData
  FuzzDispatchKind* {.pure.} = enum ## A decoded request either gets the automatic handshake reply or requires host execution.
    Reply, Execute
  FuzzDispatch* = object ## Private alternatives prevent request and automatic reply payloads being interchanged.
    case selected: FuzzDispatchKind
    of Reply: response: FuzzMessage
    of Execute: ticket: FuzzRequest
  FuzzSession* = object ## Each connection owns its own ordering, feature intersection and pending ticket.
    phase: SessionPhase
    local: FuzzPeer
    limits: FuzzLimits
    features: uint32
    pending: nil RequestData
  FuzzFrameReader* = object ## At most one validated frame is assembled; caller retains any unread suffix.
    configured, failed: bool
    limits: FuzzLimits
    prefix: array[4, byte]
    prefixBytes, extent: int
    payload: seq[byte]
  FuzzFrameProgress* = object ## Consumed bytes always refer to this call; only a complete result owns a message.
    used: int
    case ready: bool
    of true: message: FuzzMessage
    else: discard # Incomplete assembly exposes no child owner.

func error*[T](outcome: FuzzSessionResult[T]): FuzzSessionError =
  ## Inspect the immutable reason without touching an absent payload.
  outcome.status
func value*[T](outcome: FuzzSessionResult[T]): T {.inline,
    requires: outcome.status == FuzzSessionError.None.} =
  ## Extract only the completed alternative.
  outcome.completed
func refused[T](reason: FuzzSessionError): FuzzSessionResult[T] =
  ## Construct a failure containing only the selected reason.
  FuzzSessionResult[T](status: reason)
func kind*(dispatch: FuzzDispatch): FuzzDispatchKind =
  ## Select the guarded request/reply accessor.
  dispatch.selected
func reply*(dispatch: FuzzDispatch): FuzzMessage {.inline,
    requires: dispatch.selected == FuzzDispatchKind.Reply.} =
  ## Automatic responses are limited to the negotiated handshake.
  dispatch.response
func request*(dispatch: FuzzDispatch): FuzzRequest {.inline,
    requires: dispatch.selected == FuzzDispatchKind.Execute.} =
  ## Retain the outstanding immutable execution ticket.
  dispatch.ticket
proc requestMessage*(ticket: FuzzRequest): FuzzSessionResult[FuzzMessage] =
  ## Default tickets grant no backend input.
  let data = ticket.data
  if data == nil: return refused[FuzzMessage](FuzzSessionError.StaleRequest)
  FuzzSessionResult[FuzzMessage](status: FuzzSessionError.None, completed: data.message)
func consumed*(progress: FuzzFrameProgress): int =
  ## Report the exact bounded input prefix consumed by the reader.
  progress.used
func complete*(progress: FuzzFrameProgress): bool =
  ## Incomplete frames retain their private assembly and expose no message.
  progress.ready
func message*(progress: FuzzFrameProgress): FuzzMessage {.inline, requires: progress.ready.} =
  ## Extract one completely decoded message.
  progress.message
func sameVersion(left, right: FuzzVersion): bool =
  ## Require exact selected JAM profile; application versions are informational.
  left.major == right.major and left.minor == right.minor and left.patch == right.patch
proc close*(session: var FuzzSession) =
  ## Closing invalidates outstanding tickets and releases retained input ownership.
  session.phase = Terminated
  session.pending = nil
func closed*(session: FuzzSession): bool =
  ## Dormant/default and terminated connections cannot accept messages.
  session.phase in {Dormant, Terminated}
func negotiatedFeatures*(session: FuzzSession): uint32 =
  ## Only advertised supported bits intersect; the host must implement every bit it advertises.
  session.features
proc initFuzzSession*(local: FuzzPeer, limits: FuzzLimits): FuzzSessionResult[FuzzSession] =
  ## Validate the target declaration before any connection becomes active.
  if local.protocol != 1 or (local.features and not 3'u32) != 0 or uint64(limits.bytes) == 0:
    return refused[FuzzSession](FuzzSessionError.InvalidConfiguration)
  if newFuzzPeer(local, limits).error != FuzzError.None:
    return refused[FuzzSession](FuzzSessionError.InvalidConfiguration)
  FuzzSessionResult[FuzzSession](status: FuzzSessionError.None,
      completed: FuzzSession(phase: Handshake, local: local, limits: limits))
proc receive*(session: var FuzzSession, message: FuzzMessage): FuzzSessionResult[FuzzDispatch] =
  ## Admit only one ordered request. No initialization or import runs inside this protocol boundary.
  if session.closed: return refused[FuzzDispatch](FuzzSessionError.Closed)
  let info = message.fuzzInfo
  if info.error != FuzzError.None:
    session.close()
    return refused[FuzzDispatch](FuzzSessionError.InvalidMessage)
  if uint64(info.value.bytes) > uint64(session.limits.bytes):
    session.close()
    return refused[FuzzDispatch](FuzzSessionError.LimitExceeded)
  if session.phase == Pending:
    session.close()
    return refused[FuzzDispatch](FuzzSessionError.Busy)
  if session.phase == Handshake:
    if info.value.kind != FuzzKind.PeerInfo:
      session.close()
      return refused[FuzzDispatch](FuzzSessionError.UnexpectedMessage)
    let remote = message.fuzzPeer.value
    if remote.protocol != 1 or not sameVersion(remote.jam, session.local.jam):
      session.close()
      return refused[FuzzDispatch](FuzzSessionError.IncompatiblePeer)
    session.features = remote.features and session.local.features
    session.phase = Initialization
    return FuzzSessionResult[FuzzDispatch](status: FuzzSessionError.None,
        completed: FuzzDispatch(selected: FuzzDispatchKind.Reply,
          response: newFuzzPeer(session.local, session.limits).value))
  let expected = if session.phase == Initialization: info.value.kind == FuzzKind.Initialize
      else: info.value.kind in {FuzzKind.ImportBlock, FuzzKind.GetState}
  if not expected:
    session.close()
    return refused[FuzzDispatch](FuzzSessionError.UnexpectedMessage)
  if info.value.kind == FuzzKind.Initialize and (session.features and 1'u32) == 0 and
      message.fuzzAncestors.value.len != 0:
    session.close()
    return refused[FuzzDispatch](FuzzSessionError.UnexpectedMessage)
  let data = RequestData(message: message)
  session.pending = data
  session.phase = Pending
  FuzzSessionResult[FuzzDispatch](status: FuzzSessionError.None,
      completed: FuzzDispatch(selected: FuzzDispatchKind.Execute, ticket: FuzzRequest(data: data)))
proc respond*(session: var FuzzSession, ticket: FuzzRequest,
    response: FuzzMessage): FuzzSessionResult[FuzzMessage] =
  ## Host success must match the outstanding request. Error is meaningful only for a consensus ImportBlock refusal.
  if session.closed: return refused[FuzzMessage](FuzzSessionError.Closed)
  let pending = session.pending
  if session.phase != Pending or pending == nil or ticket.data != pending:
    session.close()
    return refused[FuzzMessage](FuzzSessionError.StaleRequest)
  let info = response.fuzzInfo
  if info.error != FuzzError.None:
    session.close()
    return refused[FuzzMessage](FuzzSessionError.InvalidResponse)
  let source = pending.message.fuzzInfo.value.kind
  let valid = case source
    of FuzzKind.Initialize: info.value.kind == FuzzKind.StateRoot # Initialization failure closes; it is not an import Error.
    of FuzzKind.ImportBlock: info.value.kind in {FuzzKind.StateRoot,
        FuzzKind.Error} # A genuine rejected block leaves the session usable.
    of FuzzKind.GetState: info.value.kind == FuzzKind.State # Missing history/internal failures close the connection.
    else: false         # No other kind can obtain an execution ticket.
  if not valid or uint64(info.value.bytes) > uint64(session.limits.bytes):
    session.close()
    return refused[FuzzMessage](FuzzSessionError.InvalidResponse)
  session.pending = nil
  session.phase = Active
  FuzzSessionResult[FuzzMessage](status: FuzzSessionError.None, completed: response)
proc initFuzzFrameReader*(limits: FuzzLimits): FuzzFrameReader =
  ## An explicit policy enables assembly; zero budgets fail before payload allocation.
  FuzzFrameReader(configured: uint64(limits.bytes) > 0, limits: limits)
proc feed*(reader: var FuzzFrameReader, input: openArray[byte]): FuzzSessionResult[
    FuzzFrameProgress] =
  ## Consume at most one frame and leave pipelined suffix bytes with the caller. Bad input permanently retires this reader.
  if not reader.configured or reader.failed:
    return refused[FuzzFrameProgress](FuzzSessionError.Closed)
  var used = 0
  while reader.prefixBytes < 4 and used < input.len:
    reader.prefix[reader.prefixBytes] = input[used] # Both cursors are bounded before access.
    inc reader.prefixBytes
    inc used
  if reader.prefixBytes < 4:
    return FuzzSessionResult[FuzzFrameProgress](status: FuzzSessionError.None,
        completed: FuzzFrameProgress(ready: false, used: used))
  if reader.payload.len == 0:
    let length = fuzzFrameLength(reader.prefix, reader.limits.bytes)
    if length.error != FuzzError.None:
      reader.failed = true
      return refused[FuzzFrameProgress](FuzzSessionError.LimitExceeded)
    reader.payload = newSeq[byte](length.value) # Length and policy are validated before allocation.
  let count = min(reader.payload.len-reader.extent, input.len-used)
  for index in 0..<count: reader.payload[reader.extent+index] = input[
      used+index] # Remaining extents prove both accesses.
  reader.extent += count
  used += count
  if reader.extent != reader.payload.len:
    return FuzzSessionResult[FuzzFrameProgress](status: FuzzSessionError.None,
        completed: FuzzFrameProgress(ready: false, used: used))
  let decoded = decodeFuzzMessage(reader.payload, reader.limits)
  reader.payload = @[]
  reader.extent = 0
  reader.prefixBytes = 0
  if decoded.error != FuzzError.None:
    reader.failed = true
    return refused[FuzzFrameProgress](FuzzSessionError.InvalidMessage)
  FuzzSessionResult[FuzzFrameProgress](status: FuzzSessionError.None,
      completed: FuzzFrameProgress(ready: true, used: used, message: decoded.value))
