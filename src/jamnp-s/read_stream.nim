# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded canonical reads, opaque uploads and availability framing. Parent owns native retirement and deadlines;
## callbacks retain bytes only, and the host resolves canonical requests outside engine calls.

import ../quic/transport
import ./segment_request
import ../codec/bounded

const MaxReadRequestPayload* = 789 ## Largest supported fixed payload is the exact CE131/132 epoch/attempt/proof.

type
  ReadKind* {.pure.} = enum ## Content retrieval and fixed/variable bare-FIN uploads share bounded framing.
    Blocks = 128, State = 129, TicketProxy = 131, TicketDistribution = 132, Guarantee = 135,
        Report = 136, Availability = 137, Audit = 138, SegmentShards = 139,
            ProvenSegmentShards = 140, Assurance = 141, PreimageAnnouncement = 142, Preimage = 143,
                AuditAnnouncement = 144, Judgment = 145, Bundle = 147, Segments = 148
  ReadError* {.pure.} = enum ## Failures never expose a partial request/reply owner.
    Uninitialized, None, InvalidRequest, Unavailable, LimitExceeded, InvalidStream, Busy, BackendFailure
  ReadRequest* = object ## Exact bounded copied request facts survive a host/worker handoff without native pointers.
    ready: bool
    selector: ReadKind
    payload: array[MaxReadRequestPayload, byte]
    length: int
    variable: seq[byte]
    groups, items: int
  ReadEffect* {.pure.} = enum ## Local backend planning hints never travel on the wire or establish a state certificate.
    None, FetchPreimage
  ReadReply* = object ## Frozen framed bytes are bound to all originating request facts.
    request: ReadRequest
    wire: seq[byte]
    effect: ReadEffect
  ReadResult*[T] = object ## Private success tags gate all extraction.
    case status: ReadError
    of None: completed: T
    else: discard         # No partial byte owners escape failures.
  ReadRoute* = object ## Native stream is borrowed through close; fixed-address parent owns capacity and cancellation.
    stream: NativeStream
    selector: ReadKind
    request: array[MaxReadRequestPayload+5, byte]
    used, offset: int
    captured: ReadRequest
    output: seq[byte]
    pending, taken, writing, failed: bool
    variable: seq[byte]
    cursor: SegmentRequestCursor
    declared: int

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

func batch*(kind: ReadKind): bool =
  ## Variable grouped retrieval has a separate finite payload ceiling and incremental grammar.
  kind in [ReadKind.SegmentShards, ReadKind.ProvenSegmentShards, ReadKind.Segments]

func variable*(kind: ReadKind): bool =
  ## Opaque guaranteed reports share bounded variable storage with grouped requests, without borrowing the grouped-request grammar.
  kind.batch or kind in [ReadKind.Guarantee, ReadKind.Assurance, ReadKind.AuditAnnouncement,
      ReadKind.Judgment]

func maximumRequestBytes(kind: ReadKind): int =
  ## CE135 has an independent local hard ceiling; grouped requests retain their exact existing grammar ceiling.
  if kind == ReadKind.Assurance: 139 # Anchor, largest fixed profile bitfield and Ed25519 signature.
  elif kind == ReadKind.Guarantee: MaxReadReplyBytes
  elif kind == ReadKind.AuditAnnouncement: 16*133 # Whole batches have at most sixteen fixed initial/later records.
  elif kind == ReadKind.Judgment: 16*306 # Each maximum negative record has three inline credentials.
  else: kind.segmentKind.maximumPayload

func segmentKind*(kind: ReadKind): SegmentRequestKind {.requires: kind.batch.} =
  ## Only declared batch selectors enter the matching protocol grammar.
  case kind
  of ReadKind.SegmentShards: SegmentRequestKind.Shards
  of ReadKind.ProvenSegmentShards: SegmentRequestKind.ProvenShards
  else: SegmentRequestKind.Segments # The checked precondition excludes all fixed selectors.

func requestLength(kind: ReadKind): int =
  ## Pinned fixed payload extents exclude selector and E4 header.
  case kind
  of ReadKind.Guarantee, ReadKind.Assurance, ReadKind.AuditAnnouncement, ReadKind.Judgment,
      ReadKind.SegmentShards, ReadKind.ProvenSegmentShards, ReadKind.Segments: -1
  of ReadKind.Blocks: 37
  of ReadKind.State: 98
  of ReadKind.Report, ReadKind.Preimage, ReadKind.Bundle: 32
  of ReadKind.Availability, ReadKind.Audit: 34
  of ReadKind.PreimageAnnouncement: 40
  of ReadKind.TicketProxy, ReadKind.TicketDistribution: 789

proc payload*(request: ReadRequest): seq[byte] {.requires: request.ready.} =
  ## Copy only complete admitted payload bytes; no mutable fixed backing array escapes.
  result = newSeq[byte](request.length)
  for index in 0..<request.length:
    result[index] = if request.selector.variable: request.variable[index] else: request.payload[index]

proc decodeReadRequest*(kind: ReadKind, payload: openArray[byte]): ReadResult[ReadRequest] =
  ## Validate exact extents before retaining transport facts; method-specific semantics stay in services.
  if kind in [ReadKind.Guarantee, ReadKind.Assurance, ReadKind.AuditAnnouncement,
      ReadKind.Judgment]:
    if kind == ReadKind.Assurance and payload.len < 97: return readFailure[ReadRequest](
        ReadError.InvalidRequest)
    if kind == ReadKind.Guarantee and payload.len == 0: return readFailure[ReadRequest](
        ReadError.InvalidRequest)
    if payload.len > kind.maximumRequestBytes: return readFailure[ReadRequest](
        ReadError.LimitExceeded)
    var bytes = newSeq[byte](payload.len)
    for index in 0..<payload.len: bytes[index] = payload[index]
    return ReadResult[ReadRequest](status: ReadError.None, completed: ReadRequest(ready: true,
      selector: kind, length: payload.len, variable: bytes))
  if kind.batch:
    if payload.len > kind.segmentKind.maximumPayload: return readFailure[ReadRequest](
        ReadError.LimitExceeded)
    var cursor = initSegmentRequestCursor(kind.segmentKind)
    for octet in payload:
      let reason = cursor.consume(octet)
      if reason == SegmentRequestError.LimitExceeded: return readFailure[ReadRequest](
          ReadError.LimitExceeded)
      if reason != SegmentRequestError.None: return readFailure[ReadRequest](
          ReadError.InvalidRequest)
    if not cursor.complete: return readFailure[ReadRequest](ReadError.InvalidRequest)
    var bytes = newSeq[byte](payload.len)
    for index in 0..<payload.len: bytes[index] = payload[index]
    return ReadResult[ReadRequest](status: ReadError.None, completed: ReadRequest(ready: true,
      selector: kind, length: payload.len, variable: bytes, groups: cursor.groupCount,
      items: cursor.itemCount))
  if payload.len != requestLength(kind): return ReadResult[ReadRequest](
      status: ReadError.InvalidRequest)
  var captured = ReadRequest(ready: true, selector: kind, length: payload.len)
  for index in 0..<payload.len: captured.payload[index] = payload[index]
  ReadResult[ReadRequest](status: ReadError.None, completed: captured)

proc detachedReadRequest*(request: ReadRequest): ReadRequest {.requires: request.valid.} =
  ## CPU capture receives independent variable storage before submission; native callbacks may then retire their own aliases.
  result = ReadRequest(ready: true, selector: request.selector, length: request.length,
    payload: request.payload, groups: request.groups, items: request.items)
  result.variable = newSeq[byte](request.variable.len)
  for index in 0..<request.variable.len: result.variable[index] = request.variable[index]

func payloadLength*(request: ReadRequest): int {.requires: request.valid.} =
  ## Logical request copy admission uses scalar extent before allocating a detached payload view.
  request.length

proc requestBytes*(request: ReadRequest): seq[byte] {.requires: request.valid.} =
  ## Serialize one exact selector/E4/body with a single exact-sized allocation after the parent reserves output credit.
  result = newSeq[byte](request.length+5)
  result[0] = byte(request.selector)
  for index in 0..<4: result[1+index] = byte((uint32(request.length) shr (8*index)) and 255)
  for index in 0..<request.length:
    result[5+index] = if request.selector.variable: request.variable[index] else: request.payload[index]

func itemCount*(request: ReadRequest): int {.requires: request.valid.} =
  ## Validated scalar counts determine exact response message arity without reparsing payloads in callbacks.
  request.items

func sameRequest(left, right: ReadRequest): bool =
  ## Full fixed-array equality prevents foreign/stale work from targeting a different request.
  left.ready and right.ready and left.selector == right.selector and left.length == right.length and
      left.payload == right.payload and left.variable == right.variable

func request*(reply: ReadReply): ReadRequest =
  ## A frozen reply retains its original request binding; defaults return an invalid request, never an initialized success.
  reply.request

func matches*(reply: ReadReply, request: ReadRequest): bool =
  ## All exact method and payload facts must match before a retained detached reply can serve another physical stream.
  sameRequest(reply.request, request)

proc forRequest*(reply: ReadReply, request: ReadRequest): ReadResult[ReadReply] =
  ## Reuse only an already frozen complete reply under its exact admitted binding; no caller bytes construct a successful prefix.
  if not reply.matches(request): return readFailure[ReadReply](ReadError.InvalidRequest)
  ReadResult[ReadReply](status: ReadError.None, completed: reply)

func replyMessageCount*(request: ReadRequest): int {.requires: request.valid.} =
  ## CE142 acknowledges with FIN alone; ordinary content replies use one message and CE129 uses two.
  if request.selector == ReadKind.ProvenSegmentShards: request.items+1
  elif request.selector == ReadKind.Segments: 2
  elif request.selector == ReadKind.Availability: 3
  elif request.selector in [ReadKind.State, ReadKind.Audit]: 2
  elif request.selector in [ReadKind.Guarantee, ReadKind.Assurance, ReadKind.AuditAnnouncement,
      ReadKind.Judgment, ReadKind.PreimageAnnouncement, ReadKind.TicketProxy,
          ReadKind.TicketDistribution]: 0
  else: 1

func maximumReplyBytes*(request: ReadRequest): int {.requires: request.valid.} =
  ## Large original bundles and all-row distributions have their own hard ceiling; existing reads retain their prior bound.
  if request.kind in [ReadKind.SegmentShards, ReadKind.ProvenSegmentShards]: 32*1024*1024
  elif request.kind in [ReadKind.Availability, ReadKind.Bundle, ReadKind.Segments]: 16*1024*1024
  else: MaxReadReplyBytes

func minimumReplyBytes*(request: ReadRequest): uint64 {.requires: request.valid.} =
  ## Framing minima include only actual E4 messages, never a fabricated acknowledgment prefix.
  uint64(request.replyMessageCount*4)

func effect*(reply: ReadReply): ReadEffect =
  ## Only the host's own canonical worker output supplies this non-wire planning hint.
  reply.effect

proc captureReadReply*(request: ReadRequest, wire: openArray[byte],
    effect = ReadEffect.None): ReadResult[ReadReply] =
  ## Freeze only an exact bounded sequence of E4 messages; this grants no state/consensus authority.
  if not request.ready: return ReadResult[ReadReply](status: ReadError.InvalidRequest)
  if wire.len > request.maximumReplyBytes: return ReadResult[ReadReply](
      status: ReadError.LimitExceeded)
  if effect != ReadEffect.None and request.selector != ReadKind.PreimageAnnouncement:
    return ReadResult[ReadReply](status: ReadError.InvalidRequest)
  let count = request.replyMessageCount
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
  ReadResult[ReadReply](status: ReadError.None, completed: ReadReply(request: request, wire: copied,
      effect: effect))

func byteLength*(reply: ReadReply): int =
  ## Inspect frozen wire extent before admitting a host-side output copy against aggregate credit.
  reply.wire.len

proc bytes*(reply: ReadReply): seq[byte] =
  ## Copy the frozen transcript without exporting mutable storage.
  reply.wire

func writtenBytes*(route: ReadRoute): int =
  ## Scalar progress lets the enclosing host enforce inactivity without inspecting or copying output.
  route.offset

func receivedBytes*(route: ReadRoute): int =
  ## Fixed request progress is observable without exposing the partially filled request array.
  route.used

func bufferedBytes*(route: ReadRoute): uint64 =
  ## Declared heap storage is charged immediately, even when a peer withholds the body or FIN.
  if route.selector.variable and route.used >= 5: uint64(route.declared)+5
  else: uint64(route.used)

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
  if kind.batch: route.cursor = initSegmentRequestCursor(kind.segmentKind)
  wantRead(stream, 1)
  ReadError.None

proc takeRequest*(route: var ReadRoute): ReadResult[ReadRequest] =
  ## Exactly one host job is released only after the complete request and FIN.
  if not route.pending or route.taken or route.failed: return ReadResult[ReadRequest](
      status: ReadError.Unavailable)
  route.taken = true
  ReadResult[ReadRequest](status: ReadError.None, completed: route.captured)

proc selectedKind*(route: ReadRoute): ReadKind {.requires: route.stream != NativeStream(nil).} =
  ## A bound native route exposes its fixed selector without consuming an incomplete or already claimed request.
  route.selector

proc deferRequest*(route: var ReadRoute): bool =
  ## Return a complete claim to admission; responding, reset and retired routes cannot be re-admitted.
  if route.stream == NativeStream(nil) or route.failed or not route.pending or not route.taken:
    return false
  route.taken = false
  true

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

proc event*(route: var ReadRoute, stream: NativeStream, event: cint,
    inputBudget = ByteLimit(32*1024*1024)) =
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
    var buffer = default(array[4096, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return
    if count < 0 or count > int64(buffer.len):
      route.reject()
      return
    if count > 0:
      for index in 0..<int(count):
        # Validate declared storage before allocation; each byte advances only fixed scalar grammar state.
        let octet = buffer[index]
        if uint64(route.used) >= uint64(inputBudget):
          route.reject()
          return
        if route.used < 5:
          route.request[route.used] = octet
          inc route.used
          if route.used == 5:
            if route.request[0] != byte(route.selector):
              route.reject()
              return
            var length = 0'u64
            for position in 0..<4: length = length or (uint64(route.request[position+1]) shl (8*position))
            if route.selector.variable:
              if length > uint64(route.selector.maximumRequestBytes) or length+5 > uint64(inputBudget):
                route.reject()
                return
              if (route.selector == ReadKind.Guarantee and length == 0) or
                  (route.selector == ReadKind.Assurance and length < 97):
                route.reject()
                return
              route.declared = int(length)
              route.variable = newSeq[byte](route.declared)
            else:
              if length != uint64(requestLength(route.selector)):
                route.reject()
                return
              route.declared = int(length)
        else:
          if route.used-5 >= route.declared:
            route.reject()
            return
          if route.selector.variable:
            route.variable[route.used-5] = octet
            if route.selector.batch and route.cursor.consume(octet) != SegmentRequestError.None:
              route.reject()
              return
          else: route.request[route.used] = octet
          inc route.used
      return # Even exact complete bytes wait for request FIN before host admission.
    if route.used < 5 or route.used-5 != route.declared:
      route.reject()
      return
    if route.selector.variable:
      if route.selector.batch and not route.cursor.complete:
        route.reject()
        return
      route.captured = ReadRequest(ready: true, selector: route.selector, length: route.declared,
        variable: move(route.variable), groups: route.cursor.groupCount,
            items: route.cursor.itemCount)
    else:
      let decoded = decodeReadRequest(route.selector, route.request.toOpenArray(5, route.used-1))
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
