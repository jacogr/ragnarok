# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_chain_arc_release"}

## Public application ownership and RPC joining through real ephemeral loopback WebSocket clients.

import std/[assertions, envvars, syncio, base64, strutils, nativesocket]
import std/posix/posix
import ../../../src/app/chain
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/rpc/[server, protocol]
import ../../../src/codec/[header, bounded, report_owned]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/state/store
import ../../../src/state/accumulation/[chain as accumulation_chain, state as accumulation_state,
    completion as accumulation_completion, finalization as accumulation_finalization,
    times as accumulation_times, statistics as accumulation_statistics,
    validators as accumulation_validators, activity as accumulation_activity,
    consensus as accumulation_consensus]
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/accumulation/publication as accumulation_publication
import ../../support/[accumulation_activity_context, accumulation_completion_context, arc_evidence]

# Primitive refusal begins after genuine signed source and retained view construction.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
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

type Fixture = object ## Authentic finalized source and its exact original complete-map chain parent.
  source: PreparedFinalAccumulation
  parent: BlockSnapshotResult

const
  Best = """{"jsonrpc":"2.0","method":"bestBlock","id":1}"""
  Subscribe = """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}"""

proc settings(): ParameterResult =
  ## Decode one complete fixture tuple with two cores and a twelve-slot epoch.
  decodeParametersHex("ffffffffffffffff020000000000000003000000000000000200050000000c0000000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c0000000a000000")

proc bytes(owner: OwnedHeader): seq[byte] =
  ## Re-emit the immutable sealed header under its measured exact extent.
  result = newSeq[byte](owner.headerInfo.value.consumed)
  assert encodeOwnedHeader(owner, result).error == HeaderError.None

proc fixture(base: OwnedReport, incoming = false, disputed = false, ticket = false,
    rotated = false, writes = 1000'u64): Fixture =
  ## Sign and execute through existing shared fixtures instead of manufacturing successful source owners.
  let authored = activityFixture(base, guarantees = (if incoming: 2 else: 0), available = incoming,
    blobs = incoming, provided = incoming, withDispute = disputed, withTicket = ticket,
    shiftPending = rotated, slot = (if rotated: 12'u32 else: 2'u32), storeWrites = writes)
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let bound = source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  let parent = captureBlockSnapshot(bytes(bound.admittedParent),
      source.finalAccumulationParent.value, settings().value)
  assert parent.error == GenesisError.None
  Fixture(source: source, parent: parent)

proc initialized(context: Fixture): ApplicationChain =
  ## Explicit parent finality is inherited by the canonical owner and independent copied branches.
  let view = genesisView(context.parent).finalizeView(context.parent.value.blockHash).value
  initApplicationChain(view).value

proc witness(context: Fixture) =
  ## No listener is required; the owner uses exactly one existing state/chain adoption and retains old aliases.
  let policy = completionLimits().composition
  failHash(1)
  var owner = initialized(context)
  assert hashCalls() == 0 and sameChainView(owner.chainView, initialized(context).chainView)
  failHash(0)
  let old = owner
  let before = owner.stateSnapshot.value
  var expectedState = forkStateStore(before).value
  var expectedView = old.chainView
  failHash(0)
  let expected = applyAccumulationChain(expectedState, expectedView, context.source, policy).value
  let cost = hashCalls()
  failHash(0)
  let applied = owner.applyAccumulation(context.source, policy)
  assert applied.error == ApplicationChainError.None
  assert hashCalls() == cost
  let child = applied.value
  assert sameStateSnapshot(child.stateSnapshot, owner.stateSnapshot.value)
  assert sameStateSnapshot(child.stateSnapshot, owner.chainView.bestBlock.value.stateSnapshot)
  assert array[32, byte](child.stateRoot) == array[32, byte](expected.stateRoot)
  assert owner.chainView.retainedCount == 2 and old.chainView.retainedCount == 1
  assert sameStateSnapshot(old.stateSnapshot.value, before)
  assert sameStateSnapshot(owner.chainView.finalizedBlock.value.stateSnapshot, before)
  var branch = old
  assert branch.applyAccumulation(context.source, policy).error == ApplicationChainError.None
  assert sameStateSnapshot(old.stateSnapshot.value, before)
  failHash(1)
  let replay = owner.applyAccumulation(context.source, policy)
  assert replay.chainFailure.error == AccumulationChainError.StaleState and hashCalls() == 0
  failHash(0)
  assert not sameChainView(owner.chainView, genesisView(owner.chainView.bestBlock)), "retained window is part of the selected view"

proc views(context: Fixture) =
  ## Exact history comparison includes profiles, state version identity and explicit finality, without hashing.
  let view = genesisView(context.parent)
  let finalized = view.finalizeView(context.parent.value.blockHash).value
  let parent = context.source.finalAccumulationParent.value
  var entries: seq[StateEntry] = @[]
  for index in 0..<parent.commitment.entries:
    let key = parent.keyAt(StateEntryIndex(index)).value
    entries.add(StateEntry(key: key, value: parent.lookup(
        key).value.bytes)) # Independent equal-root reconstruction has a different owner.
  let wire = bytes(context.parent.value.header)
  let rebuilt = captureBlockSnapshot(wire, entries, settings().value)
  var parameterWire = settings().value.encodeParameters
  parameterWire[0] = parameterWire[0] xor 1 # Alter a non-framing parameter while preserving header bytes and exact state identity.
  let profiled = captureBlockSnapshot(wire, parent, decodeParameters(parameterWire).value)
  failHash(1)
  assert sameChainView(view, view) and sameChainView(finalized, finalized)
  assert not sameChainView(view, finalized)
  assert not sameChainView(view, genesisView(rebuilt))
  assert not sameChainView(view, genesisView(profiled))
  let empty = default(ChainView)
  assert not sameChainView(empty, empty)
  assert not sameChainView(view, empty)
  assert hashCalls() == 0
  failHash(0)
  let readonly = initApplicationChain(genesisView(rebuilt)).value
  var fork = forkStateStore(readonly.stateSnapshot.value).value
  assert fork.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
    value: @[1'u8])]).error == StateStoreError.LimitExceeded, "constructor preserves raw capture's readonly policy"
  let missing = initApplicationChain(default(ChainView))
  assert missing.error == ApplicationChainError.MissingHead
  let absent = default(ApplicationChain)
  assert absent.stateSnapshot.error == StateStoreError.Uninitialized
  assert absent.chainView.bestBlock.error == GenesisError.Unavailable

proc address(port: uint16): Sockaddr_in =
  ## Native addresses use the real OS-selected loopback port and explicit initialization on every platform.
  result = default(Sockaddr_in)
  result.sin_family = TSa_Family(ord(nativesocket.AF_INET))
  result.sin_port = networkPort(port)
  result.sin_addr.s_addr = ipv4("127.0.0.1")
  when defined(macosx):
    result.sin_len = uint8(sizeof(result)) # Darwin requires the native address extent.

proc listener(rpc: var Server, parent: BlockSnapshotResult): uint16 =
  ## Select an ephemeral port; retry the bounded reservation/start race without fixed ports or private server fields.
  for attempt in 0..<8:
    let probe = openSocket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
    assert probe >= 0
    var selected = address(0)
    assert bindPort(probe, addr selected, SockLen(sizeof(selected))) == 0
    var size = SockLen(sizeof(selected))
    assert socketName(probe, addr selected, addr size) == 0
    let port = hostPort(selected.sin_port)
    discard posix.close(probe)
    if rpc.start(port, "test", settings(), parent): return port # Only a real successfully owned listener is returned.
  assert false, "ephemeral RPC startup failed"
  0'u16

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

proc rpcWitness(context: Fixture) =
  ## Public RPC/application APIs update all three handles before an observable subscriber event.
  let policy = completionLimits().composition
  var rpc = default(Server)
  let port = listener(rpc, context.parent)
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  sendText(peer, "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", false)
  assert "101 Switching Protocols" in readPacket(rpc, peer, pending, true)
  sendText(peer, Subscribe)
  assert "\"result\":1" in readPacket(rpc, peer, pending)
  assert "\"slot\":1" in readPacket(rpc, peer, pending)
  var owner = initApplicationChain(genesisView(context.parent)).value
  let old = owner
  assert rpc.publishFinalized(context.parent.value.blockHash) == ViewFinalizeError.None
  failHash(1)
  let mismatch = owner.applyAccumulation(rpc, context.source, policy)
  assert mismatch.rpcFailure.error == RpcAccumulationError.StaleView and hashCalls() == 0
  failHash(0)
  owner = initialized(context) # Explicitly align the application with caller-certified finality before retrying.
  var expectedState = forkStateStore(owner.stateSnapshot.value).value
  var expectedView = owner.chainView
  failHash(0)
  discard applyAccumulationChain(expectedState, expectedView, context.source, policy).value
  let cost = hashCalls()
  failAfter(cost - 1)
  let refused = owner.applyAccumulation(rpc, context.source, policy)
  failHash(0)
  assert refused.rpcFailure.chainFailure.error == AccumulationChainError.CaptureFailure
  sendText(peer, Best)
  let unchanged = readPacket(rpc, peer, pending)
  assert "\"slot\":1" in unchanged and "\"method\"" notin unchanged, "refusal queues no event ahead of the old-head reply"
  failHash(0)
  let applied = owner.applyAccumulation(rpc, context.source, policy)
  assert applied.error == ApplicationChainError.None and hashCalls() == cost
  let child = applied.value
  assert sameStateSnapshot(child.stateSnapshot, owner.stateSnapshot.value)
  assert sameStateSnapshot(child.stateSnapshot, owner.chainView.bestBlock.value.stateSnapshot)
  let event = readPacket(rpc, peer, pending)
  assert "subscribeBestBlock" in event and base64.encode(array[32, byte](child.blockHash)) in event
  sendText(peer, Best)
  assert base64.encode(array[32, byte](child.blockHash)) in readPacket(rpc, peer, pending)
  failHash(1)
  let replay = owner.applyAccumulation(rpc, context.source, policy)
  assert replay.rpcFailure.chainFailure.error == AccumulationChainError.StaleState and hashCalls() == 0
  failHash(0)
  assert sameStateSnapshot(old.stateSnapshot.value, context.source.finalAccumulationParent.value)
  rpc.close()
  failHash(1)
  let unavailable = owner.applyAccumulation(rpc, context.source, policy)
  assert unavailable.rpcFailure.error == RpcAccumulationError.Unavailable and hashCalls() == 0
  failHash(0)
  var fresh = initialized(context)
  assert fresh.applyAccumulation(context.source, policy).error == ApplicationChainError.None, "disabled RPC cannot block the explicit independent path"
  var short = default(Server)
  discard listener(short, owner.chainView.bestBlock) # Same head/map but a shorter retained window cannot overwrite application history.
  assert short.publishFinalized(child.blockHash) == ViewFinalizeError.None
  var windowOwner = initApplicationChain(owner.chainView.finalizeView(child.blockHash).value).value
  failHash(1)
  let window = windowOwner.applyAccumulation(short, default(PreparedFinalAccumulation), policy)
  assert window.rpcFailure.error == RpcAccumulationError.StaleView and hashCalls() == 0
  failHash(0)
  short.close()

proc preparedRpcWitness(context: Fixture) =
  ## Prepare once, preflight exact lease/view authority, then install before any best-head notification.
  var rpc = default(Server)
  let port = listener(rpc, context.parent)
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  sendText(peer, "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", false)
  assert "101 Switching Protocols" in readPacket(rpc, peer, pending, true)
  sendText(peer, Subscribe)
  assert "\"result\":1" in readPacket(rpc, peer, pending)
  assert "\"slot\":1" in readPacket(rpc, peer, pending)
  var owner = initApplicationChain(genesisView(context.parent)).value
  let before = owner
  let prepared = owner.prepareAccumulation(context.source, completionLimits().composition).value
  assert sameChainView(owner.chainView, before.chainView)
  let lease = rpc.pauseChain()
  assert lease != nil
  failHash(1)
  assert owner.canInstallPrepared(prepared)
  assert not owner.canInstallPrepared(rpc, prepared)
  assert owner.canInstallPrepared(rpc, prepared, lease)
  let alternate = initialized(context)
  assert not alternate.canInstallPrepared(rpc, prepared, lease)
  owner.installPrepared(rpc, prepared, lease)
  assert hashCalls() == 0 and sameStateSnapshot(owner.stateSnapshot.value, prepared.stateSnapshot)
  assert not owner.canInstallPrepared(rpc, prepared, lease)
  assert rpc.resumeChain(lease)
  let event = readPacket(rpc, peer, pending)
  assert "subscribeBestBlock" in event and base64.encode(array[32, byte](
      prepared.child.blockHash)) in event
  sendText(peer, Best)
  assert base64.encode(array[32, byte](prepared.child.blockHash)) in readPacket(rpc, peer, pending)
  assert sameChainView(before.chainView, genesisView(context.parent))
  rpc.close()
  failHash(0)

proc cycle(context: Fixture) =
  ## Independent success, stale replay and late quota refusal release all private application branches each cycle.
  let policy = completionLimits().composition
  var owner = initialized(context)
  var refused = owner
  let before = owner.stateSnapshot.value
  assert owner.applyAccumulation(context.source, policy).error == ApplicationChainError.None
  assert owner.applyAccumulation(context.source, policy).chainFailure.error ==
      AccumulationChainError.StaleState
  var short = policy
  short.consensus.chapterBytes = ByteLimit(0)
  let failure = refused.applyAccumulation(context.source, short)
  assert failure.chainFailure.applicationFailure.compositionFailure.error ==
      AccumulationCompletionError.ConsensusFailure
  assert sameStateSnapshot(refused.stateSnapshot.value, before)

proc main() {.raises.} =
  ## Real signed sources exercise public constructors/methods; primitive failure never fabricates a successful owner.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  witness(fixture(base))
  let context = fixture(base, incoming = true)
  witness(context)
  witness(fixture(base, disputed = true))
  witness(fixture(base, ticket = true))
  witness(fixture(base, rotated = true))
  views(context)
  rpcWitness(context)
  preparedRpcWitness(context)
  let cappedSource = fixture(base, writes = 6)
  var capped = initialized(cappedSource)
  let limited = capped.applyAccumulation(cappedSource.source, completionLimits().composition)
  assert limited.chainFailure.applicationFailure.compositionFailure.consensusFailure.stateError ==
      StateStoreError.LimitExceeded
  assert sameStateSnapshot(capped.stateSnapshot.value,
      cappedSource.source.finalAccumulationParent.value)
  var detached = default(BlockSnapshot)
  block:
    let local = fixture(base)
    var owner = initialized(local)
    detached = owner.applyAccumulation(local.source, completionLimits().composition).value # Retain the complete child past owner/source lifetime.
  assert detached.lookup(chapterKey(StateChapter(11))).value.bytes == @[2'u8, 0, 0, 0]
  cycle(context)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context) # Private working maps and copied owner pairs leave scope on every path.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_chain", 1000, before, after)
  echo "Application-owned accumulation chain passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O errors must fail the native suite.
except:
  quit(2)
