# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent TLS requests and complete durable-map checks qualify the actual current command executable.
import std/[assertions, syncio, envvars, monotimes, times, os]
import ../../src/app/[current_download_policy, services]
import ../../src/quic/[current_block_download_stream, current_block_download_loop]
import ../../src/codec/[report_owned, bounded]
import ../../src/chain/[genesis, provider]
import ../../src/crypto/primitives
import ../../src/state/[block_admission, report_admission, accumulation_current_consensus]
import ../support/[accumulation_current_chain_context,
  current_download_command_context,
  current_application_context, current_services_disk_samples, block_download_transport,
  current_consecutive_context, current_consecutive_download_context]

proc main() {.raises.} =
  ## The witness owns wire/state assertions; Python owns process arguments, output and joined cleanup.
  let mode = getEnv("RAGNAROK_CURRENT_SEQUENCE_CASE")
  assert mode in ["journal", "managed", "journal-resumed", "managed-resumed", "replay", "empty",
      "timeout", "resource"]
  let managed = mode in ["managed", "managed-resumed", "empty"]
  let partial = mode in ["replay", "empty", "timeout", "resource"]
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet)
  let fixture = currentConsecutiveFixture(decodeOwnedReport(report, 2).value)
  writeFile("current-chain.json", fixture.seed.currentApplicationText)
  var limits = currentConsecutivePolicy()
  if mode == "timeout":
    limits.stream.timeout = CurrentDownloadTimeout(20000)
    limits.attemptTimeout = CurrentDownloadAttemptTimeout(30000)
  if mode == "resource":
    limits.candidate.completion.composition.recent.history.blocks = ElementLimit(
        3) # Third successor requires four retained C3 rows.
  writeFile("current-policy.conf", encodeCurrentDownloadPolicy(limits))
  var requests = newSeq[array[42, byte]](0)
  var responses = newSeq[seq[byte]](0)
  var modes = newSeq[DownloadTransferMode](0)
  for index in 0..2:
    requests.add(currentExpectedRequest(array[32, byte](fixture.heads[index].blockHash)))
    if index == 2 and mode == "empty":
      responses.add(newSeq[byte](0))
    elif index == 2 and mode == "replay":
      responses.add(currentConsecutiveResponse(fixture.children[0]))
    else:
      responses.add(currentConsecutiveResponse(fixture.children[index]))
    modes.add(if index == 2 and mode == "timeout": NoFin else: DownloadTransferMode.Healthy)
  var servers = default(DownloadResponders)
  let resumed = mode in ["journal-resumed", "managed-resumed"]
  if resumed:
    assert servers.openSequenceResponders(@[requests[0]], @[responses[0]], @[modes[0]])
  else:
    assert servers.openSequenceResponders(requests, responses, modes)
  writeFile("current-ready", $servers.port(true))
  var prefixRequests = 0
  let started = getMonoTime()
  while not fileExists("current-stop"):
    assert (getMonoTime()-started).inMilliseconds < 25000, "current executable responder deadline"
    if resumed and prefixRequests == 0 and fileExists("current-next"):
      # Each fresh executable uses a fresh independent listener; this fixture transport admits one connection.
      assert servers.requestCount(true) == 1 and servers.requestCount(false) == 0
      servers.close()
      servers = default(DownloadResponders)
      assert servers.openSequenceResponders(@[requests[1], requests[2]], @[responses[1], responses[
          2]], @[modes[1], modes[2]])
      prefixRequests = 1
      writeFile("current-ready", $servers.port(true))
    assert servers.poll(), "independent current TLS progress"
    yieldCurrentDiskThread()
  let count = prefixRequests+servers.requestCount(true)
  assert servers.requestCount(false) == 0, "unused identity receives no request"
  servers.close() # Completed application IO/worker shutdown precedes strict independent disk inspection.
  assert count == 3, "exact consecutive executable request count"
  let adopted = if partial: 2 else: 3
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(currentDiskOptions("current-chain.json", "current-state.db", managed, 0), "consecutive executable strict reopen")
  let view = owner.chainView
  assert view.retainedCount == adopted+1
  assert view.finalizedBlock.error == GenesisError.Unavailable
  for index in 0..adopted:
    let actual = view.retainedBlockAt(RetainedBlockIndex(uint64(index))).value
    assert array[32, byte](actual.blockHash) == array[32, byte](fixture.heads[index].blockHash)
    equalCurrentDiskMap(actual.stateSnapshot, fixture.heads[index].stateSnapshot)
  owner.close()
  echo "CURRENT_SEQUENCE_VERIFIED adopted=" & $adopted & " requests=" & $count

try:
  main()
except:
  quit(2) # Any native transport, map or ownership failure defeats the independent witness verdict.
