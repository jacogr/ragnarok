# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded CE133/146 native framing pauses exactly at the authorization boundary and retains no canonical source owner.

import std/assertions
import ./[work_submission, read_stream]
import ../quic/transport
import ../codec/bounded
from ../codec/work/package import MaxBundleBytes

type
  HeaderBytes = ref object ## Complete immutable copied header messages outlive the native stream without retaining its pointer.
    kind: WorkSubmissionKind
    first, package: seq[byte]
  UntrustedWorkHeader* = object ## Structural completion confers no authorization or body-read authority.
    data: nil HeaderBytes
  BodyBytes = ref object ## Complete immutable copied body messages grant no commitment, proof or execution authority.
    kind: WorkSubmissionKind
    extrinsics, segments, proofs: seq[byte]
  UntrustedWorkBody* = object ## Defaults and partial/reset streams cannot produce a body owner.
    data: nil BodyBytes
  WorkStreamResult*[T] = object ## Only complete selected success exposes an immutable transcript.
    case status: ReadError
    of None: completed: T
    else: discard               # Refused/default results contain no byte prefix.
  WorkRoute* = object ## Borrowed native handle and source-free buffers remain stable through actual native close.
    stream: NativeStream
    configured, headerTaken, permitted, receivedFin, bodyTaken, acknowledging, sentFin: bool
    kind: WorkSubmissionKind
    failure: ReadError
    info: WorkSubmissionInfo
    messages: array[5, seq[byte]]
    prefix: array[4, byte]
    prefixUsed, index, remaining: int
    received: uint64

func error*[T](outcome: WorkStreamResult[T]): ReadError =
  ## Inspect framing status before selecting a complete transcript.
  outcome.status

func value*[T](outcome: WorkStreamResult[T]): T {.requires: outcome.status == ReadError.None.} =
  ## Framing success is still untrusted input for the actual Services CPU jobs.
  outcome.completed

func valid*(header: UntrustedWorkHeader): bool =
  ## Default header handles contain no completed transcript.
  header.data != nil

func valid*(body: UntrustedWorkBody): bool =
  ## A body exists only after exact message framing and request FIN.
  body.data != nil

proc copied(input: openArray[byte]): seq[byte] =
  ## Private transcripts never expose a mutable alias to retained native framing storage.
  result = newSeq[byte](input.len)
  for index in 0..<input.len: result[index] = input[index]

proc firstMessage*(header: UntrustedWorkHeader): seq[byte] {.requires: header.data != nil.} =
  ## Return detached core/package or core/mappings bytes for host-side admission.
  let data = header.data
  assert data != nil
  copied(data.first)

proc packageMessage*(header: UntrustedWorkHeader): seq[byte] {.requires: header.data != nil.} =
  ## CE133 has no second header payload; CE146 retains exactly its bounded package message.
  let data = header.data
  assert data != nil
  copied(data.package)

func kind*(header: UntrustedWorkHeader): WorkSubmissionKind {.requires: header.data != nil.} =
  ## Retain the selector's exact independently framed form.
  let data = header.data
  assert data != nil
  data.kind

proc extrinsics*(body: UntrustedWorkBody): seq[byte] {.requires: body.data != nil.} =
  ## Detached bytes still require original-package commitment verification.
  let data = body.data
  assert data != nil
  copied(data.extrinsics)

proc segments*(body: UntrustedWorkBody): seq[byte] {.requires: body.data != nil.} =
  ## CE133 supplies no imported bytes on this stream; CE146 raw leaves remain untrusted.
  let data = body.data
  assert data != nil
  copied(data.segments)

proc proofs*(body: UntrustedWorkBody): seq[byte] {.requires: body.data != nil.} =
  ## Neither canonical hash-path framing nor inclusion is implied by stream completion.
  let data = body.data
  assert data != nil
  copied(data.proofs)

func headerCount(route: WorkRoute): int =
  ## CE133 has one small header; CE146 separates mappings from its package.
  if route.kind == WorkSubmissionKind.Package: 1 else: 2

func messageCount(route: WorkRoute): int =
  ## The body forms differ independently from the common outer E4 framing.
  if route.kind == WorkSubmissionKind.Package: 2 else: 5

func failed*(route: WorkRoute): bool =
  ## Parent teardown revokes a reset/failed route before host acknowledgment.
  route.configured and route.failure != ReadError.None

func receivedBytes*(route: WorkRoute): uint64 =
  ## Credit remains charged for all copied E4/payload bytes until actual parent/native retirement.
  route.received

func headerReady*(route: WorkRoute): bool =
  ## Only a complete exact small header can become one host task.
  route.configured and not route.failed and route.index == route.headerCount and
    not route.permitted and not route.headerTaken

func bodyReady*(route: WorkRoute): bool =
  ## Request FIN and all exact body messages precede host-visible completion.
  route.configured and not route.failed and route.permitted and route.receivedFin and
      not route.bodyTaken

proc refuse(route: var WorkRoute, reason: ReadError) =
  ## Abort only this native stream; the parent retains physical quota and buffers until actual close.
  route.failure = reason
  if route.stream != NativeStream(nil):
    wantRead(route.stream, 0)
    wantWrite(route.stream, 0)
    streamAbort(route.stream)

proc bindWorkStream*(route: var WorkRoute, stream: NativeStream,
    kind: WorkSubmissionKind): ReadError =
  ## The authenticated parent consumes the selector and binds only a live bidirectional peer-initiated route.
  if route.configured or stream == NativeStream(nil): return ReadError.InvalidStream
  if (uint64(stream.streamId) and 2) != 0: return ReadError.InvalidStream
  if kind notin [WorkSubmissionKind.Package, WorkSubmissionKind.Bundle]: return ReadError.InvalidRequest
  route = WorkRoute(stream: stream, configured: true, kind: kind, failure: ReadError.None)
  wantRead(stream, 1)
  wantWrite(stream, 0)
  ReadError.None

proc takeHeader*(route: var WorkRoute): WorkStreamResult[UntrustedWorkHeader] =
  ## Freeze independent raw header bytes; no graph owner or native pointer reaches the host.
  if not route.headerReady: return WorkStreamResult[UntrustedWorkHeader](
      status: ReadError.Unavailable)
  var package: seq[byte] = @[]
  if route.kind == WorkSubmissionKind.Bundle: package = copied(route.messages[1])
  route.headerTaken = true
  WorkStreamResult[UntrustedWorkHeader](status: ReadError.None,
    completed: UntrustedWorkHeader(data: HeaderBytes(kind: route.kind,
      first: copied(route.messages[0]), package: package)))

proc permitBody*(route: var WorkRoute, info: WorkSubmissionInfo): ReadError =
  ## Trusted host dispatch calls this only after actual grant collection; independent hard bounds protect transport memory.
  if not route.configured or route.failed or not route.headerTaken or route.permitted or
      route.index != route.headerCount or route.stream == NativeStream(
          nil): return ReadError.InvalidStream
  if info.kind != route.kind or info.packageBytes < 1 or info.packageBytes > MaxBundleBytes or
      info.extrinsicBytes < 0 or info.extrinsicBytes > 13904950 or
      info.importCount < 0 or info.importCount > 3072: return ReadError.InvalidRequest
  if info.segmentBytes != info.importCount*4104: return ReadError.InvalidRequest
  let actualPackage = if route.kind == WorkSubmissionKind.Package: route.messages[0].len-2
    else: route.messages[1].len
  if info.packageBytes != actualPackage: return ReadError.InvalidRequest
  if route.messages[0].len < 2: return ReadError.InvalidRequest
  let core = uint64(route.messages[0][0]) or (uint64(route.messages[0][1]) shl 8)
  if uint64(info.core) != core: return ReadError.InvalidRequest
  if info.packageBytes+info.extrinsicBytes+info.segmentBytes+info.importCount > 13904950:
    return ReadError.LimitExceeded
  route.info = info
  route.permitted = true
  wantRead(route.stream, 1)
  ReadError.None

proc lengthAllowed(route: WorkRoute, length: uint64): bool =
  ## Validate the complete E4 extent before allocation or native-int narrowing.
  if route.index < route.headerCount:
    if route.index == 0:
      let maximum = if route.kind == WorkSubmissionKind.Package: uint64(
          MaxBundleBytes+2) else: 515'u64
      return length >= 3 and length <= maximum
    return length > 0 and length <= uint64(MaxBundleBytes)
  if not route.permitted: return false
  let body = route.index-route.headerCount
  if body == 0: return length == uint64(route.info.extrinsicBytes)
  if body == 1: return length == uint64(route.info.segmentBytes)
  let available = 13904950-route.info.packageBytes-route.info.extrinsicBytes-route.info.segmentBytes
  length <= uint64(min(route.info.importCount*385, available))

proc nextMessage(route: var WorkRoute) =
  ## Completion advances at most one bounded message and pauses exactly before any unauthorized body prefix.
  inc route.index
  route.prefixUsed = 0
  route.remaining = 0
  route.prefix = default(array[4, byte])
  if route.index == route.headerCount and not route.permitted: wantRead(route.stream, 0)

proc takeBody*(route: var WorkRoute): WorkStreamResult[UntrustedWorkBody] =
  ## Exact FIN grants only a complete untrusted transcript for host-side commitment/proof/execution verification.
  if not route.bodyReady: return WorkStreamResult[UntrustedWorkBody](status: ReadError.Unavailable)
  let start = route.headerCount
  var segments, proofs: seq[byte] = @[]
  if route.kind == WorkSubmissionKind.Bundle:
    segments = copied(route.messages[start+1])
    proofs = copied(route.messages[start+2])
  route.bodyTaken = true
  WorkStreamResult[UntrustedWorkBody](status: ReadError.None,
    completed: UntrustedWorkBody(data: BodyBytes(kind: route.kind,
      extrinsics: copied(route.messages[start]), segments: segments, proofs: proofs)))

proc acknowledge*(route: var WorkRoute): ReadError =
  ## The host must have verified and accepted the whole original-bound body before requesting the bare response FIN.
  if not route.configured or route.failed or not route.receivedFin or not route.bodyTaken or
      route.acknowledging or route.stream == NativeStream(nil): return ReadError.InvalidStream
  route.acknowledging = true
  wantWrite(route.stream, 1)
  ReadError.None

proc event*(route: var WorkRoute, stream: NativeStream, event: cint,
    budget: ByteLimit) =
  ## Copy at most one 4096-byte chunk, never overread a message/header boundary, and perform no semantic or canonical work.
  if not route.configured or route.stream != stream: return
  if event == 3:
    route.stream = NativeStream(nil)
    if not route.sentFin: route.failure = ReadError.InvalidStream
    return # Parent destroys the physical frame only after this callback returns.
  if event == 4:
    route.failure = ReadError.InvalidStream
    wantRead(stream, 0)
    wantWrite(stream, 0)
    return # Reset always precedes host success, including while authorization is paused.
  if route.failed: return
  if event == 2:
    if route.acknowledging and not route.sentFin:
      route.sentFin = true
      wantWrite(stream, 0)
      discard streamFlush(stream)
      streamFin(stream)
    return # No response payload or fabricated E4 acknowledgment exists.
  if event != 1 or route.receivedFin: return
  if route.index == route.headerCount and not route.permitted: return
  let awaitingFin = route.index == route.messageCount
  var maximum = 1
  if not awaitingFin:
    # Native read sizes stop exactly at prefix/body extents, so one callback cannot consume an unauthorized next prefix.
    maximum = if route.prefixUsed < 4: 4-route.prefixUsed else: min(4096, route.remaining)
    if uint64(maximum) > uint64(budget): maximum = int(min(uint64(budget), 4096'u64))
    if maximum == 0:
      route.refuse(ReadError.LimitExceeded)
      return
  var bytes = default(array[4096, byte])
  let count = streamRead(stream, addr bytes[0], csize_t(maximum))
  if count == -2: return
  if count < 0 or count > int64(maximum):
    route.refuse(ReadError.InvalidStream)
    return
  if count == 0:
    if not awaitingFin:
      route.refuse(ReadError.InvalidRequest)
      return
    route.receivedFin = true
    wantRead(stream, 0)
    readDone(stream)
    return
  if awaitingFin:
    route.refuse(ReadError.InvalidRequest)
    return # Any trailing octet, including another E4 message, invalidates the transcript.
  route.received += uint64(count)
  if route.prefixUsed < 4:
    # Exactly four prefix bytes are assembled before any declared body bytes are copied.
    for index in 0..<int(count): route.prefix[route.prefixUsed+index] = bytes[index]
    route.prefixUsed += int(count)
    if route.prefixUsed == 4:
      var length = 0'u64
      for index in 0..<4: length = length or (uint64(route.prefix[index]) shl (index*8))
      if not route.lengthAllowed(length):
        route.refuse(ReadError.InvalidRequest)
        return
      route.remaining = int(length) # All allowed extents are independently below fourteen million bytes.
      if route.remaining == 0: route.nextMessage() # Empty messages still consume their own exact E4 frame.
  else:
    # The preflighted remaining extent and shared byte credit prove bounded append and subtraction.
    for index in 0..<int(count): route.messages[route.index].add(bytes[index])
    route.remaining -= int(count)
    if route.remaining == 0: route.nextMessage()
