# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-free CE134 client framing sends two bounded messages and accepts exactly one96-byte response plus FIN.
## Native callbacks perform bounded I/O only; report-hash/signature verification belongs to the managed worker.

import std/assertions
import ./[sharing_wire, read_stream]
import ../quic/transport
import ../codec/bounded

type
  UntrustedSharingReply* = object ## Fixed complete bytes confer no credential or report authority before managed verification.
    ready: bool
    response: array[SharingResponseBytes, byte]
  SharingClientResult* = object ## Failure/default outcomes contain no accepted response prefix.
    case status: ReadError
    of None: completed: UntrustedSharingReply
    else: discard               # Only exact request/reply FIN completion exposes bytes.
  SharingClientRoute* = object ## The native parent owns retirement and reservations; this route only borrows its stream.
    configured, sentFin, receivedFin, taken: bool
    stream: NativeStream
    failure: ReadError
    output: seq[byte]
    offset, used: int
    input: array[SharingResponseBytes+4, byte]

func error*(outcome: SharingClientResult): ReadError =
  ## Read refusal without writable discriminator access.
  outcome.status

func value*(outcome: SharingClientResult): UntrustedSharingReply {.requires: outcome.status ==
    ReadError.None.} =
  ## Framing success grants only complete untrusted bytes.
  outcome.completed

func sharingClientFailure*(reason: ReadError): SharingClientResult =
  ## The parent can return a reason but cannot manufacture a completed reply.
  SharingClientResult(status: reason)

func valid*(reply: UntrustedSharingReply): bool =
  ## A default fixed array is never an implicit completed response.
  reply.ready

func bytes*(reply: UntrustedSharingReply): array[SharingResponseBytes,
    byte] {.requires: reply.ready.} =
  ## Return independent fixed bytes with no native or canonical owner alias.
  reply.response

func failed*(route: SharingClientRoute): bool =
  ## Native reset/error revokes host extraction immediately.
  route.configured and route.failure != ReadError.None

func ready*(route: SharingClientRoute): bool =
  ## Both exact FINs and the one complete fixed response precede extraction, including after native close.
  route.configured and not route.failed and route.sentFin and route.receivedFin and not route.taken

func bufferedBytes*(route: SharingClientRoute): int =
  ## Prefix and body credit remains charged until host collection or physical retirement.
  route.used

func writtenBytes*(route: SharingClientRoute): int =
  ## Output progress refreshes scalar parent deadlines only.
  route.offset

proc writeMessage(output: var seq[byte], cursor: var int, message: openArray[byte]) =
  ## Caller-owned independent buffers have already passed complete-size preflight; subtraction guards every prefix/copy extent.
  assert cursor >= 0 and cursor <= output.len
  assert output.len-cursor >= 4 and message.len <= output.len-cursor-4
  let length = uint32(message.len)
  for octet in 0..<4: output[cursor+octet] = byte((length shr (8*octet)) and 255)
  cursor += 4
  for octet in message:
    output[cursor] = octet
    inc cursor

proc configureSharing*(route: var SharingClientRoute, request: SharedWorkRequest): ReadError =
  ## The parent reserves the complete output before calling; independent bounded copies contain no canonical state.
  if route.configured: return ReadError.Busy
  let sizes = request.sharingInfo
  if sizes.error != SharingWireError.None: return ReadError.InvalidRequest
  let first = request.firstMessage
  let body = request.bundleMessage
  var output = newSeq[byte](9+sizes.value.headerBytes+sizes.value.bundleBytes)
  output[0] = 134
  var cursor = 1
  writeMessage(output, cursor, first)
  writeMessage(output, cursor, body)
  route = SharingClientRoute(configured: true, failure: ReadError.None, output: output)
  ReadError.None

proc bindSharingClient*(route: var SharingClientRoute, stream: NativeStream): ReadError =
  ## One serialized locally opened bidirectional stream must fulfill the pre-reserved intent.
  if not route.configured or route.failed or route.taken or route.sentFin or route.receivedFin:
    return ReadError.InvalidStream
  if stream == NativeStream(nil) or (uint64(stream.streamId) and 2) !=
      0: return ReadError.InvalidStream
  if route.stream != NativeStream(nil): return ReadError.Busy
  route.stream = stream
  wantRead(stream, 1)
  wantWrite(stream, 1)
  ReadError.None

proc refuse(route: var SharingClientRoute, reason: ReadError) =
  ## The parent retains physical quota and bytes through the eventual native close callback.
  route.failure = reason
  if route.stream != NativeStream(nil):
    wantRead(route.stream, 0)
    wantWrite(route.stream, 0)
    streamAbort(route.stream)

proc event*(route: var SharingClientRoute, stream: NativeStream, kind: cint, budget: ByteLimit) =
  ## One4096-byte write or at most100-byte read per callback; no hash, signature, state or guest work occurs here.
  if stream == NativeStream(nil) or route.stream != stream: return
  if kind == 3:
    route.stream = NativeStream(nil)
    route.output = @[]
    if route.failure == ReadError.None and (not route.sentFin or not route.receivedFin):
      route.failure = ReadError.InvalidStream
    return # Complete fixed reply survives physical close for exact host extraction.
  if kind == 4:
    route.failure = ReadError.InvalidStream
    wantRead(stream, 0)
    wantWrite(stream, 0)
    return # Parent explicitly retires its remaining directions after a directional reset.
  if route.failed: return
  if kind == 2:
    if route.sentFin: return
    let maximum = min(4096, route.output.len-route.offset)
    let written = streamWrite(stream, addr route.output[route.offset], csize_t(maximum))
    if written == -2 or written == 0: return # LSQUIC write_avail may be zero until transport credit advances.
    if written < 0 or written > int64(maximum):
      route.refuse(ReadError.InvalidStream)
      return
    route.offset += int(written)
    if route.offset == route.output.len:
      route.sentFin = true
      route.output = @[]
      wantWrite(stream, 0)
      discard streamFlush(stream)
      streamFin(stream)
    return # Output reservations remain charged by the parent even after this private buffer retires.
  if kind != 1 or route.receivedFin: return
  let awaitingFin = route.used == route.input.len
  let maximum = if awaitingFin: 1 else: int(min(uint64(route.input.len-route.used), uint64(budget)))
  if maximum == 0:
    route.refuse(ReadError.LimitExceeded)
    return
  var input = default(array[SharingResponseBytes+4, byte])
  let read = streamRead(stream, addr input[0], csize_t(maximum))
  if read == -2: return
  if read < 0 or read > int64(maximum):
    route.refuse(ReadError.InvalidStream)
    return
  if read == 0:
    if not awaitingFin:
      route.refuse(ReadError.InvalidRequest)
      return
    route.receivedFin = true
    readDone(stream)
    wantRead(stream, 0)
    return # A complete body without exact FIN is still unavailable to the host.
  if awaitingFin:
    route.refuse(ReadError.InvalidRequest)
    return # Any suffix or second response message refuses rather than completing a prefix.
  for octet in 0..<int(read): route.input[route.used+octet] = input[octet]
  route.used += int(read)
  if route.used >= 4:
    if route.input[0] != byte(SharingResponseBytes) or route.input[1] != 0 or route.input[2] != 0 or
        route.input[3] != 0:
      route.refuse(ReadError.InvalidRequest) # Exact E4(96) is the only legal response prefix; no peer length controls allocation.

proc take*(route: var SharingClientRoute): SharingClientResult =
  ## Only complete framing transfers a fixed immutable transcript, once.
  if route.failed: return sharingClientFailure(route.failure)
  if not route.ready: return sharingClientFailure(ReadError.Unavailable)
  var response = default(array[SharingResponseBytes, byte])
  for octet in 0..<response.len: response[octet] = route.input[4+octet]
  route.taken = true
  SharingClientResult(status: ReadError.None, completed: UntrustedSharingReply(ready: true,
      response: response))
