# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional CE135 host admission acknowledges only fresh managed verification and bounded detached retention.
## Native callbacks retain raw bytes; this source-free controller owns only exact tickets, policy and pending candidates.
import std/[monotimes, times]
import ./services
import ./work_guarantee_pool
import ../jamnp-s/[node, read_stream, report_cache, work_distribution]
import ../codec/bounded
import ../codec/state/safrole

type
  WorkDistributionPolicy* = object ## Explicit CPU, retained-row, retained-byte and elapsed-time ceilings leave omission disabled.
    ready: bool
    limits: WorkDistributionLimits
    entries: int
    bytes: ByteLimit
    timeout: int
  WorkDistributionDispatcher* = object ## Noncopyable exact namespace ownership cannot collect or join a different controller's work.
    policy: WorkDistributionPolicy
    pool: WorkGuaranteePool
    held, active, cancelled: bool
    ticket: NodeReadTicket
    request: ReadRequest
    token: WorkDistributionToken
    started: MonoTime
    received: uint64
func workDistributionPolicy*(limits: WorkDistributionLimits,
    entries: range[1..MaxPendingGuarantees], bytes: ByteLimit,
    timeoutMs: range[1..120000] = 30000): WorkDistributionPolicy =
  ## Retention must accommodate one maximum accepted payload; native framing keeps its separate hard ceiling.
  let wire = uint64(limits.wireBytes)
  if wire == 0 or wire > uint64(MaxReadReplyBytes): return default(WorkDistributionPolicy)
  if uint64(bytes) < wire or uint64(bytes) > 32'u64*1024*1024: return default(WorkDistributionPolicy)
  if uint64(limits.targets) == 0 or uint64(limits.targets) > 2046: return default(WorkDistributionPolicy)
  WorkDistributionPolicy(ready: true, limits: limits, entries: entries, bytes: bytes,
      timeout: timeoutMs)
func valid*(policy: WorkDistributionPolicy): bool =
  ## Default policy does not activate native receipt or allocate retention capacity.
  policy.ready
func received*(owner: WorkDistributionDispatcher): uint64 =
  ## Count only fresh, retained incoming guarantees whose live transport accepted the bare FIN.
  owner.received
func pendingCount*(owner: WorkDistributionDispatcher): int =
  ## Detached candidate occupancy is observable during any foreign canonical lease.
  owner.pool.len
func pendingBytes*(owner: WorkDistributionDispatcher): int =
  ## Exact canonical payload bytes exclude native input and report-cache framing.
  owner.pool.byteLength
proc pendingPayload*(owner: WorkDistributionDispatcher, ordinal: int): seq[byte] {.requires:
    ordinal >= 0 and ordinal < owner.pool.len.} =
  ## A later block/assurer consumer must freshly qualify this independently copied candidate.
  owner.pool.payloadAt(ordinal)
proc `=copy`*(destination: var WorkDistributionDispatcher,
    source: WorkDistributionDispatcher) {.error.}
  ## Duplicate control would allow competing cancellation and claim retirement.
proc `=dup`*(source: WorkDistributionDispatcher): WorkDistributionDispatcher {.error.}
  ## Initialization cannot duplicate worker/stream authority either.
proc `=wasMoved`*(owner: var WorkDistributionDispatcher) {.nodestroy, requires:
    not owner.held and not owner.active.} =
  ## Every retained child transfers only after explicit retirement of exact native/CPU controls.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.pool)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.token)
  owner.held = false
  owner.active = false
proc requireClosed(owner: WorkDistributionDispatcher) {.requires:
    not owner.held and not owner.active.} =
  ## A destructor cannot silently abandon or join a canonical borrower.
  discard
proc `=destroy`*(owner: WorkDistributionDispatcher) =
  ## Only source-free owners retire after the required explicit controller close.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.pool)
  `=destroy`(owner.request)
  `=destroy`(owner.token)
proc configure*(owner: var WorkDistributionDispatcher, streams: var NodeService,
    policy: WorkDistributionPolicy): bool =
  ## Configure storage before opening native admission; no private signing key is required to receive a guarantee.
  if owner.policy.ready or not policy.ready or owner.held or owner.active: return false
  let entries = policy.entries
  if entries < 1 or entries > MaxPendingGuarantees: return false
  let capacity = range[1..MaxPendingGuarantees](entries)
  if not streams.enableDistributionStreams(): return false
  if not owner.pool.configure(capacity, policy.bytes): return false
  owner.policy = policy
  true
proc clearClaim(owner: var WorkDistributionDispatcher) =
  ## Matching collection or joined revocation precedes host-only raw/token retirement.
  owner.held = false
  owner.active = false
  owner.cancelled = false
  owner.ticket = default(NodeReadTicket)
  owner.request = default(ReadRequest)
  owner.token = default(WorkDistributionToken)
proc reject(owner: var WorkDistributionDispatcher, streams: var NodeService) =
  ## Refusal closes only the claimed native stream and never manufactures a successful empty response.
  discard streams.reject(owner.ticket)
  owner.clearClaim()
proc poll*(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService, reports: var ReportCache, clock: MonoTime, now: StateTime) =
  ## Collection and source-free retirement precede CPU arbitration; this activation never submits a new job.
  if not owner.policy.ready: return
  owner.pool.expire(now)
  if not owner.held: return
  let expired = (clock-owner.started).inMilliseconds >= owner.policy.timeout
  let live = streams.readLive(owner.ticket)
  if not owner.active:
    if expired or not live: owner.reject(streams)
    return
  if not services.workDistributionActive(owner.token):
    owner.reject(streams) # External joined shutdown revoked the old namespace, not a foreign worker.
    return
  if (expired or not live) and not owner.cancelled:
    owner.cancelled = services.cancelWorkDistribution(owner.token)
  let completed = services.collectWorkDistribution(owner.token)
  if completed.kind == WorkDistributionCompletionKind.Uninitialized: return
  owner.active = false
  owner.token = default(WorkDistributionToken)
  if expired or not live or owner.cancelled:
    owner.reject(streams)
    return
  if completed.kind != WorkDistributionCompletionKind.Completed:
    owner.reject(streams) # Actual verification failures cannot disclose a successful FIN.
    return
  let info = completed.distributionInfo
  if not services.workDistributionCurrent(info, now):
    return # Preserve the original native deadline and raw bytes for a fresh CPU qualification.
  if not owner.pool.canRemember(info):
    owner.reject(streams)
    return
  if reports.remember(completed.distributionReport) != ReportCacheError.None:
    owner.reject(streams)
    return
  if not owner.pool.remember(completed):
    owner.reject(streams)
    return
  let reply = captureReadReply(owner.request, [])
  if reply.error != ReadError.None:
    owner.reject(streams)
    return
  if streams.respond(owner.ticket, reply.value) == ReadError.None:
    if owner.received < high(uint64): inc owner.received
    owner.clearClaim()
  else:
    owner.reject(streams) # Retained candidate may remain locally useful despite a native reset or output refusal.
proc submit*(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService, clock: MonoTime, now: StateTime): bool {.raises.} =
  ## One complete filtered request waits under its original deadline; all source capture aliases retire inside Services before publication.
  if not owner.policy.ready or owner.active or not services.stateProofAvailable: return false
  if not owner.held:
    let task = streams.takeRead(ReadKind.Guarantee)
    if task.error != NodeError.None: return false
    owner.ticket = task.value.ticket
    owner.request = task.value.request
    owner.started = clock
    owner.held = true
  if not streams.readLive(owner.ticket) or (clock-owner.started).inMilliseconds >=
      owner.policy.timeout:
    owner.reject(streams)
    return true
  let admitted = services.beginWorkDistribution(owner.request, now, owner.policy.limits)
  if admitted.error == StateProofAdmissionError.Busy: return false
  if admitted.error != StateProofAdmissionError.None:
    owner.reject(streams)
    return true
  owner.token = admitted.value
  owner.active = true
  owner.cancelled = false
  true
proc close*(owner: var WorkDistributionDispatcher, services: var Services,
    streams: var NodeService) =
  ## Joining requires successful exact cancellation; stale/default controls never interrupt a foreign lease.
  if owner.active:
    if services.cancelWorkDistribution(owner.token): services.stopStateProofs()
  if owner.held: discard streams.reject(owner.ticket)
  owner.clearClaim()
  owner.pool.clear()
  owner.policy = default(WorkDistributionPolicy)
