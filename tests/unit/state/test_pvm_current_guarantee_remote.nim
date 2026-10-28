# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual current command acquires original ancestry only after the first adoption, preserving exact prefixes on wrong context or timeout.
import std/[assertions, envvars, syncio, monotimes, times, os, strutils]
import std/posix/posix
import ../../../src/app/[current_download_command, current_download_policy, options, services]
import ../../../src/quic/[current_block_download_loop, current_block_download_stream]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/report_owned
import ../../../src/storage/managed_manifest
import ../../support/[current_guarantee_sequence_context, current_guarantee_remote_context,
  current_consecutive_download_context, current_download_command_context,
  current_application_context,
  current_services_disk_samples, managed_storage_samples, block_download_transport]
type RemoteCase {.pure.} = enum ## The independent responder changes only original-context bytes or FIN behavior.
  Adopt, WrongParent, Timeout
const ChainPath = "pvm-current-guarantee-remote-chain"
const PolicyPath = "pvm-current-guarantee-remote-policy"

proc check(fixture: CurrentGuaranteeSequenceFixture, layout: int, mode: RemoteCase) {.raises.} =
  ## Every fork precedes Services/native workers; each callback owner remains at its original child-process address until join.
  var database = "pvm-current-guarantee-remote-state-" & $getMonoTime().ticks
  let stopPath = database & "-stop"
  let countPath = database & "-count"
  defer:
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString())
    for name in [ChainPath, PolicyPath, stopPath, countPath]:
      var path = name
      discard posix.unlink(path.toCString())
  writeFile(ChainPath, fixture.sequence.seed.currentApplicationText)
  var policy = currentConsecutivePolicy()
  policy.input.discoverAncestors = true
  policy.stream.timeout = CurrentDownloadTimeout(20000)
  policy.attemptTimeout = CurrentDownloadAttemptTimeout(30000)
  writeFile(PolicyPath, encodeCurrentDownloadPolicy(policy))
  let modes = @[Healthy, Healthy, (if mode == RemoteCase.Timeout: NoFin else: Healthy)]
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(currentGuaranteeRequests(fixture),
      currentGuaranteeResponses(fixture, mode == RemoteCase.WrongParent), modes)
  let port = servers.port(true)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists(stopPath) and (getMonoTime()-started).inMilliseconds < 15000:
      if not servers.poll(): posix.exitnow(3)
      yieldCurrentDiskThread() # Independent native progress borrows no parent-process canonical graph.
    let count = servers.requestCount(true)
    let unused = servers.requestCount(false)
    servers.close()
    if unused != 0: posix.exitnow(4)
    writeFile(countPath, $count)
    posix.exitnow(0) # Inherited parent ARC owners never undergo destruction in the forked process.
  servers.close()
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(child, status, 0)
  var extra = @["--download-discover-ancestors", "1"]
  if layout != 0:
    for argument in ["--state-storage", "disk", "--state-db", database]: extra.add(argument)
    if layout == 2:
      for argument in ["--state-layout", "managed", "--state-compact-bytes", "0"]: extra.add(argument)
  var options = default(Options)
  assert parseCanonicalOptions(currentCommandArguments(port, 2, ChainPath, PolicyPath, extra,
    (if mode == RemoteCase.Timeout: "4000" else: "10000")), options)
  let outcome = runCurrentDownloads(options)
  writeFile(stopPath, "stop")
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "independent current guarantee remote responder joined"
  assert parseInt(readFile(countPath)) == 3, "two current requests and exactly one original-context request"
  let adopted = if mode == RemoteCase.Adopt: 2 else: 1
  let expected = if mode == RemoteCase.Adopt: CurrentDownloadCommandResult.Adopted elif mode ==
      RemoteCase.Timeout: CurrentDownloadCommandResult.Timeout else: CurrentDownloadCommandResult.Exhausted
  assert outcome.error == expected and outcome.adoptedBlocks == adopted and
      outcome.requestedBlocks == 2
  if layout == 0: return # Actual memory command outcomes intentionally retain scalar progress alone.
  var reopened = default(Services)
  defer: reopened.close()
  assert reopened.start(currentDiskOptions(ChainPath, database, layout == 2, 0), "strict original guarantee remote restart")
  let view = reopened.chainView
  assert view.retainedCount == adopted+1 and view.finalizedBlock.error == GenesisError.Unavailable
  for index in 0..adopted:
    let actual = view.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
    assert array[32, byte](actual.blockHash) == array[32, byte](fixture.sequence.heads[
        index].blockHash)
    equalCurrentDiskMap(actual.stateSnapshot, fixture.sequence.heads[index].stateSnapshot)
  reopened.close()

proc main() {.raises.} =
  ## Real discovery succeeds or refuses after the same confirmed first child in memory and both durable layouts.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = currentGuaranteeSequenceFixture(decodeOwnedReport(bytes, 2).value)
  for layout in 0..2:
    for mode in [RemoteCase.Adopt, RemoteCase.WrongParent, RemoteCase.Timeout]: check(fixture,
        layout, mode)
try:
  main()
except:
  quit(2) # Wrong direction, repeat download, incorrect deadline or changed complete durable history cannot satisfy acquisition evidence.
echo "PVM current guarantee remote passed"
