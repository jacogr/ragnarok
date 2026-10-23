# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One-child dispatcher drives native I/O, private preparation and actual deferred adoption separately.
## Keep this owner and its exclusively borrowed Services stable until explicit close retires callbacks.

import ./[current_block_download_peers, current_block_download_session, current_block_download_stream]
import ../app/[services, handoff, current_handoff, chain, candidate, current_block_input,
    current_block_download, download_schedule, preparation_worker]
import ../codec/[bounded, header]
import ../chain/genesis
import ../state/[accumulation_current_update, store, report_anchors]

type
  CurrentDownloadLoopTick* = distinct uint64 ## Monotonic host milliseconds shared by all dispatcher deadlines.
  CurrentDownloadAttemptTimeout* = distinct uint64 ## Total attempt duration includes handshake, native open and execution; cancellation waits for actual retirement.
  CurrentDownloadLoopLimits* = object ## Caller supplies every execution, reception, retry and adoption policy independently.
    schedule*: DownloadScheduleLimits
    input*: CurrentBlockInputLimits
    candidate*: CurrentCandidateLimits
    stream*: CurrentDownloadStreamLimits
    attemptTimeout*: CurrentDownloadAttemptTimeout
  CurrentDownloadLoopStage* {.pure.} = enum ## Adoption is terminal only after taking a successful canonical handoff result.
    Uninitialized, Waiting, Receiving, Preparing, Cancelling, Queued, Adopted, Exhausted, Failed,
      Closed, DrainingAncestors, AwaitingAncestors
  CurrentDownloadLoopError* {.pure.} = enum ## Ordinary wait/retry/budget completion are stages, while refusals preserve ownership.
    None, Uninitialized, Busy, InvalidPolicy, MissingState, ServicesBusy, ClockRegression,
    SessionFailure, LostHandoff, LostPreparation, Closed, AttemptExpired
  CurrentDownloadLoop* = object ## Fixed-address composite owns native callback targets and one scheduler/session lease.
    catalog: CurrentDownloadPeers
    session: CurrentDownloadSession
    owner: nil ptr Services
    peers: seq[DownloadPeerId]
    ancestors: seq[OwnedHeader]
    limits: CurrentDownloadLoopLimits
    current: nil CurrentDownloadSessionAttempt
    status: CurrentDownloadLoopStage
    lastTick, started: uint64
    requested, hasCompletion: bool
    completion: CurrentHandoffResult
    refusal: CurrentDownloadSessionFailure

proc `=copy`*(destination: var CurrentDownloadLoop, source: CurrentDownloadLoop) {.
    error: "CurrentDownloadLoop owns stable native callbacks and exclusive adoption".}
  ## Copying the aggregate would duplicate callback addresses and result-consumption authority.
proc `=dup`*(source: CurrentDownloadLoop): CurrentDownloadLoop {.error.}
  ## Explicitly forbid composite duplication independently of nested owner hooks.
proc requireClosed(dispatcher: CurrentDownloadLoop) {.requires:
    dispatcher.status in [CurrentDownloadLoopStage.Uninitialized,
        CurrentDownloadLoopStage.Closed].} =
  ## Even an endpoint-free configured dispatcher must release its Services borrow explicitly.
  discard
proc `=destroy`*(dispatcher: CurrentDownloadLoop) =
  ## Destruction checks retirement rather than invoking callbacks through possibly expired borrows.
  requireClosed(dispatcher)
  `=destroy`(dispatcher.catalog)
  `=destroy`(dispatcher.session)
  `=destroy`(dispatcher.peers)
  `=destroy`(dispatcher.ancestors)
  `=destroy`(dispatcher.limits)
  `=destroy`(dispatcher.current)
  `=destroy`(dispatcher.completion)
  `=destroy`(dispatcher.refusal)

func stage*(dispatcher: CurrentDownloadLoop): CurrentDownloadLoopStage =
  ## Inspect progress without exposing native owners or mutable session state.
  dispatcher.status
func sessionFailure*(dispatcher: CurrentDownloadLoop): CurrentDownloadSessionFailure {.requires:
    dispatcher.status notin [CurrentDownloadLoopStage.Preparing,
        CurrentDownloadLoopStage.Cancelling].} =
  ## Retain the latest selected admission/reception/preparation refusal for diagnostics, including retries.
  dispatcher.refusal
func completed*(dispatcher: CurrentDownloadLoop): bool =
  ## A retained adoption refusal also counts as an observed result, never as successful adoption.
  dispatcher.hasCompletion
func adoption*(dispatcher: CurrentDownloadLoop): CurrentHandoffResult {.
    requires: dispatcher.hasCompletion and dispatcher.status notin [
        CurrentDownloadLoopStage.Preparing, CurrentDownloadLoopStage.Cancelling].} =
  ## Copy only a real consumed Services result; its own success/failure guards remain authoritative.
  dispatcher.completion
proc readyPeers*(dispatcher: CurrentDownloadLoop): seq[DownloadPeerId] =
  ## Return copied authenticated identities without granting native callback access.
  dispatcher.catalog.readyPeers

proc configure*(dispatcher: var CurrentDownloadLoop, owner: var Services,
    peers: openArray[DownloadPeerId], ancestors: openArray[OwnedHeader],
    limits: CurrentDownloadLoopLimits, now: CurrentDownloadLoopTick): CurrentDownloadLoopError =
  ## Validate bounded retained configuration before borrowing stable Services; no endpoint opens here.
  if dispatcher.status != CurrentDownloadLoopStage.Uninitialized: return CurrentDownloadLoopError.Busy
  if uint64(limits.schedule.peers) == 0 or uint64(limits.schedule.peers) > 16 or
      uint64(limits.attemptTimeout) == 0 or uint64(limits.stream.readBytes) == 0 or
      uint64(limits.stream.readBytes) > 4096 or uint64(limits.stream.writeBytes) == 0 or
      uint64(limits.stream.writeBytes) > 42 or uint64(limits.stream.timeout) == 0 or
      uint64(limits.input.blockBytes) == 0 or
      uint64(ancestors.len) > uint64(limits.input.ancestors):
    return CurrentDownloadLoopError.InvalidPolicy # Prove catalog, callback and retained ancestor counts before allocation.
  var remaining = uint64(limits.input.ancestorBytes)
  for ancestor in ancestors:
    let info = ancestor.headerInfo
    if info.error != HeaderError.None or uint64(info.value.consumed) > remaining:
      return CurrentDownloadLoopError.InvalidPolicy # Guard extraction and subtraction before copying any history context.
    remaining -= uint64(info.value.consumed)
  if owner.preparationActive or owner.stateProofActive or
      owner.diskPublicationActive: return CurrentDownloadLoopError.ServicesBusy # No canonical alias may escape another worker lease.
  if owner.stateSnapshot.error != StateStoreError.None: return CurrentDownloadLoopError.MissingState
  if not owner.preparationAvailable or owner.currentAccumulationPhase !=
      CurrentHandoffPhase.Idle: return CurrentDownloadLoopError.ServicesBusy
  if dispatcher.session.configure(peers, limits.schedule, DownloadScheduleTick(uint64(now))) !=
      DownloadScheduleError.None: return CurrentDownloadLoopError.InvalidPolicy
  discard dispatcher.catalog.configure(limits.schedule.peers) # Matching positive <=16 policy was checked above.
  dispatcher.peers = @[]
  for peer in peers: dispatcher.peers.add(peer) # Scheduler preflight has already bounded/validated the complete peer set.
  dispatcher.ancestors = @[]
  for ancestor in ancestors: dispatcher.ancestors.add(
      ancestor) # Immutable owned headers retain only the bounded context.
  dispatcher.limits = limits
  dispatcher.owner = addr owner
  dispatcher.lastTick = uint64(now)
  dispatcher.status = CurrentDownloadLoopStage.Waiting
  CurrentDownloadLoopError.None

proc nextChild*(dispatcher: var CurrentDownloadLoop, ancestors: openArray[OwnedHeader],
    now: CurrentDownloadLoopTick): CurrentDownloadLoopError =
  ## Rearm only after an actual consumed adoption and retired stream/worker lease; retain stable authenticated endpoints.
  if dispatcher.status != CurrentDownloadLoopStage.Adopted or not dispatcher.hasCompletion or
      dispatcher.completion.error != CurrentHandoffError.None or dispatcher.current != nil:
    return CurrentDownloadLoopError.Busy # Waiting, failed or fabricated producer status cannot create another import turn.
  if uint64(now) < dispatcher.lastTick: return CurrentDownloadLoopError.ClockRegression
  let borrowed = dispatcher.owner
  if borrowed == nil: return CurrentDownloadLoopError.Uninitialized
  let owner: ptr Services = borrowed
  if owner[].preparationActive or owner[].stateProofActive or owner[].diskPublicationActive:
    return CurrentDownloadLoopError.ServicesBusy # Observe scalar exclusion before any canonical access.
  if not owner[].preparationAvailable: return CurrentDownloadLoopError.ServicesBusy
  if dispatcher.catalog.busy or dispatcher.session.busy or dispatcher.session.streamActive:
    return CurrentDownloadLoopError.ServicesBusy # No old native callback/input may survive rearming.
  if uint64(ancestors.len) > uint64(dispatcher.limits.input.ancestors): return CurrentDownloadLoopError.InvalidPolicy
  var remaining = uint64(dispatcher.limits.input.ancestorBytes)
  for ancestor in ancestors:
    let info = ancestor.headerInfo
    if info.error != HeaderError.None or uint64(info.value.consumed) > remaining:
      return CurrentDownloadLoopError.InvalidPolicy # Refuse the whole replacement before retiring the prior result/ancestry.
    remaining -= uint64(info.value.consumed)
  var retained = newSeq[OwnedHeader](ancestors.len)
  for index, ancestor in ancestors: retained[index] = ancestor # Copy only bounded immutable header handles while the worker is idle.
  if dispatcher.session.configure(dispatcher.peers, dispatcher.limits.schedule,
      DownloadScheduleTick(uint64(now))) != DownloadScheduleError.None:
    return CurrentDownloadLoopError.InvalidPolicy # Keep all native endpoints and the consumed adoption diagnostic on refusal.
  dispatcher.ancestors = retained
  dispatcher.completion = default(CurrentHandoffResult)
  dispatcher.refusal = default(CurrentDownloadSessionFailure)
  dispatcher.hasCompletion = false
  dispatcher.requested = false
  dispatcher.lastTick = uint64(now)
  dispatcher.status = CurrentDownloadLoopStage.Waiting # The next tick may select one new attempt; rearming performs no IO or execution.
  CurrentDownloadLoopError.None

proc openPeer*(dispatcher: var CurrentDownloadLoop; id: DownloadPeerId;
    expected: CurrentDownloadPeerKey; port: uint16;
    certificate, key, alpn: string): CurrentDownloadPeerError =
  ## Startup explicitly maps only scheduled identities to endpoints, without changing budgets or peer weight.
  if dispatcher.status != CurrentDownloadLoopStage.Waiting or dispatcher.current != nil:
    return CurrentDownloadPeerError.Busy # Register all endpoints before starting attempts; no moving live callback owners.
  var known = false
  for peer in dispatcher.peers:
    if peer == id: known = true # At most sixteen checked identities are scanned.
  if not known: return CurrentDownloadPeerError.InvalidPeer
  dispatcher.catalog.openPeer(id, expected, port, certificate, key, alpn)

proc finish(dispatcher: var CurrentDownloadLoop, outcome: DownloadAttemptOutcome,
    now: CurrentDownloadLoopTick): CurrentDownloadLoopError =
  ## Retire only after the caller has observed native close and settled/discarded application input.
  let token = dispatcher.current
  if token == nil: return CurrentDownloadLoopError.SessionFailure
  let ended = dispatcher.session.finish(token, outcome, DownloadScheduleTick(uint64(now)))
  if ended.error != CurrentDownloadSessionError.None:
    dispatcher.refusal = ended
    dispatcher.status = CurrentDownloadLoopStage.Failed
    return CurrentDownloadLoopError.SessionFailure # Preserve an invariant failure rather than selecting another lease.
  dispatcher.current = nil
  dispatcher.requested = false
  dispatcher.status = if outcome == DownloadAttemptOutcome.Adopted: CurrentDownloadLoopStage.Adopted
    else: CurrentDownloadLoopStage.Waiting # A retry selects at most one new lease on a later host tick.
  CurrentDownloadLoopError.None

proc retry(dispatcher: var CurrentDownloadLoop, now: CurrentDownloadLoopTick): CurrentDownloadLoopError =
  ## Retire pending/bound opens before discarding input, so late callbacks cannot attach to a replacement.
  let token = dispatcher.current
  if token == nil: return CurrentDownloadLoopError.SessionFailure
  discard dispatcher.catalog.retire(token.peer)
  let discarded = dispatcher.session.discardInput(token)
  if discarded.error != CurrentDownloadSessionError.None:
    dispatcher.refusal = discarded
    dispatcher.status = CurrentDownloadLoopStage.Failed
    return CurrentDownloadLoopError.SessionFailure # Keep the lease for explicit close on unexpected retirement failure.
  dispatcher.finish(DownloadAttemptOutcome.Retry, now)

proc tick*(dispatcher: var CurrentDownloadLoop, now: CurrentDownloadLoopTick): CurrentDownloadLoopError =
  ## One turn polls bounded endpoints, submits/collects at most one job and adopts only an earlier queued candidate.
  if dispatcher.status == CurrentDownloadLoopStage.Uninitialized: return CurrentDownloadLoopError.Uninitialized
  if dispatcher.status == CurrentDownloadLoopStage.Closed: return CurrentDownloadLoopError.Closed
  if uint64(now) < dispatcher.lastTick: return CurrentDownloadLoopError.ClockRegression
  let borrowed = dispatcher.owner
  if borrowed == nil: return CurrentDownloadLoopError.Uninitialized
  let owner: ptr Services = borrowed
  if owner[].stateProofActive or (dispatcher.status == CurrentDownloadLoopStage.Queued and
      owner[].diskPublicationActive):
    dispatcher.lastTick = uint64(now)
    owner[].tick(uint32(dispatcher.catalog.readyPeers.len))
    return CurrentDownloadLoopError.None # Owned publication/maintenance and proof leases end before foreign-handoff checks or callback/input alias access.
  if owner[].accumulationStage != AccumulationHandoffStage.Idle:
    return CurrentDownloadLoopError.ServicesBusy # Current scheduling never consumes a legacy producer's handoff.
  if dispatcher.status in [CurrentDownloadLoopStage.Preparing,
      CurrentDownloadLoopStage.Cancelling] and not owner[].preparationActive:
    dispatcher.status = CurrentDownloadLoopStage.Failed
    return CurrentDownloadLoopError.LostPreparation # External take/stop cannot substitute for this producer's completion.
  if dispatcher.status notin [CurrentDownloadLoopStage.Preparing,
      CurrentDownloadLoopStage.Cancelling] and owner[].preparationActive:
    return CurrentDownloadLoopError.ServicesBusy # Never mutate aliases owned by an unexpected external producer.
  if dispatcher.status != CurrentDownloadLoopStage.Queued and owner[].currentAccumulationPhase !=
      CurrentHandoffPhase.Idle:
    return CurrentDownloadLoopError.ServicesBusy # Never process/consume another producer's pending or finished handoff.
  if dispatcher.status == CurrentDownloadLoopStage.Queued and owner[].currentAccumulationPhase ==
      CurrentHandoffPhase.Idle:
    dispatcher.status = CurrentDownloadLoopStage.Failed
    return CurrentDownloadLoopError.LostHandoff # An external take/cancel violates exclusive borrowed ownership; never infer success.
  dispatcher.lastTick = uint64(now)
  owner[].tick(uint32(dispatcher.catalog.readyPeers.len)) # At most sixteen authenticated endpoints; no narrowing overflow.
  if owner[].stateProofActive: return CurrentDownloadLoopError.None # RPC dispatch may have granted a new native proof lease in this turn.
  if dispatcher.status == CurrentDownloadLoopStage.Queued:
    if owner[].currentAccumulationPhase != CurrentHandoffPhase.Finished:
      return CurrentDownloadLoopError.None # Durable publication may span multiple nonblocking service ticks.
    dispatcher.completion = owner[].takeCurrentAccumulation()
    dispatcher.hasCompletion = true
    let outcome = if dispatcher.completion.error == CurrentHandoffError.None:
        DownloadAttemptOutcome.Adopted else: DownloadAttemptOutcome.Retry
    return dispatcher.finish(outcome, now) # Actual refusal keeps the bounded retry plan alive.
  if dispatcher.status in [CurrentDownloadLoopStage.DrainingAncestors,
      CurrentDownloadLoopStage.AwaitingAncestors]:
    if uint64(now) - dispatcher.started >= uint64(dispatcher.limits.attemptTimeout):
      dispatcher.status = CurrentDownloadLoopStage.Failed
      return CurrentDownloadLoopError.AttemptExpired # Acquisition cannot reset the original child attempt's total deadline.
    if dispatcher.status == CurrentDownloadLoopStage.DrainingAncestors:
      if dispatcher.catalog.disconnectPeers() != CurrentDownloadPeerError.None:
        dispatcher.status = CurrentDownloadLoopStage.Failed
        return CurrentDownloadLoopError.SessionFailure # No new endpoint may race a still-borrowed native stream.
      if dispatcher.catalog.count == 0:
        dispatcher.status = CurrentDownloadLoopStage.AwaitingAncestors # Actual connection close precedes exposing the host acquisition turn.
    return CurrentDownloadLoopError.None # Host explicitly acquires context; this turn cannot submit or request another child.
  if dispatcher.status in [CurrentDownloadLoopStage.Adopted, CurrentDownloadLoopStage.Exhausted,
      CurrentDownloadLoopStage.Failed]: return CurrentDownloadLoopError.None # Terminal plans never select or prepare again.
  if dispatcher.status in [CurrentDownloadLoopStage.Preparing, CurrentDownloadLoopStage.Cancelling]:
    let token = dispatcher.current
    if token == nil:
      dispatcher.status = CurrentDownloadLoopStage.Failed
      return CurrentDownloadLoopError.SessionFailure # Missing scheduler authority cannot authorize worker result consumption.
    discard dispatcher.catalog.poll() # Retired input streams cannot callback into the leased graph; unrelated endpoint I/O continues.
    let preparationElapsed = uint64(now)-dispatcher.started # Monotonic entry checks prove subtraction before the deadline comparison.
    if dispatcher.status == CurrentDownloadLoopStage.Preparing and
        preparationElapsed >= uint64(dispatcher.limits.attemptTimeout):
      discard dispatcher.session.cancelPreparation(token, owner[])
      dispatcher.status = CurrentDownloadLoopStage.Cancelling # Even a Done certificate is unwanted once this deadline is observed.
      return CurrentDownloadLoopError.None # Keep lease and input intact until a later retirement turn.
    if owner[].preparationPhase != PreparationPhase.Done: return CurrentDownloadLoopError.None
    let completed = dispatcher.session.collectPreparation(token, owner[])
    if completed.error == CurrentDownloadSessionError.None:
      dispatcher.status = CurrentDownloadLoopStage.Queued # Queue now; a later Services tick alone can adopt.
    elif dispatcher.session.stage == CurrentBlockDownloadStage.AwaitingAncestors:
      dispatcher.status = CurrentDownloadLoopStage.DrainingAncestors # Managed collection ended every exclusive graph borrow before connection retirement.
    else:
      dispatcher.refusal = completed.failure
      return dispatcher.retry(now) # Collection already ended worker/RPC exclusion before raw/context retirement.
    return CurrentDownloadLoopError.None
  let active = dispatcher.current
  if active != nil and uint64(now) - dispatcher.started >= uint64(dispatcher.limits.attemptTimeout):
    return dispatcher.retry(now) # Includes handshakes/pending opens and forces native retirement at the exact total deadline.
  discard dispatcher.catalog.expire(CurrentDownloadTick(uint64(now)))
  discard dispatcher.catalog.poll() # Native callbacks only copy/route input; all preparation below follows their return.
  let token = dispatcher.current
  if token == nil:
    let selected = dispatcher.session.begin(owner[], dispatcher.ancestors, dispatcher.limits.input,
      dispatcher.limits.candidate, DownloadScheduleTick(uint64(now)))
    if selected.error != CurrentDownloadSessionError.None:
      dispatcher.refusal = selected.failure
      if selected.error == CurrentDownloadSessionError.ScheduleFailure:
        case selected.failure.scheduleError
        of DownloadScheduleError.Waiting: return CurrentDownloadLoopError.None # Preserve cooldown without sleeping or spinning.
        of DownloadScheduleError.Exhausted:
          dispatcher.status = CurrentDownloadLoopStage.Exhausted
          return CurrentDownloadLoopError.None # Exhaustion cannot be mistaken for an adopted successor.
        else: discard # Other scheduler failures indicate unusable configuration/invariants.
      dispatcher.status = CurrentDownloadLoopStage.Failed
      return CurrentDownloadLoopError.SessionFailure
    dispatcher.current = selected.value
    dispatcher.started = uint64(now)
    dispatcher.status = CurrentDownloadLoopStage.Receiving
    return CurrentDownloadLoopError.None # Selecting does not also request/prepare/adopt in this turn.
  if not dispatcher.requested:
    if dispatcher.catalog.ready(token.peer):
      let opened = dispatcher.catalog.requestStream(dispatcher.session, token,
        dispatcher.limits.stream, CurrentDownloadTick(uint64(now)))
      if opened != CurrentDownloadPeerError.None: return dispatcher.retry(now)
      dispatcher.requested = true # Retain pending-open identity until callback or total-deadline retirement.
    return CurrentDownloadLoopError.None # Incomplete authentication consumes no callback work beyond the bounded catalog poll.
  if dispatcher.catalog.busy or dispatcher.session.streamActive: return CurrentDownloadLoopError.None
  case dispatcher.session.stage
  of CurrentBlockDownloadStage.Ready:
    let prepared = dispatcher.session.beginPreparation(token, owner[])
    if prepared.error == CurrentDownloadSessionError.None:
      dispatcher.status = CurrentDownloadLoopStage.Preparing # The current turn only submits; execution and adoption remain separate.
    else:
      dispatcher.refusal = prepared.failure
      return dispatcher.retry(now) # Preparation failures release private prefixes only after native retirement.
  of CurrentBlockDownloadStage.Empty:
    return dispatcher.finish(DownloadAttemptOutcome.Empty,
        now) # A valid empty reply remains retryable within the same budget.
  of CurrentBlockDownloadStage.Failed:
    dispatcher.refusal = dispatcher.session.receptionFailure(token)
    return dispatcher.retry(now) # Preserve the actual framing failure before discarding input.
  else:
    return dispatcher.retry(now) # Closed cancelled input or rejected binding cannot hold the scheduler forever.
  CurrentDownloadLoopError.None

proc close*(dispatcher: var CurrentDownloadLoop) =
  ## Join execution before retiring callbacks/input, then settle only this dispatcher's handoff and end its Services borrow.
  let borrowed = dispatcher.owner
  if borrowed != nil:
    let owner: ptr Services = borrowed
    if owner[].stateProofActive: owner[].stopStateProofs() # Join every selected-state borrower before callback/input alias retirement.
    if owner[].diskPublicationActive:
      owner[].stopDiskPublication() # Join durable IO before input/callback aliases can retire.
    owner[].stopPreparation() # Join before any native close callback or retained input/context owner can retire.
    let active = dispatcher.current
    if active != nil: discard dispatcher.session.retirePreparation(active, owner[])
  dispatcher.catalog.close()
  if borrowed != nil and dispatcher.status == CurrentDownloadLoopStage.Queued:
    let owner: ptr Services = borrowed
    if owner[].currentAccumulationPhase == CurrentHandoffPhase.Pending:
      discard owner[].cancelCurrentAccumulation() # Shutdown never executes an unattempted candidate.
    elif owner[].currentAccumulationPhase == CurrentHandoffPhase.Finished:
      dispatcher.completion = owner[].takeCurrentAccumulation()
      dispatcher.hasCompletion = true # Preserve an actual result produced by an explicit external Services tick.
  let token = dispatcher.current
  if token != nil:
    discard dispatcher.session.discardInput(token) # Queued/terminal private ownership retires with the closed aggregate.
  dispatcher.session = default(CurrentDownloadSession) # Native close above makes private receiver/lease retirement safe.
  dispatcher.ancestors = @[]
  dispatcher.peers = @[]
  dispatcher.owner = nil
  dispatcher.current = nil
  dispatcher.status = CurrentDownloadLoopStage.Closed

proc ancestorDemand*(dispatcher: CurrentDownloadLoop): CurrentDownloadSessionResult[
    ReportLookupDemand] {.requires:
    dispatcher.status == CurrentDownloadLoopStage.AwaitingAncestors.} =
  ## Only a collected prepared input and fully retired peer catalog can authorize host-side acquisition.
  let token = dispatcher.current
  if token == nil: return default(CurrentDownloadSessionResult[
      ReportLookupDemand]) # Lost ownership never fabricates a plan.
  dispatcher.session.ancestorDemand(token)

func ancestorRemaining*(dispatcher: CurrentDownloadLoop,
    now: CurrentDownloadLoopTick): uint64 {.requires:
    dispatcher.status == CurrentDownloadLoopStage.AwaitingAncestors and uint64(now) >=
        dispatcher.lastTick.} =
  ## Return the original attempt's remaining milliseconds; a query never creates a new request budget.
  let elapsed = uint64(now) - dispatcher.started
  let maximum = uint64(dispatcher.limits.attemptTimeout)
  if elapsed >= maximum: 0'u64
  else: maximum - elapsed # Ordered monotonic ticks prove the subtraction does not wrap.

proc resumeAncestors*(dispatcher: var CurrentDownloadLoop, ancestors: openArray[OwnedHeader],
    now: CurrentDownloadLoopTick): CurrentDownloadLoopError =
  ## Resume the same token/input after host acquisition; a later tick alone may grant another worker lease.
  if dispatcher.status != CurrentDownloadLoopStage.AwaitingAncestors: return CurrentDownloadLoopError.Busy
  if uint64(now) < dispatcher.lastTick: return CurrentDownloadLoopError.ClockRegression
  dispatcher.lastTick = uint64(now)
  if uint64(now) - dispatcher.started >= uint64(dispatcher.limits.attemptTimeout):
    dispatcher.status = CurrentDownloadLoopStage.Failed
    return CurrentDownloadLoopError.AttemptExpired
  let borrowed = dispatcher.owner
  let token = dispatcher.current
  if borrowed == nil or token == nil: return CurrentDownloadLoopError.Uninitialized
  let owner: ptr Services = borrowed
  if not owner[].preparationAvailable: return CurrentDownloadLoopError.ServicesBusy
  let resumed = dispatcher.session.resumeAncestors(token, owner[], ancestors)
  if resumed.error != CurrentDownloadSessionError.None:
    dispatcher.refusal = resumed.failure
    return CurrentDownloadLoopError.SessionFailure # Quota/context refusal keeps the exact suspended input available for explicit correction/close.
  var retained = newSeq[OwnedHeader](ancestors.len)
  for index, ancestor in ancestors: retained[index] = ancestor # Input resumption proved all descriptor/count/byte bounds before this copy.
  dispatcher.ancestors = retained
  dispatcher.status = CurrentDownloadLoopStage.Receiving # requested remains true: the next tick prepares Ready input without another network request.
  CurrentDownloadLoopError.None
