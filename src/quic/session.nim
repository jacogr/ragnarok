## Private CE stream owners and retained peer/mesh sessions over the bounded synchronous UDP dispatcher.
import std/[os, strutils, monotimes, times, assertions, syncio, envvars]
import ./transport
import ./protocol
import ./integration
import ./offload
import ../telemetry/options

# Emit complete lifecycle observations immediately; the native Nimony stdout buffer otherwise waits until exit.
# Harness readiness and cancellation gates must observe progress while this process still owns live sockets.
template progress*() {.varargs.} =
  # Format each public diagnostic field through syncio, preserving exact existing marker bytes.
  for field in unpack(): stdout.write(field)
  stdout.write('\n')
  stdout.flushFile()

type
  # One bounded native stream owns application storage until its final close callback.
  StreamState = object
    handle: NativeStream
    received, sending: seq[byte]
    receivedLength, sendLength, sendOffset: int
    readFin, writeFin, counted, paused, blocked, responder: bool
    started: MonoTime
    attack: string
    verified: VerifiedDigest
    query: PreimageKey
    fixture: int
    job: JobId
  # This stack owner outlives every synchronous native callback and its dispatcher/engine teardown.
  Peer = object
    transport: Transport
    expected: seq[byte]
    server, failed, stopping, service, mixed, integrated, mesh, recovering, overload: bool
    streams: array[64, StreamState]
    completed, opened, healthy, rejected, cancelled: int
    capacityRejected, peakStreams: int
    attack: string
    bank: IntegrationBank
    offloading, light, badProof: bool
    pool: OffloadPool

# Fixture preimage key is independently checked by the shared harness; no unfinished database/state code is involved.
const RequestHash = [17'u8, 192, 231, 155, 113, 195, 151, 108, 205, 12, 2, 209, 49, 14, 37, 22,
  192, 142, 220, 157, 139, 111, 87, 204, 214, 128, 214, 58, 77, 142, 114, 218]
# Independent hashes name cheap and wrong-domain test preimages; CE framing remains unchanged.
const LightHash = [10'u8, 253, 74, 4, 215, 114, 13, 169, 146, 47, 43, 64, 36, 153, 137, 250, 244,
    255, 128, 150, 225, 237, 73, 190, 230, 21, 187, 108, 177, 238, 79, 125]
const BadProofHash = [15'u8, 96, 93, 27, 146, 148, 195, 111, 125, 23, 196, 140, 148, 61, 162, 184,
    119, 205, 169, 96, 186, 94, 51, 55, 231, 178, 226, 155, 206, 96, 61, 24]

# Bounded one-MiB soak fixture is i mod 251, named by its independently computed Blake2b-256 digest.
const LargeSize = 1024 * 1024
const LargeHash = [138'u8, 90, 122, 157, 195, 207, 32, 62, 211, 116, 176, 161, 238, 169,
  48, 96, 26, 210, 172, 191, 226, 180, 188, 98, 207, 131, 222, 78, 229, 54, 82, 139]

# Native TLS verification borrows only the retained peer's expected key; no closure or async frame is captured.
proc verifyPeer(user: pointer, der: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  let peer = cast[ptr Peer](user)
  cint(validPeer(cast[ptr byte](der), length, peer.expected))

# Settle one stream exactly once; soak rejections preserve healthy siblings on the same connection.
proc finishStream(peer: ptr Peer, state: ptr StreamState, good: bool) {.raises: [].} =
  # Reset and close notifications may report the same terminal state more than once.
  if state.counted: return
  state.counted = true
  # A healthy result means exact request/reply bytes and the required FIN were validated.
  if good:
    inc peer.completed
    inc peer.healthy
    if peer.offloading and state.receivedLength == 37 and state.received[5] == LightHash[0]:
      progress "OFFLOAD_LIGHT_DONE ", busyPool(peer.pool) # Exact reply FIN progressed during actual Rust calls, or an explicitly reported hold.
    # Progress alongside a genuinely parked writer is stronger evidence than an authenticated connection count.
    if peer.service:
      for other in peer.streams:
        if other.handle != NativeStream(nil) and other.blocked and not other.counted and samePeer(
            state.handle, other.handle) == 0:
          progress "ISOLATED_HEALTHY"
          break
    if peer.attack == "soak": progress (if peer.server: "SERVER_HEALTHY" else: "HEALTHY_OK") # Expose verified outcomes.
  elif peer.offloading:
    # Admission, cancellation and invalid proofs reject only their own stream.
    inc peer.completed
    inc peer.rejected
  elif peer.mesh and peer.recovering:
    # A known vanished peer settles its pending requests; buffers remain owned until final native close.
    inc peer.completed
    inc peer.rejected
  elif peer.attack == "soak":
    # An intentionally bad stream retires only its own buffers/callbacks.
    inc peer.completed
    inc peer.rejected
    progress (if peer.server: "STREAM_REJECTED" else: "EXPECTED_REJECT")
  else:
    # The one-shot rejection matrix fails the attempted application exchange.
    peer.failed = true

# Legacy fixtures use connection role; mesh CE streams use their independently observed initiator.
proc accepting(peer: ptr Peer, state: ptr StreamState): bool {.raises: [].} =
  if peer.mesh: state.responder else: peer.server

# Check incremental framing and fixture payloads; success requires one exact message followed by FIN.
proc frameExtent(peer: ptr Peer, state: ptr StreamState): tuple[complete, valid: bool] {.raises: [].} =
  let maximum = if accepting(peer, state): 32 elif peer.integrated: WireCap elif peer.attack ==
      "soak": LargeSize else: 1024
  let boundary = inspectFrame(state.received.toOpenArray(0, state.receivedLength - 1),
      accepting(peer, state), maximum, state.readFin)
  # Incomplete directions expose no payload extent until exact FIN; malformed framing settles the stream.
  if boundary.error == FrameError.Pending: return (false, true)
  if boundary.error != FrameError.None: return (false, false)
  let extent = boundary.extent
  let payloadSize = boundary.size
  # The integration corpus deliberately uses complete C.2 digests as otherwise opaque CE preimages.
  if peer.integrated:
    if accepting(peer, state):
      if payloadSize != 32: return (false, false) # CE query hash width remains normative.
      let index = findFixture(peer.bank, state.received.toOpenArray(5, 36))
      if index < 0:
        progress "INTEGRATION_REJECT Lookup"
        return (false, false) # A missing database key cannot select a default record.
      state.fixture = index
      let fixture = fixtureBytes(peer.bank, index)
      let key = fixtureKey(peer.bank, index)
      if fixture.error != IntegrationError.None or key.error != IntegrationError.None:
        return (false, false) # No default/missing bank entry can create a response snapshot.
      var scratch = fixture.value
      let checked = captureDigest(scratch, key.value)
      if checked.error != IntegrationError.None:
        progress "INTEGRATION_REJECT ", checked.error
        return (false, false) # Codec/ownership/crypto failure settles only this stream.
      state.verified = checked.value
      progress "OWNED_VERIFIED"
    else:
      # Capture the actual received preimage; its query key is retained independently of source storage.
      let checked = captureDigest(state.received.toOpenArray(4, extent - 1), state.query)
      if checked.error != IntegrationError.None:
        progress "INTEGRATION_REJECT ", checked.error
        return (false, false)
      state.verified = checked.value
      progress "OWNED_VERIFIED"
    return (true, true)
  # Requests select only exact fixture hash keys, never a default/missing map entry.
  if accepting(peer, state):
    if payloadSize != 32: return (false, false) # Preimage keys have fixed width.
    var wanted = RequestHash
    # Cheap lookup, wrong-domain policy and backpressure fixtures each retain a full exact content key.
    if peer.offloading and state.received[5] == LightHash[0]:
      wanted = LightHash
    elif peer.offloading and state.received[5] == BadProofHash[0]:
      wanted = BadProofHash
    elif peer.attack == "soak" and state.received[5] == LargeHash[0]:
      wanted = LargeHash
    for i, value in wanted:
      if state.received[5 + i] != value: return (false, false) # Complete hash equality.
  else:
    # Replies must contain the exact expected tiny/large fixture, independently of transport chunking.
    let size = if state.attack == "slow": LargeSize else: 3
    if payloadSize != size: return (false, false)
    for i in 0..<size:
      let wanted = if size == LargeSize: byte(i mod 251) else: byte(i + 1 + (
          if peer.light: 3 elif peer.badProof: 6 else: 0))
      if state.received[4 + i] != wanted: return (false, false) # Compare every byte of the preimage.
  (true, true)

# Initialize bounded request/reply storage on a new native stream; no network length chooses an allocation.
proc newStream(peer: ptr Peer, state: ptr StreamState, handle: NativeStream) {.raises: [].} =
  state[] = StreamState(handle: handle, started: getMonoTime(), attack: peer.attack)
  # Connection acceptors may open queries too; native stream IDs identify the actual requester.
  if peer.mesh: state.responder = not locallyOpened(peer.transport, handle)
  state.received = newSeq[byte](if accepting(peer, state): 1050 elif peer.integrated: WireCap +
      5 elif peer.attack != "soak": 1050 else: LargeSize + 5)
  # The acceptor waits for one exact request before allocating its trusted fixture response.
  if accepting(peer, state): return
  state.sending = newSeq[byte](64)
  state.sending[0] = 143
  state.sending[1] = 32
  # The integrated query corpus keeps eight independent stream owners and exact typed request keys.
  if peer.integrated:
    let index = peer.opened
    if index >= 8: peer.failed = true; streamAbort(handle); return # Trusted workload ceiling.
    inc peer.opened
    state.fixture = index
    let key = fixtureKey(peer.bank, index)
    if key.error != IntegrationError.None:
      peer.failed = true
      streamAbort(handle)
      return # A missing bank cannot supply a default request identity.
    state.query = key.value
    state.attack = if index == 6: "cancel" else: "valid"
    for i, value in array[32, byte](state.query): state.sending[5 + i] = value
    if index == 4: state.sending[5] = state.sending[5] xor 1 # Deliberately request an absent key.
    state.sendLength = 37
    if index == 6:
      state.paused = true
      wantRead(handle, 0) # Cancellation must retire a snapshot behind real backpressure.
    wantWrite(handle, 1)
    return
  var wanted = if peer.light: LightHash elif peer.badProof: BadProofHash else: RequestHash
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
  of "valid", "slow", "cancel", "no-fin", "proof-cancel": discard # Correct wire bytes with different read/FIN schedules.
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
  if state.attack in ["slow", "cancel", "proof-cancel"]:
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
      if peer.mesh: readDone(state.handle) # Retire the read half only after exact FIN validation.
      wantRead(state.handle, 0) # Stop repeated EOF callbacks after validated FIN.
      # Only a validated fixture key can select a bounded server response allocation.
      if accepting(peer, state):
        if peer.offloading and state.received[5] != LightHash[0]:
          state.job = submitPool(peer.pool, state.received[5] == BadProofHash[0])
          if state.job == JobId(0):
            progress "OFFLOAD_REJECT Capacity"
            finishStream(peer, state, false)
            streamAbort(state.handle)
          else:
            progress "OFFLOAD_ADMIT ", $state.job
          return # No reply allocation/write occurs until the I/O thread selects verified completion.
        if peer.integrated:
          let length = wireLength(state.verified)
          if length.error != IntegrationError.None or length.value > high(int) - 4:
            finishStream(peer, state, false)
            streamAbort(state.handle)
            return # Missing/oversized snapshot metadata cannot choose a send allocation.
          state.sending = newSeq[byte](length.value + 4)
          for i in 0..<4: state.sending[i] = byte((length.value shr (8 * i)) and 255) # Native E4 header.
          let copied = copyVerifiedWire(state.verified, state.sending.toOpenArray(4,
              state.sending.len - 1))
          if copied.error != IntegrationError.None:
            finishStream(peer, state, false)
            streamAbort(state.handle)
            return # Failed copy cannot publish a partial response.
          if state.fixture == 5: state.sending[8] = state.sending[
              8] xor 1 # Test-only corrupt response remains a valid digest with the wrong preimage hash.
          state.sendLength = state.sending.len
          wantWrite(state.handle, 1)
          return # The snapshot and write storage remain retained until native stream close.
        let size = if peer.attack == "soak" and state.received[5] == LargeHash[0]: LargeSize else: 3
        state.sending = newSeq[byte](size + 4)
        # Encode trusted E4 bytes before the fixture payload, independently of the C bridge.
        for i in 0..<4: state.sending[i] = byte((size shr (8 * i)) and 255)
        for i in 0..<size: state.sending[4 + i] = if size == LargeSize: byte(i mod 251) else: byte(
            i + 1 + (if peer.offloading and state.received[5] == LightHash[0]: 3 else: 0)) # Fixture bytes.
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
  if not state.writeFin and (accepting(peer, state) or state.attack != "no-fin"):
    streamFin(state.handle)
    state.writeFin = true
    if accepting(peer, state): finishStream(peer, state,
        true) # Exact request and queued reply FIN complete server work.

# Native callbacks borrow this peer synchronously; only native close releases application buffers.
proc onStream(user: pointer, handle: NativeStream, event: cint) {.cdecl, raises: [].} =
  let peer = cast[ptr Peer](user)
  var state: nil ptr StreamState = nil # No callback slot has been resolved yet.
                                       # Resolve a currently retained native handle before accessing its application buffers.
  for index in 0..<peer.streams.len:
    # Slot addresses stay inside this stack-stable peer through native callbacks and close.
    let slot = addr peer.streams[index]
    if slot.handle == handle: state = slot; break # Unique live stream ownership.
  if event == 0:
    # The fixed slot ceiling bounds concurrent requests and all associated application storage.
    for index in 0..<peer.streams.len:
      # Slot addresses stay inside this stack-stable peer through native callbacks and close.
      let slot = addr peer.streams[index]
      if slot.handle == NativeStream(nil): state = slot; break # Allocate only a retired slot.
    if state == nil:
      # At capacity a service rejects only this stream, preserving existing peers.
      if not peer.service: peer.failed = true
      else: inc peer.capacityRejected # Only the newly arriving service stream loses admission.
      streamAbort(handle)
      return # Never grow an unbounded stream queue.
    newStream(peer, state, handle)
    # Observe actual retained application owners, independently of transport stream-credit limits.
    if peer.overload:
      var live = 0
      for slot in peer.streams:
        if slot.handle != NativeStream(nil): inc live # Final close is the only slot release point.
      peer.peakStreams = max(peer.peakStreams, live)
    return
  # Unknown native events cannot dereference released framing state.
  if state == nil:
    # Capacity-rejected service streams never acquired buffers; their final close needs no release.
    if not (peer.service and event in [3.cint, 4.cint]): peer.failed = true
    return
  if event == 3:
    if peer.offloading: cancelPool(peer.pool, state.job) # Final close releases only this generation.
    # A premature native close rejects unsettled work unless teardown is already retiring the owner.
    if not state.counted and not peer.stopping: finishStream(peer, state, false)
    # The cancelled large response must have reached owned capture before final close releases it.
    if peer.integrated and accepting(peer, state) and state.fixture == 6 and
        wireLength(state.verified).error == IntegrationError.None: progress "OWNED_CANCEL_RELEASE"
    state[] = StreamState() # ARC releases both buffers; the slot holds no closure/reference back to Peer.
    return
  if event == 4:
    if peer.offloading: cancelPool(peer.pool, state.job) # Running Rust retains its copied input after reset.
    # A directional reset settles pending reads and writes before final native close releases their storage.
    if not peer.stopping: finishStream(peer, state, false)
    streamAbort(handle)
    return
  # No new application work starts during teardown or after a completed client response.
  if peer.stopping or (state.counted and not accepting(peer, state)): return
  case event
  of 1: readStream(peer, state) # Read readiness preserves incremental framing across callbacks.
  of 2: writeStream(peer, state) # Write readiness preserves partial-write offsets across callbacks.
  else: peer.failed = true # Undefined bridge events are explicit integration failures.

# Stream-local lifecycle deadlines run on the same dispatcher thread as native transport timers.
proc soakTick(peer: ptr Peer) {.raises: [].} =
  # Only live, unsettled streams own deadline work; close callbacks may recycle slots synchronously.
  for index in 0..<peer.streams.len:
    # Resolve a stable slot by index; no mutable iterator temporary owns its ARC buffers.
    let state = addr peer.streams[index]
    if state.handle == NativeStream(nil) or state.counted: continue # Retired streams have no pending timer.
    let elapsed = (getMonoTime() - state.started).inMilliseconds
    if peer.server:
      # A complete hash without request FIN must not retain its handler indefinitely.
      if not state.readFin and elapsed > (if peer.overload: 30000 else: 500):
        progress "REQUEST_TIMEOUT"
        finishStream(peer, state, false)
        streamAbort(state.handle)
      elif state.sendLength > 65536 and state.sendOffset < state.sendLength and
          not state.blocked and elapsed > 100:
        # The pending large write proves real flow-control backpressure, not an artificial sleep alone.
        state.blocked = true
        progress "BACKPRESSURE"
    elif state.attack == "cancel" and elapsed > (if peer.integrated: 500 elif peer.mixed: 700 else: 150):
      # Cancel while the remote large write is parked behind withheld receive credit.
      state.counted = true
      inc peer.completed
      inc peer.cancelled
      progress "CANCEL_OK"
      streamAbort(state.handle)
    elif state.attack == "slow" and state.paused and elapsed > (if peer.mixed: 1000 else: 350):
      # Resume application consumption so the native stream window can advance again.
      state.paused = false
      wantRead(state.handle, 1)

# Deliver completed proof decisions on the only I/O thread, resolving generations afresh after cancellation/reuse.
proc offloadTick(peer: ptr Peer) =
  tickPool(peer.pool)
  # At most four retained completions exist; no worker can grow this drain without bound.
  for index in 0..<4:
    let polled = collectPool(peer.pool)
    if not polled.ready: break # Pending has no completion data.
    let completion = polled.completion
    var matched = false
    for index in 0..<peer.streams.len:
      # Resolve a stable slot by index; no mutable iterator temporary owns its ARC buffers.
      let state = addr peer.streams[index]
      if state.handle != NativeStream(nil) and state.job == completion.id and not state.counted:
        matched = true
        state.job = JobId(0) # The pool has retired its input; final stream close owns only application bytes.
        if completion.outcome != Verified:
          progress "OFFLOAD_REJECT Proof"
          finishStream(peer, state, false)
          streamAbort(state.handle)
        else:
          progress "OFFLOAD_VERIFIED ", $completion.id
          state.sending = @[3'u8, 0, 0, 0, 1, 2, 3]
          state.sendLength = 7
          wantWrite(state.handle, 1) # Only verified completion enables response readiness.
        break
    if not matched: progress "OFFLOAD_STALE ", $completion.id # A vanished/reused stream cannot receive old completion.

# Own one bounded authentication/exchange attempt and release readiness before native callback destruction.
proc runPeer*(): bool {.raises.} =
  # Trusted CLI inputs still have explicit shape and narrowing checks.
  if peerParamCount() notin [7, 8]: return false # Reject malformed trusted invocation before endpoint setup.
  let port = parseInt(paramStr(2))
  let timeout = parseInt(paramStr(7))
  let timeoutLimit = if peerParamCount() == 8 and paramStr(8) == "offload": 300000 else: 120000
  # Guard host-to-native conversions before any endpoint is created.
  if port < 1 or port > 65535 or timeout < 1 or timeout > timeoutLimit: return false
  let server = paramStr(1) == "server"
  if not server and paramStr(1) != "client": return false # Never infer an unknown role.
  let mode = if peerParamCount() == 8: paramStr(8) else: "valid"
  # Service uses the established mixed fixture protocol; mixed clients bypass the old lifecycle harness gate.
  if mode in ["service", "integration", "overload", "offload"] and not server: return false
  let integrated = mode in ["integration", "integrated"]
  let service = mode in ["service", "integration", "overload", "offload"]
  let load = mode in ["overload", "holder", "idle", "probe", "offload", "proof", "light",
      "invalid-proof", "proof-cancel"]
  let target = if mode in ["probe", "proof", "light", "invalid-proof", "proof-cancel"]: 1 else: 8
  var attack = mode
  # Existing service/integration workloads keep their mixed failure schedules.
  if (service and mode != "offload") or integrated or mode == "mixed":
    attack = "soak"
  elif mode in ["clean", "probe", "proof", "light", "invalid-proof", "offload"]:
    attack = "valid" # These one-query fixtures use normal request bytes and FIN.
  elif mode == "holder":
    attack = "no-fin" # Saturation holders keep their read direction deliberately incomplete.
  var peer = Peer(server: server, service: service, integrated: integrated,
      mixed: mode == "mixed", attack: attack, mesh: load, overload: mode == "overload",
      offloading: mode == "offload", light: mode == "light", badProof: mode == "invalid-proof")
  # Explicitly integrated binaries load public fixtures before registering native callbacks.
  if peer.integrated and (not IntegrationEnabled or not loadBank(peer.bank, getEnv(
      "RAGNAROK_INTEGRATION_FIXTURES"))): return false
  # Initialize fixed worker-owned Rust setups before exposing the listener. Join after native callbacks retire.
  if peer.offloading:
    if not startPool(peer.pool): return false # Explicit offload mode never silently uses the I/O thread.
  defer:
    if peer.offloading: stopPool(peer.pool) # Transport teardown runs first and cancels every remaining stream job.
  # Expected identity bytes remain owned by Peer across all TLS verification callbacks.
  if paramStr(5) != "-":
    let text = readFile(paramStr(5))
    if text.len != 32: return false # Fixture identity has exact Ed25519 width.
    peer.expected = newSeq[byte](32)
    for i in 0..<32: peer.expected[i] = byte(text[i]) # Copy public identity bytes, not PEM strings.
  if not server and peer.expected.len != 32: return false # Every dialer pins the server identity.
  var telemetry = default(Client)
  defer: telemetry.close() # Best-effort telemetry never delays peer shutdown.
  # Cleanup must also run after poll/setup failures; both stack owners remain alive until final native callbacks finish.
  defer:
    peer.stopping = true
    closeTransport(peer.transport)
  if not openTransport(peer.transport, server, peer.attack == "soak", uint16(port), paramStr(3),
      paramStr(4), paramStr(6), addr peer, verifyPeer,
          onStream, peer.service, ipv6 = load, profile = (
              if peer.overload or peer.offloading: SaturatedService else: CrashRecovery)): return false # No partially initialized endpoint is used.
  # Derive the telemetry peer identity/address from this endpoint, with an explicit chain file.
  if not telemetry.setup(paramStr(3), localPort(peer.transport), load):
    stderr.writeLine("Invalid telemetry endpoint, certificate or --chain file")
    return false
  if server: progress "READY" # Announce only after listener binding and native setup.
  elif not connectTransport(peer.transport, uint16(port)): return false # Dial setup failed before authentication.
  let started = getMonoTime()
  let stopFile = getEnv("RAGNAROK_SERVICE_STOP")
  let cancelFile = getEnv("RAGNAROK_OFFLOAD_CANCEL")
  # An externally gated service must have a concrete stop path before entering its bounded loop.
  if peer.service and stopFile.len == 0: return false
  var lastActive = -1
  var lastLive, lastCapacity = -1
  var lastLoadActive = -1
  var lastCapacityConnections = 0
  var lastIdle = 0'u64
  var serviceStopped = false
  var authenticated, opened = false # Neither authentication nor application admission has happened at startup.
 # One dispatcher loop services all streams, UDP reads and LSQUIC/application deadlines.
  while not peer.failed and (peer.service or peer.completed < target) and (getMonoTime() -
      started).inMilliseconds < timeout:
    # Server metrics count authenticated retained peers; client status excludes pending handshakes.
    let telemetryPeers = if server: uint32(peerMetric(peer.transport, 0)) else: (if transportStatus(
        peer.transport) == 1: 1'u32 else: 0'u32)
    telemetry.observe(telemetryPeers)
    if peer.offloading: offloadTick(addr peer) # Poll completions without blocking UDP or native deadlines.
    # Observe retirement while keeping the same socket, dispatcher and native engine throughout every wave.
    if peer.service:
      let active = int(peerMetric(peer.transport, 0))
      if active != lastActive:
        progress "PEERS ", active
        lastActive = active
      var live = 0
      # Only final native close releases application buffer ownership.
      for state in peer.streams:
        if state.handle != NativeStream(nil): inc live
      # Emit state changes only, so burst input cannot create an unbounded diagnostic stream.
      if peer.overload and (active != lastLoadActive or live != lastLive or peer.capacityRejected !=
          lastCapacity or peerMetric(peer.transport, 5) != uint64(lastCapacityConnections)):
        progress "LOAD_STATE ", active, " ", live, " ", peerMetric(peer.transport, 5), " ",
            peer.capacityRejected, " ", peer.peakStreams
        lastLoadActive = active
        lastLive = live; lastCapacity = peer.capacityRejected; lastCapacityConnections = int(
            peerMetric(peer.transport, 5))
      let accepted = peerMetric(peer.transport, 1)
      if active == 0 and live == 0 and accepted > lastIdle:
        progress "SERVICE_IDLE ", accepted, " ", peerMetric(peer.transport, 2), " ", getOccupiedMem()
        lastIdle = accepted
      if fileExists(stopFile):
        serviceStopped = peer.offloading or (active == 0 and live == 0)
        if peer.offloading: progress "OFFLOAD_SHUTDOWN_PENDING ",
            live # Explicit test shutdown also exercises pending jobs.
        break
    let status = transportStatus(peer.transport)
    # Reusable IPv6 engines become idle after close; this CLI attempt cannot reconnect or finish without a live peer.
    if not server and peerMetric(peer.transport, 2) > 0 and peerMetric(peer.transport, 0) == 0:
      progress "CONNECTION_CLOSED"
      break # No stream callback exists if admission was refused before any request opened.
    if status < 0: break # Authentication or persistent UDP failure settles this bounded attempt.
    if status == 1 and not authenticated:
      progress "AUTH_OK"
      authenticated = true
    if authenticated and not server and not opened and mode != "idle":
      # Open concurrent requests before waiting for replies; the soak introduces three later healthy siblings.
      opened = true
      for index in 0..<(if peer.attack == "soak": 5 else: target): openStream(peer.transport)
    # The controller releases cancellation only after observing actual worker execution.
    if mode == "proof-cancel" and fileExists(cancelFile):
      for index in 0..<peer.streams.len:
        # Resolve a stable slot by index; no mutable iterator temporary owns its ARC buffers.
        let state = addr peer.streams[index]
        if state.handle != NativeStream(nil): streamAbort(state.handle) # Cancel this authenticated pending query.
      disconnectTransport(peer.transport)
      let grace = getMonoTime()
      while (getMonoTime() - grace).inMilliseconds < 100:
        discard pollTransport(peer.transport) # Deliver reset/close while UDP and callbacks still own their buffers.
      return false # The intentional cancellation has no validated reply.
    if peer.attack == "soak":
      soakTick(addr peer)
      # Late healthy requests prove continued service after malformed input, cancellation and missing FIN.
      if not server and opened and peer.opened == 5 and (getMonoTime() - started).inMilliseconds > (
          if peer.mixed: 1200 else: 650):
        for index in 0..<3: openStream(peer.transport)
    if not pollTransport(peer.transport): break # Selector/UDP failure cannot become a successful exchange.
  # A final receive cycle can authenticate, finish requests and close; preserve handshake evidence without reopening work.
  if peerMetric(peer.transport, 4) > 0 and not authenticated:
    progress "AUTH_OK"
    authenticated = true
  # A service succeeds only after the harness requests shutdown with every promoted connection and stream retired.
  if peer.service:
    progress "SERVICE_DONE ", peerMetric(peer.transport, 1), " ", peerMetric(peer.transport, 2),
        " ", peerMetric(peer.transport, 3)
    return serviceStopped and not peer.failed and (peer.offloading or peerMetric(peer.transport,
        3) >= 3)
  result = authenticated and not peer.failed and peer.completed == target
  # Client success counts must distinguish exactly five healthy, two rejected and one cancelled stream.
  if result and peer.attack == "soak" and not server:
    result = if peer.integrated: peer.healthy == 3 and peer.rejected == 4 and peer.cancelled ==
        1 else: peer.healthy == 5 and peer.rejected == 2 and peer.cancelled == 1
  if result:
    progress "EXCHANGE_OK ", target # Authentication alone is insufficient without all terminal application outcomes.
    # Mixed/probe clients explicitly close while UDP remains active so the persistent server can retire their connection.
    if mode in ["mixed", "clean", "integrated", "probe", "proof", "light"]: disconnectTransport(peer.transport)
    let grace = getMonoTime()
    # Drain final handshake/FIN packets before removing readiness and destroying native stream state.
    while (getMonoTime() - grace).inMilliseconds < 100:
      if not pollTransport(peer.transport): return false # Final I/O errors are still observable.
  else:
    # Print only framing counts/lifecycle state, never private-key or certificate buffer contents.
    progress "proof rejected or timed out ", peer.completed, " ", peer.healthy, " ", peer.rejected,
        " ", peer.cancelled

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
  if extent.complete: assert extent.valid and fin and input.len == (if server: 37 else: 7)
  if fin and input.len < (if server: 5 else: 4): assert not extent.valid # Partial-header EOF is immediate rejection.

# Deterministic malformed-input coverage remains independently testable before native transport setup.
proc peerSelfTest*() =
  assert checkedLength([0'u8, 0, 0, 0], 0).value == 0
  assert checkedLength([255'u8, 255, 255, 255], 1024).error != FrameError.None
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
      assert frameExtent(addr peer, addr frame) == (false, true)
      frame.readFin = true
      let extent = frameExtent(addr peer, addr frame)
      assert extent == (length == wire.len, length == wire.len)
  var state = 0x51554943'u64
  # Xorshift produces reproducible parser coverage bytes, not cryptographic randomness.
  for iteration in 0..<10000:
    var input = default(array[128, byte])
    for index in 0..<input.len:
      state = state xor (state shl 13)
      state = state xor (state shr 7)
      state = state xor (state shl 17)
      input[index] = byte(state and 255)
    fuzzPeer(input.toOpenArray(0, iteration mod 129 - 1), iteration mod 2 == 0, iteration mod 3 == 0)
  progress "Nim QUIC selftest: 10000 malformed DER/frame cases passed"

## Retained two-peer IPv6 lifecycle policy shares this module's private owners and callbacks.

# Compare the full public-key byte strings lexicographically, then apply pinned JAMNP-S Required connectivity.
proc preferred(local, remote: array[32, byte]): bool {.raises: [].} =
  var less = false
  # The first unequal byte determines the ordering; the high bit is separately taken from byte 31.
  for index in 0..<32:
    if local[index] != remote[index]: less = local[index] < remote[index]; break
  (local[31] > 127) xor (remote[31] > 127) xor less

# Test ordering, both final-byte high bits and direction symmetry without any cryptographic secret material.
proc meshSelfTest*() =
  # Exercise all high-bit combinations with both possible lexicographic orders.
  for highA in [0'u8, 128'u8]:
    # Vary the remote high bit independently of the local high bit.
    for highB in [0'u8, 128'u8]:
      # Exercise both first-byte ordering outcomes for this parity combination.
      for firstA in [0'u8, 2'u8]:
        var a, b = default(array[32, byte])
        a[0] = firstA; b[0] = 1
        a[31] = highA; b[31] = highB
        assert preferred(a, b) == ((highA != highB) xor (firstA < 1))
        assert preferred(a, b) != preferred(b, a)
  var a, b = default(array[32, byte])
  b[31] = 127
  assert preferred(a, b) # Ordering reaches the final byte without treating 127 as high.
  b[31] = 128
  assert not preferred(a, b) # Exactly 128 changes the parity.
  progress "MESH_POLICY_OK"

# Count live stream owners; a settled reply alone does not prove all native close callbacks have retired.
proc liveMesh(peer: ptr Peer): int {.raises: [].} =
  result = 0 # An empty peer has no live stream owners; every increment starts from a defined count.
  # A slot owns its buffers until its handle becomes nil in the final close callback.
  for state in peer.streams:
    if state.handle != NativeStream(nil): inc result

# Prove eight pending owners contain four fully sent queries and four complete request prefixes without FIN.
proc pendingMesh(peer: ptr Peer): bool {.raises: [].} =
  var local, remote = 0
  # Ignore retired slots; every retained slot must still be unsettled and waiting for the missing peer/FIN.
  for state in peer.streams:
    if state.handle == NativeStream(nil): continue # Final close has already released this owner.
    if state.counted or state.readFin: return false # A completed message cannot stand in for pending work.
    if state.responder:
      if state.receivedLength != 37: return false # Require the complete CE query prefix to have arrived.
      inc remote
    else:
      if state.sendOffset != 37 or state.writeFin: return false # All request bytes must be sent without FIN.
      inc local
  local == 4 and remote == 4

# Drive both role engines from their one dispatcher, surfacing framing or socket failures as bounded outcomes.
proc meshPoll(incoming, outgoing: var Peer): bool =
  pollPair(incoming.transport, outgoing.transport) and not incoming.failed and not outgoing.failed

# Retain two IPv6 engines through sixteen externally gated reconnects and simultaneous CE queries.
proc runMesh*(): bool {.raises.} =
  # Validate all trusted controls before opening sockets or narrowing ports.
  if paramCount() != 9: return false
  let localPort = parseInt(paramStr(2))
  let remotePort = parseInt(paramStr(3))
  let rounds = parseInt(getEnv("RAGNAROK_MESH_ROUNDS", "16"))
  if localPort notin 1..65535 or remotePort notin 1..65535 or rounds notin 1..64: return false
  let localKey = readFile(paramStr(6))
  let remoteKey = readFile(paramStr(7))
  if localKey.len != 32 or remoteKey.len != 32 or localKey == remoteKey: return false # No self/ambiguous peer.
  var a, b = default(array[32, byte])
  var expected = newSeq[byte](32)
  # Retain owned identity bytes across both engines' TLS callbacks, with no certificate pointer escaping.
  for index in 0..<32:
    a[index] = byte(localKey[index]); b[index] = byte(remoteKey[index]); expected[index] = b[index]
  let initiator = preferred(a, b)
  let disrupted = getEnv("RAGNAROK_MESH_DISRUPT") == "1"
  let profile = if disrupted: CrashRecovery else: RetainedPeer
  let gate = paramStr(9)
  let dispatcher = newDispatcher()
  defer: dispatcher.close() # Both borrowed endpoint registrations retire first, in reverse defer order.
  var incoming = Peer(server: true, mesh: true, expected: expected, attack: "valid")
  var outgoing = Peer(mesh: true, expected: expected, attack: "valid")
  defer:
    incoming.stopping = true; outgoing.stopping = true
    closeTransport(outgoing.transport)
    closeTransport(incoming.transport) # TLS globals outlive the first engine destruction.
  # The listener is persistent; outgoing binds once to an ephemeral IPv6 port and keeps it across reconnects.
  if not openTransport(incoming.transport, true, false, uint16(localPort), paramStr(4), paramStr(5),
      paramStr(8), addr incoming, verifyPeer, onStream, ipv6 = true,
          dispatcher = dispatcher, profile = profile): return false
  if not openTransport(outgoing.transport, false, false, 0, paramStr(4), paramStr(5),
      paramStr(8), addr outgoing, verifyPeer, onStream, ipv6 = true,
          dispatcher = dispatcher, profile = profile): return false
  progress "MESH_READY ", int(initiator)
  var authenticatedIn, authenticatedOut = 0'u64
  # All rounds retain these exact stack/socket/dispatcher/TLS/engine owners.
  for round in 0..<rounds:
    var started = getMonoTime()
    # External barriers permit both simultaneous dials and post-retirement resource observations.
    while not fileExists(gate / ("start-" & $round)):
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 15: return false
    # A final healthy generation proves recovery after the last forced loss without introducing another crash.
    let lossRound = disrupted and not fileExists(gate / "healthy-final")
    let fallback = round == 0 and getEnv("RAGNAROK_MESH_FALLBACK") == "1"
    started = getMonoTime()
    # A suppressed preferred dial lets the other peer initiate after the spec's example five-second timeout.
    if fallback:
      while (getMonoTime() - started).inMilliseconds < 5000:
        if not meshPoll(incoming, outgoing): return false # Keep the listener responsive while waiting.
      if not initiator and not connectTransport(outgoing.transport, uint16(
          remotePort)): return false
    else:
      if not connectTransport(outgoing.transport, uint16(
          remotePort)): return false # Deliberately race both dials.
    let useOutgoing = if fallback: not initiator else: initiator
    let kept = if useOutgoing: addr outgoing else: addr incoming
    let discarded = if useOutgoing: addr incoming else: addr outgoing
    # Expected handshake generations advance independently of callbacks, which may arrive after the losing close.
    if fallback:
      if useOutgoing: inc authenticatedOut
      else: inc authenticatedIn # Only the fallback direction is attempted.
    else:
      inc authenticatedIn; inc authenticatedOut # Both authenticated directions are required for the duplicate proof.
    started = getMonoTime()
    # Duplicate arbitration runs only after both directions authenticate; fallback has only one live direction.
    while transportStatus(kept.transport) != 1 or peerMetric(incoming.transport, 4) <
        authenticatedIn or peerMetric(outgoing.transport, 4) < authenticatedOut:
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 10: return false
    if not fallback:
      progress "MESH_DUPLICATE ", round
      disconnectTransport(discarded.transport) # Local policy: keep the preferred-initiator direction.
    started = getMonoTime()
    # Never open application work on an engine whose duplicate close still owns a connection.
    while peerMetric(discarded.transport, 0) != 0:
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 10: return false
    if peerMetric(kept.transport, 0) != 1: return false # The selected connection must survive duplicate retirement.
    progress "MESH_CONNECTED ", round, " ", int(useOutgoing)
    # Four local queries share this connection with the remote peer's four queries.
    for query in 0..<4: openStream(kept.transport)
    started = getMonoTime()
    while kept.healthy != 8 or liveMesh(kept) != 0:
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 10: return false
    progress "MESH_EXCHANGED ", round, " ", kept.healthy
    # Opt-in crash rounds retain real incomplete request owners before the harness kills the other process.
    if lossRound:
      started = getMonoTime()
      # Both peers must finish and retire healthy work before either introduces incomplete streams into that phase.
      while not fileExists(gate / ("pending-" & $round)):
        if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds >
            15: return false
      kept.recovering = true
      kept.attack = "no-fin"
      for request in 0..<4: openStream(kept.transport) # Four outgoing requests accompany the peer's four pending queries.
      started = getMonoTime()
      while not pendingMesh(kept):
        if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds >
            10: return false
      progress "MESH_PENDING ", round, " 8"
    started = getMonoTime()
    # Hold a live connection for resource/thread sampling until the harness permits orderly close.
    while not fileExists(gate / ("close-" & $round)):
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 15: return false
    # Crash rounds await negotiated idle expiry; graceful rounds still explicitly queue connection close.
    if not lossRound: disconnectTransport(kept.transport)
    started = getMonoTime()
    # Connection and stream owners must all retire before the next gate releases a reconnect.
    while peerMetric(incoming.transport, 0) != 0 or peerMetric(outgoing.transport, 0) != 0 or
        liveMesh(addr incoming) != 0 or liveMesh(addr outgoing) != 0:
      if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 10: return false
    # Every pending request must settle exactly once when the vanished connection retires.
    if lossRound:
      if kept.rejected != 8: return false # Retained buffers cannot disappear without terminal outcomes.
      progress "MESH_RECOVERED ", round, " ", kept.rejected
    kept.healthy = 0; kept.completed = 0; kept.rejected = 0
    kept.recovering = false; kept.attack = "valid" # A malformed request in the next healthy phase remains a real failure.
    progress "MESH_IDLE ", round, " ", getOccupiedMem(), " ", peerMetric(incoming.transport, 1),
        " ", peerMetric(outgoing.transport, 1), " ", peerMetric(incoming.transport, 2), " ",
            peerMetric(outgoing.transport, 2)
  let started = getMonoTime()
  # Retain the final idle owner scope for the last sample before normal ARC/native teardown.
  while not fileExists(gate / "stop"):
    if not meshPoll(incoming, outgoing) or (getMonoTime() - started).inSeconds > 15: return false
  true
