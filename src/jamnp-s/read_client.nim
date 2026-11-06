# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded CE128/129/143 client framing. Complete replies remain untrusted until host semantic/cryptographic validation.
import ./read_stream
import ../quic/transport
import ../codec/bounded

type
  UntrustedReadReply* = object ## Private complete bytes bind to the exact fixed request, without granting state authority.
    ready: bool
    request: ReadRequest
    wire: seq[byte]
  ReadClientResult* = object ## Only exact complete success carries an immutable untrusted transcript.
    case status: ReadError
    of None: completed: UntrustedReadReply
    else: discard # Partial/default failures expose only a reason.
  ReadClientRoute* = object ## One borrowed native stream and bounded detached buffers survive through host collection.
    stream: NativeStream
    configured, sentFin, receivedFin, taken: bool
    failure: ReadError
    request: ReadRequest
    output, input: seq[byte]
    offset, prefixUsed, messages: int
    prefix: array[4, byte]
    remaining, maximum: uint64
func error*(outcome: ReadClientResult): ReadError =
  ## Read only the private completion discriminator.
  outcome.status
func value*(outcome: ReadClientResult): UntrustedReadReply {.requires: outcome.status ==
    ReadError.None.} =
  ## Successful framing still grants no semantic or cryptographic state authority.
  outcome.completed
func clientFailure*(reason: ReadError): ReadClientResult {.requires: reason != ReadError.None.} =
  ## Parent lifecycle refusals cannot manufacture a successful response owner.
  ReadClientResult(status: reason)
func valid*(reply: UntrustedReadReply): bool =
  ## Default replies carry no completed transcript or request binding.
  reply.ready
func request*(reply: UntrustedReadReply): ReadRequest {.requires: reply.ready.} =
  ## Fixed request facts identify what the host must validate before using these untrusted bytes.
  reply.request
proc bytes*(reply: UntrustedReadReply): seq[byte] {.requires: reply.ready.} =
  ## Detached copies cannot mutate the privately retained transcript.
  result = @[]
  for octet in reply.wire: result.add(octet)
func expectedMessages(route: ReadClientRoute): int =
  ## CE129 has two E4 messages, CE142 has none, and ordinary content replies have one.
  route.request.replyMessageCount
func ready*(route: ReadClientRoute): bool =
  ## Both completed directions and exact response FIN precede host-visible success, even after native close.
  route.configured and route.failure == ReadError.None and route.sentFin and route.receivedFin and
      not route.taken
func failed*(route: ReadClientRoute): bool =
  ## Only configured failed routes can revoke a pending task.
  route.configured and route.failure != ReadError.None
func error*(route: ReadClientRoute): ReadError =
  ## Error tags expose no response prefix.
  route.failure
func bufferedBytes*(route: ReadClientRoute): int =
  ## Parent accounts the entire incrementally owned wire, including E4 prefixes.
  route.input.len
func writtenBytes*(route: ReadClientRoute): int =
  ## Request output progress is scalar and independent of canonical source ownership.
  route.offset
proc configure*(route: var ReadClientRoute, request: ReadRequest,
    maximum = ByteLimit(MaxReadReplyBytes)): ReadError =
  ## Reserve a valid fixed request and hard-bounded reply policy before requesting any native open.
  if route.configured: return ReadError.Busy
  if not request.valid: return ReadError.InvalidRequest
  let minimum = request.minimumReplyBytes
  if uint64(maximum) < minimum or uint64(maximum) > uint64(
      request.maximumReplyBytes): return ReadError.LimitExceeded
  route = ReadClientRoute(configured: true, failure: ReadError.None,
    request: detachedReadRequest(request), maximum: uint64(maximum), output: request.requestBytes)
  ReadError.None
proc bindStream*(route: var ReadClientRoute, stream: NativeStream): ReadError =
  ## Only the authenticated parent supplies a locally initiated bidirectional stream for this reserved intent.
  if not route.configured or route.failed or route.taken or route.sentFin or route.receivedFin or
      stream == NativeStream(nil): return ReadError.InvalidStream
  if route.stream != NativeStream(nil): return ReadError.Busy
  if (uint64(stream.streamId) and 2) != 0: return ReadError.InvalidStream
  route.stream = stream
  wantRead(stream, 1)
  wantWrite(stream, 1)
  ReadError.None
proc refuse(route: var ReadClientRoute, reason: ReadError) =
  ## Reject this transcript only; the parent retains byte/physical charges until real retirement.
  route.failure = reason
  if route.stream != NativeStream(nil):
    wantRead(route.stream, 0)
    wantWrite(route.stream, 0)
    streamAbort(route.stream)
proc feed(route: var ReadClientRoute, input: openArray[byte]): ReadError =
  ## Parse one bounded native chunk; declared lengths are checked before body growth or narrowing.
  for octet in input:
    if route.messages == route.expectedMessages: return ReadError.InvalidRequest
    if uint64(route.input.len) >= route.maximum: return ReadError.LimitExceeded
    route.input.add(octet)
    if route.remaining > 0:
      dec route.remaining
      if route.remaining == 0: inc route.messages
    else:
      route.prefix[route.prefixUsed] = octet
      inc route.prefixUsed
      if route.prefixUsed == 4:
        var length = 0'u64
        for index in 0..<4: length = length or (uint64(route.prefix[index]) shl (8*index))
        if length > route.maximum-uint64(route.input.len): return ReadError.LimitExceeded
        route.prefixUsed = 0
        route.remaining = length
        if length == 0: inc route.messages # Canonical empty block/preimage replies still require the final native FIN.
  ReadError.None
proc event*(route: var ReadClientRoute, stream: NativeStream, kind: cint,
    inputBudget = ByteLimit(MaxReadReplyBytes)) =
  ## At most4096 bytes of I/O per callback; no state graph, proof verification or adoption work occurs here.
  if stream == NativeStream(nil) or route.stream != stream: return
  if kind == 3:
    route.stream = NativeStream(nil)
    route.output = @[]
    if route.failure == ReadError.None and (not route.sentFin or
        not route.receivedFin): route.failure = ReadError.InvalidStream
    return # Complete privately owned bytes survive native close until their host takes/cancels them.
  if kind == 4:
    route.failure = ReadError.InvalidStream
    wantRead(stream, 0)
    wantWrite(stream, 0)
    return # Parent retires remaining application directions after this directional reset.
  if route.failed: return
  case kind
  of 1:
    var buffer = default(array[4096, byte])
    let awaitingFin = route.messages == route.expectedMessages and route.remaining == 0 and
        route.prefixUsed == 0
    let maximum = if awaitingFin: 1 else: int(min(4096'u64, uint64(inputBudget)))
    if maximum == 0:
      route.refuse(ReadError.LimitExceeded)
      return # No uncharged body byte may be retained when the parent's shared credit is exhausted.
    let amount = streamRead(stream, addr buffer[0], csize_t(maximum))
    if amount == -2: return
    if amount < 0 or amount > int64(maximum):
      route.refuse(ReadError.InvalidStream)
      return
    if amount == 0:
      if not awaitingFin:
        route.refuse(ReadError.InvalidRequest)
        return
      route.receivedFin = true
      readDone(stream)
      wantRead(stream, 0)
    else:
      let parsed = route.feed(buffer.toOpenArray(0, int(amount)-1))
      if parsed != ReadError.None: route.refuse(parsed)
  of 2:
    if route.offset < route.output.len:
      let amount = streamWrite(stream, addr route.output[route.offset], csize_t(min(4096,
          route.output.len-route.offset)))
      if amount == -2 or amount == 0: return # Public LSQUIC zero-progress writes are ordinary backpressure.
      if amount < 0 or amount > int64(route.output.len-route.offset):
        route.refuse(ReadError.InvalidStream)
        return
      route.offset += int(amount)
    if route.offset == route.output.len and not route.sentFin:
      route.sentFin = true
      route.output = @[]
      wantWrite(stream, 0)
      discard streamFlush(stream)
      streamFin(stream) # One exact fixed request ends before any reply can be collected.
  else: discard # No other callback kind establishes protocol progress.
proc take*(route: var ReadClientRoute): ReadClientResult =
  ## Transfer a complete frozen transcript; failures and partial responses expose no prefix.
  if route.failed: return clientFailure(route.failure)
  if not route.ready: return clientFailure(ReadError.Unavailable)
  let captured = UntrustedReadReply(ready: true, request: route.request, wire: route.input)
  route.input = @[]
  route.taken = true
  ReadClientResult(status: ReadError.None, completed: captured)
