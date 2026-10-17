## Optional trailing CLI controls for the existing bounded proof-peer command shape.
import std/[os, envvars, syncio, times, monotimes, strutils, base64]
import ./[wire, client, chain]
import ../quic/transport
export wire, client

# Only an exact trailing pair extends the existing CLI; malformed forms fail the original shape checks.
proc requested*(): bool = paramCount() >= 2 and paramStr(paramCount() - 1) == "--telemetry"
# Reject a missing endpoint, duplicate option or non-trailing placement before opening any endpoint.
proc validTelemetryOption*(): bool =
  var seen = false
  # Existing positional fixture modes remain untouched; only the explicit telemetry option is reserved.
  for i in 1..paramCount():
    if paramStr(i) == "--telemetry":
      if seen or i != paramCount() - 1: return false # Exactly one trailing option/value pair is supported.
      seen = true
  true

# Keep positional proof-peer parsing unchanged when the optional pair is present.
proc peerParamCount*(): int = paramCount() - (if requested(): 2 else: 0)

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

# Build registration from explicit JIP-4 configuration and the actual local certificate/socket.
proc setup*(client: var Client, certificate: string, port: uint16, ipv6: bool): bool {.raises.} =
  if not requested(): return true # Absence is the default and requires no configuration.
  let text = boundedFile(getEnv("RAGNAROK_TELEMETRY_CHAIN"), MaxChainBytes)
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
  configure(client, paramStr(paramCount()), parsed.value)

# Translate wall time for wire timestamps and monotonic time for retry/status deadlines.
proc observe*(client: var Client, peers: uint32) =
  if not requested(): return # Default runs do not even query telemetry clocks.
  let wall = getTime()
  let seconds = wall.toUnix - 1_735_732_800'i64
  # A clock before the Common Era cannot be represented; skip telemetry until corrected.
  if seconds < 0 or seconds > int64(high(uint64) div 1_000_000) - 1: return
  let timestamp = Timestamp(uint64(seconds) * 1_000_000 + uint64(wall.nanosecond div 1000))
  client.tick(getMonoTime().ticks div 1_000_000, timestamp, peers)
