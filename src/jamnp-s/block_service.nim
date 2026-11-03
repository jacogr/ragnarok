# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical CE128 selection and a borrowed-stream responder. Chain selection runs outside native
## callbacks; the route owns only bounded request/reply bytes, never a canonical state graph.
import ../chain/[genesis, provider]
import ../quic/transport

type
  BlockServiceError* {.pure.} = enum ## Failures carry no partial request or response.
    Uninitialized, None, InvalidRequest, Unavailable, LimitExceeded, InvalidStream, Busy
  BlockDirection* {.pure.} = enum ## Pinned CE128 direction bytes, without alternate encodings.
    Ascending, Descending
  BlockQuery* = object ## Only exact wire decoding constructs an admitted request.
    hash: BlockHash
    direction: BlockDirection
    maximum: uint32
    valid: bool
  BlockReply* = object ## Frozen response retains wire bytes and the exact originating request.
    query: BlockQuery
    wire: seq[byte]
  BlockServiceResult*[T] = object ## Default and failure variants contain reasons only.
    case status: BlockServiceError
    of None: completed: T
    else: discard                 # No partial canonical result escapes rejection.
  BlockRequestRoute* = object ## Parent owns native close and fixed routing capacity; this route borrows its stream.
    stream: NativeStream
    request: array[42, byte]
    used, offset: int
    query: BlockQuery
    output: seq[byte]
    pending, taken, writing, failed: bool

const MaxBlockReplyBytes* = 8*1024*1024 ## Hard response ceiling includes the E4 header.
const MaxBlockReplyCount* = 64 ## A request may receive fewer than its untrusted u32 maximum.

func error*[T](outcome: BlockServiceResult[T]): BlockServiceError =
  ## Inspect the private result discriminator.
  outcome.status
func value*[T](outcome: BlockServiceResult[T]): T {.requires: outcome.status ==
    BlockServiceError.None.} =
  ## Extract only a successfully completed owned value.
  outcome.completed
func sameQuery(left, right: BlockQuery): bool =
  ## Async response matching compares all request facts, not merely the selector or anchor.
  left.valid and right.valid and left.direction == right.direction and left.maximum ==
      right.maximum and
    array[32, byte](left.hash) == array[32, byte](right.hash)
proc decodeBlockQuery*(wire: openArray[byte]): BlockServiceResult[BlockQuery] =
  ## Decode only the 37-byte CE128 message payload, after the enclosing E4/FIN boundary.
  if wire.len != 37 or wire[32] > 1:
    return BlockServiceResult[BlockQuery](status: BlockServiceError.InvalidRequest)
  var hash = default(array[32, byte])
  var maximum = 0'u32
  for index in 0..<32: hash[index] = wire[index] # Exact extent precedes all indexing.
  for index in 0..<4: maximum = maximum or (uint32(wire[33+index]) shl (8*index))
  BlockServiceResult[BlockQuery](status: BlockServiceError.None, completed: BlockQuery(
    hash: BlockHash(hash), direction: BlockDirection(wire[32]), maximum: maximum, valid: true))
func child(view: ChainView, hash: BlockHash): BlockSnapshotResult =
  ## A retained child's sealed parent commitment remains useful after its parent is evicted.
  for index in 0..<view.retainedCount:
    let saved = view.retainedBlockAt(RetainedBlockIndex(index))
    if saved.error == GenesisError.None and array[32, byte](saved.value.parentHash) == array[32,
        byte](hash):
      return saved # Only the caller-selected canonical linear history supplies candidates.
  unavailableGenesis()
proc serveBlocks*(view: ChainView, query: BlockQuery): BlockServiceResult[BlockReply] =
  ## Run under the caller's canonical read lease; retain only a bounded complete-block wire reply.
  if not query.valid:
    return BlockServiceResult[BlockReply](status: BlockServiceError.InvalidRequest)
  let anchor = view.blockAt(query.hash)
  var selected = if query.direction == BlockDirection.Ascending: view.child(query.hash) else: anchor
  if anchor.error != GenesisError.None and selected.error != GenesisError.None:
    return BlockServiceResult[BlockReply](status: BlockServiceError.Unavailable) # Unknown or incompatible forks never look like a known empty tip.
  var output = newSeq[byte](4)
  var count = 0
  while selected.error == GenesisError.None and count < MaxBlockReplyCount and uint32(count) < query.maximum:
    let snapshot = selected.value
    if not snapshot.hasBlockBody:
      if count == 0: return BlockServiceResult[BlockReply](status: BlockServiceError.Unavailable)
      break # Pruned bodies terminate an available prefix; never fabricate a block from its header.
    let length = snapshot.blockBodyLength
    if length > MaxBlockReplyBytes-output.len:
      if count == 0: return BlockServiceResult[BlockReply](status: BlockServiceError.LimitExceeded)
      break # Check before the body copy and every output allocation.
    let body = snapshot.blockBody
    for octet in body: output.add(octet) # Bare concatenation has no per-block count or length prefixes.
    inc count
    selected = if query.direction == BlockDirection.Ascending: view.child(
        snapshot.blockHash) else: view.blockAt(snapshot.parentHash)
  let length = uint32(output.len-4)
  for index in 0..<4: output[index] = byte((length shr (8*index)) and 255)
  BlockServiceResult[BlockReply](status: BlockServiceError.None, completed: BlockReply(query: query, wire: output))
proc bytes*(reply: BlockReply): seq[byte] =
  ## Return an independently owned wire copy without exposing mutable frozen storage.
  reply.wire
func handle*(route: BlockRequestRoute): NativeStream =
  ## Parent uses the borrowed pointer only while the native stream remains alive.
  route.stream
proc refuse(route: var BlockRequestRoute) =
  ## Poison the route and revoke a pending job before stopping only this stream.
  route.failed = true
  route.pending = false
  route.output = @[]
  if route.stream != NativeStream(nil): streamAbort(route.stream)
proc bindStream*(route: var BlockRequestRoute, stream: NativeStream): BlockServiceError =
  ## Bind an accepted remote bidirectional stream before its selector has been consumed.
  if stream == NativeStream(nil): return BlockServiceError.InvalidStream
  if (uint64(stream.streamId) and 2) != 0: return BlockServiceError.InvalidStream # CE requests require both directions.
  if route.stream != NativeStream(nil): return BlockServiceError.Busy
  route = BlockRequestRoute(stream: stream)
  wantRead(stream, 1)
  BlockServiceError.None
proc takeRequest*(route: var BlockRequestRoute): BlockServiceResult[BlockQuery] =
  ## Host drains a completed request outside callbacks; no work is released before request FIN.
  if not route.pending or route.taken or route.failed:
    return BlockServiceResult[BlockQuery](status: BlockServiceError.Unavailable)
  route.taken = true
  BlockServiceResult[BlockQuery](status: BlockServiceError.None, completed: route.query)
proc respond*(route: var BlockRequestRoute, reply: BlockReply): BlockServiceError =
  ## Stale/foreign replies cannot authorize output on another pending request.
  if route.stream == NativeStream(nil) or route.failed or not route.pending or not route.taken:
    return BlockServiceError.InvalidStream
  if not sameQuery(route.query, reply.query) or reply.wire.len < 4 or reply.wire.len > MaxBlockReplyBytes:
    return BlockServiceError.InvalidRequest
  route.output = reply.wire
  route.pending = false
  route.writing = true
  wantWrite(route.stream, 1)
  BlockServiceError.None
proc reject*(route: var BlockRequestRoute) =
  ## Host reports unavailable/busy canonical work without sending a misleading empty response.
  route.refuse()
proc event*(route: var BlockRequestRoute, stream: NativeStream, event: cint) =
  ## Exactly one bounded native read/write per callback; parent retains this slot until close.
  if route.stream != stream or stream == NativeStream(nil): return
  if event == 3:
    route = default(BlockRequestRoute)
    return # Native close revokes pending work and releases all byte owners.
  if event == 4:
    route.failed = true
    route.pending = false
    route.output = @[]
    wantRead(stream, 0)
    wantWrite(stream, 0)
    return # Reset is terminal even if the host has not drained its work queue.
  if route.failed: return
  case event
  of 1:
    var buffer = default(array[43, byte])
    let read = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if read == -2: return
    if read < 0 or read > int64(route.request.len-route.used):
      route.refuse()
      return # One extra byte, duplicate messages or a transport error poisons the request.
    if read > 0:
      for index in 0..<int(read): route.request[route.used+index] = buffer[index]
      route.used += int(read)
      return # Even a full request waits for the following native FIN observation.
    if route.used != 42 or route.request[0] != 128 or route.request[1] != 37 or
        route.request[2] != 0 or route.request[3] != 0 or route.request[4] != 0:
      route.refuse()
      return # Exact selector, E4 extent, message count and request FIN are mandatory.
    let decoded = decodeBlockQuery(route.request.toOpenArray(5, 41))
    if decoded.error != BlockServiceError.None:
      route.refuse()
      return
    route.query = decoded.value
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
        route.refuse()
        return # A failed write never advances or repeats an unaccepted suffix.
      route.offset += int(written)
    if route.offset == route.output.len:
      route.writing = false
      wantWrite(stream, 0)
      discard streamFlush(stream)
      streamFin(stream) # Output ownership lasts through actual native close, not just queued FIN.
  else: discard # Open is handled by the fixed-capacity parent before binding this route.
