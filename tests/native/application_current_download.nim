# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent TLS requests and complete durable-map checks qualify the actual current command executable.
import std/[assertions, syncio, envvars, monotimes, times, os]
import ../../src/app/[current_download_policy, services]
import ../../src/quic/[current_block_download_stream, current_block_download_loop]
import ../../src/codec/report_owned
import ../../src/chain/[genesis, provider]
import ../../src/crypto/primitives
import ../../src/state/[block_admission, report_admission, accumulation_current_consensus]
import ../support/[accumulation_current_chain_context,
  current_download_command_context,
  current_application_context, current_services_disk_samples, block_download_transport]

proc main() {.raises.} =
  ## The witness owns wire/state assertions; Python owns process arguments, output and joined cleanup.
  let mode = getEnv("RAGNAROK_CURRENT_DOWNLOAD_CASE")
  assert mode in ["journal", "managed", "replay", "empty", "timeout", "legacy-policy"]
  let managed = mode in ["managed", "empty"]
  let partial = mode in ["replay", "empty", "timeout"]
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet)
  let context = currentChainFixture(decodeOwnedReport(report, 2).value,
      available = true)
  writeFile("current-chain.json", context.currentApplicationText)
  var limits = currentCommandLimits()
  if mode == "timeout":
    limits.stream.timeout = CurrentDownloadTimeout(20000)
    limits.attemptTimeout = CurrentDownloadAttemptTimeout(
        30000) # Whole-command expiry precedes independent stage ceilings.
  writeFile("current-policy.conf", if mode ==
      "legacy-policy": "ragnarok-download-policy-v1\n" else: encodeCurrentDownloadPolicy(limits))
  var requests = @[currentExpectedRequest(array[32, byte](
      context.parent.value.blockHash))]
  var responses = @[context.currentResponseFrame]
  var modes = @[DownloadTransferMode.Healthy]
  if partial:
    let binding = context.source.currentChainAdmission.reportBlockStage.value.value.admitted
    let digest = blake2b256(currentChainBytes(binding.admittedHeader))
    assert digest.error == CryptoError.None
    requests.add(currentExpectedRequest(array[32, byte](
        digest.value))) # Only the actual first adopted child authorizes this second parent.
    if mode == "empty":
      responses.add(newSeq[byte](0)) # Exact empty response is independently distinct from a replay.
    else:
      responses.add(context.currentResponseFrame)
    modes.add(if mode == "timeout": NoFin else: DownloadTransferMode.Healthy)
  var servers = default(DownloadResponders)
  assert servers.openSequenceResponders(requests, responses, modes)
  writeFile("current-ready", $servers.port(true))
  let started = getMonoTime()
  while not fileExists("current-stop"):
    assert (getMonoTime()-started).inMilliseconds < 25000, "current executable responder deadline"
    assert servers.poll(), "independent current TLS progress"
    yieldCurrentDiskThread()
  let count = servers.requestCount(true)
  assert servers.requestCount(false) == 0, "unused identity receives no request"
  servers.close() # Completed application IO/worker shutdown precedes strict independent disk inspection.
  let expected = if mode == "legacy-policy": 0 elif partial: 2 else: 1
  assert count == expected, "exact current executable request count"
  if mode == "legacy-policy":
    assert not fileExists("current-state.db"), "policy preflight has no durable effects"
  else:
    var owner = default(Services)
    defer: owner.close()
    assert owner.start(currentDiskOptions("current-chain.json",
        "current-state.db", managed, 0), "current executable strict reopen")
    equalCurrentDiskMap(owner.stateSnapshot.value,
        context.source.currentConsensusState.value)
    assert owner.chainView.retainedCount == 2, "only the genuine first child is durable"
    owner.close()
  echo "CURRENT_EXECUTABLE_VERIFIED adopted=" & $(if mode ==
      "legacy-policy": 0 else: 1) & " requests=" & $count
try:
  main()
except:
  quit(2) # Any native transport, map or ownership failure defeats the independent witness verdict.
