# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_handoff_arc_release"}

## Single-candidate dispatcher adoption, retained outcomes and exact authority through public application/service APIs.

import std/[assertions, syncio, envvars, strutils, nativesocket]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/[chain, handoff]
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


const SeedPath = "application-handoff-chain.json"

proc configured(port = 0'u16, withState = false): Options =
  ## Telemetry-only options exercise disabled RPC without making a collector connection.
  result = default(Options)
  var arguments = @["server", "--chain", SeedPath]
  if withState:
    for value in ["--with-state", "--state-writes", "1000", "--state-write-bytes", "1000000"]:
      arguments.add(value) # Canonical ownership is explicit even with all listeners disabled.
  if port == 0 and not withState:
    for value in ["--with-telemetry", "--telemetry", "127.0.0.1:1"]:
      arguments.add(value) # The pinned sequence API appends individual owned values.
  elif port != 0:
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

proc listener(owner: var Services, viaCli = false): uint16 {.raises.} =
  ## Retry only the bounded release/bind race; each successful listener uses explicit state policy.
  for attempt in 0..<8:
    let reserved = reservation()
    discard posix.close(reserved.fd)
    let options = configured(reserved.port, viaCli)
    let started = if viaCli: owner.start(options, "test") else: owner.start(options, "test", policy())
    if started: return reserved.port # Return only the port owned by the successful startup path.
  assert false, "ephemeral Services startup failed"
  0'u16


proc expectedCost(owner: Services, final: PreparedFinalAccumulation): cint =
  ## Compare actual queued publication with the existing coordinator on an independent exact-parent branch.
  var branch = initApplicationChain(owner.chainView).value
  failHash(0)
  assert branch.applyAccumulation(final, completionLimits().composition).error ==
      ApplicationChainError.None
  result = hashCalls()
  failHash(0)

proc local(context: SeedFixture) {.raises.} =
  ## Admission/cancellation do no hash work; one turn adopts once and retains explicit producer backpressure.
  let limits = completionLimits().composition
  writeFile(SeedPath, context.text)
  var owner = default(Services)
  failHash(1)
  assert owner.accumulationStage == AccumulationHandoffStage.Idle
  assert not owner.cancelAccumulation()
  assert owner.enqueueAccumulation(context.source, limits) ==
      AccumulationEnqueueError.Unavailable
  owner.tick(0)
  assert hashCalls() == 0
  failHash(0)
  assert owner.start(configured(withState = true), "test")
  let final = execution(owner, context)
  let old = owner.stateSnapshot.value
  let cost = expectedCost(owner, final)
  failHash(1)
  let invalid = owner.enqueueAccumulation(default(PreparedFinalAccumulation), limits)
  assert invalid == AccumulationEnqueueError.InvalidSource
  assert owner.enqueueAccumulation(context.source, limits) ==
      AccumulationEnqueueError.StaleState
  assert owner.enqueueAccumulation(final, limits) ==
      AccumulationEnqueueError.None
  assert owner.accumulationStage == AccumulationHandoffStage.Pending
  assert sameStateSnapshot(old, owner.stateSnapshot.value)
  assert owner.enqueueAccumulation(final, limits) ==
      AccumulationEnqueueError.Busy
  assert owner.cancelAccumulation() and owner.accumulationStage == AccumulationHandoffStage.Idle
  assert not owner.cancelAccumulation()
  assert hashCalls() == 0
  failHash(0)
  assert owner.enqueueAccumulation(final, limits) ==
      AccumulationEnqueueError.None
  owner.tick(0)
  assert owner.accumulationStage == AccumulationHandoffStage.Finished
  assert hashCalls() == cost
  assert not sameStateSnapshot(old, owner.stateSnapshot.value)
  assert old.lookup(chapterKey(StateChapter(11))).value.bytes == @[1'u8, 0, 0, 0]
  failHash(1)
  assert owner.enqueueAccumulation(final, limits) ==
      AccumulationEnqueueError.Busy
  assert not owner.cancelAccumulation()
  for turn in 0..<8: owner.tick(0) # Finished results do not retry or hash on subsequent dispatcher turns.
  assert hashCalls() == 0
  let applied = owner.takeAccumulation()
  assert applied.error == ApplicationChainError.None
  assert sameStateSnapshot(applied.value.stateSnapshot, owner.stateSnapshot.value)
  assert owner.accumulationStage == AccumulationHandoffStage.Idle
  owner.tick(0)
  assert hashCalls() == 0
  failHash(0)
  owner.close()

proc failures(context: SeedFixture) {.raises.} =
  ## A failed attempt is retained exactly once; explicit take/re-enqueue can retry while stale interleaving cannot.
  let limits = completionLimits().composition
  writeFile(SeedPath, context.text)
  var owner = default(Services)
  assert owner.start(configured(withState = true), "test")
  let final = execution(owner, context)
  let old = owner.stateSnapshot.value
  let cost = expectedCost(owner, final)
  assert owner.enqueueAccumulation(final, limits) ==
      AccumulationEnqueueError.None
  failAfter(cost - 1)
  owner.tick(0)
  failHash(0)
  assert sameStateSnapshot(old, owner.stateSnapshot.value)
  assert owner.accumulationStage == AccumulationHandoffStage.Finished
  let refused = owner.takeAccumulation()
  assert refused.chainFailure.error == AccumulationChainError.CaptureFailure
  assert owner.enqueueAccumulation(final, limits) ==
      AccumulationEnqueueError.None
  owner.tick(0)
  assert owner.takeAccumulation().error == ApplicationChainError.None
  owner.close()
  assert owner.start(configured(withState = true), "test")
  let pending = execution(owner, context)
  assert owner.enqueueAccumulation(pending, limits) ==
      AccumulationEnqueueError.None
  assert owner.applyAccumulation(pending, limits).error ==
      ApplicationChainError.None
  let advanced = owner.stateSnapshot.value
  failHash(1)
  owner.tick(0)
  assert hashCalls() == 0
  let stale = owner.takeAccumulation()
  assert stale.chainFailure.error == AccumulationChainError.StaleState
  assert sameStateSnapshot(advanced, owner.stateSnapshot.value)
  failHash(0)
  owner.close()
  assert owner.start(configured(withState = true), "test")
  let captured = execution(owner, context)
  var budget = default(AccumulationCompositionLimits)
  var branch = initApplicationChain(owner.chainView).value
  let expected = branch.applyAccumulation(captured, budget)
  assert expected.error == ApplicationChainError.ChainFailure
  assert owner.enqueueAccumulation(captured, budget) == AccumulationEnqueueError.None
  budget = limits # Mutating caller limits cannot replace the retained queued policy.
  owner.tick(0)
  let limited = owner.takeAccumulation()
  assert limited.error == expected.error and limited.chainFailure.error ==
      expected.chainFailure.error
  owner.close()

proc rpc(context: SeedFixture) {.raises.} =
  ## Pending work leaves RPC at its old head; service tick installs all handles before a real subscription update.
  let limits = completionLimits().composition
  writeFile(SeedPath, context.text)
  var owner = default(Services)
  let port = listener(owner, true)
  let final = execution(owner, context)
  let cost = expectedCost(owner, final)
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  sendText(peer, "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", false)
  assert "101 Switching Protocols" in readPacket(owner.rpc, peer, pending, true)
  sendText(peer, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}""")
  assert "\"result\":1" in readPacket(owner.rpc, peer, pending)
  assert "\"slot\":1" in readPacket(owner.rpc, peer, pending)
  failHash(1)
  assert owner.enqueueAccumulation(final, limits) ==
      AccumulationEnqueueError.None
  sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
  assert "\"slot\":1" in readPacket(owner.rpc, peer, pending)
  assert hashCalls() == 0
  failHash(0)
  owner.tick(0)
  assert hashCalls() == cost
  assert owner.accumulationStage == AccumulationHandoffStage.Finished
  let current = owner.stateSnapshot.value
  assert sameStateSnapshot(current, owner.chainView.bestBlock.value.stateSnapshot)
  assert "\"slot\":2" in readPacket(owner.rpc, peer, pending)
  sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
  assert "\"slot\":2" in readPacket(owner.rpc, peer, pending)
  let applied = owner.takeAccumulation()
  assert sameStateSnapshot(applied.value.stateSnapshot, current)
  owner.close()

proc enqueueScoped(owner: var Services, context: SeedFixture): AccumulationEnqueueError =
  ## All newly finalized source locals retire before the caller's next dispatcher turn.
  let source = execution(owner, context)
  owner.enqueueAccumulation(source, completionLimits().composition)

proc closure(context: SeedFixture) {.raises.} =
  ## Enabled listener closure and stale finality retain refusal; shutdown releases pending/finished slots before restart.
  let limits = completionLimits().composition
  writeFile(SeedPath, context.text)
  var owner = default(Services)
  discard listener(owner, true)
  let final = execution(owner, context)
  let old = owner.stateSnapshot.value
  assert owner.enqueueAccumulation(final, limits) ==
      AccumulationEnqueueError.None
  owner.rpc.close()
  failHash(1)
  owner.tick(0)
  owner.tick(0)
  assert hashCalls() == 0
  let closed = owner.takeAccumulation()
  assert closed.rpcFailure.error == RpcAccumulationError.Unavailable
  assert sameStateSnapshot(old, owner.stateSnapshot.value)
  failHash(0)
  owner.close()
  discard listener(owner, true)
  let stale = execution(owner, context)
  let parent = owner.chainView.bestBlock.value
  assert owner.enqueueAccumulation(stale, limits) ==
      AccumulationEnqueueError.None
  assert owner.rpc.publishFinalized(parent.blockHash) == ViewFinalizeError.None
  failHash(1)
  owner.tick(0)
  assert hashCalls() == 0
  let mismatch = owner.takeAccumulation()
  assert mismatch.rpcFailure.error == RpcAccumulationError.StaleView
  failHash(0)
  owner.close()
  assert owner.start(configured(withState = true), "test")
  let cancelled = execution(owner, context)
  assert owner.enqueueAccumulation(cancelled, limits) ==
      AccumulationEnqueueError.None
  owner.close()
  assert owner.accumulationStage == AccumulationHandoffStage.Idle
  assert owner.start(configured(withState = true), "test")
  assert owner.enqueueAccumulation(cancelled, limits) ==
      AccumulationEnqueueError.StaleState
  assert enqueueScoped(owner, context) == AccumulationEnqueueError.None
  owner.tick(0)
  owner.close() # Explicit shutdown can also discard a completed outcome whose producer has retired.
  assert owner.accumulationStage == AccumulationHandoffStage.Idle
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  owner.close()

proc cycle(seed: ApplicationChain, source: PreparedFinalAccumulation, mode: int) =
  ## Each scope retires pending cancellation/destruction and completed taken/untaken graphs without retaining history.
  var branch = seed
  var handoff = default(AccumulationHandoff)
  let limits = if mode == 4: default(AccumulationCompositionLimits) else: completionLimits().composition
  assert handoff.enqueue(branch, source, limits) == AccumulationEnqueueError.None
  case mode
  of 0:
    assert handoff.cancel() # Explicitly release an unattempted source.
  of 1:
    discard # Implicit destruction releases the still-pending source.
  of 2:
    handoff.process(branch)
    assert handoff.take().error == ApplicationChainError.None # Taken immutable outcomes leave the local scope.
  of 3:
    handoff.process(branch) # Implicit destruction also releases a Finished success and its retained child.
    assert handoff.stage == AccumulationHandoffStage.Finished
  else:
    handoff.process(branch)
    assert handoff.take().error == ApplicationChainError.ChainFailure # Refused composition retains only its actual nested reasons.

proc main() {.raises.} =
  ## Retain one authentic source authority and independently test configured service and direct handoff ownership.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let context = fixture(decodeOwnedReport(wire, 2).value)
  defer: discard posix.unlink("application-handoff-chain.json")
  local(context)
  failures(context)
  rpc(context)
  closure(context)
  let bound = context.source.finalAccumulationAdmission.value.reportBlockStage.value.value.admitted
  var header = newSeq[byte](bound.admittedParent.headerInfo.value.consumed)
  assert encodeOwnedHeader(bound.admittedParent, header).error == HeaderError.None
  let parent = captureBlockSnapshot(header, context.source.finalAccumulationParent.value,
      runnerParameters())
  let seed = initApplicationChain(genesisView(parent)).value
  for mode in 0..<5: cycle(seed, context.source, mode) # Warm every ownership path before the measured repeated workload.
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(seed, context.source,
      iteration mod 5) # No candidate/result survives its cycle scope.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_handoff", 1000, before, after)
  echo "Bounded application successor handoffs passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # File/fixture I/O failures must fail the native suite after all owners retire.
except:
  quit(2)
