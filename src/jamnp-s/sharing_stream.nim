# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CE134 copies two bounded messages and exact FIN, then writes only a host-supplied fixed96-byte response.
## No canonical state, private key, cryptography or guest execution enters these native callbacks.
import ./[sharing_wire, read_stream]
import ../quic/transport
import ../codec/bounded

type
  SharingStreamResult*[T] = object ## Success contains only complete untrusted transport bytes.
    case status: ReadError
    of None: completed: T
    else: discard                  # Refused/default requests retain no partial payload.
  SharingRoute* = object ## The parent owns physical retirement; this route only borrows its native stream.
    stream: NativeStream
    configured, taken, receivedFin, responding, sentFin: bool
    failure: ReadError
    messages: array[2, seq[byte]]
    prefix: array[4, byte]
    index, prefixUsed, remaining, offset: int
    received: uint64
    output: array[SharingResponseBytes+4, byte]
func error*[T](outcome: SharingStreamResult[T]): ReadError =
  ## Inspect a refusal without writable status.
  outcome.status
func value*[T](outcome: SharingStreamResult[T]): T {.requires: outcome.status == ReadError.None.} =
  ## Only two complete messages and exact request FIN can escape.
  outcome.completed
func failed*(route: SharingRoute): bool =
  ## Reset/close failures revoke host response authority.
  route.configured and route.failure != ReadError.None
func receivedBytes*(route: SharingRoute): uint64 =
  ## All prefix/payload credit remains charged through native retirement, including after host capture.
  route.received
func writtenBytes*(route: SharingRoute): int =
  ## Detached progress drives parent activity clocks without source-owner access.
  route.offset
func requestReady*(route: SharingRoute): bool =
  ## No task can precede exact request FIN or be claimed twice.
  route.configured and not route.failed and route.receivedFin and not route.taken
proc refuse(route: var SharingRoute, reason: ReadError) =
  ## Parent keeps buffers/physical quota until the actual native close callback.
  route.failure = reason
  if route.stream != NativeStream(nil):
    wantRead(route.stream, 0)
    wantWrite(route.stream, 0)
    streamAbort(route.stream)
proc bindSharingStream*(route: var SharingRoute, stream: NativeStream): ReadError =
  ## The authenticated parent has consumed CE134 and admitted an incoming bidirectional validator stream.
  if route.configured or stream == NativeStream(nil): return ReadError.InvalidStream
  if (uint64(stream.streamId) and 2) != 0: return ReadError.InvalidStream
  route = SharingRoute(stream: stream, configured: true, failure: ReadError.None)
  wantRead(stream, 1)
  wantWrite(stream, 0)
  ReadError.None
proc takeRequest*(route: var SharingRoute): SharingStreamResult[SharedWorkRequest] =
  ## Copy bounded independent bytes outside the callback; later native close cannot invalidate CPU inputs.
  if not route.requestReady: return SharingStreamResult[SharedWorkRequest](
      status: ReadError.Unavailable)
  let captured = captureSharedWork(route.messages[0], route.messages[1])
  if captured.error == SharingWireError.LimitExceeded:
    return SharingStreamResult[SharedWorkRequest](status: ReadError.LimitExceeded)
  if captured.error != SharingWireError.None:
    return SharingStreamResult[SharedWorkRequest](status: ReadError.InvalidRequest)
  route.taken = true
  SharingStreamResult[SharedWorkRequest](status: ReadError.None, completed: captured.value)
proc respond*(route: var SharingRoute, response: array[SharingResponseBytes, byte]): ReadError =
  ## Only the external managed-result controller supplies bytes; a reset/duplicate response cannot succeed.
  if not route.configured or route.failed or not route.taken or not route.receivedFin or
      route.responding or route.stream == NativeStream(nil): return ReadError.InvalidStream
  route.output[0] = byte(SharingResponseBytes)
  for index in 0..<SharingResponseBytes: route.output[4+index] = response[index]
  route.responding = true
  wantWrite(route.stream, 1)
  ReadError.None
proc event*(route: var SharingRoute, stream: NativeStream, event: cint, budget: ByteLimit) =
  ## At most one4096-byte read or one100-byte write per callback; semantic processing is never invoked here.
  if not route.configured or route.stream != stream: return
  if event == 3:
    route.stream = NativeStream(nil)
    if not route.sentFin: route.failure = ReadError.InvalidStream
    return # The parent now retires the physical frame.
  if event == 4:
    route.failure = ReadError.InvalidStream
    wantRead(stream, 0)
    wantWrite(stream, 0)
    return # Directional reset revokes a pending CPU response immediately.
  if route.failed: return
  if event == 2:
    if not route.responding or route.sentFin: return
    let remaining = route.output.len-route.offset
    let written = streamWrite(stream, addr route.output[route.offset], csize_t(remaining))
    if written == -2: return
    if written < 0 or written > int64(remaining):
      route.refuse(ReadError.InvalidStream)
      return
    route.offset += int(written)
    if route.offset == route.output.len:
      route.sentFin = true
      wantWrite(stream, 0)
      discard streamFlush(stream)
      streamFin(stream)
    return # No source or signer alias survives in this output buffer.
  if event != 1 or route.receivedFin: return
  let awaitingFin = route.index == 2
  var maximum = 1
  if not awaitingFin:
    # Prefixes are complete before declared body storage; shared input credit precedes every byte copy.
    maximum = if route.prefixUsed < 4: 4-route.prefixUsed else: min(4096, route.remaining)
    maximum = int(min(uint64(maximum), uint64(budget)))
    if maximum == 0:
      route.refuse(ReadError.LimitExceeded)
      return
  var bytes = default(array[4096, byte])
  let read = streamRead(stream, addr bytes[0], csize_t(maximum))
  if read == -2: return
  if read < 0 or read > int64(maximum):
    route.refuse(ReadError.InvalidStream)
    return
  if read == 0:
    if not awaitingFin:
      route.refuse(ReadError.InvalidRequest)
      return
    route.receivedFin = true
    wantRead(stream, 0)
    readDone(stream)
    return # Only exact FIN makes the whole untrusted bundle claimable.
  if awaitingFin:
    route.refuse(ReadError.InvalidRequest)
    return # A third message or even one suffix byte is not another valid request.
  route.received += uint64(read)
  if route.prefixUsed < 4:
    # The bounded read stops exactly at the little-endian E4 prefix extent.
    for index in 0..<int(read): route.prefix[route.prefixUsed+index] = bytes[index]
    route.prefixUsed += int(read)
    if route.prefixUsed == 4:
      var length = 0'u64
      for index in 0..<4: length = length or (uint64(route.prefix[index]) shl (8*index))
      let lower = if route.index == 0: 5'u64 else: 1'u64
      let upper = if route.index == 0: uint64(MaxSharingHeaderBytes) else: uint64(MaxSharingBundleBytes)
      if length < lower or length > upper:
        route.refuse(ReadError.InvalidRequest)
        return
      route.remaining = int(length) # Both protocol ceilings fit the native indexing domain.
  else:
    # Declared remaining bytes and shared credit bound each append and subsequent subtraction.
    for index in 0..<int(read): route.messages[route.index].add(bytes[index])
    route.remaining -= int(read)
    if route.remaining == 0:
      inc route.index
      route.prefixUsed = 0
      route.prefix = default(array[4, byte])
