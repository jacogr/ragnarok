# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real current-command ancestor acquisition preserves exact lineage, bounded deadlines and every durable state entry.
import std/[assertions, syncio, envvars, monotimes, times, os, strutils]
import std/posix/posix
import ../../../src/app/current/download/[command as current_download_command,
    policy as current_download_policy]
import ../../../src/app/[options, services]
import "../../../src/quic/current/block/download/loop" as current_block_download_loop
import "../../../src/quic/current/block/download/stream" as current_block_download_stream
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[report_owned, header]
import ../../../src/state/accumulation/current/consensus as accumulation_current_consensus
import ../../../src/storage/managed/manifest as managed_manifest
import ../../support/[accumulation_current_chain_context,
  current_application_context,
  current_download_command_context, current_services_disk_samples,
  managed_storage_samples,
  block_download_transport]

type RemoteWitness {.pure.} = enum ## Refusal mode remains independent of the command's actual result.
  Adopt, WrongParent, Timeout
const
  ChainPath = "pvm-current-download-remote-chain"
  PolicyPath = "pvm-current-download-remote-policy"
  Database = "pvm-current-download-remote-state"
  StopPath = "pvm-current-download-remote-stop"
  CountPath = "pvm-current-download-remote-count"

proc historicalFrame(context: CurrentChainFixture, wrong: bool): seq[byte] =
  ## Exact original sealed header plus seven empty extrinsics grants lineage context, never a current completion certificate.
  assert context.older.len == 1
  var body = currentChainBytes(context.older[0])
  if wrong: body[body.high] = body[body.high] xor 1 # Same extent and syntax cannot substitute a different sealed identity.
  for index in 0..<7: body.add(0'u8)
  result = newSeq[byte](body.len+4)
  for index in 0..<4: result[index] = byte((uint64(body.len) shr (8*index)) and 255)
  for index, octet in body: result[index+4] = octet

proc check(context: CurrentChainFixture, discovery, managed: bool,
    witness: RemoteWitness) {.raises.} =
  ## Fork only after all setup owners close; the isolated child checks every full request and actual FIN independently.
  var database = Database
  defer:
    if managed: removeManagedSample(database, [ManagedEpoch(1)])
    else: discard posix.unlink(database.toCString())
    for name in [ChainPath, PolicyPath, StopPath, CountPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Retire only exact test-owned paths after joining both processes.
  writeFile(ChainPath, context.currentApplicationText)
  var limits = currentCommandLimits(discovery)
  limits.stream.timeout = CurrentDownloadTimeout(20000)
  limits.attemptTimeout = CurrentDownloadAttemptTimeout(30000)
  writeFile(PolicyPath, encodeCurrentDownloadPolicy(limits))
  var before = ""
  if witness != RemoteWitness.Adopt:
    var seed = default(Services)
    assert seed.start(currentDiskOptions(ChainPath, database, false, 0), "current remote refusal seed")
    seed.close()
    before = readFile(database) # Refused remote context must preserve the existing journal byte-for-byte.
  var ancestor = currentExpectedRequest(array[32, byte](
      context.parent.value.header.headerInfo.value.unsigned.parent))
  ancestor[37] = 1 # Normative descending request starts at the retained original head's exact parent.
  let childRequest = currentExpectedRequest(array[32, byte](
      context.parent.value.blockHash))
  let historical = historicalFrame(context, witness ==
      RemoteWitness.WrongParent)
  let childWire = context.currentResponseFrame
  let behavior = if witness == RemoteWitness.Timeout: NoFin else: DownloadTransferMode.Healthy
  let requests = if discovery: @[childRequest, ancestor] else: @[ancestor, childRequest]
  let responses = if discovery: @[childWire, historical] else: @[historical, childWire]
  let modes = if discovery: @[DownloadTransferMode.Healthy, behavior] else: @[
      behavior, DownloadTransferMode.Healthy]
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses, modes)
  let port = servers.port(true)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists(StopPath) and (getMonoTime()-started).inMilliseconds < 15000:
      if not servers.poll(): posix.exitnow(3)
      yieldCurrentDiskThread() # Native callbacks retain addresses in this sole polling process.
    let count = servers.requestCount(true)
    let other = servers.requestCount(false)
    servers.close()
    if other != 0: posix.exitnow(4)
    writeFile(CountPath, $count)
    posix.exitnow(0) # Do not run destructors over inherited parent ARC/native graphs.
  servers.close()
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var state = 0.cint
      discard posix.waitpid(child, state, 0)
  var extra = @["--state-storage", "disk", "--state-db", database,
    (if discovery: "--download-discover-ancestors" else: "--download-remote-ancestors"), "1"]
  if managed:
    extra.add("--state-layout")
    extra.add("managed")
    extra.add("--state-compact-bytes")
    extra.add("0") # Qualify exact current publication separately from maintenance scheduling.
  var selected = default(Options)
  let arguments = currentCommandArguments(port, 1, ChainPath, PolicyPath, extra,
    (if witness == RemoteWitness.Timeout: "1000" else: "10000"))
  assert parseCanonicalOptions(arguments, selected)
  let outcome = runCurrentDownloads(selected)
  writeFile(StopPath, "stop")
  var state = 0.cint
  assert posix.waitpid(child, state, 0) == child
  reaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0, "independent ancestor responder joined"
  let success = witness == RemoteWitness.Adopt
  let expected = if success: CurrentDownloadCommandResult.Adopted elif witness ==
      RemoteWitness.Timeout: CurrentDownloadCommandResult.Timeout else: CurrentDownloadCommandResult.Exhausted
  assert outcome.error == expected, "exact current remote outcome: " & $outcome.error
  assert outcome.requestedBlocks == 1 and outcome.adoptedBlocks == (
      if success: 1 else: 0)
  assert parseInt(readFile(CountPath)) == (if success or discovery: 2 else: 1), "original child is never downloaded twice"
  if not success: assert readFile(database) == before, "remote refusal preserves the original durable journal"
  var reopened = default(Services)
  defer: reopened.close()
  assert reopened.start(currentDiskOptions(ChainPath, database, managed, 0), "current remote strict restart")
  if success: equalCurrentDiskMap(reopened.stateSnapshot.value,
      context.source.currentConsensusState.value)
  else: equalCurrentDiskMap(reopened.stateSnapshot.value,
      context.parent.value.stateSnapshot)
  assert reopened.chainView.retainedCount == (if success: 2 else: 1)
  reopened.close()

proc main() {.raises.} =
  ## Genuine two-guarantee lookup demand distinguishes fetched original history from a synthetic readiness claim.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet)
  let context = currentChainFixture(decodeOwnedReport(report, 2).value,
      uses = 2, available = true)
  for discovery in [false, true]:
    check(context, discovery, false, RemoteWitness.Adopt)
    check(context, discovery, true, RemoteWitness.Adopt)
    check(context, discovery, false, RemoteWitness.WrongParent)
    check(context, discovery, false, RemoteWitness.Timeout)
try:
  main()
except:
  quit(2) # Protocol, process, current execution and complete-map failures cannot satisfy acquisition evidence.
echo "PVM current download remote passed"
