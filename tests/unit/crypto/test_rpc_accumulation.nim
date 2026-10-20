# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "rpc_accumulation_arc_release"}

## Signed dispatcher adoption with real nonblocking sockets, ordered notifications and atomic failure isolation.

import std/[assertions, syncio, envvars, base64]
import ../../../src/codec/[header, bounded, report_owned, state_layout, state_trie]
import ../../../src/state/[accumulation_state, accumulation_consensus, accumulation_times,
  accumulation_statistics, accumulation_validators, accumulation_activity, report_admission,
  block_transition, block_admission]
import ../../support/[accumulation_activity_context, accumulation_completion_context, arc_evidence]
include ../../../src/rpc/server

# Backend refusal begins only after genuine signed owners and native transport fixtures exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc rpcPair(domain, kind, protocol: cint, pair: pointer): cint {.importc: "socketpair",
    header: "<sys/socket.h>".}

const
  Best = """{"jsonrpc":"2.0","method":"bestBlock","id":1}"""
  Subscribe = """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}"""
  Statistics = """{"jsonrpc":"2.0","method":"subscribeStatistics","params":[false],"id":3}"""
  Finalized = """{"jsonrpc":"2.0","method":"subscribeFinalizedBlock","params":[],"id":4}"""

type RpcFixture = object ## Execution provenance and structural parent both retain the exact original state version.
  source: PreparedFinalAccumulation
  parent: BlockSnapshotResult

proc settings(): ParameterResult =
  ## Use the signed fixture's complete tuple with two cores and twelve slots per epoch.
  decodeParametersHex("ffffffffffffffff020000000000000003000000000000000200050000000c0000000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c0000000a000000")

proc headerBytes(owner: OwnedHeader): seq[byte] =
  ## Copy only the immutable sealed-header extent for structural parent fixture capture.
  result = newSeq[byte](owner.headerInfo.value.consumed)
  assert encodeOwnedHeader(owner, result).error == HeaderError.None

proc fixture(base: OwnedReport, incoming = false, disputed = false, ticket = false,
    rotated = false): RpcFixture =
  ## Genuinely sign/execute/finalize each scenario using the existing shared effect-selection fixture.
  let authored = activityFixture(base, guarantees = (if incoming: 2 else: 0), available = incoming,
    blobs = incoming, provided = incoming, withDispute = disputed, withTicket = ticket,
    shiftPending = rotated, slot = (if rotated: 12'u32 else: 2'u32))
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let binding = source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  let parent = captureBlockSnapshot(headerBytes(binding.admittedParent),
      source.finalAccumulationParent.value,
    settings().value)
  assert parent.error == GenesisError.None
  RpcFixture(source: source, parent: parent)

proc opened(owner: var Server, context: RpcFixture) =
  ## Own an actual ephemeral loopback listener without a fixed test port; never forge descriptor ownership.
  owner.fd = socket(cint(ord(nativesocket.AF_INET)), cint(ord(nativesocket.SOCK_STREAM)), 0)
  assert owner.fd >= 0
  owner.opened = true
  var address = default(Sockaddr_in)
  address.sin_family = TSa_Family(ord(nativesocket.AF_INET))
  when defined(macosx):
    address.sin_len = uint8(sizeof(address)) # BSD requires the native address extent.
  var loopback = "127.0.0.1"
  assert nonblocking(owner.fd)
  assert parseAddress(cint(ord(nativesocket.AF_INET)), loopback.toCString(),
      addr address.sin_addr) == 1
  assert bindSocket(owner.fd, addr address, SockLen(sizeof(address))) == 0
  assert listenSocket(owner.fd, 1) == 0
  owner.parameters = settings()
  owner.chain = genesisView(context.parent).finalizeView(context.parent.value.blockHash).value

proc connected(owner: var Server, index: int): cint =
  ## Transfer one real socket-pair endpoint into a server slot; the caller owns and closes the peer endpoint.
  var pair = default(array[2, cint])
  assert rpcPair(cint(ord(nativesocket.AF_UNIX)), cint(ord(nativesocket.SOCK_STREAM)), 0, addr pair[0]) == 0
  owner.connections[index].fd = pair[0]
  owner.connections[index].opened = true
  owner.connections[index].upgraded = true
  owner.connections[index].deadline = getMonoTime().ticks div 1_000_000 + 30000
  assert nonblocking(pair[0]) and nonblocking(pair[1])
  pair[1]

proc info(owner: var Server): ClientInfo =
  ## Copy the same immutable view/parameters that tick places in one request context.
  ClientInfo(chain: owner.chain, parameters: owner.parameters)

proc receiveFrame(peer: cint): string =
  ## Read a required small frame from a nonblocking peer; absence fails immediately rather than hanging.
  var buffer = default(array[8192, char])
  let count = receive(peer, addr buffer[0], csize_t(buffer.len), 0)
  assert count > 0
  result = ""
  for index in 0..<count: result.add(buffer[index]) # Copy only initialized native receive bytes.

proc masked(payload: string): string =
  ## Construct an independently masked canonical client text frame for a bounded request.
  assert payload.len < 126
  result = "\x81" & $char(128 or payload.len) & "abcd"
  for index, octet in payload: result.add(char(ord(octet) xor ord("abcd"[index mod 4])))

proc sameQueue(left, right: RpcSession) =
  ## Observe copies so comparing pending events cannot consume either live session.
  var a = left
  var b = right
  for index in 0..MaxSubscriptionUpdates:
    let first = a.nextUpdate()
    let second = b.nextUpdate()
    assert first == second
    if first.len == 0: return # Both bounded queues have been fully compared.
  assert false, "subscription queue did not terminate"

proc witness(context: RpcFixture) =
  ## Existing queued replies precede accepted best/statistics events; a later request sees the paired successor.
  let policy = completionLimits().composition
  let parent = context.source.finalAccumulationParent.value
  var state = forkStateStore(parent).value
  var owner = default(Server)
  opened(owner, context)
  let peer = connected(owner, 0)
  let finalPeer = connected(owner, 1)
  let plainPeer = connected(owner, 2)
  defer:
    discard posix.close(peer)
    discard posix.close(finalPeer)
    discard posix.close(plainPeer)
  let previous = owner.info
  discard respond(Subscribe, previous, owner.connections[0].session)
  discard respond(Statistics, previous, owner.connections[0].session)
  discard owner.connections[0].session.nextUpdate()
  discard owner.connections[0].session.nextUpdate()
  discard respond(Finalized, previous, owner.connections[1].session)
  discard owner.connections[1].session.nextUpdate()
  var oracleSession = owner.connections[0].session
  var oracleState = state
  var oracleView = owner.chain
  failHash(0)
  let expected = applyAccumulationChain(oracleState, oracleView, context.source, policy).value
  let expectedHashes = hashCalls()
  let queued = frame(respond(Best, previous))
  owner.connections[0].output = queued
  owner.connections[0].offset = 5
  owner.connections[0].input = "\x81"
  let deadline = owner.connections[0].deadline
  let listener = owner.fd
  let endpoint = owner.connections[0].fd
  failHash(0)
  let published = owner.publishAccumulation(state, context.source, policy)
  assert published.error == RpcAccumulationError.None
  assert hashCalls() == expectedHashes, "RPC publication adds no duplicate state, header or append work"
  let child = published.value
  assert sameStateSnapshot(state.snapshot.value, child.stateSnapshot)
  assert sameStateSnapshot(owner.chain.bestBlock.value.stateSnapshot, child.stateSnapshot)
  assert array[32, byte](child.stateRoot) == array[32, byte](expected.stateRoot)
  assert owner.fd == listener and owner.connections[0].fd == endpoint
  assert owner.connections[0].output == queued and owner.connections[0].offset == 5
  assert owner.connections[0].input == "\x81" and owner.connections[0].deadline == deadline
  assert oracleSession.queueChainUpdates(owner.chain.bestBlock)
  let bestEvent = oracleSession.nextUpdate()
  let statsEvent = oracleSession.nextUpdate()
  assert "subscribeBestBlock" in bestEvent and "subscribeStatistics" in statsEvent
  assert "\"error\"" notin statsEvent, "genuine posterior activity remains readable by statistics subscribers"
  assert base64.encode(array[32, byte](child.blockHash)) in bestEvent
  assert owner.connections[1].session.nextUpdate() == "", "best adoption cannot infer finality"
  assert owner.connections[2].session.nextUpdate() == ""
  assert sameStateSnapshot(owner.chain.finalizedBlock.value.stateSnapshot, parent)
  assert sameStateSnapshot(previous.chain.bestBlock.value.stateSnapshot, parent)
  owner.tick(0)
  assert receiveFrame(peer) == queued.substr(5)
  owner.tick(0)
  assert receiveFrame(peer) == frame(bestEvent)
  owner.tick(0)
  assert receiveFrame(peer) == frame(statsEvent)
  assert owner.connections[0].input == "\x81" and owner.connections[0].deadline <= deadline
  var packet = masked(Best)
  assert sendBytes(plainPeer, packet.toCString(), csize_t(packet.len), 0) == packet.len
  owner.tick(0)
  let response = receiveFrame(plainPeer)
  assert response == frame(respond(Best, owner.info))
  assert base64.encode(array[32, byte](child.blockHash)) in response
  let queueBefore = owner.connections[0].session
  failHash(1)
  let replay = owner.publishAccumulation(state, context.source, policy)
  assert replay.chainFailure.error == AccumulationChainError.StaleState
  assert hashCalls() == 0
  sameQueue(queueBefore, owner.connections[0].session)
  failHash(0)
  assert owner.publishFinalized(child.blockHash) == ViewFinalizeError.None
  assert "subscribeFinalizedBlock" in owner.connections[1].session.nextUpdate()
  assert owner.connections[0].session.nextUpdate() == ""
  owner.close()
  assert sameStateSnapshot(child.stateSnapshot, state.snapshot.value), "returned child outlives transport shutdown"

proc refusals(context: RpcFixture) =
  ## Disabled/missing-view and private late failures preserve exact state/history and pre-existing notifications.
  let policy = completionLimits().composition
  let parent = context.source.finalAccumulationParent.value
  var state = forkStateStore(parent).value
  var owner = default(Server)
  failHash(1)
  assert owner.publishAccumulation(state, context.source, policy).error ==
      RpcAccumulationError.Unavailable
  assert owner.start(0, "test", settings(), context.parent)
  assert owner.publishAccumulation(state, context.source, policy).error ==
      RpcAccumulationError.Unavailable
  assert hashCalls() == 0 and sameStateSnapshot(state.snapshot.value, parent)
  failHash(0)
  opened(owner, context)
  let peer = connected(owner, 0)
  defer: discard posix.close(peer)
  discard respond(Subscribe, owner.info, owner.connections[0].session)
  let pending = owner.connections[0].session
  let original = owner.chain
  owner.connections[0].output = "queued reply"
  owner.connections[0].offset = 3
  let invalid = owner.publishAccumulation(state, default(PreparedFinalAccumulation), policy)
  assert invalid.chainFailure.error == AccumulationChainError.InvalidSource
  var short = policy
  short.consensus.chapterBytes = ByteLimit(0)
  let limited = owner.publishAccumulation(state, context.source, short)
  assert limited.chainFailure.applicationFailure.compositionFailure.error ==
      AccumulationCompletionError.ConsensusFailure
  var oracleState = state
  var oracleView = original
  failHash(0)
  discard applyAccumulationChain(oracleState, oracleView, context.source, policy).value
  let total = hashCalls()
  failAfter(total - 1)
  let late = owner.publishAccumulation(state, context.source, policy)
  failHash(0)
  assert late.chainFailure.error == AccumulationChainError.CaptureFailure
  var changed = headerBytes(context.parent.value.header)
  changed[changed.len - 1] = changed[changed.len - 1] xor 1
  let alternate = captureBlockSnapshot(changed, parent, settings().value)
  owner.chain = genesisView(alternate)
  let notChild = owner.publishAccumulation(state, context.source, policy)
  assert notChild.chainFailure.viewError == ViewAdvanceError.NotChild
  assert sameStateSnapshot(state.snapshot.value, parent)
  assert array[32, byte](owner.chain.bestBlock.value.blockHash) == array[32, byte](
      alternate.value.blockHash)
  sameQueue(pending, owner.connections[0].session)
  owner.chain = default(ChainView)
  let missing = owner.publishAccumulation(state, context.source, policy)
  assert missing.chainFailure.error == AccumulationChainError.UninitializedView
  owner.chain = original
  assert owner.connections[0].output == "queued reply" and owner.connections[0].offset == 3
  assert sameStateSnapshot(owner.chain.bestBlock.value.stateSnapshot, parent)
  sameQueue(pending, owner.connections[0].session)
  let retry = owner.publishAccumulation(state, context.source, policy)
  assert retry.error == RpcAccumulationError.None
  assert "\"slot\":1" in owner.connections[0].session.nextUpdate(), "old pending events survive every refusal"
  assert base64.encode(array[32, byte](retry.value.blockHash)) in owner.connections[
      0].session.nextUpdate()
  owner.close()
  failHash(1)
  assert owner.publishAccumulation(state, context.source, policy).error ==
      RpcAccumulationError.Unavailable
  assert hashCalls() == 0 and sameStateSnapshot(state.snapshot.value, retry.value.stateSnapshot)
  failHash(0)

proc overflow(context: RpcFixture) =
  ## A full subscriber FIFO closes only its native slot after adoption; other connection states retain their policy.
  let policy = completionLimits().composition
  var owner = default(Server)
  opened(owner, context)
  var peers = default(array[5, cint])
  for index in 0..<peers.len: peers[index] = connected(owner,
      index) # Every native endpoint has exactly one owner.
  defer:
    for peer in peers: discard posix.close(peer) # Retire client endpoints independently of server close paths.
  for index in [0, 1, 3, 4]:
    discard respond(Subscribe, owner.info, owner.connections[
        index].session) # Different lifecycle states share the same active selector.
  discard owner.connections[1].session.nextUpdate()
  discard owner.connections[3].session.nextUpdate()
  discard owner.connections[4].session.nextUpdate()
  owner.connections[3].upgraded = false
  owner.connections[4].closing = true
  for index in 1..<MaxSubscriptionUpdates:
    assert owner.connections[0].session.queueChainUpdates(
        context.parent) # Fill the bounded queue without inventing a new block.
  var state = forkStateStore(context.source.finalAccumulationParent.value).value
  let published = owner.publishAccumulation(state, context.source, policy)
  assert published.error == RpcAccumulationError.None and owner.opened
  assert sameStateSnapshot(owner.chain.bestBlock.value.stateSnapshot, state.snapshot.value)
  assert not owner.connections[0].opened and owner.connections[0].session.nextUpdate() == ""
  assert owner.connections[1].opened and owner.connections[2].opened
  assert base64.encode(array[32, byte](published.value.blockHash)) in owner.connections[
      1].session.nextUpdate()
  assert owner.connections[2].session.nextUpdate() == ""
  assert owner.connections[3].session.nextUpdate() == "" and owner.connections[
      4].session.nextUpdate() == ""
  owner.close()

proc cycle(context: RpcFixture) =
  ## Success, stale replay and closed-listener refusal release transports, sessions and private composition graphs.
  let policy = completionLimits().composition
  var owner = default(Server)
  opened(owner, context)
  let peer = connected(owner, 0)
  defer: discard posix.close(peer)
  discard respond(Subscribe, owner.info, owner.connections[0].session)
  var state = forkStateStore(context.source.finalAccumulationParent.value).value
  let success = owner.publishAccumulation(state, context.source, policy)
  assert success.error == RpcAccumulationError.None
  assert owner.publishAccumulation(state, context.source, policy).chainFailure.error ==
      AccumulationChainError.StaleState
  owner.close()
  assert owner.publishAccumulation(state, context.source, policy).error ==
      RpcAccumulationError.Unavailable
  var buffer = default(array[1, byte])
  assert receive(peer, addr buffer[0], 1, 0) == 0, "server close retires its native socket endpoint"

proc main() {.raises.} =
  ## Real signed successors reach existing RPC wire/queue logic without forging execution or publication certificates.
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
  refusals(context)
  overflow(context)
  cycle(context)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context) # Every accepted head and closed/refused connection graph leaves scope.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("rpc_accumulation", 1000, before, after)
  echo "RPC finalized accumulation publication passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O errors must fail the native test.
except:
  quit(2)
