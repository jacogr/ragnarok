# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real pinned TLS validates changing parent requests, retained lineage, exact partial progress and bounded retry/deadline behavior.
import std/[assertions, syncio, envvars, os]
import std/posix/posix
import ../../../src/app/[download_command, download_policy, options]
import ../../../src/quic/[block_download_loop, block_download_stream]
import ../../../src/codec/[bounded, report_owned, header]
import ../../support/[application_download_chain, application_download_command_context, block_download_transport]

const
  ChainPath = "download-progress-chain.json"
  PolicyPath = "download-progress-policy.conf"

proc check(context: DownloadChainFixture, count: int) {.raises.} =
  ## Every admitted finite prefix uses the same retained endpoint and exact new-parent CE request.
  var responses: seq[seq[byte]] = @[]
  var modes: seq[DownloadTransferMode] = @[]
  for index in 0..<count:
    responses.add(responseFrame(context.children[index]))
    modes.add(DownloadTransferMode.Healthy)
  let observed = exchangeDownloads(context, responses, modes, count, downloadLimits(), ChainPath,
    PolicyPath, "download-progress")
  assert observed.outcome.error == DownloadCommandResult.Adopted
  assert observed.outcome.requestedBlocks == count and observed.outcome.adoptedBlocks == count
  assert observed.firstRequests == 0 and observed.secondRequests == count

proc refusedPrefixes(context: DownloadChainFixture) {.raises.} =
  ## A later empty, replayed, damaged, malformed or composition-refused child never erases the first real adoption.
  let first = responseFrame(context.children[0])
  let second = responseFrame(context.children[1])
  var damaged = second
  damaged[4 + context.heads[2].header.headerInfo.value.consumed - 1] =
    damaged[4 + context.heads[2].header.headerInfo.value.consumed - 1] xor 1
  for last in [@[0'u8, 0, 0, 0], first, damaged, @[1'u8, 0, 0, 0, 0]]:
    let observed = exchangeDownloads(context, @[first, last], @[DownloadTransferMode.Healthy,
      DownloadTransferMode.Healthy], 3, downloadLimits(), ChainPath, PolicyPath, "download-refused")
    assert observed.outcome.error == DownloadCommandResult.Exhausted
    assert observed.outcome.requestedBlocks == 3 and observed.outcome.adoptedBlocks == 1
    assert observed.secondRequests == 2 # The second exact request was real; stale bytes/signatures never became a second receipt.
  var limits = downloadLimits()
  limits.composition.validators.services = ElementLimit(1)
  let late = exchangeDownloads(context, @[first, second], @[DownloadTransferMode.Healthy,
    DownloadTransferMode.Healthy], 3, limits, ChainPath, PolicyPath, "download-policy-refused")
  assert late.outcome.error == DownloadCommandResult.Exhausted and late.outcome.adoptedBlocks == 1
  assert late.secondRequests == 2
  limits = downloadLimits()
  let exact = uint64(context.heads[0].header.headerInfo.value.consumed + context.heads[
      1].header.headerInfo.value.consumed)
  limits.input.ancestorBytes = ByteLimit(exact - 1)
  let short = exchangeDownloads(context, @[first, second], @[DownloadTransferMode.Healthy,
    DownloadTransferMode.Healthy], 3, limits, ChainPath, PolicyPath, "download-byte-refused")
  assert short.outcome.error == DownloadCommandResult.AdmissionFailure and
      short.outcome.adoptedBlocks == 2
  assert short.secondRequests == 2 # Actual evolved bytes refuse before opening the third stream.
  limits.input.ancestorBytes = ByteLimit(exact)
  let fit = exchangeDownloads(context, @[first, second, responseFrame(context.children[2])],
    @[DownloadTransferMode.Healthy, DownloadTransferMode.Healthy, DownloadTransferMode.Healthy],
    3, limits, ChainPath, PolicyPath, "download-byte-exact")
  assert fit.outcome.error == DownloadCommandResult.Adopted and fit.outcome.adoptedBlocks == 3
  limits = downloadLimits()
  limits.stream.timeout = DownloadTimeout(20000)
  limits.attemptTimeout = DownloadAttemptTimeout(30000)
  let timeout = exchangeDownloads(context, @[first, second], @[DownloadTransferMode.Healthy,
    NoFin], 3, limits, ChainPath, PolicyPath, "download-timeout", timeout = "4000")
  assert timeout.outcome.error == DownloadCommandResult.Timeout and timeout.outcome.adoptedBlocks == 1
  assert timeout.secondRequests == 2 # Shared command expiry precedes the explicit longer stream/attempt deadlines.
  limits = downloadLimits()
  limits.schedule.peers = ElementLimit(2)
  limits.schedule.attempts = 2
  let fallback = exchangeDownloads(context, @[first, second, responseFrame(context.children[2])],
    @[DownloadTransferMode.Healthy, DownloadTransferMode.Healthy, DownloadTransferMode.Healthy],
    3, limits, ChainPath, PolicyPath, "download-fallback", fallback = true)
  assert fallback.outcome.error == DownloadCommandResult.Adopted and
      fallback.outcome.adoptedBlocks == 3
  assert fallback.firstRequests == 3 and fallback.secondRequests ==
      3 # Each child gets an explicit fresh attempt budget on the retained pinned peers.

proc main() {.raises.} =
  ## Genuine ordinary-epoch successors are prepared before any responder fork; eight children cross the local history-retention window.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(wire, 2).value, 8)
  writeFile(ChainPath, context.seed.text)
  defer:
    for name in [ChainPath, PolicyPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Private generated command inputs retire on every verdict.
  let empty = default(DownloadCommandOutcome)
  assert empty.error == DownloadCommandResult.Uninitialized and empty.requestedBlocks == 0 and
      empty.adoptedBlocks == 0
  let invalid = runDownloads(default(Options))
  assert invalid.error == DownloadCommandResult.InvalidOptions and invalid.adoptedBlocks == 0
  var limits = downloadLimits()
  limits.input.ancestors = ElementLimit(1)
  writeFile(PolicyPath, encodeDownloadPolicy(limits))
  var selected = default(Options)
  assert parseOptions(downloadArguments(1, 3, ChainPath, PolicyPath,
    @["--state-storage", "disk", "--state-db", "download-progress-refused.db"]), selected)
  let refused = runDownloads(selected)
  assert refused.error == DownloadCommandResult.InvalidPolicy and refused.adoptedBlocks == 0
  assert not fileExists("download-progress-refused.db"), "whole lineage count refuses before disk startup"
  for count in [1, 2, 3, 8]: check(context, count)
  refusedPrefixes(context)
  echo "PASS application download progress: real successive TLS requests, bounded ancestry and exact confirmed counts"
try:
  main() # Fixture/native failures remain actual test failures.
except:
  quit(2)
