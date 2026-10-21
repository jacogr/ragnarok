# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent real TLS responder and durable-map witness for the actual application executable.
import std/[assertions, syncio, envvars, monotimes, times, os]
import ../../src/app/download_policy
import ../../src/quic/[block_download_loop, block_download_stream]
import ../../src/codec/report_owned
import ../support/[application_download_chain, application_download_command_context,
  application_download_disk_context, block_download_transport]

proc main() {.raises.} =
  ## Write a genuine source chain and explicit policy, then serve only independently authored exact requests/bytes.
  let mode = getEnv("RAGNAROK_DOWNLOAD_SEQUENCE_CASE")
  assert mode in ["complete", "resumed", "replay", "timeout"]
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(report, 2).value)
  writeFile("sequence-chain.json", context.seed.text)
  var limits = downloadLimits()
  if mode == "timeout":
    limits.stream.timeout = DownloadTimeout(20000)
    limits.attemptTimeout = DownloadAttemptTimeout(
        30000) # Command expiry must occur before these independent stage ceilings.
  writeFile("sequence-policy.conf", encodeDownloadPolicy(limits))
  if mode == "resumed":
    initializeFinalizedPrefix(context, "sequence-state.db") # Independent actual adoption persists one child and explicit original-head finality.
  let first = if mode == "resumed": 1 else: 0
  let total = if mode == "complete": 3 else: 2
  var requests: seq[array[42, byte]] = @[]
  var responses: seq[seq[byte]] = @[]
  var modes: seq[DownloadTransferMode] = @[]
  for index in 0..<total:
    requests.add(expectedRequest(context.heads[first + index]))
    responses.add(responseFrame(context.children[if mode == "replay" and index ==
        1: 0 else: first + index]))
    modes.add(if mode == "timeout" and index == 1: NoFin else: DownloadTransferMode.Healthy)
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses, modes)
  let port = servers.port(true)
  writeFile("sequence-ready", $port) # Python launches the real command only after observing a complete bounded port value.
  let started = getMonoTime()
  while not fileExists("sequence-stop"):
    assert (getMonoTime() - started).inMilliseconds < 20000, "executable responder deadline"
    assert servers.poll(), "actual independent TLS progress"
    pauseDownload()
  let count = servers.requestCount(true)
  servers.close() # No endpoint callback remains when the actual executable's completed disk prefix is inspected.
  assert count == total, "actual executable request count"
  let completed = if mode in ["complete", "resumed"]: 3 else: 1
  assertDiskPrefix(context, completed, "sequence-chain.json", "sequence-state.db",
    finalizedIndex = if mode == "resumed": 0 else: -1)
  echo "SEQUENCE_VERIFIED adopted=" & $(if mode == "resumed": 2 else: completed) & " requests=" & $count
try:
  main() # Native/assertion/file failures remain strict independent-process failures.
except:
  quit(2)
