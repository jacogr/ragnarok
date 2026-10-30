# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_download_session_arc_release"}

## Joined attempt identity and native-close barriers preserve bounded retry and deferred canonical adoption.

import std/[assertions, syncio, envvars]
import std/posix/posix
import "../../../src/jamnp-s/block/download/session" as block_download_session
import "../../../src/jamnp-s/block/download/stream" as block_download_stream
import ../../../src/quic/transport
import "../../../src/app/block/download" as block_download
import ../../../src/app/download/schedule as download_schedule
import "../../../src/app/block/input" as block_input
import ../../../src/app/[candidate, services, options, chain, handoff]
import ../../../src/codec/[bounded, block_codec, report_owned]
import ../../../src/state/store
import ../../../src/state/accumulation/finalization as accumulation_finalization
import ../../support/[application_candidate_context, accumulation_completion_context,
  block_download_transport, arc_evidence]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Make any accidental native-callback preparation fail deterministically.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Reception, barriers and stale-event rejection must perform no hashes.

proc policies(): DownloadScheduleLimits =
  ## Explicit retry ceilings cover the entire real transport matrix.
  DownloadScheduleLimits(peers: ElementLimit(1), attempts: 10, retryDelay: DownloadRetryDelay(1))
proc resources(): BlockInputLimits =
  ## The signed fixture and zero ancestors fit this explicit host policy.
  BlockInputLimits(blockBytes: ByteLimit(100000), ancestors: ElementLimit(0),
      ancestorBytes: ByteLimit(0))
proc begin(session: var BlockDownloadSession, owner: Services,
    now: uint64): DownloadSessionAttempt =
  ## Successful admission exposes an immutable token, not mutable receiver or schedule storage.
  let admitted = session.begin(owner, [], resources(), preparationLimits(), DownloadScheduleTick(now))
  assert admitted.error == DownloadSessionError.None
  admitted.value

proc cycle(owner: Services) =
  ## Scoped token aliases survive retirement; every unbound input is discarded before releasing its lease.
  var session = default(BlockDownloadSession)
  assert session.configure([DownloadPeerId(1)], policies(), DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  let token = session.begin(owner, 0)
  let alias = token
  assert session.finish(alias, DownloadAttemptOutcome.Adopted,
    DownloadScheduleTick(0)).error == DownloadSessionError.NotQueued
  assert session.finish(alias, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(0)).error == DownloadSessionError.NotReady
  assert session.discardInput(alias).error == DownloadSessionError.None
  assert session.finish(alias, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(0)).error == DownloadSessionError.None
  assert token.peer == DownloadPeerId(1)
  assert session.request(token).error == DownloadSessionError.StaleAttempt

proc refusal(owner: Services) =
  ## Missing initialization/head, active reconfiguration and cross-owner tokens preserve exact reasons.
  var session = default(BlockDownloadSession)
  let absent = session.begin(owner, [], resources(), preparationLimits(), DownloadScheduleTick(0))
  assert absent.failure.scheduleError == DownloadScheduleError.Uninitialized
  assert session.configure([DownloadPeerId(1)], policies(), DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  let missing = session.begin(default(Services), [], resources(), preparationLimits(),
      DownloadScheduleTick(0))
  assert missing.failure.downloadFailure.error == BlockDownloadError.MissingHead
  let waiting = session.begin(owner, [], resources(), preparationLimits(), DownloadScheduleTick(0))
  assert waiting.failure.scheduleError == DownloadScheduleError.Waiting
  let token = session.begin(owner, 1)
  assert session.configure([DownloadPeerId(2)], policies(), DownloadScheduleTick(1)) ==
      DownloadScheduleError.Busy
  assert session.begin(owner, [], resources(), preparationLimits(), DownloadScheduleTick(
      1)).error == DownloadSessionError.Busy
  var foreign = default(BlockDownloadSession)
  assert foreign.configure([DownloadPeerId(1)], policies(), DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  let other = foreign.begin(owner, 0)
  let forged = DownloadSessionAttempt()
  assert session.discardInput(forged).error == DownloadSessionError.StaleAttempt
  assert session.receptionFailure(token).error == DownloadSessionError.NotReady
  assert session.discardInput(other).error == DownloadSessionError.StaleAttempt
  assert not session.cancel(other, NativeStream(nil))
  assert not session.expire(other, NativeStream(nil), DownloadTick(100))
  assert not session.streamEvent(other, other.peer, NativeStream(nil), 3)
  let binding = session.bindStream(other, other.peer, NativeStream(nil), default(
      DownloadStreamLimits), DownloadTick(0))
  assert binding.error == DownloadSessionError.StaleAttempt
  assert session.finish(other, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(1)).error == DownloadSessionError.StaleAttempt
  assert session.discardInput(token).error == DownloadSessionError.None
  assert session.finish(token, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(0)).scheduleError == DownloadScheduleError.ClockRegression
  assert session.busy
  assert session.finish(token, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(1)).error == DownloadSessionError.None
  let replacement = session.begin(owner, 2)
  assert session.discardInput(token).error == DownloadSessionError.StaleAttempt
  assert session.discardInput(replacement).error == DownloadSessionError.None
  assert session.finish(replacement, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(2)).error == DownloadSessionError.None
  assert foreign.discardInput(other).error == DownloadSessionError.None
  assert foreign.finish(other, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(0)).error == DownloadSessionError.None

proc refusedBlock(owner: var Services) =
  ## Complete framing can still contain a refused block; preserve that exact failed preparation child after close.
  var session = default(BlockDownloadSession)
  assert session.configure([DownloadPeerId(1)], policies(), DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  let token = session.begin(owner, 0)
  let expected = session.request(token).value
  failHash(1)
  exchangeSession(session, owner, token, expected, @[1'u8, 0, 0, 0, 1], Healthy)
  assert session.stage == BlockDownloadStage.Ready and not session.streamActive
  let refused = session.enqueue(token, owner, completionLimits().composition)
  let reason = refused.failure.downloadFailure
  assert reason.error == BlockDownloadError.PreparationFailure
  assert reason.preparationFailure.error == BlockInputError.DecodeFailure
  assert session.receptionFailure(token).downloadFailure.preparationFailure.error ==
      BlockInputError.DecodeFailure
  assert hashCalls() == 0
  failHash(0)
  assert session.finish(token, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(0)).error == DownloadSessionError.None
  let next = session.begin(owner, 1)
  assert session.discardInput(next).error == DownloadSessionError.None
  assert session.finish(next, DownloadAttemptOutcome.Retry,
    DownloadScheduleTick(1)).error == DownloadSessionError.None

proc network(owner: var Services, frame: seq[byte], context: SeedFixture) =
  ## Callback-only reception precedes explicit preparation; actual adoption is observed on the later service tick.
  var session = default(BlockDownloadSession)
  assert session.configure([DownloadPeerId(1)], policies(), DownloadScheduleTick(0)) ==
      DownloadScheduleError.None
  let original = owner.stateSnapshot.value
  var tick = 0'u64
  for mode in [Oversized, PrematureClose, NoFin, Deadline, ResetEvent, EmptyReply, Healthy]:
    let token = session.begin(owner, tick)
    let expected = session.request(token).value
    failHash(1)
    exchangeSession(session, owner, token, expected, frame, mode)
    assert not session.streamActive and session.busy
    assert hashCalls() == 0 and sameStateSnapshot(original, owner.stateSnapshot.value)
    failHash(0)
    if mode == Healthy:
      let blocker = owner.enqueueCandidate(candidateBlock(context), [], preparationLimits(),
          completionLimits().composition)
      assert blocker.error == ApplicationCandidateError.None
      failHash(1)
      let busy = session.enqueue(token, owner, completionLimits().composition)
      assert busy.failure.downloadFailure.error == BlockDownloadError.Busy
      assert session.stage == BlockDownloadStage.Ready and session.busy and hashCalls() == 0
      failHash(0)
      assert owner.cancelAccumulation()
      let queued = session.enqueue(token, owner, completionLimits().composition)
      assert queued.error == DownloadSessionError.None
      assert sameStateSnapshot(queued.value.finalAccumulationParent.value, original)
      assert owner.accumulationStage == AccumulationHandoffStage.Pending and session.busy
      assert session.enqueue(token, owner, completionLimits().composition).error ==
          DownloadSessionError.AlreadyQueued
      assert session.discardInput(token).error == DownloadSessionError.AlreadyQueued
      assert sameStateSnapshot(original, owner.stateSnapshot.value)
      owner.tick(0)
      assert owner.takeAccumulation.error == ApplicationChainError.None
      assert session.finish(token, DownloadAttemptOutcome.Adopted,
        DownloadScheduleTick(tick)).error == DownloadSessionError.None
      let done = session.begin(owner, [], resources(), preparationLimits(), DownloadScheduleTick(tick))
      assert done.failure.scheduleError == DownloadScheduleError.Completed
    else:
      if mode in [Oversized, PrematureClose]:
        let reason = session.receptionFailure(token)
        let expected = if mode == Oversized: BlockDownloadError.LimitExceeded else: BlockDownloadError.Truncated
        assert reason.downloadFailure.error == expected # Native teardown preserves the original selected framing reason.
      assert session.finish(token, DownloadAttemptOutcome.Adopted,
        DownloadScheduleTick(tick)).error == DownloadSessionError.NotQueued
      let outcome = if mode == EmptyReply: DownloadAttemptOutcome.Empty else: DownloadAttemptOutcome.Retry
      assert session.finish(token, outcome, DownloadScheduleTick(tick)).error ==
          DownloadSessionError.None
      assert session.request(token).error == DownloadSessionError.StaleAttempt
    inc tick # Cooldown is supplied by the host; no callback advances scheduler time.

proc main() {.raises.} =
  ## Use the same pinned signed two-guest seed and real certificate fixture as the established producer suite.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet) # The frozen report is independent of received block bytes.
  let context = fixture(decodeOwnedReport(report, 2).value)
  let blockOwner = candidateBlock(context)
  let body = blockOwner.blockInfo.value.consumed
  var frame = newSeq[byte](body + 4)
  for index in 0..<4: frame[index] = byte((uint64(body) shr (8 * index)) and 255) # Independent E4 body length.
  let source = Block(header: blockOwner.blockHeader.value,
      extrinsic: blockOwner.blockExtrinsic.value)
  assert encodeBlock(source, preparationLimits().reporting.admission.frame,
    frame.toOpenArray(4, frame.high)).error == FrameError.None
  writeFile("application-download-session-chain.json", context.text)
  defer: discard posix.unlink("application-download-session-chain.json")
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain",
    "application-download-session-chain.json",
    "--state-writes", "1000", "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "test")
  defer: owner.close()
  refusal(owner)
  refusedBlock(owner)
  cycle(owner)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(owner) # Stable fixture owners remain outside the repeated allocation interval.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_download_session", 1000, before, after)
  network(owner, frame, context)
  echo "Application download session passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Filesystem/fixture failures cannot masquerade as successful native evidence.
except:
  quit(2)
