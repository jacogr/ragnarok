# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One-child dispatcher drives native I/O, private preparation and actual deferred adoption separately.
## Keep this owner and its exclusively borrowed Services stable until explicit close retires callbacks.

import ./[block_download_peers, block_download_session, block_download_stream]
import ../app/[services, handoff, chain, candidate, block_input, block_download, download_schedule, preparation_worker]
import ../codec/[bounded, header]
import ../chain/genesis
import ../state/[accumulation_completion, store]

type
  DownloadLoopTick* = distinct uint64 ## Monotonic host milliseconds shared by all dispatcher deadlines.
  DownloadAttemptTimeout* = distinct uint64 ## Total attempt duration includes handshake, native open and execution; cancellation waits for actual retirement.
  DownloadLoopLimits* = object ## Caller supplies every execution, reception, retry and adoption policy independently.
    schedule*: DownloadScheduleLimits
    input*: BlockInputLimits
    candidate*: ApplicationCandidateLimits
    composition*: AccumulationCompositionLimits
    stream*: DownloadStreamLimits
    attemptTimeout*: DownloadAttemptTimeout
  DownloadLoopStage* {.pure.} = enum ## Adoption is terminal only after taking a successful canonical handoff result.
    Uninitialized, Waiting, Receiving, Preparing, Cancelling, Queued, Adopted, Exhausted, Failed, Closed
  DownloadLoopError* {.pure.} = enum ## Ordinary wait/retry/budget completion are stages, while refusals preserve ownership.
    None, Uninitialized, Busy, InvalidPolicy, MissingState, ServicesBusy, ClockRegression,
    SessionFailure, LostHandoff, LostPreparation, Closed
  BlockDownloadLoop* = object ## Fixed-address composite owns native callback targets and one scheduler/session lease.
    catalog: BlockDownloadPeers
    session: BlockDownloadSession
    owner: nil ptr Services
    peers: seq[DownloadPeerId]
    ancestors: seq[OwnedHeader]
    limits: DownloadLoopLimits
    current: nil DownloadSessionAttempt
    status: DownloadLoopStage
    lastTick, started: uint64
    requested, hasCompletion: bool
    completion: ApplicationChainResult[BlockSnapshot]
    refusal: DownloadSessionFailure

proc `=copy`*(destination: var BlockDownloadLoop, source: BlockDownloadLoop) {.
    error: "BlockDownloadLoop owns stable native callbacks and exclusive adoption".}
  ## Copying the aggregate would duplicate callback addresses and result-consumption authority.
proc `=dup`*(source: BlockDownloadLoop): BlockDownloadLoop {.error.}
  ## Explicitly forbid composite duplication independently of nested owner hooks.
proc requireClosed(dispatcher: BlockDownloadLoop) {.requires:
    dispatcher.status in [DownloadLoopStage.Uninitialized, DownloadLoopStage.Closed].} =
  ## Even an endpoint-free configured dispatcher must release its Services borrow explicitly.
  discard
proc `=destroy`*(dispatcher: BlockDownloadLoop) =
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

func stage*(dispatcher: BlockDownloadLoop): DownloadLoopStage =
  ## Inspect progress without exposing native owners or mutable session state.
  dispatcher.status
func sessionFailure*(dispatcher: BlockDownloadLoop): DownloadSessionFailure {.requires:
    dispatcher.status notin [DownloadLoopStage.Preparing, DownloadLoopStage.Cancelling].} =
  ## Retain the latest selected admission/reception/preparation refusal for diagnostics, including retries.
  dispatcher.refusal
func completed*(dispatcher: BlockDownloadLoop): bool =
  ## A retained adoption refusal also counts as an observed result, never as successful adoption.
  dispatcher.hasCompletion
func adoption*(dispatcher: BlockDownloadLoop): ApplicationChainResult[BlockSnapshot] {.
    requires: dispatcher.hasCompletion and dispatcher.status notin [DownloadLoopStage.Preparing,
        DownloadLoopStage.Cancelling].} =
  ## Copy only a real consumed Services result; its own success/failure guards remain authoritative.
  dispatcher.completion
proc readyPeers*(dispatcher: BlockDownloadLoop): seq[DownloadPeerId] =
  ## Return copied authenticated identities without granting native callback access.
  dispatcher.catalog.readyPeers

proc configure*(dispatcher: var BlockDownloadLoop, owner: var Services,
    peers: openArray[DownloadPeerId], ancestors: openArray[OwnedHeader],
    limits: DownloadLoopLimits, now: DownloadLoopTick): DownloadLoopError =
  ## Validate bounded retained configuration before borrowing stable Services; no endpoint opens here.
  if dispatcher.status != DownloadLoopStage.Uninitialized: return DownloadLoopError.Busy
  if uint64(limits.schedule.peers) == 0 or uint64(limits.schedule.peers) > 16 or
      uint64(limits.attemptTimeout) == 0 or uint64(limits.stream.readBytes) == 0 or
      uint64(limits.stream.readBytes) > 4096 or uint64(limits.stream.writeBytes) == 0 or
      uint64(limits.stream.writeBytes) > 42 or uint64(limits.stream.timeout) == 0 or
      uint64(limits.input.blockBytes) == 0 or
      uint64(ancestors.len) > uint64(limits.input.ancestors):
    return DownloadLoopError.InvalidPolicy # Prove catalog, callback and retained ancestor counts before allocation.
  var remaining = uint64(limits.input.ancestorBytes)
  for ancestor in ancestors:
    let info = ancestor.headerInfo
    if info.error != HeaderError.None or uint64(info.value.consumed) > remaining:
      return DownloadLoopError.InvalidPolicy # Guard extraction and subtraction before copying any history context.
    remaining -= uint64(info.value.consumed)
  if owner.preparationActive: return DownloadLoopError.ServicesBusy # No canonical alias may escape another worker lease.
  if owner.stateSnapshot.error != StateStoreError.None: return DownloadLoopError.MissingState
  if not owner.preparationAvailable or owner.accumulationStage !=
      AccumulationHandoffStage.Idle: return DownloadLoopError.ServicesBusy
  if dispatcher.session.configure(peers, limits.schedule, DownloadScheduleTick(uint64(now))) !=
      DownloadScheduleError.None: return DownloadLoopError.InvalidPolicy
  discard dispatcher.catalog.configure(limits.schedule.peers) # Matching positive <=16 policy was checked above.
  dispatcher.peers = @[]
  for peer in peers: dispatcher.peers.add(peer) # Scheduler preflight has already bounded/validated the complete peer set.
  dispatcher.ancestors = @[]
  for ancestor in ancestors: dispatcher.ancestors.add(
      ancestor) # Immutable owned headers retain only the bounded context.
  dispatcher.limits = limits
  dispatcher.owner = addr owner
  dispatcher.lastTick = uint64(now)
  dispatcher.status = DownloadLoopStage.Waiting
  DownloadLoopError.None

proc openPeer*(dispatcher: var BlockDownloadLoop, id: DownloadPeerId, expected: DownloadPeerKey,
    port: uint16, certificate, key, alpn: string): DownloadPeerError =
  ## Startup explicitly maps only scheduled identities to endpoints, without changing budgets or peer weight.
  if dispatcher.status != DownloadLoopStage.Waiting or dispatcher.current != nil:
    return DownloadPeerError.Busy # Register all endpoints before starting attempts; no moving live callback owners.
  var known = false
  for peer in dispatcher.peers:
    if peer == id: known = true # At most sixteen checked identities are scanned.
  if not known: return DownloadPeerError.InvalidPeer
  dispatcher.catalog.openPeer(id, expected, port, certificate, key, alpn)

proc finish(dispatcher: var BlockDownloadLoop, outcome: DownloadAttemptOutcome,
    now: DownloadLoopTick): DownloadLoopError =
  ## Retire only after the caller has observed native close and settled/discarded application input.
  let token = dispatcher.current
  if token == nil: return DownloadLoopError.SessionFailure
  let ended = dispatcher.session.finish(token, outcome, DownloadScheduleTick(uint64(now)))
  if ended.error != DownloadSessionError.None:
    dispatcher.refusal = ended
    dispatcher.status = DownloadLoopStage.Failed
    return DownloadLoopError.SessionFailure # Preserve an invariant failure rather than selecting another lease.
  dispatcher.current = nil
  dispatcher.requested = false
  dispatcher.status = if outcome == DownloadAttemptOutcome.Adopted: DownloadLoopStage.Adopted
    else: DownloadLoopStage.Waiting # A retry selects at most one new lease on a later host tick.
  DownloadLoopError.None

proc retry(dispatcher: var BlockDownloadLoop, now: DownloadLoopTick): DownloadLoopError =
  ## Retire pending/bound opens before discarding input, so late callbacks cannot attach to a replacement.
  let token = dispatcher.current
  if token == nil: return DownloadLoopError.SessionFailure
  discard dispatcher.catalog.retire(token.peer)
  let discarded = dispatcher.session.discardInput(token)
  if discarded.error != DownloadSessionError.None:
    dispatcher.refusal = discarded
    dispatcher.status = DownloadLoopStage.Failed
    return DownloadLoopError.SessionFailure # Keep the lease for explicit close on unexpected retirement failure.
  dispatcher.finish(DownloadAttemptOutcome.Retry, now)

proc tick*(dispatcher: var BlockDownloadLoop, now: DownloadLoopTick): DownloadLoopError =
  ## One turn polls bounded endpoints, submits/collects at most one job and adopts only an earlier queued candidate.
  if dispatcher.status == DownloadLoopStage.Uninitialized: return DownloadLoopError.Uninitialized
  if dispatcher.status == DownloadLoopStage.Closed: return DownloadLoopError.Closed
  if uint64(now) < dispatcher.lastTick: return DownloadLoopError.ClockRegression
  let borrowed = dispatcher.owner
  if borrowed == nil: return DownloadLoopError.Uninitialized
  let owner: ptr Services = borrowed
  if dispatcher.status in [DownloadLoopStage.Preparing, DownloadLoopStage.Cancelling] and not owner[].preparationActive:
    dispatcher.status = DownloadLoopStage.Failed
    return DownloadLoopError.LostPreparation # External take/stop cannot substitute for this producer's completion.
  if dispatcher.status notin [DownloadLoopStage.Preparing, DownloadLoopStage.Cancelling] and owner[].preparationActive:
    return DownloadLoopError.ServicesBusy # Never mutate aliases owned by an unexpected external producer.
  if dispatcher.status != DownloadLoopStage.Queued and owner[].accumulationStage !=
      AccumulationHandoffStage.Idle:
    return DownloadLoopError.ServicesBusy # Never process/consume another producer's pending or finished handoff.
  if dispatcher.status == DownloadLoopStage.Queued and owner[].accumulationStage ==
      AccumulationHandoffStage.Idle:
    dispatcher.status = DownloadLoopStage.Failed
    return DownloadLoopError.LostHandoff # An external take/cancel violates exclusive borrowed ownership; never infer success.
  dispatcher.lastTick = uint64(now)
  owner[].tick(uint32(dispatcher.catalog.readyPeers.len)) # At most sixteen authenticated endpoints; no narrowing overflow.
  if dispatcher.status == DownloadLoopStage.Queued:
    if owner[].accumulationStage != AccumulationHandoffStage.Finished:
      return DownloadLoopError.None # Durable publication may span multiple nonblocking service ticks.
    dispatcher.completion = owner[].takeAccumulation()
    dispatcher.hasCompletion = true
    let outcome = if dispatcher.completion.error == ApplicationChainError.None:
        DownloadAttemptOutcome.Adopted else: DownloadAttemptOutcome.Retry
    return dispatcher.finish(outcome, now) # Actual refusal keeps the bounded retry plan alive.
  if dispatcher.status in [DownloadLoopStage.Adopted, DownloadLoopStage.Exhausted,
      DownloadLoopStage.Failed]: return DownloadLoopError.None # Terminal plans never select or prepare again.
  if dispatcher.status in [DownloadLoopStage.Preparing, DownloadLoopStage.Cancelling]:
    let token = dispatcher.current
    if token == nil:
      dispatcher.status = DownloadLoopStage.Failed
      return DownloadLoopError.SessionFailure # Missing scheduler authority cannot authorize worker result consumption.
    discard dispatcher.catalog.poll() # Retired input streams cannot callback into the leased graph; unrelated endpoint I/O continues.
    if dispatcher.status == DownloadLoopStage.Preparing and uint64(now) - dispatcher.started >=
        uint64(dispatcher.limits.attemptTimeout):
      discard dispatcher.session.cancelPreparation(token, owner[])
      dispatcher.status = DownloadLoopStage.Cancelling # Even a Done certificate is unwanted once this deadline is observed.
      return DownloadLoopError.None # Keep lease and input intact until a later retirement turn.
    if owner[].preparationPhase != PreparationPhase.Done: return DownloadLoopError.None
    let completed = dispatcher.session.collectPreparation(token, owner[],
        dispatcher.limits.composition)
    if completed.error == DownloadSessionError.None:
      dispatcher.status = DownloadLoopStage.Queued # Queue now; a later Services tick alone can adopt.
    else:
      dispatcher.refusal = completed.failure
      return dispatcher.retry(now) # Collection already ended worker/RPC exclusion before raw/context retirement.
    return DownloadLoopError.None
  let active = dispatcher.current
  if active != nil and uint64(now) - dispatcher.started >= uint64(dispatcher.limits.attemptTimeout):
    return dispatcher.retry(now) # Includes handshakes/pending opens and forces native retirement at the exact total deadline.
  discard dispatcher.catalog.expire(DownloadTick(uint64(now)))
  discard dispatcher.catalog.poll() # Native callbacks only copy/route input; all preparation below follows their return.
  let token = dispatcher.current
  if token == nil:
    let selected = dispatcher.session.begin(owner[], dispatcher.ancestors, dispatcher.limits.input,
      dispatcher.limits.candidate, DownloadScheduleTick(uint64(now)))
    if selected.error != DownloadSessionError.None:
      dispatcher.refusal = selected.failure
      if selected.error == DownloadSessionError.ScheduleFailure:
        case selected.failure.scheduleError
        of DownloadScheduleError.Waiting: return DownloadLoopError.None # Preserve cooldown without sleeping or spinning.
        of DownloadScheduleError.Exhausted:
          dispatcher.status = DownloadLoopStage.Exhausted
          return DownloadLoopError.None # Exhaustion cannot be mistaken for an adopted successor.
        else: discard # Other scheduler failures indicate unusable configuration/invariants.
      dispatcher.status = DownloadLoopStage.Failed
      return DownloadLoopError.SessionFailure
    dispatcher.current = selected.value
    dispatcher.started = uint64(now)
    dispatcher.status = DownloadLoopStage.Receiving
    return DownloadLoopError.None # Selecting does not also request/prepare/adopt in this turn.
  if not dispatcher.requested:
    if dispatcher.catalog.ready(token.peer):
      let opened = dispatcher.catalog.requestStream(dispatcher.session, token,
        dispatcher.limits.stream, DownloadTick(uint64(now)))
      if opened != DownloadPeerError.None: return dispatcher.retry(now)
      dispatcher.requested = true # Retain pending-open identity until callback or total-deadline retirement.
    return DownloadLoopError.None # Incomplete authentication consumes no callback work beyond the bounded catalog poll.
  if dispatcher.catalog.busy or dispatcher.session.streamActive: return DownloadLoopError.None
  case dispatcher.session.stage
  of BlockDownloadStage.Ready:
    let prepared = dispatcher.session.beginPreparation(token, owner[])
    if prepared.error == DownloadSessionError.None:
      dispatcher.status = DownloadLoopStage.Preparing # The current turn only submits; execution and adoption remain separate.
    else:
      dispatcher.refusal = prepared.failure
      return dispatcher.retry(now) # Preparation failures release private prefixes only after native retirement.
  of BlockDownloadStage.Empty:
    return dispatcher.finish(DownloadAttemptOutcome.Empty,
        now) # A valid empty reply remains retryable within the same budget.
  of BlockDownloadStage.Failed:
    dispatcher.refusal = dispatcher.session.receptionFailure(token)
    return dispatcher.retry(now) # Preserve the actual framing failure before discarding input.
  else:
    return dispatcher.retry(now) # Closed cancelled input or rejected binding cannot hold the scheduler forever.
  DownloadLoopError.None

proc close*(dispatcher: var BlockDownloadLoop) =
  ## Join execution before retiring callbacks/input, then settle only this dispatcher's handoff and end its Services borrow.
  let borrowed = dispatcher.owner
  if borrowed != nil:
    let owner: ptr Services = borrowed
    if owner[].diskPublicationActive:
      owner[].stopDiskPublication() # Join durable IO before input/callback aliases can retire.
    owner[].stopPreparation() # Join before any native close callback or retained input/context owner can retire.
    let active = dispatcher.current
    if active != nil: discard dispatcher.session.retirePreparation(active, owner[])
  dispatcher.catalog.close()
  if borrowed != nil and dispatcher.status == DownloadLoopStage.Queued:
    let owner: ptr Services = borrowed
    if owner[].accumulationStage == AccumulationHandoffStage.Pending:
      discard owner[].cancelAccumulation() # Shutdown never executes an unattempted candidate.
    elif owner[].accumulationStage == AccumulationHandoffStage.Finished:
      dispatcher.completion = owner[].takeAccumulation()
      dispatcher.hasCompletion = true # Preserve an actual result produced by an explicit external Services tick.
  let token = dispatcher.current
  if token != nil:
    discard dispatcher.session.discardInput(token) # Queued/terminal private ownership retires with the closed aggregate.
  dispatcher.session = default(BlockDownloadSession) # Native close above makes private receiver/lease retirement safe.
  dispatcher.ancestors = @[]
  dispatcher.peers = @[]
  dispatcher.owner = nil
  dispatcher.current = nil
  dispatcher.status = DownloadLoopStage.Closed
