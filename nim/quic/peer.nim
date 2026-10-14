## JAMNP-S identity and CE 143 policy in Nim, over the same small LSQUIC/TLS C bridge used by Odin.
## One synchronous owner drives nonblocking UDP readiness and deadlines without external Nim dependencies.
import std/[os, strutils, monotimes, times]
import ./transport

type
  # One bounded native stream owns application storage until its final close callback.
  StreamState = object
    handle: NativeStream
    received, sending: seq[byte]
    receivedLength, sendLength, sendOffset: int
    readFin, writeFin, counted, paused, blocked: bool
    started: MonoTime
    attack: string
  # This stack owner outlives every synchronous native callback and its selector/engine teardown.
  Peer = object
    transport: Transport
    expected: seq[byte]
    server, failed, stopping: bool
    streams: array[16, StreamState]
    completed, opened, healthy, rejected, cancelled: int
    attack: string

# Fixture preimage key is independently checked by the shared harness; no unfinished database/state code is involved.
const RequestHash = [17'u8, 192, 231, 155, 113, 195, 151, 108, 205, 12, 2, 209, 49, 14, 37, 22,
  192, 142, 220, 157, 139, 111, 87, 204, 214, 128, 214, 58, 77, 142, 114, 218]
# Bounded one-MiB soak fixture is i mod 251, named by its independently computed Blake2b-256 digest.
const LargeSize = 1024 * 1024
const LargeHash = [138'u8, 90, 122, 157, 195, 207, 32, 62, 211, 116, 176, 161, 238, 169,
  48, 96, 26, 210, 172, 191, 226, 180, 188, 98, 207, 131, 222, 78, 229, 54, 82, 139]

# Literal least-significant-first radix-32 formula from the pinned JAMNP-S specification.
proc peerName(key: array[32, byte]): array[54, byte] {.raises: [].} =
  const alphabet = "$abcdefghijklmnopqrstuvwxyz234567"
  result[0] = byte('$')
  result[1] = byte('e')
  # The final group zero-extends the Ed25519 key beyond 256 bits.
  for group in 0..<52:
    var index = 0
    # Gather this group's five bits in little-endian order, not RFC base32 order.
    for bit in 0..<5:
      let position = group * 5 + bit
      if position < 256: index = index or (int((key[position div 8] shr (position mod 8)) and
          1) shl bit) # Only actual key bits contribute.
    result[2 + group] = byte(alphabet[index])

# Validate copied primitive certificate observations and optional expected identity entirely in Nim.
proc validPeer(der: ptr byte, length: csize_t, expected: openArray[byte]): bool {.raises: [].} =
  var fields: CertFields
  # DER is borrowed only for bounded synchronous extraction; no TLS-owned pointer is retained.
  if parseCert(der, length, addr fields) != 1: return false
  # Require both Ed25519 algorithms and exactly one DNS SAN.
  if fields.edKey != 1 or fields.edSignature != 1 or fields.keyLength != 32 or
      fields.sanExtensions != 1 or fields.sanCount != 1 or fields.sanDns != 1: return false
  let name = peerName(fields.key)
  # Exact byte length prevents prefix and embedded-NUL acceptance.
  if fields.sanLength != csize_t(name.len): return false
  # Every DNS SAN byte must be the exact key-derived identity.
  for i, value in name:
    if fields.san[i] != value: return false # Reject altered names.
  # Dialers pin the server key; acceptors may discover a consistent unknown peer.
  if expected.len > 0:
    if expected.len != 32: return false # No narrowing of malformed trusted identity input.
    for i in 0..<32:
      if expected[i] != fields.key[i]: return false # Compare full public keys.
  true

# Native TLS verification borrows only the retained peer's expected key; no closure or async frame is captured.
proc verifyPeer(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  let peer = cast[ptr Peer](user)
  cint(validPeer(cast[ptr byte](der), length, peer.expected))

# Validate a complete E4 header before host conversion, indexing or accepting any payload extent.
proc checkedLength(header: openArray[byte], maximum: int): tuple[ok: bool, size: int] {.raises: [].} =
  # Partial headers and invalid policies expose no usable extent.
  if header.len != 4 or maximum < 0: return (false, 0)
  var claimed = 0'u64
  # Assemble exactly four little-endian bytes without a host-width-dependent cast.
  for i in 0..<4: claimed = claimed or (uint64(header[i]) shl (8 * i))
  # Prove the bounded conversion before allocation or payload access.
  if claimed > uint64(maximum): return (false, 0)
  (true, int(claimed))

# Settle one stream exactly once; soak rejections preserve healthy siblings on the same connection.
proc finishStream(peer: ptr Peer, state: ptr StreamState, good: bool) {.raises: [].} =
  # Reset and close notifications may report the same terminal state more than once.
  if state.counted: return
  state.counted = true
  # A healthy result means exact request/reply bytes and the required FIN were validated.
  if good:
    inc peer.completed
    inc peer.healthy
    if peer.attack == "soak": echo (if peer.server: "SERVER_HEALTHY" else: "HEALTHY_OK") # Expose verified outcomes.
  elif peer.attack == "soak":
    # An intentionally bad stream retires only its own buffers/callbacks.
    inc peer.completed
    inc peer.rejected
    echo (if peer.server: "STREAM_REJECTED" else: "EXPECTED_REJECT")
  else:
    # The one-shot rejection matrix fails the attempted application exchange.
    peer.failed = true

# Check incremental framing and fixture payloads; success requires one exact message followed by FIN.
proc frameExtent(peer: ptr Peer, state: ptr StreamState): tuple[complete, valid: bool] {.raises: [].} =
  let start = if peer.server: 1 else: 0
  # The request's first byte selects CE 143 explicitly.
  if peer.server and state.receivedLength > 0 and state.received[0] != 143: return (false, false)
  # A partial header remains pending only while the peer has not ended its direction.
  if state.receivedLength < start + 4: return (false, not state.readFin)
  let maximum = if peer.server: 32 elif peer.attack == "soak": LargeSize else: 1024
  let length = checkedLength(state.received.toOpenArray(start, start + 3), maximum)
  # Reject impossible declared payloads before any narrowing/indexing.
  if not length.ok: return (false, false)
  let extent = start + 4 + length.size
  # One message per direction forbids trailing bytes, even before FIN arrives.
  if state.receivedLength > extent: return (false, false)
  if not state.readFin: return (false, true) # Complete bytes without FIN are still pending.
  if state.receivedLength != extent: return (false, false) # FIN before the declared payload is truncation.
  # Requests select only exact fixture hash keys, never a default/missing map entry.
  if peer.server:
    if length.size != 32: return (false, false) # Preimage keys have fixed width.
    let wanted = if peer.attack == "soak" and state.received[5] == LargeHash[
        0]: LargeHash else: RequestHash
    for i, value in wanted:
      if state.received[5 + i] != value: return (false, false) # Complete hash equality.
  else:
    # Replies must contain the exact expected tiny/large fixture, independently of transport chunking.
    let size = if state.attack == "slow": LargeSize else: 3
    if length.size != size: return (false, false)
    for i in 0..<size:
      let wanted = if size == LargeSize: byte(i mod 251) else: byte(i + 1)
      if state.received[4 + i] != wanted: return (false, false) # Compare every byte of the preimage.
  (true, true)

# Initialize bounded request/reply storage on a new native stream; no network length chooses an allocation.
proc newStream(peer: ptr Peer, state: ptr StreamState, handle: NativeStream) {.raises: [].} =
  state[] = StreamState(handle: handle, started: getMonoTime(), attack: peer.attack)
  state.received = newSeq[byte](if peer.server or peer.attack != "soak": 1050 else: LargeSize + 5)
  # The acceptor waits for one exact request before allocating its trusted fixture response.
  if peer.server: return
  state.sending = newSeq[byte](64)
  state.sending[0] = 143
  state.sending[1] = 32
  var wanted = RequestHash
  # Five healthy requests share one connection with cancellation, bad kind and missing FIN.
  if peer.attack == "soak":
    case peer.opened
    of 1: state.attack = "slow"; wanted = LargeHash # Park consumption until the window fills.
    of 2: state.attack = "cancel"; wanted = LargeHash # Cancel a genuinely pending server write.
    of 3: state.attack = "bad-kind" # Reject only this protocol selector.
    of 4: state.attack = "no-fin" # Exercise the acceptor's stream-local deadline.
    else: state.attack = "valid" # Remaining requests must complete normally.
    inc peer.opened
  # Populate the trusted request key after selecting this stream's lifecycle scenario.
  for i, value in wanted: state.sending[5 + i] = value
  state.sendLength = 37
  # Malformed test bytes are introduced only after transport authentication.
  case state.attack
  of "valid", "slow", "cancel", "no-fin": discard # Correct wire bytes with different read/FIN schedules.
  of "bad-kind": state.sending[0] = 144 # Unsupported CE selector.
  of "oversize":
    for i in 1..4: state.sending[i] = 255 # Invalid claimed extent is rejected before payload acceptance.
  of "unknown": state.sending[5] = state.sending[5] xor 1 # Missing fixture key.
  of "truncated": state.sendLength = 36 # End before all declared hash bytes exist.
  of "trailing": state.sendLength = 38 # One extra byte violates the one-message rule.
  else:
    peer.failed = true
    streamAbort(handle)
    return # Unknown trusted selectors must never silently become valid requests.
  # Paused application reads exhaust flow-control credit while sibling streams continue.
  if state.attack in ["slow", "cancel"]:
    state.paused = true
    wantRead(handle, 0)
  wantWrite(handle, 1)

# Read all available stream bytes into stable bounded storage, preserving state across would-block events.
proc readStream(peer: ptr Peer, state: ptr StreamState) {.raises: [].} =
  # A slow/cancelled reader deliberately withholds application consumption.
  if state.paused: return
  while true:
    # A full buffer cannot accept another byte or fabricate a clean FIN.
    if state.receivedLength == state.received.len:
      finishStream(peer, state, false)
      streamAbort(state.handle)
      return
    let available = state.received.len - state.receivedLength
    let got = streamRead(state.handle, addr state.received[state.receivedLength], csize_t(available))
    # Would-block keeps the frame pending, with its same owned buffers.
    if got == -2: return
    if got < 0 or got > int64(available):
      finishStream(peer, state, false)
      streamAbort(state.handle)
      return # A reset or impossible native extent settles only this stream.
    # Zero is real FIN, never padding for a truncated message.
    if got == 0: state.readFin = true
    else: state.receivedLength += int(got) # Accumulate partial reads within the proved capacity.
    let extent = frameExtent(peer, state)
    # Protocol failures cannot leave a read handler or reply buffer pending.
    if not extent.valid:
      finishStream(peer, state, false)
      streamAbort(state.handle)
      return
    if extent.complete:
      wantRead(state.handle, 0) # Stop repeated EOF callbacks after validated FIN.
      # Only a validated fixture key can select a bounded server response allocation.
      if peer.server:
        let size = if peer.attack == "soak" and state.received[5] == LargeHash[0]: LargeSize else: 3
        state.sending = newSeq[byte](size + 4)
        # Encode trusted E4 bytes before the fixture payload, independently of the C bridge.
        for i in 0..<4: state.sending[i] = byte((size shr (8 * i)) and 255)
        for i in 0..<size: state.sending[4 + i] = if size == LargeSize: byte(i mod 251) else: byte(
            i + 1) # Fixture bytes.
        state.sendLength = state.sending.len
        wantWrite(state.handle, 1)
      else:
        # The client has checked the exact payload and response FIN.
        finishStream(peer, state, true)
      return

# Preserve unsent application bytes across partial writes and flow-control stalls; flush does not imply FIN.
proc writeStream(peer: ptr Peer, state: ptr StreamState) {.raises: [].} =
  # Keep the same owned write buffer until every byte is accepted or the native stream closes.
  while state.sendOffset < state.sendLength:
    let remaining = state.sendLength - state.sendOffset
    let sent = streamWrite(state.handle, addr state.sending[state.sendOffset], csize_t(remaining))
    # Would-block leaves this stream subscribed so transport credit can resume its write later.
    if sent in [-2'i64, 0'i64]: return
    if sent < 0 or sent > int64(remaining):
      finishStream(peer, state, false)
      streamAbort(state.handle)
      return # A failed/invalid write settles its own stream.
    state.sendOffset += int(sent)
  # Explicit flush transmits a no-FIN request too, allowing the receiver to enforce its deadline.
  if streamFlush(state.handle) != 0:
    finishStream(peer, state, false)
    streamAbort(state.handle)
    return
  wantWrite(state.handle, 0)
  # FIN half-closes writing while response reads stay active.
  if not state.writeFin and (peer.server or state.attack != "no-fin"):
    streamFin(state.handle)
    state.writeFin = true
    if peer.server: finishStream(peer, state, true) # Exact request and queued reply FIN complete server work.

# Native callbacks borrow this peer synchronously; only native close releases application buffers.
proc onStream(user: pointer, handle: NativeStream, event: cint) {.cdecl, raises: [].} =
  let peer = cast[ptr Peer](user)
  var state: ptr StreamState
  # Resolve a currently retained native handle before accessing its application buffers.
  for slot in peer.streams.mitems:
    if slot.handle == handle: state = addr slot; break # Unique live stream ownership.
  if event == 0:
    # The fixed slot ceiling bounds concurrent requests and all associated application storage.
    for slot in peer.streams.mitems:
      if slot.handle == NativeStream(nil): state = addr slot; break # Allocate only a retired slot.
    if state == nil:
      peer.failed = true
      streamAbort(handle)
      return # Never grow an unbounded stream queue.
    newStream(peer, state, handle)
    return
  # Unknown native events cannot dereference released framing state.
  if state == nil: peer.failed = true; return
  if event == 3:
    # A premature native close rejects unsettled work unless teardown is already retiring the owner.
    if not state.counted and not peer.stopping: finishStream(peer, state, false)
    state[] = StreamState() # ARC releases both buffers; the slot holds no closure/reference back to Peer.
    return
  if event == 4:
    # A directional reset settles pending reads and writes before final native close releases their storage.
    if not peer.stopping: finishStream(peer, state, false)
    streamAbort(handle)
    return
  # No new application work starts during teardown or after a completed client response.
  if peer.stopping or (state.counted and not peer.server): return
  case event
  of 1: readStream(peer, state) # Read readiness preserves incremental framing across callbacks.
  of 2: writeStream(peer, state) # Write readiness preserves partial-write offsets across callbacks.
  else: peer.failed = true # Undefined bridge events are explicit integration failures.

# Stream-local lifecycle deadlines run on the same selector thread as native transport timers.
proc soakTick(peer: ptr Peer) {.raises: [].} =
  # Only live, unsettled streams own deadline work; close callbacks may recycle slots synchronously.
  for state in peer.streams.mitems:
    if state.handle == NativeStream(nil) or state.counted: continue # Retired streams have no pending timer.
    let elapsed = (getMonoTime() - state.started).inMilliseconds
    if peer.server:
      # A complete hash without request FIN must not retain its handler indefinitely.
      if not state.readFin and elapsed > 500:
        echo "REQUEST_TIMEOUT"
        finishStream(peer, addr state, false)
        streamAbort(state.handle)
      elif state.sendLength > 65536 and state.sendOffset < state.sendLength and
          not state.blocked and elapsed > 100:
        # The pending large write proves real flow-control backpressure, not an artificial sleep alone.
        state.blocked = true
        echo "BACKPRESSURE"
    elif state.attack == "cancel" and elapsed > 150:
      # Cancel while the remote large write is parked behind withheld receive credit.
      state.counted = true
      inc peer.completed
      inc peer.cancelled
      echo "CANCEL_OK"
      streamAbort(state.handle)
    elif state.attack == "slow" and state.paused and elapsed > 350:
      # Resume application consumption so the native stream window can advance again.
      state.paused = false
      wantRead(state.handle, 1)

# Own one bounded authentication/exchange attempt and release readiness before native callback destruction.
proc runPeer(): bool =
  # Trusted CLI inputs still have explicit shape and narrowing checks.
  if paramCount() notin [7, 8]: raise newException(ValueError, "mode port cert key expected-key alpn timeout-ms")
  let port = parseInt(paramStr(2))
  let timeout = parseInt(paramStr(7))
  if port < 1 or port > 65535 or timeout < 1 or timeout > 10000: return false # Guard host-to-native conversions.
  let server = paramStr(1) == "server"
  if not server and paramStr(1) != "client": return false # Never infer an unknown role.
  var peer = Peer(server: server, attack: if paramCount() == 8: paramStr(8) else: "valid")
  # Expected identity bytes remain owned by Peer across all TLS verification callbacks.
  if paramStr(5) != "-":
    let text = readFile(paramStr(5))
    if text.len != 32: return false # Fixture identity has exact Ed25519 width.
    peer.expected = newSeq[byte](32)
    for i in 0..<32: peer.expected[i] = byte(text[i]) # Copy public identity bytes, not PEM strings.
  if not server and peer.expected.len != 32: return false # Every dialer pins the server identity.
  # Cleanup must also run after poll/setup failures; both stack owners remain alive until final native callbacks finish.
  defer:
    peer.stopping = true
    closeTransport(peer.transport)
  if not openTransport(peer.transport, server, peer.attack == "soak", uint16(port), paramStr(3),
      paramStr(4), paramStr(6), addr peer, verifyPeer,
          onStream): return false # No partially initialized endpoint is used.
  if server: echo "READY" # Announce only after listener binding and native setup.
  elif not connectTransport(peer.transport, uint16(port)): return false # Dial setup failed before authentication.
  let started = getMonoTime()
  var authenticated, opened: bool
  # One selector loop services all streams, UDP reads and LSQUIC/application deadlines.
  while not peer.failed and peer.completed < 8 and (getMonoTime() - started).inMilliseconds < timeout:
    let status = transportStatus(peer.transport)
    if status < 0: break # Authentication or persistent UDP failure settles this bounded attempt.
    if status == 1 and not authenticated:
      echo "AUTH_OK"
      authenticated = true
    if authenticated and not server and not opened:
      # Open concurrent requests before waiting for replies; the soak introduces three later healthy siblings.
      opened = true
      for index in 0..<(if peer.attack == "soak": 5 else: 8): openStream(peer.transport)
    if peer.attack == "soak":
      soakTick(addr peer)
      # Late healthy requests prove continued service after malformed input, cancellation and missing FIN.
      if not server and opened and peer.opened == 5 and (getMonoTime() - started).inMilliseconds > 650:
        for index in 0..<3: openStream(peer.transport)
    if not pollTransport(peer.transport): break # Selector/UDP failure cannot become a successful exchange.
  # A receive cycle may complete authentication and all requests before the loop observes status again.
  if transportStatus(peer.transport) == 1 and not authenticated:
    echo "AUTH_OK"
    authenticated = true
  result = authenticated and not peer.failed and peer.completed == 8
  # Client success counts must distinguish exactly five healthy, two rejected and one cancelled stream.
  if result and peer.attack == "soak" and not server:
    result = peer.healthy == 5 and peer.rejected == 2 and peer.cancelled == 1
  if result:
    echo "EXCHANGE_OK 8" # Authentication alone is insufficient without all terminal application outcomes.
    let grace = getMonoTime()
    # Drain final handshake/FIN packets before removing readiness and destroying native stream state.
    while (getMonoTime() - grace).inMilliseconds < 100:
      if not pollTransport(peer.transport): return false # Final I/O errors are still observable.
  else:
    # Print only framing counts/lifecycle state, never private-key or certificate buffer contents.
    echo "proof rejected or timed out ", peer.completed, " ", peer.healthy, " ", peer.rejected, " ", peer.cancelled

# Fuzz incremental framing and DER policy without creating a UDP endpoint or TLS engine.
proc fuzzPeer(input: openArray[byte], server, fin: bool) {.raises: [].} =
  let data = if input.len > 0: unsafeAddr input[0] else: nil
  discard validPeer(data, csize_t(input.len), [])
  var peer = Peer(server: server)
  var state = StreamState(received: newSeq[byte](input.len), receivedLength: input.len, readFin: fin)
  # Retain a distinct owned framing buffer for the parser's complete call.
  for i, value in input: state.received[i] = value
  let extent = frameExtent(addr peer, addr state)
  # Complete frames are bounded, exact and cleanly terminated.
  if extent.complete: doAssert extent.valid and fin and input.len == (if server: 37 else: 7)
  if fin and input.len < (if server: 5 else: 4): doAssert not extent.valid # Partial-header EOF is immediate rejection.

# Deterministic malformed-input coverage remains independently testable before native transport setup.
proc selfTest() =
  doAssert checkedLength([0'u8, 0, 0, 0], 0) == (true, 0)
  doAssert not checkedLength([255'u8, 255, 255, 255], 1024).ok
  # Known valid frames exercise every partial prefix with and without FIN, complementing random malformed inputs.
  var request = newSeq[byte](37)
  request[0] = 143
  request[1] = 32
  for i, value in RequestHash: request[5 + i] = value # Exact trusted fixture request.
  let response = @[3'u8, 0, 0, 0, 1, 2, 3]
  # A prefix is pending while open, rejected at premature FIN, and complete only at exact FIN.
  for server in [true, false]:
    let wire = if server: request else: response
    var peer = Peer(server: server)
    for length in 0..wire.len:
      var frame = StreamState(received: wire, receivedLength: length)
      doAssert frameExtent(addr peer, addr frame) == (false, true)
      frame.readFin = true
      let extent = frameExtent(addr peer, addr frame)
      doAssert extent == (length == wire.len, length == wire.len)
  var state = 0x51554943'u64
  # Xorshift produces reproducible parser coverage bytes, not cryptographic randomness.
  for iteration in 0..<10000:
    var input: array[128, byte]
    for value in input.mitems:
      state = state xor (state shl 13)
      state = state xor (state shr 7)
      state = state xor (state shl 17)
      value = byte(state and 255)
    fuzzPeer(input.toOpenArray(0, iteration mod 129 - 1), iteration mod 2 == 0, iteration mod 3 == 0)
  echo "Nim QUIC selftest: 10000 malformed DER/frame cases passed"

# CLI entry point returns through all normal ARC/native teardown before process exit.
proc main(): int =
  try:
    # Parser tests create no native transport or socket.
    if paramCount() == 1 and paramStr(1) == "--selftest":
      selfTest()
      return 0
    # Probe the real selector backend independently of TLS setup.
    if paramCount() == 1 and paramStr(1) == "--io-selftest":
      ioSelfTest()
      return 0
    if paramCount() == 8 and paramStr(8) == "soak":
      # Keep the same process and ARC allocator across all independently owned endpoint sessions.
      let rounds = parseInt(getEnv("RAGNAROK_SOAK_ROUNDS"))
      let gate = getEnv("RAGNAROK_SOAK_GATE")
      # Invalid controls cannot park the process indefinitely.
      if rounds < 1 or rounds > 1000 or gate.len == 0:
        return 2
      for iteration in 0..rounds:
        let control = gate / (paramStr(1) & "-" & $iteration)
        let started = getMonoTime()
        # The harness samples only after complete cleanup, then releases the next session explicitly.
        while not fileExists(control):
          if (getMonoTime() - started).inSeconds > 15: return 2 # Bound a dead/missing harness.
          sleep(10) # No native endpoint is live while waiting at this external observation barrier.
        if iteration == rounds: break # Hold the final idle sample until the harness permits normal exit.
        if not runPeer(): return 2 # Deferred selector/native cleanup finishes before failure returns.
        echo "ALLOC_BYTES ", getOccupiedMem(), " RESERVED_BYTES ", getTotalMem()
        echo "SESSION_DONE ", iteration
    elif not runPeer():
      return 2 # The one-shot rejection suite must distinguish failed exchange from successful authentication.
    0
  except CatchableError as error:
    # Setup/OS/control errors become bounded process failures after all native owners have retired.
    stderr.writeLine(error.msg)
    2

quit(main()) # Never exit while a selector or native callback still borrows a retiring Peer.
