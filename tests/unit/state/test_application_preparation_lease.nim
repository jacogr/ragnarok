# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed exclusive preparation freezes canonical/RPC access while independent dispatcher work can continue.

import std/[assertions, syncio, envvars, strutils, nativesocket, monotimes, times]
import std/posix/posix
import ../../../src/app/[services, options, preparation_worker, block_input, candidate, chain, handoff]
import ../../../src/rpc/server
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/[store, accumulation_finalization]
import ../../support/[application_candidate_context, accumulation_completion_context]

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only between bounded nonblocking test polls.
proc openSocket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
  ## Create a native loopback test socket with explicit descriptor ownership.
proc bindPort(fd: cint, address: pointer, length: SockLen): cint {.importc: "bind",
    header: "<sys/socket.h>".}
  ## Reserve the requested native endpoint for ephemeral port selection.
proc socketName(fd: cint, address: pointer, length: ptr SockLen): cint {.importc: "getsockname",
    header: "<sys/socket.h>".}
  ## Read the exact OS-selected initialized socket address.
proc connectPort(fd: cint, address: pointer, length: SockLen): cint {.importc: "connect",
    header: "<sys/socket.h>".}
  ## Connect the independent test client to the selected local listener.
proc networkPort(port: uint16): uint16 {.importc: "htons", header: "<netinet/in.h>".}
  ## Convert an explicitly bounded host port into native network byte order.
proc hostPort(port: uint16): uint16 {.importc: "ntohs", header: "<netinet/in.h>".}
  ## Convert the OS-selected network port back into a bounded host port.
proc ipv4(text: cstring): uint32 {.importc: "inet_addr", header: "<arpa/inet.h>".}
  ## Parse the literal loopback address for independent native clients.
proc sendBytes(fd: cint, data: pointer, length: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
  ## Send initialized independent HTTP/WebSocket test bytes.
proc receive(fd: cint, data: pointer, length: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}
  ## Read initialized native bytes without inspecting server-owned buffers.

proc address(port: uint16): Sockaddr_in =
  ## Native addresses use the real OS-selected loopback port and explicit initialization on every platform.
  result = default(Sockaddr_in)
  result.sin_family = TSa_Family(ord(nativesocket.AF_INET))
  result.sin_port = networkPort(port)
  result.sin_addr.s_addr = ipv4("127.0.0.1")
  when defined(macosx):
    result.sin_len = uint8(sizeof(result)) # Darwin requires the native address extent.

proc client(port: uint16): cint =
  ## Connect only to this local listener, then make all test reads nonblocking with bounded polling.
  let fd = openSocket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert fd >= 0
  var destination = address(port)
  assert connectPort(fd, addr destination, SockLen(sizeof(destination))) == 0
  let flags = fcntl(fd, F_GETFL, 0)
  assert flags >= 0 and fcntl(fd, F_SETFL, flags or O_NONBLOCK) == 0
  fd

proc sendText(peer: cint, text: string, masked = true) =
  ## Send one small independently masked client request, or the complete literal upgrade header.
  var packet = text
  if masked:
    assert text.len < 126
    packet = "\x81" & $char(128 or text.len) & "abcd"
    for index, octet in text: packet.add(char(ord(octet) xor ord("abcd"[index mod 4])))
  assert sendBytes(peer, packet.toCString(), csize_t(packet.len), 0) == packet.len

proc readPacket(rpc: var Server, peer: cint, pending: var string, upgrade = false): string =
  ## Independently decode a complete bounded server frame; retain coalesced suffixes across dispatcher turns.
  for attempt in 0..<200:
    if upgrade:
      let ending = pending.find("\r\n\r\n")
      if ending >= 0:
        result = pending.substr(0, ending + 3)
        pending = pending.substr(ending + 4)
        return # Header consumption retains any subsequent frame bytes.
    elif pending.len >= 2:
      assert ord(pending[0]) == 129 and (ord(pending[1]) and 128) == 0
      var size = ord(pending[1])
      var offset = 2
      if size == 126:
        if pending.len < 4: size = -1 # Wait for both initialized length octets.
        else:
          size = ord(pending[2]) * 256 + ord(pending[3])
          offset = 4
      assert ord(pending[1]) != 127
      if size >= 0 and pending.len >= offset + size:
        result = pending.substr(offset, offset + size - 1)
        pending = pending.substr(offset + size)
        return # One decoded payload never consumes the next notification.
    rpc.tick(0)
    var buffer = default(array[8192, char])
    let count = receive(peer, addr buffer[0], csize_t(buffer.len), 0)
    if count > 0:
      for index in 0..<count: pending.add(buffer[index]) # Only initialized receive bytes enter the bounded test buffer.
      assert pending.len <= 16384
    else:
      assert count < 0 # Unexpected EOF is a test failure, never an empty successful frame.
      discard pauseMicros(1000) # Bound local transport scheduling without an unbounded blocking receive.
  assert false, "RPC packet did not arrive"
  ""


const SeedPath = "application-preparation-lease-chain.json"

proc port(): uint16 =
  ## Reserve an OS-selected loopback endpoint, then release it immediately before bounded startup retry.
  let fd = openSocket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert fd >= 0
  var selected = address(0)
  assert bindPort(fd, addr selected, SockLen(sizeof(selected))) == 0
  var size = SockLen(sizeof(selected))
  assert socketName(fd, addr selected, addr size) == 0
  result = hostPort(selected.sin_port)
  discard posix.close(fd)

proc configured(rpc, ui: uint16): Options =
  ## Every listener and complete-state budget is explicitly selected through ordinary application options.
  result = default(Options)
  var args = @["server", "--chain", SeedPath, "--with-state", "--state-writes", "1000",
    "--state-write-bytes", "1000000"]
  if rpc != 0:
    for arg in ["--with-rpc", "--rpc-port", $rpc]: args.add(arg) # Only this test enables a real RPC listener.
  if ui != 0:
    for arg in ["--with-ui", "--ui-port", $ui]: args.add(arg) # UI owns an independent static-asset graph.
  assert parseOptions(args, result), "explicit preparation options"

proc receive(owner: Services, input: var BlockInput, wire: openArray[byte]): BlockInputId =
  ## Capture the exact canonical parent before the managed exclusion gate closes.
  let admitted = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [],
    BlockInputLimits(blockBytes: ByteLimit(uint64(wire.len))), preparationLimits())
  assert admitted.error == BlockInputError.None
  result = admitted.value
  assert input.append(result, wire, true) == BlockInputError.None

proc waitDone(owner: var Services) =
  ## Drive only permitted dispatcher/scalar work; all external canonical aliases remain untouched.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20, "bounded managed preparation"
    owner.tick(0)
    discard pauseMicros(1000) # The worker owns execution, while this host yields between nonblocking turns.

proc scenario(context: SeedFixture, wire: seq[byte], network: bool) {.raises.} =
  ## Lease the actual canonical graph, retain Done capacity, collect once and adopt only on a later host tick.
  writeFile(SeedPath, context.text)
  var input = default(BlockInput)
  var before = default(StateStoreSnapshot)
  var owner = default(Services) # Borrowed input and retained parent outlive worker-owner cleanup.
  var rpcPort = 0'u16
  var uiPort = 0'u16
  if network:
    rpcPort = port()
    uiPort = port()
    while uiPort == rpcPort: uiPort = port() # Enabled listeners require distinct explicit endpoints.
  assert owner.start(configured(rpcPort, uiPort), "lease test"), "start managed Services"
  defer: owner.close() # Input outlives this explicit joined close and every active worker borrow.
  assert owner.preparationAvailable
  before = owner.stateSnapshot.value
  let previousPause = owner.rpc.pauseChain()
  assert not owner.preparationAvailable, "foreign RPC suspension blocks preparation"
  assert owner.rpc.resumeChain(previousPause)
  assert not owner.rpc.resumeChain(previousPause), "released RPC token is stale"
  assert owner.beginPreparation(input, BlockInputId(0)).error == PreparationError.NotReady
  assert not owner.preparationActive and not owner.rpc.chainPaused, "refusal restores RPC gate"
  let id = receive(owner, input, wire)
  let admitted = owner.beginPreparation(input, id)
  assert admitted.error == PreparationError.None
  assert owner.preparationActive and owner.rpc.chainPaused and not owner.preparationAvailable
  assert owner.rpc.pauseChain() == nil, "nested pause grants no resume token"
  assert not owner.rpc.resumeChain(previousPause), "old token cannot reopen a new managed lease"
  assert not owner.rpc.resumeChain(nil), "default token cannot resume managed RPC"
  var other = default(Server)
  let foreign = other.pauseChain()
  assert not owner.rpc.resumeChain(foreign), "foreign token cannot resume managed RPC"
  assert other.resumeChain(foreign)
  assert not other.resumeChain(foreign), "resume token is single use"
  assert owner.collectPreparation(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized
  assert not owner.cancelAccumulation(), "adoption remains idle during preparation"
  assert owner.rpc.publishBlock(unavailableGenesis()) == ViewAdvanceError.Uninitialized
  assert owner.rpc.publishFinalized(default(genesis.BlockHash)) == ViewFinalizeError.Uninitialized
  var missing = default(StateStore)
  assert owner.rpc.publishAccumulation(missing, default(PreparedFinalAccumulation),
    completionLimits().composition).error == RpcAccumulationError.Unavailable
  var view = default(ChainView)
  assert owner.rpc.publishAccumulation(missing, view, default(PreparedFinalAccumulation),
    completionLimits().composition).error == RpcAccumulationError.Unavailable
  assert not owner.rpc.start(0, "cannot replace pause"), "paused start is inert"
  var peer = -1.cint
  if network:
    peer = client(rpcPort)
    sendText(peer, "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n", false)
    let ui = client(uiPort)
    sendText(ui, "GET / HTTP/1.1\r\nHost: localhost\r\nAccept-Encoding: gzip\r\n\r\n", false)
    var response = ""
    for turn in 0..<200:
      owner.tick(0)
      owner.rpc.tick(0) # Even direct access to the public RPC owner observes the pause.
      var buffer = default(array[4096, char])
      let count = receive(ui, addr buffer[0], csize_t(buffer.len), 0)
      if count > 0:
        for index in 0..<count: response.add(buffer[
            index]) # Only initialized independent HTTP bytes enter the test.
      if response.contains("\r\n\r\n"): break # UI must progress even though RPC is frozen.
      discard pauseMicros(1000)
    assert response.startsWith("HTTP/1.1 200"), "independent UI progresses during graph lease"
    discard posix.close(ui)
    var byte = '\0'
    assert receive(peer, addr byte, 1, 0) < 0, "RPC upgrade remains pending while paused"
  owner.waitDone()
  assert owner.preparationActive and not owner.preparationAvailable, "Done still holds exclusion"
  let completion = owner.collectPreparation(admitted.value)
  assert completion.kind == PreparationCompletionKind.Completed
  assert not owner.preparationActive and not owner.rpc.chainPaused and owner.preparationAvailable
  let prepared = completion.value
  assert prepared.error == BlockInputError.None, "genuine signed child execution"
  assert sameStateSnapshot(before, prepared.value.finalAccumulationParent.value), "exact canonical parent"
  assert sameStateSnapshot(before, owner.stateSnapshot.value), "worker has not published canonical state"
  assert owner.enqueueAccumulation(prepared.value, completionLimits().composition) ==
      AccumulationEnqueueError.None
  assert not owner.preparationAvailable, "pending adoption prevents a new worker lease"
  owner.tick(0)
  assert owner.takeAccumulation().error == ApplicationChainError.None, "host deferred adoption succeeds"
  assert owner.chainView.retainedCount == 2
  if network:
    var pending = ""
    assert readPacket(owner.rpc, peer, pending, true).startsWith("HTTP/1.1 101"), "RPC resumes preserved upgrade"
    sendText(peer, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ragnarok_clientInfo\"}")
    assert readPacket(owner.rpc, peer, pending).contains("lease test"), "RPC queries resume"
    discard posix.close(peer)
  assert owner.collectPreparation(admitted.value).kind == PreparationCompletionKind.Uninitialized
  for iteration in 0..<10:
    let next = receive(owner, input, @[255'u8])
    let later = owner.beginPreparation(input, next)
    assert later.error == PreparationError.None
    assert not owner.cancelPreparation(admitted.value), "old ticket cannot cancel reused worker"
    assert owner.cancelPreparation(later.value)
    owner.waitDone()
    assert owner.preparationActive and owner.rpc.chainPaused, "cancellation keeps graph gate"
    assert owner.collectPreparation(later.value).kind == PreparationCompletionKind.Cancelled
    assert not owner.preparationActive and not owner.rpc.chainPaused
    discard input.cancel(next) # Queued cancellation may leave the raw receiver ready; collection has ended its lease.
  let last = receive(owner, input, @[255'u8])
  assert owner.beginPreparation(input, last).error == PreparationError.None
  owner.close() # Join before freeing RPC's shared history or the canonical owner.
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  discard input.cancel(last)

proc main() {.raises.} =
  ## Use the pinned independent report to build one genuine signed two-guest child and complete configured parent.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet) # Detach initialized fixture bytes before decode.
  let context = fixture(decodeOwnedReport(bytes, 2).value)
  let owner = candidateBlock(context)
  var wire = newSeq[byte](owner.blockInfo.value.consumed)
  let source = Block(header: owner.blockHeader.value, extrinsic: owner.blockExtrinsic.value)
  assert encodeBlock(source, preparationLimits().reporting.admission.frame, wire).error ==
      FrameError.None
  scenario(context, wire, false)
  scenario(context, wire, true)
  echo "Application preparation lease passed"

try:
  main() # File or native startup failures are independent native-suite failures.
except:
  quit(2)
