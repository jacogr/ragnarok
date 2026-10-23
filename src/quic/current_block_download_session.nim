# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Join scheduled attempts, bounded raw reception and native close barriers in one stable owner.
## Explicit producer/host acknowledgement remains outside native callbacks and never infers adoption.

import ./[transport, current_block_download_stream]
import ../app/[download_schedule, current_block_download, current_block_input, candidate, services,
    preparation_worker, current_logical_download]
import ../codec/[bounded, header]
import ../state/[report_anchors, accumulation_current_update, current_logical]

type
  CurrentDownloadSessionError* {.pure.} = enum ## Defaults and failed alternatives contain no usable attempt or execution prefix.
    Uninitialized, None, Busy, StaleAttempt, WrongPeer, AwaitingClose, NotReady, NotQueued,
    AlreadyQueued, ScheduleFailure, DownloadFailure, StreamFailure
  CurrentDownloadSessionFailure* = object ## Only the actual selected nested refusal is retained.
    case status: CurrentDownloadSessionError
    of ScheduleFailure:
      scheduleReason: DownloadScheduleError
    of DownloadFailure:
      downloadReason: CurrentBlockDownloadFailure
    of StreamFailure:
      streamReason: CurrentDownloadStreamError
    else:
      discard                             # Plain lifetime/readiness errors carry no unrelated nested payload.
  CurrentDownloadSessionAttempt* = ref object ## Immutable token identity remains distinct across retries and session owners.
    selectedPeer: DownloadPeerId
    generation: CurrentBlockDownloadId
  CurrentDownloadSessionResult*[T] = object ## Successful extraction is guarded independently of Nimony's raw variant representation.
    case successful: bool
    of true:
      completed: T
    else:
      refused: CurrentDownloadSessionFailure
  CurrentDownloadSession* = object ## Host retains a stable address through callback teardown; nested mutable owners never escape.
    schedule: DownloadSchedule
    download: CurrentBlockDownload
    route: CurrentDownloadStream
    current: nil CurrentDownloadSessionAttempt
    lease: DownloadAttempt
    queued: bool

proc `=copy`*(destination: var CurrentDownloadSession, source: CurrentDownloadSession) {.
    error: "CurrentDownloadSession owns callbacks and scheduled reception".}
  ## Composite ownership must not depend solely on its nested non-copyable fields.
proc `=dup`*(source: CurrentDownloadSession): CurrentDownloadSession {.error.}
  ## Duplicating this owner would duplicate native callback obligations and scheduler authority.

func error*(reason: CurrentDownloadSessionFailure): CurrentDownloadSessionError =
  ## Inspect a reason without allowing retagging or nested-payload mutation.
  reason.status
func error*[T](outcome: CurrentDownloadSessionResult[T]): CurrentDownloadSessionError =
  ## A default result cannot authorize a token, request or finalized successor.
  if outcome.successful: CurrentDownloadSessionError.None
  else: outcome.refused.error # Failures retain no successful prefix.
func value*[T](outcome: CurrentDownloadSessionResult[T]): T {.inline,
    requires: outcome.successful.} =
  ## Extract only the selected successful payload.
  outcome.completed
func failure*[T](outcome: CurrentDownloadSessionResult[T]): CurrentDownloadSessionFailure {.inline,
    requires: not outcome.successful.} =
  ## Successful results have no failure alternative to extract.
  outcome.refused
func scheduleError*(reason: CurrentDownloadSessionFailure): DownloadScheduleError {.inline,
    requires: reason.status == CurrentDownloadSessionError.ScheduleFailure.} =
  ## Preserve the scheduler's exact refusal rather than flattening waiting/budget/clock outcomes.
  reason.scheduleReason
func downloadFailure*(reason: CurrentDownloadSessionFailure): CurrentBlockDownloadFailure {.inline,
    requires: reason.status == CurrentDownloadSessionError.DownloadFailure.} =
  ## Inspect only a genuine failed admission/reception/preparation child.
  reason.downloadReason
func streamError*(reason: CurrentDownloadSessionFailure): CurrentDownloadStreamError {.inline,
    requires: reason.status == CurrentDownloadSessionError.StreamFailure.} =
  ## Inspect only a native binding refusal.
  reason.streamReason
func peer*(attempt: CurrentDownloadSessionAttempt): DownloadPeerId =
  ## Tokens expose the selected authenticated-peer catalog identity, never mutable callback storage.
  attempt.selectedPeer
func stage*(session: CurrentDownloadSession): CurrentBlockDownloadStage =
  ## Observe raw framing independently of whether its native close has retired.
  session.download.stage
proc streamActive*(session: CurrentDownloadSession): bool =
  ## Cancellation retains this barrier until the route's real close callback.
  session.route.active
func busy*(session: CurrentDownloadSession): bool =
  ## A queued candidate also retains its lease until explicit host acknowledgement.
  session.current != nil
func receivedBytes*(session: CurrentDownloadSession): uint64 =
  ## Native-test/host observations borrow only a scalar, not the internal route.
  session.route.receivedBytes
func matches(session: CurrentDownloadSession, attempt: CurrentDownloadSessionAttempt): bool =
  ## Exact immutable token identity rejects foreign sessions and previous generations.
  session.current == attempt
func plain(reason: CurrentDownloadSessionError): CurrentDownloadSessionFailure =
  ## Construct only a payload-free lifecycle result.
  CurrentDownloadSessionFailure(status: reason)
func refused[T](reason: CurrentDownloadSessionFailure): CurrentDownloadSessionResult[T] =
  ## Failed generic results never retain a successful owner.
  CurrentDownloadSessionResult[T](successful: false, refused: reason)

proc configure*(session: var CurrentDownloadSession, peers: openArray[DownloadPeerId],
    limits: DownloadScheduleLimits, now: DownloadScheduleTick): DownloadScheduleError =
  ## An active request, including post-close queued work, blocks peer/budget replacement.
  if session.busy: return DownloadScheduleError.Busy # Reconfiguration cannot orphan the current attempt.
  session.schedule.configure(peers, limits, now)

proc beginSession(session: var CurrentDownloadSession, owner: Services,
    ancestors: openArray[OwnedHeader], resources: CurrentBlockInputLimits,
    policies: CurrentCandidateLimits, now: DownloadScheduleTick, qualifyLogical: bool,
    logical: CurrentLogicalDownloadPolicy): CurrentDownloadSessionResult[
        CurrentDownloadSessionAttempt] =
  ## Reserve and admit once; no native stream is opened by this application-context operation.
  if session.busy: return refused[CurrentDownloadSessionAttempt](plain(
      CurrentDownloadSessionError.Busy))
  let chosen = session.schedule.select(now)
  if chosen.error != DownloadScheduleError.None:
    return refused[CurrentDownloadSessionAttempt](CurrentDownloadSessionFailure(
      status: CurrentDownloadSessionError.ScheduleFailure, scheduleReason: chosen.error))
  let admitted = if qualifyLogical:
      session.download.begin(owner, ancestors, resources, policies, logical)
    else: session.download.begin(owner, ancestors, resources,
        policies) # Raw callers preserve their explicit original admission path.
  if admitted.error != CurrentBlockDownloadError.None:
    discard session.schedule.finish(chosen.value, DownloadAttemptOutcome.Retry,
        now) # No native binding exists; exact selection/tick makes retirement infallible.
    return refused[CurrentDownloadSessionAttempt](CurrentDownloadSessionFailure(
      status: CurrentDownloadSessionError.DownloadFailure, downloadReason: admitted.failure))
  let attempt = CurrentDownloadSessionAttempt(selectedPeer: chosen.value.peer,
      generation: admitted.value)
  session.current = attempt
  session.lease = chosen.value
  session.queued = false
  CurrentDownloadSessionResult[CurrentDownloadSessionAttempt](successful: true, completed: attempt)

proc begin*(session: var CurrentDownloadSession, owner: Services,
    ancestors: openArray[OwnedHeader], resources: CurrentBlockInputLimits,
    policies: CurrentCandidateLimits, now: DownloadScheduleTick): CurrentDownloadSessionResult[
        CurrentDownloadSessionAttempt] =
  ## Raw sessions retain the existing scheduler/native-close and deferred-adoption contract.
  session.beginSession(owner, ancestors, resources, policies, now, false, default(CurrentLogicalDownloadPolicy))
proc begin*(session: var CurrentDownloadSession, owner: Services,
    ancestors: openArray[OwnedHeader], resources: CurrentBlockInputLimits,
    policies: CurrentCandidateLimits, now: DownloadScheduleTick,
    logical: CurrentLogicalDownloadPolicy): CurrentDownloadSessionResult[
        CurrentDownloadSessionAttempt] =
  ## Retain the explicit logical source and frozen budgets before any stream or worker can borrow the receiver.
  session.beginSession(owner, ancestors, resources, policies, now, true, logical)
proc logicalCompletion*(session: CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt): CurrentDownloadSessionResult[CurrentLogicalState] =
  ## Exact queued attempt and retired native/worker leases precede logical result extraction; this is still not an adoption receipt.
  if not session.matches(attempt): return refused[CurrentLogicalState](plain(
      CurrentDownloadSessionError.StaleAttempt))
  if session.streamActive: return refused[CurrentLogicalState](plain(
      CurrentDownloadSessionError.AwaitingClose))
  if not session.queued or session.stage != CurrentBlockDownloadStage.Idle:
    return refused[CurrentLogicalState](plain(CurrentDownloadSessionError.NotReady)) # Running, failed and unprepared attempts cannot expose a successful prefix.
  let logical = session.download.logicalCompletion
  if logical.error != CurrentLogicalDownloadError.None:
    return refused[CurrentLogicalState](plain(CurrentDownloadSessionError.NotReady)) # A raw queued certificate does not imply complete logical qualification.
  CurrentDownloadSessionResult[CurrentLogicalState](successful: true, completed: logical.value)

proc request*(session: CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt): CurrentDownloadSessionResult[array[42, byte]] =
  ## Return only copied fixed request bytes for this exact admitted token.
  if not session.matches(attempt): return refused[array[42, byte]](plain(
      CurrentDownloadSessionError.StaleAttempt))
  let copied = session.download.request(attempt.generation)
  if copied.error != CurrentBlockDownloadError.None:
    return refused[array[42, byte]](CurrentDownloadSessionFailure(
      status: CurrentDownloadSessionError.DownloadFailure,
      downloadReason: copied.failure))
  CurrentDownloadSessionResult[array[42, byte]](successful: true, completed: copied.value)

proc receptionFailure*(session: CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt): CurrentDownloadSessionFailure =
  ## Preserve a selected framing failure through close until terminal acknowledgement.
  if not session.matches(attempt): return plain(CurrentDownloadSessionError.StaleAttempt)
  if session.stage != CurrentBlockDownloadStage.Failed: return plain(
      CurrentDownloadSessionError.NotReady)
  CurrentDownloadSessionFailure(status: CurrentDownloadSessionError.DownloadFailure,
    downloadReason: session.download.failure)

proc bindStream*(session: var CurrentDownloadSession, attempt: CurrentDownloadSessionAttempt,
    peer: DownloadPeerId, handle: NativeStream, limits: CurrentDownloadStreamLimits,
    now: CurrentDownloadTick): CurrentDownloadSessionFailure =
  ## Host binds only the selected peer's locally opened stream; refused late opens remain host-owned.
  if not session.matches(attempt): return plain(CurrentDownloadSessionError.StaleAttempt)
  if peer != attempt.peer: return plain(CurrentDownloadSessionError.WrongPeer) # Host's authenticated-session mapping must match selection.
  let bound = session.route.bindStream(session.download, attempt.generation, handle, limits, now)
  if bound != CurrentDownloadStreamError.None:
    return CurrentDownloadSessionFailure(status: CurrentDownloadSessionError.StreamFailure,
        streamReason: bound)
  plain(CurrentDownloadSessionError.None)

proc streamEvent*(session: var CurrentDownloadSession, attempt: CurrentDownloadSessionAttempt,
    peer: DownloadPeerId, handle: NativeStream, event: cint): bool =
  ## Callback work stays bounded by the private route's policy and cannot run preparation/adoption.
  if not session.matches(attempt) or peer != attempt.peer: return false # No native I/O or mutation for stale/wrong-peer events.
  session.route.streamEvent(session.download, attempt.generation, handle, event)

proc expire*(session: var CurrentDownloadSession, attempt: CurrentDownloadSessionAttempt,
    handle: NativeStream, now: CurrentDownloadTick): bool =
  ## A deadline cancels reception but retains the selected lease and native-close barrier.
  if not session.matches(attempt): return false # Another session's token cannot expire this stream.
  session.route.expire(session.download, attempt.generation, handle, now)

proc cancel*(session: var CurrentDownloadSession, attempt: CurrentDownloadSessionAttempt,
    handle: NativeStream): bool =
  ## Explicit bound-stream cancellation keeps the attempt busy until the native route closes.
  if not session.matches(attempt): return false # Replayed host cancellation cannot retire a replacement.
  session.route.cancel(session.download, attempt.generation, handle)

proc discardInput*(session: var CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt): CurrentDownloadSessionFailure =
  ## Explicitly discard unused raw input only after close, or before an unbound open attempt is retired.
  if not session.matches(attempt): return plain(CurrentDownloadSessionError.StaleAttempt)
  if session.streamActive: return plain(CurrentDownloadSessionError.AwaitingClose)
  if session.stage == CurrentBlockDownloadStage.Preparing: return plain(
      CurrentDownloadSessionError.Busy) # Worker access retains all raw/context owners.
  if session.queued: return plain(CurrentDownloadSessionError.AlreadyQueued) # Queued certificates belong to the Services handoff.
  discard session.download.cancel(attempt.generation)
  plain(CurrentDownloadSessionError.None)

proc finish*(session: var CurrentDownloadSession, attempt: CurrentDownloadSessionAttempt,
    outcome: DownloadAttemptOutcome, now: DownloadScheduleTick): CurrentDownloadSessionFailure =
  ## Host reports actual terminal adoption/refusal; only the private route can retire the native-close barrier.
  if not session.matches(attempt): return plain(CurrentDownloadSessionError.StaleAttempt)
  if session.streamActive: return plain(CurrentDownloadSessionError.AwaitingClose)
  if outcome == DownloadAttemptOutcome.Adopted and not session.queued:
    return plain(CurrentDownloadSessionError.NotQueued) # Empty/failed/unprepared input cannot claim adoption.
  if session.stage in [CurrentBlockDownloadStage.Receiving, CurrentBlockDownloadStage.Ready,
      CurrentBlockDownloadStage.Preparing]:
    return plain(CurrentDownloadSessionError.NotReady) # Host must explicitly discard unused input after close.
  let completed = session.schedule.finish(session.lease, outcome, now)
  if completed != DownloadScheduleError.None:
    return CurrentDownloadSessionFailure(status: CurrentDownloadSessionError.ScheduleFailure,
        scheduleReason: completed)
  discard session.download.cancel(attempt.generation) # Failed/Empty input releases only after successful acknowledgement.
  session.current = nil
  session.lease = default(DownloadAttempt)
  session.queued = false
  plain(CurrentDownloadSessionError.None)

proc beginPreparation*(session: var CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt, owner: var Services): CurrentDownloadSessionResult[
        PreparationTicket] =
  ## Native close and producer backpressure must precede lending the private raw receiver to execution.
  if not session.matches(attempt): return refused[PreparationTicket](plain(
      CurrentDownloadSessionError.StaleAttempt))
  if session.streamActive: return refused[PreparationTicket](plain(
      CurrentDownloadSessionError.AwaitingClose))
  if session.queued: return refused[PreparationTicket](plain(
      CurrentDownloadSessionError.AlreadyQueued))
  let admitted = session.download.beginPreparation(attempt.generation, owner)
  if admitted.error != CurrentBlockDownloadError.None:
    return refused[PreparationTicket](CurrentDownloadSessionFailure(
        status: CurrentDownloadSessionError.DownloadFailure, downloadReason: admitted.failure))
  CurrentDownloadSessionResult[PreparationTicket](successful: true, completed: admitted.value)

proc cancelPreparation*(session: var CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt, owner: var Services): bool =
  ## Keep the exact scheduler generation and all input aliases until execution actually retires.
  if not session.matches(attempt): return false
  session.download.cancelPreparation(attempt.generation, owner)

proc collectPreparation*(session: var CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt, owner: var Services): CurrentDownloadSessionResult[
        PreparedCurrentChainUpdate] =
  ## Successful collection queues real finalized success; actual adoption still requires a later host result.
  if not session.matches(attempt): return refused[PreparedCurrentChainUpdate](plain(
      CurrentDownloadSessionError.StaleAttempt))
  let completed = session.download.collectPreparation(attempt.generation, owner)
  if completed.error != CurrentBlockDownloadError.None:
    return refused[PreparedCurrentChainUpdate](CurrentDownloadSessionFailure(
        status: CurrentDownloadSessionError.DownloadFailure, downloadReason: completed.failure))
  session.queued = true
  CurrentDownloadSessionResult[PreparedCurrentChainUpdate](successful: true,
      completed: completed.value)

proc retirePreparation*(session: var CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt, owner: var Services): bool =
  ## Joined shutdown ends the worker borrow before the session receiver or captured history can be destroyed.
  if not session.matches(attempt): return false
  session.download.retirePreparation(attempt.generation, owner)

proc ancestorDemand*(session: CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt): CurrentDownloadSessionResult[ReportLookupDemand] =
  ## Only the original attempt after actual stream retirement can expose certified missing context.
  if not session.matches(attempt): return refused[ReportLookupDemand](plain(
      CurrentDownloadSessionError.StaleAttempt))
  if session.queued: return refused[ReportLookupDemand](plain(
      CurrentDownloadSessionError.AlreadyQueued))
  if session.streamActive: return refused[ReportLookupDemand](plain(
      CurrentDownloadSessionError.AwaitingClose))
  let demand = session.download.ancestorDemand(attempt.generation)
  if demand.error != CurrentBlockDownloadError.None:
    return refused[ReportLookupDemand](CurrentDownloadSessionFailure(
      status: CurrentDownloadSessionError.DownloadFailure,
      downloadReason: demand.failure))
  CurrentDownloadSessionResult[ReportLookupDemand](successful: true, completed: demand.value)

proc resumeAncestors*(session: var CurrentDownloadSession,
    attempt: CurrentDownloadSessionAttempt, owner: Services, ancestors: openArray[
        OwnedHeader]): CurrentDownloadSessionResult[CurrentDownloadSessionAttempt] =
  ## Preserve the reserved scheduler attempt and same input generation while rearming only a retired prepared block.
  if not session.matches(attempt): return refused[CurrentDownloadSessionAttempt](plain(
      CurrentDownloadSessionError.StaleAttempt))
  if session.queued: return refused[CurrentDownloadSessionAttempt](plain(
      CurrentDownloadSessionError.AlreadyQueued))
  if session.streamActive: return refused[CurrentDownloadSessionAttempt](plain(
      CurrentDownloadSessionError.AwaitingClose))
  let resumed = session.download.resumeAncestors(attempt.generation, owner, ancestors)
  if resumed.error != CurrentBlockDownloadError.None:
    return refused[CurrentDownloadSessionAttempt](CurrentDownloadSessionFailure(
      status: CurrentDownloadSessionError.DownloadFailure,
      downloadReason: resumed.failure))
  CurrentDownloadSessionResult[CurrentDownloadSessionAttempt](successful: true, completed: attempt)
