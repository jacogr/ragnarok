## Isolated JAMNP-S authentication proof, using pinned LSQUIC and Chronos under ARC.
import std/[os, strutils]
import chronos, lsquic, results

{.compile: "../../interoperability/quic/cert_fields.c".}
# Owned primitive X.509 observations; the C helper performs no JAM policy.
type CertFields {.importc: "rq_cert_fields", header: "../../interoperability/quic/cert_fields.h",
    bycopy.} = object
  edKey {.importc: "ed_key".}, edSignature {.importc: "ed_signature".}: cint
  sanExtensions {.importc: "san_extensions".}, sanCount {.importc: "san_count".},
      sanDns {.importc: "san_dns".}: cint
  keyLength {.importc: "public_key_length".}, sanLength {.importc: "san_length".}: csize_t
  key {.importc: "public_key".}: array[32, byte]
  san: array[256, byte]
# Borrow DER only during extraction; all returned observations own their bounded bytes.
proc parseCert(der: ptr byte, length: csize_t, fields: ptr CertFields): cint {.importc: "rq_parse_cert",
    header: "../../interoperability/quic/cert_fields.h", cdecl, raises: [], gcsafe.}

# Literal little-endian radix-32 formula from the pinned specification, including its unusual alphabet.
proc peerName(key: array[32, byte]): string {.raises: [].} =
  const alphabet = "$abcdefghijklmnopqrstuvwxyz234567"
  result = "$e"
  # Emit 52 groups least significant first; bits beyond the 256-bit key are zero.
  for group in 0..<52:
    var index = 0
    for bit in 0..<5:
      let position = group * 5 + bit
      if position < 256: index = index or (int((key[position div 8] shr (position mod 8)) and
          1) shl bit) # Zero-extend final group.
    result.add(alphabet[index])

# Validate identity entirely in Nim; self-signed PKI trust is replaced by key/SAN consistency and optional expected identity.
proc validPeer(chain: seq[seq[byte]], expected: seq[byte]): bool {.raises: [], gcsafe.} =
  # Enforce bounded certificate resources before passing untrusted bytes to the TLS parser.
  if chain.len == 0 or chain.len > 8 or chain[0].len == 0: return false
  var fields: CertFields
  if parseCert(unsafeAddr chain[0][0], csize_t(chain[0].len), addr fields) !=
      1: return false # Strict DER extraction.
  # Both the key and certificate signature algorithm must be Ed25519, with exactly one DNS SAN.
  if fields.edKey != 1 or fields.edSignature != 1 or fields.keyLength != 32 or
      fields.sanExtensions != 1 or fields.sanCount != 1 or fields.sanDns != 1: return false
  let name = peerName(fields.key)
  if fields.sanLength != csize_t(name.len): return false # Exact bytes, not C-string prefix comparison.
  for i in 0..<name.len:
    if fields.san[i] != byte(name[i]): return false # Reject altered names and embedded NULs.
  # Dialers require an expected server key; acceptors can also pin a fixture client key for the proof.
  if expected.len > 0:
    if expected.len != 32: return false # No narrowing of malformed identity input.
    for i in 0..<32:
      if expected[i] != fields.key[i]: return false # Exact peer identity.
  true

# Convert trusted fixture PEM text to owned bytes before the native library borrows them.
proc bytes(text: string): seq[byte] =
  result = newSeq[byte](text.len)
  for i in 0..<text.len: result[i] = byte(text[i]) # Preserve PEM bytes exactly.

# Fixed preimage map entry keeps this transport proof independent of unfinished state/database code.
const RequestHash = [17'u8, 192'u8, 231'u8, 155'u8, 113'u8, 195'u8, 151'u8, 108'u8, 205'u8, 12'u8,
    2'u8, 209'u8, 49'u8, 14'u8, 37'u8, 22'u8, 192'u8, 142'u8, 220'u8, 157'u8, 139'u8, 111'u8, 87'u8,
    204'u8, 214'u8, 128'u8, 214'u8, 58'u8, 77'u8, 142'u8, 114'u8, 218'u8]

# Read exactly a bounded frame component, rejecting premature FIN without inventing missing bytes.
proc readExact(stream: Stream, size: int): Future[seq[byte]] {.async.} =
  result = newSeq[byte](size)
  var offset = 0
  while offset < size:
    let received = await stream.readOnce(result.toOpenArray(offset, size - 1))
    if received == 0: raise newException(ValueError, "premature FIN") # Missing bytes cannot be padded.
    offset += received

# Validate a complete E4 header against a caller ceiling before host conversion or allocation.
proc checkedLength(header: openArray[byte], maximum: int): tuple[ok: bool, size: int] {.raises: [].} =
  if header.len != 4 or maximum < 0: return (false, 0) # Invalid headers/policies expose no extent.
  var claimed = 0'u64
  for i in 0..<4: claimed = claimed or (uint64(header[i]) shl (8 * i)) # Exact little-endian value.
  if claimed > uint64(maximum): return (false, 0) # Limit proof precedes narrowing or allocation.
  (true, int(claimed))

# Read one framed message with an explicit resource ceiling before allocating its payload.
proc readFrame(stream: Stream, maximum: int): Future[seq[byte]] {.async.} =
  let header = await readExact(stream, 4)
  let extent = checkedLength(header, maximum)
  if not extent.ok: raise newException(ValueError, "message limit") # Never allocate an unchecked claimed size.
  return await readExact(stream, extent.size)

# Require FIN after the single message, without accepting trailing bytes as another response.
proc requireFin(stream: Stream) {.async.} =
  var byteBuffer: array[1, byte]
  if (await stream.readOnce(byteBuffer)) != 0: raise newException(ValueError,
      "trailing message") # Protocol has exactly one message per direction.

# A CE 143 server reads its kind/hash/FIN then sends a framed fixture preimage and its own FIN.
proc servePreimage(stream: Stream) {.async.} =
  try:
    let kind = await readExact(stream, 1)
    if kind[0] != 143: raise newException(ValueError, "wrong stream kind") # No implicit protocol selection.
    let requested = await readFrame(stream, 32)
    if requested.len != 32: raise newException(ValueError, "wrong hash size") # Hash is fixed width.
    for i in 0..<32:
      if requested[i] != RequestHash[i]: raise newException(ValueError,
          "unknown preimage") # Bounded fixture map lookup.
    await requireFin(stream)
    await stream.write(@[3'u8, 0, 0, 0, 1, 2, 3])
    await stream.close() # Half-close writing after the response; request reading is already finished.
  except CatchableError:
    stream.abort() # Unknown/malformed/cancelled requests are rejected with reset, never a fabricated response.
    raise

# Open a CE 143 request with deliberately split kind/length writes and validate the exact response plus FIN.
proc requestPreimage(connection: Connection) {.async.} =
  let stream = await connection.openStream()
  let attack = if paramCount() == 8: paramStr(8) else: "valid"
  var request = @[143'u8, 32, 0, 0, 0]
  request.add(@RequestHash)
  # Inject malformed application frames only after normal transport authentication.
  case attack
  of "valid", "no-fin": discard # Normal bytes; no-fin delays the request half-close.
  of "bad-kind": request[0] = 144 # Unsupported protocol selector.
  of "oversize":
    for i in 1..4: request[i] = 255 # Claimed allocation must be rejected before payload handling.
  of "unknown": request[5] = request[5] xor 1 # Missing fixture map entry.
  of "truncated": request.setLen(36) # FIN before all declared hash bytes.
  of "trailing": request.add(0) # Extra content beyond the single framed request.
  else: raise newException(ValueError, "unknown test case") # Never silently substitute a valid scenario.
  await stream.write(request[0..0])
  await stream.write(request[1..2])
  await stream.write(request[3..^1])
  if attack != "no-fin": await stream.close() # Request FIN must not prevent reading the response direction.
  let response = await readFrame(stream, 1024)
  if response != @[1'u8, 2, 3]: raise newException(ValueError, "wrong preimage") # Compare actual payload bytes.
  await requireFin(stream)

# Drive eight independent CE streams concurrently, retaining all task futures until completion/cancellation.
proc exchange(connection: Connection, server: bool) {.async.} =
  var tasks: seq[Future[void]]
  try:
    for i in 0..<8:
      if server:
        let stream = await connection.incomingStream()
        tasks.add(servePreimage(stream)) # Each handler can await independently of other streams.
      else:
        tasks.add(requestPreimage(connection)) # Spawn all requests before awaiting their replies.
    for task in tasks: await task # Complete every handler/request, not just the first stream.
  finally:
    for task in tasks:
      if not task.finished: await task.cancelAndWait() # No orphan callbacks/futures after timeout or rejection.

# Bound the whole exchange so a peer that never sends FIN cannot retain tasks indefinitely.
proc runExchange(connection: Connection, server: bool, deadline: Duration) {.async.} =
  let work = exchange(connection, server)
  if not await work.withTimeout(deadline):
    await work.cancelAndWait() # Retire all child tasks before closing the transport.
    raise newException(ValueError, "exchange timeout")
  await work
  echo "EXCHANGE_OK 8"

# Run one bounded authentication attempt, releasing transport resources before global shutdown.
proc main() {.async.} =
  if paramCount() notin [7, 8]: raise newException(ValueError,
      "mode port cert key expected-key alpn timeout-ms") # Explicit trusted CLI.
  let mode = paramStr(1)
  let endpoint = initTAddress("127.0.0.1:" & paramStr(2))
  let expected = if paramStr(5) == "-": @[] else: bytes(readFile(paramStr(5)))
  # Dialers must name the server identity before authentication; acceptors may discover a consistent key.
  if mode == "client" and expected.len != 32: raise newException(ValueError, "expected server key required")
  let verifier: CertificateVerifier = CustomCertificateVerifier.init(
    proc(serverName: string, chain: seq[seq[byte]]): bool {.gcsafe.} =
    # SAN policy is tied to the key; SNI is not an ordinary public DNS trust anchor.
    validPeer(chain, expected))
  let cert = if paramStr(3) == "-": @[] else: bytes(readFile(paramStr(3)))
  let key = if paramStr(4) == "-": @[] else: bytes(readFile(paramStr(4)))
  let config = TLSConfig.new(cert, key, @[paramStr(6)], Opt.some(verifier))
  let deadline = parseInt(paramStr(7)).milliseconds
  # The acceptor opens its listener before announcing readiness to the test orchestrator.
  if mode == "server":
    let server = QuicServer.new(config)
    let listener = server.listen(endpoint)
    defer: await listener.stop()
    echo "READY"
    let incoming = listener.accept()
    if not await incoming.withTimeout(deadline):
      await incoming.cancelAndWait() # Do not leave a pending accept retaining the listener.
      raise newException(ValueError, "authentication timeout")
    let connection = await incoming
    defer: connection.close() # Retire the connection even when a framed exchange fails.
    echo "AUTH_OK"
    await runExchange(connection, mode == "server", deadline)
    await sleepAsync(100.milliseconds)
    connection.close()
  elif mode == "client":
    let client = QuicClient.new(config)
    defer: await client.stop()
    let dialing = client.dial(endpoint)
    if not await dialing.withTimeout(deadline):
      await dialing.cancelAndWait() # Native callbacks must finish before temporary ownership is released.
      raise newException(ValueError, "authentication timeout")
    let connection = await dialing
    defer: connection.close() # Retire the connection even when a framed exchange fails.
    echo "AUTH_OK"
    await runExchange(connection, mode == "server", deadline)
    await sleepAsync(100.milliseconds)
    connection.close()
  else:
    raise newException(ValueError, "unknown role") # No guessed endpoint behavior.

# Arbitrary-input entry point exercises strict DER policy and bounded E4 decoding without network sockets.
proc fuzzPeer(input: openArray[byte]) {.raises: [].} =
  discard validPeer(@[@input], @[])
  let extent = checkedLength(input, 64)
  if extent.ok: doAssert input.len == 4 and extent.size >= 0 and extent.size <= 64 # Exposed extents are bounded.

# Deterministic malformed-input coverage makes the parsers independently testable before any TLS setup.
proc selfTest() =
  doAssert checkedLength([0'u8, 0, 0, 0], 0) == (true, 0)
  doAssert not checkedLength([255'u8, 255, 255, 255], 1024).ok
  var state = 0x51554943'u64
  for iteration in 0..<10000:
    var input: array[128, byte]
    for b in input.mitems:
      state = state xor (state shl 13)
      state = state xor (state shr 7)
      state = state xor (state shl 17)
      b = byte(state and 255) # Reproducible fuzz bytes, not cryptographic randomness.
    fuzzPeer(input.toOpenArray(0, iteration mod 129 - 1))
  echo "Nim QUIC selftest: 10000 malformed DER/header cases passed"

# Standalone parser tests need no engine/global transport state or socket permission.
if paramCount() == 1 and paramStr(1) == "--selftest":
  selfTest()
  quit(0)

initializeLsquic()
var exitCode = 0
try:
  waitFor main() # Drive futures through a single I/O loop, without per-stream threads.
except CatchableError as error:
  stderr.writeLine(error.msg) # Harness failures are visible and distinguishable from successful authentication.
  exitCode = 2
finally:
  cleanupLsquic() # Global cleanup follows all deferred client/listener shutdown.

quit(exitCode) # Exit only after native global cleanup on both success and rejection.
