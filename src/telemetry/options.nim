# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional trailing CLI controls for the existing bounded proof-peer command shape.
##
## Exposes peer CLI option parsing, telemetry/RPC setup controls and connection/peer observation
## helpers.

import std/[os, syncio, times, monotimes, strutils, base64]
import ./[wire, client, chain]
import ../quic/transport
import ../rpc/[server, protocol]
import ../chain/parameters
export wire, client

# Locate the first reserved option; all configuration pairs must follow positional peer arguments.
proc optionStart(): int =
  for i in 1..paramCount():
    if paramStr(i) in ["--telemetry", "--chain", "--rpc-port"]: return i # Reserve both names even in malformed input.
  paramCount() + 1

# Validate unique trailing pairs; telemetry still requires an explicit chain, RPC is independently optional.
proc validTelemetryOption*(): bool =
  let first = optionStart()
  if (paramCount() - first + 1) mod 2 != 0: return false # Every option requires one value.
  var seen: seq[string] = @[]
  var i = first
  while i <= paramCount(): # Preserve positional arguments and reject unknown or duplicate options.
    let name = paramStr(i)
    let value = paramStr(i + 1)
    if name notin ["--telemetry", "--chain", "--rpc-port"] or name in seen or
        value.len == 0 or value.startsWith("--"): return false
    seen.add(name)
    if name == "--rpc-port": # Bound decimal parsing before narrowing to the native port type.
      if value.len > 5: return false
      var port = 0
      for c in value:
        if c notin {'0'..'9'}: return false # No signs, spaces or numeric aliases.
        port = port * 10 + ord(c) - ord('0')
      if port notin 1..65535: return false
    i += 2
  # Telemetry needs a chain; RPC may use the same chain independently or run diagnostics without one.
  ("--telemetry" notin seen or "--chain" in seen) and
    ("--chain" notin seen or "--telemetry" in seen or "--rpc-port" in seen)

# Read a validated option; absent optional features have no implicit configuration.
proc optionValue(name: string): string =
  var i = optionStart()
  while i < paramCount(): # Only validated pairs are used by startup callers.
    if paramStr(i) == name: return paramStr(i + 1)
    i += 2
  ""

# Telemetry remains independent of RPC, including its early clock/syscall shortcuts.
proc requested*(): bool = optionValue("--telemetry").len > 0

# Zero means disabled; syntax validation proves any present decimal value fits uint16.
proc rpcPort*(): uint16 =
  let value = optionValue("--rpc-port")
  if value.len == 0: return 0 # Default peer invocations do not listen for RPC.
  var port = 0
  for c in value: port = port * 10 + ord(c) - ord('0') # Startup already validated every digit and the range.
  uint16(port)

# Keep the existing positional command parsing independent of trailing option order.
proc peerParamCount*(): int = optionStart() - 1

# Read at most limit+1 bytes; empty output means missing, empty or oversized configuration.
proc boundedFile(path: string, limit: int): string {.raises.} =
  result = ""
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return # No implicit file/default chain.
  defer: close(file) # All read outcomes retire the handle.
  var text = newString(limit + 1)
  let buffer = text.beginStore(text.len)
  let count = readBuffer(file, cast[pointer](buffer), text.len)
  text.endStore() # Commit the public string bulk-write API before reading or resizing.
  if count <= 0 or count > limit: return # Detect growth/oversize without unbounded readFile.
  text.setLen(count)
  result = move(text)

# Read one startup snapshot for both RPC and telemetry so they cannot observe different file revisions.
proc loadChainText*(): string {.raises.} = boundedFile(optionValue("--chain"), MaxChainBytes)

# An explicit RPC chain must validate before opening the listener; missing configuration remains unavailable.
proc setupRpc*(rpc: var Server, role: string, text: string): bool =
  var parameters = default(ParameterResult)
  if rpcPort() != 0 and optionValue("--chain").len > 0:
    parameters = configuredParameters(text)
    if not parameters.ok: return false # Fail startup rather than advertise a partial/default parameter set.
  rpc.start(rpcPort(), role, parameters)

# Build registration from explicit JIP-4 configuration and the actual local certificate/socket.
proc setup*(client: var Client, certificate: string, port: uint16, ipv6: bool,
    text: string): bool {.raises.} =
  if not requested(): return true # Absence is the default and requires no configuration.
  if text.len == 0: return false # Never invent a chain or use an implicit development network.
  let pem = boundedFile(certificate, 16384).strip()
  const beginMarker = "-----BEGIN CERTIFICATE-----"
  const endMarker = "-----END CERTIFICATE-----"
  # Reject overlapping/empty PEM markers before constructing the body slice.
  if pem.len < beginMarker.len + endMarker.len: return false
  if not pem.startsWith(beginMarker) or not pem.endsWith(endMarker): return false
  var body = ""
  # Permit PEM whitespace but reject noncanonical base64 through round-trip validation below.
  for character in pem[beginMarker.len..<pem.len - endMarker.len]:
    if character notin {' ', '\t', '\r', '\n'}: body.add(character)
  var der = base64.decode(body)
  if der.len == 0 or der.len > 8192 or base64.encode(der) != body: return false
  # The native extractor initializes all C fields before success; no C array object constructor is used.
  var fields {.noinit.}: CertFields
  # Reuse maintained X.509 extraction; public identity is copied, never read from a secret key.
  let derPointer = der.toCString()
  if parseCert(cast[ptr byte](derPointer), csize_t(der.len), addr fields) != 1 or
      fields.edKey != 1 or fields.keyLength != 32: return false
  var address = default(array[16, byte])
  if ipv6:
    address[15] = 1 # The proof peer binds only ::1 in its IPv6 modes.
  else:
    # JIP-3 represents IPv4 endpoints as IPv4-mapped IPv6 addresses.
    address[10] = 255
    address[11] = 255
    address[12] = 127
    address[15] = 1
  var identity = default(array[32, byte])
  # Copy C array elements individually into native Nim storage before crossing the API boundary.
  for i in 0..<32: identity[i] = fields.key[i]
  let parsed = chainMetadata(text, identity, address, port)
  if not parsed.ok: return false # Failed chain metadata cannot produce a registration.
  configure(client, optionValue("--telemetry"), parsed.value)

# Convert wall time to the wire epoch; zero denotes an unavailable/pre-epoch local clock.
proc eventTimestamp(): Timestamp =
  let wall = getTime()
  let seconds = wall.toUnix - 1_735_732_800'i64
  if seconds < 0 or seconds > int64(high(uint64) div 1_000_000) - 1:
    return Timestamp(0) # Do not narrow or wrap an unrepresentable local timestamp.
  Timestamp(uint64(seconds) * 1_000_000 + uint64(wall.nanosecond div 1000))

# Translate wall time for wire timestamps and monotonic time for retry/status deadlines.
proc observe*(client: var Client, peers: uint32) =
  if not requested(): return # Default runs do not even query telemetry clocks.
  client.tick(getMonoTime().ticks div 1_000_000, eventTimestamp(), peers)

# The bounded proof dialer knows its pinned public identity and exact loopback destination before dialing.
proc startDial*(client: var Client, identity: openArray[byte], port: uint16, ipv6: bool): EventId =
  if not requested() or identity.len != 32: return EventId(0) # No instrumentation for disabled/invalid peers.
  var key = default(array[32, byte])
  for i in 0..<32: key[i] = identity[i] # Copy caller storage; no peer owner is retained.
  var address = default(array[16, byte])
  if ipv6:
    address[15] = 1 # The actual IPv6 proof transport dials ::1.
  else:
    address[10] = 255 # IPv4 destinations use their JIP-3 mapped IPv6 representation.
    address[11] = 255
    address[12] = 127
    address[15] = 1
  client.dialing(getMonoTime().ticks div 1_000_000, eventTimestamp(), key, address, port)

# Settle an outgoing attempt exactly once; callers use native authentication evidence, not application success.
proc finishDial*(client: var Client, attempt: EventId, authenticated: bool) =
  if not requested(): return # Disabled telemetry does not query clocks or encode frames.
  client.dialOutcome(getMonoTime().ticks div 1_000_000, eventTimestamp(), attempt, authenticated)

# Copy the authenticated outgoing identity only after the caller observes a native connection close.
proc finishConnection*(client: var Client, identity: openArray[byte]) =
  if not requested() or identity.len != 32: return # Invalid or disabled peers cannot emit a closure.
  var key = default(array[32, byte])
  for i in 0..<32: key[i] = identity[i] # No caller storage is retained by the bounded exporter.
  client.peerDisconnected(getMonoTime().ticks div 1_000_000, eventTimestamp(), key)

# Fixed correlation storage belongs to the peer and outlives native SSL destruction callbacks.
type IncomingAttempts* = object
  active: array[IncomingHandshakeSlots, bool]
  ids: array[IncomingHandshakeSlots, EventId]

# Copy callback data immediately; only bounded frames are queued here, never socket operations.
proc observeIncoming*(client: var Client, attempts: var IncomingAttempts, slot: cuint,
    event: cint, address: ptr ConstByte, port: uint16, der: ptr ConstByte, length: csize_t) =
  let stamp = eventTimestamp()
  if event == AdmissionRefused:
    if address == nil:
      client.omit(stamp) # A real refusal without endpoint metadata is a dropped observation.
      return
    var remote = default(array[16, byte])
    let source = cast[ptr UncheckedArray[byte]](address)
    for i in 0..<16: remote[i] = source[i] # The native stack borrow ends with this callback.
    client.refusing(getMonoTime().ticks div 1_000_000, stamp, remote, port)
    return # Refusals neither allocate nor settle handshake correlation slots.
  if event == HandshakeDropped or slot >= cuint(IncomingHandshakeSlots):
    client.omit(stamp) # Overflow or missing primitive metadata cannot fabricate an attempt.
    return
  let index = int(slot)
  let now = getMonoTime().ticks div 1_000_000
  if event == HandshakeStarted:
    if address == nil: # A missing address is not the all-zero endpoint.
      client.omit(stamp)
      return
    var remote = default(array[16, byte])
    let source = cast[ptr UncheckedArray[byte]](address)
    for i in 0..<16: remote[i] = source[i] # Borrow ends before the callback returns.
    attempts.ids[index] = client.accepting(now, stamp, remote, port)
    attempts.active[index] = true
  elif event == HandshakeSucceeded or event == HandshakeFailed:
    if not attempts.active[index]: # A missing start cannot acquire another attempt's ID.
      client.omit(stamp)
      return
    attempts.active[index] = false
    var identity = default(array[32, byte])
    if event == HandshakeSucceeded:
      var fields {.noinit.}: CertFields
      if der == nil or length == 0 or length > 8192 or
          parseCert(cast[ptr byte](der), length, addr fields) != 1 or
          fields.edKey != 1 or fields.keyLength != 32:
        client.omit(stamp) # Authentication succeeded but unusable metadata cannot become a failure.
        return
      for i in 0..<32: identity[i] = fields.key[i] # Native extraction initializes these owned fields.
    client.acceptOutcome(now, stamp, attempts.ids[index], identity, event == HandshakeSucceeded)

# The admitted-peer table copies authenticated public identities; no TLS/native pointer is retained.
type IncomingPeers* = object
  active, known: array[IncomingPeerSlots, bool]
  identities: array[IncomingPeerSlots, array[32, byte]]

# Admission only retains identity; a separately observed close produces JIP-3 event 27 exactly once.
proc observePeer*(client: var Client, peers: var IncomingPeers, slot: cuint,
    event: cint, der: ptr ConstByte, length: csize_t) =
  if slot >= cuint(IncomingPeerSlots): return # Native registration proves this bound; reject invalid callbacks.
  let index = int(slot)
  if event == PeerAccepted:
    peers.active[index] = true
    peers.known[index] = false # Slot reuse never inherits the previous peer's identity.
    peers.identities[index] = default(array[32, byte])
    var fields {.noinit.}: CertFields
    if der == nil or length == 0 or length > 8192 or
        parseCert(cast[ptr byte](der), length, addr fields) != 1 or
        fields.edKey != 1 or fields.keyLength != 32: return # Missing metadata cannot invent a public identity.
    for i in 0..<32: peers.identities[index][i] = fields.key[i] # Copy while native DER remains borrowed.
    peers.known[index] = true
  elif event == PeerClosed and peers.active[index]:
    peers.active[index] = false # Duplicate notifications cannot emit another closure for this lifetime.
    let stamp = eventTimestamp()
    if peers.known[index]:
      client.peerDisconnected(getMonoTime().ticks div 1_000_000, stamp, peers.identities[index])
    else:
      client.omit(stamp) # A real close with unavailable identity is a dropped observation.
    peers.known[index] = false
    peers.identities[index] = default(array[32, byte])
