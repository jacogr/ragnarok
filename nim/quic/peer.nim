## Isolated JAMNP-S authentication proof, using pinned LSQUIC and Chronos under ARC.
import std/[os, strutils]
from std/times import epochTime
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

# Capture only the owned identity bytes, never the async main frame that also owns this verifier.
proc peerVerifier(expected: seq[byte]): CertificateVerifier =
  CustomCertificateVerifier.init(
    proc(serverName: string, chain: seq[seq[byte]]): bool {.gcsafe.} =
    validPeer(chain, expected))

# Convert trusted fixture PEM text to owned bytes before the native library borrows them.
proc bytes(text: string): seq[byte] =
  result = newSeq[byte](text.len)
  for i in 0..<text.len: result[i] = byte(text[i]) # Preserve PEM bytes exactly.

# Fixed preimage map entry keeps this transport proof independent of unfinished state/database code.
const RequestHash = [17'u8, 192'u8, 231'u8, 155'u8, 113'u8, 195'u8, 151'u8, 108'u8, 205'u8, 12'u8,
    2'u8, 209'u8, 49'u8, 14'u8, 37'u8, 22'u8, 192'u8, 142'u8, 220'u8, 157'u8, 139'u8, 111'u8, 87'u8,
    204'u8, 214'u8, 128'u8, 214'u8, 58'u8, 77'u8, 142'u8, 114'u8, 218'u8]

# Soak fixture is one MiB of i mod 251, named by its independently computed Blake2b-256 digest.
const LargeSize = 1024 * 1024
const LargeHash = [138'u8, 90, 122, 157, 195, 207, 32, 62, 211, 116, 176, 161, 238, 169,
  48, 96, 26, 210, 172, 191, 226, 180, 188, 98, 207, 131, 222, 78, 229, 54, 82, 139]

# An explicit scenario keeps existing one-shot proof behaviour separate from the opt-in soak workload.
proc soaking(): bool =
  paramCount() == 8 and paramStr(8) == "soak"

# Generate a bounded owned response; no untrusted request controls its allocation size.
proc largeResponse(): seq[byte] =
  result = newSeq[byte](LargeSize + 4)
  result[2] = 16 # E4 length 0x00100000.
  # The fixture pattern is validated independently by every receiving implementation.
  for i in 0..<LargeSize: result[4 + i] = byte(i mod 251)

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

# Validate one request before selecting a fixture, with a read deadline local to this stream.
proc readRequest(stream: Stream): Future[seq[byte]] {.async.} =
  let kind = await readExact(stream, 1)
  if kind[0] != 143: raise newException(ValueError, "wrong stream kind") # Explicit CE selection.
  result = await readFrame(stream, 32)
  if result.len != 32: raise newException(ValueError, "wrong hash size") # No partial key lookup.
  await requireFin(stream)

# Serve one bounded fixture; soak errors retire only this stream and preserve sibling requests.
proc servePreimage(stream: Stream) {.async.} =
  var reading: Future[seq[byte]]
  var writing: Future[void]
  try:
    reading = readRequest(stream)
    # Missing FIN must release its handler while unrelated streams continue on the connection.
    if soaking() and not await reading.withTimeout(500.milliseconds):
      await reading.cancelAndWait()
      echo "REQUEST_TIMEOUT"
      raise newException(ValueError, "request timeout")
    let requested = await reading
    if requested == @RequestHash:
      await stream.write(@[3'u8, 0, 0, 0, 1, 2, 3]) # The original tiny fixture remains unchanged.
    elif soaking() and requested == @LargeHash:
      writing = stream.write(largeResponse())
      # An unread response exceeds 64 KiB credit; verify its write remains pending before readers resume.
      await sleepAsync(100.milliseconds)
      if not writing.finished:
        echo "BACKPRESSURE"
      await writing # Retain the owned payload until completion or cancellation.
    else:
      raise newException(ValueError, "unknown preimage") # No fabricated fixture response.
    await stream.close()
    if soaking(): echo "SERVER_HEALTHY" # Exact request, bounded reply and queued FIN complete.
  except CatchableError:
    stream.abort() # Reset the failed direction without freeing a live borrowed write buffer.
    if soaking():
      echo "STREAM_REJECTED" # The harness checks terminal counts and healthy sibling completion.
    else:
      raise # Preserve the original single-attempt rejection suite.
  finally:
    # Cancellation must settle nested tasks before their borrowed read/write storage is released.
    if reading != nil and not reading.finished: await reading.cancelAndWait()
    if writing != nil and not writing.finished: await writing.cancelAndWait()

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

# Exercise five valid streams and three intentional failures on one authenticated connection.
proc soakRequest(connection: Connection, index: int) {.async.} =
  # Late healthy requests prove the connection remains usable after malformed input and a timeout.
  if index >= 5: await sleepAsync(650.milliseconds)
  let stream = await connection.openStream()
  var request = @[143'u8, 32, 0, 0, 0]
  request.add(if index in [1, 2]: @LargeHash else: @RequestHash)
  # One unsupported CE kind must reset this stream without killing the other seven.
  if index == 3: request[0] = 144
  await stream.write(request)
  # The missing-FIN case must be rejected by the server's stream deadline.
  if index != 4: await stream.close()
  # Cancel while a large server write is parked behind receive credit.
  if index == 2:
    await sleepAsync(150.milliseconds)
    stream.abort()
    echo "CANCEL_OK"
    return
  # Withhold application reads long enough to exhaust the deliberately small transport window.
  if index == 1: await sleepAsync(350.milliseconds)
  var responseArrived = false
  try:
    let response = await readFrame(stream, LargeSize)
    responseArrived = true
    await requireFin(stream)
    if index in [3, 4]: raise newException(ValueError, "failed stream unexpectedly succeeded")
    # Large payload bytes are checked exactly, independent of sender chunking.
    if index == 1:
      if response.len != LargeSize: raise newException(ValueError, "wrong large extent")
      for i, b in response:
        if b != byte(i mod 251): raise newException(ValueError, "wrong large payload")
    elif response != @[1'u8, 2, 3]:
      raise newException(ValueError, "wrong preimage")
    echo "HEALTHY_OK"
  except CatchableError:
    stream.abort()
    if index in [3, 4] and not responseArrived:
      echo "EXPECTED_REJECT"
    else:
      raise # A healthy stream failure must fail the whole soak session.

# Drive eight independent CE streams concurrently, retaining all task futures until completion/cancellation.
proc exchange(connection: Connection, server: bool) {.async.} =
  var tasks: seq[Future[void]]
  try:
    for i in 0..<8:
      if server:
        let stream = await connection.incomingStream()
        tasks.add(servePreimage(stream)) # Each handler can await independently of other streams.
      else:
        if soaking():
          tasks.add(soakRequest(connection, i)) # Mixed tasks stay owned through cancellation.
        else:
          tasks.add(requestPreimage(connection)) # Original proof requests.
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
  let verifier = peerVerifier(expected) # The independent factory avoids an ARC frame/self-closure cycle.
  let cert = if paramStr(3) == "-": @[] else: bytes(readFile(paramStr(3)))
  let key = if paramStr(4) == "-": @[] else: bytes(readFile(paramStr(4)))
  let config = TLSConfig.new(cert, key, @[paramStr(6)], Opt.some(verifier))
  let deadline = parseInt(paramStr(7)).milliseconds
  var engine = DefaultQuicEngineConfig
  # Cap stream credit so the large fixture demonstrably parks writes during delayed reads.
  if soaking():
    engine.initialMaxStreamDataBidiLocal = Opt.some(65536'u32)
    engine.initialMaxStreamDataBidiRemote = Opt.some(65536'u32)
    engine.maxStreamFlowControlWindow = Opt.some(65536'u32)
  # The acceptor opens its listener before announcing readiness to the test orchestrator.
  if mode == "server":
    let server = QuicServer.new(config, engineConfig = engine)
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
    let client = QuicClient.new(config, engineConfig = engine)
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
  # The same process and ARC allocator survive every engine/socket lifecycle in the soak.
  if soaking():
    let rounds = parseInt(getEnv("RAGNAROK_SOAK_ROUNDS"))
    let gate = getEnv("RAGNAROK_SOAK_GATE")
    if rounds < 1 or rounds > 1000 or gate.len == 0: raise newException(ValueError, "invalid soak controls")
    for iteration in 0..rounds:
      let control = gate / (paramStr(1) & "-" & $iteration)
      let started = epochTime()
      # The external harness samples only after cleanup and releases each new session explicitly.
      while not fileExists(control):
        if epochTime() - started > 15: raise newException(ValueError, "soak gate timeout")
        waitFor sleepAsync(10.milliseconds)
      if iteration == rounds: break # Hold the final idle snapshot until the harness releases it.
      waitFor main()
      echo "ALLOC_BYTES ", getOccupiedMem(), " RESERVED_BYTES ", getTotalMem() # Distinguish live ARC storage from arena reserve.
      echo "SESSION_DONE ", iteration
  else:
    waitFor main() # Original one-shot proof.
except CatchableError as error:
  stderr.writeLine(error.msg) # Harness failures are visible and distinguishable from successful authentication.
  exitCode = 2
finally:
  cleanupLsquic() # Global cleanup follows all deferred client/listener shutdown.

quit(exitCode) # Exit only after native global cleanup on both success and rejection.
