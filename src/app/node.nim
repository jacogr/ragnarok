# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable application node host manages inbound replies and bounded checked outbound reads through exact Services leases.
## Close this host before retiring Services storage; peer claims never select local finality.
import std/[assertions, monotimes, times]
import ./services
import ./preimage_followup
import ./work_dispatch
import ./work_exchange
import ./work_distribution
import ./assurance_distribution
import ./[audit_distribution, initial_audit]
import ./[judgment_distribution, forced_audit]
import ../jamnp-s/judgment_receipt
import ./audit_state
import ../jamnp-s/audit_validation
import ./assurance_broadcast
import ./audit_acquisition
import ../jamnp-s/[audit_registry, audit_evaluation]
import ./assurance_acquirer
import ../jamnp-s/assurance_record
import ../codec/assurances
import ../jamnp-s/work_signer
import ../quic/address
import ../jamnp-s/work_recovery
import ./proof/worker
import ./[audit_branches, candidate, chain, preparation_worker]
import "./current/block/input" as current_block_input
import ../codec/[block_codec, header]
import ../jamnp-s/[node as node_streams, connections, read_stream, read_client, read_validation,
    report_cache, preimage_cache, preimage_announcement, preimage_gossip, admission,
    ticket_packet, ticket_validation, ticket_pool, ticket_forwarding, ticket_origin]
import ../chain/[provider, genesis]
import ../codec/state/[safrole, consensus, service_values, requests]
import ../codec/[bounded, tickets]

type
  CheckedRequestIdentity = ref object ## Host-only retained namespace prevents stale tickets matching a reopened or foreign host.
    marker: uint8
  CheckedRequestTicket* = object ## The namespace and nonwrapping serial bind acquisition and verification to one host operation.
    owner: nil CheckedRequestIdentity
    serial: uint64
  CheckedRequestStart* = object ## Admission failures grant no network or worker collection authority.
    case status: NodeError
    of None: ticket: CheckedRequestTicket
    else: discard # Default/refused admission contains only its reason.
  CheckedRequestPhase* {.pure.} = enum ## A complete network reply can wait for a foreign canonical worker without exposing bytes.
    Idle, Receiving, Waiting, Verifying, Done
  CheckedCompletionKind* {.pure.} = enum ## Only Completed exposes a whole verification result, whose own failure tag remains guarded.
    Uninitialized, Pending, Completed, Cancelled, TimedOut, Interrupted, NetworkFailure,
    AdmissionFailure
  CheckedRequestCompletion* = object ## No cancellation, transport or admission failure carries a checked response prefix.
    case status: CheckedCompletionKind
    of Completed: response: ReadVerificationResult[CheckedReadReply]
    of NetworkFailure: networkReason: ReadError
    of AdmissionFailure: admissionReason: ReadVerificationError
    else: discard # Pending/default/lifecycle failures have no payload.
  SourceStamp = object ## Fixed local source facts survive exclusive worker access without ARC aliases.
    head, finalized: array[32, byte]
    now: StateTime
  AuditBranchIngressPolicy* = object ## The operator bounds CE128 bytes, full-block preparation and independent branch retention.
    ready: bool
    verification: ReadVerificationLimits
    input: CurrentBlockInputLimits
    candidate: CurrentCandidateLimits
    storage: AuditBranchLimits
  BranchAttempt = object ## A bounded cooldown prevents one untrusted leaf from monopolizing the worker.
    hash: genesis.BlockHash
    retry: MonoTime
  BranchIngress = object ## Stable native preparation input and exact checked/worker control stay on the node.
    policy: AuditBranchIngressPolicy
    request: CheckedRequestTicket
    ticket: PreparationTicket
    input: CurrentBlockInput
    id: CurrentBlockInputId
    checking, preparing: bool
    reply: CheckedReadReply
    remaining, peer, cursor: int
    parent: genesis.BlockHash
    attempts: array[32, BranchAttempt]
  ApplicationNode* = object ## Noncopyable host/native ownership borrows one stable Services address through explicit close.
    opened, pending, cancelled, epochHeld: bool
    services: nil ptr Services
    streams: NodeService
    workerTicket: ProofWorkerTicket
    readTicket: NodeReadTicket
    pendingRequest: ReadRequest
    stamp: SourceStamp
    checkedIdentity: nil CheckedRequestIdentity
    checkedNext: uint64
    checkedPhase: CheckedRequestPhase
    checkedNetwork: NodeRequestTicket
    checkedPeer: NodePeer
    checkedWorker: ProofWorkerTicket
    checkedRequest: ReadRequest
    checkedLimits: ReadVerificationLimits
    checkedWire: seq[byte]
    checkedOutcome: CheckedRequestCompletion
    checkedCancel: CheckedCompletionKind
    checkedStarted: MonoTime
    preferChecked, preferFetch, preferPreimage: bool
    preimages: PreimageFollowups
    gossip: PreimageGossip
    work: WorkDispatcher
    exchange: WorkExchangeDispatcher
    audits: AuditDispatcher
    initialAudits: InitialAudits
    branchIngress: BranchIngress
    preferInitialAudits, preferBranchIngress: bool
    auditRetentionFloor: uint64
    forcedAudits: ForcedAudits
    preferForcedAudits: bool
    judgments: JudgmentDispatcher
    preferJudgments: bool
    preferAudits: bool
    auditAcquirer: AuditAcquisition
    preferAuditAcquirer: bool
    assurances: AssuranceDispatcher
    preferAssurances: bool
    acquisition: AssuranceAcquirer
    preferAcquisition: bool
    broadcaster: AssuranceBroadcaster
    preferBroadcast: bool
    distribution: WorkDistributionDispatcher
    preferDistribution: bool
    preferWork, preferExchange: bool
    reports: ReportCache
    tickets: PendingTicketPool
    forwarding: TicketForwarding
    connectivityApplied: StateTime
    origins: TicketOrigins
    producing, productionContextReady: bool
    productionWorker: ProofWorkerTicket
    productionContext: array[32, byte]
    productionKeyVersion, generated: uint64
    productionAttempt, productionLimit: int
    lastProduced: NetworkTicketResult[CheckedNetworkTicket]
proc `=copy`*(destination: var ApplicationNode, source: ApplicationNode) {.error.}
  ## Copying the host would duplicate a worker ticket and move nested native callback addresses.
proc `=dup`*(source: ApplicationNode): ApplicationNode {.error.}
  ## Initialization cannot create another owner of the same borrowed Services/native lifetime.
proc `=wasMoved`*(owner: var ApplicationNode) {.nodestroy, requires: not owner.opened.} =
  ## Only explicit joined/retired hosts may move their child storage.
  `=wasMoved`(owner.streams)
  `=wasMoved`(owner.workerTicket)
  `=wasMoved`(owner.checkedIdentity)
  `=wasMoved`(owner.checkedWorker)
  `=wasMoved`(owner.checkedWire)
  `=wasMoved`(owner.checkedOutcome)
  `=wasMoved`(owner.reports)
  `=wasMoved`(owner.tickets)
  `=wasMoved`(owner.forwarding)
  `=wasMoved`(owner.origins)
  `=wasMoved`(owner.productionWorker)
  `=wasMoved`(owner.lastProduced)
  `=wasMoved`(owner.preimages)
  `=wasMoved`(owner.gossip)
  `=wasMoved`(owner.work)
  `=wasMoved`(owner.exchange)
  `=wasMoved`(owner.auditAcquirer)
  `=wasMoved`(owner.forcedAudits)
  `=wasMoved`(owner.initialAudits)
  `=wasMoved`(owner.branchIngress)
  `=wasMoved`(owner.judgments)
  `=wasMoved`(owner.audits)
  `=wasMoved`(owner.assurances)
  `=wasMoved`(owner.acquisition)
  `=wasMoved`(owner.broadcaster)
  `=wasMoved`(owner.distribution)
  `=wasMoved`(owner.checkedPeer)
  owner.opened = false
  owner.pending = false
  owner.cancelled = false
  owner.epochHeld = false
  owner.services = nil
  owner.readTicket = default(NodeReadTicket)
  owner.stamp = default(SourceStamp)
proc requireClosed(owner: ApplicationNode) {.requires: not owner.opened.} =
  ## Native contexts and borrowed Services storage must be retired before destruction.
  discard
proc `=destroy`*(owner: ApplicationNode) =
  ## Destruction neither abandons an active CPU lease nor silently joins unrelated Services work.
  requireClosed(owner)
  `=destroy`(owner.streams)
  `=destroy`(owner.workerTicket)
  `=destroy`(owner.checkedIdentity)
  `=destroy`(owner.checkedWorker)
  `=destroy`(owner.checkedWire)
  `=destroy`(owner.checkedOutcome)
  `=destroy`(owner.reports)
  `=destroy`(owner.tickets)
  `=destroy`(owner.forwarding)
  `=destroy`(owner.origins)
  `=destroy`(owner.productionWorker)
  `=destroy`(owner.lastProduced)
  `=destroy`(owner.preimages)
  `=destroy`(owner.gossip)
  `=destroy`(owner.work)
  `=destroy`(owner.exchange)
  `=destroy`(owner.auditAcquirer)
  `=destroy`(owner.forcedAudits)
  `=destroy`(owner.initialAudits)
  `=destroy`(owner.branchIngress)
  `=destroy`(owner.judgments)
  `=destroy`(owner.audits)
  `=destroy`(owner.assurances)
  `=destroy`(owner.acquisition)
  `=destroy`(owner.broadcaster)
  `=destroy`(owner.distribution)
  `=destroy`(owner.checkedPeer)
func isOpen*(owner: ApplicationNode): bool =
  ## Default and explicitly closed hosts grant no peer/read authority.
  owner.opened
proc configureWork*(owner: var ApplicationNode, policy: WorkDispatchPolicy): bool =
  ## Explicit activation installs bounded CPU dispatch before enabling native work selectors.
  if not owner.opened: return false
  owner.work.configure(owner.streams, policy)
proc configureWorkExchange*(owner: var ApplicationNode, policy: WorkExchangePolicy,
    certificate, privateKey: string): bool =
  ## Signed sharing is separately optional; private setup is bound to this host's actual authenticated public identity before enabling CE134.
  if not owner.opened or not policy.valid or owner.exchange.configured: return false
  let services = owner.services
  if services == nil: return false
  let identity = owner.streams.localIdentity
  if services[].workSigningConfigured:
    if not services[].workSignerMatches(identity, policy.storageLimits): return false
  else:
    let configured = services[].configureWorkSigner(certificate, privateKey, identity,
        policy.storageLimits)
    if configured.error != WorkSigningSetupError.None: return false
  if not services[].availabilityReadsMatch(policy.servingLimits):
    if not services[].configureAvailabilityReads(policy.servingLimits): return false
  owner.exchange.configure(owner.streams, policy)
proc configureAssuranceAcquisition*(owner: var ApplicationNode,
    policy: AssuranceAcquisitionPolicy): bool =
  ## Explicit activation requires an independently installed healthy archive; only polling with a supplied Common Era clock admits acquisition jobs.
  if not owner.opened: return false
  let services = owner.services
  if services == nil: return false
  owner.acquisition.configure(services[], owner.streams, policy)
func acquiredAssuranceShards*(owner: ApplicationNode): uint64 =
  ## Actual retained worker completions grant no signing or block-admission authority.
  owner.acquisition.acquired
func probedAssuranceShards*(owner: ApplicationNode): uint64 =
  ## Count real collected existing-record proof and durability checks, independently of new acquisition or signing authority.
  owner.acquisition.probed
func attemptedAssuranceRequests*(owner: ApplicationNode): uint64 =
  ## Count admitted remote requests, preserving observable default-off behavior.
  owner.acquisition.attempted
func assuranceAcquisitionPhase*(owner: ApplicationNode): AssuranceAcquirerPhase =
  ## Detached progress remains available during another canonical worker lease.
  owner.acquisition.phase
func assuranceDemandConnections*(owner: ApplicationNode): int =
  ## Closing owned acquisition dials remain charged until native retirement.
  owner.acquisition.demandConnections
func isValidator*(owner: ApplicationNode): bool =
  ## Only the actual open native host's authenticated topology can select validator-only optional startup.
  owner.opened and owner.streams.isValidator
proc configureAssuranceSigner*(owner: var ApplicationNode, certificate, privateKey: string): bool =
  ## Explicit startup imports a private signer only against this open host's actual bound TLS identity.
  if not owner.opened: return false
  let services = owner.services
  if services == nil: return false
  let identity = owner.streams.localIdentity
  if services[].assuranceSigningConfigured: return services[].assuranceSigningMatches(identity)
  services[].configureAssuranceSigner(certificate, privateKey, identity).error ==
      WorkSigningSetupError.None
proc configureAssuranceBroadcast*(owner: var ApplicationNode,
    policy: AssuranceBroadcastPolicy): bool =
  ## Explicit outgoing setup requires the independently installed archive and actual TLS-matched signer.
  if not owner.opened: return false
  let services = owner.services
  if services == nil: return false
  owner.broadcaster.configure(services[], owner.streams, policy)
func assuranceBroadcastPhase*(owner: ApplicationNode): AssuranceBroadcastPhase =
  ## Detached scalar progress grants no signature or canonical inclusion authority.
  owner.broadcaster.phase
func attemptedAssuranceBroadcasts*(owner: ApplicationNode): uint64 =
  ## Count actual queued CE141 requests independently from receipt and shard acquisition.
  owner.broadcaster.attempted
func acknowledgedAssuranceBroadcasts*(owner: ApplicationNode): uint64 =
  ## Only complete remote FINs count as acknowledged delivery.
  owner.broadcaster.acknowledged
proc beginAuditAcquisition*(owner: var ApplicationNode, policy: AuditAcquisitionPolicy,
    id: AuditOriginId, ordinal: int, clock: MonoTime): bool =
  ## Explicit optional foreground work uses a private Services selector; no caller report/state or validity bit enters this controller.
  if not owner.opened: return false
  if owner.forcedAudits.ownsAcquisition: return false
  owner.auditAcquirer.begin(policy, id, ordinal, clock)
func auditAcquisitionBusy*(owner: ApplicationNode): bool =
  ## Native retirement remains observable after an evaluation completes; re-admission waits for every exact control to drain.
  owner.auditAcquirer.busy
func auditAcquisitionPhase*(owner: ApplicationNode): AuditAcquisitionPhase =
  ## Fixed lifecycle observations remain available while the worker leases private full state.
  owner.auditAcquirer.phase
func acquiredAuditInfo*(owner: ApplicationNode): AuditEvaluationInfo {.requires: owner.auditAcquirer.phase ==
    AuditAcquisitionPhase.Complete.} =
  ## Actual source-free observations grant no separate signing capability.
  owner.auditAcquirer.evaluationInfo
proc cancelAuditAcquisition*(owner: var ApplicationNode) =
  ## Exact cancellation never interrupts an unrelated foreign worker lease.
  let services = owner.services
  if services != nil: owner.auditAcquirer.cancel(services[], owner.streams)
proc configureForcedAudits*(owner: var ApplicationNode, policy: ForcedAuditPolicy): bool =
  ## Enable automatic original-key participation after receipt and signer setup.
  let services = owner.services
  if not owner.opened or services == nil: return false
  owner.forcedAudits.configure(services[], owner.streams, owner.judgments, policy)

proc configureJudgmentReceipt*(owner: var ApplicationNode, policy: JudgmentReceiptPolicy): bool =
  ## Explicit full-state private retention must precede native judgment activation; omission never enables CE145.
  let services = owner.services
  if not owner.opened or services == nil or not services[].stateProofAvailable or not services[].auditRetentionConfigured: return false
  owner.judgments.configure(owner.streams, policy)
func receivedJudgments*(owner: ApplicationNode): uint64 =
  ## Count whole acknowledged qualified uploads independently of their record count.
  owner.judgments.received
func pendingForcedAudits*(owner: ApplicationNode): int =
  ## Negative receipt can require auditing a previously unseen report without a CE144 declaration.
  owner.judgments.pendingCount
proc pendingForcedAudit*(owner: ApplicationNode, ordinal: int): RetainedJudgment {.requires: ordinal >=
    0 and ordinal < owner.judgments.pendingCount.} =
  ## Source-free original record and private host selector expose neither execution state nor report truth.
  owner.judgments.pendingAt(ordinal)
func retainedJudgmentCount*(owner: ApplicationNode): int =
  ## Fixed ledger occupancy includes independently qualified conflicting original signed claims.
  owner.judgments.judgmentCount
proc retainedJudgmentAt*(owner: ApplicationNode, ordinal: int): QualifiedJudgment {.requires: ordinal >=
    0 and ordinal < owner.judgments.judgmentCount.} =
  ## Return one immutable original signed record after whole receipt succeeded.
  owner.judgments.judgmentAt(ordinal)
proc configureAuditReceipt*(owner: var ApplicationNode, policy: AuditReceiptPolicy): bool =
  ## A real bounded managed verifier and retained intent pool must exist before native CE144 selection is enabled.
  if not owner.opened: return false
  owner.audits.configure(owner.streams, policy)
func auditBranchIngressPolicy*(verification: ReadVerificationLimits,
    input: CurrentBlockInputLimits, candidate: CurrentCandidateLimits,
    storage: AuditBranchLimits): AuditBranchIngressPolicy =
  ## One bounded CE128 reply is retained at a time. The full transition still applies its own exact limits.
  if not storage.valid or uint64(verification.blocks) notin 1'u64..64'u64 or
      uint64(verification.wireBytes) notin 5'u64..uint64(MaxReadReplyBytes) or
      uint64(input.blockBytes) == 0 or input.discoverAncestors:
    return default(AuditBranchIngressPolicy)
  AuditBranchIngressPolicy(ready: true, verification: verification, input: input,
      candidate: candidate, storage: storage)
proc configureAuditBranchIngress*(owner: var ApplicationNode,
    policy: AuditBranchIngressPolicy): bool =
  ## Keep this independent retention feature opt-in and bound to the opened Services lifetime.
  let services = owner.services
  if not owner.opened or services == nil or not policy.ready or owner.branchIngress.policy.ready:
    return false
  if not services[].configureAuditBranches(policy.storage): return false
  owner.branchIngress.policy = policy
  true
proc configureInitialAudits*(owner: var ApplicationNode, policy: InitialAuditPolicy): bool =
  ## Enable automatic production only on an open validator with managed CE144 receipt.
  let services = owner.services
  if not owner.opened or services == nil or not owner.audits.configured or
      not owner.forcedAudits.configured: return false
  owner.initialAudits.configure(services[], owner.streams, policy)
func initialAuditDeclarationCount*(owner: ApplicationNode): int =
  ## Count retained local obligations separately from incoming declarations.
  owner.initialAudits.declarationCount
func initialAuditDeclaration*(owner: ApplicationNode,
    index: int): InitialAuditDeclaration {.requires:
    index >= 0 and index < owner.initialAudits.declarationCount.} =
  ## Return a detached copy of the signed local declaration and its selected cores.
  owner.initialAudits.declarationAt(index)
func receivedAuditAnnouncements*(owner: ApplicationNode): uint64 =
  ## Count wholly authenticated uploads acknowledged through their original live native ticket.
  owner.audits.received
func pendingAuditAnnouncements*(owner: ApplicationNode): int =
  ## Distinct original declarations retain their obligations across later positive information.
  owner.audits.pendingCount
proc pendingAuditAnnouncement*(owner: ApplicationNode,
    ordinal: int): CheckedAuditAnnouncement {.requires: ordinal >= 0 and ordinal <
    owner.audits.pendingCount.} =
  ## Source-free immutable intent metadata grants neither private judgment nor finality authority.
  owner.audits.pendingAt(ordinal)
proc configureAssuranceReceipt*(owner: var ApplicationNode, policy: AssuranceReceiptPolicy): bool =
  ## Independently optional bounded CE141 receipt enables no archive, private signer or outgoing assurance schedule.
  if not owner.opened: return false
  owner.assurances.configure(owner.streams, policy)
func receivedAssurances*(owner: ApplicationNode): uint64 =
  ## Count real retained fresh incoming candidates whose native reply accepted FIN.
  owner.assurances.received
func pendingAssurances*(owner: ApplicationNode): int =
  ## Expanded original validator positions remain unadmitted block candidates.
  owner.assurances.pendingCount
proc pendingAssurance*(owner: ApplicationNode, ordinal: int): Assurance {.requires: ordinal >= 0 and
    ordinal < owner.assurances.pendingCount.} =
  ## Return an owned candidate only; block construction must sort and freshly apply its post-judgment rules.
  owner.assurances.pendingAt(ordinal)
proc configureWorkDistribution*(owner: var ApplicationNode, policy: WorkDistributionPolicy): bool =
  ## Independently optional receipt/delivery installs bounded managed consumers before enabling CE135.
  if not owner.opened: return false
  owner.distribution.configure(owner.streams, policy)
func workDeliveryPhase*(owner: ApplicationNode): WorkDeliveryPhase =
  ## Fixed delivery state grants no claim that every configured validator acknowledged.
  owner.distribution.deliveryPhase
func workDeliveryAcknowledgments*(owner: ApplicationNode): uint64 =
  ## Actual remote FIN responses are separate from local credential collection and self-retention.
  owner.distribution.acknowledged
func workDeliveryAttempts*(owner: ApplicationNode): uint64 =
  ## Observe admitted native requests independently from remote success.
  owner.distribution.attempted
func workDeliveryRefusals*(owner: ApplicationNode): uint64 =
  ## Offline, invalid endpoint and transport refusals do not count as delivered reports.
  owner.distribution.refused
func workDeliveryDemandConnections*(owner: ApplicationNode): int =
  ## Observe exact controller-owned dial reservations, including busy or closing connections.
  owner.distribution.demandConnections
func workDeliveryRounds*(owner: ApplicationNode): uint64 =
  ## A finished bounded round may contain refused/unavailable recipients.
  owner.distribution.rounds
func receivedWorkGuarantees*(owner: ApplicationNode): uint64 =
  ## Count actual fresh retained incoming CE135 acknowledgments, separately from locally collected credentials.
  owner.distribution.received
func pendingWorkGuarantees*(owner: ApplicationNode): int =
  ## Detached candidates remain observable through foreign worker leases.
  owner.distribution.pendingCount
func pendingWorkGuaranteeBytes*(owner: ApplicationNode): int =
  ## Exact retained payload bytes follow the explicitly configured local capacity.
  owner.distribution.pendingBytes
proc pendingWorkGuarantee*(owner: ApplicationNode, ordinal: int): seq[byte] {.requires:
    ordinal >= 0 and ordinal < owner.distribution.pendingCount.} =
  ## Candidate bytes grant no fresh block/assurer admission authority.
  owner.distribution.pendingPayload(ordinal)
func workExchangePhase*(owner: ApplicationNode): WorkExchangePhase =
  ## Fixed controller state remains observable through canonical/private-key worker leases.
  owner.exchange.phase
func receivedWorkContributions*(owner: ApplicationNode): uint64 =
  ## Count independently computed incoming CE134 responses accepted by the live transport.
  owner.exchange.received
func collectedWorkGuarantees*(owner: ApplicationNode): uint64 =
  ## A collected guarantee still requires fresh inclusion qualification and CE135 delivery.
  owner.exchange.collected
proc configureWorkAcquisition*(owner: var ApplicationNode, policy: WorkAcquisitionPolicy): bool =
  ## Optional CE133 fetch participation requires an explicitly configured work dispatcher and independent network ceilings.
  if not owner.opened: return false
  owner.work.configureAcquisition(policy)
proc configureWorkRecovery*(owner: var ApplicationNode, policy: WorkRecoveryPolicy): bool =
  ## Explicit original-assurer fallback policies are fixed before any work session is admitted.
  if not owner.opened: return false
  owner.work.configureRecovery(policy)
func workPhase*(owner: ApplicationNode): WorkDispatchPhase =
  ## Observe detached lifecycle without borrowing the retained result.
  owner.work.phase
func acceptedWork*(owner: ApplicationNode): uint64 =
  ## Successful refinement/transport acknowledgments are distinct from report inclusion.
  owner.work.accepted
func completedWork*(owner: ApplicationNode): WorkSessionToken {.requires: owner.work.phase ==
    WorkDispatchPhase.Ready.} =
  ## Downstream report processing uses the original Services session.
  owner.work.completed
proc releaseWork*(owner: var ApplicationNode): bool =
  ## Explicit downstream consumption allows the next bounded submission.
  let services = owner.services
  if services == nil: return false
  if owner.exchange.phase != WorkExchangePhase.Idle:
    discard owner.exchange.release(services[], owner.streams)
  owner.work.release(services[])
func ticketProductionActive*(owner: ApplicationNode): bool =
  ## Scalar observation grants no cancellation or key access.
  owner.producing
func generatedTickets*(owner: ApplicationNode): uint64 =
  ## Count fresh checked candidates successfully retained for local proxy work or queued for remote first-step delivery.
  owner.generated
func originatedTickets*(owner: ApplicationNode): uint64 =
  ## Observe complete CE131 transport acknowledgments without canonical inclusion authority.
  owner.origins.acknowledged
func ticketOriginActive*(owner: ApplicationNode): int =
  ## At most two exact Native first-step requests are charged independently of CPU work.
  owner.origins.sending
proc lastProducedTicket*(owner: ApplicationNode): NetworkTicketResult[CheckedNetworkTicket] =
  ## Return the last complete cryptographic outcome, which is separate from fresh-clock/pool/delivery admission and contains no secret or source owner.
  owner.lastProduced
func ticketForwardingCount*(owner: ApplicationNode): int =
  ## Observe retained proxy intents without borrowing canonical state.
  owner.forwarding.len
func ticketForwardingActive*(owner: ApplicationNode): int =
  ## Exact native requests remain separately bounded within the shared read quota.
  owner.forwarding.sending
func forwardedTickets*(owner: ApplicationNode): uint64 =
  ## Count complete transport acknowledgments without claiming canonical inclusion.
  owner.forwarding.acknowledged
func cachedReportCount*(owner: ApplicationNode): int =
  ## Detached cache statistics are safe while any canonical worker owns the graph.
  owner.reports.len
func cachedReportBytes*(owner: ApplicationNode): int =
  ## Logical immutable cache wire bytes exclude native buffers and transient response copies.
  owner.reports.byteLength
func cachedPreimageCount*(owner: ApplicationNode): int =
  ## Observe detached hash-checked blob count independently of canonical graph leases.
  owner.preimages.cachedCount
func cachedPreimageBytes*(owner: ApplicationNode): int =
  ## Logical framed cache usage includes the four-byte CE143 prefix.
  owner.preimages.cachedBytes
func pendingPreimageCount*(owner: ApplicationNode): int =
  ## Queued and active automatic retrievals have a separate fixed eight-intent capacity.
  owner.preimages.pendingCount
func preimageGossipCount*(owner: ApplicationNode): int =
  ## Fixed detached possession intents do not imply inclusion or remote adoption.
  owner.gossip.len
func preimageGossipSending*(owner: ApplicationNode): bool =
  ## Observe detached native announcement ownership without reading canonical state.
  owner.gossip.sending
func deliveredPreimageGossip*(owner: ApplicationNode): uint64 =
  ## Count successful exact bare-FIN deliveries, independently of content/state authority.
  owner.gossip.deliveredCount
func pendingTicketCount*(owner: ApplicationNode): int =
  ## Detached prospective GP ticket count grants no canonical inclusion authority.
  owner.tickets.len
proc pendingTicketAt*(owner: ApplicationNode, ordinal: int): CheckedNetworkTicket {.requires: ordinal >=
    0 and ordinal < owner.tickets.len.} =
  ## Only complete sealed proof metadata leaves retention; no mutable pool row or worker ticket escapes.
  owner.tickets.ticketAt(ordinal)
proc localPort*(owner: ApplicationNode): uint16 =
  ## Observe detached native listener state without a canonical graph alias.
  if owner.opened: owner.streams.localPort else: 0'u16
proc peerCount*(owner: ApplicationNode): int =
  ## Expose authenticated logical reservations for ordinary service diagnostics.
  if owner.opened: owner.streams.peerCount else: 0
proc peerAt*(owner: ApplicationNode, ordinal: int): NodeResult[NodePeer] =
  ## The nested actor's generation token still requires live-source checks.
  owner.streams.peerAt(ordinal)
proc beginPeerConnection*(owner: var ApplicationNode, identity: StateEdKey,
    endpoint: NetworkEndpoint): DialResult =
  ## Explicit source-free connection demand keeps actual TLS identity pinning and the native node's fixed engine limits.
  owner.streams.beginPeerConnection(identity, endpoint)
proc source*(owner: ApplicationNode, peer: NodePeer): NodeResult[NodeClaims] =
  ## Detached remote claims carry no canonical adoption or finality authority.
  owner.streams.source(peer)
proc request*(owner: var ApplicationNode, peer: NodePeer, request: ReadRequest,
    maximum = ByteLimit(MaxReadReplyBytes)): NodeResult[NodeRequestTicket] =
  ## Fixed outbound request facts may be queued while a Services worker owns the unrelated canonical graph.
  owner.streams.request(peer, request, maximum)
proc takeReply*(owner: var ApplicationNode, ticket: NodeRequestTicket): ReadClientResult =
  ## Complete detached bytes remain untrusted; the host must acquire any state/proof validation gate separately.
  owner.streams.takeReply(ticket)
proc cancelRequest*(owner: var ApplicationNode, ticket: NodeRequestTicket): bool =
  ## Cancelling an outbound network stream never cancels a Services canonical worker lease.
  owner.streams.cancelRequest(ticket)
proc requestLive*(owner: ApplicationNode, ticket: NodeRequestTicket): bool =
  ## Exact peer generation and serial bind outbound activity independently of canonical CPU ownership.
  owner.streams.requestLive(ticket)
func error*(started: CheckedRequestStart): NodeError =
  ## Observe admission without granting a ticket from a failed/default start.
  started.status
func value*(started: CheckedRequestStart): CheckedRequestTicket {.requires: started.status ==
    NodeError.None.} =
  ## Only accepted bounded network acquisition grants the exact host generation.
  started.ticket
func kind*(completed: CheckedRequestCompletion): CheckedCompletionKind =
  ## Observe lifecycle failure without extracting any accepted body.
  completed.status
func value*(completed: CheckedRequestCompletion): ReadVerificationResult[
    CheckedReadReply] {.requires: completed.status == CheckedCompletionKind.Completed.} =
  ## The inner verifier still distinguishes complete checked success from semantic/proof failure.
  completed.response
func networkError*(completed: CheckedRequestCompletion): ReadError {.requires: completed.status ==
    CheckedCompletionKind.NetworkFailure.} =
  ## Transport failure reasons are carried only by an actual failed collection.
  completed.networkReason
func admissionError*(completed: CheckedRequestCompletion): ReadVerificationError {.requires: completed.status ==
    CheckedCompletionKind.AdmissionFailure.} =
  ## Trusted-source capture refusals remain distinct from later cryptographic failures.
  completed.admissionReason
func checkedLive*(owner: ApplicationNode, ticket: CheckedRequestTicket): bool =
  ## Complete uncollected operations occupy capacity; default, foreign, stale and reopened tickets cannot match.
  owner.opened and owner.checkedPhase != CheckedRequestPhase.Idle and ticket.owner != nil and
    ticket.owner == owner.checkedIdentity and ticket.serial == owner.checkedNext
func checkedPhase*(owner: ApplicationNode, ticket: CheckedRequestTicket): CheckedRequestPhase =
  ## Phase is scalar and may be observed while a foreign worker owns canonical ARC graphs.
  if owner.checkedLive(ticket): owner.checkedPhase else: CheckedRequestPhase.Idle
proc clearChecked(owner: var ApplicationNode) =
  ## Retire detached buffers and exact tickets only after matching worker collection/join or before admission.
  owner.checkedPhase = CheckedRequestPhase.Idle
  owner.checkedNetwork = default(NodeRequestTicket)
  owner.checkedPeer = default(NodePeer)
  owner.checkedWorker = default(ProofWorkerTicket)
  owner.checkedRequest = default(ReadRequest)
  owner.checkedLimits = default(ReadVerificationLimits)
  owner.checkedWire = @[]
  owner.checkedOutcome = default(CheckedRequestCompletion)
  owner.checkedCancel = CheckedCompletionKind.Uninitialized
  owner.checkedStarted = default(MonoTime)
proc requestChecked*(owner: var ApplicationNode, peer: NodePeer, request: ReadRequest,
    limits: ReadVerificationLimits): CheckedRequestStart =
  ## Reserve one complete acquisition-to-verification operation; native framing applies the same hard byte ceiling.
  if not owner.opened: return CheckedRequestStart(status: NodeError.Unavailable)
  if owner.checkedPhase != CheckedRequestPhase.Idle: return CheckedRequestStart(
      status: NodeError.Unavailable)
  if not request.valid: return CheckedRequestStart(status: NodeError.InvalidConfig)
  let minimum = request.minimumReplyBytes
  if uint64(limits.wireBytes) < minimum or uint64(limits.wireBytes) > uint64(MaxReadReplyBytes):
    return CheckedRequestStart(status: NodeError.InvalidConfig)
  if owner.checkedNext == high(uint64): return CheckedRequestStart(status: NodeError.Exhausted)
  let admitted = owner.streams.request(peer, request, limits.wireBytes)
  if admitted.error != NodeError.None: return CheckedRequestStart(status: admitted.error)
  inc owner.checkedNext
  owner.checkedNetwork = admitted.value
  owner.checkedPeer = peer
  owner.checkedRequest = request
  owner.checkedLimits = limits
  owner.checkedStarted = getMonoTime()
  owner.checkedPhase = CheckedRequestPhase.Receiving
  CheckedRequestStart(status: NodeError.None, ticket: CheckedRequestTicket(
    owner: owner.checkedIdentity, serial: owner.checkedNext))
proc announcePreimage*(owner: var ApplicationNode, peer: NodePeer, service: ServiceIndex,
    blob: CheckedReadReply, limits: ReadVerificationLimits): CheckedRequestStart =
  ## Publish only retained full-hash content requested in local canonical state, to an authenticated validator recipient.
  if not owner.opened or owner.services == nil: return CheckedRequestStart(
      status: NodeError.Unavailable)
  if not blob.valid or blob.kind != ReadKind.Preimage: return CheckedRequestStart(
      status: NodeError.InvalidConfig)
  if not owner.streams.isValidator(peer): return CheckedRequestStart(
      status: NodeError.InvalidSource)
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return CheckedRequestStart(
      status: NodeError.Unavailable)
  let notice = announcementRequest(service, blob.preimageHash, RequestLength(uint32(
      blob.preimageByteLength)))
  if notice.error != ReadError.None: return CheckedRequestStart(status: NodeError.InvalidConfig)
  if services[].chainView.requested(notice.value) != ReadError.None:
    return CheckedRequestStart(status: NodeError.InvalidSource) # This bounded account/history query retires before native admission.
  if owner.checkedPhase != CheckedRequestPhase.Idle: return CheckedRequestStart(
      status: NodeError.Unavailable)
  if owner.preimages.retain(blob) != PreimageCacheError.None:
    return CheckedRequestStart(status: NodeError.LimitExceeded)
  owner.requestChecked(peer, notice.value.request, limits)
proc cancelChecked(owner: var ApplicationNode, reason: CheckedCompletionKind) =
  ## Admitted CPU work keeps its exact lease until collection, even when cancellation follows Done.
  if owner.checkedPhase == CheckedRequestPhase.Verifying:
    if owner.checkedCancel == CheckedCompletionKind.Uninitialized:
      owner.checkedCancel = reason
      let services = owner.services
      if services != nil: discard services[].cancelStateProof(owner.checkedWorker)
  else:
    if owner.checkedPhase == CheckedRequestPhase.Receiving:
      discard owner.streams.cancelRequest(owner.checkedNetwork)
    owner.checkedWire = @[]
    owner.checkedOutcome = CheckedRequestCompletion(status: reason)
    owner.checkedPhase = CheckedRequestPhase.Done
proc cancelChecked*(owner: var ApplicationNode, ticket: CheckedRequestTicket): bool =
  ## Cancellation is scoped to this checked operation and never joins/cancels a foreign Services job.
  if not owner.checkedLive(ticket): return false
  owner.cancelChecked(CheckedCompletionKind.Cancelled)
  true
proc takeChecked*(owner: var ApplicationNode, ticket: CheckedRequestTicket): CheckedRequestCompletion =
  ## A pending result grants no body and cannot retire an admitted lease; one terminal collection frees capacity.
  if not owner.checkedLive(ticket): return default(CheckedRequestCompletion)
  if owner.checkedPhase != CheckedRequestPhase.Done:
    return CheckedRequestCompletion(status: CheckedCompletionKind.Pending)
  result = move(owner.checkedOutcome)
  owner.clearChecked()
proc stageBranchInput(ingress: var BranchIngress, services: Services,
    blockOwner: OwnedBlock, now: StateTime): bool =
  ## Detach one exact GP body, with independently retained older headers in descending order.
  let component = blockOwner.blockHeader.value
  let fields = readHeader(component).value.owner.headerInfo.value.unsigned
  if uint32(fields.slot) > uint32(now): return false
  let parent = genesis.BlockHash(array[32, byte](fields.parent))
  let source = services.auditBranchParent(parent)
  if source.error != ApplicationChainError.None: return false
  let view = source.value.chainView
  var ancestors: seq[OwnedHeader] = @[]
  let retained = view.validationHeaderCount
  for index in 1..<retained:
    # The exact parent itself is already bound by CurrentBlockInput.
    ancestors.add(view.validationHeaderAt(ValidationHeaderIndex(retained-1-index)).header)
  let size = blockOwner.blockInfo.value.consumed
  if uint64(size) > uint64(ingress.policy.input.blockBytes): return false
  var wire = newSeq[byte](size)
  if blockOwner.encodeOwnedBlock(wire).error != FrameError.None: return false
  let started = services.beginAuditBranchInput(ingress.input, parent, ByteLimit(uint64(size)),
      ancestors, ingress.policy.input, ingress.policy.candidate)
  if started.error != CurrentBlockInputError.None: return false
  ingress.id = started.value
  if ingress.input.append(ingress.id, wire, true) != CurrentBlockInputError.None:
    discard ingress.input.cancel(ingress.id)
    return false
  ingress.parent = parent
  true
proc pollBranchIngress(owner: var ApplicationNode, services: var Services) =
  ## Collect exact native ownership before retaining a certificate or advancing the detached batch.
  if not owner.branchIngress.policy.ready: return
  if owner.branchIngress.preparing:
    let done = services.collectPreparation(owner.branchIngress.ticket)
    if done.kind == PreparationCompletionKind.Uninitialized and services.preparationActive: return
    owner.branchIngress.preparing = false
    discard owner.branchIngress.input.cancel(owner.branchIngress.id)
    if done.kind != PreparationCompletionKind.CurrentCompleted or
        done.currentValue.error != CurrentBlockInputError.None:
      owner.branchIngress.remaining = 0
    else:
      let accepted = services.retainAuditBranch(done.currentValue.value)
      if accepted notin [AuditBranchError.None, AuditBranchError.Duplicate]:
        owner.branchIngress.remaining = 0
    if owner.branchIngress.remaining == 0:
      owner.branchIngress.reply = default(CheckedReadReply)
  if owner.branchIngress.checking:
    var ticket = owner.branchIngress.request
    let completed = owner.takeChecked(ticket)
    if completed.kind == CheckedCompletionKind.Pending: return
    owner.branchIngress.checking = false
    if completed.kind == CheckedCompletionKind.Completed and
        completed.value.error == ReadVerificationError.None:
      owner.branchIngress.reply = completed.value.value
      owner.branchIngress.remaining = owner.branchIngress.reply.blockCount
proc submitBranchIngress(owner: var ApplicationNode, services: var Services,
    clock: MonoTime, now: StateTime): bool {.raises.} =
  ## Schedule one native transition or one bounded CE128 retrieval per arbitration turn.
  if not owner.branchIngress.policy.ready or owner.branchIngress.checking or
      owner.branchIngress.preparing or not services.preparationAvailable:
    return false
  if owner.branchIngress.remaining > 0:
    let index = owner.branchIngress.remaining-1
    dec owner.branchIngress.remaining
    let hash = owner.branchIngress.reply.hashAt(index)
    if services.knownAuditBlock(hash): return false
    if not owner.branchIngress.stageBranchInput(services, owner.branchIngress.reply.blockAt(index), now):
      owner.branchIngress.remaining = 0
      owner.branchIngress.reply = default(CheckedReadReply)
      return false
    let started = services.beginAuditBranchPreparation(owner.branchIngress.input,
        owner.branchIngress.id, owner.branchIngress.parent)
    if started.error != PreparationError.None:
      discard owner.branchIngress.input.cancel(owner.branchIngress.id)
      owner.branchIngress.remaining = 0
      owner.branchIngress.reply = default(CheckedReadReply)
      return false
    owner.branchIngress.ticket = started.value
    owner.branchIngress.preparing = true
    return true
  owner.branchIngress.reply = default(CheckedReadReply)
  if owner.checkedPhase != CheckedRequestPhase.Idle: return false
  let count = owner.streams.peerCount
  if count == 0: return false
  let ordinal = owner.branchIngress.peer mod count
  owner.branchIngress.peer = (ordinal+1) mod count
  let peer = owner.streams.peerAt(ordinal)
  if peer.error != NodeError.None: return false
  let claims = owner.streams.source(peer.value)
  if claims.error != NodeError.None: return false
  for leaf in claims.value.claims.leaves:
    # Peer leaves nominate downloads only. Hash linkage and the complete STF run before retention.
    if uint32(leaf.slot) > uint32(now): continue
    let hash = genesis.BlockHash(array[32, byte](leaf.hash))
    var cooling = false
    for attempt in owner.branchIngress.attempts:
      if attempt.retry > clock and array[32, byte](attempt.hash) == array[32, byte](hash):
        cooling = true
        break
    if cooling or services.knownAuditBlock(hash): continue
    var payload = default(array[37, byte])
    for index in 0..<32: payload[index] = array[32, byte](hash)[index]
    payload[32] = 1 # Descending inclusive, with a bounded number of older candidate ancestors.
    payload[33] = byte(uint64(owner.branchIngress.policy.verification.blocks))
    let request = decodeReadRequest(ReadKind.Blocks, payload).value
    var limits = owner.branchIngress.policy.verification
    let started = owner.requestChecked(peer.value, request, limits)
    if started.error != NodeError.None: return false
    let row = owner.branchIngress.cursor
    owner.branchIngress.attempts[row] = BranchAttempt(hash: hash,
        retry: clock+initDuration(seconds = 5))
    owner.branchIngress.cursor = (row+1) mod owner.branchIngress.attempts.len
    owner.branchIngress.request = started.value
    owner.branchIngress.checking = true
    return true
  false
proc receiveChecked(owner: var ApplicationNode, clock: MonoTime) =
  ## Bound detached waiting time even while an unrelated Services job holds the graph gate.
  if owner.checkedPhase in [CheckedRequestPhase.Receiving, CheckedRequestPhase.Waiting,
      CheckedRequestPhase.Verifying]:
    if clock < owner.checkedStarted or (clock-owner.checkedStarted).inMilliseconds >= 120000:
      owner.cancelChecked(CheckedCompletionKind.TimedOut)
  if owner.checkedPhase != CheckedRequestPhase.Receiving: return
  let completed = owner.streams.takeReply(owner.checkedNetwork)
  if completed.error == ReadError.Unavailable: return # Exact FIN has not arrived; retain native input accounting and ticket.
  if completed.error != ReadError.None:
    discard owner.streams.cancelRequest(owner.checkedNetwork)
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.NetworkFailure,
      networkReason: completed.error)
    owner.checkedPhase = CheckedRequestPhase.Done
    return
  owner.checkedWire = completed.value.bytes # Fresh detached bounded bytes outlive real native stream retirement.
  owner.checkedNetwork = default(NodeRequestTicket)
  owner.checkedPhase = CheckedRequestPhase.Waiting
proc collectChecked(owner: var ApplicationNode) =
  ## Collect only this exact CPU generation; a foreign Done operation cannot be retired by this ticket.
  if owner.checkedPhase != CheckedRequestPhase.Verifying: return
  let services = owner.services
  if services == nil: return
  let phase = services[].stateProofPhase
  if phase in [ProofWorkerPhase.Queued, ProofWorkerPhase.Running]: return
  let completed = services[].collectStateProof(owner.checkedWorker)
  if owner.checkedCancel != CheckedCompletionKind.Uninitialized:
    owner.checkedOutcome = CheckedRequestCompletion(status: owner.checkedCancel)
  elif completed.kind == ProofWorkerCompletionKind.ReadVerified:
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.Completed,
      response: completed.verifiedReadValue)
    let checked = completed.verifiedReadValue
    if checked.error == ReadVerificationError.None and checked.value.kind == ReadKind.Report:
      discard owner.reports.remember(checked.value) # Local retention refusal cannot turn a complete checked read into failed delivery.
    if checked.error == ReadVerificationError.None and checked.value.kind == ReadKind.Preimage:
      discard owner.preimages.retain(checked.value) # Public checked reads can populate detached content without canonical mutation.
    if checked.error == ReadVerificationError.None and checked.value.kind ==
        ReadKind.PreimageAnnouncement:
      let notice = decodeAnnouncement(checked.value.request.payload)
      if notice.error == ReadError.None and owner.preimages.has(notice.value):
        discard owner.gossip.offer(owner.streams, notice.value,
            owner.checkedPeer) # An already acknowledged publisher recipient needs no duplicate gossip.
  else:
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.Interrupted)
  owner.checkedWorker = default(ProofWorkerTicket)
  owner.checkedPhase = CheckedRequestPhase.Done
proc submitChecked(owner: var ApplicationNode): bool {.raises.} =
  ## Admit after temporary trusted-source capture retires; Busy leaves one bounded detached reply waiting.
  if owner.checkedPhase != CheckedRequestPhase.Waiting: return false
  let services = owner.services
  if services == nil: return false
  let admitted = services[].beginReadVerification(owner.checkedRequest, owner.checkedWire,
    owner.checkedLimits)
  if admitted.error == StateProofAdmissionError.Busy: return false
  owner.checkedWire = @[]
  if admitted.error == StateProofAdmissionError.None:
    owner.checkedWorker = admitted.value
    owner.checkedPhase = CheckedRequestPhase.Verifying
  elif admitted.error == StateProofAdmissionError.QueryFailure:
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.AdmissionFailure,
      admissionReason: admitted.verificationError)
    owner.checkedPhase = CheckedRequestPhase.Done
  else:
    owner.checkedOutcome = CheckedRequestCompletion(status: CheckedCompletionKind.Interrupted)
    owner.checkedPhase = CheckedRequestPhase.Done
  owner.preferFetch = true
  owner.preferChecked = false # An inbound responder gets first opportunity after this verification turn.
  true
proc stage(owner: var ApplicationNode, config: ConnectionConfig, limits: SafroleStateConfig,
    now: StateTime): NodeError =
  ## Every temporary Services view retires on return, before the host can submit native CPU work.
  let services = owner.services
  if services == nil: return NodeError.Unavailable
  let view = services[].chainView
  let head = view.bestBlock
  let finalized = view.finalizedBlock
  if head.error != GenesisError.None: return NodeError.InvalidSource
  if finalized.error != GenesisError.None: return NodeError.NoFinality
  if head.value.slot > uint64(uint32(now)): return NodeError.InvalidSource
  let opened = owner.streams.open(config, view, limits)
  if opened != NodeError.None: return opened
  owner.connectivityApplied = now # Initial installation is the first actual connectivity application.
  owner.stamp = SourceStamp(head: array[32, byte](head.value.blockHash),
    finalized: array[32, byte](finalized.value.blockHash), now: now)
  NodeError.None
proc open*(owner: var ApplicationNode, services: var Services, config: ConnectionConfig,
    limits: SafroleStateConfig, now: StateTime): NodeError =
  ## Bind exactly one stable full-state Services owner; missing finality never falls back to best.
  if owner.opened or config.protocol.len == 0 or config.protocol != services.nodeProtocol:
    return NodeError.InvalidConfig # Full-state networking uses the original configured genesis, never a mutable best head.
  if not services.stateProofAvailable: return NodeError.Unavailable
  owner.services = addr services
  let opened = owner.stage(config, limits, now)
  if opened != NodeError.None:
    owner.streams.close()
    owner.services = nil
    return opened # Failed factories retain neither a Services borrow nor native callbacks.
  owner.epochHeld = false
  owner.preimages.reset()
  owner.preferFetch = false
  owner.preferWork = true
  owner.preferExchange = true
  owner.preferDistribution = true
  owner.preferJudgments = true
  owner.preferForcedAudits = true
  owner.preferAudits = true
  owner.preferInitialAudits = true
  owner.preferBranchIngress = true
  owner.auditRetentionFloor = 0
  owner.preferAuditAcquirer = true
  owner.preferAssurances = true
  owner.preferPreimage = false
  owner.producing = false
  owner.productionContextReady = false
  owner.productionWorker = default(ProofWorkerTicket)
  owner.lastProduced = default(NetworkTicketResult[CheckedNetworkTicket])
  owner.productionAttempt = 0
  owner.productionLimit = 0
  owner.productionKeyVersion = 0
  owner.generated = 0
  owner.clearChecked()
  owner.checkedIdentity = CheckedRequestIdentity(marker: 1)
  owner.checkedNext = 0
  owner.preferChecked = false
  owner.opened = true
  NodeError.None
proc refresh(owner: var ApplicationNode, now: StateTime): NodeError =
  ## Capture changed source metadata only under the graph gate, without retaining any map/header owner.
  let services = owner.services
  if services == nil: return NodeError.Unavailable
  let view = services[].chainView
  let head = view.bestBlock
  let finalized = view.finalizedBlock
  if head.error != GenesisError.None: return NodeError.InvalidSource
  if finalized.error != GenesisError.None: return NodeError.NoFinality
  if uint32(now) < uint32(owner.stamp.now) or head.value.slot > uint64(uint32(now)):
    return NodeError.InvalidSource # Epoch transition delay uses explicit local JAM time, never remote slots.
  let headHash = array[32, byte](head.value.blockHash)
  let finalizedHash = array[32, byte](finalized.value.blockHash)
  if headHash == owner.stamp.head and finalizedHash == owner.stamp.finalized:
    if not owner.epochHeld or uint32(now) == uint32(owner.stamp.now):
      owner.stamp.now = now
      return NodeError.None # Clock ticks alone cannot broadcast the unchanged header; retry only a held epoch gate.
  let previousEpoch = owner.streams.connectivityEpoch
  let advanced = owner.streams.advance(view, now)
  if advanced.error != NodeError.None: return advanced.error
  if owner.streams.connectivityEpoch != previousEpoch:
    owner.connectivityApplied = now # Same-epoch source updates never restart either ticket delay.
  owner.epochHeld = advanced.value == EpochUpdate.Held
  owner.stamp = SourceStamp(head: headHash, finalized: finalizedHash, now: now)
  NodeError.None
proc clearJob(owner: var ApplicationNode) =
  ## Drop host-only tickets only after matching collection/join or confirmed stale retirement.
  owner.pending = false
  owner.cancelled = false
  owner.workerTicket = default(ProofWorkerTicket)
  owner.readTicket = default(NodeReadTicket)
  owner.pendingRequest = default(ReadRequest)
proc close*(owner: var ApplicationNode) =
  ## Cancel/join only this host's exact worker before retiring native callbacks and the Services borrow.
  owner.streams.stop()
  let services = owner.services
  if owner.producing and services != nil:
    if services[].cancelStateProof(owner.productionWorker):
      services[].stopStateProofs() # Only successful exact cancellation permits joining a secret-borrowing job.
  owner.producing = false
  owner.productionWorker = default(ProofWorkerTicket)
  owner.productionContextReady = false
  owner.lastProduced = default(NetworkTicketResult[CheckedNetworkTicket])
  if owner.pending and services != nil:
    if services[].cancelStateProof(owner.workerTicket):
      services[].stopStateProofs() # Successful exact-ticket cancellation proves this serialized host owns the joined job.
  if owner.checkedPhase == CheckedRequestPhase.Verifying and services != nil:
    if services[].cancelStateProof(owner.checkedWorker):
      services[].stopStateProofs() # Joined teardown belongs only to a successfully matched checked-request ticket.
  if services != nil:
    if owner.branchIngress.preparing and services[].cancelPreparation(owner.branchIngress.ticket):
      services[].stopPreparation()
    discard owner.branchIngress.input.cancel(owner.branchIngress.id)
    owner.forcedAudits.close(services[], owner.streams)
    owner.initialAudits.close(services[], owner.streams)
    owner.judgments.close(services[], owner.streams)
    owner.auditAcquirer.close(services[], owner.streams)
    owner.audits.close(services[], owner.streams)
    owner.assurances.close(services[], owner.streams)
    owner.acquisition.close(services[], owner.streams)
    owner.broadcaster.close(services[], owner.streams)
    owner.distribution.close(services[], owner.streams)
    owner.exchange.close(services[], owner.streams)
    owner.work.close(services[], owner.streams)
    owner.preimages.close(services[], owner.streams)
  owner.branchIngress.policy = default(AuditBranchIngressPolicy)
  owner.branchIngress.checking = false
  owner.branchIngress.preparing = false
  owner.branchIngress.request = default(CheckedRequestTicket)
  owner.branchIngress.ticket = default(PreparationTicket)
  owner.branchIngress.reply = default(CheckedReadReply)
  owner.branchIngress.remaining = 0
  owner.branchIngress.peer = 0
  owner.branchIngress.cursor = 0
  owner.branchIngress.attempts = default(array[32, BranchAttempt])
  owner.gossip.close(owner.streams)
  owner.forwarding.close(owner.streams)
  owner.origins.close(owner.streams)
  owner.streams.close()
  owner.clearChecked()
  owner.reports.clear()
  owner.tickets.clear()
  owner.checkedIdentity = nil
  owner.clearJob()
  owner.opened = false
  owner.epochHeld = false
  owner.services = nil
  owner.stamp = default(SourceStamp)
proc serveCached(owner: var ApplicationNode, task: NodeReadTask): bool =
  ## A hit needs no canonical graph or worker, but still requires the native ticket's exact method/hash binding.
  case task.request.kind
  of ReadKind.Report:
    let retained = owner.judgments.findReport(task.request)
    if retained.error == ReadError.None:
      if owner.streams.respond(task.ticket, retained.value) != ReadError.None:
        discard owner.streams.reject(task.ticket)
      owner.preferChecked = true
      return true
    let found = owner.reports.find(task.request)
    if found.error != ReportCacheError.None: return false
    if owner.streams.respond(task.ticket, found.value) != ReadError.None:
      discard owner.streams.reject(task.ticket) # Output pressure cannot orphan a claimed cached request.
  of ReadKind.Preimage:
    let found = owner.preimages.find(task.request)
    if found.error != PreimageCacheError.None: return false
    if owner.streams.respond(task.ticket, found.value) != ReadError.None:
      discard owner.streams.reject(task.ticket) # Retained content has the same exact native ticket constraints.
  else: return false # Other methods require their canonical backend, never guessed cached state.
  owner.preferChecked = true
  true
proc serveDetached(owner: var ApplicationNode) =
  ## Inspect one cached kind per turn; alternate when both are populated and preserve original miss deadlines.
  let hasReports = owner.reports.len > 0 or owner.judgments.retainedReportCount > 0
  let hasPreimages = owner.preimages.cachedCount > 0
  if not hasReports and not hasPreimages: return
  let preimage = hasPreimages and (not hasReports or owner.preferPreimage)
  owner.preferPreimage = not preimage
  let selected = if preimage: ReadKind.Preimage else: ReadKind.Report
  let task = owner.streams.takeRead(selected)
  if task.error != NodeError.None: return
  if owner.serveCached(task.value): return
  if not owner.streams.deferRead(task.value.ticket):
    discard owner.streams.reject(task.value.ticket) # Failed revocation never leaves taken work without an owner.
proc dispatchGossip(owner: var ApplicationNode, clock: MonoTime) =
  ## Retire every temporary canonical request lookup in this activation before the host can admit its next CPU worker.
  let services = owner.services
  if services == nil: return
  let candidate = owner.gossip.candidate()
  if candidate.valid:
    let notice = candidate.notice
    if not owner.preimages.has(notice) or services[].chainView.requested(notice) != ReadError.None:
      discard owner.gossip.reject(owner.streams, candidate) # No canonical alias is retained across dispatch or worker admission.
    else:
      discard owner.gossip.dispatch(owner.streams, candidate,
          clock) # Accepted topology and live recipient generation are checked at the actual send.
proc refreshTickets(owner: var ApplicationNode, now: StateTime) =
  ## Source aliases retire here before another CPU job can borrow the shared ARC input context.
  if owner.tickets.len == 0: return
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return
  let selected = services[].currentTicketSource()
  if selected.error == NetworkTicketError.None:
    discard owner.tickets.advance(selected.value, now)
proc finishTicket(owner: var ApplicationNode,
    outcome: NetworkTicketResult[CheckedNetworkTicket], now: StateTime): bool =
  ## Completed proof work still needs fresh clock/context/stream eligibility before retention or acknowledgment.
  if outcome.error notin [NetworkTicketError.None, NetworkTicketError.AlreadyIncluded]: return false
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return false
  let source = services[].currentTicketSource()
  if source.error != NetworkTicketError.None: return false
  if not source.value.allowsTime(now, owner.streams.connectivityEpoch): return false
  if outcome.error == NetworkTicketError.AlreadyIncluded: return true # Genuine verified finalized inclusion needs no new pending owner.
  if owner.tickets.advance(source.value, now) != TicketPoolError.None: return false
  let retained = owner.tickets.retain(outcome.value, now)
  if retained == TicketPoolError.AlreadyIncluded: return true
  if retained notin [TicketPoolError.None, TicketPoolError.Duplicate]: return false
  if outcome.value.delivery == TicketDelivery.Proxy:
    if owner.forwarding.advance(owner.streams, source.value, now, owner.connectivityApplied):
      discard owner.forwarding.offer(outcome.value) # Admission after the forwarding window may still supply a valid pending block input.
  true
proc dispatchTickets(owner: var ApplicationNode, now: StateTime, clock: MonoTime) =
  ## Retire all selected-source aliases before another canonical worker can be submitted.
  if owner.forwarding.len == 0: return
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return
  let selected = services[].currentTicketSource()
  if selected.error != NetworkTicketError.None:
    owner.forwarding.close(owner.streams)
    return
  if owner.forwarding.advance(owner.streams, selected.value, now, owner.connectivityApplied):
    discard owner.forwarding.dispatch(owner.streams, now, clock)
proc finishProduction(owner: var ApplicationNode, outcome: NetworkTicketResult[
    CheckedNetworkTicket], now: StateTime): bool =
  ## A genuine generated proof still needs current finalized context/inclusion and the original first-step window.
  if outcome.error != NetworkTicketError.None: return false
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return false
  if services[].ticketSigningVersion != owner.productionKeyVersion: return false
  let source = services[].currentTicketSource()
  if source.error != NetworkTicketError.None: return false
  if outcome.value.contextHash != source.value.contextHash or source.value.includes(
      outcome.value.identifier): return false
  if not owner.origins.advance(owner.streams, source.value, now,
      owner.connectivityApplied): return false
  let local = owner.streams.localIdentity
  if array[32, byte](outcome.value.proxy) == array[32, byte](local):
    if owner.tickets.advance(source.value, now) != TicketPoolError.None: return false
    let retained = owner.tickets.retain(outcome.value, now)
    if retained notin [TicketPoolError.None, TicketPoolError.Duplicate]: return false
    if owner.forwarding.advance(owner.streams, source.value, now, owner.connectivityApplied):
      return owner.forwarding.offer(outcome.value) # Self-proxies skip CE131 and keep the independent later CE132 delay.
    return false
  owner.origins.offer(outcome.value)
proc dispatchOrigins(owner: var ApplicationNode, now: StateTime, clock: MonoTime) =
  ## Fresh-source staging aliases retire before another shared CPU activation can borrow signer/source storage.
  if owner.origins.len == 0: return
  let services = owner.services
  if services == nil or not services[].stateProofAvailable: return
  let source = services[].currentTicketSource()
  if source.error != NetworkTicketError.None:
    owner.origins.close(owner.streams)
    return
  if owner.origins.advance(owner.streams, source.value, now, owner.connectivityApplied):
    discard owner.origins.dispatch(owner.streams, now, clock)
proc prepareProduction(owner: var ApplicationNode, now: StateTime): bool =
  ## Only scalar scheduling decisions escape selected-source capture; no source or signer alias survives admission.
  let services = owner.services
  if services == nil or not services[].hasTicketSigner or not services[].stateProofAvailable: return false
  if not owner.streams.isValidator: return false
  let source = services[].currentTicketSource()
  if source.error != NetworkTicketError.None: return false
  if not source.value.allowsTime(now, owner.streams.connectivityEpoch): return false
  let duration = source.value.epochLength
  let first = uint64(uint32(owner.connectivityApplied))+uint64(max(duration div 60, 1'u32))
  let finish = uint64(source.value.epoch)*uint64(duration)+uint64(source.value.lotteryTail div 2)
  if uint64(uint32(now)) < first or uint64(uint32(now)) >= finish: return false
  if uint32(owner.connectivityApplied) div duration != source.value.epoch: return false
  let context = source.value.contextHash
  let version = services[].ticketSigningVersion
  if not owner.productionContextReady or owner.productionContext != context or
      owner.productionKeyVersion != version:
    owner.origins.close(owner.streams)
    owner.productionContext = context
    owner.productionKeyVersion = version
    owner.productionAttempt = 0
    owner.productionLimit = source.value.networkAttempts
    owner.productionContextReady = true
  owner.productionAttempt < owner.productionLimit
proc submitProduction(owner: var ApplicationNode, now: StateTime): bool {.raises.} =
  ## At most two epoch attempts share the existing worker; all staging activations retire before this exact submission.
  if owner.producing or not owner.prepareProduction(now): return false
  let services = owner.services
  if services == nil: return false
  assert owner.productionAttempt >= 0 and owner.productionAttempt < 2
  let admitted = services[].beginTicketProduction(owner.streams.localIdentity, now,
      owner.streams.connectivityEpoch, TicketAttempt(uint8(owner.productionAttempt)))
  if admitted.error != StateProofAdmissionError.None: return false
  owner.productionWorker = admitted.value
  owner.producing = true
  inc owner.productionAttempt # Failed native signing still consumes its bounded local attempt for this context/key configuration.
  true
proc beginIncoming(owner: var ApplicationNode, task: NodeReadTask,
    now: StateTime): bool {.raises.} =
  ## Each specialized admission retires staging aliases before its one exact worker can execute.
  let services = owner.services
  if services == nil: return false
  if task.request.kind in [ReadKind.TicketProxy, ReadKind.TicketDistribution]:
    let peer = task.ticket.sourcePeer
    if not owner.streams.isValidator or not owner.streams.isValidator(peer): return false
    let packet = decodeTicketPacket(task.request.payload)
    if packet.error != TicketPacketError.None: return false
    let delivery = if task.request.kind == ReadKind.TicketProxy: TicketDelivery.Proxy else: TicketDelivery.Distribution
    let recipient = TicketRecipient(local: owner.streams.localIdentity, peer: peer.identity,
        now: now, connectivityEpoch: owner.streams.connectivityEpoch, delivery: delivery)
    let admitted = services[].beginNetworkTicket(packet.value, recipient)
    if admitted.error != StateProofAdmissionError.None: return false
    owner.workerTicket = admitted.value
  else:
    let admitted = services[].beginNetworkRead(task.request)
    if admitted.error != StateProofAdmissionError.None: return false
    owner.workerTicket = admitted.value
  owner.readTicket = task.ticket
  owner.pendingRequest = task.request
  owner.preferFetch = true
  owner.preferChecked = true # Inbound semantic admission keeps existing arbitration with public checked reads and private content fetches.
  owner.pending = true
  owner.cancelled = false
  true
proc pollHost(owner: var ApplicationNode, clock: MonoTime, now: StateTime,
    maximumMs: range[0..1], assuranceClock: bool, assuranceNow: AssuranceTime): bool {.raises.} =
  ## Service detached native data during CPU work; capture/refresh only after the exclusive graph gate opens.
  if not owner.opened or owner.services == nil: return false
  let services = owner.services
  if services == nil: return false
  owner.broadcaster.beforePoll(services[], owner.streams, clock, assuranceClock, assuranceNow)
  owner.distribution.beforePoll(services[], owner.streams, now)
  if not owner.streams.poll(clock, maximumMs): return false
  owner.tickets.expire(now) # Host-only proof owners may retire while a different job holds immutable source/context aliases.
  owner.origins.expire(owner.streams, now)
  owner.origins.poll(owner.streams, clock)
  owner.forwarding.expire(owner.streams, now)
  owner.forwarding.poll(owner.streams, clock)
  owner.gossip.poll(owner.streams, clock)
  owner.preimages.poll(services[], owner.streams, clock)
  owner.work.poll(services[], owner.streams, clock, now)
  owner.exchange.poll(services[], owner.streams, clock)
  owner.judgments.poll(services[], owner.streams, owner.reports, clock)
  owner.auditAcquirer.poll(services[], owner.streams, clock)
  owner.forcedAudits.poll(services[], owner.streams, owner.judgments, owner.auditAcquirer, clock)
  owner.initialAudits.poll(services[], owner.streams, clock)
  if owner.initialAudits.canExpire and owner.forcedAudits.canExpire and owner.judgments.canExpire:
    # Advance all affected ownership together between exact worker admissions.
    let floor = services[].expireFinalizedAudits(owner.auditRetentionFloor)
    if floor > owner.auditRetentionFloor:
      let declarations = owner.initialAudits.expireBefore(floor)
      let pending = owner.judgments.expireBefore(floor)
      owner.forcedAudits.expireBefore(owner.streams, floor, declarations, pending)
      owner.audits.expireBefore(floor)
      owner.auditRetentionFloor = floor
  owner.audits.poll(services[], owner.streams, clock)
  owner.assurances.poll(services[], owner.streams, clock)
  owner.acquisition.poll(services[], owner.streams, clock)
  owner.broadcaster.poll(services[], owner.streams, clock)
  owner.distribution.poll(services[], owner.streams, owner.reports, clock, now)
  if owner.exchange.configured and owner.work.phase == WorkDispatchPhase.Ready:
    let completed = owner.work.completed
    let phase = services[].workSessionPhase(completed)
    if phase in [WorkSessionPhase.Empty, WorkSessionPhase.Retired]:
      discard owner.work.release(services[]) # A refused/timed-out downstream exchange must not strand the builder controller at Ready.
    else:
      discard owner.exchange.beginCompleted(services[], completed, clock)
  if owner.exchange.phase == WorkExchangePhase.Ready and owner.work.phase ==
      WorkDispatchPhase.Ready:
    discard owner.distribution.beginLocal(services[], owner.work.completed, clock)
  let acquired = owner.preimages.takeAcquired()
  if acquired.error == ReadError.None and owner.preimages.has(acquired.value):
    discard owner.gossip.offer(owner.streams, acquired.value) # Fresh state/possession checks remain required before transmission.
  owner.receiveChecked(clock)
  owner.collectChecked()
  owner.pollBranchIngress(services[])
  if not services[].stateProofAvailable: owner.serveDetached()
  if owner.producing:
    let phase = services[].stateProofPhase
    if phase in [ProofWorkerPhase.Queued, ProofWorkerPhase.Running]: return true
    if phase == ProofWorkerPhase.Done:
      let completed = services[].collectStateProof(owner.productionWorker)
      if completed.kind == ProofWorkerCompletionKind.TicketProduced:
        owner.lastProduced = completed.producedTicketValue
        if owner.finishProduction(completed.producedTicketValue, now):
          if owner.generated < high(uint64): inc owner.generated
    owner.producing = false
    owner.productionWorker = default(ProofWorkerTicket) # A stale/foreign completion cannot release another lease or expose a produced prefix.
  if owner.pending:
    if not owner.cancelled and not owner.streams.readLive(owner.readTicket):
      owner.cancelled = services[].cancelStateProof(owner.workerTicket)
    let phase = services[].stateProofPhase
    if phase in [ProofWorkerPhase.Queued, ProofWorkerPhase.Running]: return true
    if phase == ProofWorkerPhase.Done:
      let completed = services[].collectStateProof(owner.workerTicket)
      if completed.kind == ProofWorkerCompletionKind.TicketVerified and owner.streams.readLive(
          owner.readTicket):
        let accepted = owner.finishTicket(completed.verifiedTicketValue, now)
        if accepted:
          let reply = captureReadReply(owner.pendingRequest, [])
          if reply.error != ReadError.None:
            discard owner.streams.reject(owner.readTicket) # A failed frozen acknowledgment never exposes an empty default reply.
          elif owner.streams.respond(owner.readTicket, reply.value) != ReadError.None:
            discard owner.streams.reject(owner.readTicket) # Output pressure retires the exact claimed stream.
        else:
          discard owner.streams.reject(owner.readTicket) # Epoch/window/context failures expose no accepted ticket prefix or success FIN.
      elif completed.kind == ProofWorkerCompletionKind.ReadCompleted and
          completed.readValue.error == ReadError.None and owner.streams.readLive(owner.readTicket):
        let reply = completed.readValue.value
        var accepted = true
        if reply.effect == ReadEffect.FetchPreimage:
          let notice = decodeAnnouncement(owner.pendingRequest.payload)
          accepted = notice.error == ReadError.None
          if accepted:
            accepted = owner.preimages.enqueue(owner.streams, owner.readTicket.sourcePeer,
                notice.value, clock)
            if accepted and owner.preimages.has(notice.value):
              discard owner.gossip.offer(owner.streams,
                  notice.value) # Cached reception can announce a separately requested service namespace.
        if not accepted or owner.streams.respond(owner.readTicket, reply) != ReadError.None:
          discard owner.streams.reject(owner.readTicket) # Exhausted followup/output capacity never acknowledges unowned work.
      else:
        discard owner.streams.reject(owner.readTicket) # Cancellation/stale collection never emits a successful response prefix.
    else:
      discard owner.streams.reject(owner.readTicket) # External joined Services shutdown has already retired the old worker.
    owner.clearJob()
  if not services[].stateProofAvailable: return true # Foreign RPC/preparation/publication leases remain untouched.
  if owner.refresh(now) != NodeError.None: return false
  owner.refreshTickets(now) # All detached source aliases retire before any subsequent worker admission.
  owner.dispatchOrigins(now, clock)
  owner.dispatchTickets(now, clock) # Finality/context checks precede every actual proxy transmission.
  owner.dispatchGossip(clock) # The staging activation retires all canonical aliases before CPU admission.
  if assuranceClock and owner.preferBroadcast:
    if owner.broadcaster.submit(services[], owner.streams, clock, assuranceNow):
      owner.preferBroadcast = false
      return true
  owner.preferBroadcast = true # Timed signing alternates with acquisition and incoming work rather than monopolizing the shared worker.
  if assuranceClock and owner.preferAcquisition:
    if owner.acquisition.submit(services[], owner.streams, clock, assuranceNow):
      owner.preferAcquisition = false
      return true
  owner.preferAcquisition = true # A continuously missing archive alternates with ordinary incoming/read work.
  if owner.preferAuditAcquirer and owner.auditAcquirer.submit(services[], owner.streams, clock):
    owner.preferAuditAcquirer = false
    return true
  owner.preferAuditAcquirer = true # An active audit cannot monopolize the shared CPU pool.
  if owner.preferForcedAudits and owner.forcedAudits.submit(services[], owner.streams,
      owner.judgments, owner.auditAcquirer, owner.initialAudits, clock):
    owner.preferForcedAudits = false
    return true
  owner.preferForcedAudits = true
  if owner.preferJudgments and owner.judgments.submit(services[], owner.streams, owner.reports, clock):
    owner.preferJudgments = false
    return true
  owner.preferJudgments = true # Whole receipt shares fair bounded foreground turns with other managed CPU consumers.
  if owner.preferBranchIngress and owner.submitBranchIngress(services[], clock, now):
    owner.preferBranchIngress = false
    return true
  owner.preferBranchIngress = true
  if owner.preferInitialAudits and owner.initialAudits.submit(services[], owner.streams, clock):
    owner.preferInitialAudits = false
    return true
  owner.preferInitialAudits = true
  if owner.preferAudits and owner.audits.submit(services[], owner.streams, clock):
    owner.preferAudits = false
    return true
  owner.preferAudits = true # A continuous audit backlog alternates with other bounded managed CPU consumers.
  if owner.preferAssurances and owner.assurances.submit(services[], owner.streams, clock):
    owner.preferAssurances = false
    return true
  owner.preferAssurances = true # A continuous assurance backlog alternates with other ordinary CPU consumers.
  if owner.preferDistribution and owner.distribution.submit(services[], owner.streams, clock, now):
    owner.preferDistribution = false
    return true
  owner.preferDistribution = true # A continuously supplied CE135 queue alternates with other ordinary CPU consumers.
  if owner.preferExchange and owner.exchange.submit(services[], owner.streams, clock, now):
    owner.preferExchange = false
    return true
  owner.preferExchange = true # Other ordinary CPU admissions alternate with a continuous incoming sharing backlog.
  if owner.preferWork and owner.work.submit(services[], owner.streams, clock, now):
    owner.preferWork = false
    return true
  owner.preferWork = true # An intervening ordinary CPU admission prevents a continuous builder backlog monopolizing the worker.
  if owner.submitProduction(now): return true # Optional production consumes at most two turns per epoch/context, then ordinary read arbitration resumes.
  if owner.preferFetch and owner.preimages.submitWaiting(services[]):
    owner.preferFetch = false
    return true
  if owner.preferChecked and owner.submitChecked(): return true
  let request = owner.streams.takeReadExcept({ReadKind.Guarantee, ReadKind.Assurance,
      ReadKind.AuditAnnouncement, ReadKind.Judgment})
  if request.error != NodeError.None:
    if assuranceClock and owner.broadcaster.submit(services[], owner.streams, clock,
        assuranceNow): return true
    if assuranceClock and owner.acquisition.submit(services[], owner.streams, clock,
        assuranceNow): return true
    if owner.auditAcquirer.submit(services[], owner.streams, clock): return true
    if owner.judgments.submit(services[], owner.streams, owner.reports, clock): return true
    if owner.audits.submit(services[], owner.streams, clock): return true
    if owner.assurances.submit(services[], owner.streams, clock): return true
    if owner.distribution.submit(services[], owner.streams, clock, now): return true
    if owner.exchange.submit(services[], owner.streams, clock, now): return true
    if owner.work.submit(services[], owner.streams, clock, now): return true
    if not owner.submitChecked(): discard owner.preimages.submitWaiting(services[])
    return true
  if owner.serveCached(request.value): return true
  if not owner.beginIncoming(request.value, now):
    discard owner.streams.reject(request.value.ticket) # Busy/missing/invalid semantic admission never fabricates an empty successful response.
  true

proc poll*(owner: var ApplicationNode, clock: MonoTime, now: StateTime,
    maximumMs: range[0..1] = 1): bool {.raises.} =
  ## Existing hosts service transport and already-owned work without inventing Common Era retention time from a slot number.
  owner.pollHost(clock, now, maximumMs, false, AssuranceTime(0))
proc poll*(owner: var ApplicationNode, clock: MonoTime, now: StateTime,
    assuranceNow: AssuranceTime, maximumMs: range[0..1] = 1): bool {.raises.} =
  ## Validator hosts explicitly supply whole Common Era seconds separately from slots before new durable acquisition jobs are admitted.
  owner.pollHost(clock, now, maximumMs, true, assuranceNow)
