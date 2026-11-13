# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional source-free CE137 acquisition serializes canonical planning, existing-record probes, actual guarantor requests and verified durable retention through exact shared leases.

import std/[monotimes, times]
import ./services
import ./proof/[worker, work_submission, assurance_acquisition]
import ../jamnp-s/[node, connections, endpoints, read_stream, read_client, assurance_fetch,
  availability_proof, assurance_store, assurance_record]
import ../codec/bounded
import ../codec/state/safrole

type
  AssuranceAcquisitionPolicy* = object ## Whole-round network reservations and finite peer/CPU deadlines accompany explicit canonical/proof/output limits; omission stays disabled.
    ready: bool
    planning: AssuranceFetchLimits
    acquisition: AssuranceAcquisitionLimits
    requests, dials, bytes: uint64
    peerTimeout, jobTimeout, roundTimeout, retry, attempts: int
  AssuranceAcquirerPhase* {.pure.} = enum ## Waiting means the current pass needs no more fetches, never that an assurance may be signed without re-verification.
    Idle, Planning, ProbeReady, Probing, Choosing, Connecting, Fetching, Ready, Retaining,
      LocalReady, LocalReading, Retiring, Backoff, Waiting, Blocked
  AssuranceAcquirer* = object ## Stable noncopyable host owns no canonical map, namespace alias or private key; tokens remain exact through cancellation/Done.
    policy: AssuranceAcquisitionPolicy
    phase, retireNext, afterBackoff: AssuranceAcquirerPhase
    plan: AssuranceFetchPlan
    proof: ProofWorkerTicket
    active, cancelled: bool
    proofStarted, roundStarted, targetStarted, fetchStarted, wake: MonoTime
    core, local, target: int
    selected: AssuranceFetchRequest
    request: ReadRequest
    replyLimit: ByteLimit
    prepared, passComplete: bool
    raw: seq[byte]
    network: NodeRequestTicket
    fetching: bool
    dial: DialTicket
    dialKey: StateEdKey
    dialing, closingDial: bool
    usedRequests, usedDials, usedBytes: uint64
    attempted, retained, probed, failed, passes: uint64

func assuranceAcquisitionPolicy*(planning: AssuranceFetchLimits,
    acquisition: AssuranceAcquisitionLimits, requests, dials: ElementLimit, bytes: ByteLimit,
    peerTimeoutMs: range[1..120000] = 5000, jobTimeoutMs: range[1..120000] = 30000,
    roundTimeoutMs: range[1..600000] = 60000, retryMs: range[1..600000] = 1000,
    attempts: range[1..3] = 3): AssuranceAcquisitionPolicy =
  ## The maximal GP request product is a traversal bound, never an allocated request graph or permission to exceed configured network reservations.
  if not planning.valid or not acquisition.valid: return default(AssuranceAcquisitionPolicy)
  if uint64(requests) == 0 or uint64(requests) > 3'u64*341*1023: return default(AssuranceAcquisitionPolicy)
  if uint64(dials) == 0 or uint64(dials) > 3'u64*341*1023: return default(AssuranceAcquisitionPolicy)
  if uint64(bytes) < uint64(acquisition.wireBytes) or uint64(bytes) > 16'u64*1024*1024*1024*1024:
    return default(AssuranceAcquisitionPolicy)
  AssuranceAcquisitionPolicy(ready: true, planning: planning, acquisition: acquisition,
    requests: uint64(requests), dials: uint64(dials), bytes: uint64(bytes),
    peerTimeout: peerTimeoutMs, jobTimeout: jobTimeoutMs, roundTimeout: roundTimeoutMs,
    retry: retryMs, attempts: attempts)

func valid*(policy: AssuranceAcquisitionPolicy): bool =
  ## A default cannot start jobs, dials or data acquisition.
  policy.ready

proc `=copy`*(destination: var AssuranceAcquirer, source: AssuranceAcquirer) {.error.}
  ## A copied controller could cancel or collect another owner's native/source lease.

proc `=dup`*(source: AssuranceAcquirer): AssuranceAcquirer {.error.}
  ## Initialization cannot duplicate live exact tokens.

proc requireClosed(owner: AssuranceAcquirer) {.requires: not owner.active and not owner.fetching and
    not owner.dialing.} =
  ## Explicit close retires host token ownership before destruction of any managed/raw children.
  discard

proc `=wasMoved`*(owner: var AssuranceAcquirer) {.nodestroy, requires: not owner.active and
    not owner.fetching and not owner.dialing.} =
  ## Only an inactive owner moves; delegate every owned child and opaque token namespace.
  `=wasMoved`(owner.policy)
  `=wasMoved`(owner.plan)
  `=wasMoved`(owner.proof)
  `=wasMoved`(owner.selected)
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.raw)
  `=wasMoved`(owner.network)
  `=wasMoved`(owner.dial)

proc `=destroy`*(owner: AssuranceAcquirer) =
  ## The foreground host joins owned work and requests native retirement before this storage disappears.
  requireClosed(owner)
  `=destroy`(owner.policy)
  `=destroy`(owner.plan)
  `=destroy`(owner.proof)
  `=destroy`(owner.selected)
  `=destroy`(owner.request)
  `=destroy`(owner.raw)
  `=destroy`(owner.network)
  `=destroy`(owner.dial)

func phase*(owner: AssuranceAcquirer): AssuranceAcquirerPhase =
  ## Detached scalar progress is safe while a worker owns canonical/namespace graphs.
  owner.phase

func acquired*(owner: AssuranceAcquirer): uint64 =
  ## Count actual uncancelled synchronized retention results, never cached possession or signed cores.
  owner.retained

func probed*(owner: AssuranceAcquirer): uint64 =
  ## Count only uncancelled actual stored-proof and restore-sync completions; these observations never renew a promise.
  owner.probed

func attempted*(owner: AssuranceAcquirer): uint64 =
  ## Count only admitted remote CE137 requests, including later transport/proof refusal.
  owner.attempted

func failures*(owner: AssuranceAcquirer): uint64 =
  ## Refusal counts grant no partial data or canonical authority.
  owner.failed

func passes*(owner: AssuranceAcquirer): uint64 =
  ## A complete pass can include unavailable coordinates; only fresh private signing may claim possession.
  owner.passes

func demandConnections*(owner: AssuranceAcquirer): int =
  ## Ordinary active/closing dial ownership remains charged until exact native retirement.
  if owner.dialing: 1 else: 0

proc bump(value: var uint64) =
  ## Diagnostic lifetime counters saturate rather than wrap.
  if value < high(uint64): inc value

proc configure*(owner: var AssuranceAcquirer, services: Services, streams: NodeService,
    policy: AssuranceAcquisitionPolicy): bool =
  ## Explicit full-state healthy storage and an actual validator transport are required; configuration opens no namespace and loads no key.
  if owner.policy.ready or not policy.ready or owner.active or owner.fetching or
      owner.dialing: return false
  if not services.stateProofAvailable or not streams.isValidator: return false
  let storage = services.assuranceStorageInfo
  if not storage.opened or storage.faulted: return false
  owner.policy = policy
  owner.phase = AssuranceAcquirerPhase.Idle
  owner.attempted = 0
  owner.retained = 0
  owner.probed = 0
  owner.failed = 0
  owner.passes = 0
  true

proc resetRound(owner: var AssuranceAcquirer, clock: MonoTime) =
  ## New reservation windows do not reset the current core/local cursor or discard previously retained data.
  owner.usedRequests = 0
  owner.usedDials = 0
  owner.usedBytes = 0
  owner.roundStarted = clock
  owner.targetStarted = clock

proc cancelNetwork(owner: var AssuranceAcquirer, streams: var NodeService) =
  ## The native parent retains physical frame credit until close even after this exact logical token is cancelled.
  if owner.fetching: discard streams.cancelRequest(owner.network)
  owner.fetching = false
  owner.network = default(NodeRequestTicket)

proc retireDial(owner: var AssuranceAcquirer, streams: var NodeService, force = false) =
  ## Closing intent does not release normal demand; pre-existing connections never acquire an owned token here.
  if not owner.dialing: return
  if not streams.peerConnectionLive(owner.dial):
    owner.dialing = false
    owner.closingDial = false
    owner.dial = default(DialTicket)
    return
  if not owner.closingDial and (force or not streams.peerBusy(owner.dialKey)):
    owner.closingDial = streams.cancelPeerConnection(owner.dial)

proc transition(owner: var AssuranceAcquirer, streams: var NodeService,
    next: AssuranceAcquirerPhase) =
  ## Only detached state moves while an owned dial retires; no replacement dial can overtake its still-charged engine.
  owner.cancelNetwork(streams)
  owner.retireDial(streams)
  if owner.dialing:
    owner.retireNext = next
    owner.phase = AssuranceAcquirerPhase.Retiring
  else: owner.phase = next

proc pause(owner: var AssuranceAcquirer, streams: var NodeService, clock: MonoTime,
    resume: AssuranceAcquirerPhase) =
  ## Budget/time backoff preserves coordinate progress and starts a fresh reservation window only after its configured delay.
  owner.afterBackoff = resume
  owner.wake = clock+initDuration(milliseconds = owner.policy.retry)
  owner.transition(streams, AssuranceAcquirerPhase.Backoff)

proc clearCoordinate(owner: var AssuranceAcquirer) =
  ## No canonical graph is retained by the request, selected coordinate or detached raw transcript.
  owner.prepared = false
  owner.raw = @[]
  owner.request = default(ReadRequest)
  owner.selected = default(AssuranceFetchRequest)
  owner.replyLimit = ByteLimit(0)
  owner.target = 0

proc dropPlan(owner: var AssuranceAcquirer, streams: var NodeService) =
  ## Source refresh discards only source-free request metadata; durable promises remain in Services.
  owner.plan = default(AssuranceFetchPlan)
  owner.core = 0
  owner.local = 0
  owner.clearCoordinate()
  owner.transition(streams, AssuranceAcquirerPhase.Idle)

proc advance(owner: var AssuranceAcquirer, streams: var NodeService, clock: MonoTime,
    stored: bool) =
  ## Independent original local indices advance before original core rows; no metadata prefix grants an assurance bit.
  if not stored: owner.passComplete = false
  let info = owner.plan.fetchInfo.value.duty
  inc owner.local
  if owner.local >= info.localIndices:
    owner.local = 0
    inc owner.core
  owner.clearCoordinate()
  if owner.core >= info.assignments:
    bump(owner.passes)
    owner.core = 0
    owner.local = 0
    if owner.passComplete:
      owner.transition(streams, AssuranceAcquirerPhase.Waiting)
    else:
      owner.passComplete = true
      owner.pause(streams, clock, AssuranceAcquirerPhase.ProbeReady)
  else:
    owner.targetStarted = clock
    owner.transition(streams, AssuranceAcquirerPhase.ProbeReady)

proc nextTarget(owner: var AssuranceAcquirer, streams: var NodeService, clock: MonoTime) =
  ## At most the actual two/three original credential targets are attempted; no random peer or self-claimed root substitutes.
  owner.raw = @[]
  inc owner.target
  owner.targetStarted = clock
  let count = owner.plan.coreAt(owner.core).value.targets
  if owner.target >= count or owner.target >= owner.policy.attempts:
    owner.advance(streams, clock, false)
  else: owner.transition(streams, AssuranceAcquirerPhase.Choosing)

proc prepare(owner: var AssuranceAcquirer): bool =
  ## Exact reply extent and fixed CE137 bytes derive solely from the independent canonical plan before any native input allocation.
  let selected = owner.plan.requestAt(owner.core, owner.local)
  if selected.error != AssuranceFetchError.None: return false
  let specifier = owner.plan.coreAt(owner.core).value.specifier
  let described = availabilityVerificationInfo(specifier, selected.value.request)
  if described.error != AvailabilityTransferError.None: return false
  let payload = described.value.payloadBytes
  if payload > 16'u64*1024*1024-12: return false
  let ceiling = payload+12
  if ceiling > uint64(owner.policy.acquisition.wireBytes): return false
  var wire = default(array[34, byte])
  for index in 0..<32: wire[index] = selected.value.request.root.bytes[index]
  let shard = uint64(selected.value.request.shard)
  wire[32] = byte(shard and 255)
  wire[33] = byte((shard shr 8) and 255)
  let request = decodeReadRequest(ReadKind.Availability, wire)
  if request.error != ReadError.None: return false
  owner.selected = selected.value
  owner.request = request.value
  owner.replyLimit = ByteLimit(ceiling)
  owner.prepared = true
  true

proc collect(owner: var AssuranceAcquirer, services: var Services,
    streams: var NodeService, clock: MonoTime) =
  ## Exact collection or proven joined revocation precedes every input/raw/token retirement; foreign jobs are untouched.
  if not services.stateProofActive(owner.proof):
    owner.active = false
    owner.proof = default(ProofWorkerTicket)
    owner.dropPlan(streams)
    return
  let expired = (clock-owner.proofStarted).inMilliseconds >= owner.policy.jobTimeout or
    (clock-owner.roundStarted).inMilliseconds >= owner.policy.roundTimeout
  if expired and not owner.cancelled: owner.cancelled = services.cancelStateProof(owner.proof)
  let result = services.collectStateProof(owner.proof)
  if result.kind == ProofWorkerCompletionKind.Uninitialized: return
  owner.active = false
  owner.proof = default(ProofWorkerTicket)
  if owner.cancelled or expired or result.kind == ProofWorkerCompletionKind.Cancelled:
    owner.cancelled = false
    if owner.plan.valid: owner.pause(streams, clock, AssuranceAcquirerPhase.ProbeReady)
    else: owner.pause(streams, clock, AssuranceAcquirerPhase.Idle)
    return
  let phase = owner.phase
  if phase == AssuranceAcquirerPhase.Planning:
    if result.kind != ProofWorkerCompletionKind.WorkSubmitted:
      bump(owner.failed)
      owner.pause(streams, clock, AssuranceAcquirerPhase.Idle)
      return
    let planned = result.workSubmissionValue
    if planned.kind != WorkJobResultKind.AssurancePlanned:
      bump(owner.failed)
      owner.pause(streams, clock, AssuranceAcquirerPhase.Idle)
      return
    owner.plan = planned.plannedAssurance
    if not services.assurancePlanningCurrent(owner.plan):
      owner.dropPlan(streams)
      return
    owner.core = 0
    owner.local = 0
    owner.passComplete = true
    owner.clearCoordinate()
    if owner.plan.fetchInfo.value.duty.assignments ==
        0: owner.phase = AssuranceAcquirerPhase.Waiting
    else: owner.phase = AssuranceAcquirerPhase.ProbeReady
    return
  if not services.assurancePlanningCurrent(owner.plan):
    owner.dropPlan(streams)
    return
  if phase == AssuranceAcquirerPhase.LocalReading:
    if result.kind == ProofWorkerCompletionKind.ReadCompleted and result.readValue.error ==
        ReadError.None:
      let reply = result.readValue.value
      if uint64(reply.byteLength) <= uint64(owner.replyLimit):
        owner.raw = reply.bytes
        owner.phase = AssuranceAcquirerPhase.Ready
        return
    bump(owner.failed)
    owner.nextTarget(streams, clock)
    return
  if result.kind != ProofWorkerCompletionKind.AssuranceAcquired:
    bump(owner.failed)
    owner.advance(streams, clock, false)
    return
  let acquired = result.assuranceAcquisitionValue
  if acquired.error == AssuranceAcquisitionError.None:
    let info = acquired.value
    let source = owner.plan.fetchInfo.value.duty
    let sameAnchor = array[32, byte](info.duty.anchor) == array[32, byte](source.anchor)
    let sameRoot = array[32, byte](info.duty.root) == array[32, byte](source.root)
    if not sameAnchor or not sameRoot or uint64(info.core) != uint64(owner.selected.core) or uint16(
        info.validator) != uint16(owner.selected.validator):
      bump(owner.failed)
      owner.dropPlan(streams)
      return
    if phase == AssuranceAcquirerPhase.Retaining: bump(owner.retained)
    if phase == AssuranceAcquirerPhase.Probing: bump(owner.probed)
    owner.advance(streams, clock, true)
    return
  if phase == AssuranceAcquirerPhase.Probing and acquired.error ==
      AssuranceAcquisitionError.StorageFailure:
    let missing = acquired.storageError.error
    if missing in [AssuranceStoreError.Missing, AssuranceStoreError.Conflict]:
      owner.target = 0
      owner.targetStarted = clock
      owner.phase = AssuranceAcquirerPhase.Choosing
      return
  bump(owner.failed)
  if phase == AssuranceAcquirerPhase.Retaining and acquired.error ==
      AssuranceAcquisitionError.TransferFailure:
    owner.nextTarget(streams, clock)
  else: owner.advance(streams, clock, false)

proc poll*(owner: var AssuranceAcquirer, services: var Services,
    streams: var NodeService, clock: MonoTime) =
  ## Source-free transport progress continues while unrelated workers run; all canonical comparisons first require actual host availability.
  if not owner.policy.ready: return
  if owner.active:
    owner.collect(services, streams, clock)
    return
  if owner.phase == AssuranceAcquirerPhase.Retiring:
    # A peer continually opening unrelated streams must not hold this controller forever; only its own dial may be closed at the round deadline.
    let expired = (clock-owner.roundStarted).inMilliseconds >= owner.policy.roundTimeout
    owner.retireDial(streams, expired)
    if not owner.dialing: owner.phase = owner.retireNext
    return
  let storage = services.assuranceStorageInfo
  if not storage.opened or storage.faulted:
    owner.raw = @[]
    owner.plan = default(AssuranceFetchPlan)
    owner.transition(streams, AssuranceAcquirerPhase.Blocked)
    return
  if owner.phase == AssuranceAcquirerPhase.Blocked: owner.phase = AssuranceAcquirerPhase.Idle
  if owner.plan.valid and services.stateProofAvailable:
    if not services.assurancePlanningCurrent(owner.plan):
      owner.dropPlan(streams)
      return
  if owner.phase == AssuranceAcquirerPhase.Backoff:
    if clock >= owner.wake:
      owner.resetRound(clock)
      owner.phase = owner.afterBackoff
    return
  if owner.phase in [AssuranceAcquirerPhase.Fetching, AssuranceAcquirerPhase.Connecting]:
    if (clock-owner.roundStarted).inMilliseconds >= owner.policy.roundTimeout:
      owner.pause(streams, clock, AssuranceAcquirerPhase.Choosing)
      return
  if owner.phase == AssuranceAcquirerPhase.Fetching:
    let reply = streams.takeReply(owner.network)
    if reply.error == ReadError.None:
      owner.raw = reply.value.bytes
      owner.fetching = false
      owner.network = default(NodeRequestTicket)
      owner.phase = AssuranceAcquirerPhase.Ready
      return
    let expired = (clock-owner.fetchStarted).inMilliseconds >= owner.policy.peerTimeout
    if not expired and streams.requestLive(owner.network): return
    owner.cancelNetwork(streams)
    bump(owner.failed)
    owner.nextTarget(streams, clock)
    return
  if owner.phase == AssuranceAcquirerPhase.Connecting:
    let target = owner.plan.targetAt(owner.core, owner.target).value.validator
    if streams.peerForIdentity(target.ed25519).error == NodeError.None:
      owner.phase = AssuranceAcquirerPhase.Choosing
    elif not streams.peerConnectionLive(owner.dial) or (clock-owner.targetStarted).inMilliseconds >=
        owner.policy.peerTimeout:
      bump(owner.failed)
      owner.nextTarget(streams, clock)
    return
  if owner.phase != AssuranceAcquirerPhase.Choosing or not services.stateProofAvailable: return
  if owner.target >= owner.plan.coreAt(owner.core).value.targets or owner.target >=
      owner.policy.attempts:
    owner.advance(streams, clock, false)
    return
  if (clock-owner.roundStarted).inMilliseconds >= owner.policy.roundTimeout:
    owner.pause(streams, clock, AssuranceAcquirerPhase.Choosing)
    return
  if (clock-owner.targetStarted).inMilliseconds >= owner.policy.peerTimeout:
    bump(owner.failed)
    owner.nextTarget(streams, clock)
    return
  let target = owner.plan.targetAt(owner.core, owner.target).value.validator
  if array[32, byte](target.ed25519) == array[32, byte](streams.localIdentity):
    owner.phase = AssuranceAcquirerPhase.LocalReady
    return
  let peer = streams.peerForIdentity(target.ed25519)
  if peer.error == NodeError.None:
    if owner.usedBytes > owner.policy.bytes:
      owner.pause(streams, clock, AssuranceAcquirerPhase.Choosing)
      return
    let bytes = uint64(owner.replyLimit)
    if owner.usedRequests >= owner.policy.requests or bytes > owner.policy.bytes-owner.usedBytes:
      owner.pause(streams, clock, AssuranceAcquirerPhase.Choosing)
      return
    let started = streams.request(peer.value, owner.request, owner.replyLimit)
    if started.error in [NodeError.Unavailable, NodeError.LimitExceeded]: return
    if started.error != NodeError.None:
      bump(owner.failed)
      owner.nextTarget(streams, clock)
      return
    inc owner.usedRequests
    owner.usedBytes += bytes
    bump(owner.attempted)
    owner.network = started.value
    owner.fetching = true
    owner.fetchStarted = clock
    owner.phase = AssuranceAcquirerPhase.Fetching
    return
  if owner.usedDials >= owner.policy.dials:
    owner.pause(streams, clock, AssuranceAcquirerPhase.Choosing)
    return
  let endpoint = validatorEndpoint(array[128, byte](target.metadata))
  if endpoint.error != EndpointError.None:
    bump(owner.failed)
    owner.nextTarget(streams, clock)
    return
  let dial = streams.beginPeerConnection(target.ed25519, endpoint.value)
  if dial.error == DialError.Unavailable: return
  if dial.error != DialError.None:
    bump(owner.failed)
    owner.nextTarget(streams, clock)
    return
  inc owner.usedDials
  owner.dial = dial.value
  owner.dialKey = target.ed25519
  owner.dialing = true
  owner.closingDial = false
  owner.phase = AssuranceAcquirerPhase.Connecting

proc submit*(owner: var AssuranceAcquirer, services: var Services,
    streams: var NodeService, clock: MonoTime, now: AssuranceTime): bool {.raises.} =
  ## CPU arbitration admits at most one closed job; staging aliases and detached input wrappers retire inside Services before publication.
  if not owner.policy.ready or owner.active or not services.stateProofAvailable: return false
  let storage = services.assuranceStorageInfo
  if not storage.opened or storage.faulted: return false
  if owner.phase == AssuranceAcquirerPhase.Idle:
    let started = services.beginAssurancePlanning(streams.localIdentity, owner.policy.planning)
    if started.error == StateProofAdmissionError.Busy: return false
    if started.error != StateProofAdmissionError.None:
      bump(owner.failed)
      owner.pause(streams, clock, AssuranceAcquirerPhase.Idle)
      return true
    owner.resetRound(clock)
    owner.proof = started.value
    owner.proofStarted = clock
    owner.active = true
    owner.cancelled = false
    owner.phase = AssuranceAcquirerPhase.Planning
    return true
  if owner.phase notin [AssuranceAcquirerPhase.ProbeReady, AssuranceAcquirerPhase.Ready,
      AssuranceAcquirerPhase.LocalReady]: return false
  if not services.assurancePlanningCurrent(owner.plan):
    owner.dropPlan(streams)
    return true
  if not owner.prepared:
    if not owner.prepare():
      bump(owner.failed)
      owner.advance(streams, clock, false)
      return true
  if (clock-owner.roundStarted).inMilliseconds >= owner.policy.roundTimeout:
    owner.pause(streams, clock, owner.phase)
    return true
  if owner.phase == AssuranceAcquirerPhase.LocalReady:
    let started = services.beginNetworkRead(owner.request)
    if started.error == StateProofAdmissionError.Busy: return false
    if started.error != StateProofAdmissionError.None:
      bump(owner.failed)
      owner.nextTarget(streams, clock)
      return true
    owner.proof = started.value
    owner.phase = AssuranceAcquirerPhase.LocalReading
  else:
    let restoring = owner.phase == AssuranceAcquirerPhase.ProbeReady
    let started = if restoring:
      services.beginAssuranceProbe(streams.localIdentity, owner.selected.core,
          owner.selected.localOrdinal, now, owner.policy.acquisition)
    else:
      services.beginAssuranceAcquisition(streams.localIdentity, owner.selected.core,
          owner.selected.localOrdinal, owner.raw, now, owner.policy.acquisition)
    if started.error == AssuranceStorageStartError.Busy: return false
    if started.error != AssuranceStorageStartError.None:
      bump(owner.failed)
      owner.advance(streams, clock, false)
      return true
    owner.proof = started.value
    owner.raw = @[] # The worker owns its independently copied transcript before this caller buffer retires.
    owner.phase = if restoring: AssuranceAcquirerPhase.Probing else: AssuranceAcquirerPhase.Retaining
  owner.proofStarted = clock
  owner.active = true
  owner.cancelled = false
  true

proc close*(owner: var AssuranceAcquirer, services: var Services, streams: var NodeService) =
  ## Only an exact owned CPU lease may be joined; the native parent retains requested physical dial/frame retirement after logical teardown.
  if owner.active and services.stateProofActive(owner.proof): services.stopStateProofs()
  owner.active = false
  owner.cancelled = false
  owner.proof = default(ProofWorkerTicket)
  owner.cancelNetwork(streams)
  owner.retireDial(streams, true)
  owner.dialing = false
  owner.closingDial = false
  owner.dial = default(DialTicket)
  owner.plan = default(AssuranceFetchPlan)
  owner.clearCoordinate()
  owner.policy = default(AssuranceAcquisitionPolicy)
  owner.phase = AssuranceAcquirerPhase.Idle
