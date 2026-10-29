# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared explicit command policies and independent forked TLS series retain exact requests and joined process cleanup.
import std/[assertions, syncio, envvars, monotimes, times, os, strutils]
import std/posix/posix
import ../../src/app/download/[command as download_command, policy as download_policy,
    schedule as download_schedule]
import ../../src/app/options
import "../../src/app/block/input" as block_input
import "../../src/quic/block/download/loop" as block_download_loop
import "../../src/quic/block/download/stream" as block_download_stream
import ../../src/codec/bounded
import ./[application_download_chain, application_candidate_context, block_download_transport]

type DownloadExchange* = object ## Scalar observations retain no native process, socket or canonical alias.
  outcome*: DownloadCommandOutcome
  firstRequests*, secondRequests*: int

proc pauseDownload*() =
  ## Yield between bounded responder polls without introducing another host thread.
  var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
  var remaining = default(Timespec)
  discard nanosleep(requested, remaining)

proc downloadLimits*(): DownloadLoopLimits =
  ## Explicit ceilings cover evolved statistics and the complete ordinary-epoch fixture lineage.
  DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(1)), input: BlockInputLimits(blockBytes: ByteLimit(100000),
    ancestors: ElementLimit(8), ancestorBytes: ByteLimit(100000)), candidate: preparationLimits(),
    composition: chainCompositionLimits(), stream: DownloadStreamLimits(readBytes: ByteLimit(4096),
    writeBytes: ByteLimit(42), timeout: DownloadTimeout(5000)),
        attemptTimeout: DownloadAttemptTimeout(8000))

proc downloadArguments*(port: uint16, count: int, chainPath, policyPath: string,
    extra: seq[string] = @[], timeout = "10000"): seq[string] =
  ## Preserve the actual executable command shape and explicit pinned second identity.
  result = @["download", $port, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    getEnv("RAGNAROK_TEST_PEER_B"), "jamnp-s/1/00000000", timeout, policyPath,
    "--with-state", "--chain", chainPath, "--state-writes", "1000", "--state-write-bytes",
        "1000000",
    "--download-blocks", $count]
  for value in extra: result.add(value) # Callers select backend/RPC policy without mutating the retained argv owner.

proc exchangeDownloads*(context: DownloadChainFixture, responses: seq[seq[byte]],
    modes: seq[DownloadTransferMode], count: int, limits: DownloadLoopLimits,
    chainPath, policyPath, prefix: string, extra: seq[string] = @[], timeout = "10000",
    firstChild = 0, fallback = false): DownloadExchange {.raises.} =
  ## Independent responders verify the exact parent series; every exit joins them after command workers/callbacks retire.
  result = default(DownloadExchange)
  assert firstChild >= 0 and responses.len > 0 and responses.len == modes.len
  assert firstChild + responses.len <= context.heads.len
  let stopPath = prefix & "-stop"
  let countPath = prefix & "-count"
  var stop = stopPath
  discard posix.unlink(stop.toCString())
  defer:
    for name in [stopPath, countPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Generated process signals/evidence never survive their owning exchange.
  writeFile(chainPath, context.seed.text)
  writeFile(policyPath, encodeDownloadPolicy(limits))
  var requests: seq[array[42, byte]] = @[]
  for index in 0..<responses.len: requests.add(expectedRequest(context.heads[firstChild + index]))
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses, modes, fallback)
  let port = servers.port(true)
  let firstPort = servers.port(false)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists(stopPath) and (getMonoTime() - started).inMilliseconds < 15000:
      if not servers.poll(): posix.exitnow(3) # Actual native responder errors cannot become a passing command verdict.
      pauseDownload()
    let first = servers.requestCount(false)
    let second = servers.requestCount(true)
    servers.close()
    writeFile(countPath, $first & ":" & $second)
    posix.exitnow(0) # Forked children never run destructors over copied parent canonical graphs.
  servers.close()
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var state = 0.cint
      discard posix.waitpid(child, state, 0) # Assertion, IO and command failures still retire the bounded responder.
  var arguments = downloadArguments(port, count, chainPath, policyPath, extra, timeout)
  if fallback:
    var pairs: seq[string] = @[]
    for index in 0..<8:
      pairs.add(if index == 1: $firstPort elif index == 4: getEnv(
          "RAGNAROK_TEST_PEER_A") else: arguments[index])
    pairs.add($port)
    pairs.add(getEnv("RAGNAROK_TEST_PEER_B"))
    for index in 8..<arguments.len: pairs.add(arguments[
        index]) # Additional peer tuples stay before every service control.
    arguments = pairs
  var options = default(Options)
  assert parseCanonicalOptions(arguments, options)
  let outcome = runDownloads(options)
  writeFile(stopPath, "stop")
  var state = 0.cint
  assert posix.waitpid(child, state, 0) == child
  reaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0, "independent TLS responder completed"
  let counts = readFile(countPath)
  let separator = counts.find(':')
  assert separator > 0 and separator < counts.len - 1
  result = DownloadExchange(outcome: outcome, firstRequests: parseInt(counts.substr(0, separator - 1)),
    secondRequests: parseInt(counts.substr(separator + 1)))
