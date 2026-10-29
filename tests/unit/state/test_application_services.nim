# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_services"}

## Service-owned configured state, exact RPC seeding, adoption and shutdown/restart without a running peer.

import std/[assertions, syncio, envvars, strutils, monotimes, times, base64]
import std/posix/posix
import ../../../src/app/[services, options]
import ../../../src/app/disk/chain as disk_chain
import ../../../src/app/handoff
import ../../../src/storage/node/repository as node_repository
import ../../../src/app/chain
import ../../../src/chain/[genesis, provider, parameters]
import ../../../src/rpc/[server, protocol]
import ../../../src/lib/json/writer as json_writer
import ../../../src/codec/[header, bounded, report_owned]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/state/store
import ../../../src/state/accumulation/[state as accumulation_state, chain as accumulation_chain,
    completion as accumulation_completion, finalization as accumulation_finalization,
    times as accumulation_times, statistics as accumulation_statistics,
    validators as accumulation_validators, activity as accumulation_activity,
    round as accumulation_round, queue as accumulation_queue, runner as accumulation_runner,
    driver as accumulation_driver]
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../support/[accumulation_activity_context, accumulation_completion_context,
  accumulation_execution_context, accumulation_runner_context, arc_evidence]
import ../../support/report_admission_context as report_fixture
import ../../support/mcp_socket
import ../../support/rpc_socket

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
const DiskPath = "application-services-state.db" # Every mode chooses one explicit isolated fixture journal.

proc configured(port = 0'u16, withState = false, disk = false, mcpPort = 0'u16): Options =
  ## Telemetry-only options exercise disabled RPC without making a collector connection.
  result = default(Options)
  var arguments = @["server", "--chain", SeedPath]
  if withState:
    for value in ["--with-state", "--state-writes", "1000", "--state-write-bytes", "1000000"]:
      arguments.add(value) # Canonical ownership is explicit even with all listeners disabled.
  if port == 0 and not withState:
    for value in ["--with-telemetry", "--telemetry-endpoint", "127.0.0.1:1"]:
      arguments.add(value) # The pinned sequence API appends individual owned values.
  elif port != 0:
    for value in ["--with-rpc", "--rpc-port", $port]:
      arguments.add(value) # Preserve the validated explicit listener port.
  if mcpPort != 0:
    for value in ["--with-mcp", "--mcp-port", $mcpPort]: arguments.add(value)
  if disk:
    for value in ["--state-storage", "disk", "--state-db", DiskPath]: arguments.add(value)
  assert parseCanonicalOptions(arguments, result)

proc listener(owner: var Services, viaCli = false, withDisk = false,
    mcpPort = 0'u16): uint16 {.raises.} =
  ## Retry only the bounded release/bind race; each successful listener uses explicit state policy.
  for attempt in 0..<8:
    let reserved = reservation()
    discard posix.close(reserved.fd)
    let options = configured(reserved.port, viaCli, withDisk, mcpPort)
    let started = if viaCli: owner.start(options, "test") else: owner.start(options, "test", policy())
    if started: return reserved.port # Return only the port owned by the successful startup path.
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
  let mcpReservation = reservation()
  discard posix.close(mcpReservation.fd)
  let port = listener(owner, true, mcpPort = mcpReservation.port)
  assert hashCalls() == cost, "RPC reuses the seed without another map/header hash"
  let before = owner.stateSnapshot.value
  let initialMcp = mcpTool(owner, mcpReservation.port, "get_chain_status")
  assert "\"slot\":\"1\"" in initialMcp
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
  let advancedMcp = mcpTool(owner, mcpReservation.port, "get_chain_status")
  assert "\"slot\":\"2\"" in advancedMcp
  assert base64.encode(array[32, byte](applied.value.blockHash)) in advancedMcp
  sendText(peer, """{"jsonrpc":"2.0","method":"bestBlock","id":1}""")
  assert "\"slot\":2" in readPacket(owner.rpc, peer, pending)
  # Publication advances best state while the fixed configured genesis identity remains unchanged.
  sendText(peer, """{"jsonrpc":"2.0","method":"ragnarok_clientInfo","id":3}""")
  let diagnostic = readPacket(owner.rpc, peer, pending)
  assert "\"chainState\":{\"best\":{\"header_hash\":" & quote(base64.encode(array[32, byte](
      applied.value.blockHash))) in diagnostic
  assert "\"stateKeys\":" & $owner.chainView.bestBlock.value.keyCount in diagnostic
  assert "\"knownServices\":" & $owner.chainView.bestBlock.value.serviceCount in diagnostic
  assert "\"retainedBlocks\":2" in diagnostic
  let seed = configuredGenesis(context.text, configuredParameters(context.text).value)
  assert "\"genesisHash\":" & quote(base64.encode(array[32, byte](seed.value.blockHash))) in diagnostic
  assert "\"genesisStateRoot\":" & quote(base64.encode(array[32, byte](before.commitment.root))) in diagnostic
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
  assert parseCanonicalOptions(@["server", "--with-ui", "--chain", SeedPath,
    "--rpc-port", $reserved.port, "--ui-port", $uiPort.port], partial)
  assert not owner.start(partial, "test", policy())
  assertPortReleased(uiPort.port)
  discard posix.close(reserved.fd)
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  var ui = default(Options)
  assert parseCanonicalOptions(@["server", "--with-ui", "--chain", SeedPath,
    "--ui-dev-dir", "missing-application-services-ui"], ui)
  assert not owner.start(ui, "test", policy())
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized
  assert owner.start(options, "test", policy())
  owner.close()
  var missing = default(Options)
  let missingPort = reservation()
  discard posix.close(missingPort.fd)
  assert parseCanonicalOptions(@["server", "--with-rpc", "--rpc-port", $missingPort.port], missing)
  assert not owner.start(missing, "test", policy())
  failHash(1)
  assert owner.start(missing, "test"), "legacy unavailable genesis still starts without state/hash work"
  assert hashCalls() == 0 and owner.stateSnapshot.error == StateStoreError.Uninitialized
  failHash(0)
  owner.close()

proc cli(context: SeedFixture) {.raises.} =
  ## The executable's shared three-argument startup selects canonical state with no RPC or telemetry activation.
  writeFile(SeedPath, context.text)
  var owner = default(Services)
  assert owner.start(configured(withState = true), "test")
  let old = owner.stateSnapshot.value
  let final = execution(owner, context)
  assert owner.applyAccumulation(final, completionLimits().composition).error ==
      ApplicationChainError.None
  assert not sameStateSnapshot(old, owner.stateSnapshot.value)
  owner.close()
  var readonly = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", SeedPath,
    "--state-writes", "0", "--state-write-bytes", "0"], readonly)
  assert owner.start(readonly, "test")
  var branch = forkStateStore(owner.stateSnapshot.value).value
  assert branch.apply([StateWrite(key: chapterKey(StateChapter(249)), kind: StateWriteKind.Put,
    value: @[1'u8])]).error == StateStoreError.LimitExceeded
  owner.close()
  for selected in ["--state-writes", "--state-write-bytes"]:
    var arguments = @["server", "--with-state", "--chain", SeedPath]
    for field in ["--state-writes", "--state-write-bytes"]:
      arguments.add(field)
      arguments.add(if field == selected: "1" else: "1000") # Check exact propagation of each independent budget.
    var limited = default(Options)
    assert parseCanonicalOptions(arguments, limited)
    assert owner.start(limited, "test")
    var branch = forkStateStore(owner.stateSnapshot.value).value
    let writes = [StateWrite(key: chapterKey(StateChapter(248)), kind: StateWriteKind.Put, value: @[1'u8]),
      StateWrite(key: chapterKey(StateChapter(249)), kind: StateWriteKind.Put, value: @[2'u8])]
    assert branch.apply(writes).error == StateStoreError.LimitExceeded
    assert branch.apply([writes[0]]).error == StateStoreError.None
    owner.close()
  writeFile(SeedPath, "{}")
  assert not owner.start(configured(withState = true), "test")
  assert owner.stateSnapshot.error == StateStoreError.Uninitialized

proc cycle(options: Options, explicitClose: bool) {.raises.} =
  ## Both explicit idempotent close and implicit destruction retire the complete seed/text graph.
  var owner = default(Services)
  assert owner.start(options, "test", policy())
  if explicitClose:
    owner.close()
    owner.close()
    assert owner.stateSnapshot.error == StateStoreError.Uninitialized

proc diskLifecycle(context: SeedFixture, withRpc: bool) {.raises.} =
  ## Real execution is rebound to the fresh disk owner; native durability spans multiple nonblocking ticks.
  writeFile(SeedPath, context.text)
  let options = configured(withState = true, disk = true)
  var owner = default(Services)
  defer: owner.close()
  if withRpc:
    discard owner.listener(viaCli = true, withDisk = true)
  else:
    assert owner.start(options, "disk runtime")
  var diskPath = DiskPath
  defer: discard posix.unlink(diskPath.toCString())
  var competing = default(Services)
  assert not competing.start(options, "locked disk")
  competing.close()
  let parent = owner.stateSnapshot.value
  let parentHash = owner.chainView.bestBlock.value.blockHash
  let source = execution(owner, context)
  assert owner.applyAccumulation(source, completionLimits().composition).error ==
      ApplicationChainError.DurabilityRequired
  assert owner.enqueueAccumulation(source, completionLimits().composition) ==
      AccumulationEnqueueError.None
  owner.tick(0)
  assert owner.accumulationStage == AccumulationHandoffStage.Publishing
  assert owner.diskPublicationActive and owner.rpc.chainPaused
  assert not owner.cancelAccumulation()
  let started = getMonoTime()
  while owner.accumulationStage != AccumulationHandoffStage.Finished:
    assert (getMonoTime()-started).inSeconds < 20, "bounded durable service completion"
    owner.tick(0)
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Only scalar/tick work occurs until the native graph lease ends.
  assert not owner.diskPublicationActive and not owner.rpc.chainPaused
  let adopted = owner.takeAccumulation()
  assert adopted.error == ApplicationChainError.None
  assert sameStateSnapshot(adopted.value.stateSnapshot, owner.stateSnapshot.value)
  assert not sameStateSnapshot(parent, owner.stateSnapshot.value)
  assert owner.diskPublicationOutcome.error == DiskChainError.None
  assert uint64(owner.diskPublicationOutcome.value) == 3
  let child = owner.chainView.bestBlock.value.blockHash
  owner.close()
  assert owner.diskPublicationOutcome.error == DiskChainError.None
  var restartedPort = 0'u16
  if withRpc:
    restartedPort = owner.listener(viaCli = true, withDisk = true)
  else:
    assert owner.start(options, "local disk restart")
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](child)
  assert owner.chainView.retainedCount == 2
  assert array[32, byte](owner.chainView.parentOf(child).value.blockHash) ==
    array[32, byte](parentHash)
  if withRpc:
    let peer = client(restartedPort)
    defer: discard posix.close(peer)
    var pending = ""
    owner.rpc.upgrade(peer, pending)
    let head = base64.encode(array[32, byte](child))
    sendText(peer, "{\"jsonrpc\":\"2.0\",\"method\":\"parent\",\"params\":[\"" & head & "\"],\"id\":4}")
    assert base64.encode(array[32, byte](parentHash)) in readPacket(owner.rpc, peer, pending)
    let prior = base64.encode(array[32, byte](parentHash))
    sendText(peer, "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" & prior & "\"],\"id\":5}")
    assert base64.encode(array[32, byte](parent.commitment.root)) in readPacket(owner.rpc, peer, pending)
    # Durable restart restores a later head while retaining the original configured genesis identity.
    sendText(peer, """{"jsonrpc":"2.0","method":"ragnarok_clientInfo","id":6}""")
    let diagnostic = readPacket(owner.rpc, peer, pending)
    assert "\"genesisHash\":" & quote(prior) in diagnostic
    assert "\"genesisStateRoot\":" & quote(base64.encode(array[32, byte](
        parent.commitment.root))) in diagnostic
  owner.close()

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
  cli(context)
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
  diskLifecycle(context, false)
  diskLifecycle(context, true)
  echo "Application service state lifecycles passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # File I/O errors must fail the native suite.
except:
  quit(2)
