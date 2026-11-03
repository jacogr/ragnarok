# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded fixed-request CE128/129/143 framing. Parent owns native retirement and deadlines;
## callbacks retain bytes only, and the host resolves canonical requests outside engine calls.
import ../quic/transport

type
  ReadKind* {.pure.} = enum ## Only fixed-request canonical retrieval methods share this route.
    Blocks = 128, State = 129, Preimage = 143
  ReadError* {.pure.} = enum ## Failures never expose a partial request/reply owner.
    Uninitialized, None, InvalidRequest, Unavailable, LimitExceeded, InvalidStream, Busy, BackendFailure
  ReadRequest* = object ## Exact bounded copied request facts survive a host/worker handoff without native pointers.
    ready: bool
    selector: ReadKind
    payload: array[98, byte]
    length: int
  ReadReply* = object ## Frozen framed bytes are bound to all originating request facts.
    request: ReadRequest
    wire: seq[byte]
  ReadResult*[T] = object ## Private success tags gate all extraction.
    case status: ReadError
    of None: completed: T
    else: discard         # No partial byte owners escape failures.
  ReadRoute* = object ## Native stream is borrowed through close; fixed-address parent owns capacity and cancellation.
    stream: NativeStream
    selector: ReadKind
    request: array[103, byte]
    used, offset: int
    captured: ReadRequest
    output: seq[byte]
    pending, taken, writing, failed: bool
const MaxReadReplyBytes* = 8*1024*1024 ## Aggregate framed reply ceiling, independent of untrusted u32 limits.
func error*[T](outcome: ReadResult[T]): ReadError =
  ## Inspect the private discriminator.
  outcome.status
func readFailure*[T](reason: ReadError): ReadResult[T] {.requires: reason != ReadError.None.} =
  ## Backends can report a reason without exposing result discriminators or success construction.
  ReadResult[T](status: reason)
func value*[T](outcome: ReadResult[T]): T {.requires: outcome.status == ReadError.None.} =
  ## Extract only a complete successful owner.
  outcome.completed
func valid*(request: ReadRequest): bool =
  ## Default requests confer no framing or reply authority.
  request.ready
func kind*(request: ReadRequest): ReadKind {.requires: request.ready.} =
  ## Copy the exact admitted selector.
  request.selector
func requestLength(kind: ReadKind): int =
  ## Pinned fixed payload extents exclude selector and E4 header.
  case kind
  of ReadKind.Blocks: 37
  of ReadKind.State: 98
  of ReadKind.Preimage: 32
proc payload*(request: ReadRequest): seq[byte] {.requires: request.ready.} =
  ## Copy only complete admitted payload bytes; no mutable fixed backing array escapes.
  result = newSeq[byte](request.length)
  for index in 0..<request.length: result[index] = request.payload[index]
proc decodeReadRequest*(kind: ReadKind, payload: openArray[byte]): ReadResult[ReadRequest] =
  ## Validate exact extents before retaining transport facts; method-specific semantics stay in services.
  if payload.len != requestLength(kind): return ReadResult[ReadRequest](
      status: ReadError.InvalidRequest)
  var captured = ReadRequest(ready: true, selector: kind, length: payload.len)
  for index in 0..<payload.len: captured.payload[index] = payload[index]
  ReadResult[ReadRequest](status: ReadError.None, completed: captured)
func sameRequest(left, right: ReadRequest): bool =
  ## Full fixed-array equality prevents foreign/stale work from targeting a different request.
  left.ready and right.ready and left.selector == right.selector and left.length == right.length and
      left.payload == right.payload
proc captureReadReply*(request: ReadRequest, wire: openArray[byte]): ReadResult[ReadReply] =
  ## Freeze only an exact bounded sequence of E4 messages; this grants no state/consensus authority.
  if not request.ready: return ReadResult[ReadReply](status: ReadError.InvalidRequest)
  if wire.len > MaxReadReplyBytes: return ReadResult[ReadReply](status: ReadError.LimitExceeded)
  let count = if request.selector == ReadKind.State: 2 else: 1
  var cursor = 0
  for message in 0..<count:
    if wire.len-cursor < 4: return ReadResult[ReadReply](status: ReadError.InvalidRequest)
    var length = 0'u64
    for index in 0..<4: length = length or (uint64(wire[cursor+index]) shl (8*index))
    cursor += 4
    if length > uint64(wire.len-cursor): return ReadResult[ReadReply](
        status: ReadError.InvalidRequest)
    cursor += int(length) # The remaining host-sized slice proves this conversion and addition.
  if cursor != wire.len: return ReadResult[ReadReply](status: ReadError.InvalidRequest)
  var copied = newSeq[byte](wire.len)
  for index in 0..<wire.len: copied[index] = wire[index]
  ReadResult[ReadReply](status: ReadError.None, completed: ReadReply(request: request, wire: copied))
proc bytes*(reply: ReadReply): seq[byte] =
  ## Copy the frozen transcript without exporting mutable storage.
  reply.wire
func handle*(route: ReadRoute): NativeStream =
  ## Parent compares the borrowed pointer only during its native lifetime.
  route.stream
proc reject*(route: var ReadRoute) =
  ## Revoke pending work before resetting only this stream.
  route.failed = true
  route.pending = false
  route.output = @[]
  if route.stream != NativeStream(nil): streamAbort(route.stream)
proc bindReadStream*(route: var ReadRoute, stream: NativeStream, kind: ReadKind,
    kindConsumed = false): ReadError =
  ## A multiplexer may consume the selector before binding; local initiation remains the parent's check.
  if stream == NativeStream(nil): return ReadError.InvalidStream
  if (uint64(stream.streamId) and 2) != 0: return ReadError.InvalidStream
  if route.stream != NativeStream(nil): return ReadError.Busy
  route = ReadRoute(stream: stream, selector: kind)
  if kindConsumed:
    route.request[0] = byte(kind)
    route.used = 1 # Preserve one consistent whole-request fingerprint after external selector dispatch.
  wantRead(stream, 1)
  ReadError.None
proc takeRequest*(route: var ReadRoute): ReadResult[ReadRequest] =
  ## Exactly one host job is released only after the complete request and FIN.
  if not route.pending or route.taken or route.failed: return ReadResult[ReadRequest](
      status: ReadError.Unavailable)
  route.taken = true
  ReadResult[ReadRequest](status: ReadError.None, completed: route.captured)
proc respond*(route: var ReadRoute, reply: ReadReply): ReadError =
  ## A reply for any different request cannot be sent through this borrowed stream.
  if route.stream == NativeStream(nil) or route.failed or not route.pending or
      not route.taken: return ReadError.InvalidStream
  if not sameRequest(route.captured, reply.request): return ReadError.InvalidRequest
  route.output = reply.wire
  route.pending = false
  route.writing = true
  wantWrite(route.stream, 1)
  ReadError.None
proc event*(route: var ReadRoute, stream: NativeStream, event: cint) =
  ## One bounded native read/write per callback; only native close releases the route slot.
  if route.stream != stream or stream == NativeStream(nil): return
  if event == 3:
    route = default(ReadRoute)
    return # Late worker replies can no longer match an active pending request.
  if event == 4:
    route.failed = true
    route.pending = false
    route.output = @[]
    wantRead(stream, 0)
    wantWrite(stream, 0)
    return # Reset is terminal before final native retirement.
  if route.failed: return
  case event
  of 1:
    var buffer = default(array[104, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return
    let extent = requestLength(route.selector)+5
    if count < 0 or count > int64(extent-route.used):
      route.reject()
      return # Extra messages/suffixes never allocate or release host work.
    if count > 0:
      for index in 0..<int(count): route.request[route.used+index] = buffer[index]
      route.used += int(count)
      return # Even exact full payloads wait for native FIN.
    if route.used != extent or route.request[0] != byte(route.selector) or
        route.request[1] != byte(extent-5) or route.request[2] != 0 or route.request[3] != 0 or
            route.request[4] != 0:
      route.reject()
      return # One exact fixed-size E4 message is the entire request.
    let decoded = decodeReadRequest(route.selector, route.request.toOpenArray(5, extent-1))
    if decoded.error != ReadError.None:
      route.reject()
      return
    route.captured = decoded.value
    route.pending = true
    readDone(stream)
    wantRead(stream, 0)
  of 2:
    if not route.writing: return
    let length = min(4096, route.output.len-route.offset)
    if length > 0:
      let written = streamWrite(stream, addr route.output[route.offset], csize_t(length))
      if written == -2: return
      if written < 0 or written > int64(length):
        route.reject()
        return
      route.offset += int(written) # Never repeat an accepted prefix after a short write.
    if route.offset == route.output.len:
      route.writing = false
      wantWrite(stream, 0)
      discard streamFlush(stream)
      streamFin(stream) # Output remains owned through actual close.
  else: discard # The parent binds this route during the initial native open callback.
