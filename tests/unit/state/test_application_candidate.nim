# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_candidate_arc_release"}

## Genuine owned-block preparation, selected-head execution and deferred application publication.

import std/[assertions, syncio, envvars, strutils, nativesocket]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/[chain, handoff, candidate]
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/rpc/[server, protocol]
import ../../../src/codec/[assurances, block_codec, header, bounded, report_owned, state_layout, state_trie]
import ../../../src/state/[store, accumulation_state, accumulation_chain, accumulation_completion,
  accumulation_finalization, accumulation_times, accumulation_statistics, accumulation_validators,
  accumulation_activity, accumulation_round, accumulation_queue, accumulation_runner,
  accumulation_driver, report_admission, block_transition, block_admission]
import ../../support/[accumulation_activity_context, accumulation_completion_context,
  accumulation_execution_context, accumulation_runner_context, arc_evidence]
import ../../support/report_admission_context as report_fixture
import ../../support/application_candidate_context

# Backend faults begin after all authored source/context bytes are independently retained.
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

const SeedPath = "application-candidate-chain.json"

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



proc witness(context: SeedFixture) =
  ## Manual lower-level stage execution and the producer agree without publishing either private prefix.
  let chain = initialized(context)
  let before = chain.stateSnapshot.value
  let limits = preparationLimits()
  let parent = chain.chainView
  var manualOwner = initApplicationChain(parent).value
  var working = forkStateStore(before).value
  let bound = candidateBlock(context)
  failHash(0)
  let staged = report_fixture.stage(working, bound, parent.bestBlock.value.header)
  let reports = planBlockReports(staged, [], limits.reporting.reports).value
  let queue = planBlockAccumulationQueue(reports, limits.queue).value
  let round = planBlockInitialAccumulation(queue, limits.round).value
  let parameters = parent.bestBlock.value.chainParameters
  let initial = runBlockAccumulation(round, parameters, limits.execution).value
  let stopped = driveAccumulation(initial, parameters, limits.driver).value
  let expected = prepareFinalAccumulation(stopped, limits.finalization).value
  let cost = hashCalls()
  failHash(0)
  let prepared = prepareCandidate(chain, bound, [], limits)
  assert prepared.error == ApplicationCandidateError.None
  assert hashCalls() == cost, "the adapter adds no trie/header hash work beyond existing stages"
  let final = prepared.value
  assert sameStateSnapshot(final.finalAccumulationParent.value, before)
  let expectedRoot = expected.finalAccumulationState.value.commitment.root
  assert array[32, byte](final.finalAccumulationState.value.commitment.root) == array[32, byte](expectedRoot)
  let facts = final.finalAccumulationInfo.value
  assert facts.outputs.executions == 2
  assert uint64(facts.remainingGas) == 299956, "two real halt guests consume 22 gas each from the 300000 budget"
  assert sameStateSnapshot(chain.stateSnapshot.value, before)
  assert chain.chainView.retainedCount == 1
  assert manualOwner.applyAccumulation(expected, completionLimits().composition).error ==
      ApplicationChainError.None
  var handoff = default(AccumulationHandoff)
  failHash(0)
  let queued = handoff.enqueueCandidate(chain, bound, [], limits, completionLimits().composition)
  assert queued.error == ApplicationCandidateError.None and hashCalls() == cost
  assert handoff.stage == AccumulationHandoffStage.Pending
  assert sameStateSnapshot(chain.stateSnapshot.value, before)
  failHash(1)
  let busy = handoff.enqueueCandidate(chain, default(OwnedBlock), [], default(
      ApplicationCandidateLimits), default(AccumulationCompositionLimits))
  assert busy.error == ApplicationCandidateError.Busy and hashCalls() == 0
  failHash(0)
  var adopted = chain
  handoff.process(adopted)
  let published = handoff.take()
  assert published.error == ApplicationChainError.None
  let expectedHead = manualOwner.chainView.bestBlock.value
  assert array[32, byte](published.value.stateRoot) == array[32, byte](expectedHead.stateRoot)
  assert array[32, byte](published.value.blockHash) == array[32, byte](expectedHead.blockHash)

proc failures(context: SeedFixture) =
  ## Each selected stage refuses under its own changed policy; no failed prefix changes canonical state or fills the handoff.
  let chain = initialized(context)
  let before = chain.stateSnapshot.value
  let child = candidateBlock(context)
  let limits = preparationLimits()
  failHash(1)
  let absent = prepareCandidate(default(ApplicationChain), child, [], limits)
  assert absent.error == ApplicationCandidateError.MissingHead and hashCalls() == 0
  for field in 0..<3:
    var changed = limits
    case field
    of 0: changed.reporting.admission.frame.cores = CoreCount(3) # Different core domain cannot authorize hashing.
    of 1: changed.reporting.admission.frame.validators = ValidatorCount(
        7) # Population belongs to the selected head.
    else: changed.reporting.admission.frame.epochSlots = EpochSlots(
        13) # Epoch width belongs to the selected head.
    let refused = prepareCandidate(chain, child, [], changed)
    assert refused.error == ApplicationCandidateError.ProfileMismatch and hashCalls() == 0
  failHash(0)
  let malformed = prepareCandidate(chain, default(OwnedBlock), [], limits)
  assert malformed.error == ApplicationCandidateError.BlockFailure
  assert malformed.blockFailure.error != BlockTransitionError.None
  for stage in 0..<6:
    var changed = limits
    case stage
    of 0: changed.reporting.reports.credentials.assignments.epochSlots = EpochSlots(
        13) # Report domains refuse after genuine prefix validation.
    of 1: changed.queue.queues.cores = CoreCount(3) # Admitted queue domains cannot be replaced.
    of 2: changed.round.privileges.cores = CoreCount(3) # Privilege projection retains the admitted profile.
    of 3: changed.execution.completion.services = ElementLimit(
        0) # Real guest count cannot bypass the initial execution limit.
    of 4: changed.driver.preparation.selection.executions = ElementLimit(
        0) # Continuation selection must inspect both completed guests.
    else: changed.finalization.rounds = ElementLimit(0) # Final output history remains independently bounded.
    var handoff = default(AccumulationHandoff)
    let refused = handoff.enqueueCandidate(chain, child, [], changed, completionLimits().composition)
    case stage
    of 0:
      assert refused.error == ApplicationCandidateError.ReportFailure
      assert refused.reportFailure.error == ReportAdmissionError.InvalidConfig
    of 1:
      assert refused.error == ApplicationCandidateError.QueueFailure
      assert refused.queueError == AccumulationQueueError.InvalidConfig
    of 2:
      assert refused.error == ApplicationCandidateError.RoundFailure
      assert refused.roundError != AccumulationRoundError.None
    of 3:
      assert refused.error == ApplicationCandidateError.RunnerFailure
      assert refused.runnerFailure.error == AccumulationRunnerError.LimitExceeded
    of 4:
      assert refused.error == ApplicationCandidateError.DriverFailure
      assert refused.driverFailure.error == AccumulationDriverError.SelectionFailure
    else:
      assert refused.error == ApplicationCandidateError.FinalizationFailure
      assert refused.finalizationFailure.error == AccumulationFinalizationError.OutputFailure
    assert handoff.stage == AccumulationHandoffStage.Idle
    assert sameStateSnapshot(before, chain.stateSnapshot.value)
  failHash(1)
  let primitive = prepareCandidate(chain, child, [], limits)
  failHash(0)
  assert primitive.error == ApplicationCandidateError.BlockFailure
  assert prepareCandidate(chain, child, [], limits).error == ApplicationCandidateError.None
  let header = chain.chainView.bestBlock.value
  var wire = newSeq[byte](header.header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header.header, wire).error == HeaderError.None
  let profiled = captureBlockSnapshot(wire, before, runnerParameters(queue = 79))
  var other = initApplicationChain(genesisView(profiled)).value
  let selected = prepareCandidate(other, child, [], limits)
  assert selected.runnerFailure.error == AccumulationRunnerError.InvalidParameters

proc rpc(context: SeedFixture) {.raises.} =
  ## Service producer queues actual validation/execution and only a later dispatcher turn publishes to real subscribers.
  writeFile(SeedPath, context.text)
  var owner = default(Services)
  let port = listener(owner, true)
  let before = owner.stateSnapshot.value
  let peer = client(port)
  defer: discard posix.close(peer)
  var pending = ""
  sendText(peer, "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n", false)
  assert "101 Switching Protocols" in readPacket(owner.rpc, peer, pending, true)
  sendText(peer, """{"jsonrpc":"2.0","method":"subscribeBestBlock","params":[],"id":2}""")
  assert "\"result\":1" in readPacket(owner.rpc, peer, pending)
  assert "\"slot\":1" in readPacket(owner.rpc, peer, pending)
  let queued = owner.enqueueCandidate(candidateBlock(context), [], preparationLimits(),
      completionLimits().composition)
  assert queued.error == ApplicationCandidateError.None
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert owner.accumulationStage == AccumulationHandoffStage.Pending
  failHash(1)
  let busy = owner.enqueueCandidate(default(OwnedBlock), [], default(ApplicationCandidateLimits),
      default(AccumulationCompositionLimits))
  assert busy.error == ApplicationCandidateError.Busy and hashCalls() == 0
  failHash(0)
  owner.tick(0)
  assert "\"slot\":2" in readPacket(owner.rpc, peer, pending)
  let applied = owner.takeAccumulation()
  assert applied.error == ApplicationChainError.None
  assert sameStateSnapshot(applied.value.stateSnapshot, owner.stateSnapshot.value)
  assert before.lookup(chapterKey(StateChapter(11))).value.bytes == @[1'u8, 0, 0, 0]
  failHash(1)
  let repeated = owner.enqueueCandidate(candidateBlock(context), [], preparationLimits(),
      completionLimits().composition)
  assert repeated.error == ApplicationCandidateError.BlockFailure
  failHash(0)
  owner.close()

proc cycle(chain: ApplicationChain, child: OwnedBlock, refuse: bool) =
  ## Returned genuine stopped graphs and mid-pipeline refusals release all private prefix owners each scope.
  var limits = preparationLimits()
  if refuse: limits.execution.completion.services = ElementLimit(
      0) # Failed initial execution releases earlier valid stages.
  let prepared = prepareCandidate(chain, child, [], limits)
  assert prepared.error == (if refuse: ApplicationCandidateError.RunnerFailure else: ApplicationCandidateError.None)

proc main() {.raises.} =
  ## Decode the frozen independent report before authored signed blocks, real execution and ownership measurements.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let context = fixture(decodeOwnedReport(wire, 2).value)
  defer: discard posix.unlink("application-candidate-chain.json")
  witness(context)
  failures(context)
  rpc(context)
  let chain = initialized(context)
  let child = candidateBlock(context)
  cycle(chain, child, false)
  cycle(chain, child, true)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(chain, child, iteration mod 2 ==
      0) # Every private result graph retires before the next measurement.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_candidate", 1000, before, after)
  echo "Application candidate preparation passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture/file I/O refusal must fail the native suite.
except:
  quit(2)
