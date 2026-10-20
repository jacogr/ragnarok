# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Join scheduled attempts, bounded raw reception and native close barriers in one stable owner.
## Explicit producer/host acknowledgement remains outside native callbacks and never infers adoption.

import ./[transport, block_download_stream]
import ../app/[download_schedule, block_download, block_input, candidate, services]
import ../codec/[bounded, header]
import ../state/[accumulation_finalization, accumulation_completion]

type
  DownloadSessionError* {.pure.} = enum ## Defaults and failed alternatives contain no usable attempt or execution prefix.
    Uninitialized, None, Busy, StaleAttempt, WrongPeer, AwaitingClose, NotReady, NotQueued,
    AlreadyQueued, ScheduleFailure, DownloadFailure, StreamFailure
  DownloadSessionFailure* = object ## Only the actual selected nested refusal is retained.
    case status: DownloadSessionError
    of ScheduleFailure:
      scheduleReason: DownloadScheduleError
    of DownloadFailure:
      downloadReason: BlockDownloadFailure
    of StreamFailure:
      streamReason: DownloadStreamError
    else:
      discard                      # Plain lifetime/readiness errors carry no unrelated nested payload.
  DownloadSessionAttempt* = ref object ## Immutable token identity remains distinct across retries and session owners.
    selectedPeer: DownloadPeerId
    generation: BlockDownloadId
  DownloadSessionResult*[T] = object ## Successful extraction is guarded independently of Nimony's raw variant representation.
    case successful: bool
    of true:
      completed: T
    else:
      refused: DownloadSessionFailure
  BlockDownloadSession* = object ## Host retains a stable address through callback teardown; nested mutable owners never escape.
    schedule: DownloadSchedule
    download: BlockDownload
    route: BlockDownloadStream
    current: nil DownloadSessionAttempt
    lease: DownloadAttempt
    queued: bool

proc `=copy`*(destination: var BlockDownloadSession, source: BlockDownloadSession) {.
    error: "BlockDownloadSession owns callbacks and scheduled reception".}
  ## Composite ownership must not depend solely on its nested non-copyable fields.
proc `=dup`*(source: BlockDownloadSession): BlockDownloadSession {.error.}
  ## Duplicating this owner would duplicate native callback obligations and scheduler authority.

func error*(reason: DownloadSessionFailure): DownloadSessionError =
  ## Inspect a reason without allowing retagging or nested-payload mutation.
  reason.status
func error*[T](outcome: DownloadSessionResult[T]): DownloadSessionError =
  ## A default result cannot authorize a token, request or finalized successor.
  if outcome.successful: DownloadSessionError.None
  else: outcome.refused.error # Failures retain no successful prefix.
func value*[T](outcome: DownloadSessionResult[T]): T {.inline, requires: outcome.successful.} =
  ## Extract only the selected successful payload.
  outcome.completed
func failure*[T](outcome: DownloadSessionResult[T]): DownloadSessionFailure {.inline,
    requires: not outcome.successful.} =
  ## Successful results have no failure alternative to extract.
  outcome.refused
func scheduleError*(reason: DownloadSessionFailure): DownloadScheduleError {.inline,
    requires: reason.status == DownloadSessionError.ScheduleFailure.} =
  ## Preserve the scheduler's exact refusal rather than flattening waiting/budget/clock outcomes.
  reason.scheduleReason
func downloadFailure*(reason: DownloadSessionFailure): BlockDownloadFailure {.inline,
    requires: reason.status == DownloadSessionError.DownloadFailure.} =
  ## Inspect only a genuine failed admission/reception/preparation child.
  reason.downloadReason
func streamError*(reason: DownloadSessionFailure): DownloadStreamError {.inline,
    requires: reason.status == DownloadSessionError.StreamFailure.} =
  ## Inspect only a native binding refusal.
  reason.streamReason
func peer*(attempt: DownloadSessionAttempt): DownloadPeerId =
  ## Tokens expose the selected authenticated-peer catalog identity, never mutable callback storage.
  attempt.selectedPeer
func stage*(session: BlockDownloadSession): BlockDownloadStage =
  ## Observe raw framing independently of whether its native close has retired.
  session.download.stage
proc streamActive*(session: BlockDownloadSession): bool =
  ## Cancellation retains this barrier until the route's real close callback.
  session.route.active
func busy*(session: BlockDownloadSession): bool =
  ## A queued candidate also retains its lease until explicit host acknowledgement.
  session.current != nil
func receivedBytes*(session: BlockDownloadSession): uint64 =
  ## Native-test/host observations borrow only a scalar, not the internal route.
  session.route.receivedBytes
func matches(session: BlockDownloadSession, attempt: DownloadSessionAttempt): bool =
  ## Exact immutable token identity rejects foreign sessions and previous generations.
  session.current == attempt
func plain(reason: DownloadSessionError): DownloadSessionFailure =
  ## Construct only a payload-free lifecycle result.
  DownloadSessionFailure(status: reason)
func refused[T](reason: DownloadSessionFailure): DownloadSessionResult[T] =
  ## Failed generic results never retain a successful owner.
  DownloadSessionResult[T](successful: false, refused: reason)

proc configure*(session: var BlockDownloadSession, peers: openArray[DownloadPeerId],
    limits: DownloadScheduleLimits, now: DownloadScheduleTick): DownloadScheduleError =
  ## An active request, including post-close queued work, blocks peer/budget replacement.
  if session.busy: return DownloadScheduleError.Busy # Reconfiguration cannot orphan the current attempt.
  session.schedule.configure(peers, limits, now)

proc begin*(session: var BlockDownloadSession, owner: Services,
    ancestors: openArray[OwnedHeader], resources: BlockInputLimits,
    policies: ApplicationCandidateLimits, now: DownloadScheduleTick): DownloadSessionResult[
        DownloadSessionAttempt] =
  ## Reserve and admit once; no native stream is opened by this application-context operation.
  if session.busy: return refused[DownloadSessionAttempt](plain(DownloadSessionError.Busy))
  let chosen = session.schedule.select(now)
  if chosen.error != DownloadScheduleError.None:
    return refused[DownloadSessionAttempt](DownloadSessionFailure(
      status: DownloadSessionError.ScheduleFailure, scheduleReason: chosen.error))
  let admitted = session.download.begin(owner, ancestors, resources, policies)
  if admitted.error != BlockDownloadError.None:
    discard session.schedule.finish(chosen.value, DownloadAttemptOutcome.Retry,
        now) # No native binding exists; exact selection/tick makes retirement infallible.
    return refused[DownloadSessionAttempt](DownloadSessionFailure(
      status: DownloadSessionError.DownloadFailure, downloadReason: admitted.failure))
  let attempt = DownloadSessionAttempt(selectedPeer: chosen.value.peer, generation: admitted.value)
  session.current = attempt
  session.lease = chosen.value
  session.queued = false
  DownloadSessionResult[DownloadSessionAttempt](successful: true, completed: attempt)

proc request*(session: BlockDownloadSession, attempt: DownloadSessionAttempt): DownloadSessionResult[
    array[42, byte]] =
  ## Return only copied fixed request bytes for this exact admitted token.
  if not session.matches(attempt): return refused[array[42, byte]](plain(
      DownloadSessionError.StaleAttempt))
  let copied = session.download.request(attempt.generation)
  if copied.error != BlockDownloadError.None:
    return refused[array[42, byte]](DownloadSessionFailure(
      status: DownloadSessionError.DownloadFailure,
      downloadReason: copied.failure))
  DownloadSessionResult[array[42, byte]](successful: true, completed: copied.value)

proc receptionFailure*(session: BlockDownloadSession,
    attempt: DownloadSessionAttempt): DownloadSessionFailure =
  ## Preserve a selected framing failure through close until terminal acknowledgement.
  if not session.matches(attempt): return plain(DownloadSessionError.StaleAttempt)
  if session.stage != BlockDownloadStage.Failed: return plain(DownloadSessionError.NotReady)
  DownloadSessionFailure(status: DownloadSessionError.DownloadFailure,
    downloadReason: session.download.failure)

proc bindStream*(session: var BlockDownloadSession, attempt: DownloadSessionAttempt,
    peer: DownloadPeerId, handle: NativeStream, limits: DownloadStreamLimits,
    now: DownloadTick): DownloadSessionFailure =
  ## Host binds only the selected peer's locally opened stream; refused late opens remain host-owned.
  if not session.matches(attempt): return plain(DownloadSessionError.StaleAttempt)
  if peer != attempt.peer: return plain(DownloadSessionError.WrongPeer) # Host's authenticated-session mapping must match selection.
  let bound = session.route.bindStream(session.download, attempt.generation, handle, limits, now)
  if bound != DownloadStreamError.None:
    return DownloadSessionFailure(status: DownloadSessionError.StreamFailure, streamReason: bound)
  plain(DownloadSessionError.None)

proc streamEvent*(session: var BlockDownloadSession, attempt: DownloadSessionAttempt,
    peer: DownloadPeerId, handle: NativeStream, event: cint): bool =
  ## Callback work stays bounded by the private route's policy and cannot run preparation/adoption.
  if not session.matches(attempt) or peer != attempt.peer: return false # No native I/O or mutation for stale/wrong-peer events.
  session.route.streamEvent(session.download, attempt.generation, handle, event)

proc expire*(session: var BlockDownloadSession, attempt: DownloadSessionAttempt,
    handle: NativeStream, now: DownloadTick): bool =
  ## A deadline cancels reception but retains the selected lease and native-close barrier.
  if not session.matches(attempt): return false # Another session's token cannot expire this stream.
  session.route.expire(session.download, attempt.generation, handle, now)

proc cancel*(session: var BlockDownloadSession, attempt: DownloadSessionAttempt,
    handle: NativeStream): bool =
  ## Explicit bound-stream cancellation keeps the attempt busy until the native route closes.
  if not session.matches(attempt): return false # Replayed host cancellation cannot retire a replacement.
  session.route.cancel(session.download, attempt.generation, handle)

proc discardInput*(session: var BlockDownloadSession,
    attempt: DownloadSessionAttempt): DownloadSessionFailure =
  ## Explicitly discard unused raw input only after close, or before an unbound open attempt is retired.
  if not session.matches(attempt): return plain(DownloadSessionError.StaleAttempt)
  if session.streamActive: return plain(DownloadSessionError.AwaitingClose)
  if session.queued: return plain(DownloadSessionError.AlreadyQueued) # Queued certificates belong to the Services handoff.
  discard session.download.cancel(attempt.generation)
  plain(DownloadSessionError.None)

proc enqueue*(session: var BlockDownloadSession, attempt: DownloadSessionAttempt,
    owner: var Services, composition: AccumulationCompositionLimits): DownloadSessionResult[
        PreparedFinalAccumulation] =
  ## Preparation occurs explicitly after native teardown; successful enqueue still does not imply adoption.
  if not session.matches(attempt): return refused[PreparedFinalAccumulation](plain(
      DownloadSessionError.StaleAttempt))
  if session.streamActive: return refused[PreparedFinalAccumulation](plain(
      DownloadSessionError.AwaitingClose))
  if session.queued: return refused[PreparedFinalAccumulation](plain(
      DownloadSessionError.AlreadyQueued))
  let prepared = session.download.enqueue(attempt.generation, owner, composition)
  if prepared.error != BlockDownloadError.None:
    return refused[PreparedFinalAccumulation](DownloadSessionFailure(
      status: DownloadSessionError.DownloadFailure, downloadReason: prepared.failure))
  session.queued = true
  DownloadSessionResult[PreparedFinalAccumulation](successful: true, completed: prepared.value)

proc finish*(session: var BlockDownloadSession, attempt: DownloadSessionAttempt,
    outcome: DownloadAttemptOutcome, now: DownloadScheduleTick): DownloadSessionFailure =
  ## Host reports actual terminal adoption/refusal; only the private route can retire the native-close barrier.
  if not session.matches(attempt): return plain(DownloadSessionError.StaleAttempt)
  if session.streamActive: return plain(DownloadSessionError.AwaitingClose)
  if outcome == DownloadAttemptOutcome.Adopted and not session.queued:
    return plain(DownloadSessionError.NotQueued) # Empty/failed/unprepared input cannot claim adoption.
  if session.stage in [BlockDownloadStage.Receiving, BlockDownloadStage.Ready]:
    return plain(DownloadSessionError.NotReady) # Host must explicitly discard unused input after close.
  let completed = session.schedule.finish(session.lease, outcome, now)
  if completed != DownloadScheduleError.None:
    return DownloadSessionFailure(status: DownloadSessionError.ScheduleFailure,
        scheduleReason: completed)
  discard session.download.cancel(attempt.generation) # Failed/Empty input releases only after successful acknowledgement.
  session.current = nil
  session.lease = default(DownloadAttempt)
  session.queued = false
  plain(DownloadSessionError.None)
