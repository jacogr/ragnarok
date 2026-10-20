# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_services"}

## Service-owned configured state, exact RPC seeding, adoption and shutdown/restart without a running peer.

import std/[assertions, syncio, envvars, strutils, nativesocket]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/chain
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/rpc/[server, protocol]
import ../../../src/json_writer
import ../../../src/codec/[header, bounded, report_owned, state_layout, state_trie]
import ../../../src/state/[store, accumulation_state, accumulation_chain, accumulation_completion,
  accumulation_finalization, accumulation_times, accumulation_statistics, accumulation_validators,
  accumulation_activity, accumulation_round, accumulation_queue, accumulation_runner,
  accumulation_driver, report_admission, block_transition, block_admission]
import ../../support/[accumulation_activity_context, accumulation_completion_context,
  accumulation_execution_context, accumulation_runner_context, arc_evidence]
import ../../support/report_admission_context as report_fixture

# Backend faults begin after all authored source/context bytes are independently retained.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

type SeedFixture = object ## Test text comes from a genuine signed original parent; its original certificate remains a separate owner.
  text: string
  source: PreparedFinalAccumulation

proc hex(value: openArray[byte]): string =
  ## Emit canonical lowercase hexadecimal independently of the production configuration decoder.
  result = ""
  for octet in value: result.add(toHex(int(octet), 2).toLowerAscii())

proc policy(writes = 1000'u64, bytes = 1000000'u64): StateStoreLimits =
  ## Writable mutation ceilings are caller decisions; fixed trie capture ceilings retain the legacy limits.
  result = genesisStoreLimits()
  result.writes = ElementLimit(writes)
  result.writeValueBytes = ByteLimit(bytes)

proc fixture(base: OwnedReport): SeedFixture =
  ## Capture all original entries of an empty signed block, including opaque and service chapters.
  let authored = activityFixture(base)
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let parent = source.finalAccumulationParent.value
  let bound = source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  var wire = newSeq[byte](bound.admittedParent.headerInfo.value.consumed)
  assert encodeOwnedHeader(bound.admittedParent, wire).error == HeaderError.None
  var state = JsonObject()
  for index in 0..<parent.commitment.entries:
    let key = parent.keyAt(StateEntryIndex(index)).value
    let value = parent.lookup(key).value.bytes
    state.add(hex(array[31, byte](key)), json(hex(value)))
  let text = $jsonObject([("protocol_parameters", json(hex(runnerParameters().encodeParameters))),
    ("genesis_header", json(hex(wire))), ("genesis_state", json(state))])
  SeedFixture(text: text, source: source)

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
proc openSocket(domain, kind, protocol: cint): cint {.importc: "socket", header: "<sys/socket.h>".}
proc bindPort(fd: cint, address: pointer, length: SockLen): cint {.importc: "bind",
    header: "<sys/socket.h>".}
proc socketName(fd: cint, address: pointer, length: ptr SockLen): cint {.importc: "getsockname",
    header: "<sys/socket.h>".}
proc connectPort(fd: cint, address: pointer, length: SockLen): cint {.importc: "connect",
    header: "<sys/socket.h>".}
proc networkPort(port: uint16): uint16 {.importc: "htons", header: "<netinet/in.h>".}
proc hostPort(port: uint16): uint16 {.importc: "ntohs", header: "<netinet/in.h>".}
proc ipv4(text: cstring): uint32 {.importc: "inet_addr", header: "<arpa/inet.h>".}
proc sendBytes(fd: cint, data: pointer, length: csize_t, flags: cint): int {.importc: "send",
    header: "<sys/socket.h>".}
proc receive(fd: cint, data: pointer, length: csize_t, flags: cint): int {.importc: "recv",
    header: "<sys/socket.h>".}

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

proc execution(owner: var Services, context: SeedFixture): PreparedFinalAccumulation =
  ## Re-admit the actual signed empty block against the decoded seed, then use only existing PVM execution/finalization owners.
  let bound = context.source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  var working = forkStateStore(owner.stateSnapshot.value).value
  let staged = report_fixture.stage(working, bound.admittedBlock, bound.admittedParent)
  assert staged.error == BlockTransitionError.None
  let reports = planBlockReports(staged, [], report_fixture.config())
  assert reports.error == ReportAdmissionError.None
  let queue = planBlockAccumulationQueue(reports.value, executionQueueConfig()).value
  let round = planBlockInitialAccumulation(queue, executionRoundConfig()).value
  let parameters = owner.chainView.bestBlock.value.chainParameters
  let initial = runBlockAccumulation(round, parameters, runnerLimits()).value
  let stopped = driveAccumulation(initial, parameters, completionDriverLimits()).value
  result = prepareFinalAccumulation(stopped, completionLimits().finalization).value
  assert sameStateSnapshot(result.finalAccumulationParent.value, owner.stateSnapshot.value)


const SeedPath = "application-services-chain.json"

proc configured(port = 0'u16): Options =
  ## Telemetry-only options exercise disabled RPC without making a collector connection.
  result = default(Options)
  var arguments = @["server", "--chain", SeedPath]
  if port == 0:
    for value in ["--with-telemetry", "--telemetry", "127.0.0.1:1"]:
      arguments.add(value) # The pinned sequence API appends individual owned values.
  else:
    for value in ["--with-rpc", "--rpc-port", $port]:
      arguments.add(value) # Preserve the validated explicit listener port.
  assert parseOptions(arguments, result)

proc reservation(): tuple[fd: cint, port: uint16] =
  ## Keep an OS-assigned loopback port occupied until the caller deliberately releases it.
  let probe = openSocket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert probe >= 0
  var selected = address(0)
  assert bindPort(probe, addr selected, SockLen(sizeof(selected))) == 0
  var size = SockLen(sizeof(selected))
  assert socketName(probe, addr selected, addr size) == 0
  (probe, hostPort(selected.sin_port))

proc listener(owner: var Services): uint16 {.raises.} =
  ## Retry only the bounded release/bind race; each successful listener uses explicit state policy.
  for attempt in 0..<8:
    let reserved = reservation()
    discard posix.close(reserved.fd)
    if owner.start(configured(reserved.port), "test", policy()): return reserved.port
  assert false, "ephemeral Services startup failed"
  0'u16

proc local(context: SeedFixture) {.raises.} =
  ## No-RPC ownership survives adoption and old readers; close/restart resets exact parent authority.
  writeFile(SeedPath, context.text)
  let options = configured()
  failHash(0)
  discard initApplicationChain(context.text, policy()).value
  let cost = hashCalls()
  failHash(0)
  var owner = default(Services)
  assert owner.start(options, "test", policy())
  assert hashCalls() == cost, "service startup commits one map and hashes one header"
  let old = owner.stateSnapshot.value
  assert sameStateSnapshot(old, owner.chainView.bestBlock.value.stateSnapshot)
  writeFile(SeedPath, "invalid")
  failHash(1)
  assert not owner.start(options, "test", policy()) and hashCalls() == 0
  assert sameStateSnapshot(old, owner.stateSnapshot.value)
  failHash(0)
  let final = execution(owner, context)
  let applied = owner.applyAccumulation(final, completionLimits().composition)
  assert applied.error == ApplicationChainError.None
  assert sameStateSnapshot(applied.value.stateSnapshot, owner.stateSnapshot.value)
  assert owner.chainView.retainedCount == 2
  assert old.lookup(chapterKey(StateChapter(11))).value.bytes == @[1'u8, 0, 0, 0]
  owner.close()
  owner.close()
  failHash(1)
  let closed = owner.applyAccumulation(final, completionLimits().composition)
  assert closed.chainFailure.stateError == StateStoreError.Uninitialized and hashCalls() == 0
  failHash(0)
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  assert owner.chainView.bestBlock.error == GenesisError.Unavailable
  assert not owner.start(options, "test", policy()), "restart reads a new file instead of reviving stale state"
  writeFile(SeedPath, context.text)
  assert owner.start(options, "test", policy())
  assert not sameStateSnapshot(old, owner.stateSnapshot.value)
  failHash(1)
  let stale = owner.applyAccumulation(final, completionLimits().composition)
  assert stale.chainFailure.error == AccumulationChainError.StaleState and hashCalls() == 0
  failHash(0)
  owner.close()

proc rpc(context: SeedFixture) {.raises.} =
  ## Enabled RPC shares the exact decoded seed, emits genuine adoption, and never falls back after closure.
  writeFile(SeedPath, context.text)
  var owner = default(Services)
  failHash(0)
  discard initApplicationChain(context.text, policy()).value
  let cost = hashCalls()
  failHash(0)
  let port = listener(owner)
  assert hashCalls() == cost, "RPC reuses the seed without another map/header hash"
  let before = owner.stateSnapshot.value
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  sendText(peer, "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", false)
  assert "101 Switching Protocols" in readPacket(owner.rpc, peer, pending, true)
  sendText(peer, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}""")
  assert "\"result\":1" in readPacket(owner.rpc, peer, pending)
  assert "\"slot\":1" in readPacket(owner.rpc, peer, pending)
  let final = execution(owner, context)
  let applied = owner.applyAccumulation(final, completionLimits().composition)
  assert applied.error == ApplicationChainError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, owner.chainView.bestBlock.value.stateSnapshot)
  assert "\"slot\":2" in readPacket(owner.rpc, peer, pending)
  sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
  assert "\"slot\":2" in readPacket(owner.rpc, peer, pending)
  let head = owner.stateSnapshot.value
  owner.rpc.close()
  failHash(1)
  let unavailable = owner.applyAccumulation(final, completionLimits().composition)
  assert unavailable.rpcFailure.error == RpcAccumulationError.Unavailable and hashCalls() == 0
  assert sameStateSnapshot(head, owner.stateSnapshot.value)
  failHash(0)
  owner.close()
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  assert before.lookup(chapterKey(StateChapter(11))).value.bytes == @[1'u8, 0, 0, 0]

proc refusals(context: SeedFixture) {.raises.} =
  ## All seed/UI/listener failures retire partial ownership and permit a later independent startup.
  var owner = default(Services)
  assert not owner.start(default(Options), "test", policy())
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  let options = configured()
  writeFile(SeedPath, "{}")
  assert not owner.start(options, "test", policy())
  writeFile(SeedPath, context.text)
  var short = policy()
  short.trie.items = ElementLimit(0)
  assert not owner.start(options, "test", short)
  failHash(1)
  assert not owner.start(options, "test", policy())
  failHash(0)
  discard initApplicationChain(context.text, policy()).value
  let cost = hashCalls()
  failAfter(cost - 1)
  assert not owner.start(options, "test", policy())
  failHash(0)
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  let reserved = reservation()
  let uiPort = reservation()
  discard posix.close(uiPort.fd)
  var partial = default(Options)
  assert parseOptions(@["server", "--with-ui", "--chain", SeedPath,
    "--rpc-port", $reserved.port, "--ui-port", $uiPort.port], partial)
  assert not owner.start(partial, "test", policy())
  let probe = openSocket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert probe >= 0
  var released = address(uiPort.port)
  assert bindPort(probe, addr released, SockLen(sizeof(released))) == 0, "RPC refusal releases the opened UI listener"
  discard posix.close(probe)
  discard posix.close(reserved.fd)
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  var ui = default(Options)
  assert parseOptions(@["server", "--with-ui", "--chain", SeedPath,
    "--dev-ui-dir", "missing-application-services-ui"], ui)
  assert not owner.start(ui, "test", policy())
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  assert owner.start(options, "test", policy())
  owner.close()
  var missing = default(Options)
  let missingPort = reservation()
  discard posix.close(missingPort.fd)
  assert parseOptions(@["server", "--with-rpc", "--rpc-port", $missingPort.port], missing)
  assert not owner.start(missing, "test", policy())
  failHash(1)
  assert owner.start(missing, "test"), "legacy unavailable genesis still starts without state/hash work"
  assert hashCalls() == 0 and owner.stateSnapshot.error == StateStoreError.Uninitialized
  failHash(0)
  owner.close()

proc cycle(options: Options, explicitClose: bool) {.raises.} =
  ## Both explicit idempotent close and implicit destruction retire the complete seed/text graph.
  var owner = default(Services)
  assert owner.start(options, "test", policy())
  if explicitClose:
    owner.close()
    owner.close()
    assert owner.stateSnapshot.error == StateStoreError.Uninitialized

proc main() {.raises.} =
  ## Build authentic authority once, then test file/listener lifecycle and allocation-stable independent startup.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let context = fixture(decodeOwnedReport(wire, 2).value)
  defer: discard posix.unlink("application-services-chain.json")
  local(context)
  rpc(context)
  refusals(context)
  writeFile(SeedPath, context.text)
  let options = configured()
  cycle(options, true)
  cycle(options, false)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(options, iteration mod 2 ==
      0) # Each full graph leaves scope before measurement.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_services", 1000, before, after)
  echo "Application service state lifecycles passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # File I/O errors must fail the native suite.
except:
  quit(2)
