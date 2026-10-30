# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit current command policies and independent forked TLS responders preserve exact requests, scalar progress and joined cleanup.
import std/[assertions, syncio, envvars, monotimes, times, os, strutils]
import std/posix/posix
import ../../src/app/current/download/[command as current_download_command,
    policy as current_download_policy]
import "../../src/app/current/block/input" as current_block_input
import ../../src/app/download/schedule as download_schedule
import ../../src/app/options
import "../../src/jamnp-s/current/block/download/loop" as current_block_download_loop
import "../../src/jamnp-s/current/block/download/stream" as current_block_download_stream
import ../../src/chain/[genesis, provider]
import ../../src/codec/bounded
import ../../src/crypto/primitives
import "../../src/state/block/admission" as block_admission
import ../../src/state/report/admission as report_admission
import ./[accumulation_current_chain_context, accumulation_current_candidate_context,
  current_application_context, current_services_disk_samples, block_download_transport]
type CurrentDownloadExchange* = object ## Scalar outcomes retain no canonical map or live native owner.
  outcome*: CurrentDownloadCommandOutcome
  firstRequests*, secondRequests*: int
proc currentCommandLimits*(discover = false): CurrentDownloadLoopLimits =
  ## Every current ceiling is explicit; callback/whole-attempt durations accommodate real TLS setup independently of GP slots.
  CurrentDownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(1)), input: CurrentBlockInputLimits(blockBytes: ByteLimit(
        100000),
      ancestorBytes: ByteLimit(100000), ancestors: ElementLimit(8), discoverAncestors: discover),
    candidate: currentCandidateLimits(), stream: CurrentDownloadStreamLimits(readBytes: ByteLimit(4096),
      writeBytes: ByteLimit(42), timeout: CurrentDownloadTimeout(5000)),
    attemptTimeout: CurrentDownloadAttemptTimeout(8000))
proc currentCommandArguments*(port: uint16, count: int, chainPath, policyPath: string,
    extra: seq[string] = @[], timeout = "10000"): seq[string] =
  ## Public command shape remains explicit and the selected peer pin is never inferred from a remote certificate.
  result = @["download-current", $port, getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"),
    getEnv("RAGNAROK_TEST_PEER_B"), "jamnp-s/1/00000000", timeout, policyPath,
    "--with-state", "--chain", chainPath, "--state-writes", "1000", "--state-write-bytes",
        "1000000",
    "--download-blocks", $count]
  for value in extra: result.add(value)
proc currentResponseFrame*(context: CurrentChainFixture): seq[byte] =
  ## Independently encode E4 extent and exact signed body without a production download adapter.
  let body = context.currentDiskChildBytes
  assert body.len <= high(int)-4 and uint64(body.len) <= 0xffffffff'u64
  result = newSeq[byte](body.len+4)
  for index in 0..<4: result[index] = byte((uint64(body.len) shr (8*index)) and 255)
  for index, octet in body: result[index+4] = octet
proc currentExpectedRequest*(hash: array[32, byte]): array[42, byte] =
  ## Normative CE128 request is a full sealed-header identity, ascending direction and one-child maximum.
  result = default(array[42, byte])
  result[0] = 128
  result[1] = 37
  result[38] = 1
  for index, octet in hash: result[index+5] = octet
proc exchangeCurrentDownloads*(context: CurrentChainFixture, responses: seq[seq[byte]],
    modes: seq[DownloadTransferMode], count: int, limits: CurrentDownloadLoopLimits,
    chainPath, policyPath, prefix: string, extra: seq[string] = @[], timeout = "10000",
    fallback = false): CurrentDownloadExchange {.raises.} =
  ## Responders verify the original parent and optional next-child request; all application/worker teardown precedes process reaping.
  result = default(CurrentDownloadExchange)
  assert responses.len > 0 and responses.len <= 2 and responses.len == modes.len
  let stopPath = prefix & "-stop"
  let countPath = prefix & "-count"
  var stop = stopPath
  discard posix.unlink(stop.toCString())
  defer:
    for name in [stopPath, countPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Only exact generated control/evidence names are retired.
  writeFile(chainPath, context.currentApplicationText)
  writeFile(policyPath, encodeCurrentDownloadPolicy(limits))
  var requests = @[currentExpectedRequest(array[32, byte](context.parent.value.blockHash))]
  if responses.len == 2:
    let binding = context.source.currentChainAdmission.reportBlockStage.value.value.admitted
    let digest = blake2b256(currentChainBytes(binding.admittedHeader))
    assert digest.error == CryptoError.None
    requests.add(currentExpectedRequest(array[32, byte](
        digest.value))) # Independent full sealed-header hash identifies the actually installed successor.
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses, modes, fallback)
  let port = servers.port(true)
  let firstPort = servers.port(false)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let started = getMonoTime()
    while not fileExists(stopPath) and (getMonoTime()-started).inMilliseconds < 15000:
      if not servers.poll(): posix.exitnow(3)
      yieldCurrentDiskThread() # Isolated responder polling retains its original native callback addresses.
    let first = servers.requestCount(false)
    let second = servers.requestCount(true)
    servers.close()
    writeFile(countPath, $first & ":" & $second)
    posix.exitnow(0) # Never run destructors over inherited parent ARC/native state after fork.
  servers.close() # Drop only the parent's private listener copies before the command opens endpoints.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var state = 0.cint
      discard posix.waitpid(child, state, 0)
  var arguments = currentCommandArguments(port, count, chainPath, policyPath, extra, timeout)
  if fallback:
    var pairs: seq[string] = @[]
    for index in 0..<8:
      pairs.add(if index == 1: $firstPort elif index == 4: getEnv(
          "RAGNAROK_TEST_PEER_A") else: arguments[index])
    pairs.add($port)
    pairs.add(getEnv("RAGNAROK_TEST_PEER_B"))
    for index in 8..<arguments.len: pairs.add(arguments[
        index]) # Pair preflight remains before all service controls.
    arguments = pairs
  var options = default(Options)
  assert parseCanonicalOptions(arguments, options)
  let outcome = runCurrentDownloads(options)
  writeFile(stopPath, "stop")
  var state = 0.cint
  assert posix.waitpid(child, state, 0) == child
  reaped = true
  assert WIFEXITED(state) and WEXITSTATUS(state) == 0, "independent current TLS responder joined"
  let counts = readFile(countPath)
  let separator = counts.find(':')
  assert separator > 0 and separator < counts.len-1
  result = CurrentDownloadExchange(outcome: outcome,
    firstRequests: parseInt(counts.substr(0, separator-1)), secondRequests: parseInt(counts.substr(separator+1)))
