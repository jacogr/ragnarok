# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional trailing CLI controls for the existing bounded proof-peer command shape.
##
## Exposes peer CLI option parsing, telemetry/RPC setup controls and connection/peer observation
## helpers. loadChainText reads one bounded startup snapshot shared by RPC and telemetry.

import std/[os, syncio, times, monotimes, strutils, base64]
import ./[wire, client, chain]
import ../quic/transport
import ../rpc/[server, protocol]
import ../chain/[parameters, genesis]
export wire, client

const
  Switches = ["--with-ui", "--with-rpc", "--with-telemetry"]
  Values = ["--telemetry", "--chain", "--rpc-port", "--ui-port", "--dev-ui-dir"]

# Locate reserved controls without consuming positional peer arguments.
proc optionStart(): int =
  for i in 1..paramCount(): # Both switches and pairs start the trailing configuration region.
    if paramStr(i) in Switches or paramStr(i) in Values: return i
  paramCount() + 1

# Only validated trailing controls reach the startup adapters.
proc optionValue(name: string): string =
  var i = optionStart()
  while i <= paramCount(): # Switches consume one argument; configuration pairs consume two.
    if paramStr(i) == name:
      if name in Switches: return "true"
      if i < paramCount(): return paramStr(i + 1)
      return ""
    i += (if paramStr(i) in Switches: 1 else: 2)
  ""

proc uiRequested*(): bool =
  ## UI activation also activates RPC; configuration alone never starts either listener.
  optionValue("--with-ui").len > 0

proc requested*(): bool =
  ## Telemetry requires an explicit enable switch, endpoint and chain configuration.
  optionValue("--with-telemetry").len > 0

# Decode decimal ports after CLI validation, using the documented service default when absent.
proc configuredPort(name: string, fallback: uint16): uint16 =
  let value = optionValue(name)
  if value.len == 0: return fallback
  var port = 0
  for c in value: port = port * 10 + ord(c) - ord('0') # Validation proves the range before narrowing.
  uint16(port)

proc rpcPort*(): uint16 =
  ## Zero disables RPC; UI implies RPC with the same configurable port.
  if not uiRequested() and optionValue("--with-rpc").len == 0: return 0
  configuredPort("--rpc-port", 19800)

proc uiPort*(): uint16 =
  ## Zero disables UI; the default enabled listener uses port 8888.
  if not uiRequested(): return 0
  configuredPort("--ui-port", 8888)

proc devUiDirectory*(): string =
  ## An absent override serves embedded assets; explicit relative roots use the process directory.
  optionValue("--dev-ui-dir")

proc validTelemetryOption*(): bool =
  ## Validate unique trailing switches/pairs, decimal ports and enabled-service dependencies.
  var seen: seq[string] = @[]
  var i = optionStart()
  while i <= paramCount(): # Reject duplicates, unknown controls and missing pair values before use.
    let name = paramStr(i)
    if name in seen: return false
    seen.add(name)
    if name in Switches:
      inc i # Enable switches have no value.
    elif name in Values:
      if i == paramCount(): return false
      let value = paramStr(i + 1)
      if value.len == 0 or value.startsWith("--"): return false
      if name in ["--rpc-port", "--ui-port"]: # Prove the bounded decimal conversion before narrowing.
        if value.len > 5: return false
        var port = 0
        for c in value:
          if c notin {'0'..'9'}: return false
          port = port * 10 + ord(c) - ord('0')
        if port notin 1..65535: return false
      i += 2
    else: return false # Unknown trailing configuration is never positional fixture input.
  if requested() and ("--telemetry" notin seen or "--chain" notin seen): return false
  if "--chain" in seen and not requested() and rpcPort() == 0: return false
  if uiRequested() and uiPort() == rpcPort(): return false # Independent listeners need distinct ports.
  true

proc peerParamCount*(): int =
  ## Keep the existing positional command parsing independent of trailing option order.
  optionStart() - 1

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

proc loadChainText*(): string {.raises.} =
  ## Read one startup snapshot for both RPC and telemetry so they cannot observe different file revisions.
  boundedFile(optionValue("--chain"), MaxChainBytes)

proc setupRpc*(rpc: var Server, role: string, text: string): bool =
  ## An explicit RPC chain must validate before opening the listener; missing configuration remains unavailable.
  var parameters = default(ParameterResult)
  var genesis = unavailableGenesis()
  if rpcPort() != 0 and optionValue("--chain").len > 0:
    parameters = configuredParameters(text)
    if not parameters.ok: return false # Fail startup rather than advertise a partial/default parameter set.
    genesis = configuredGenesis(text, parameters.value)
    if genesis.error == GenesisError.Invalid: return false # Reject an incomplete or malformed explicit genesis.
  rpc.start(rpcPort(), role, parameters, genesis, uiPort())

proc setup*(client: var Client, certificate: string, port: uint16, ipv6: bool,
    text: string): bool {.raises.} =
  ## Build registration from explicit JIP-4 configuration and the actual local certificate/socket.
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

proc observe*(client: var Client, peers: uint32) =
  ## Translate wall time for wire timestamps and monotonic time for retry/status deadlines.
  if not requested(): return # Default runs do not even query telemetry clocks.
  client.tick(getMonoTime().ticks div 1_000_000, eventTimestamp(), peers)

proc startDial*(client: var Client, identity: openArray[byte], port: uint16, ipv6: bool): EventId =
  ## The bounded proof dialer knows its pinned public identity and exact loopback destination before dialing.
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

proc finishDial*(client: var Client, attempt: EventId, authenticated: bool) =
  ## Settle an outgoing attempt exactly once; callers use native authentication evidence, not application success.
  if not requested(): return # Disabled telemetry does not query clocks or encode frames.
  client.dialOutcome(getMonoTime().ticks div 1_000_000, eventTimestamp(), attempt, authenticated)

proc finishConnection*(client: var Client, identity: openArray[byte]) =
  ## Copy the authenticated outgoing identity only after the caller observes a native connection close.
  if not requested() or identity.len != 32: return # Invalid or disabled peers cannot emit a closure.
  var key = default(array[32, byte])
  for i in 0..<32: key[i] = identity[i] # No caller storage is retained by the bounded exporter.
  client.peerDisconnected(getMonoTime().ticks div 1_000_000, eventTimestamp(), key)

type IncomingAttempts* = object ## Fixed correlation storage belongs to the peer and outlives native SSL destruction callbacks.
  active: array[IncomingHandshakeSlots, bool]
  ids: array[IncomingHandshakeSlots, EventId]

proc observeIncoming*(client: var Client, attempts: var IncomingAttempts, slot: cuint,
    event: cint, address: ptr ConstByte, port: uint16, der: ptr ConstByte, length: csize_t) =
  ## Copy callback data immediately; only bounded frames are queued here, never socket operations.
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

proc observePeer*(client: var Client, peers: var IncomingPeers, slot: cuint,
    event: cint, der: ptr ConstByte, length: csize_t) =
  ## Admission only retains identity; a separately observed close produces JIP-3 event 27 exactly once.
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
