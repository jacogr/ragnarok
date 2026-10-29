# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent TLS requests and complete durable-map checks qualify the actual current command executable.
import std/[assertions, syncio, envvars, monotimes, times, os]
import ../../src/app/current/download/policy as current_download_policy
import ../../src/app/services
import "../../src/quic/current/block/download/stream" as current_block_download_stream
import "../../src/quic/current/block/download/loop" as current_block_download_loop
import ../../src/codec/[report_owned, bounded, block_codec]
import ../../src/chain/[genesis, provider]
import ../../src/crypto/primitives
import "../../src/state/block/admission" as block_admission
import ../../src/state/report/admission as report_admission
import ../../src/state/accumulation/current/consensus as accumulation_current_consensus
import ../support/[accumulation_current_chain_context,
  current_download_command_context,
  current_application_context, current_services_disk_samples, block_download_transport,
  current_consecutive_context, current_rotated_sequence_context,
  current_consecutive_download_context,
  current_preimage_sequence_context, current_guarantee_sequence_context, current_guarantee_remote_context]

proc main() {.raises.} =
  ## The witness owns wire/state assertions; Python owns process arguments, output and joined cleanup.
  let mode = getEnv("RAGNAROK_CURRENT_SEQUENCE_CASE")
  assert mode in ["journal", "managed", "journal-resumed", "managed-resumed", "replay", "empty",
      "timeout", "resource", "managed-maintenance", "maintenance-resource", "maintenance-resumed",
      "preimages-journal", "preimages-managed", "preimages-repeated", "preimages-resumed",
      "guarantees-journal", "guarantees-managed", "guarantees-wrong", "guarantees-timeout",
      "rotated-journal", "rotated-managed", "rotated-resumed", "rotated-maintenance", "rotated-resource"]
  let rotated = mode in ["rotated-journal", "rotated-managed", "rotated-resumed",
      "rotated-maintenance", "rotated-resource"]
  let preimages = mode in ["preimages-journal", "preimages-managed", "preimages-repeated", "preimages-resumed"]
  let guarantees = mode in ["guarantees-journal", "guarantees-managed", "guarantees-wrong", "guarantees-timeout"]
  let managed = mode in ["managed", "managed-resumed", "empty", "managed-maintenance",
      "maintenance-resource", "maintenance-resumed", "preimages-managed", "preimages-repeated",
      "guarantees-managed", "guarantees-wrong", "rotated-managed", "rotated-maintenance", "rotated-resource"]
  let partial = mode in ["replay", "empty", "timeout", "resource", "maintenance-resource",
      "preimages-repeated", "guarantees-wrong", "guarantees-timeout", "rotated-resource"]
  let total = if guarantees or (preimages and not partial): 2 else: 3
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet)
  let base = decodeOwnedReport(report, 2).value
  var fixture = default(CurrentConsecutiveFixture)
  var repeated = default(OwnedBlock)
  var remoteFixture = default(CurrentGuaranteeSequenceFixture)
  if rotated:
    fixture = currentRotatedSequenceFixture(base) # Existing signed rotation and genuine second-epoch children retain exact expected maps.
  elif guarantees:
    remoteFixture = currentGuaranteeSequenceFixture(base)
    fixture = remoteFixture.sequence
  elif preimages:
    let authored = currentPreimageSequenceFixture(base)
    fixture = authored.sequence
    repeated = authored.repeated
  else:
    fixture = currentConsecutiveFixture(base) # Ordinary witnesses retain their original three-successor fixture.
  writeFile("current-chain.json", fixture.seed.currentApplicationText)
  var limits = currentConsecutivePolicy()
  if mode in ["timeout", "guarantees-timeout"]:
    limits.stream.timeout = CurrentDownloadTimeout(20000)
    limits.attemptTimeout = CurrentDownloadAttemptTimeout(30000)
  if mode in ["resource", "maintenance-resource", "rotated-resource"]:
    limits.candidate.completion.composition.recent.history.blocks = ElementLimit(
        3) # Third successor requires four retained C3 rows.
  if guarantees: limits.input.discoverAncestors = true
  writeFile("current-policy.conf", encodeCurrentDownloadPolicy(limits))
  var requests = newSeq[array[42, byte]](0)
  var responses = newSeq[seq[byte]](0)
  var modes = newSeq[DownloadTransferMode](0)
  for index in 0..<total:
    requests.add(currentExpectedRequest(array[32, byte](fixture.heads[index].blockHash)))
    if preimages and index == 2:
      responses.add(currentConsecutiveResponse(repeated)) # A fresh seal and valid parent distinguish prior-request refusal from old-header replay.
    elif index == 2 and mode == "empty":
      responses.add(newSeq[byte](0))
    elif index == 2 and mode == "replay":
      responses.add(currentConsecutiveResponse(fixture.children[0]))
    else:
      responses.add(currentConsecutiveResponse(fixture.children[index]))
    modes.add(if index == 2 and mode == "timeout": NoFin else: DownloadTransferMode.Healthy)
  var servers = default(DownloadResponders)
  if guarantees:
    requests = currentGuaranteeRequests(remoteFixture)
    responses = currentGuaranteeResponses(remoteFixture, mode == "guarantees-wrong")
    modes = @[Healthy, Healthy, (if mode == "guarantees-timeout": NoFin else: Healthy)]
  let resumed = mode in ["journal-resumed", "managed-resumed", "maintenance-resumed",
      "preimages-resumed", "rotated-resumed"]
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
      if total == 2:
        assert servers.openSequenceResponders(@[requests[1]], @[responses[1]], @[modes[1]])
      else:
        assert servers.openSequenceResponders(@[requests[1], requests[2]], @[responses[1],
            responses[2]], @[modes[1], modes[2]])
      prefixRequests = 1
      writeFile("current-ready", $servers.port(true))
    assert servers.poll(), "independent current TLS progress"
    yieldCurrentDiskThread()
  let count = prefixRequests+servers.requestCount(true)
  assert servers.requestCount(false) == 0, "unused identity receives no request"
  servers.close() # Completed application IO/worker shutdown precedes strict independent disk inspection.
  let expectedRequests = if guarantees: total+1 else: total
  assert count == expectedRequests, "exact current and original-context executable request count"
  let adopted = if partial: total-1 else: total
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
