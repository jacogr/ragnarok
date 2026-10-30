# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded loopback devnet transport: pinned TLS identities and canonical CE128 one-child
## polling. Callbacks only frame/copy bytes; block execution and catalog publication stay outside.

import std/assertions
import ../quic/transport
import ./[protocol, announcements, announcement_stream, streams]
import ../codec/header

const MaxBlock = 65536 ## Empty Tiny blocks and variable epoch markers fit this explicit local ceiling.

type
  ServedBlock = object ## Only the host publishes fully validated canonical successors into this finite catalog.
    parent: array[32, byte]
    bytes: seq[byte]
  Response = object ## Fixed admitted-stream slots retain bounded input/output through the native close event.
    stream: NativeStream
    request: array[42, byte]
    received, offset: int
    bytes: seq[byte]
    writing: bool
    announcement: AnnouncementRoute
    sentVersion: uint64
  DevnetNetwork* = object ## Exclusive stable callback owner; explicit close retires both engines before destruction.
    incoming, outgoing: Transport
    peers: array[6, array[32, byte]]
    expected: array[32, byte]
    responses: array[16, Response]
    catalog: seq[ServedBlock]
    client: NativeStream
    request: array[42, byte]
    response: seq[byte]
    sent: int
    active, dialed, opened, complete, failed: bool
    discovery: bool
    announcementLimits: AnnouncementLimits
    localHandshake: AnnouncementHandshake
    announcementBody: seq[byte]
    announcementVersion: uint64

proc `=copy`*(destination: var DevnetNetwork, source: DevnetNetwork) {.error:
    "DevnetNetwork owns stable native callback addresses".}
  ## Neither endpoint nor its per-stream routing can be duplicated.
proc `=dup`*(source: DevnetNetwork): DevnetNetwork {.error.}
  ## Sequence retention must not introduce an implicit exclusive-owner copy.
proc `=wasMoved`*(owner: var DevnetNetwork) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(owner.incoming)
  `=wasMoved`(owner.outgoing)
  `=wasMoved`(owner.peers)
  `=wasMoved`(owner.expected)
  `=wasMoved`(owner.responses)
  `=wasMoved`(owner.catalog)
  `=wasMoved`(owner.client)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.response)
  `=wasMoved`(owner.sent)
  `=wasMoved`(owner.active)
  `=wasMoved`(owner.dialed)
  `=wasMoved`(owner.opened)
  `=wasMoved`(owner.complete)
  `=wasMoved`(owner.failed)
  `=wasMoved`(owner.discovery)
  `=wasMoved`(owner.announcementLimits)
  `=wasMoved`(owner.localHandshake)
  `=wasMoved`(owner.announcementBody)
  `=wasMoved`(owner.announcementVersion)

proc `=destroy`*(owner: DevnetNetwork) =
  ## Teardown remains explicit while callbacks can still borrow this exact owner address.
  assert not owner.active, "DevnetNetwork requires close before destruction"
  assert owner.catalog.len == 0 and owner.announcementBody.len == 0
  assert owner.localHandshake.leaves.len == 0 # Explicit close releases managed routing/publication storage as well as native engines.

proc serverVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## A server accepts only the six configured identities, with ordinary JAMNP certificate/SAN checks.
  let owner = cast[ptr DevnetNetwork](user)
  for index in 0..<6:
    if validPeer(cast[ptr byte](der), length, owner.peers[index]): return 1
  0
proc clientVerify(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## Each dial pins one exact expected peer rather than trusting an arbitrary certificate.
  let owner = cast[ptr DevnetNetwork](user)
  cint(validPeer(cast[ptr byte](der), length, owner.expected))

proc selectPersistent(owner: ptr DevnetNetwork, stream: NativeStream): bool {.raises: [].} =
  ## Reject stale UP0 arrivals before replacing any live route on this same authenticated connection.
  let candidate = stream.streamId
  if not persistentInitiator(candidate): return false
  # Inspect every retained route first so slot ordering cannot revoke an older route for a rejected candidate.
  for index in 0..<owner.responses.len:
    let old = owner.responses[index].announcement.handle
    if old != NativeStream(nil) and old != stream and
        not owner.responses[index].announcement.failed and samePeer(old, stream) == 1:
      if not preferPersistent(candidate, old.streamId): return false
  # Revoke every older claim before resetting its native stream. Close retains ownership of its slot.
  for index in 0..<owner.responses.len:
    let old = owner.responses[index].announcement.handle
    if old != NativeStream(nil) and old != stream and
        not owner.responses[index].announcement.failed and samePeer(old, stream) == 1:
      discard owner.responses[index].announcement.event(old, 4)
      streamAbort(old)
  true

proc serverEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## One bounded native read/write per event preserves progress across all admitted connections.
  let owner = cast[ptr DevnetNetwork](user)
  var found = -1
  for index in 0..<owner.responses.len:
    if owner.responses[index].stream == stream: found = index
  if event == 0:
    if owner.incoming.locallyOpened(stream):
      streamAbort(stream)
      return # A block responder never binds a locally initiated request stream.
    for index in 0..<owner.responses.len:
      if found < 0 and owner.responses[index].stream == NativeStream(nil): found = index
    if found < 0:
      streamAbort(stream)
      return # Fixed callback routing capacity never grows under incoming work.
    owner.responses[found] = Response(stream: stream)
    wantRead(stream, 1)
    return
  if found < 0: return # Already retired/rejected streams cannot access another slot.
  let response = addr owner.responses[found]
  if response.announcement.handle == stream:
    discard response.announcement.event(stream, event)
    if event == 3: response[] = Response() # Final native retirement precedes release of every UP0 byte owner.
    return
  case event
  of 1:
    if response.received == 0:
      var kind = 0'u8
      let count = streamRead(stream, addr kind, 1)
      if count == -2: return
      if count != 1:
        streamAbort(stream)
        return # FIN/errors before the stream kind cannot select a responder.
      if kind == 0:
        if not owner.discovery or not selectPersistent(owner, stream):
          streamAbort(stream)
          return
        let bound = response.announcement.bindStream(stream, false, owner.localHandshake,
          owner.announcementLimits)
        if bound != AnnouncementError.None:
          streamAbort(stream)
          return
        discard response.announcement.acceptKind(kind)
        response.sentVersion = owner.announcementVersion
        return # Only this one kind byte was consumed; subsequent callbacks copy bounded UP0 frames.
      if kind != 128:
        streamAbort(stream)
        return # This development responder supports only explicit UP0 and ascending one-child CE128.
      response.request[0] = kind
      response.received = 1
      return
    var buffer = default(array[64, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return # Would-block retains the current incomplete request.
    if count < 0 or count > int64(42-owner.responses[found].received):
      streamAbort(stream)
      return # Errors and overlong requests cannot trigger a response allocation.
    if count > 0:
      for index in 0..<int(count):
        owner.responses[found].request[owner.responses[found].received+index] = buffer[index]
      owner.responses[found].received += int(count)
    else:
      let request = owner.responses[found].request
      var expected = default(array[42, byte])
      expected[0] = 128
      expected[1] = 37
      expected[38] = 1
      for index in 5..<37: expected[index] = request[index]
      if owner.responses[found].received != 42 or request != expected:
        streamAbort(stream)
        return # Require exact CE128 kind, E4 size, ascending direction, maximum1 and request FIN.
      readDone(stream)
      wantRead(stream, 0)
      var parent = default(array[32, byte])
      owner.responses[found].bytes = newSeq[byte](4) # E4 zero is the exact empty block-sequence frame.
      for index in 0..<32: parent[index] = request[index+5]
      for index in 0..<owner.catalog.len:
        if owner.catalog[index].parent == parent:
          let bytes = owner.catalog[index].bytes
          owner.responses[found].bytes = newSeq[byte](bytes.len+4)
          for octet in 0..<4:
            owner.responses[found].bytes[octet] = byte((uint64(bytes.len) shr (8*octet)) and 255)
          for octet in 0..<bytes.len: owner.responses[found].bytes[octet+4] = bytes[octet]
          break # Catalog insertion refuses competing successors for the same canonical parent.
      owner.responses[found].writing = true
      wantWrite(stream, 1) # An absent child returns an empty response sequence followed by FIN.
  of 2:
    if owner.responses[found].writing:
      let remaining = owner.responses[found].bytes.len-owner.responses[found].offset
      if remaining > 0:
        let offset = owner.responses[found].offset
        let count = streamWrite(stream, addr owner.responses[found].bytes[offset], csize_t(min(
            remaining, 4096)))
        if count == -2: return # Retain exact unsent offset for the next writable event.
        if count < 0 or count > int64(min(remaining, 4096)):
          streamAbort(stream)
          return
        owner.responses[found].offset += int(count)
      if owner.responses[found].offset == owner.responses[found].bytes.len:
        owner.responses[found].writing = false
        wantWrite(stream, 0)
        discard streamFlush(stream)
        streamFin(stream) # Native close retains this slot until both directions are retired.
  of 3:
    owner.responses[found] = Response() # Only the final close releases immutable response storage.
  of 4:
    wantRead(stream, 0)
    wantWrite(stream, 0) # Reset is terminal for this stream; final close still owns retirement.
  else: discard # Unknown events confer no framing or canonical authority.

proc clientEvent(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## The sole outstanding request returns copied bytes only after its exact response sequence FIN.
  let owner = cast[ptr DevnetNetwork](user)
  case event
  of 0:
    if not owner.dialed or not owner.outgoing.locallyOpened(stream) or owner.client != NativeStream(nil):
      streamAbort(stream)
      return # Never replace a live callback binding.
    owner.client = stream
    wantRead(stream, 1)
    wantWrite(stream, 1)
  of 1:
    if owner.client != stream or owner.complete or owner.failed: return
    var buffer = default(array[4096, byte])
    let count = streamRead(stream, addr buffer[0], csize_t(buffer.len))
    if count == -2: return # Framing decisions await actual data/FIN.
    if count < 0 or count > int64(MaxBlock+4-owner.response.len):
      owner.failed = true
      streamAbort(stream)
      return # Aggregate response storage never exceeds the hard block ceiling.
    if count > 0:
      for index in 0..<int(count): owner.response.add(buffer[index])
    else:
      readDone(stream)
      wantRead(stream, 0)
      owner.complete = true # Host parsing still checks exact E4 extent before using payload bytes.
  of 2:
    if owner.client != stream or owner.failed: return
    if owner.sent < 42:
      let count = streamWrite(stream, addr owner.request[owner.sent], csize_t(42-owner.sent))
      if count == -2: return # A partial request preserves its exact write position.
      if count < 0 or count > int64(42-owner.sent):
        owner.failed = true
        streamAbort(stream)
        return
      owner.sent += int(count)
    if owner.sent == 42:
      wantWrite(stream, 0)
      discard streamFlush(stream)
      streamFin(stream) # Response reads remain available after this clean request half-close.
  of 3:
    if owner.client == stream:
      owner.client = NativeStream(nil)
      if not owner.complete: owner.failed = true # A close/reset without response FIN is not empty success.
  of 4:
    owner.failed = true
  else: discard # Native events outside the declared lifecycle cannot complete a request.

proc closeRequest*(owner: var DevnetNetwork) =
  ## Native destruction delivers final callbacks while the response and owner remain alive.
  if owner.dialed:
    disconnectTransport(owner.outgoing)
    discard pollTransport(owner.outgoing, 0) # Emit connection close while UDP and callback owners remain live.
  closeTransport(owner.outgoing)
  owner.dialed = false
  owner.opened = false
  owner.client = NativeStream(nil)
proc close*(owner: var DevnetNetwork) =
  ## Retire both endpoint engines before callback metadata and catalog storage leave scope.
  owner.closeRequest()
  closeTransport(owner.incoming)
  owner.responses = default(array[16, Response]) # Native close retired all borrowed stream handles first.
  owner.catalog = @[]
  owner.response = @[]
  owner.localHandshake = default(AnnouncementHandshake)
  owner.announcementBody = @[]
  owner.announcementVersion = 0
  owner.discovery = false
  owner.active = false
proc open*(owner: var DevnetNetwork, port: uint16, cert, key, alpn: string,
    peers: array[6, array[32, byte]]): bool =
  ## Stable stack ownership begins before any TLS/native callback can observe the endpoint.
  if owner.active: return false
  owner.peers = peers
  owner.active = true
  if not openTransport(owner.incoming, true, false, port, cert, key, alpn, addr owner,
      serverVerify, serverEvent, multi = true):
    owner.close()
    return false # Setup refusal retires all partially acquired resources.
  true
proc publish*(owner: var DevnetNetwork, parent: array[32, byte], bytes: seq[byte]): bool =
  ## Host-only publication follows complete validation/adoption; finite canonical history serves catch-up.
  if bytes.len == 0 or bytes.len > MaxBlock or owner.catalog.len >= 64: return false
  for index in 0..<owner.catalog.len:
    if owner.catalog[index].parent == parent: return false # No ambiguous child for one canonical parent.
  owner.catalog.add(ServedBlock(parent: parent, bytes: bytes))
  true
proc request*(owner: var DevnetNetwork, port: uint16, expected: array[32, byte],
    parent: array[32, byte], cert, key, alpn: string): bool =
  ## Serial dialing bounds resources to one outstanding peer/request per node.
  if not owner.active or owner.dialed: return false
  owner.expected = expected
  owner.sent = 0
  owner.complete = false
  owner.failed = false
  owner.response = @[]
  owner.request = default(array[42, byte])
  owner.request[0] = 128
  owner.request[1] = 37
  owner.request[38] = 1
  for index in 0..<32: owner.request[index+5] = parent[index]
  if not openTransport(owner.outgoing, false, false, 0, cert, key, alpn, addr owner,
      clientVerify, clientEvent): return false
  owner.dialed = true
  if not connectTransport(owner.outgoing, port):
    owner.closeRequest()
    return false
  true
proc poll*(owner: var DevnetNetwork): bool =
  ## Both engines progress with nonblocking bounded work; no consensus execution occurs in callbacks.
  if not pollTransport(owner.incoming, 0): return false
  if owner.discovery:
    for index in 0..<owner.responses.len:
      let response = addr owner.responses[index]
      response.announcement.process() # Decoding and header hashing run only after every native callback returned.
      if response.sentVersion != owner.announcementVersion and response.announcement.active:
        if response.announcement.announce(owner.announcementBody) == AnnouncementError.None:
          response.sentVersion = owner.announcementVersion # Busy output retains the newest detached publication for a later bounded turn.
  if owner.dialed:
    if not pollTransport(owner.outgoing, 1): owner.failed = true
    if not owner.opened and transportStatus(owner.outgoing) == 1:
      owner.opened = true
      openStream(owner.outgoing) # One stream opens only after TLS authentication.
  true
func finished*(owner: DevnetNetwork): bool =
  ## Both peer failure and actual FIN return control to the bounded host retry loop.
  owner.complete or owner.failed
proc take*(owner: var DevnetNetwork, bytes: var seq[byte]): bool =
  ## Copy a single exact framed block or an empty response; refusal never returns a partial payload.
  bytes = @[]
  if not owner.complete or owner.failed or owner.sent != 42: return false
  if owner.response.len < 4: return false
  var count = 0'u64
  for index in 0..<4: count = count or (uint64(owner.response[index]) shl (8*index))
  if count > uint64(MaxBlock) or count != uint64(owner.response.len-4): return false
  bytes = newSeq[byte](int(count))
  for index in 0..<bytes.len: bytes[index] = owner.response[index+4]
  true

proc enableAnnouncements*(owner: var DevnetNetwork, local: AnnouncementHandshake,
    limits: AnnouncementLimits): AnnouncementError =
  ## Configure copied local evidence before the listener can accept a persistent UP0 stream.
  if owner.active or owner.discovery: return AnnouncementError.Busy
  let encoded = encodeHandshake(local, limits)
  if encoded.error != AnnouncementError.None: return encoded.error
  owner.localHandshake.finalized = local.finalized
  owner.localHandshake.leaves = @[]
  for leaf in local.leaves: owner.localHandshake.leaves.add(leaf)
  owner.announcementLimits = limits
  owner.discovery = true
  AnnouncementError.None
proc publishAnnouncement*(owner: var DevnetNetwork, header: OwnedHeader,
    finalized: AnnouncedBlock): AnnouncementError =
  ## Host-only publication follows actual durable admission; retain bytes/scalars rather than canonical aliases.
  if not owner.discovery: return AnnouncementError.Uninitialized
  if owner.announcementVersion == high(uint64): return AnnouncementError.LimitExceeded
  let encoded = encodeAnnouncement(header, finalized, owner.announcementLimits)
  if encoded.error != AnnouncementError.None: return encoded.error
  let decoded = decodeAnnouncement(encoded.value, owner.announcementLimits)
  if decoded.error != AnnouncementError.None: return decoded.error
  owner.localHandshake = AnnouncementHandshake(finalized: finalized, leaves: @[decoded.value.head])
  owner.announcementBody = encoded.value
  inc owner.announcementVersion
  AnnouncementError.None

proc localPort*(owner: DevnetNetwork): uint16 =
  ## Report the actual bound listener for bounded host/test integration, including ephemeral port selection.
  if owner.active: owner.incoming.localPort else: 0'u16
