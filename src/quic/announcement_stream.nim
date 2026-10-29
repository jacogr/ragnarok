# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One UP0 route borrows its catalog-owned stream, frames bounded messages and retains copied
## untrusted peer leaves. Stream closure revokes every observation; no chain executes in callbacks.

import ./[announcements, transport]
import ../codec/[bounded, header]

type
  PeerAnnouncements* = object ## A snapshot describes source claims, never local finality or validated state.
    finalized*: AnnouncedBlock
    leaves*: seq[AnnouncedBlock]
    sequence*: uint64
  PeerAnnouncementSnapshot* = object ## Default/retired streams carry no source claims.
    case available: bool
    of true: captured: PeerAnnouncements
    else: discard                    # No payload exists until the exact native stream completed a handshake.
  AnnouncementRoute* = object ## Fixed-address parent owns native retirement; this route owns only message bytes.
    stream: NativeStream
    limits: AnnouncementLimits
    reader: AnnouncementReader
    output: seq[byte]
    offset: int
    known, failed, kindNeeded: bool
    remote: PeerAnnouncements

proc active*(route: AnnouncementRoute): bool =
  ## A reset, EOF or native close immediately revokes formerly known leaves.
  route.stream != NativeStream(nil) and route.known and not route.failed
func handle*(route: AnnouncementRoute): NativeStream =
  ## Parent callback routing compares the borrowed handle only during its native lifetime.
  route.stream
func failed*(route: AnnouncementRoute): bool =
  ## A failed stream cannot silently retain an eligible target until transport teardown.
  route.failed
func available*(snapshot: PeerAnnouncementSnapshot): bool =
  ## Only a live authenticated parent may expose a route's completed remote handshake.
  snapshot.available
func value*(snapshot: PeerAnnouncementSnapshot): PeerAnnouncements {.inline,
    requires: snapshot.available.} =
  ## The returned data is still an untrusted peer claim rather than adoption authority.
  snapshot.captured
proc snapshot*(route: AnnouncementRoute): PeerAnnouncementSnapshot =
  ## Copied remote metadata is exposed only while this exact persistent stream is usable.
  if not route.active: return default(PeerAnnouncementSnapshot)
  var leaves: seq[AnnouncedBlock] = @[]
  for leaf in route.remote.leaves: leaves.add(leaf)
  PeerAnnouncementSnapshot(available: true, captured: PeerAnnouncements(
    finalized: route.remote.finalized, leaves: leaves, sequence: route.remote.sequence))

proc framed(body: seq[byte], initiator: bool): seq[byte] =
  ## Prefix a bounded message with E4 size and, once per initiated stream, UP kind zero.
  result = @[]
  if initiator: result.add(0)
  for index in 0..<4: result.add(byte((uint64(body.len) shr (8 * index)) and 255))
  for value in body: result.add(value)
proc bindStream*(route: var AnnouncementRoute, stream: NativeStream, initiator: bool,
    local: AnnouncementHandshake, limits: AnnouncementLimits): AnnouncementError =
  ## Install every byte owner before enabling callbacks; the acceptor first checks the kind byte.
  if stream == NativeStream(nil): return AnnouncementError.InvalidStream
  if route.stream != NativeStream(nil): return AnnouncementError.Busy
  let encoded = encodeHandshake(local, limits)
  if encoded.error != AnnouncementError.None: return encoded.error
  route = AnnouncementRoute(stream: stream, limits: limits, output: framed(encoded.value,
      initiator),
    kindNeeded: not initiator)
  let configured = route.reader.configure(limits.bytes)
  if configured != AnnouncementError.None: return configured
  wantRead(stream, 1)
  wantWrite(stream, 1)
  AnnouncementError.None
proc revoke(route: var AnnouncementRoute) =
  ## Forget source claims without touching an already-reset or closing native handle.
  route.failed = true
  route.known = false
  route.remote = default(PeerAnnouncements)
proc refuse(route: var AnnouncementRoute) =
  ## Reset only this persistent stream; the parent keeps any unrelated CE request alive.
  route.revoke()
  if route.stream != NativeStream(nil): streamAbort(route.stream)
proc acceptKind*(route: var AnnouncementRoute, kind: byte): AnnouncementError =
  ## A multiplexing acceptor may consume the one stream-kind byte before binding this UP0 route.
  if route.stream == NativeStream(nil): return AnnouncementError.InvalidStream
  if not route.kindNeeded: return AnnouncementError.Busy
  if kind != 0:
    route.refuse()
    return AnnouncementError.InvalidStream # An already consumed foreign kind cannot enter UP0 framing.
  route.kindNeeded = false
  AnnouncementError.None
proc acceptMessage(route: var AnnouncementRoute): bool =
  ## Commit one whole decoded message atomically; invalid claims retain no partial target set.
  let message = route.reader.message
  if message.error != AnnouncementError.None: return false
  if not route.known:
    let handshake = decodeHandshake(message.value, route.limits)
    if handshake.error != AnnouncementError.None: return false
    route.remote.finalized = handshake.value.finalized
    route.remote.leaves = handshake.value.leaves
    route.known = true
  else:
    let announced = decodeAnnouncement(message.value, route.limits)
    if announced.error != AnnouncementError.None: return false
    let decoded = announced.value
    let info = decoded.header.headerInfo
    if info.error != HeaderError.None: return false
    let parent = AnnouncedHeaderHash(array[32, byte](info.value.unsigned.parent))
    let announcedHash = decoded.head.hash
    var leaves: seq[AnnouncedBlock] = @[]
    for leaf in route.remote.leaves:
      # Replacing an announced parent with its child follows UP0's leaf semantics, not fork choice.
      if leaf.hash != parent and leaf.hash != announcedHash:
        leaves.add(leaf)
    if leaves.len >= int(uint64(route.limits.leaves)): return false
    leaves.add(decoded.head)
    route.remote.finalized = decoded.finalized
    route.remote.leaves = leaves
  if route.remote.sequence == high(uint64): return false
  inc route.remote.sequence
  route.reader.consume() == AnnouncementError.None
proc event*(route: var AnnouncementRoute, stream: NativeStream, event: cint): bool =
  ## Handle at most one bounded read/write chunk or one complete message per native event.
  if stream == NativeStream(nil) or stream != route.stream: return false
  if route.failed and event notin [3.cint, 4.cint]: return true
  case event
  of 1:
    var buffer = default(array[4096, byte])
    let maximum = if route.kindNeeded: 1 else: min(buffer.len, route.reader.remaining)
    if maximum <= 0:
      route.refuse()
      return true
    let count = streamRead(stream, addr buffer[0], csize_t(maximum))
    if count == -2: return true # QUIC would-block leaves framing and claims unchanged.
    if count <= 0 or count > int64(maximum):
      route.refuse() # Persistent-stream FIN is not successful catch-up or an empty message.
      return true
    if route.kindNeeded:
      if route.acceptKind(buffer[0]) != AnnouncementError.None: return true
    else:
      if route.reader.feed(buffer.toOpenArray(0, int(count) - 1)) != AnnouncementError.None:
        route.refuse()
        return true
      if route.reader.ready: wantRead(stream, 0) # Host processing/hash validation follows callback return.
  of 2:
    if route.offset < route.output.len:
      let maximum = min(4096, route.output.len - route.offset)
      let count = streamWrite(stream, addr route.output[route.offset], csize_t(maximum))
      if count == -2: return true # Preserve the original output offset under backpressure.
      if count <= 0 or count > int64(maximum):
        route.refuse()
        return true
      route.offset += int(count)
    if route.offset == route.output.len:
      route.output = @[]
      route.offset = 0
      wantWrite(stream, 0)
      discard streamFlush(stream) # UP streams remain open; an idle send queue never emits FIN.
  of 3:
    route.stream = NativeStream(nil)
    route.known = false
    route.remote = default(PeerAnnouncements) # Final native retirement invalidates earlier observations.
  of 4:
    route.revoke()
    wantRead(stream, 0)
    wantWrite(stream, 0) # A peer reset is already terminal; never reset it recursively.
  else: discard # Unrelated native event kinds cannot fabricate a target observation.
  true
proc process*(route: var AnnouncementRoute) =
  ## Decode/hash at most one complete detached message outside native callbacks, then resume reads.
  if route.stream != NativeStream(nil) and not route.failed and route.reader.ready:
    if not route.acceptMessage():
      route.refuse()
      return
    wantRead(route.stream, 1)

proc announce*(route: var AnnouncementRoute, body: seq[byte]): AnnouncementError =
  ## Queue detached encoded bytes; native polling never touches canonical ARC header aliases.
  if route.stream == NativeStream(nil) or route.failed: return AnnouncementError.Uninitialized
  if route.output.len != 0: return AnnouncementError.Busy
  let decoded = decodeAnnouncement(body, route.limits)
  if decoded.error != AnnouncementError.None: return decoded.error
  route.output = framed(body, false)
  route.offset = 0
  wantWrite(route.stream, 1)
  AnnouncementError.None
