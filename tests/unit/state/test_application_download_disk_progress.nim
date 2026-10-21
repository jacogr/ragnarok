# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Durable multi-child success, later refusal, resumed runs and bounded history preserve independently composed complete maps and explicit finality.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/download_command
import ../../../src/quic/[block_download_loop, block_download_stream]
import ../../../src/codec/[bounded, report_owned]
import ../../support/[application_download_chain, application_download_command_context,
  application_download_disk_context, block_download_transport]

const
  ChainPath = "download-disk-chain.json"
  PolicyPath = "download-disk-policy.conf"
  DiskPath = "download-progress.db"

proc removeDisk() =
  ## Each independent scenario creates a fresh selected database; no production repair/overwrite path is invoked.
  var path = DiskPath
  discard posix.unlink(path.toCString())

proc extra(): seq[string] =
  ## Backend choice remains independent of import authority and future full/light modes.
  @["--state-storage", "disk", "--state-db", DiskPath]

proc main() {.raises.} =
  ## Author eight real ordinary-epoch successors before process/worker startup.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(wire, 2).value, 8)
  defer:
    for name in [ChainPath, PolicyPath, DiskPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Every synchronous inspection/command returns after closing its actual disk lock.
  let healthy = @[DownloadTransferMode.Healthy, DownloadTransferMode.Healthy,
      DownloadTransferMode.Healthy]
  let first = responseFrame(context.children[0])
  let second = responseFrame(context.children[1])
  let third = responseFrame(context.children[2])
  let complete = exchangeDownloads(context, @[first, second, third], healthy, 3, downloadLimits(),
    ChainPath, PolicyPath, "disk-complete", extra())
  assert complete.outcome.error == DownloadCommandResult.Adopted and
      complete.outcome.adoptedBlocks == 3
  assert complete.secondRequests == 3
  assertDiskPrefix(context, 3, ChainPath, DiskPath)
  let resumed = exchangeDownloads(context, @[responseFrame(context.children[3]), responseFrame(
      context.children[4])],
    @[DownloadTransferMode.Healthy, DownloadTransferMode.Healthy], 2, downloadLimits(),
    ChainPath, PolicyPath, "disk-resumed", extra(), firstChild = 3)
  assert resumed.outcome.error == DownloadCommandResult.Adopted and resumed.outcome.adoptedBlocks == 2
  assert resumed.secondRequests == 2
  assertDiskPrefix(context, 5, ChainPath, DiskPath) # Requested/adopted diagnostics count this run while the actual durable chain retains its full prefix.
  let bytes = readFile(DiskPath)
  let stale = exchangeDownloads(context, @[first], @[DownloadTransferMode.Healthy], 2,
    downloadLimits(), ChainPath, PolicyPath, "disk-stale", extra(), firstChild = 5)
  assert stale.outcome.error == DownloadCommandResult.Exhausted and stale.outcome.adoptedBlocks == 0
  assert stale.secondRequests == 1 and readFile(DiskPath) == bytes
  assertDiskPrefix(context, 5, ChainPath, DiskPath)
  removeDisk()
  let empty = exchangeDownloads(context, @[first, @[0'u8, 0, 0, 0]], healthy[0..1], 3,
    downloadLimits(), ChainPath, PolicyPath, "disk-empty", extra())
  assert empty.outcome.error == DownloadCommandResult.Exhausted and empty.outcome.adoptedBlocks == 1
  assertDiskPrefix(context, 1, ChainPath, DiskPath)
  removeDisk()
  var limits = downloadLimits()
  limits.composition.validators.services = ElementLimit(1)
  let refused = exchangeDownloads(context, @[first, second], healthy[0..1], 3, limits,
    ChainPath, PolicyPath, "disk-refused", extra())
  assert refused.outcome.error == DownloadCommandResult.Exhausted and
      refused.outcome.adoptedBlocks == 1
  assert refused.secondRequests == 2
  assertDiskPrefix(context, 1, ChainPath, DiskPath)
  removeDisk()
  limits = downloadLimits()
  limits.stream.timeout = DownloadTimeout(20000)
  limits.attemptTimeout = DownloadAttemptTimeout(30000)
  let timeout = exchangeDownloads(context, @[first, second], @[DownloadTransferMode.Healthy, NoFin],
    3, limits, ChainPath, PolicyPath, "disk-timeout", extra(), timeout = "4000")
  assert timeout.outcome.error == DownloadCommandResult.Timeout and timeout.outcome.adoptedBlocks == 1
  assert timeout.secondRequests == 2
  assertDiskPrefix(context, 1, ChainPath, DiskPath)
  removeDisk()
  initializeFinalizedPrefix(context, DiskPath)
  let finalized = exchangeDownloads(context, @[second, third], healthy[0..1], 2, downloadLimits(),
    ChainPath, PolicyPath, "disk-finalized", extra(), firstChild = 1)
  assert finalized.outcome.error == DownloadCommandResult.Adopted and
      finalized.outcome.adoptedBlocks == 2
  assertDiskPrefix(context, 3, ChainPath, DiskPath, finalizedIndex = 0)
  removeDisk()
  var responses: seq[seq[byte]] = @[]
  var modes: seq[DownloadTransferMode] = @[]
  for child in context.children:
    responses.add(responseFrame(child))
    modes.add(DownloadTransferMode.Healthy)
  let rolling = exchangeDownloads(context, responses, modes, 8, downloadLimits(),
    ChainPath, PolicyPath, "disk-rolling", extra())
  assert rolling.outcome.error == DownloadCommandResult.Adopted and rolling.outcome.adoptedBlocks == 8
  assert rolling.secondRequests == 8
  assertDiskPrefix(context, 8, ChainPath, DiskPath) # Actual restart retains eight roots and evicts the original unfinalized head.
  echo "PASS application download disk progress: confirmed prefixes, resumed runs, exact maps and explicit bounded history/finality"
try:
  main() # Process/file/native failures retain the native runner's failed verdict.
except:
  quit(2)
