# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual TLS stream retirement precedes token-bound context discovery and resumed worker execution.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../../src/app/[block_input, block_download, candidate, chain, services, options,
    preparation_worker, handoff, download_schedule]
import ../../../src/app/download_schedule
import ../../../src/quic/block_download_session
import ../../../src/chain/provider
import ../../../src/codec/[bounded, report_owned, block_codec, header]
import ../../../src/state/[report_anchors, accumulation_completion]
import ../../support/[application_candidate_context, accumulation_completion_context]
import ../../support/block_download_transport
import ../../support/report_admission_context as report_context

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
  writeFile("session-ancestor-seed", context.text)
  defer: discard posix.unlink("session-ancestor-seed")
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
  assert parseOptions(@["server", "--with-state", "--chain", "session-ancestor-seed",
    "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "ancestor resumption")
  defer: owner.close() # All worker leases below are collected before Services retirement.
  var session = default(BlockDownloadSession)
  assert session.configure([DownloadPeerId(1)], DownloadScheduleLimits(peers: ElementLimit(1),
    attempts: 2, retryDelay: DownloadRetryDelay(1)), DownloadScheduleTick(0)) ==
        DownloadScheduleError.None
  let resources = BlockInputLimits(blockBytes: ByteLimit(wire.len), ancestorBytes: ByteLimit(8192),
    ancestors: ElementLimit(1), discoverAncestors: true)
  let id = session.begin(owner, [], resources, preparationLimits(), DownloadScheduleTick(0)).value
  let expected = session.request(id).value
  exchangeSession(session, owner, id, expected, frame, Healthy)
  assert not session.streamActive and session.busy
  assert session.beginPreparation(id, owner).error == DownloadSessionError.None
  waitDone(owner)
  let needed = session.collectPreparation(id, owner, completionLimits().composition)
  assert needed.error == DownloadSessionError.DownloadFailure and
      needed.failure.downloadFailure.error == BlockDownloadError.NeedsAncestors
  assert not owner.preparationActive and owner.preparationAvailable
  assert session.stage == BlockDownloadStage.AwaitingAncestors
  assert session.ancestorDemand(id).value.missingLookups.value == 1
  assert owner.chainView.retainedCount == 1
  let foreign = DownloadSessionAttempt()
  assert session.resumeAncestors(foreign, owner, older).error ==
      DownloadSessionError.StaleAttempt
  let refused = session.resumeAncestors(id, owner, [older[0], older[0]])
  assert refused.error == DownloadSessionError.DownloadFailure and
      refused.failure.downloadFailure.inputError ==BlockInputError.LimitExceeded
  assert session.stage == BlockDownloadStage.AwaitingAncestors
  assert session.resumeAncestors(id, owner, older).error == DownloadSessionError.None
  assert session.stage == BlockDownloadStage.Ready
  assert session.beginPreparation(id, owner).error == DownloadSessionError.None
  waitDone(owner)
  assert session.collectPreparation(id, owner, completionLimits().composition).error ==
      DownloadSessionError.None
  assert session.stage == BlockDownloadStage.Idle
  assert owner.chainView.retainedCount == 1 and owner.accumulationStage ==
      AccumulationHandoffStage.Pending
  owner.tick(0) # Only this later Services turn may actually publish the prepared successor.
  assert owner.accumulationStage == AccumulationHandoffStage.Finished
  assert owner.takeAccumulation.error == ApplicationChainError.None
  assert owner.chainView.retainedCount == 2
  assert session.finish(id, DownloadAttemptOutcome.Adopted, DownloadScheduleTick(1)).error ==
      DownloadSessionError.None
  assert session.ancestorDemand(id).error == DownloadSessionError.StaleAttempt
  echo "session-ancestors: ok"
try:
  main() # Fixture IO failure cannot emit the success contract.
except:
  quit(2)
