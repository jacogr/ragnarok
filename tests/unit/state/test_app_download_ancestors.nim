# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A framed signed child suspends through Services worker collection and resumes without another stream or early publication.
import std/assertions
import std/envvars
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../../src/app/block_input as app_block_input
import ../../../src/app/block_download as app_block_download
import ../../../src/app/candidate as app_candidate
import ../../../src/app/chain as app_chain
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/handoff as app_handoff
import ../../../src/chain/provider as chain_provider
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/header as codec_header
import ../../../src/state/report_anchors as state_report_anchors
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../support/app_candidate_context
import ../../support/state_accumulation_completion_context
import ../../support/state_report_admission_context as report_context

proc waitDone(owner: var Services) =
  ## Keep graph aliases untouched while polling only the synchronized worker phase.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Actual execution runs outside this host activation.
proc main() {.raises.} =
  ## Services owns the only canonical parent; genuine signed report preparation is reused after collection.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var source = newSeq[byte](raw.len)
  for index, octet in raw: source[index] = byte(octet) # Preserve the pinned independent fixture bytes.
  let base = decodeOwnedReport(source, 2).value
  let context = fixture(base, guarantees = 1)
  writeFile("download-ancestor-seed", context.text)
  defer: discard posix.unlink("download-ancestor-seed")
  let blockOwner = candidateBlock(context)
  var wire = newSeq[byte](blockOwner.blockInfo.value.consumed)
  assert encodeOwnedBlock(blockOwner, wire).error == FrameError.None
  assert wire.len < 1000000
  var frame = newSeq[byte](wire.len + 4)
  for index in 0..<4: frame[index] = byte((uint32(wire.len) shr (index * 8)) and
      255) # Literal independent E4 payload extent.
  for index, octet in wire: frame[index + 4] = octet
  let older = report_context.authored(base).older
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "download-ancestor-seed",
    "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "ancestor resumption")
  defer: owner.close() # All worker leases below are collected before Services retirement.
  var download = default(BlockDownload)
  let resources = BlockInputLimits(blockBytes: ByteLimit(wire.len), ancestorBytes: ByteLimit(8192),
    ancestors: ElementLimit(1), discoverAncestors: true)
  let id = download.begin(owner, [], resources, preparationLimits()).value
  assert download.requestFinished(id) == BlockDownloadError.None
  assert download.append(id, frame, true) == BlockDownloadError.None
  assert download.beginPreparation(id, owner).error == BlockDownloadError.None
  waitDone(owner)
  let needed = download.collectPreparation(id, owner, completionLimits().composition)
  assert needed.error == BlockDownloadError.NeedsAncestors
  assert not owner.preparationActive and owner.preparationAvailable
  assert download.stage == BlockDownloadStage.AwaitingAncestors
  assert download.ancestorDemand(id).value.missingLookups.value == 1
  assert owner.chainView.retainedCount == 1
  assert download.resumeAncestors(default(BlockDownloadId), owner, older).error ==
      BlockDownloadError.StaleDownload
  let refused = download.resumeAncestors(id, owner, [older[0], older[0]])
  assert refused.error == BlockDownloadError.InputFailure and refused.failure.inputError ==
      BlockInputError.LimitExceeded
  assert download.stage == BlockDownloadStage.AwaitingAncestors
  assert download.resumeAncestors(id, owner, older).error == BlockDownloadError.None
  assert download.stage == BlockDownloadStage.Ready
  assert download.beginPreparation(id, owner).error == BlockDownloadError.None
  waitDone(owner)
  assert download.collectPreparation(id, owner, completionLimits().composition).error ==
      BlockDownloadError.None
  assert download.stage == BlockDownloadStage.Idle
  assert owner.chainView.retainedCount == 1 and owner.accumulationStage ==
      AccumulationHandoffStage.Pending
  owner.tick(0) # Only this later Services turn may actually publish the prepared successor.
  assert owner.accumulationStage == AccumulationHandoffStage.Finished
  assert owner.takeAccumulation.error == ApplicationChainError.None
  assert owner.chainView.retainedCount == 2
  echo "download-ancestors: ok"
try:
  main() # Fixture IO failure cannot emit the success contract.
except:
  quit(2)
