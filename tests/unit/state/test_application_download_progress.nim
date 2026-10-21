# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real pinned TLS response series validates each newly adopted parent's exact CE request.
import std/[assertions, syncio, envvars, monotimes, times, os]
import std/posix/posix
import ../../../src/app/[download_command, download_policy, download_schedule, options, block_input]
import ../../../src/quic/[block_download_loop, block_download_stream]
import ../../../src/codec/[bounded, report_owned]
import ../../support/[application_download_chain, application_candidate_context, block_download_transport]

const
  ChainPath = "download-progress-chain.json"
  PolicyPath = "download-progress-policy.conf"
  StopPath = "download-progress-stop"
  CountPath = "download-progress-count"

proc pause() =
  ## Yield between bounded responder polls; all native events remain on this host thread.
  var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(requested, remaining)

proc progressLimits(): DownloadLoopLimits =
  ## Explicit resource ceilings cover evolved service statistics and the retained three-child header lineage.
  DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(1)), input: BlockInputLimits(blockBytes: ByteLimit(100000),
    ancestors: ElementLimit(8), ancestorBytes: ByteLimit(100000)), candidate: preparationLimits(),
    composition: chainCompositionLimits(), stream: DownloadStreamLimits(readBytes: ByteLimit(4096),
    writeBytes: ByteLimit(42), timeout: DownloadTimeout(5000)),
        attemptTimeout: DownloadAttemptTimeout(8000))

proc progressOptions(port: uint16, count: int, extra: seq[string] = @[]): Options =
  ## All peers remain explicitly pinned; service controls follow the original positional command shape.
  var arguments = @["download", $port, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    getEnv("RAGNAROK_TEST_PEER_B"), "jamnp-s/1/00000000", "10000", PolicyPath,
    "--with-state", "--chain", ChainPath, "--state-writes", "1000", "--state-write-bytes",
        "1000000",
    "--download-blocks", $count]
  for value in extra: arguments.add(value) # Parser/command own the copied complete option tuple.
  result = default(Options)
  assert parseOptions(arguments, result)

proc positive(context: DownloadChainFixture, count: int) {.raises.} =
  ## Forked independent responders see exactly one changing parent-bound request for each confirmed child.
  var stop = StopPath
  discard posix.unlink(stop.toCString())
  var requests: seq[array[42, byte]] = @[]
  var responses: seq[seq[byte]] = @[]
  var modes: seq[DownloadTransferMode] = @[]
  for index in 0..<count:
    requests.add(expectedRequest(context.heads[index]))
    responses.add(responseFrame(context.children[index]))
    modes.add(DownloadTransferMode.Healthy)
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses, modes)
  let port = servers.port(true)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists(StopPath) and (getMonoTime() - started).inMilliseconds < 12000:
      if not servers.poll(): posix.exitnow(3) # Native responder failure cannot become a command success.
      pause()
    let observed = servers.requestCount(true)
    servers.close()
    writeFile(CountPath, $observed)
    posix.exitnow(0) # No copied parent canonical graph runs destructors in the child.
  servers.close()
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var state = 0.cint
      discard posix.waitpid(child, state, 0) # Every assertion/exception path retires the responder.
  writeFile(PolicyPath, encodeDownloadPolicy(progressLimits()))
  let outcome = runDownloads(progressOptions(port, count))
  assert outcome.error == DownloadCommandResult.Adopted, "bounded command terminal success count=" &
      $count & " error=" & $outcome.error & " adopted=" & $outcome.adoptedBlocks
  assert outcome.requestedBlocks == count and outcome.adoptedBlocks == count, "exact confirmed progress"
  writeFile(StopPath, "stop")
  var state = 0.cint
  assert posix.waitpid(child, state, 0) == child
  reaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0
  assert readFile(CountPath) == $count, "one exact new-parent CE request per adopted child"

proc main() {.raises.} =
  ## Genuine signed children and expected complete maps are prepared before any native responder is forked.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(wire, 2).value)
  writeFile(ChainPath, context.seed.text)
  defer:
    for name in [ChainPath, PolicyPath, StopPath, CountPath]:
      var path = name
      discard posix.unlink(path.toCString()) # All generated inputs/evidence stay inside the runner's private work directory.
  let empty = default(DownloadCommandOutcome)
  assert empty.error == DownloadCommandResult.Uninitialized and empty.requestedBlocks == 0 and
      empty.adoptedBlocks == 0
  let invalid = runDownloads(default(Options))
  assert invalid.error == DownloadCommandResult.InvalidOptions and invalid.adoptedBlocks == 0
  var limits = progressLimits()
  limits.input.ancestors = ElementLimit(1)
  writeFile(PolicyPath, encodeDownloadPolicy(limits))
  let refused = runDownloads(progressOptions(1, 3, @["--state-storage", "disk", "--state-db",
      "download-progress-refused.db"]))
  assert refused.error == DownloadCommandResult.InvalidPolicy and refused.adoptedBlocks == 0
  assert not fileExists("download-progress-refused.db"), "whole lineage count refuses before disk startup"
  for count in 1..3: positive(context, count) # Legacy one-child and each finite prefix use the same joined production path.
  echo "PASS application download progress: real successive TLS requests, bounded ancestry and exact confirmed counts"
try:
  main() # Native/fixture failures remain genuine test failures.
except:
  quit(2)
