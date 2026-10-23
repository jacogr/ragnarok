# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit multi-child native request sequences qualify command restart and bounded authenticated retries.
import std/[assertions, syncio, monotimes, times, os, strutils, envvars]
import std/posix/posix
import ../../src/chain/genesis
import ../../src/app/[current_download_command, current_download_policy, options]
import ../../src/quic/current_block_download_loop
import ./[current_consecutive_context, current_application_context,
  current_download_command_context,
  current_services_disk_samples, block_download_transport]

proc exchangeCurrentSequence*(fixture: CurrentConsecutiveFixture, start, requested: int,
    responses: seq[seq[byte]], modes: seq[DownloadTransferMode], policy: CurrentDownloadLoopLimits,
    chainPath, policyPath, prefix: string, extra: seq[string] = @[], timeout = "10000",
    fallback = false): CurrentDownloadExchange {.raises.} =
  ## Expected parents come from actual complete fixture heads; a restarted disk owner must select the caller's explicit start head.
  result = default(CurrentDownloadExchange)
  assert start >= 0 and responses.len > 0 and responses.len <= 4
  assert responses.len == modes.len and responses.len <= fixture.heads.len
  assert start <= fixture.heads.len-responses.len
  assert requested >= 1 and requested <= 64
  let stopPath = prefix & "-stop"
  let countPath = prefix & "-count"
  for name in [stopPath, countPath]:
    var path = name
    discard posix.unlink(path.toCString()) # A failed earlier witness cannot stop or supply evidence for this invocation.
  defer:
    for name in [stopPath, countPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Cleanup touches only this invocation's exact generated coordination paths.
  writeFile(chainPath, fixture.seed.currentApplicationText)
  writeFile(policyPath, encodeCurrentDownloadPolicy(policy))
  var requests: seq[array[42, byte]] = @[]
  for index in 0..<responses.len:
    requests.add(currentExpectedRequest(array[32, byte](fixture.heads[start+index].blockHash)))
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses, modes, fallback)
  let port = servers.port(true)
  let firstPort = servers.port(false)
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    let begin = getMonoTime()
    while not fileExists(stopPath) and (getMonoTime()-begin).inMilliseconds < 15000:
      if not servers.poll(): posix.exitnow(3)
      yieldCurrentDiskThread() # Callback state stays at the same address in this independent polling process.
    let first = servers.requestCount(false)
    let second = servers.requestCount(true)
    servers.close()
    writeFile(countPath, $first & ":" & $second)
    posix.exitnow(0) # Inherited parent fixture owners never undergo child-process ARC destruction.
  servers.close()
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var status = 0.cint
      discard posix.waitpid(child, status, 0)
  var arguments = currentCommandArguments(port, requested, chainPath, policyPath, extra, timeout)
  if fallback:
    var paired: seq[string] = @[]
    for index in 0..<8:
      paired.add(if index == 1: $firstPort elif index == 4: getEnv(
          "RAGNAROK_TEST_PEER_A") else: arguments[index])
    paired.add($port)
    paired.add(getEnv("RAGNAROK_TEST_PEER_B"))
    for index in 8..<arguments.len: paired.add(arguments[index])
    arguments = paired # Both explicit authenticated identities remain paired with their authored ports.
  var options = default(Options)
  assert parseOptions(arguments, options)
  let outcome = runCurrentDownloads(options)
  writeFile(stopPath, "stop")
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "independent current sequence responder joined"
  let counts = readFile(countPath)
  let separator = counts.find(':')
  assert separator > 0 and separator < counts.len-1
  result = CurrentDownloadExchange(outcome: outcome, firstRequests: parseInt(counts.substr(0,
      separator-1)),
    secondRequests: parseInt(counts.substr(separator+1)))
