# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical CE128 selection and a borrowed-stream responder. Chain selection runs outside native
## callbacks; the route owns only bounded request/reply bytes, never a canonical state graph.

import ../chain/[genesis, provider]
import ../quic/transport
import ./read_stream

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
    frame: ReadRoute
    request: ReadRequest
    query: BlockQuery

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
  ## Parent observes only the shared route's borrowed handle.
  route.frame.handle

proc bindStream*(route: var BlockRequestRoute, stream: NativeStream): BlockServiceError =
  ## Bind the CE128 adapter to the shared fixed-request wire lifecycle.
  let bound = route.frame.bindReadStream(stream, ReadKind.Blocks)
  case bound
  of ReadError.None: BlockServiceError.None
  of ReadError.Busy: BlockServiceError.Busy
  else: BlockServiceError.InvalidStream # Shared failures confer no native authority.

proc takeRequest*(route: var BlockRequestRoute): BlockServiceResult[BlockQuery] =
  ## Decode method semantics only after the shared exact-frame/FIN gate.
  let incoming = route.frame.takeRequest()
  if incoming.error != ReadError.None: return BlockServiceResult[BlockQuery](
      status: BlockServiceError.Unavailable)
  let decoded = decodeBlockQuery(incoming.value.payload)
  if decoded.error != BlockServiceError.None:
    route.frame.reject()
    return decoded # Invalid directions reset before canonical work is released.
  route.request = incoming.value
  route.query = decoded.value
  decoded

proc respond*(route: var BlockRequestRoute, reply: BlockReply): BlockServiceError =
  ## Preserve the CE128 request binding while delegating bounded write/FIN ownership.
  if route.frame.handle == NativeStream(nil) or not route.request.valid: return BlockServiceError.InvalidStream
  if not sameQuery(route.query, reply.query): return BlockServiceError.InvalidRequest
  let frozen = captureReadReply(route.request, reply.wire)
  if frozen.error != ReadError.None: return BlockServiceError.InvalidRequest
  let sent = route.frame.respond(frozen.value)
  if sent == ReadError.None: BlockServiceError.None else: BlockServiceError.InvalidStream

proc reject*(route: var BlockRequestRoute) =
  ## Host reports canonical unavailability without a misleading empty successful reply.
  route.frame.reject()

proc event*(route: var BlockRequestRoute, stream: NativeStream, event: cint) =
  ## Shared framing owns native retirement; adapter facts are revoked on terminal events too.
  if stream == NativeStream(nil) or route.frame.handle !=
      stream: return # Unrelated stale events cannot revoke this adapter.
  route.frame.event(stream, event)
  if event == 3 or event == 4:
    route.query = default(BlockQuery)
    route.request = default(ReadRequest) # A retired stream's async response cannot authorize a replacement.
