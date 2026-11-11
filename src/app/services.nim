# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable owner for optional listeners, telemetry and the configured canonical chain.
##
## Startup captures bounded chain input for the enabled consumers. Canonical startup
## shares the selected head with RPC so the listener and application begin from the
## same retained state version. A failed listener start rolls back earlier owners.
##
## The dispatcher borrows fields while this owner stays stable. Native callbacks must
## retire before listener destruction. After starting preparation, explicitly close
## to join before borrowed input or shared aliases retire. Detached reader snapshots
## retain their immutable state independently.
##
## Canonical state, optional listeners and worker admission have separate lifetimes.
## The startup anchor is captured before disk history can replace the selected head.
## It is detached trust metadata, not a newer best-head claim. Disk publication installs
## the confirmed durable successor after collection. Management continues to observe
## copied startup and OS data while canonical graph access is excluded.
##
## Full-state Jit startup owns one shared compiler runtime. The accumulation residency
## context retains four service/version/backend workers. Managed work completion passes
## the runtime through StateProofWorker and runInputRefinement to refinePackage.
## The package worker leaves the runtime unbound for one-item packages. It retains
## one source/policy cache across sequential items and retires before Done.
## Proof and preparation turns exclude each other through collection or join,
## including host-side ARC access to runtime anchors. stopPreparation preserves residency.
## Full close joins both consumers, drops accumulation workers, then closes the runtime.
##
## Authorization still uses a fresh one-shot prepared owner without a runtime. Nested
## refinement modules inherit the backend but construct their own prepared owners without
## a runtime. The JAMNP-S audit and work-sharing refinement adapters also use the default
## runtime argument. Those routes can request Jit and complete through checked execution.
##
## The runtime's four image credits cover both bound consumers. Four installed accumulation
## images can leave a package worker without a credit even with zero active invocations.
## This is permitted checked fallback; the credit count grants no consumer a fair share.
## Each prepared owner separately permits up to 64 MiB of idle baseline/private payload.
## Four resident accumulation owners and a package worker therefore have up to 320 MiB of
## such logical allowance, before prepared facts, source storage and live invocation memory.
## This is a policy sum, not an RSS bound or a promise that all slots become populated.
##
## Extending runtime availability requires a reviewed environment contract first. One
## stable owner must close the compiler only after all admitted consumers join. Separate
## leases must cover outer and nested prepared owners while an outer callback is suspended.
## The environment must assign aggregate prepared/source/scratch limits and an explicit
## competition policy across accumulation and package owners. Optional retention or native
## admission refusal must preserve checked results, gas, attempts and host-call order.
## Reserve each retained owner's share before cache admission and return it after storage
## retirement. An exhausted optional share can select one-shot preparation under the same
## mandatory resource limits or disable idle scratch retention. Nested owners need their
## own share while the outer prepared lease remains active. The current API has no such
## environment reservation or aggregate accounting; these are requirements for future wiring.
## Increasing image credits alone supplies neither aggregate byte accounting nor fairness.

import ../state/accumulation/residency
import ../codec/composite
import ../codec/work/digest
from ../pvm/step import PvmBackend, PreparationResult, PreparedCacheInfo, NativeRuntime,
    newNativeRuntime, start, close
import ../lib/logging

import std/[syncio, strutils, base64, assertions, monotimes, times]
import ../state/logical_continuation
import ./options
import ../jamnp-s/[alpn, chain_alpn]
import ../chain/network_identity
import ./node_logging
import ../rpc/light_source
import ./light/runtime as light_actor
import ./light/[head as light_head, policy as light_policy]
import ./checkpoint/[recovery as checkpoint_recovery, trust as checkpoint_trust]
import ./handoff
import ./current/handoff as current_handoff
import "./current/block/input" as current_block_input
import ./candidate
import "./block/input" as block_input
import ./preparation_worker
import ./collected/supplied/[plan as collected_supplied_plan, state as collected_supplied_state]
import ./logical/review as logical_review
import ./logical/proof as logical_proof
import ../state/account/review/plan as account_review_plan
import ./logical/checkpoint as logical_checkpoint
import ./frozen_supplied
import ../state/supplied/services as supplied_services
import ./logical/service_proof as logical_service_proof
import "./logical/export" as logical_export
import ./logical/source_export as logical_source_export
import "./logical/checkpoint/import" as logical_checkpoint_import
import ./logical/code as logical_code
import ./logical/code/proof as logical_code_proof
import ../state/code_availability
import ./full_logical_proof
import ./paged/logical_proof as paged_logical_proof
import ./logical/seed as logical_seed
import ../codec/state/composition as state_composition
import ../codec/composite
import ./current/logical as collected_logical
import ../state/parent/logical as parent_logical
import ../state/current/logical as current_logical
import ./proof/[query as proof_query, worker as proof_worker, network_read]
import ./proof/read_validation as verification_job
import ./proof/ticket_verification as ticket_job
import ./proof/ticket_production
import ./proof/assurance_storage
import ./proof/assurance_acquisition
import ./proof/assurance_signing
import ../jamnp-s/assurance_possession
from ../codec/assurances import AssuranceBits
import ../jamnp-s/[assurance_store, assurance_record]
import ./proof/work_submission as work_jobs
import ../jamnp-s/work_submission
import ../jamnp-s/work_recovery
from ../codec/state/safrole import StateValidatorIndex, StateValidator
import ../jamnp-s/work_stream
import ../jamnp-s/work_report
import ../jamnp-s/[work_signer, work_eligibility, work_sharing, sharing_wire, work_guarantee]
import ../jamnp-s/[availability_read, availability_store, guarantor_store, work_distribution]
import ../jamnp-s/assurance_distribution
import ../jamnp-s/assurance_fetch
import ../jamnp-s/assurance_schedule
import ../jamnp-s/[audit_context, audit_receipt, audit_origin, audit_registry, audit_evaluation,
    audit_recovery, audit_fetch, judgment_claim, judgment_receipt, judgment_source,
    audit_participation, audit_publication]
import ./[audit_state, audit_branches]
from ../jamnp-s/audit_validation import AuditProofLimits
from ../codec/disputes import JudgeIndex
from ../codec/owned import OwnershipError
from ../codec/work/report import ErasureRoot, CoreIndex
from ../state/availability/specifier import AvailabilityCommitment
import ../jamnp-s/availability_proof
from ../state/erasure/words import ErasureShardIndex
from ../state/computed/report import ComputedReportInfo, computedReportInfo, computedReportSource, value
from ../state/computed/guarantee import ComputedGuaranteeTranscript, ComputedGuaranteeError,
    computedGuaranteeReport, error, value
from ../jamnp-s/work_duty import WorkRecipient, WorkDutyLimits, WorkDuty, valid, activeAt, shardCount
from ../codec/work/package import PackageConfig, MaxBundleBytes
from ../codec/work/digest import Gas
import ../state/input_refinement
import "../state/import/justification" as work_imports
from ../codec/work/report import SegmentLookup
import ../bandersnatch/bandersnatch as bs
import ../codec/[tickets, header]
import ../codec/state/safrole
import ../jamnp-s/[ticket_packet, ticket_validation]
import ../jamnp-s/read_validation as read_verification
import ../jamnp-s/read_stream
import ../state/proof/[service as proof_service, plan as proof_plan, view as proof_view]
import ../state/trie_proof
import ./disk/[chain as disk_chain, worker as disk_worker]
import ./historical/[disk as historical_disk, context as historical_context]
import ./checkpoint/[identity as checkpoint_identity, transfer as checkpoint_transfer,
    session as checkpoint_session, worker as checkpoint_worker, file as checkpoint_file]
import ../codec/bounded
import ../crypto/primitives
import ../codec/[block_codec, header]
import ../codec/state/trie as state_trie
import ./chain as application_chain
import ../state/[store, disk_store]
import ../state/accumulation/[finalization as accumulation_finalization,
    completion as accumulation_completion, publication as accumulation_publication]
import ../state/accumulation/current/update as accumulation_current_update
import ../storage/file/repository as file_repository
import ../storage/node/[repository as node_repository, records as node_records]
import ../storage/[record_codec, database_identity]
import ../storage/managed/[repository as managed_repository, manifest as managed_manifest]
import ../storage/full/paged/store as full_paged_store
import ../storage/history/index as history_index
import ../chain/provider
import ../telemetry/[wire, client, chain]
import ../quic/transport
import "../jamnp-s/protocol"
import ../rpc/[server, protocol, proof_requests]
import ../chain/[parameters, genesis]
import ../ui/server
import ../management/[server, protocol]
import ../mcp/server
import ../mcp/protocol as mcp_protocol

type
  StateProofAdmissionError* {.pure.} = enum ## Admission grants a ticket only after capture and native submission succeed.
    Uninitialized, None, Closed, Busy, QueryFailure, WorkerFailure
  AssuranceStorageStartError* {.pure.} = enum ## Namespace startup has its own closed capture/worker alternatives and never grants possession or signing authority.
    Uninitialized, None, Closed, Unavailable, Busy, IdentityFailure, CaptureFailure, WorkerFailure
  AssuranceStorageStart* = object ## Only admitted full-state storage work exposes the exact shared-worker collection ticket.
    case status: AssuranceStorageStartError
    of None: ticket: ProofWorkerTicket
    of IdentityFailure: identityReason: NetworkIdentityError
    of CaptureFailure: captureReason: AssuranceStorageJobError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # No failed/default alternative retains a path, job or native owner.
  AssuranceAcquisitionStart* = object ## Accepted acquisition alone grants the exact shared-worker ticket; failure contains no selected-state or input alias.
    case status: AssuranceStorageStartError
    of None: ticket: ProofWorkerTicket
    of CaptureFailure: captureReason: AssuranceAcquisitionError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Closed, unavailable and busy starts cannot access the namespace or canonical graph.
  AssuranceWorkStart* = object ## Closed assurance planning or receipt owns only an exact shared-worker ticket; failed admission retains no source.
    case status: StateProofAdmissionError
    of None: ticket: ProofWorkerTicket
    of QueryFailure: captureReason: WorkJobError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Default/closed/busy starts contain no accepted job.
  AuditPlanningStart* = object ## Only admitted full-state audit work exposes an exact shared-worker ticket; failed starts retain no source.
    case status: StateProofAdmissionError
    of None: ticket: ProofWorkerTicket
    of QueryFailure: captureReason: WorkJobError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Default/closed/busy cannot expose an audit context or accepted input alias.
  AssuranceSigningStart* = object ## Only accepted native signing exposes a ticket; the caller provides a selection, never a purported possession proof or raw message.
    case status: AssuranceStorageStartError
    of None: ticket: ProofWorkerTicket
    of CaptureFailure: captureReason: AssuranceSigningJobError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Failed/default capture cannot expose a private key, source or signing lease.
  AssuranceStorageInfo* = object ## Host-owned cached accounting remains readable while a mutable namespace lease runs elsewhere.
    opened*, faulted*: bool
    records*, bytes*: uint64
    chain*: AssuranceChainId
  ReadVerificationStart* = object ## Bounded fresh verification shares the existing exact Services worker lease.
    case status: StateProofAdmissionError
    of None: ticket: ProofWorkerTicket
    of QueryFailure: verificationReason: ReadVerificationError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Closed/busy/default starts carry no job, graph or collection ticket.
  NetworkReadStart* = object ## Managed canonical reads use the same exclusive capacity but distinct read failure reasons.
    case status: StateProofAdmissionError
    of None: ticket: ProofWorkerTicket
    of QueryFailure: readReason: ReadError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Failed/default starts carry no graph, lease or native collection ticket.
  StateProofAdmission* = object ## Private guarded alternatives cannot forge a successful managed lease.
    case status: StateProofAdmissionError
    of None: ticket: ProofWorkerTicket
    of QueryFailure: queryReason: ProofQueryError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Closed/busy/default refusals expose no authority.

type
  NetworkTicketStart* = object ## Accepted admission alone grants the exact shared CPU ticket; capture retains genuine decoder/backend causes.
    case status: StateProofAdmissionError
    of None: ticket: ProofWorkerTicket
    of QueryFailure: captureReason: NetworkTicketResult[TicketSource]
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Closed/busy/default results own no stream, input or worker authority.

type
  TicketSignerConfiguration* = object ## Successful configuration has no extractable key; only genuine derivation failure carries a native cause.
    case status: TicketSignerError
    of KeyFailure: keyReason: bs.BsError
    else: discard # None denotes completed configuration without exposing its private signing owner.

type
  LogicalProofAdmissionError* {.pure.} = enum ## Capture provenance/resource failures remain distinct from managed worker/RPC admission.
    Uninitialized, None, Closed, Busy, CaptureFailure, AdmissionFailure
  LogicalProofAdmission* = object ## Only actual native submission grants an existing managed proof ticket.
    case status: LogicalProofAdmissionError
    of None: ticket: ProofWorkerTicket
    of CaptureFailure: captureReason: LogicalProofResult
    of AdmissionFailure: admissionReason: StateProofAdmission
    else: discard # Defaults, closed Services and active leases retain no query or ticket.

func error*(admission: LogicalProofAdmission): LogicalProofAdmissionError =
  ## Observe the selected capture or managed admission stage without granting a graph lease.
  admission.status

func value*(admission: LogicalProofAdmission): ProofWorkerTicket {.inline,
    requires: admission.status == LogicalProofAdmissionError.None.} =
  ## Successful submission returns the existing ticket for actual collection or joined shutdown.
  admission.ticket

func captureFailure*(admission: LogicalProofAdmission): LogicalProofResult {.inline,
    requires: admission.status == LogicalProofAdmissionError.CaptureFailure.} =
  ## Keep invalid original source, view admission and nested query refusal causes unchanged.
  admission.captureReason

func admissionFailure*(admission: LogicalProofAdmission): StateProofAdmission {.inline,
    requires: admission.status == LogicalProofAdmissionError.AdmissionFailure.} =
  ## Preserve original RPC pause or native-worker admission refusal without a successful ticket.
  admission.admissionReason

type
  ServiceDiskOperation {.pure.} = enum ## One private tag selects the receipt/cleanup path for the shared native disk slot.
    Publication, Maintenance, CurrentPublication, Retirement

type StartupBlockAnchor* = object ## Detached independently configured full-state checkpoint, captured before disk history restoration.
  case available: bool
  of true:
    hash: BlockHash
    slot: HeaderSlot
  else: discard # Defaults, light mode and closed startup retain no configured full anchor.

func available*(anchor: StartupBlockAnchor): bool =
  ## Only a successful full-state startup can expose its independent configured identity.
  anchor.available

func blockHash*(anchor: StartupBlockAnchor): BlockHash {.requires: anchor.available.} =
  ## Imported best-head progress never replaces this fixed original configured hash.
  anchor.hash

func slot*(anchor: StartupBlockAnchor): HeaderSlot {.requires: anchor.available.} =
  ## Slot is copied from the original checkpoint, independently of later canonical imports.
  anchor.slot

proc captureStartupAnchor(view: ChainView): StartupBlockAnchor =
  ## Retire temporary full graph aliases before disk restoration or native startup workers begin.
  let head = view.bestBlock
  if head.error != GenesisError.None: return default(StartupBlockAnchor)
  StartupBlockAnchor(available: true, hash: head.value.blockHash, slot: HeaderSlot(head.value.slot))

type
  WorkSessionPhase* {.pure.} = enum ## Only scalar state is observed while any canonical borrower owns the graph.
    Empty, Authorizing, Authorized, Completing, Complete, Reporting, ReportReady, Failed, Retired,
      Recovering, CheckingRecovery, Signing, Contributed, PreparingExchange, AwaitingContributions,
        CheckingContribution, CollectingGuarantee, Guaranteed
  WorkExchangeInfo* = object ## Fixed committed progress remains observable while a worker owns source-bearing graphs.
    targets*, credentials*, requestBytes*, guaranteeBytes*: int
    status*: WorkJobResultKind
  WorkSessionIdentity = ref object ## Host-only namespace never crosses into the CPU job or canonical state graph.
    marker: uint8
  WorkSessionToken* = object ## Private owner identity and nonwrapping generation reject foreign and stale session controls.
    owner: nil WorkSessionIdentity
    generation: uint64
  WorkSubmissionStart* = object ## Accepted work owns an opaque session; only Services retains the exact worker ticket.
    case status: StateProofAdmissionError
    of None: token: WorkSessionToken
    of QueryFailure: captureReason: WorkJobError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Refusals contain no session, graph or collection authority.

func signedWorkPhase(phase: WorkSessionPhase): bool =
  ## Cached signing/report metadata describes the original contribution through every exchange stage.
  phase in {WorkSessionPhase.Contributed, WorkSessionPhase.PreparingExchange,
    WorkSessionPhase.AwaitingContributions, WorkSessionPhase.CheckingContribution,
    WorkSessionPhase.CollectingGuarantee, WorkSessionPhase.Guaranteed}

func exchangeWorkPhase(phase: WorkSessionPhase): bool =
  ## Prepared independent bytes and fixed targets remain usable while another graph job runs.
  phase in {WorkSessionPhase.AwaitingContributions, WorkSessionPhase.CheckingContribution,
    WorkSessionPhase.CollectingGuarantee, WorkSessionPhase.Guaranteed}

type
  WorkSigningSetupError* {.pure.} = enum ## Startup-only failures never expose a private signer owner.
    Uninitialized, None, Closed, Busy, InvalidIdentity, InvalidStorage, SignerFailure
  WorkSigningSetupResult* = object ## Only an actual failed import carries its guarded child; successful installation returns no alias.
    case status: WorkSigningSetupError
    of SignerFailure: reason: WorkSignerResult[WorkSigner]
    else: discard # No caller can obtain the privately installed key.

func error*(outcome: WorkSigningSetupResult): WorkSigningSetupError =
  ## Observe setup status without writable result alternatives.
  outcome.status

func signerError*(outcome: WorkSigningSetupResult): WorkSignerResult[
    WorkSigner] {.requires: outcome.status == WorkSigningSetupError.SignerFailure.} =
  ## Inspect only the genuine failed loader result, whose success payload is inaccessible.
  outcome.reason

type
  WorkSharingToken* = object ## Host-only namespace cannot be used to collect the primary builder's CPU ticket.
    owner: nil WorkSessionIdentity
    generation: uint64
  WorkSharingStart* = object ## Only accepted admission exposes a distinct sharing control token.
    case status: StateProofAdmissionError
    of None: token: WorkSharingToken
    of QueryFailure: captureReason: WorkJobError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard            # Busy/closed/source refusals contain no request or collection authority.
  WorkSharingCompletionKind* {.pure.} = enum ## Missing, cancelled and failed work never expose a response signature.
    Uninitialized, Completed, Cancelled, Refused, InvalidResult
  WorkSharingCompletion* = object ## Only complete genuine signing has response bytes; failures preserve their actual receiver cause.
    case status: WorkSharingCompletionKind
    of Completed:
      response: array[SharingResponseBytes, byte]
      info: WorkEligibilityInfo
    of Refused: reason: WorkSharingResult[SignedWorkContribution]
    else: discard # No partial result or source-bearing owner escapes.

func error*(outcome: WorkSharingStart): StateProofAdmissionError =
  ## Inspect admission before extracting any token.
  outcome.status

func value*(outcome: WorkSharingStart): WorkSharingToken {.requires: outcome.status ==
    StateProofAdmissionError.None.} =
  ## Tokens control only this Services namespace and admission generation.
  outcome.token

func captureError*(outcome: WorkSharingStart): WorkJobError {.requires: outcome.status ==
    StateProofAdmissionError.QueryFailure.} =
  ## Preserve actual independent-wire/view capture refusal.
  outcome.captureReason

func workerError*(outcome: WorkSharingStart): ProofWorkerError {.requires: outcome.status ==
    StateProofAdmissionError.WorkerFailure.} =
  ## Expose the actual shared CPU admission failure.
  outcome.workerReason

func kind*(outcome: WorkSharingCompletion): WorkSharingCompletionKind =
  ## Fixed status observations grant no graph or signing authority.
  outcome.status

func response*(outcome: WorkSharingCompletion): array[SharingResponseBytes,
    byte] {.requires: outcome.status == WorkSharingCompletionKind.Completed.} =
  ## Copy only the complete hash/signature wire payload of an actual received package computation.
  outcome.response

func sharingInfo*(outcome: WorkSharingCompletion): WorkEligibilityInfo {.requires: outcome.status ==
    WorkSharingCompletionKind.Completed.} =
  ## Detached original source/credential facts do not carry a signer alias.
  outcome.info

func sharingError*(outcome: WorkSharingCompletion): WorkSharingResult[
    SignedWorkContribution] {.requires: outcome.status == WorkSharingCompletionKind.Refused.} =
  ## Refusal has only the genuine failed worker result, never a completed contribution prefix.
  outcome.reason

type
  WorkDistributionToken* = object ## Independent host namespace never aliases builder, sharing or generic proof controls.
    owner: nil WorkSessionIdentity
    generation: uint64
  WorkDistributionStart* = object ## Only successful capture/admission grants a collection or cancellation token.
    case status: StateProofAdmissionError
    of None: token: WorkDistributionToken
    of QueryFailure: captureReason: WorkJobError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Closed/busy alternatives grant no operation authority.
  WorkDistributionCompletionKind* {.pure.} = enum ## No cancellation or failure exposes a report/guarantee prefix.
    Uninitialized, Completed, Cancelled, Refused, EncodingFailure, CacheFailure, LimitExceeded, InvalidResult
  WorkDistributionCompletion* = object ## Successful detached facts/bytes/report retain no canonical source graph, signer or native stream.
    case status: WorkDistributionCompletionKind
    of Completed:
      info: WorkDistributionInfo
      targets: seq[StateValidator]
      payload: seq[byte]
      report: read_verification.CheckedReadReply
    of Refused: reason: WorkDistributionResult[CheckedWorkDistribution]
    of EncodingFailure: encodingReason: OwnershipError
    of CacheFailure: cacheReason: read_verification.ReadVerificationResult[
        read_verification.CheckedReadReply]
    else: discard # Failure payloads contain only actual selected causes.

func error*(outcome: WorkDistributionStart): StateProofAdmissionError =
  ## Read admission status before selecting its token or cause.
  outcome.status

func value*(outcome: WorkDistributionStart): WorkDistributionToken {.requires: outcome.status ==
    StateProofAdmissionError.None.} =
  ## Exact Services identity and a nonwrapping generation are required for later control.
  outcome.token

func captureError*(outcome: WorkDistributionStart): WorkJobError {.requires: outcome.status ==
    StateProofAdmissionError.QueryFailure.} =
  ## Return only the actual request/view capture refusal.
  outcome.captureReason

func workerError*(outcome: WorkDistributionStart): ProofWorkerError {.requires: outcome.status ==
    StateProofAdmissionError.WorkerFailure.} =
  ## Preserve the actual shared worker's admission error.
  outcome.workerReason

func kind*(outcome: WorkDistributionCompletion): WorkDistributionCompletionKind =
  ## Fixed completion tags are safe after exact collection and through unrelated later worker leases.
  outcome.status

func distributionInfo*(outcome: WorkDistributionCompletion): WorkDistributionInfo {.requires: outcome.status ==
    WorkDistributionCompletionKind.Completed.} =
  ## Copy source/observation facts without retaining the checked canonical graph.
  outcome.info

func distributionTarget*(outcome: WorkDistributionCompletion,
    index: int): StateValidator {.requires:
    outcome.status == WorkDistributionCompletionKind.Completed and index >= 0 and index <
    outcome.targets.len.} =
  ## Return an independent fixed validator record within this exact completed plan.
  outcome.targets[index]

proc distributionPayload*(outcome: WorkDistributionCompletion): seq[
    byte] {.requires: outcome.status == WorkDistributionCompletionKind.Completed.} =
  ## Caller mutation of detached bytes cannot alter this immutable completion or any future transport request.
  result = newSeq[byte](outcome.payload.len)
  for index in 0..<result.len: result[index] = outcome.payload[index]

func distributionReport*(outcome: WorkDistributionCompletion): read_verification.CheckedReadReply {.requires: outcome.status ==
    WorkDistributionCompletionKind.Completed.} =
  ## Independently hash-checked source-free report ownership may enter detached serving retention.
  outcome.report

func distributionError*(outcome: WorkDistributionCompletion): WorkDistributionResult[
    CheckedWorkDistribution] {.requires: outcome.status ==
    WorkDistributionCompletionKind.Refused.} =
  ## Failed context/signature/policy checks cannot expose a qualified source or report.
  outcome.reason

func distributionEncodingError*(outcome: WorkDistributionCompletion): OwnershipError {.requires: outcome.status ==
    WorkDistributionCompletionKind.EncodingFailure.} =
  ## Keep the actual report encoder's failed status selected.
  outcome.encodingReason

func distributionCacheError*(outcome: WorkDistributionCompletion): read_verification.ReadVerificationResult[
    read_verification.CheckedReadReply] {.requires: outcome.status ==
    WorkDistributionCompletionKind.CacheFailure.} =
  ## Preserve the real detached verifier's cause, without a synthesized checked report.
  outcome.cacheReason

type Services* = object             ## Owns listeners/exporter; fields are borrowed by synchronous peer callbacks.
  light: light_actor.LightRuntime
  rpc*: Server
  ui*: UiServer
  mcp*: McpServer
  mcpInfo: ClientInfo
  management*: ManagementServer
  telemetry*: Client
  chainText, networkBase: string
  startupAnchor: StartupBlockAnchor
  historyLimits: StateStoreLimits   # Historical decoding inherits the exact startup complete-map policy.
  historyLog: LogWriter             # Borrowed writer outlives Services and its joined disk worker.
  canonical: ApplicationChain
  adoption: AccumulationHandoff
  currentAdoption: CurrentAccumulationHandoff
  worker: PreparationWorker
  nativeRuntime: NativeRuntime      # Explicit application-wide compiler lifecycle, never per-code thread creation.
  executionContext: ServiceExecutionContext # Full-state lifetime; bounded baseline/scratch is allowed, but no live CPU/host/result/chain state.
  proofWorker: StateProofWorker
  assuranceStore: AssuranceStore
  assuranceStorageInput: AssuranceStorageJob
  assuranceStorageChain: AssuranceChainId
  assuranceAcquisitionInput: AssuranceAcquisitionJob
  assuranceAcquisitionActive: bool
  assuranceReadActive, assuranceReadsEnabled: bool
  assuranceReadLimits: AssuranceReadLimits
  assuranceSigner: WorkSigner
  assuranceSignerReady: bool
  assuranceSignerIdentity: StateEdKey
  auditSigner: WorkSigner
  auditSignerReady: bool
  auditSignerIdentity: StateEdKey
  audits: ManagedAuditState
  auditBranches: AuditBranches
  auditPreparationChain: ApplicationChain
  assuranceWorkInput: WorkSubmissionJob
  assuranceSigningInput: AssuranceSigningJob
  assuranceSigningActive: bool
  lastAssurance: SignedAssurance
  assuranceStorageActive: bool
  assuranceInfo: AssuranceStorageInfo
  proofInput: ProofQuery
  networkReadInput: NetworkReadJob
  verificationInput: ReadVerificationJob
  ticketInput: TicketVerificationJob
  productionInput: TicketProductionJob
  workInput: WorkSubmissionJob
  distributionInput: WorkSubmissionJob
  distributionIdentity: nil WorkSessionIdentity
  distributionGeneration: uint64
  distributionActive: bool
  distributionTicket: ProofWorkerTicket
  sharingInput: WorkSubmissionJob
  sharingIdentity: nil WorkSessionIdentity
  sharingGeneration: uint64
  sharingActive: bool
  sharingTicket: ProofWorkerTicket
  sharedContribution: SignedWorkContribution
  guarantorStore: GuarantorStore
  workContext: AuthorizedWorkContext
  workRecovery: WorkRecovery
  workRecoveryInfo: WorkRecoveryInfo
  workRecoveryJobs: uint64
  workRecoveryEnabled, workFallbackAllowed: bool
  workOutcome: WorkJobResult
  workExchangeOutcome: WorkJobResult
  workRound: WorkGuaranteeRound
  workSharedRequest: SharedWorkRequest
  workShareTargets: array[2, WorkShareTarget]
  workExchangeState: WorkExchangeInfo
  workGuarantee: CollectedWorkGuarantee
  workGuaranteeBytes: seq[byte]
  workIdentity: nil WorkSessionIdentity
  workGeneration: uint64
  workPhase: WorkSessionPhase
  workActive: bool
  workTicket: ProofWorkerTicket
  workInfo: WorkSubmissionInfo
  workDuty: WorkDuty
  workSigner: WorkSigner
  workSignerReady: bool
  workSignerIdentity: StateEdKey
  workContributionInfo: WorkEligibilityInfo
  workReportInfo: ComputedReportInfo
  availabilityEnabled: bool
  availabilityLimits: AvailabilityReadLimits
  availabilityStore: AvailabilityStore
  workHead: BlockHash
  ticketSigner: TicketSigner
  ticketSignerReady: bool
  ticketSignerVersion: uint64
  ticketSignerPublic: array[32, byte]
  ticketSource: NetworkTicketResult[TicketSource]
  ticketCaptureFailure: NetworkTicketResult[TicketSource]
  rpcProof: RpcProofDispatch        # Detached connection intent never retains canonical state.
  rpcProofTicket: ProofWorkerTicket # Host-only exact collection authority for an RPC-origin job.
  proofing: bool
  checkpointExport: ApplicationCheckpointSession
  rpcLease: nil RpcChainLease
  preparing: bool
  started, chainRpc: bool
  rpcStarted, uiStarted, managementStarted, telemetryStarted,
    storageStarted: bool            # Successful listener setup controls shutdown messages.
  disk: DiskStateStore
  diskWorker: DiskPublicationWorker
  diskMaintenance: PreparedDiskMaintenance
  diskRetirement: PreparedPagedRetirement
  retirementCompletion: DiskPublicationCompletion
  retirementDelayed: bool
  retirementAttempt: MonoTime
  maintenanceStage: DiskChainResult[PreparedDiskMaintenance]
  maintenanceCompletion: DiskPublicationCompletion
  startupMaintenance: DiskChainResult[ManagedCompaction]
  maintenanceAdmission: DiskWorkerError
  diskOperation: ServiceDiskOperation
  diskPublication: PreparedDiskPublication
  currentDiskPublication: PreparedCurrentDiskPublication
  currentDiskStageOutcome: DiskChainResult[PreparedCurrentDiskPublication]
  currentDiskAdmission: DiskWorkerError
  diskTicket: DiskPublicationTicket
  diskStageOutcome: DiskChainResult[PreparedDiskPublication]
  diskCommitOutcome: DiskChainResult[RepositoryGeneration]
  diskId: StorageChainId
  diskLimits: JournalLimits
  diskEnabled, publishing, diskFaulted, diskManaged, diskPaged, diskResume: bool
  compactBytes: ByteLimit

func error*(admission: StateProofAdmission): StateProofAdmissionError =
  ## Read the reason without granting a selected-state lease ticket.
  admission.status

func value*(admission: StateProofAdmission): ProofWorkerTicket {.inline,
    requires: admission.status == StateProofAdmissionError.None.} =
  ## Only accepted managed work exposes its worker ticket.
  admission.ticket

func queryError*(admission: StateProofAdmission): ProofQueryError {.inline,
    requires: admission.status == StateProofAdmissionError.QueryFailure.} =
  ## Capture refusals retain the exact selection/plan/budget reason.
  admission.queryReason

func workerError*(admission: StateProofAdmission): ProofWorkerError {.inline,
    requires: admission.status == StateProofAdmissionError.WorkerFailure.} =
  ## Native refusal carries no successful ticket and leaves RPC available.
  admission.workerReason

proc `=wasMoved`*(services: var Services) {.nodestroy, inline, requires: not services.started.} =
  ## Only closed aggregates may relocate; native workers and callback borrows require the original stable parent address.
  `=wasMoved`(services.light)
  `=wasMoved`(services.proofWorker)
  `=wasMoved`(services.assuranceStore)
  `=wasMoved`(services.assuranceStorageInput)
  `=wasMoved`(services.assuranceAcquisitionInput)
  `=wasMoved`(services.assuranceSigner)
  `=wasMoved`(services.auditSigner)
  `=wasMoved`(services.audits)
  `=wasMoved`(services.auditBranches)
  `=wasMoved`(services.auditPreparationChain)
  `=wasMoved`(services.assuranceWorkInput)
  `=wasMoved`(services.assuranceSigningInput)
  `=wasMoved`(services.lastAssurance)
  `=wasMoved`(services.proofInput)
  `=wasMoved`(services.networkReadInput)
  `=wasMoved`(services.verificationInput)
  `=wasMoved`(services.ticketInput)
  `=wasMoved`(services.productionInput)
  `=wasMoved`(services.distributionInput)
  `=wasMoved`(services.distributionIdentity)
  `=wasMoved`(services.distributionTicket)
  `=wasMoved`(services.sharingInput)
  `=wasMoved`(services.sharingIdentity)
  `=wasMoved`(services.sharingTicket)
  `=wasMoved`(services.sharedContribution)
  `=wasMoved`(services.guarantorStore)
  services.distributionGeneration = 0
  services.distributionActive = false
  services.sharingGeneration = 0
  services.sharingActive = false
  `=wasMoved`(services.workInput)
  `=wasMoved`(services.workExchangeOutcome)
  `=wasMoved`(services.workRound)
  `=wasMoved`(services.workSharedRequest)
  `=wasMoved`(services.workShareTargets)
  `=wasMoved`(services.workExchangeState)
  `=wasMoved`(services.workGuarantee)
  `=wasMoved`(services.workGuaranteeBytes)
  `=wasMoved`(services.workContext)
  `=wasMoved`(services.workRecovery)
  `=wasMoved`(services.workSigner)
  `=wasMoved`(services.workContributionInfo)
  services.workSignerReady = false
  services.workSignerIdentity = default(StateEdKey)
  `=wasMoved`(services.workDuty)
  `=wasMoved`(services.workReportInfo)
  `=wasMoved`(services.availabilityStore)
  `=wasMoved`(services.workOutcome)
  `=wasMoved`(services.workIdentity)
  `=wasMoved`(services.workTicket)
  `=wasMoved`(services.ticketSigner)
  `=wasMoved`(services.ticketSource)
  `=wasMoved`(services.ticketCaptureFailure)
  `=wasMoved`(services.rpcProof)
  `=wasMoved`(services.rpcProofTicket)
  `=wasMoved`(services.diskWorker)
  `=wasMoved`(services.disk)
  `=wasMoved`(services.diskRetirement)
  `=wasMoved`(services.retirementCompletion)
  `=wasMoved`(services.diskMaintenance)
  `=wasMoved`(services.maintenanceStage)
  `=wasMoved`(services.maintenanceCompletion)
  `=wasMoved`(services.startupMaintenance)
  `=wasMoved`(services.diskPublication)
  `=wasMoved`(services.currentDiskPublication)
  `=wasMoved`(services.currentDiskStageOutcome)
  `=wasMoved`(services.diskTicket)
  `=wasMoved`(services.diskStageOutcome)
  `=wasMoved`(services.diskCommitOutcome)
  `=wasMoved`(services.checkpointExport)
  `=wasMoved`(services.worker)
  `=wasMoved`(services.executionContext)
  `=wasMoved`(services.nativeRuntime)
  `=wasMoved`(services.rpcLease)
  `=wasMoved`(services.mcp)
  `=wasMoved`(services.mcpInfo)
  `=wasMoved`(services.management)
  `=wasMoved`(services.ui)
  `=wasMoved`(services.rpc)
  `=wasMoved`(services.telemetry)
  `=wasMoved`(services.chainText)
  `=wasMoved`(services.networkBase)
  `=wasMoved`(services.startupAnchor)
  `=wasMoved`(services.canonical)
  `=wasMoved`(services.adoption)
  `=wasMoved`(services.currentAdoption)

proc `=copy`*(destination: var Services, source: Services) {.error: "Application Services owns descriptors".}
  ## Reject copying application descriptors, workers and listener lifetimes.

proc `=dup`*(source: Services): Services {.error.}
  ## Composite ownership includes the stable worker and all listener lifetimes.

proc `=destroy`*(services: Services) =
  ## Retire partially configured owners and the shared snapshot even without explicit shutdown.
  `=destroy`(services.light)
  `=destroy`(services.proofWorker) # Explicit joined close precedes every selected-state alias retirement.
  `=destroy`(services.assuranceStorageInput)
  `=destroy`(services.assuranceAcquisitionInput)
  `=destroy`(services.assuranceSigner)
  `=destroy`(services.auditSigner)
  `=destroy`(services.audits)
  `=destroy`(services.auditBranches)
  `=destroy`(services.auditPreparationChain)
  `=destroy`(services.assuranceWorkInput)
  `=destroy`(services.assuranceSigningInput)
  `=destroy`(services.lastAssurance)
  `=destroy`(services.assuranceStore) # Its native borrower has joined and its single-writer gate is explicitly closed.
  `=destroy`(services.proofInput)
  `=destroy`(services.networkReadInput)
  `=destroy`(services.verificationInput)
  `=destroy`(services.ticketInput)
  `=destroy`(services.productionInput)
  `=destroy`(services.distributionInput)
  `=destroy`(services.distributionIdentity)
  `=destroy`(services.distributionTicket)
  `=destroy`(services.sharingInput)
  `=destroy`(services.sharingIdentity)
  `=destroy`(services.sharingTicket)
  `=destroy`(services.sharedContribution)
  `=destroy`(services.guarantorStore)
  `=destroy`(services.workInput)
  `=destroy`(services.workExchangeOutcome)
  `=destroy`(services.workRound)
  `=destroy`(services.workSharedRequest)
  `=destroy`(services.workShareTargets)
  `=destroy`(services.workExchangeState)
  `=destroy`(services.workGuarantee)
  `=destroy`(services.workGuaranteeBytes)
  `=destroy`(services.workContext)
  `=destroy`(services.workRecovery)
  `=destroy`(services.workSigner)
  `=destroy`(services.workContributionInfo)
  `=destroy`(services.workDuty)
  `=destroy`(services.workReportInfo)
  `=destroy`(services.availabilityStore)
  `=destroy`(services.workOutcome)
  `=destroy`(services.workIdentity)
  `=destroy`(services.workTicket)
  `=destroy`(services.ticketSigner)
  `=destroy`(services.ticketSource)
  `=destroy`(services.ticketCaptureFailure)
  `=destroy`(services.rpcProof)
  `=destroy`(services.rpcProofTicket)
  `=destroy`(services.diskWorker) # Join must precede every disk/canonical/publication alias retirement.
  `=destroy`(services.disk)
  `=destroy`(services.diskRetirement)
  `=destroy`(services.retirementCompletion)
  `=destroy`(services.diskMaintenance)
  `=destroy`(services.maintenanceStage)
  `=destroy`(services.maintenanceCompletion)
  `=destroy`(services.startupMaintenance)
  `=destroy`(services.diskPublication)
  `=destroy`(services.currentDiskPublication)
  `=destroy`(services.currentDiskStageOutcome)
  `=destroy`(services.diskTicket)
  `=destroy`(services.diskStageOutcome)
  `=destroy`(services.diskCommitOutcome)
  `=destroy`(services.checkpointExport) # Explicit close joins the detached I/O child before aggregate destruction.
  `=destroy`(services.worker) # Explicit close must join before any shared chain alias retires.
  `=destroy`(services.executionContext) # Joined preparation ends every cross-thread context borrow first.
  `=destroy`(services.nativeRuntime) # Explicit close has joined compiler; closed anchors can outlive client retirement.
  `=destroy`(services.rpcLease)
  `=destroy`(services.mcp)
  `=destroy`(services.mcpInfo)
  `=destroy`(services.management)
  `=destroy`(services.ui)
  `=destroy`(services.rpc)
  `=destroy`(services.telemetry)
  `=destroy`(services.chainText)
  `=destroy`(services.networkBase)
  `=destroy`(services.startupAnchor)
  `=destroy`(services.canonical)
  `=destroy`(services.adoption)
  `=destroy`(services.currentAdoption)

proc reportHistoryCleanup(services: Services) =
  ## Called only after native graph exclusion ends; an actual reclamation failure never revokes a confirmed block.
  if services.disk.opened:
    let reason = services.disk.historyCleanupError
    if reason notin [HistoryError.None, HistoryError.Uninitialized]:
      log(services.historyLog, LogTarget.Storage, LogLevel.Warn,
          "Historical cleanup deferred reason=" & $reason)

proc stateProofAvailable*(services: Services): bool
  ## Scalar graph admission is shared by trusted finality and managed proof/read work.

proc finishDiskGraph(services: var Services) =
  ## Collected IO no longer borrows canonical state or retained audit origins.
  services.publishing = false
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  if services.stateProofAvailable: services.audits.drainAbandonedDeclarations()

proc finishDiskRetirement(services: var Services, completion: DiskPublicationCompletion) =
  ## Cleanup has its own receipt: never replace a completed canonical publication with a cleanup failure.
  services.retirementCompletion = completion
  if completion.kind == DiskCompletionKind.Retired:
    let outcome = completion.retirementValue
    if outcome.error == DiskStoreError.FileFailure and outcome.fileError == FileError.Busy:
      services.retirementDelayed = true
      services.retirementAttempt = getMonoTime() # A foreign immutable reader backpressures authoring without an IO spin.
    elif outcome.error != DiskStoreError.None:
      services.diskFaulted = true
    elif outcome.value.retirementError != FileError.None:
      services.diskFaulted = true # Confirmed removal remains visible independently from final close uncertainty.
    else:
      services.retirementDelayed = false # The next ordinary publication may now author one new artifact.
  else:
    assert completion.kind == DiskCompletionKind.NotExecuted # Joined queued work entered no IO and leaves the target pending.
  services.diskRetirement = default(PreparedPagedRetirement)
  services.diskOperation = ServiceDiskOperation.Publication
  services.finishDiskGraph()

proc finishDiskMaintenance(services: var Services, completion: DiskPublicationCompletion) =
  ## Joined/collected maintenance ends the physical lease without changing canonical/RPC state or adoption receipts.
  services.maintenanceCompletion = completion
  if completion.kind == DiskCompletionKind.Maintained:
    let outcome = completion.maintenanceValue
    if outcome.error != DiskChainError.None:
      services.diskFaulted = true
    elif outcome.value.cleanup != FileError.None:
      services.diskFaulted = true # Preserve durable selection and expose cleanup refusal without attempting another mutation.
  else:
    assert completion.kind == DiskCompletionKind.NotExecuted
  services.diskOperation = ServiceDiskOperation.Publication
  services.diskMaintenance = default(PreparedDiskMaintenance)
  services.finishDiskGraph()

proc finishCurrentDiskPublication(services: var Services, completion: DiskPublicationCompletion) =
  ## Collection/join ends all borrows before exact receipt/context checks and canonical/RPC installation.
  if completion.kind == DiskCompletionKind.Completed:
    services.reportHistoryCleanup() # Collection/join has ended every worker borrow.
    let receipt = completion.value
    services.diskCommitOutcome = receipt # Preserve the actual IO result, including uncertainty, independently of handoff status.
    if receipt.error != DiskChainError.None:
      services.diskFaulted = true
      services.currentAdoption.refusePublication(CurrentHandoffError.DurabilityRefused)
    elif not confirmsCurrentDiskPublication(services.disk,
        services.currentDiskPublication, receipt.value):
      services.diskFaulted = true
      services.currentAdoption.refusePublication(CurrentHandoffError.DurabilityRefused)
    else:
      let prepared = services.currentDiskPublication.chainUpdate
      if not services.canonical.canInstallPrepared(prepared):
        services.diskFaulted = true
        services.currentAdoption.refusePublication(CurrentHandoffError.StaleState)
      elif services.chainRpc and not services.canonical.canInstallPrepared(services.rpc, prepared,
          services.rpcLease):
        services.diskFaulted = true
        services.currentAdoption.refusePublication(CurrentHandoffError.RpcRefused)
      else:
        if services.chainRpc:
          services.canonical.installPrepared(services.rpc, prepared, services.rpcLease)
        else:
          services.canonical.installPrepared(prepared) # Disabled RPC still installs only after the same confirmed IO receipt.
        services.currentAdoption.completePublication(services.canonical.installedPrepared(prepared))
  else:
    assert completion.kind == DiskCompletionKind.NotExecuted
    services.currentAdoption.refusePublication(CurrentHandoffError.DurabilityRefused) # Joined queued work creates no IO success.
  services.currentDiskPublication = default(PreparedCurrentDiskPublication)
  services.diskOperation = ServiceDiskOperation.Publication
  services.finishDiskGraph()

proc finishDiskPublication(services: var Services, completion: DiskPublicationCompletion) =
  ## Called only after collect/join retires all native temporaries; install before reopening RPC access.
  if not services.publishing: return
  case services.diskOperation
  of ServiceDiskOperation.Retirement:
    services.finishDiskRetirement(completion)
    return # Retiring old physical storage never installs another canonical or RPC head.
  of ServiceDiskOperation.Maintenance:
    services.finishDiskMaintenance(completion)
    return # Physical maintenance has no application installation outcome.
  of ServiceDiskOperation.CurrentPublication:
    services.finishCurrentDiskPublication(completion)
    return # Current completion uses its exact saved publication and never a legacy update.
  of ServiceDiskOperation.Publication:
    discard # Preserve the existing legacy receipt/install path below.
  if completion.kind == DiskCompletionKind.Completed:
    services.reportHistoryCleanup() # Native IO has retired before diagnostics read its passive metadata.
    services.diskCommitOutcome = completion.value
    if completion.value.error == DiskChainError.None:
      let prepared = services.diskPublication.chainUpdate
      if services.chainRpc:
        services.canonical.installPrepared(services.rpc, prepared, services.rpcLease)
      else:
        services.canonical.installPrepared(prepared)
      services.adoption.completePublication(services.canonical.installedPrepared(prepared))
    else:
      services.diskFaulted = true # Never attempt another mutation after a potentially uncertain publication.
      services.adoption.completePublication(durabilityFailure())
  else:
    assert completion.kind == DiskCompletionKind.NotExecuted
    services.adoption.completePublication(durabilityFailure()) # Joined queued shutdown made no IO attempt.
  services.diskPublication = default(PreparedDiskPublication)
  services.finishDiskGraph()

proc stopDiskPublication*(services: var Services) =
  ## Shutdown outside callbacks joins before any input/canonical/RPC alias can retire, preserving actual IO receipts.
  if services.light.active:
    services.light.stopDisk()
    return # Joined light IO retains its distinct actual outcome.
  let completion = services.diskWorker.close()
  services.finishDiskPublication(completion)
  if services.diskEnabled: services.diskFaulted = true # Explicit backend shutdown requires a fresh startup before more writes.

func diskPublicationActive*(services: Services): bool =
  ## Scalar-only observation is permitted while canonical graphs remain exclusively borrowed.
  services.publishing

proc diskPublicationPhase*(services: var Services): DiskWorkerPhase =
  ## Scalar-only synchronized observation grants no access to a Done job's still-leased graph.
  services.diskWorker.phase

func currentDiskPreparationOutcome*(services: Services): DiskChainResult[
    PreparedCurrentDiskPublication] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Only an actual current host staging refusal is retained; default never grants publication authority.
  services.currentDiskStageOutcome

func currentDiskPublicationAdmissionError*(services: Services): DiskWorkerError =
  ## Observe the actual current worker admission reason without touching any leased ARC owner.
  services.currentDiskAdmission

func diskPublicationOutcome*(services: Services): DiskChainResult[RepositoryGeneration] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Preserve the actual last IO receipt, including across close, until a later startup/job replaces it.
  services.diskCommitOutcome

func diskPreparationOutcome*(services: Services): DiskChainResult[
    PreparedDiskPublication] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Failed host staging keeps its own typed context refusal; default means no such failure was recorded.
  services.diskStageOutcome

proc refreshAssuranceStorage(services: var Services) =
  ## Only exact collection or joined stop may copy scalar namespace state after its exclusive mutable borrow retires.
  if services.assuranceStore.opened:
    services.assuranceInfo = AssuranceStorageInfo(opened: true,
      faulted: services.assuranceStore.faulted, chain: services.assuranceStorageChain,
      records: services.assuranceStore.len, bytes: services.assuranceStore.byteLength)
  else:
    # Closed admission carries no remembered namespace identity or capacity facts.
    services.assuranceInfo = default(AssuranceStorageInfo)

proc stopStateProofs*(services: var Services) =
  ## Join before dropping the captured selection or releasing this proof job's exact RPC token.
  if services.light.active:
    services.light.stopProofs()
    return # Full-state worker/lease fields remain unstarted in light mode.
  services.proofWorker.close()
  services.audits.stop() # Joined proof collection revokes only host controls; full pins survive until every shared borrower joins.
  services.assuranceWorkInput = default(WorkSubmissionJob)
  services.assuranceSigningInput = default(AssuranceSigningJob)
  if services.assuranceSigningActive:
    # Joined cancellation may have renewed data but must not leave a publishable signature from this stopped turn.
    services.refreshAssuranceStorage()
    services.assuranceSigningActive = false
    services.lastAssurance = default(SignedAssurance)
  services.assuranceAcquisitionInput = default(AssuranceAcquisitionJob)
  if services.assuranceAcquisitionActive:
    # A cancelled completed publication remains stored; only joined observation can refresh accounting or its fault gate.
    services.refreshAssuranceStorage()
    services.assuranceAcquisitionActive = false
  if services.assuranceReadActive:
    # A cancelled read may already have detected corrupt durable data; join precedes cached fault observation.
    services.refreshAssuranceStorage()
    services.assuranceReadActive = false
  services.assuranceStorageInput = default(AssuranceStorageJob)
  if services.assuranceStorageActive:
    # Joined startup may already have opened the namespace; cancellation cannot roll that side effect back on the worker.
    discard services.assuranceStore.close()
    services.assuranceInfo = default(AssuranceStorageInfo)
    services.assuranceStorageActive = false
  services.distributionInput = default(WorkSubmissionJob)
  services.distributionTicket = default(ProofWorkerTicket)
  services.distributionActive = false # Joined stop revokes this namespace before its worker can reopen.
  services.sharingInput = default(WorkSubmissionJob)
  services.sharingTicket = default(ProofWorkerTicket)
  services.sharingActive = false # Joined stop revokes the exact incoming namespace before another controller can reopen it.
  if services.workActive:
    # Joined external stop retires this session without releasing source owners borrowed by other worker families.
    services.workActive = false
    services.workPhase = WorkSessionPhase.Retired
  services.workInput = default(WorkSubmissionJob)
  services.ticketInput = default(TicketVerificationJob)
  services.productionInput = default(TicketProductionJob)
  services.ticketSource = default(NetworkTicketResult[TicketSource])
  services.ticketCaptureFailure = default(NetworkTicketResult[TicketSource])
  if services.proofing:
    services.proofInput = default(ProofQuery)
    services.networkReadInput = default(NetworkReadJob)
    services.verificationInput = default(ReadVerificationJob)
    services.proofing = false
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # Only this worker's joined lease can reopen canonical access.
  if services.rpcProof.valid:
    discard services.rpc.finishStateProof(services.rpcProof, default(StateRoot), [], "State proof stopped")
    services.rpcProof = default(RpcProofDispatch)
    services.rpcProofTicket = default(ProofWorkerTicket)
  if services.stateProofAvailable: services.audits.drainAbandonedDeclarations()

func residentServiceCount*(services: Services): int {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Observe idle finite code occupancy only after exact collection/join; this is not memory accounting.
  residentServices(services.executionContext)

proc residentServiceInfo*(services: Services, service: ServiceIndex, version: CodeHash,
    backend: PvmBackend): PreparationResult[PreparedCacheInfo] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Copy existing worker facts only after exact collection/join; Done/cancel never reopen this gate.
  residentServiceInfo(services.executionContext, service, version, backend)

proc stopPreparation*(services: var Services) =
  ## Join and discard private execution before reopening canonical/RPC access; listeners and canonical state remain owned.
  if services.light.active: return # Distinct light actor owns its own CPU/IO lease and joins.
  if services.proofing or services.publishing: return # A proof/disk borrower owns the same RPC lease until its own joined retirement.
  services.worker.close()
  services.auditPreparationChain = default(ApplicationChain)
  services.preparing = false
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  if services.stateProofAvailable: services.audits.drainAbandonedDeclarations()

proc stopCheckpointExport*(services: var Services) =
  ## Join detached I/O outside callbacks and retain actual uncollected work/retirement uncertainty until explicit acknowledgement.
  services.checkpointExport.close()

proc clearWorkExchange(services: var Services) =
  ## Call only after CPU borrowers retire; independent raw caches and retained credential graphs reset together.
  services.workExchangeOutcome = default(WorkJobResult)
  services.workRound = default(WorkGuaranteeRound)
  services.workSharedRequest = default(SharedWorkRequest)
  services.workShareTargets = default(array[2, WorkShareTarget])
  services.workExchangeState = default(WorkExchangeInfo)
  services.workGuarantee = default(CollectedWorkGuarantee)
  services.workGuaranteeBytes = @[]

proc close*(services: var Services) =
  ## Idempotent retirement happens after every dispatcher/native callback has ended its borrows.
  if services.started:
    log(services.historyLog, LogTarget.Startup, LogLevel.Info, "Stopping service workers and listeners")
  services.light.close() # Distinct light workers join before the borrowed RPC owner or partial evidence retires.
  services.stopStateProofs() # Join selected-state access before any canonical/RPC owner retires.
  discard services.assuranceStore.close() # No namespace descriptor or owner address retires before its borrower joins.
  services.assuranceInfo = default(AssuranceStorageInfo)
  services.ticketSigner = default(TicketSigner) # Last private-key ownership retires only after every secret-borrowing job joins.
  services.ticketSignerReady = false
  services.ticketSignerVersion = 0
  services.ticketSignerPublic = default(array[32, byte])
  services.stopCheckpointExport() # Repeated close preserves the fixed joined-outcome journal.
  services.stopDiskPublication() # Commit receipts survive shutdown; joined IO ends all graph borrowing.
  services.stopPreparation() # Join before releasing any canonical, signer or listener alias.
  services.auditBranches.clear()
  services.audits.clear() # Every proof, preparation, disk and checkpoint borrower has joined.
  services.auditSigner = default(WorkSigner)
  services.auditSignerReady = false
  services.auditSignerIdentity = default(StateEdKey)
  services.sharedContribution = default(SignedWorkContribution)
  services.guarantorStore.clear() # Joined shutdown retires every retained serving alias before dropping the cache.
  services.distributionIdentity = nil
  services.distributionGeneration = 0
  services.distributionInput = default(WorkSubmissionJob)
  services.distributionTicket = default(ProofWorkerTicket)
  services.distributionActive = false
  services.sharingIdentity = nil
  services.sharingGeneration = 0
  services.assuranceSigner = default(WorkSigner)
  services.assuranceSignerReady = false
  services.assuranceSignerIdentity = default(StateEdKey)
  services.lastAssurance = default(SignedAssurance)
  services.workSigner = default(WorkSigner)
  services.workSignerReady = false
  services.workSignerIdentity = default(StateEdKey)
  services.workContributionInfo = default(WorkEligibilityInfo)
  services.sharingInput = default(WorkSubmissionJob)
  services.sharingTicket = default(ProofWorkerTicket)
  services.sharingActive = false
  services.workInput = default(WorkSubmissionJob)
  services.workContext = default(AuthorizedWorkContext)
  services.workRecovery = default(WorkRecovery)
  services.workRecoveryInfo = default(WorkRecoveryInfo)
  services.workRecoveryJobs = 0
  services.workRecoveryEnabled = false
  services.workFallbackAllowed = false
  services.workOutcome = default(WorkJobResult)
  services.clearWorkExchange()
  services.workIdentity = nil
  services.workTicket = default(ProofWorkerTicket)
  services.availabilityStore.clear()
  services.assuranceReadsEnabled = false
  services.assuranceReadLimits = default(AssuranceReadLimits)
  services.availabilityEnabled = false
  services.availabilityLimits = default(AvailabilityReadLimits)
  services.workGeneration = 0
  services.workPhase = WorkSessionPhase.Empty
  services.workActive = false
  services.workInfo = default(WorkSubmissionInfo)
  services.workDuty = default(WorkDuty)
  services.workReportInfo = default(ComputedReportInfo)
  services.workContributionInfo = default(WorkEligibilityInfo)
  services.workHead = default(BlockHash)
  services.executionContext = default(ServiceExecutionContext) # Full Services close retires code; stopPreparation alone preserves it.
  assert services.nativeRuntime.close() # No active invocation survives joined preparation/context retirement.
  services.nativeRuntime = default(NativeRuntime)
  if services.mcp.enabled: log(services.historyLog, LogTarget.Startup, LogLevel.Info, "Stopping MCP listener")
  services.mcp.close()
  services.mcpInfo = default(ClientInfo)
  if services.managementStarted: log(services.historyLog, LogTarget.Startup, LogLevel.Info, "Stopping management listener")
  services.management.close()
  if services.uiStarted: log(services.historyLog, LogTarget.Startup, LogLevel.Info, "Stopping UI listener")
  services.ui.close()
  if services.rpcStarted: log(services.historyLog, LogTarget.Rpc, LogLevel.Info, "Stopping RPC listener")
  services.rpc.close()
  if services.telemetryStarted: log(services.historyLog, LogTarget.Telemetry, LogLevel.Info, "Stopping telemetry exporter")
  services.telemetry.close()
  services.rpc = default(Server) # Server.close retires sockets; replacement also releases its retained history/configuration.
  services.adoption = default(AccumulationHandoff) # Retire pending or unacknowledged immutable owners on shutdown.
  services.currentAdoption = default(CurrentAccumulationHandoff) # Native workers joined before current graph retirement.
  var storageClose = FileError.None
  if services.disk.opened: storageClose = services.disk.close
  services.diskEnabled = false
  services.diskManaged = false
  services.compactBytes = ByteLimit(0)
  services.diskOperation = ServiceDiskOperation.Publication
  services.diskFaulted = false
  services.diskTicket = default(DiskPublicationTicket)
  services.canonical = default(ApplicationChain)
  services.historyLimits = default(StateStoreLimits)
  if services.storageStarted:
    if storageClose == FileError.None:
      log(services.historyLog, LogTarget.Storage, LogLevel.Info, "Storage closed")
    else:
      log(services.historyLog, LogTarget.Storage, LogLevel.Error, "Storage close failed: " & $storageClose)
  services.historyLog = default(LogWriter)
  services.rpcStarted = false
  services.uiStarted = false
  services.managementStarted = false
  services.telemetryStarted = false
  services.storageStarted = false
  services.started = false
  services.chainRpc = false
  services.chainText = ""
  services.networkBase = ""
  services.startupAnchor = default(StartupBlockAnchor)

proc boundedFile(path: string, limit: int): string {.raises.} =
  ## Read at most limit+1 bytes; empty output means missing, empty or oversized configuration.
  result = ""
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return # No implicit file/default chain.
  defer: close(file) # All read outcomes retire the handle.
  var text = newString(limit + 1)
  let buffer = text.beginStore(text.len)
  let count = readBuffer(file, cast[pointer](buffer), text.len)
  text.endStore() # Commit the public string bulk-write API before reading or resizing.
  if count <= 0 or count > limit: return # Detect growth/oversize without unbounded readFile.
  text.setLen(count)
  result = move(text)

proc setupRpc(rpc: var Server, options: Options, role: string, text: string,
    mcpInfo: var ClientInfo, networkBase: var string): bool =
  ## An explicit RPC/MCP chain must validate before opening the listener; missing configuration remains unavailable.
  var parameters = default(ParameterResult)
  var genesis = unavailableGenesis()
  if options.chainPath().len > 0:
    let network = readNetworkIdentity(text)
    if network.error == NetworkIdentityError.None:
      networkBase = genesisAlpn(network.value.genesisHash) # Stateless identity needs header bytes, not a complete state map.
    if options.rpcPort() != 0 or options.mcpPort() != 0:
      parameters = configuredParameters(text)
      if not parameters.ok: return false # Public metadata retains its existing validation contract.
      genesis = configuredGenesis(text, parameters.value)
      if genesis.error == GenesisError.Invalid: return false
  if options.mcpPort != 0:
    mcpInfo = ClientInfo(role: role, parameters: parameters, chain: genesisView(genesis),
      identity: chainIdentity(genesis)) # No canonical worker exists in this legacy listener-only path.
  rpc.start(options.rpcPort(), role, parameters, genesis, options.uiPort(), chainIdentity(genesis))

proc logCertificateIdentity(writer: LogWriter, certificate: string) =
  ## Read only bounded public certificate bytes; unavailable diagnostics never affect transport acceptance.
  if not writer.enabled(LogTarget.Network, LogLevel.Info): return
  try:
    let pem = boundedFile(certificate, 16384).strip()
    const first = "-----BEGIN CERTIFICATE-----"
    const last = "-----END CERTIFICATE-----"
    if not pem.startsWith(first) or not pem.endsWith(last) or pem.len < first.len+last.len: return
    var body = ""
    for character in pem[first.len..<pem.len-last.len]:
      if character notin {' ', '\t', '\r', '\n'}: body.add(character)
    var der = base64.decode(body)
    if der.len == 0 or der.len > 8192: return
    var fields {.noinit.}: CertFields
    if parseCert(cast[ptr byte](der.toCString()), csize_t(der.len), addr fields) != 1 or
        fields.edKey != 1 or fields.keyLength != 32: return
    var key = default(array[32, byte])
    for index in 0..<key.len: key[index] = fields.key[index]
    var name = ""
    for character in peerName(key): name.add(char(character))
    log(writer, LogTarget.Network, LogLevel.Info, "Local node identity: " & name)
  except:
    log(writer, LogTarget.Network, LogLevel.Warn, "Local certificate identity is unavailable for logging")

proc setupTelemetry(client: var Client, options: Options, certificate: string, port: uint16,
    ipv6: bool, text: string): bool {.raises.} =
  ## Build registration from explicit JIP-4 configuration and the actual local certificate/socket.
  if not options.telemetryEnabled(): return true # Absence is the default and requires no configuration.
  if text.len == 0: return false # Never invent a chain or use an implicit development network.
  let pem = boundedFile(certificate, 16384).strip()
  const beginMarker = "-----BEGIN CERTIFICATE-----"
  const endMarker = "-----END CERTIFICATE-----"
  # Reject overlapping/empty PEM markers before constructing the body slice.
  if pem.len < beginMarker.len + endMarker.len: return false
  if not pem.startsWith(beginMarker) or not pem.endsWith(endMarker): return false
  var body = ""
  # Permit PEM whitespace but reject noncanonical base64 through round-trip validation below.
  for character in pem[beginMarker.len..<pem.len - endMarker.len]:
    if character notin {' ', '\t', '\r', '\n'}: body.add(character)
  var der = base64.decode(body)
  if der.len == 0 or der.len > 8192 or base64.encode(der) != body: return false
  # The native extractor initializes all C fields before success; no C array object constructor is used.
  var fields {.noinit.}: CertFields
  # Reuse maintained X.509 extraction; public identity is copied, never read from a secret key.
  let derPointer = der.toCString()
  if parseCert(cast[ptr byte](derPointer), csize_t(der.len), addr fields) != 1 or
      fields.edKey != 1 or fields.keyLength != 32: return false
  let address = if options.networkBind.valid: options.networkBind.bytes
    elif options.networkPeer.valid:
      (if options.networkPeer.ipv6: ipv6Address(default(array[16, byte])).bytes
        else: ipv4Address([0'u8, 0, 0, 0]).bytes)
    else: loopbackAddress(ipv6).bytes # Report the configured wildcard instead of fabricating a loopback source.
  var identity = default(array[32, byte])
  # Copy C array elements individually into native Nim storage before crossing the API boundary.
  for i in 0..<32: identity[i] = fields.key[i]
  let parsed = chainMetadata(text, identity, address, port)
  if not parsed.ok: return false # Failed chain metadata cannot produce a registration.
  configure(client, options.telemetryEndpoint(), parsed.value, options.logWriter)

proc diskJournalLimits(policy: StateStoreLimits): JournalLimits =
  ## Finite initial backend ceilings cap one batch, accumulated physical history and the complete journal independently.
  JournalLimits(repository: RepositoryLimits(codec: RecordLimits(trie: policy.trie,
    records: TrieExportLimits(records: TrieNodeLimit(1048576), valueBytes: ByteLimit(4*1024*1024)),
    encoded: ByteLimit(64*1024*1024)), records: ElementLimit(4194304),
    valueBytes: ByteLimit(128*1024*1024)), bytes: ByteLimit(256*1024*1024), contextBytes: ByteLimit(4*1024*1024))

proc managedPolicy(limits: JournalLimits): ManagedLimits =
  ## Managed files retain the same graph/physical/journal ceilings plus bounded canonical history roots.
  ManagedLimits(repository: limits.repository, roots: ElementLimit(MaxRetainedBlocks+1),
    snapshotBytes: limits.bytes, journalBytes: limits.bytes, contextBytes: limits.contextBytes)

proc initializeSelectedDisk(services: var Services, path: string): DiskChainResult[
    RepositoryGeneration] =
  ## Explicit layout dispatch never resets an existing path or infers migration from its shape.
  if services.diskPaged:
    let created = initializePagedDiskChain(services.disk, path, services.diskId, services.canonical,
        services.diskLimits)
    if created.error != DiskChainError.StoreFailure: return created
    let failed = created.storeFailure
    if not services.diskResume or failed.error != DiskStoreError.FileFailure: return created
    if failed.fileError != FileError.AlreadyExists: return created
    # Only explicit independently configured genesis/import authority can retry an existing failed bootstrap; CURRENT is never overwritten.
    initializePagedDiskChain(services.disk, path, services.diskId, services.canonical,
        services.diskLimits, replay = true)
  elif services.diskManaged:
    initializeManagedDiskChain(services.disk, path, services.diskId, services.canonical,
        managedPolicy(services.diskLimits))
  else:
    initializeDiskChain(services.disk, path, services.diskId, services.canonical,
        services.diskLimits)

proc maintenanceDue(services: var Services): bool =
  ## Inspect only cached scalar usage while idle; a header-only journal never triggers repeated no-op replacement.
  if not services.diskManaged or services.diskFaulted or uint64(services.compactBytes) ==
      0: return false
  let usage = services.disk.managedDiskUsage
  if usage.error != FileError.None:
    services.diskFaulted = true
    return false
  usage.value.journalBytes > uint64(ManagedJournalHeaderBytes) and
    usage.value.journalBytes >= uint64(services.compactBytes)

proc setupDisk(services: var Services, options: Options, limits: StateStoreLimits,
    imported: bool): bool {.raises.} =
  ## Derive chain identity from the selected configured genesis; imports create exclusively and never replace a local DB.
  let seed = initApplicationChain(services.chainText, limits)
  if seed.error != ApplicationChainError.None: return false
  var identity: seq[byte] = @[]
  for character in "RAGNAROK-CHAIN-V1\n": identity.add(byte(character))
  for octet in array[32, byte](seed.value.chainView.bestBlock.value.blockHash): identity.add(octet)
  for octet in array[32, byte](seed.value.stateSnapshot.value.commitment.root): identity.add(octet)
  for octet in seed.value.chainView.bestBlock.value.chainParameters.encodeParameters: identity.add(octet)
  let digest = blake2b256(identity)
  if digest.error != CryptoError.None: return false
  services.diskId = StorageChainId(array[32, byte](digest.value))
  services.diskLimits = diskJournalLimits(limits)
  services.diskManaged = options.managedStorage
  services.diskPaged = options.pagedStorage
  services.diskResume = options.resumePagedStorage
  services.compactBytes = if services.diskManaged: options.stateCompactionBytes else: ByteLimit(0)
  if options.stateMigration:
    if imported: return false # Independently imported authority cannot be mixed with a local legacy source.
    var legacy = default(DiskStateStore)
    defer:
      if legacy.opened: discard legacy.close
    let recovered = openDiskChain(legacy, options.stateMigrationSource, services.diskId,
      seed.value.chainView.bestBlock.value.chainParameters, limits, services.diskLimits)
    if recovered.error != DiskChainError.None: return false
    let migrated = migrateDiskChain(legacy, services.disk, options.stateDatabase, services.diskId,
      recovered.value, managedPolicy(services.diskLimits))
    if migrated.error != DiskChainError.None: return false
    if legacy.close != FileError.None: return false # A valid destination may remain after retirement refusal; it is never overwritten on retry.
    services.canonical = recovered.value
  elif imported:
    if services.initializeSelectedDisk(options.stateDatabase).error !=
        DiskChainError.None: return false
  else:
    let opened = if services.diskPaged:
      openPagedDiskChain(services.disk, options.stateDatabase, services.diskId,
        seed.value.chainView.bestBlock.value.chainParameters, limits, services.diskLimits)
    elif services.diskManaged:
      openManagedDiskChain(services.disk, options.stateDatabase, services.diskId,
        seed.value.chainView.bestBlock.value.chainParameters, limits, managedPolicy(
            services.diskLimits))
    else:
      openDiskChain(services.disk, options.stateDatabase, services.diskId,
        seed.value.chainView.bestBlock.value.chainParameters, limits, services.diskLimits)
    if opened.error == DiskChainError.None:
      services.canonical = opened.value # Local restart preserves bounded history and explicit finality.
    else:
      if options.argumentCount > 0 and options.argument(1) ==
          "history": return false # Offline reads never create a database or substitute configured genesis.
      if opened.error != DiskChainError.StoreFailure: return false
      if opened.storeFailure.error != DiskStoreError.FileFailure: return false
      if opened.storeFailure.fileError != FileError.IoFailure: return false
      let created = services.initializeSelectedDisk(options.stateDatabase)
      if created.error != DiskChainError.None:
        return false # O_EXCL prevents a failed open from overwriting any existing or concurrently created file.
  if options.retentionSpecified:
    let configured = configureDiskHistory(services.disk, services.canonical, services.diskId,
      options.retentionPolicy, services.diskLimits.contextBytes)
    if configured.error != DiskChainError.None: return false
  services.reportHistoryCleanup() # Existing indexed policies remain selected when no override was supplied.
  services.diskRetirement = default(PreparedPagedRetirement)
  services.retirementCompletion = default(DiskPublicationCompletion)
  services.retirementDelayed = false
  services.retirementAttempt = default(MonoTime)
  services.diskMaintenance = default(PreparedDiskMaintenance)
  services.maintenanceStage = default(DiskChainResult[PreparedDiskMaintenance])
  services.maintenanceCompletion = default(DiskPublicationCompletion)
  services.maintenanceAdmission = DiskWorkerError.Uninitialized
  services.startupMaintenance = default(DiskChainResult[ManagedCompaction])
  services.diskOperation = ServiceDiskOperation.Publication
  if services.diskManaged and uint64(services.compactBytes) > 0:
    # Physical and canonical validation precede bounded cleanup; zero preserves staged forensic files.
    if services.disk.cleanupManagedDiskFiles != FileError.None: return false
  if services.maintenanceDue():
    let prepared = prepareDiskMaintenance(services.disk, services.canonical, services.diskId,
      services.diskLimits.contextBytes)
    if prepared.error != DiskChainError.None:
      services.maintenanceStage = prepared
      return false
    services.startupMaintenance = commitDiskMaintenance(services.disk, prepared.value)
    if services.startupMaintenance.error != DiskChainError.None: return false
    if services.startupMaintenance.value.cleanup != FileError.None: return false
  if services.diskFaulted: return false # Startup has no callbacks/listeners or foreign ARC borrowers yet.
  services.diskEnabled = true
  services.diskStageOutcome = default(DiskChainResult[PreparedDiskPublication])
  services.currentDiskStageOutcome = default(DiskChainResult[PreparedCurrentDiskPublication])
  services.currentDiskPublication = default(PreparedCurrentDiskPublication)
  services.currentDiskAdmission = DiskWorkerError.Uninitialized
  services.diskCommitOutcome = default(DiskChainResult[RepositoryGeneration])
  try:
    if not services.diskWorker.start(): return false # Exactly one idle native thread is started at the final Services address.
  except:
    services.close()
    raise # No startup exception may leave a live disk lock or borrower.
  true

proc startServices(services: var Services, options: Options, role: string,
    withState: bool, limits: StateStoreLimits, recovered: ApplicationChain): bool {.raises.} =
  ## Capture one bounded file and install the optional canonical owner before listeners become observable.
  if services.started or not options.valid(): return false # Repeat start cannot disturb an existing lifetime.

  if options.recoveryEnabled and recovered.chainView.retainedCount == 0:
    return false # Parsed import intent cannot silently select ordinary genesis startup.
  services.historyLimits = limits
  services.historyLog = options.logWriter
  services.chainText = boundedFile(options.chainPath(), MaxChainBytes)
  var identity = default(ChainIdentity)
  if withState:
    if recovered.chainView.retainedCount > 0:
      let configured = configuredParameters(services.chainText)
      let head = recovered.chainView.bestBlock.value
      if not configured.ok or configured.value.encodeParameters !=
          head.chainParameters.encodeParameters:
        services.close() # A trusted anchor must still match the complete explicitly selected chain profile.
        return false
      let network = readNetworkIdentity(services.chainText)
      if network.error == NetworkIdentityError.None:
        services.networkBase = genesisAlpn(network.value.genesisHash)
      if options.rpcPort() != 0 or options.mcpPort() != 0:
        identity = chainIdentity(configuredGenesis(services.chainText,
            configured.value)) # Imported head is never genesis identity.
      services.canonical = recovered # Preserve the exact restored map, inherited policy and one-head/unfinalized view.
    else:
      let seeded = initApplicationChain(services.chainText, limits)
      if seeded.error != ApplicationChainError.None:
        services.close() # A missing/refused seed cannot become a partial listener-only startup.
        return false
      services.canonical = seeded.value
      services.networkBase = genesisAlpn(seeded.value.chainView.bestBlock.value.blockHash)
      identity = chainIdentity(seeded.value.chainView.bestBlock) # Reuse capture without repeating map/header hashing.
  if withState:
    services.startupAnchor = captureStartupAnchor(
        services.canonical.chainView) # Capture the independent seed/recovery checkpoint before restored unfinalized children can replace bestBlock.
  if options.diskStorage:
    if not withState or not services.setupDisk(options, limits, recovered.chainView.retainedCount > 0):
      services.close()
      return false # Backend failure never falls back to ephemeral memory or another chain.
  elif withState and options.retentionSpecified:
    # Seed the independent memory index before shrinking its complete-state live window.
    let indexed = services.canonical.chainView.withHistoricalPolicy(options.retentionPolicy)
    if indexed.error != HistoryError.None:
      services.close()
      return false
    let policy = options.retentionPolicy
    let count = if policy.archive: DefaultRetainedBlocks else: min(DefaultRetainedBlocks,
        policy.retainedBlocks)
    let window = indexed.value.withRetentionLimit(ElementLimit(count))
    if window.error != ViewAdvanceError.None:
      services.close()
      return false
    let selected = initApplicationChain(window.value)
    if selected.error != ApplicationChainError.None:
      services.close()
      return false
    services.canonical = selected.value # Complete current state and header-only validation inputs are unchanged.
  if not services.ui.start(options.uiPort(), options.devUiDirectory(), options.logWriter):
    stderr.writeLine("Invalid UI listener or --ui-dev-dir")
    services.close() # Failed startup cannot retain a directory, seed or partially opened listener.
    return false
  var rpcReady = false
  if withState:
    let head = services.canonical.chainView.bestBlock
    let parameters = decodeParameters(head.value.chainParameters.encodeParameters)
    if options.mcpPort != 0:
      services.mcpInfo = ClientInfo(role: role, parameters: parameters, identity: identity)
    rpcReady = services.rpc.start(options.rpcPort(), role, parameters, services.canonical.chainView,
        options.uiPort(), identity)
  else:
    rpcReady = services.rpc.setupRpc(options, role,
        services.chainText, services.mcpInfo, services.networkBase) # Preserve legacy optional/unavailable genesis behavior.
  if not rpcReady:
    stderr.writeLine("Invalid RPC listener or --chain parameters")
    services.close() # RPC failures retire both the UI listener and the canonical owner.
    return false
  if options.rpcPort() != 0:
    log(options.logWriter, LogTarget.Rpc, LogLevel.Info, "RPC listener started port=" &
        $options.rpcPort())
  if not services.mcp.start(options.mcpPort, options.logWriter):
    stderr.writeLine("Invalid MCP listener; check --mcp-port")
    services.close()
    return false # Partial startup retires every already opened endpoint.
  services.chainRpc = withState and options.rpcPort() != 0
  # Enable autonomous full-state proof jobs only where the dispatcher retains no
  # external parent aliases across turns. Download orchestration keeps its own lease.
  if services.chainRpc and options.argument(1) in ["server", "client", "mesh"]:
    discard services.rpc.enableStateProofs() # These dispatcher shapes retain no external canonical aliases across turns.
  let database = if options.diskStorage: options.stateDatabase else: ""
  let managementInfo = ManagementInfo(role: role, chainPath: options.chainPath,
    databasePath: database, stateEnabled: withState)
  if not services.management.start(options.managementSocket, managementInfo, options.logWriter):
    stderr.writeLine("Invalid management socket; select an absent path in an owned private directory")
    services.close() # A refused management listener rolls back every previously started service.
    return false
  services.historyLog = options.logWriter
  if withState and options.pvmBackend == PvmBackend.Jit:
    services.nativeRuntime = newNativeRuntime()
    try:
      discard services.nativeRuntime.start() # Unsupported hosts keep checked execution with no compiler thread.
      services.executionContext.bindNativeRuntime(services.nativeRuntime)
    except:
      services.close()
      raise
  services.started = true
  services.rpcStarted = options.rpcPort != 0
  services.uiStarted = options.uiPort != 0
  services.managementStarted = options.managementSocket.len > 0
  services.telemetryStarted = options.telemetryEnabled
  services.storageStarted = options.stateEnabled
  logServiceStartup(options)
  true

type LightStartup = object ## Fixed configured/trusted metadata retains no complete genesis StateStore or ChainView.
  ready: bool
  trust: TrustedApplicationCheckpoint
  policy: LightRuntimePolicy
  parameters: ParameterResult
  identity: ChainIdentity
  networkBase: string

proc captureLightStartup(text: string, options: Options): LightStartup =
  ## Complete configured genesis is transient validation input only; every full-state alias retires before listeners/workers become observable.
  let parameters = configuredParameters(text)
  if not parameters.ok: return default(LightStartup) # Explicit configuration cannot be guessed from partial proofs.
  let genesis = configuredGenesis(text, parameters.value)
  if genesis.error != GenesisError.None: return default(
      LightStartup) # Header geometry/network identity require complete independently configured genesis.
  let trust = loadCheckpointTrust(options.lightTrustPath, options.lightHeaderPath,
    ByteLimit(uint64(MaxRecoveryHeaderBytes+ApplicationCheckpointIdentityBytes)))
  if trust.error != CheckpointTrustError.None: return default(
      LightStartup) # Missing/malformed independent current authority never falls back to genesis.
  if trust.value.identity.parameters.encodeParameters !=
      parameters.value.encodeParameters: return default(
      LightStartup) # A current checkpoint must belong to the configured fetch profile.
  let selected = genesis.value
  let profile = HeaderConfig(cores: selected.cores, authorValidators: selected.activeValidators,
    epochSlots: selected.epochSlots, maxBytes: ByteLimit(262144))
  var domain: seq[byte] = @[]
  for character in "RAGNAROK-CHAIN-V1\n": domain.add(byte(
      character)) # Same independently configured network identity domain as full storage.
  for octet in array[32, byte](selected.blockHash): domain.add(octet)
  for octet in array[32, byte](selected.stateRoot): domain.add(octet)
  for octet in selected.chainParameters.encodeParameters: domain.add(octet)
  let digest = blake2b256(domain)
  if digest.error != CryptoError.None: return default(
      LightStartup) # No default chain identity escapes backend failure.
  let policy = lightRuntimePolicy(StorageChainId(array[32, byte](digest.value)),
      trust.value.identity.stateRoot, profile)
  LightStartup(ready: true, trust: trust.value, policy: policy, parameters: parameters,
    identity: chainIdentity(genesis), networkBase: genesisAlpn(selected.blockHash))

proc startLightServices(services: var Services, options: Options, role: string): bool {.raises.} =
  ## Light startup chooses distinct memory/paged ownership with independent current trust before any listener is exposed.
  if services.started or not options.valid or not options.lightMode: return false # Failed/repeated mode selection cannot disturb an existing lifetime.
  services.chainText = boundedFile(options.chainPath, MaxChainBytes)
  let startup = captureLightStartup(services.chainText, options)
  services.networkBase = startup.networkBase
  if not startup.ready:
    services.close()
    return false # No complete/partial startup prefix becomes an active service.
  var ready = false
  defer:
    if not ready: services.close() # Join every partial acquisition before rollback or exception propagation.
  if not services.ui.start(options.uiPort, options.devUiDirectory, options.logWriter): return false
  let path = if options.diskStorage: options.stateDatabase else: ""
  if not services.light.start(services.rpc, role, options.rpcPort, options.uiPort,
      options.diskStorage, path, startup.trust, startup.policy, startup.parameters,
      startup.identity): return false
  if options.mcpPort != 0:
    services.mcpInfo = ClientInfo(role: role, parameters: startup.parameters,
      identity: startup.identity,
      lightDisk: options.diskStorage) # Fixed metadata retains no complete configured genesis map.
  if not services.mcp.start(options.mcpPort, options.logWriter): return false
  let info = ManagementInfo(role: role, chainPath: options.chainPath, databasePath: path,
      stateEnabled: true)
  if not services.management.start(options.managementSocket,
      info, options.logWriter): return false # Static management remains separate from complete-map execution controls.
  if not options.telemetryEnabled: services.chainText = "" # No raw configured genesis is retained during ordinary light runtime.
  services.chainRpc = options.rpcPort != 0
  services.historyLog = options.logWriter
  services.started = true
  services.rpcStarted = options.rpcPort != 0
  services.uiStarted = options.uiPort != 0
  services.managementStarted = options.managementSocket.len > 0
  services.telemetryStarted = options.telemetryEnabled
  services.storageStarted = options.stateEnabled
  logServiceStartup(options)
  ready = true
  true

proc lightHead*(services: Services): light_actor.LightRuntimeResult[LightApplicationHead] =
  ## Distinct partial-state access is gated before any shared handle copy and never returns a complete StateStore snapshot.
  services.light.head

proc lightDiskPhase*(services: var Services): DiskWorkerPhase =
  ## Synchronized phase polling never copies the still-leased native outcome.
  services.light.diskPhase

func lightDiskActive*(services: Services): bool =
  ## Scalar IO observation remains safe while native publication/retirement borrows partial graphs.
  services.light.diskActive

func lightStorageFaulted*(services: Services): bool =
  ## Uncertain mutation outcomes disable writes without withdrawing immutable known evidence.
  services.light.storageFaulted

func lightMode*(services: Services): bool =
  ## Selected active ownership remains independent of memory/disk backend choice.
  services.light.active

proc lightDiskCompletion*(services: Services): DiskPublicationCompletion {.requires: not services.light.busy.} =
  ## Actual light IO outcomes survive joined shutdown; no full publication generation is fabricated.
  services.light.diskCompletion

proc startConfigured(services: var Services, options: Options, role: string,
    withState: bool, limits: StateStoreLimits): bool {.raises.} =
  ## Both public startup policies share one explicit import dispatcher before any listener becomes visible.
  if services.started or not options.valid:
    return false # Live/default startup cannot trigger trust or checkpoint I/O.
  if options.recoveryEnabled:
    if not withState: return false # Imported complete state cannot enter a listener-only startup.
    let trustLimit = ByteLimit(uint64(MaxRecoveryHeaderBytes + ApplicationCheckpointIdentityBytes))
    let trust = loadCheckpointTrust(options.recoveryTrustPath, options.recoveryHeaderPath, trustLimit)
    if trust.error != CheckpointTrustError.None:
      return false # Missing or mismatched independent trust never falls back to configured genesis.
    let recovered = loadTrustedCheckpoint(options.recoveryPath, trust.value, limits,
        options.recoveryByteLimit)
    if recovered.error != ApplicationRecoveryError.None:
      return false # Native/context/map/header refusal grants no partial canonical owner.
    return startServices(services, options, role, true, limits, recovered.value)
  startServices(services, options, role, withState, limits, default(ApplicationChain))

proc start*(services: var Services, options: Options, role: string): bool {.raises.} =
  ## Select canonical startup only from validated explicit CLI policy; legacy commands retain optional genesis behavior.
  if options.lightMode: return services.startLightServices(options,
      role) # Complete-state initialization is a separate selected mode.
  var limits = genesisStoreLimits()
  if options.stateEnabled:
    limits.writes = options.stateWrites # Fixed trie ceilings never imply a mutable budget.
    limits.writeValueBytes = options.stateWriteBytes
    return startConfigured(services, options, role, true, limits)
  startConfigured(services, options, role, false, limits)

proc start*(services: var Services, options: Options, role: string,
    limits: StateStoreLimits): bool {.raises.} =
  ## Explicitly enable canonical complete-state ownership, sharing the exact seed with optional RPC.
  if options.lightMode: return false # Explicit complete-map component policy cannot silently become partial light ownership.
  startConfigured(services, options, role, true, limits)

proc startRecovered*(services: var Services, options: Options, role: string,
    recovered: ApplicationRecoveryResult): bool {.raises.} =
  ## Explicit component recovery preserves its caller-selected map policy, like the existing explicit-limits startup overload.
  ## CLI recovery must restore with its parsed policy before calling this entry point; no map policy is widened here.
  if options.lightMode: return false # Complete recovered maps never enter a partial light actor.
  if services.started or not options.valid or not options.stateEnabled:
    return false # Failed/repeated admission must not read files or disturb active services.
  if recovered.error != ApplicationRecoveryError.None:
    return false # Refused/default recovery never falls back to configured genesis.
  startServices(services, options, role, true, genesisStoreLimits(), recovered.value)

func chainView*(services: Services): ChainView {.requires: not (services.proofing or
    services.preparing or services.publishing).} =
  ## Return an immutable selected-history alias; default/closed/legacy services have no canonical head.
  services.canonical.chainView

proc publishFinalized*(services: var Services, hash: BlockHash): ViewFinalizeError =
  ## Trusted local consensus/checkpoint input only: no proof is verified or authority inferred from peer claims.
  if not services.stateProofAvailable: return ViewFinalizeError.Uninitialized
  result = if services.chainRpc: services.canonical.publishFinalized(services.rpc, hash)
    else: services.canonical.publishFinalized(hash)
  if result == ViewFinalizeError.None:
    services.auditBranches.retire(services.canonical.chainView)

proc describeHead*(services: Services): string =
  ## Busy workers exclude every graph read; diagnostics cannot extend an RPC/canonical lease.
  if services.proofing or services.preparing or services.publishing or services.light.busy:
    return "best: busy, finalized: unavailable"
  if services.light.active:
    let metadata = services.light.queryMetadata
    if metadata.len == 0: return "best: unavailable, finalized: unavailable"
    let identity = metadata.current.identity
    return "best: light slot " & $identity.slot & " (" &
      shortHash(array[32, byte](identity.blockHash)) & "), finalized: unavailable"
  services.canonical.describeHead

proc historicalSnapshot*(services: var Services, hash: BlockHash): HistoryResult[ApplicationChain] =
  ## Synchronous startup/offline or explicitly excluded IO only; never call from a dispatcher callback.
  if not services.started: return historyFailure[ApplicationChain](HistoryError.Uninitialized)
  if services.light.active: return historyFailure[ApplicationChain](HistoryError.InvalidPolicy)
  if services.proofing or services.preparing or services.publishing:
    return historyFailure[ApplicationChain](HistoryError.Busy)
  if services.diskEnabled:
    return readDiskHistoricalSnapshot(services.disk, services.canonical, services.diskId, hash,
      services.historyLimits, services.diskLimits.contextBytes)
  let saved = services.canonical.chainView.historicalBlockAt(hash)
  if saved.error != GenesisError.None: return historyFailure[ApplicationChain](
      HistoryError.Unavailable)
  let owner = initApplicationChain(genesisView(saved))
  if owner.error != ApplicationChainError.None: return historyFailure[ApplicationChain](
      HistoryError.InvalidFormat)
  historySuccess(owner.value)

proc historicalSnapshot*(services: var Services, ordinal: HistoryOrdinal): HistoryResult[
    ApplicationChain] =
  ## Local ordinal addressing is a disk-index capability; memory callers select an exact block hash.
  if not services.started: return historyFailure[ApplicationChain](HistoryError.Uninitialized)
  if services.light.active: return historyFailure[ApplicationChain](HistoryError.InvalidPolicy)
  if services.proofing or services.preparing or services.publishing:
    return historyFailure[ApplicationChain](HistoryError.Busy)
  if not services.diskEnabled: return historyFailure[ApplicationChain](HistoryError.Unavailable)
  readDiskHistoricalSnapshot(services.disk, services.canonical, services.diskId, ordinal,
    services.historyLimits, services.diskLimits.contextBytes)

func historicalCleanupError*(services: Services): HistoryError =
  ## Observe actual cleanup diagnostics only when no worker can mutate the disk owner.
  if services.proofing or services.preparing or services.publishing: return HistoryError.Busy
  if not services.diskEnabled: return HistoryError.Unavailable
  services.disk.historyCleanupError

proc startCheckpointExport*(services: var Services,
    path: string): ApplicationCheckpointFileError {.raises.} =
  ## Explicit host startup requires an active stable service owner; pending shutdown acknowledgement blocks worker restart.
  if not services.started: return ApplicationCheckpointFileError.Uninitialized
  services.checkpointExport.start(path)

proc checkpointExportPhase*(services: var Services): ApplicationCheckpointWorkerPhase =
  ## Bounded scalar polling performs no serialization, canonical graph access or file I/O.
  services.checkpointExport.phase

proc stageCheckpointExport*(services: var Services, prepared: var PreparedApplicationCheckpoint,
    limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Stage only independent bytes, including during an execution lease; refusal preserves the caller's sole owner.
  services.checkpointExport.stage(prepared, limit)

proc beginCheckpointExport*(services: var Services, ticket: ApplicationCheckpointTicket): bool =
  ## Explicit bounded dispatch authorizes a matching staged native publication.
  services.checkpointExport.begin(ticket)

proc cancelCheckpointExport*(services: var Services, ticket: ApplicationCheckpointTicket): bool =
  ## Cancel only unstarted matching work; possible publication outcomes stay observable.
  services.checkpointExport.cancel(ticket)

proc peekCheckpointExport*(services: var Services,
    ticket: ApplicationCheckpointTicket): ApplicationCheckpointCompletion =
  ## Fixed receipt observation retains acknowledgement capacity and never touches canonical state.
  services.checkpointExport.peek(ticket)

proc collectCheckpointExport*(services: var Services,
    ticket: ApplicationCheckpointTicket): ApplicationCheckpointCompletion =
  ## Host acknowledgement retires sole bytes only after native aliases have ended.
  services.checkpointExport.collect(ticket)

func checkpointShutdownPending*(services: Services): bool =
  ## A fixed actual joined receipt survives canonical/listener close and repeated aggregate cleanup.
  services.checkpointExport.shutdownPending

func checkpointShutdown*(services: Services): ApplicationCheckpointShutdown =
  ## Only a retained shutdown journal grants its exact operation and retirement outcomes.
  services.checkpointExport.shutdown

proc takeCheckpointShutdown*(services: var Services): ApplicationCheckpointShutdown =
  ## Explicit acknowledgement unblocks export restart without retrying or adopting a possibly published state.
  services.checkpointExport.takeShutdown()

proc checkpointIdentity*(services: Services): ApplicationCheckpointIdentityResult {.requires: not (
    services.proofing or services.preparing or services.publishing).} =
  ## Capture fixed context only while canonical aliases are available; no file metadata supplies independent trust.
  captureApplicationCheckpointIdentity(services.canonical)

proc prepareCheckpoint*(services: Services, limit: ByteLimit): PreparedApplicationCheckpoint {.requires: not (
    services.proofing or services.preparing or services.publishing).} =
  ## Explicit host-side serialization runs outside callbacks and before any detached I/O admission or execution lease.
  prepareApplicationCheckpoint(services.canonical, limit)

proc stateSnapshot*(services: Services): StateStoreResult[StateStoreSnapshot] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Retain only immutable complete state independently of listener lifetime and future adoption.
  services.canonical.stateSnapshot

proc applyAccumulation*(services: var Services, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): ApplicationChainResult[BlockSnapshot] {.requires:
    not (services.proofing or services.preparing or services.publishing) and
      services.currentAdoption.phase == CurrentHandoffPhase.Idle.} =
  ## Publish between dispatcher turns using the startup RPC choice; enabled-listener refusal never falls back.
  if services.diskEnabled: return durabilityRequired() # Explicit disk consumers enqueue and poll; dispatcher IO must stay nonblocking.
  if services.chainRpc:
    services.canonical.applyAccumulation(services.rpc, source,
        limits) # Join all three handles before notifications.
  else:
    services.canonical.applyAccumulation(source, limits) # Disabled/default canonical owners still use existing guarded adoption.

func accumulationStage*(services: Services): AccumulationHandoffStage =
  ## Physical cleanup preserves completed adoption and delays graph-bearing acknowledgement until the lease ends.
  if services.publishing and services.diskOperation in
      {ServiceDiskOperation.Maintenance, ServiceDiskOperation.Retirement}: return AccumulationHandoffStage.Publishing
  services.adoption.stage

proc enqueueAccumulation*(services: var Services, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): AccumulationEnqueueError {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Hand one finalized candidate to the next dispatcher turn; canonical authority is rechecked at adoption.
  if services.currentAdoption.phase != CurrentHandoffPhase.Idle: return AccumulationEnqueueError.Busy
  services.adoption.enqueue(services.canonical, source, limits)

proc enqueueCandidate*(services: var Services, candidate: OwnedBlock,
    ancestors: openArray[OwnedHeader], limits: ApplicationCandidateLimits,
    composition: AccumulationCompositionLimits): ApplicationCandidateResult {.requires:
    not (services.proofing or services.preparing or services.publishing) and
      services.currentAdoption.phase == CurrentHandoffPhase.Idle.} =
  ## Prepare from this selected head and queue the genuine successor; publication waits for the next service tick.
  services.adoption.enqueueCandidate(services.canonical, candidate, ancestors, limits, composition,
    residency = addr services.executionContext)

proc beginBlockInput*(services: Services, input: var BlockInput, extent: ByteLimit,
    ancestors: openArray[OwnedHeader], resources: BlockInputLimits,
    policies: ApplicationCandidateLimits): BlockInputAdmission {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Bind bounded reception to this exact canonical history without preparing or publishing a block.
  input.begin(services.canonical, extent, ancestors, resources, policies)

proc enqueueBlockInput*(services: var Services, input: var BlockInput, id: BlockInputId,
    composition: AccumulationCompositionLimits): BlockInputResult {.requires:
    not (services.proofing or services.preparing or services.publishing) and
      services.currentAdoption.phase == CurrentHandoffPhase.Idle.} =
  ## Explicit producer work runs outside transport callbacks; finalized success waits for a later adoption tick.
  input.enqueue(id, services.canonical, services.adoption, composition,
      residency = addr services.executionContext)

func currentAccumulationPhase*(services: Services): CurrentHandoffPhase =
  ## Physical cleanup delays graph-bearing acknowledgment until the shared native lease ends.
  if services.publishing and services.diskOperation in {ServiceDiskOperation.Maintenance,
      ServiceDiskOperation.Retirement}:
    return CurrentHandoffPhase.Publishing
  services.currentAdoption.phase

proc enqueueCurrentAccumulation*(services: var Services,
    update: PreparedCurrentChainUpdate): CurrentHandoffAdmission =
  ## Share producer capacity with legacy work and reject native/disk exclusion before canonical graph reads.
  if services.proofing or services.preparing or services.publishing:
    return CurrentHandoffAdmission.Busy # Cancellation and Done do not release an outstanding native lease.
  if services.adoption.stage != AccumulationHandoffStage.Idle:
    return CurrentHandoffAdmission.Busy # A legacy pending or unacknowledged outcome retains producer capacity.
  if not services.started or services.diskFaulted:
    return CurrentHandoffAdmission.Unavailable # No current job can bypass closed ownership or uncertain physical state.
  services.currentAdoption.enqueue(services.canonical, update)

proc takeCurrentAccumulation*(services: var Services): CurrentHandoffResult {.requires:
    not (services.proofing or services.preparing or services.publishing) and
      services.currentAdoption.phase == CurrentHandoffPhase.Finished.} =
  ## Acknowledge only the retained current installation result after every native lease ends.
  result = services.currentAdoption.take()
  if result.error == CurrentHandoffError.None:
    log(services.historyLog, LogTarget.Application, LogLevel.Info, "Imported block, " &
        services.describeHead)
  else:
    log(services.historyLog, LogTarget.Application, LogLevel.Warn, "Block import rejected: " & $result.error)

proc cancelCurrentAccumulation*(services: var Services): bool =
  ## Cancellation cannot revoke publication or release a preparation/proof/disk borrow.
  if services.proofing or services.preparing or services.publishing: return false
  services.currentAdoption.cancel()

proc beginBlockInput*(services: Services, input: var CurrentBlockInput, extent: ByteLimit,
    ancestors: openArray[OwnedHeader], resources: CurrentBlockInputLimits,
    policies: CurrentCandidateLimits): CurrentBlockInputAdmission {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Current reception binds the canonical parent and frozen policies before a later native execution lease.
  input.begin(services.canonical, extent, ancestors, resources, policies)

func stateProofActive*(services: Services): bool =
  ## Cancelled and Done proof jobs retain exclusion until exact collection or joined stop.
  services.proofing or services.light.proofActive

proc stateProofAvailable*(services: Services): bool =
  ## Reject scalar exclusions before creating any temporary canonical ARC alias.
  if services.light.active: return false # Complete-map/logical proof entry points cannot borrow partial light state.
  if not services.started or services.proofing or services.preparing or services.publishing:
    return false # A native borrower owns the graph or no stable service owner exists.
  if services.diskFaulted or services.rpc.chainPaused:
    return false # Uncertain IO and foreign RPC suspension cannot grant proof access.
  if services.adoption.stage != AccumulationHandoffStage.Idle or
      services.currentAdoption.phase != CurrentHandoffPhase.Idle:
    return false # Pending/unacknowledged adoption retains its existing exclusive producer capacity.
  services.canonical.stateSnapshot.error == StateStoreError.None

proc stageStateProof(services: var Services, selected: BlockHash, plan: StateProofPlan,
    limits: ProofQueryLimits): ProofQueryError =
  ## This activation and all its canonical ARC aliases retire BEFORE the worker can start.
  let captured = captureProofQuery(services.canonical.chainView.blockAt(selected), plan, limits)
  if captured.error == ProofQueryError.None:
    services.proofInput = captured.value # One staged owner survives after every temporary alias retires.
  captured.error

proc stageStateProof(services: var Services, selected: BlockHash, plan: ServiceProofPlan,
    limits: ProofQueryLimits): ProofQueryError =
  ## This activation and all its canonical ARC aliases retire BEFORE the worker can start.
  let captured = captureProofQuery(services.canonical.chainView.blockAt(selected), plan, limits)
  if captured.error == ProofQueryError.None:
    services.proofInput = captured.value # One staged owner survives after every temporary alias retires.
  captured.error

proc finishStateProof(services: var Services, reason: ProofQueryError): StateProofAdmission =
  ## Staging activations have retired; only this common path may pause RPC and submit the private query.
  if reason != ProofQueryError.None:
    return StateProofAdmission(status: StateProofAdmissionError.QueryFailure, queryReason: reason)
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.proofInput = default(ProofQuery)
    return StateProofAdmission(status: StateProofAdmissionError.Busy)
  let admitted = services.proofWorker.submit(services.proofInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true # Only scalar/ticket operations follow successful native submission.
    return StateProofAdmission(status: StateProofAdmissionError.None, ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.proofInput = default(ProofQuery) # A refusal never grants the worker access to this owner.
  StateProofAdmission(status: StateProofAdmissionError.WorkerFailure, workerReason: admitted.error)

func error*(outcome: NetworkReadStart): StateProofAdmissionError =
  ## Observe the managed start without exposing lease authority.
  outcome.status

func value*(outcome: NetworkReadStart): ProofWorkerTicket {.requires: outcome.status ==
    StateProofAdmissionError.None.} =
  ## Only successful native submission exposes its exact retirement ticket.
  outcome.ticket

func readError*(outcome: NetworkReadStart): ReadError {.requires: outcome.status ==
    StateProofAdmissionError.QueryFailure.} =
  ## Preserve source/admission refusal without claiming a partial reply.
  outcome.readReason

func workerError*(outcome: NetworkReadStart): ProofWorkerError {.requires: outcome.status ==
    StateProofAdmissionError.WorkerFailure.} =
  ## Expose native worker admission refusal only in its matching alternative.
  outcome.workerReason

func error*(outcome: ReadVerificationStart): StateProofAdmissionError =
  ## Observe admission failure without granting a partially captured verification job.
  outcome.status

func value*(outcome: ReadVerificationStart): ProofWorkerTicket {.requires: outcome.status ==
    StateProofAdmissionError.None.} =
  ## Only successful native admission grants this exact lease collection identity.
  outcome.ticket

func verificationError*(outcome: ReadVerificationStart): ReadVerificationError {.requires: outcome.status ==
    StateProofAdmissionError.QueryFailure.} =
  ## Capture refusals remain distinct from later CPU proof/hash failures.
  outcome.verificationReason

func workerError*(outcome: ReadVerificationStart): ProofWorkerError {.requires: outcome.status ==
    StateProofAdmissionError.WorkerFailure.} =
  ## A native admission cause exists only in its matching failed alternative.
  outcome.workerReason

proc stageReadVerification(services: var Services, request: ReadRequest,
    wire: openArray[byte], limits: ReadVerificationLimits): ReadVerificationError =
  ## All canonical aliases retire with this activation; only fresh wire/fixed metadata remain for CPU work.
  let captured = captureReadVerification(services.canonical.chainView, request, wire, limits)
  if captured.error == ReadVerificationError.None: services.verificationInput = captured.value
  captured.error

proc beginReadVerification*(services: var Services, request: ReadRequest,
    wire: openArray[byte], limits: ReadVerificationLimits): ReadVerificationStart {.raises.} =
  ## Full-state Services selects trusted roots before submission; partial/light state has a separate owner contract.
  if not services.started: return ReadVerificationStart(status: StateProofAdmissionError.Closed)
  if services.light.active: return ReadVerificationStart(
    status: StateProofAdmissionError.QueryFailure,
    verificationReason: ReadVerificationError.NoSource)
  if not services.stateProofAvailable: return ReadVerificationStart(
      status: StateProofAdmissionError.Busy)
  discard services.proofWorker.start()
  let captured = services.stageReadVerification(request, wire, limits)
  if captured != ReadVerificationError.None: return ReadVerificationStart(
    status: StateProofAdmissionError.QueryFailure, verificationReason: captured)
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.verificationInput = default(ReadVerificationJob)
    return ReadVerificationStart(status: StateProofAdmissionError.Busy)
  let admitted = services.proofWorker.submit(services.verificationInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true # Cancellation/Done still retain the exact lease until collection or joined stop.
    return ReadVerificationStart(status: StateProofAdmissionError.None, ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.verificationInput = default(ReadVerificationJob)
  ReadVerificationStart(status: StateProofAdmissionError.WorkerFailure,
      workerReason: admitted.error)

func error*(started: NetworkTicketStart): StateProofAdmissionError =
  ## Observe admission without granting a failed/default worker ticket.
  started.status

func value*(started: NetworkTicketStart): ProofWorkerTicket {.requires: started.status ==
    StateProofAdmissionError.None.} =
  ## Exact accepted submission owns the shared graph/RPC lease until collection or joined close.
  started.ticket

func captureFailure*(started: NetworkTicketStart): NetworkTicketResult[
    TicketSource] {.requires: started.status == StateProofAdmissionError.QueryFailure.} =
  ## Preserve actual source/input refusal and genuine failed chapter/hash causes without an accepted source.
  started.captureReason

func workerError*(started: NetworkTicketStart): ProofWorkerError {.requires: started.status ==
    StateProofAdmissionError.WorkerFailure.} =
  ## Only an actual failed worker admission exposes its child cause.
  started.workerReason

proc stageTicketSource(services: var Services): NetworkTicketResult[TicketSource] =
  ## Canonical aliases retire in this activation; the cache owns only fresh decoded fixed metadata and immutable rosters.
  let finalized = services.canonical.chainView.finalizedBlock
  if finalized.error != GenesisError.None: return ticketFailure[TicketSource](
      NetworkTicketError.NoSource)
  var reuse = false
  if services.ticketSource.error == NetworkTicketError.None:
    let cached = services.ticketSource.value
    let sameBlock = array[32, byte](cached.sourceBlock) == array[32, byte](
        finalized.value.blockHash)
    let sameRoot = array[32, byte](cached.stateRoot) == array[32, byte](finalized.value.stateRoot)
    reuse = sameBlock and sameRoot
  if not reuse: services.ticketSource = captureTicketSource(finalized)
  services.ticketSource

proc currentTicketSource*(services: var Services): NetworkTicketResult[
    TicketSource] {.requires: services.stateProofAvailable.} =
  ## This ARC owner shares the job input lease; callers retire all aliases before admitting the next worker.
  if services.light.active: return ticketFailure[TicketSource](NetworkTicketError.NoSource)
  services.stageTicketSource()

proc stageNetworkTicket(services: var Services, packet: TicketPacket,
    recipient: TicketRecipient): NetworkTicketError =
  ## Only scalar status escapes staging; successful source/job aliases retire before thread submission.
  let source = services.stageTicketSource()
  if source.error != NetworkTicketError.None:
    services.ticketCaptureFailure = source
    return source.error
  let captured = captureTicketVerification(source.value, packet, recipient)
  if captured.error != NetworkTicketError.None:
    services.ticketCaptureFailure = ticketFailure[TicketSource](captured.error)
    return captured.error
  services.ticketInput = captured.value
  services.ticketCaptureFailure = default(NetworkTicketResult[TicketSource])
  NetworkTicketError.None

proc beginNetworkTicket*(services: var Services, packet: TicketPacket,
    recipient: TicketRecipient): NetworkTicketStart {.raises.} =
  ## Full-state source capture, RPC pause and CPU admission remain one exact bounded operation; light roots cannot substitute a complete source.
  if not services.started: return NetworkTicketStart(status: StateProofAdmissionError.Closed)
  if services.light.active: return NetworkTicketStart(status: StateProofAdmissionError.QueryFailure,
      captureReason: ticketFailure[TicketSource](NetworkTicketError.NoSource))
  if not services.stateProofAvailable: return NetworkTicketStart(
      status: StateProofAdmissionError.Busy)
  discard services.proofWorker.start()
  let captured = services.stageNetworkTicket(packet, recipient)
  if captured != NetworkTicketError.None:
    return NetworkTicketStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: move(services.ticketCaptureFailure))
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.ticketInput = default(TicketVerificationJob)
    return NetworkTicketStart(status: StateProofAdmissionError.Busy)
  let admitted = services.proofWorker.submit(services.ticketInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true # Done/cancellation still retain this exact lease until collection or joined close.
    return NetworkTicketStart(status: StateProofAdmissionError.None, ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.ticketInput = default(TicketVerificationJob)
  NetworkTicketStart(status: StateProofAdmissionError.WorkerFailure, workerReason: admitted.error)

func error*(outcome: TicketSignerConfiguration): TicketSignerError =
  ## Observe configuration without exposing seed, scalar or private signer ownership.
  outcome.status

func keyError*(outcome: TicketSignerConfiguration): bs.BsError {.requires: outcome.status ==
    TicketSignerError.KeyFailure.} =
  ## A failed configuration preserves only its genuine key derivation cause.
  outcome.keyReason

func hasTicketSigner*(services: Services): bool =
  ## Scalar-only availability is safe while the immutable signer is exclusively leased by CPU work.
  services.started and services.ticketSignerReady

func ticketSigningVersion*(services: Services): uint64 =
  ## A nonwrapping host configuration generation carries no key material.
  if services.started and services.ticketSignerReady: services.ticketSignerVersion else: 0'u64

proc configureTicketSignerSeed*(services: var Services, masterSeed: openArray[
    byte]): TicketSignerConfiguration =
  ## Explicit local configuration retains no caller seed bytes; Busy cannot replace a leased signing allocation.
  if not services.started: return TicketSignerConfiguration(status: TicketSignerError.Closed)
  if services.light.active: return TicketSignerConfiguration(status: TicketSignerError.WrongMode)
  if not services.stateProofAvailable: return TicketSignerConfiguration(
      status: TicketSignerError.Busy)
  if services.ticketSignerVersion == high(uint64): return TicketSignerConfiguration(
      status: TicketSignerError.Exhausted)
  let captured = captureTicketSigner(masterSeed)
  if captured.error == TicketSignerError.KeyFailure:
    return TicketSignerConfiguration(status: TicketSignerError.KeyFailure,
        keyReason: captured.keyError)
  if captured.error != TicketSignerError.None: return TicketSignerConfiguration(
      status: captured.error)
  let public = captured.value.signingPublic
  if services.ticketSignerReady and public == services.ticketSignerPublic:
    return TicketSignerConfiguration(status: TicketSignerError.None) # Reconfiguring the same key does not reopen completed epoch attempts or cancel valid queued work.
  services.ticketSigner = captured.value
  services.ticketSignerPublic = public
  inc services.ticketSignerVersion
  services.ticketSignerReady = true
  TicketSignerConfiguration(status: TicketSignerError.None)

proc stageTicketProduction(services: var Services, local: StateEdKey, now: StateTime,
    connectivityEpoch: uint32, attempt: TicketAttempt): NetworkTicketError =
  ## Successful source/signer staging aliases retire in this activation before native CPU submission.
  let source = services.stageTicketSource()
  if source.error != NetworkTicketError.None:
    services.ticketCaptureFailure = source
    return source.error
  let captured = captureTicketProduction(source.value, services.ticketSigner, local, now,
      connectivityEpoch, attempt)
  if captured.error != NetworkTicketError.None:
    services.ticketCaptureFailure = ticketFailure[TicketSource](captured.error)
    return captured.error
  services.productionInput = captured.value
  services.ticketCaptureFailure = default(NetworkTicketResult[TicketSource])
  NetworkTicketError.None

proc beginTicketProduction*(services: var Services, local: StateEdKey, now: StateTime,
    connectivityEpoch: uint32, attempt: TicketAttempt): NetworkTicketStart {.raises.} =
  ## Optional genuine signing uses the existing exact full-state RPC/worker lease and never runs inside Native callbacks.
  if not services.started: return NetworkTicketStart(status: StateProofAdmissionError.Closed)
  if services.light.active: return NetworkTicketStart(status: StateProofAdmissionError.QueryFailure,
      captureReason: ticketFailure[TicketSource](NetworkTicketError.NoSource))
  if not services.stateProofAvailable: return NetworkTicketStart(
      status: StateProofAdmissionError.Busy)
  if not services.ticketSignerReady: return NetworkTicketStart(
      status: StateProofAdmissionError.QueryFailure,

captureReason: ticketFailure[TicketSource](NetworkTicketError.NoSigner))
  discard services.proofWorker.start()
  let captured = services.stageTicketProduction(local, now, connectivityEpoch, attempt)
  if captured != NetworkTicketError.None:
    return NetworkTicketStart(status: StateProofAdmissionError.QueryFailure, captureReason: move(
        services.ticketCaptureFailure))
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.productionInput = default(TicketProductionJob)
    return NetworkTicketStart(status: StateProofAdmissionError.Busy)
  let admitted = services.proofWorker.submit(services.productionInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true
    return NetworkTicketStart(status: StateProofAdmissionError.None, ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.productionInput = default(TicketProductionJob)
  NetworkTicketStart(status: StateProofAdmissionError.WorkerFailure, workerReason: admitted.error)

func availabilityReadsMatch*(services: Services, limits: AvailabilityReadLimits): bool =
  ## A reopened signed host can observe the same fixed serving policy through foreign leases without rebinding any source.
  services.availabilityEnabled and uint64(services.availabilityLimits.wireBytes) == uint64(
      limits.wireBytes) and
    uint64(services.availabilityLimits.computation.bytes) == uint64(limits.computation.bytes) and
    uint64(services.availabilityLimits.computation.hashes) == uint64(limits.computation.hashes) and
    uint64(services.availabilityLimits.computation.hashBytes) == uint64(
        limits.computation.hashBytes)

proc configureAssuranceReads*(services: var Services, limits: AssuranceReadLimits): bool =
  ## Explicit durable audit serving requires an installed healthy full-state namespace, and opens no archive or key itself.
  if not services.started or services.light.active or not services.stateProofAvailable or
      services.assuranceReadsEnabled or not limits.valid: return false
  if not services.assuranceInfo.opened or services.assuranceInfo.faulted: return false
  services.assuranceReadLimits = limits
  services.assuranceReadsEnabled = true
  true

proc configureAvailabilityReads*(services: var Services, limits: AvailabilityReadLimits): bool =
  ## Explicit one-time policy activation never rebinds a live worker's source or resource contract.
  if not services.started or not services.stateProofAvailable or services.availabilityEnabled or
      not limits.valid:
    return false
  services.availabilityLimits = limits
  services.availabilityEnabled = true
  true

proc configureAvailabilityStorage*(services: var Services, limits: AvailabilityStoreLimits): bool =
  ## Optional explicit storage policy cannot rebind entries or mutate a worker-borrowed cache.
  if not services.started or services.light.active or not services.stateProofAvailable or
      not services.availabilityEnabled:
    return false
  services.availabilityStore.configure(limits)

proc rememberAvailability*(services: var Services,
    transfer: VerifiedAvailabilityTransfer): AvailabilityStoreError =
  ## Private detached storage is changed only while every canonical/availability CPU borrower has retired.
  if not services.started or not services.availabilityEnabled: return AvailabilityStoreError.Unconfigured
  if not services.stateProofAvailable: return AvailabilityStoreError.Busy
  services.availabilityStore.remember(transfer)

proc stageAvailabilityAudit(services: var Services, request: ReadRequest): ReadError =
  ## Durable lookup stays on the worker; legacy memory-cache sources are selected only while the host owns the idle lease.
  if services.assuranceReadsEnabled:
    # Durable selection performs no foreground filesystem IO; all lookup, proof and synchronization work stays in the closed job.
    let captured = captureAssuranceRead(services.assuranceStore, request,
        services.assuranceReadLimits)
    if captured.error == ReadError.None: services.networkReadInput = captured.value
    return captured.error
  if not services.availabilityEnabled: return ReadError.Unavailable
  let payload = request.payload
  var selected = AvailabilityRequest(kind: AvailabilityTransferKind.Audit,
    shard: ErasureShardIndex(uint64(payload[32]) or (uint64(payload[33]) shl 8)))
  for index in 0..<32: selected.root.bytes[index] = payload[index]
  let found = services.availabilityStore.find(selected)
  if found.error != AvailabilityStoreError.None: return ReadError.Unavailable
  let captured = captureAvailabilityAudit(found.value, request, services.availabilityLimits)
  if captured.error == ReadError.None: services.networkReadInput = captured.value
  captured.error

proc stageOriginalSegments(services: var Services, request: ReadRequest): ReadError =
  ## Retained report roots coexist with the current unsigned original; only worker-side bounded selection/hash work interprets the batch.
  if not services.availabilityEnabled: return ReadError.Unavailable
  var original = default(AvailabilityCommitment)
  if services.workPhase == WorkSessionPhase.ReportReady or signedWorkPhase(services.workPhase):
    var transcript = default(ComputedGuaranteeTranscript)
    case services.workOutcome.kind
    of WorkJobResultKind.Reported: transcript = services.workOutcome.reportTranscript
    of WorkJobResultKind.Contributed: transcript = services.workOutcome.signedContribution.contributionTranscript.value
    else: discard # A default/non-report session contributes no unsigned source authority.
    let report = transcript.computedGuaranteeReport
    if report.error == ComputedGuaranteeError.None: original = report.value.computedReportSource.value
  let captured = captureOriginalSegments(original, services.guarantorStore.snapshot,
    request, services.availabilityLimits)
  if captured.error == ReadError.None: services.networkReadInput = captured.value
  captured.error

proc stageAvailabilityRead(services: var Services, request: ReadRequest): ReadError =
  ## Exact retained roots survive completed sessions and later signatures; staging aliases retire before CPU submission.
  if not services.availabilityEnabled: return ReadError.Unavailable
  if request.valid and request.kind == ReadKind.Segments: return services.stageOriginalSegments(request)
  if request.availabilityRead:
    # Root lookup covers every non-evicted signed source before considering an unsigned/current best-effort source.
    var root = default(ErasureRoot)
    let payload = request.payload
    for index in 0..<32: root.bytes[index] = payload[index]
    let found = services.guarantorStore.find(root)
    if found.error == GuarantorStoreError.None:
      let captured = captureAvailabilityRead(found.value, request, services.availabilityLimits)
      if captured.error == ReadError.None: services.networkReadInput = captured.value
      return captured.error
  var reason = ReadError.Unavailable
  if services.workPhase == WorkSessionPhase.ReportReady or signedWorkPhase(services.workPhase):
    var transcript = default(ComputedGuaranteeTranscript)
    case services.workOutcome.kind
    of WorkJobResultKind.Reported:
      # Primary unsigned reports keep their original source until explicit retirement.
      transcript = services.workOutcome.reportTranscript
    of WorkJobResultKind.Contributed:
      # Local signing preserves the same original availability source.
      transcript = services.workOutcome.signedContribution.contributionTranscript.value
    else:
      discard # An inconsistent/default outcome cannot provide a source.
    let report = transcript.computedGuaranteeReport
    if report.error == ComputedGuaranteeError.None:
      let captured = captureAvailabilityRead(report.value.computedReportSource.value, request,
        services.availabilityLimits)
      if captured.error == ReadError.None:
        services.networkReadInput = captured.value
        return ReadError.None
      reason = captured.error
  let shared = services.sharedContribution.contributionInfo
  if shared.error == WorkSignerError.None:
    # Received sharing never overwrites the builder context; its separately retained bundle remains serveable.
    let report = services.sharedContribution.contributionTranscript.value.computedGuaranteeReport.value
    let captured = captureAvailabilityRead(report.computedReportSource.value, request,
        services.availabilityLimits)
    if captured.error == ReadError.None: services.networkReadInput = captured.value
    return captured.error
  reason

proc stageSegmentShardBatch(services: var Services, request: ReadRequest): ReadError =
  ## The complete bounded private cache snapshot is frozen before admission; no caller-owned transfer alias enters this job.
  if services.assuranceReadsEnabled and uint64(services.assuranceReadLimits.batchSources) > 0:
    # A separately selected durable batch policy captures no payload graphs or filesystem data on the foreground thread.
    let captured = captureAssuranceRead(services.assuranceStore, request,
        services.assuranceReadLimits)
    if captured.error == ReadError.None: services.networkReadInput = captured.value
    return captured.error
  if not services.availabilityEnabled or not services.availabilityStore.configured: return ReadError.Unavailable
  let captured = captureSegmentShardBatch(services.availabilityStore.snapshot, request,
      services.availabilityLimits)
  if captured.error == ReadError.None: services.networkReadInput = captured.value
  captured.error

proc stageNetworkRead(services: var Services, request: ReadRequest): ReadError =
  ## Every temporary canonical alias retires in this activation before native submission.
  if request.valid and request.kind in [ReadKind.SegmentShards,
      ReadKind.ProvenSegmentShards]: return services.stageSegmentShardBatch(request)
  if request.valid and request.kind == ReadKind.Segments: return services.stageAvailabilityRead(request)
  if request.valid and request.kind == ReadKind.Audit: return services.stageAvailabilityAudit(request)
  if request.availabilityRead: return services.stageAvailabilityRead(request)
  let captured = captureNetworkRead(services.canonical.chainView, request)
  if captured.error == ReadError.None: services.networkReadInput = captured.value
  captured.error

proc beginNetworkRead*(services: var Services, request: ReadRequest): NetworkReadStart {.raises.} =
  ## Admit one full-state network read through the existing single worker and exact RPC/canonical lease.
  if not services.started: return NetworkReadStart(status: StateProofAdmissionError.Closed)
  if services.light.active: return NetworkReadStart(status: StateProofAdmissionError.QueryFailure,
      readReason: ReadError.Unavailable)
  if not services.stateProofAvailable: return NetworkReadStart(
      status: StateProofAdmissionError.Busy)
  discard services.proofWorker.start() # Reuse one fixed-address worker for all read/RPC jobs.
  let reason = services.stageNetworkRead(request)
  if reason != ReadError.None: return NetworkReadStart(
      status: StateProofAdmissionError.QueryFailure, readReason: reason)
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.networkReadInput = default(NetworkReadJob)
    return NetworkReadStart(status: StateProofAdmissionError.Busy)
  let admitted = services.proofWorker.submit(services.networkReadInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true # Disconnect/cancel must not clear this flag before matching Done collection or join.
    let batch = request.kind in [ReadKind.SegmentShards, ReadKind.ProvenSegmentShards] and
      uint64(services.assuranceReadLimits.batchSources) > 0
    services.assuranceReadActive = services.assuranceReadsEnabled and (request.kind ==
        ReadKind.Audit or batch)
    return NetworkReadStart(status: StateProofAdmissionError.None, ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.networkReadInput = default(NetworkReadJob)
  NetworkReadStart(status: StateProofAdmissionError.WorkerFailure, workerReason: admitted.error)

proc beginStateProof*(services: var Services, selected: BlockHash, plan: StateProofPlan,
    limits: ProofQueryLimits): StateProofAdmission {.raises.} =
  ## Dispatch a bounded proof plan against the exact selected block.
  ## Full mode stages the retained complete source before borrowing it to the
  ## reusable worker. Light mode delegates to the independent partial proof actor.
  ## Retirement of the exact ticket governs when the source is available again.
  if services.light.active:
    let admitted = services.light.beginQuery(selected, plan, limits)
    case admitted.error
    of light_actor.LightRuntimeError.None:
      return StateProofAdmission(status: StateProofAdmissionError.None, ticket: admitted.value)
    of light_actor.LightRuntimeError.Closed:
      return StateProofAdmission(status: StateProofAdmissionError.Closed)
    of light_actor.LightRuntimeError.QueryFailure:
      return StateProofAdmission(status: StateProofAdmissionError.QueryFailure,
          queryReason: admitted.queryError)
    of light_actor.LightRuntimeError.WorkerFailure:
      return StateProofAdmission(status: StateProofAdmissionError.WorkerFailure,
          workerReason: admitted.workerError)
    else:
      return StateProofAdmission(status: StateProofAdmissionError.Busy) # No refused light admission grants a complete-map source.
  if not services.started: return StateProofAdmission(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable:
    return StateProofAdmission(status: StateProofAdmissionError.Busy)
  discard services.proofWorker.start() # Idle reuse never creates a worker per request.
  let reason = services.stageStateProof(selected, plan, limits)
  services.finishStateProof(reason) # No selected-state temporary survives the staging activation.

proc beginStateProof*(services: var Services, selected: BlockHash, plan: ServiceProofPlan,
    limits: ProofQueryLimits): StateProofAdmission {.raises.} =
  ## Existing service callers retain guarded admission and completion error alternatives.
  if services.light.active:
    let admitted = services.light.beginQuery(selected, plan, limits)
    case admitted.error
    of light_actor.LightRuntimeError.None:
      return StateProofAdmission(status: StateProofAdmissionError.None, ticket: admitted.value)
    of light_actor.LightRuntimeError.Closed:
      return StateProofAdmission(status: StateProofAdmissionError.Closed)
    of light_actor.LightRuntimeError.QueryFailure:
      return StateProofAdmission(status: StateProofAdmissionError.QueryFailure,
          queryReason: admitted.queryError)
    of light_actor.LightRuntimeError.WorkerFailure:
      return StateProofAdmission(status: StateProofAdmissionError.WorkerFailure,
          workerReason: admitted.workerError)
    else:
      return StateProofAdmission(status: StateProofAdmissionError.Busy) # No refused light admission grants a complete-map source.
  if not services.started: return StateProofAdmission(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable:
    return StateProofAdmission(status: StateProofAdmissionError.Busy)
  discard services.proofWorker.start() # Idle reuse never creates a worker per request.
  let reason = services.stageStateProof(selected, plan, limits)
  services.finishStateProof(reason) # No selected-state temporary survives the staging activation.

proc stageLogicalProof(services: var Services, source: CurrentLogicalState,
    plan: StateProofPlan, limits: LogicalProofLimits, failure: var LogicalProofResult): bool =
  ## Retire every temporary source/query alias before the caller can submit the staged owner.
  let captured = captureLogicalProofQuery(source, plan, limits)
  if captured.error != LogicalProofError.None:
    failure = captured # Only refused capture alternatives reach the caller's failure owner.
    return false
  services.proofInput = captured.value
  true

proc beginLogicalProof*(services: var Services, source: CurrentLogicalState,
    plan: StateProofPlan, limits: LogicalProofLimits): LogicalProofAdmission {.raises.} =
  ## Explicit retained producer provenance selects this proof; canonical installation and root trust remain separate.
  if not services.started:
    return LogicalProofAdmission(status: LogicalProofAdmissionError.Closed)
  if not services.stateProofAvailable:
    return LogicalProofAdmission(status: LogicalProofAdmissionError.Busy) # Check scalar exclusions before touching any source alias.
  discard services.proofWorker.start() # Reuse the one fixed-address managed worker and its existing exclusive lease.
  var failure = default(LogicalProofResult)
  if not services.stageLogicalProof(source, plan, limits, failure):
    return LogicalProofAdmission(status: LogicalProofAdmissionError.CaptureFailure,
      captureReason: failure)
  let admitted = services.finishStateProof(ProofQueryError.None) # Staging activation has retired; successful submission permits only scalar/ticket work.
  if admitted.error != StateProofAdmissionError.None:
    return LogicalProofAdmission(status: LogicalProofAdmissionError.AdmissionFailure,
      admissionReason: admitted)
  LogicalProofAdmission(status: LogicalProofAdmissionError.None, ticket: admitted.value)

proc stateProofPhase*(services: var Services): ProofWorkerPhase =
  ## Synchronized scalar polling never observes or copies selected-state ARC owners.
  if services.light.active: services.light.proofPhase() else: services.proofWorker.phase

proc stateProofActive*(services: var Services, ticket: ProofWorkerTicket): bool =
  ## Closed full-state managed jobs retain an exact generation through Done; foreign tickets and joined shutdown cannot revive it.
  services.proofing and not services.light.active and services.proofWorker.active(ticket)

proc cancelStateProof*(services: var Services, ticket: ProofWorkerTicket): bool =
  ## Cancellation requests discard without releasing graph access or bounded capacity.
  if services.light.active: services.light.cancelQuery(ticket) else: services.proofWorker.cancel(ticket)

proc auditSource(services: Services, hash: genesis.BlockHash): ChainView =
  ## Prefer independently installed selected history, otherwise use the exact registered branch.
  let selected = services.canonical.chainView
  if selected.blockAt(hash).error == GenesisError.None: return selected
  let branch = services.auditBranches.parentView(selected, hash)
  if branch.bestBlock.error == GenesisError.None: branch else: selected

proc collectSharedStateProof(services: var Services,
    ticket: ProofWorkerTicket): ProofWorkerCompletion =
  ## Only matching Done collection retires the query and reopens canonical/RPC access together.
  if services.light.active: return services.light.collectQuery(
      ticket) # Only actual matching Done collection ends its own request lease.
  result = services.proofWorker.collect(ticket)
  if result.kind != ProofWorkerCompletionKind.Uninitialized:
    services.assuranceWorkInput = default(
        WorkSubmissionJob) # Matching collection retires the canonical receipt borrow before RPC resumes.
    if services.assuranceSigningActive:
      # Only this Services lifetime's actual uncancelled completed signature becomes publishable; cancellation still refreshes real retained promises/faults.
      services.refreshAssuranceStorage()
      services.lastAssurance = default(SignedAssurance)
      if result.kind == ProofWorkerCompletionKind.AssuranceSigned:
        let signed = result.assuranceSigningValue
        if signed.error == AssuranceSigningError.None: services.lastAssurance = signed.value
      services.assuranceSigningInput = default(AssuranceSigningJob)
      services.assuranceSigningActive = false
    if services.assuranceAcquisitionActive:
      # Cancellation may hide a completed durable write; refresh actual counters/fault status without claiming a possession bit.
      services.refreshAssuranceStorage()
      services.assuranceAcquisitionInput = default(AssuranceAcquisitionJob)
      services.assuranceAcquisitionActive = false
    if services.assuranceReadActive:
      # Exact collection ends the namespace borrow before observing real restore faults, including cancelled Done reads.
      services.refreshAssuranceStorage()
      services.assuranceReadActive = false
    if services.assuranceStorageActive:
      # Exact collection ends mutation before touching any native-owner fields; a cancelled Done result still needs explicit close.
      if result.kind == ProofWorkerCompletionKind.AssuranceCompleted and
          result.assuranceStorageValue.error == AssuranceStoreError.None:
        services.refreshAssuranceStorage()
      else:
        discard services.assuranceStore.close()
        services.assuranceInfo = default(AssuranceStorageInfo)
      services.assuranceStorageInput = default(AssuranceStorageJob)
      services.assuranceStorageActive = false
    if services.audits.active:
      services.audits.finish(result, services.canonical.chainView,
          services.auditBranches) # Private capability retention precedes reopening RPC.
    services.proofing = false
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # A stale/foreign/early ticket never resumes another lease.
    if services.stateProofAvailable: services.audits.drainAbandonedDeclarations()

proc collectStateProof*(services: var Services, ticket: ProofWorkerTicket): ProofWorkerCompletion =
  ## Managed audit capabilities stay private even if a caller knows their host control ticket.
  if services.audits.active: return default(ProofWorkerCompletion)
  services.collectSharedStateProof(ticket)

proc collectAudit*(services: var Services, ticket: ProofWorkerTicket): ManagedAuditCompletion =
  ## Foreign controls cannot collect an unrelated worker or expose any full-state success alias.
  if not services.audits.matches(ticket): return default(ManagedAuditCompletion)
  if services.audits.active:
    discard services.collectSharedStateProof(ticket)
  result = services.audits.collect(ticket)
  if services.stateProofAvailable: services.audits.drainAbandonedDeclarations()

func error*(outcome: AssuranceStorageStart): AssuranceStorageStartError =
  ## Read the selected startup refusal before accessing its ticket or child reason.
  outcome.status

func value*(outcome: AssuranceStorageStart): ProofWorkerTicket {.requires: outcome.status ==
    AssuranceStorageStartError.None.} =
  ## Only successful native admission grants collection or cancellation authority.
  outcome.ticket

func identityError*(outcome: AssuranceStorageStart): NetworkIdentityError {.requires: outcome.status ==
    AssuranceStorageStartError.IdentityFailure.} =
  ## Preserve actual configured-genesis identity refusal; a best head or caller-selected chain cannot replace the original network.
  outcome.identityReason

func captureError*(outcome: AssuranceStorageStart): AssuranceStorageJobError {.requires: outcome.status ==
    AssuranceStorageStartError.CaptureFailure.} =
  ## Preserve bounded path/policy capture failure without opening a namespace.
  outcome.captureReason

func workerError*(outcome: AssuranceStorageStart): ProofWorkerError {.requires: outcome.status ==
    AssuranceStorageStartError.WorkerFailure.} =
  ## Worker refusal leaves no live namespace job or canonical/RPC exclusion.
  outcome.workerReason

func assuranceStorageInfo*(services: Services): AssuranceStorageInfo =
  ## Poll only host-owned cached accounting; the actual namespace can be mutating on the native thread.
  services.assuranceInfo

proc stageAssuranceStorage(services: var Services, folder: string, chain: AssuranceChainId,
    limits: AssuranceStoreLimits, mode: AssuranceStorageMode): AssuranceStorageJobError =
  ## Retire the capture wrapper and its private path aliases before a native thread can execute the staged job.
  let captured = captureAssuranceStorage(services.assuranceStore, folder, chain, limits, mode)
  if captured.error == AssuranceStorageJobError.None:
    services.assuranceStorageInput = captured.value
    services.assuranceStorageChain = chain
  captured.error

proc beginAssuranceStorage*(services: var Services, folder: string,
    limits: AssuranceStoreLimits, mode: AssuranceStorageMode): AssuranceStorageStart {.raises.} =
  ## Explicit full-state startup uses the same single CPU/I/O capacity and exact RPC lease; no foreground callback scans files.
  if not services.started: return AssuranceStorageStart(status: AssuranceStorageStartError.Closed)
  if services.light.active: return AssuranceStorageStart(
      status: AssuranceStorageStartError.Unavailable)
  if not services.stateProofAvailable or services.assuranceInfo.opened:
    return AssuranceStorageStart(status: AssuranceStorageStartError.Busy)
  discard services.proofWorker.start()
  let identity = readNetworkIdentity(services.chainText)
  if identity.error != NetworkIdentityError.None:
    return AssuranceStorageStart(status: AssuranceStorageStartError.IdentityFailure,
        identityReason: identity.error)
  let chain = AssuranceChainId(array[32, byte](identity.value.genesisHash))
  let captured = services.stageAssuranceStorage(folder, chain, limits, mode)
  if captured != AssuranceStorageJobError.None:
    return AssuranceStorageStart(status: AssuranceStorageStartError.CaptureFailure,
        captureReason: captured)
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.assuranceStorageInput = default(AssuranceStorageJob)
    return AssuranceStorageStart(status: AssuranceStorageStartError.Busy)
  let admitted = services.proofWorker.submit(services.assuranceStorageInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true
    services.assuranceStorageActive = true
    return AssuranceStorageStart(status: AssuranceStorageStartError.None, ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.assuranceStorageInput = default(AssuranceStorageJob)
  AssuranceStorageStart(status: AssuranceStorageStartError.WorkerFailure,
      workerReason: admitted.error)

func error*(outcome: AssuranceAcquisitionStart): AssuranceStorageStartError =
  ## Read startup/lease refusal before extracting its guarded ticket or child reason.
  outcome.status

func value*(outcome: AssuranceAcquisitionStart): ProofWorkerTicket {.requires: outcome.status ==
    AssuranceStorageStartError.None.} =
  ## Exact admitted acquisition alone can be collected or cancelled.
  outcome.ticket

func captureError*(outcome: AssuranceAcquisitionStart): AssuranceAcquisitionError {.requires: outcome.status ==
    AssuranceStorageStartError.CaptureFailure.} =
  ## Keep the actual bounded input/source/namespace capture refusal.
  outcome.captureReason

func workerError*(outcome: AssuranceAcquisitionStart): ProofWorkerError {.requires: outcome.status ==
    AssuranceStorageStartError.WorkerFailure.} =
  ## A failed native submission retains no canonical/RPC exclusion or source owner.
  outcome.workerReason

proc stageAssuranceAcquisition(services: var Services, local: StateEdKey, core: CoreIndex,
    ordinal: int, wire: openArray[byte], now: AssuranceTime,
    limits: AssuranceAcquisitionLimits, existingOnly: bool): AssuranceAcquisitionError =
  ## All temporary best-head/capture aliases retire before submission; the peer supplies no canonical source, descriptor or shard coordinate.
  let captured = if existingOnly:
    captureAssuranceProbe(services.assuranceStore, services.canonical.chainView.bestBlock,
      services.assuranceInfo.chain, local, core, ordinal, now, limits)
  else:
    captureAssuranceAcquisition(services.assuranceStore, services.canonical.chainView.bestBlock,
      services.assuranceInfo.chain, local, core, ordinal, wire, now, limits)
  if captured.error == AssuranceAcquisitionError.None:
    services.assuranceAcquisitionInput = captured.value
  captured.error

proc beginAcquisition(services: var Services, local: StateEdKey, core: CoreIndex,
    ordinal: int, wire: openArray[byte], now: AssuranceTime,
    limits: AssuranceAcquisitionLimits, existingOnly: bool): AssuranceAcquisitionStart {.raises.} =
  ## Optional full-state acquisition binds current canonical assignments and the installed chain namespace under one reusable worker/RPC lease.
  if not services.started: return AssuranceAcquisitionStart(
      status: AssuranceStorageStartError.Closed)
  if services.light.active or not services.assuranceInfo.opened or services.assuranceInfo.faulted:
    return AssuranceAcquisitionStart(status: AssuranceStorageStartError.Unavailable)
  if not services.stateProofAvailable: return AssuranceAcquisitionStart(
      status: AssuranceStorageStartError.Busy)
  discard services.proofWorker.start()
  let reason = services.stageAssuranceAcquisition(local, core, ordinal, wire, now, limits, existingOnly)
  if reason != AssuranceAcquisitionError.None:
    return AssuranceAcquisitionStart(status: AssuranceStorageStartError.CaptureFailure,
        captureReason: reason)
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.assuranceAcquisitionInput = default(AssuranceAcquisitionJob)
    return AssuranceAcquisitionStart(status: AssuranceStorageStartError.Busy)
  let admitted = services.proofWorker.submit(services.assuranceAcquisitionInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true
    services.assuranceAcquisitionActive = true
    return AssuranceAcquisitionStart(status: AssuranceStorageStartError.None,
        ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.assuranceAcquisitionInput = default(AssuranceAcquisitionJob)
  AssuranceAcquisitionStart(status: AssuranceStorageStartError.WorkerFailure,
      workerReason: admitted.error)

proc beginAssuranceAcquisition*(services: var Services, local: StateEdKey, core: CoreIndex,
    ordinal: int, wire: openArray[byte], now: AssuranceTime,
    limits: AssuranceAcquisitionLimits): AssuranceAcquisitionStart {.raises.} =
  ## Detached actual CE137 bytes enter only fresh canonical verification and real durable publication under the shared lease.
  services.beginAcquisition(local, core, ordinal, wire, now, limits, false)

proc beginAssuranceProbe*(services: var Services, local: StateEdKey, core: CoreIndex,
    ordinal: int, now: AssuranceTime, limits: AssuranceAcquisitionLimits): AssuranceAcquisitionStart {.raises.} =
  ## Full stored verification and actual restore synchronization return fixed observations only; absence never claims possession or opens a namespace implicitly.
  services.beginAcquisition(local, core, ordinal, [], now, limits, true)

func error*(outcome: AssuranceWorkStart): StateProofAdmissionError =
  ## Read admission before selecting an exact ticket or real capture/native failure.
  outcome.status

func value*(outcome: AssuranceWorkStart): ProofWorkerTicket {.requires: outcome.status ==
    StateProofAdmissionError.None.} =
  ## Foreign/stale tickets cannot collect or cancel this receipt's lease.
  outcome.ticket

func captureError*(outcome: AssuranceWorkStart): WorkJobError {.requires: outcome.status ==
    StateProofAdmissionError.QueryFailure.} =
  ## Failed closed capture never retains a canonical alias.
  outcome.captureReason

func workerError*(outcome: AssuranceWorkStart): ProofWorkerError {.requires: outcome.status ==
    StateProofAdmissionError.WorkerFailure.} =
  ## Native slot refusal remains distinct from raw request admission.
  outcome.workerReason

func error*(outcome: AuditPlanningStart): StateProofAdmissionError =
  ## Read the selected admission branch before accessing a ticket or actual child failure.
  outcome.status

func value*(outcome: AuditPlanningStart): ProofWorkerTicket {.requires: outcome.status ==
    StateProofAdmissionError.None.} =
  ## Only exact admitted audit planning grants collection/cancellation authority.
  outcome.ticket

func captureError*(outcome: AuditPlanningStart): WorkJobError {.requires: outcome.status ==
    StateProofAdmissionError.QueryFailure.} =
  ## Failed closed capture cannot retain canonical source authority.
  outcome.captureReason

func workerError*(outcome: AuditPlanningStart): ProofWorkerError {.requires: outcome.status ==
    StateProofAdmissionError.WorkerFailure.} =
  ## Preserve real bounded native admission refusal independently of source capture.
  outcome.workerReason

proc stageAssuranceDistribution(services: var Services, request: ReadRequest,
    peer: StateEdKey, limits: AssuranceDistributionLimits): WorkJobError =
  ## Source and capture wrapper aliases retire before shared-worker publication.
  let captured = captureAssuranceDistribution(request, services.canonical.chainView.bestBlock, peer, limits)
  if captured.error != WorkJobError.None: return captured.error
  services.assuranceWorkInput = captured.value
  WorkJobError.None

proc admitAssuranceWork(services: var Services): AssuranceWorkStart {.raises.} =
  ## Staging activations have retired every temporary alias before this exact canonical/RPC admission publishes the private job.
  discard services.proofWorker.start()
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.assuranceWorkInput = default(WorkSubmissionJob)
    return AssuranceWorkStart(status: StateProofAdmissionError.Busy)
  let admitted = services.proofWorker.submit(services.assuranceWorkInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true
    return AssuranceWorkStart(status: StateProofAdmissionError.None, ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.assuranceWorkInput = default(WorkSubmissionJob)
  AssuranceWorkStart(status: StateProofAdmissionError.WorkerFailure,
      workerReason: admitted.error)

proc releaseDisputedAudit*(services: var Services, id: AuditOriginId): bool =
  ## Reclaim a retired exact disputed map only while the complete graph is idle.
  services.stateProofAvailable and services.audits.releaseDispute(id)

proc releaseInitialAudit*(services: var Services, id: AuditOriginId): bool =
  ## Release one completed declaration pin between graph leases.
  if not services.stateProofAvailable: return false
  services.audits.drainAbandonedDeclarations()
  services.audits.releaseDeclaration(id)

proc retireInitialAudit*(services: var Services, id: AuditOriginId) =
  ## A closing node hands off exactly its pin even when another controller owns the graph lease.
  if not id.valid: return
  services.audits.abandonDeclaration(id)
  if services.stateProofAvailable: services.audits.drainAbandonedDeclarations()

proc expireFinalizedAudits*(services: var Services, previous: uint64): uint64 =
  ## Verdicts may still use the prior-state epoch or one earlier. Only installed finality advances this floor.
  if not services.stateProofAvailable or services.audits.occupied: return previous
  services.audits.drainAbandonedDeclarations()
  let finalized = services.canonical.chainView.finalizedBlock
  if finalized.error != GenesisError.None: return previous
  let slots = finalized.value.chainParameters.get(epochPeriod)
  if slots == 0: return previous
  let epoch = finalized.value.slot div slots
  if epoch <= 1 or epoch-1 <= previous: return previous
  let floor = epoch-1
  if services.audits.expireBefore(floor): floor else: previous

func auditRetentionConfigured*(services: Services): bool =
  ## Host-only optional activation observation follows no full-state or worker-leased aliases.
  services.audits.configured

proc configureAudits*(services: var Services, limits: AuditRegistryLimits): bool =
  ## Optional full-state retention requires explicit finite limits and an idle canonical graph.
  if not services.stateProofAvailable: return false
  services.audits.configure(limits)

proc configureAuditBranches*(services: var Services, limits: AuditBranchLimits): bool =
  ## Explicit storage policy reserves bounded full-state side-branch ownership.
  if not services.stateProofAvailable: return false
  services.auditBranches.configure(limits)

proc auditBranchParent*(services: Services, parent: genesis.BlockHash): ApplicationChainResult[
    ApplicationChain] =
  ## Full candidate preparation borrows only an independently retained exact parent view.
  if not services.stateProofAvailable: return initApplicationChain(default(ChainView))
  initApplicationChain(services.auditBranches.parentView(services.canonical.chainView, parent))

proc beginAuditBranchInput*(services: Services, input: var CurrentBlockInput,
    parent: genesis.BlockHash, extent: ByteLimit, ancestors: openArray[OwnedHeader],
    resources: CurrentBlockInputLimits, policies: CurrentCandidateLimits): CurrentBlockInputAdmission =
  ## Bound the received bytes to an independently retained exact parent and ordinary full-block policy.
  let branch = services.auditBranchParent(parent)
  if branch.error != ApplicationChainError.None:
    return default(CurrentBlockInputAdmission)
  input.begin(branch.value, extent, ancestors, resources, policies)

proc retainAuditBranch*(services: var Services, prepared: PreparedCurrentChainUpdate): AuditBranchError =
  ## A validated side child never installs selected state or changes RPC/finality.
  if not services.stateProofAvailable or services.audits.occupied: return AuditBranchError.Uninitialized
  services.auditBranches.retain(services.canonical.chainView, prepared)

proc knownAuditBlock*(services: Services, hash: genesis.BlockHash): bool =
  ## A leaf already present on either independently retained history needs no network request.
  if not services.stateProofAvailable: return false
  services.canonical.chainView.blockAt(hash).error == GenesisError.None or
    services.auditBranches.at(hash).bestBlock.error == GenesisError.None

func auditBranchCount*(services: Services): int =
  ## Stable side-branch ordinal space is separate from selected slot order.
  services.auditBranches.len

func nextAuditBranch*(services: Services, after: uint64): AuditBranchCandidate =
  ## Return a detached scheduling identity that is independent of row compaction.
  services.auditBranches.nextAfter(after)

proc retainAuditOrigin*(services: var Services, origin: AuditBlockOrigin): AuditRegistryResult[
    AuditOriginId] =
  ## Backfill an already authenticated whole origin only against independently retained canonical/checkpoint trust.
  if not services.stateProofAvailable or services.audits.occupied or not origin.valid:
    return auditRegistryFailure[AuditOriginId](AuditRegistryError.InvalidSource)
  services.audits.drainAbandonedDeclarations()
  services.audits.retain(origin, services.auditSource(origin.originInfo.value.blockHash).blockAt(
      origin.originInfo.value.blockHash))

proc admitManagedAudit(services: var Services): AuditPlanningStart {.raises.} =
  ## Reuse exactly the ordinary fixed worker and canonical/RPC lease without translating unrelated failure alternatives.
  let admitted = services.admitAssuranceWork()
  case admitted.error
  of StateProofAdmissionError.None: AuditPlanningStart(status: StateProofAdmissionError.None,
      ticket: admitted.value)
  of StateProofAdmissionError.WorkerFailure: AuditPlanningStart(
      status: StateProofAdmissionError.WorkerFailure, workerReason: admitted.workerError)
  of StateProofAdmissionError.QueryFailure: AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: admitted.captureError)
  of StateProofAdmissionError.Busy: AuditPlanningStart(status: StateProofAdmissionError.Busy)
  of StateProofAdmissionError.Closed: AuditPlanningStart(status: StateProofAdmissionError.Closed)
  of StateProofAdmissionError.Uninitialized: AuditPlanningStart(
      status: StateProofAdmissionError.Uninitialized)

proc stageInitialAudit(services: var Services, blockHash: genesis.BlockHash, identity: StateEdKey,
    ordinal: JudgeIndex, context: AuditContextLimits, proof: AuditProofLimits,
        discover: bool): WorkJobError =
  ## Retire source and private signer staging aliases before publishing the exact worker lease.
  let captured = captureInitialAuditJob(services.auditSource(blockHash), blockHash, context, proof,
      services.ticketSigner, identity, ordinal, discover)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginInitialAudit*(services: var Services, blockHash: genesis.BlockHash, identity: StateEdKey,
    ordinal: JudgeIndex, context: AuditContextLimits,
        proof: AuditProofLimits, discover = false): AuditPlanningStart {.raises.} =
  ## Optional local signing uses the shared state worker and returns detached CE144 output.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable or services.audits.occupied: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if services.light.active or not services.ticketSignerReady:
    return AuditPlanningStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  let staged = services.stageInitialAudit(blockHash, identity, ordinal, context, proof, discover)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.admitManagedAudit()

proc stageManagedAuditOrigin(services: var Services, blockHash: genesis.BlockHash,
    context: AuditContextLimits, limits: AuditOriginLimits): WorkJobError =
  ## Temporary view wrappers retire before native admission publishes its source borrow.
  let captured = captureAuditOriginJob(services.auditSource(blockHash), blockHash, context, limits)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditOriginCapture*(services: var Services, blockHash: genesis.BlockHash,
    context: AuditContextLimits, limits: AuditOriginLimits,
        forDeclaration = false): AuditPlanningStart {.raises.} =
  ## Only actual canonical history can feed managed full-origin capture, with one unconsumed completion at most.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable or services.audits.occupied: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if not services.audits.configured: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  services.audits.drainAbandonedDeclarations()
  let staged = services.stageManagedAuditOrigin(blockHash, context, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitOrigin(result.value, forDeclaration)

proc auditSelectorAvailable(services: var Services): bool =
  ## Check the shared lease before draining; no admission can borrow a queued abandoned selector.
  if not services.stateProofAvailable or services.audits.occupied: return false
  services.audits.drainAbandonedDeclarations()
  true

proc stageManagedAuditEvaluation(services: var Services, id: AuditOriginId, ordinal: int,
    wire: openArray[byte], limits: AuditEvaluationLimits): WorkJobError =
  ## Only the privately registered original target enters the fixed evaluator; caller wire is copied within finite policy.
  let captured = services.audits.stageEvaluation(id, ordinal, wire, limits)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditEvaluation*(services: var Services, id: AuditOriginId, ordinal: int,
    wire: openArray[byte], limits: AuditEvaluationLimits): AuditPlanningStart {.raises.} =
  ## A source-free selector grants no signing authority and cannot replace the registered complete predecessor.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.auditSelectorAvailable: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if not services.audits.configured: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let staged = services.stageManagedAuditEvaluation(id, ordinal, wire, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitEvaluation(result.value,
      id, ordinal)

proc stageManagedAuditShard(services: var Services, plan: AuditFetchPlan, ordinal: int,
    wire: openArray[byte], limits: AvailabilityMerkleLimits): WorkJobError =
  ## Retire bounded capture temporaries before native submission; this job borrows only immutable detached routing.
  let captured = captureAuditShardVerificationJob(plan, ordinal, wire, limits)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditShardVerification*(services: var Services, plan: AuditFetchPlan, ordinal: int,
    wire: openArray[byte], limits: AvailabilityMerkleLimits): AuditPlanningStart {.raises.} =
  ## Whole transcript proof checks run outside native callbacks through the exact managed worker lease.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable or services.audits.occupied:
    return AuditPlanningStart(status: StateProofAdmissionError.Busy)
  if not services.audits.configured:
    return AuditPlanningStart(status: StateProofAdmissionError.QueryFailure,
      captureReason: WorkJobError.InvalidInput)
  let staged = services.stageManagedAuditShard(plan, ordinal, wire, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitShard(result.value)

proc stageManagedAuditFetch(services: var Services, id: AuditOriginId, ordinal: int,
    limits: AuditFetchLimits): WorkJobError =
  ## Temporary private lookup wrappers retire before source ownership crosses to the fixed worker.
  let captured = services.audits.stageFetch(id, ordinal, limits)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditFetchPlanning*(services: var Services, id: AuditOriginId, ordinal: int,
    limits: AuditFetchLimits): AuditPlanningStart {.raises.} =
  ## Optional retrieval planning exposes only deep detached routes, never a private registry source.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.auditSelectorAvailable:
    return AuditPlanningStart(status: StateProofAdmissionError.Busy)
  if not services.audits.configured:
    return AuditPlanningStart(status: StateProofAdmissionError.QueryFailure,
      captureReason: WorkJobError.InvalidInput)
  let staged = services.stageManagedAuditFetch(id, ordinal, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None:
    services.audits.admitFetch(result.value, id, ordinal)

proc stageManagedAuditRecovery(services: var Services, id: AuditOriginId, ordinal: int,
    packets: openArray[VerifiedAvailabilityTransfer], recovery: AuditRecoveryLimits,
    evaluation: AuditEvaluationLimits): WorkJobError =
  ## Retire private source selection wrappers before native publication.
  let captured = services.audits.stageRecoveryEvaluation(id, ordinal, packets, recovery, evaluation)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditRecoveryEvaluation*(services: var Services, id: AuditOriginId, ordinal: int,
    packets: openArray[VerifiedAvailabilityTransfer], recovery: AuditRecoveryLimits,
    evaluation: AuditEvaluationLimits): AuditPlanningStart {.raises.} =
  ## Whole authenticated threshold recovery and genuine original evaluation share the ordinary exact canonical/RPC worker lease.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.auditSelectorAvailable: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if not services.audits.configured: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let staged = services.stageManagedAuditRecovery(id, ordinal, packets, recovery, evaluation)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitEvaluation(result.value,
      id, ordinal)

proc configureAuditSigner*(services: var Services, certificate, privateKey: string,
    transportIdentity: StateEdKey): WorkSigningSetupResult =
  ## Explicit full-state setup imports one private signer, independently from builder/assurer activation, and matches the real bound TLS identity.
  if not services.started: return WorkSigningSetupResult(status: WorkSigningSetupError.Closed)
  if not services.stateProofAvailable or services.auditSignerReady: return WorkSigningSetupResult(
      status: WorkSigningSetupError.Busy)
  if not services.audits.configured: return WorkSigningSetupResult(
      status: WorkSigningSetupError.InvalidStorage)
  let loaded = loadWorkSigner(certificate, privateKey)
  if loaded.error != WorkSignerError.None: return WorkSigningSetupResult(
      status: WorkSigningSetupError.SignerFailure, reason: loaded)
  let identity = loaded.value.signerIdentity.value
  if array[32, byte](identity) != array[32, byte](transportIdentity): return WorkSigningSetupResult(
      status: WorkSigningSetupError.InvalidIdentity)
  services.auditSigner = loaded.value
  services.auditSignerIdentity = identity
  services.auditSignerReady = true
  WorkSigningSetupResult(status: WorkSigningSetupError.None)

func auditSigningConfigured*(services: Services): bool =
  ## Cached scalar observation never touches the private key while a native lease runs.
  services.started and services.auditSignerReady

proc stageManagedAuditSigning(services: var Services, id: AuditOriginId, ordinal: int,
    validator: StateValidatorIndex): WorkJobError =
  ## Only the private completed registry slot and configured immutable key enter the fixed signing runner.
  let captured = services.audits.stageSigning(id, ordinal, services.auditSigner, validator)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditSigning*(services: var Services, id: AuditOriginId, ordinal: int,
    validator: StateValidatorIndex): AuditPlanningStart {.raises.} =
  ## A caller selects an original target/ordinal, never a purported validity bit, message or external evaluation capability.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.auditSelectorAvailable: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if not services.auditSignerReady: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let staged = services.stageManagedAuditSigning(id, ordinal, validator)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitSigning(result.value, id, ordinal)

proc stageAuditPlanning(services: var Services, blockHash: genesis.BlockHash,
    limits: AuditContextLimits): WorkJobError =
  ## Retire all temporary actual-view aliases before native submission can use the captured full history.
  let captured = captureAuditPlanning(services.canonical.chainView, blockHash, limits)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditPlanning*(services: var Services, blockHash: genesis.BlockHash,
    limits: AuditContextLimits): AuditPlanningStart {.raises.} =
  ## Only actual full-state Services history can feed this fixed audit context runner; a foreign lease is left untouched.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if services.light.active: return AuditPlanningStart(status: StateProofAdmissionError.QueryFailure,
      captureReason: WorkJobError.InvalidInput)
  let staged = services.stageAuditPlanning(blockHash, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  let admitted = services.admitAssuranceWork()
  case admitted.error
  of StateProofAdmissionError.None: AuditPlanningStart(status: StateProofAdmissionError.None,
      ticket: admitted.value)
  of StateProofAdmissionError.WorkerFailure: AuditPlanningStart(
      status: StateProofAdmissionError.WorkerFailure, workerReason: admitted.workerError)
  of StateProofAdmissionError.Busy: AuditPlanningStart(status: StateProofAdmissionError.Busy)
  of StateProofAdmissionError.QueryFailure: AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: admitted.captureError)
  of StateProofAdmissionError.Closed: AuditPlanningStart(status: StateProofAdmissionError.Closed)
  of StateProofAdmissionError.Uninitialized: AuditPlanningStart(
      status: StateProofAdmissionError.Uninitialized) # Every selected refusal preserves its actual branch; no future child may silently default.

proc stageAuditPublication(services: var Services, id: AuditOriginId, ordinal: int,
    validator: StateValidatorIndex, limits: AuditPublicationLimits): WorkJobError =
  ## Input capture selects only an already completed private registry slot and the explicitly installed signer.
  let captured = services.audits.stagePublication(id, ordinal, services.auditSigner, validator, limits)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditPublication*(services: var Services, id: AuditOriginId, ordinal: int,
    validator: StateValidatorIndex, limits: AuditPublicationLimits): AuditPlanningStart {.raises.} =
  ## No raw report-validity flag or external computation result can authorize a public judgment or its serving bytes.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.auditSelectorAvailable: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if not services.auditSignerReady: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let staged = services.stageAuditPublication(id, ordinal, validator, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitSigning(result.value, id, ordinal)

proc auditRoutingHead*(services: Services): genesis.BlockHash {.requires:
    services.stateProofAvailable.} =
  ## Observe only the trusted selected head that supplies current successor topology.
  services.canonical.chainView.bestBlockContext.hash

proc stageAuditParticipation(services: var Services, id: AuditOriginId, ordinal: int,
    identity: StateEdKey, limits: AuditParticipationLimits): WorkJobError =
  ## Temporary actual canonical wrappers retire before native publication of the immutable private source lease.
  let captured = services.audits.stageParticipation(id, ordinal,
      services.canonical.chainView.bestBlock, identity, limits)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditParticipation*(services: var Services, id: AuditOriginId, ordinal: int,
    identity: StateEdKey, limits: AuditParticipationLimits): AuditPlanningStart {.raises.} =
  ## Explicit full-node planning preserves every original local ordinal and only actually known successor topology.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.auditSelectorAvailable: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  let staged = services.stageAuditParticipation(id, ordinal, identity, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitParticipation(result.value)

proc stageAuditRoutingRefresh(services: var Services, basis: AuditRoutingBasis,
    limits: AuditParticipationLimits): WorkJobError =
  ## All selected-state wrappers retire before native submission.
  let captured = captureAuditRoutingRefresh(basis, services.canonical.chainView.bestBlock, limits)
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditRoutingRefresh*(services: var Services, basis: AuditRoutingBasis,
    limits: AuditParticipationLimits): AuditPlanningStart {.raises.} =
  ## Refresh uses the exact ordinary participation collector without retaining an execution origin.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable or services.audits.occupied: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  let staged = services.stageAuditRoutingRefresh(basis, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitParticipation(result.value)

func auditSigningMatches*(services: Services, identity: StateEdKey): bool =
  ## Cached fixed public identity checks never touch the private key while another worker borrows it.
  services.auditSigningConfigured and array[32, byte](services.auditSignerIdentity) == array[32,
      byte](identity)

proc judgmentSource*(services: Services, claim: SignedJudgmentClaim,
    excluded: openArray[JudgmentSourceAttempt] = [], maximumSlot = high(uint64),
    allowPrimary = true, allowAlternates = true): JudgmentSourceResult =
  ## Metadata-only selection observes actual canonical history solely while the shared graph gate is idle; Busy/default contains no guessed source.
  if not services.stateProofAvailable: return default(JudgmentSourceResult)
  let selected = services.canonical.chainView
  let alternatives = services.auditBranches.liveViews(selected)
  let source = judgmentAuthorityView(selected, alternatives, claim)
  if source.bestBlock.error != GenesisError.None: return default(JudgmentSourceResult)
  var histories = @[selected]
  for branch in alternatives: histories.add(branch)
  selectJudgmentSourceAcross(source, histories, claim, excluded, maximumSlot, allowPrimary, allowAlternates)

proc stageJudgmentReceipt(services: var Services, claims: SignedJudgmentBatch,
    inputs: openArray[JudgmentSourceInput], limits: JudgmentReceiptLimits): WorkJobError =
  ## Temporary canonical wrappers retire before the fixed worker borrows its immutable input graph.
  let selected = services.canonical.chainView
  let captured = captureJudgmentReceiptJob(selected, claims, inputs, limits,
      services.auditBranches.liveViews(selected))
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginJudgmentReceipt*(services: var Services, claims: SignedJudgmentBatch,
    inputs: openArray[JudgmentSourceInput], limits: JudgmentReceiptLimits): AuditPlanningStart {.raises.} =
  ## Complete negative-source preparation is optional and full-node-only; generic collection cannot steal its private origins.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable or services.audits.occupied: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if not services.audits.configured: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  services.audits.drainAbandonedDeclarations()
  let staged = services.stageJudgmentReceipt(claims, inputs, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  result = services.admitManagedAudit()
  if result.error == StateProofAdmissionError.None: services.audits.admitJudgmentReceipt(result.value)

proc stageJudgmentClaims(services: var Services, wire: openArray[byte],
    limits: JudgmentClaimLimits): WorkJobError =
  ## Temporary canonical wrappers retire before the closed worker takes its exclusive original-roster lease.
  let selected = services.canonical.chainView
  let captured = captureJudgmentClaimJob(selected, wire, limits, services.auditBranches.liveViews(selected))
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginJudgmentClaims*(services: var Services, wire: openArray[byte],
    limits: JudgmentClaimLimits): AuditPlanningStart {.raises.} =
  ## Optional full-state verification pauses ordinary canonical/RPC graph access; returned claims contain only detached fixed original-membership facts.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if services.light.active: return AuditPlanningStart(status: StateProofAdmissionError.QueryFailure,
    captureReason: WorkJobError.InvalidInput)
  let staged = services.stageJudgmentClaims(wire, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.admitManagedAudit()

proc stageAuditAnnouncements(services: var Services, wire: openArray[byte],
    limits: AuditReceiptLimits): WorkJobError =
  ## Capture wrappers and copied caller bytes retire before the worker borrows actual full history.
  let selected = services.canonical.chainView
  let captured = captureAuditAnnouncements(selected, wire, limits,
      services.auditBranches.liveViews(selected))
  if captured.error == WorkJobError.None: services.assuranceWorkInput = captured.value
  captured.error

proc beginAuditAnnouncements*(services: var Services, wire: openArray[byte],
    limits: AuditReceiptLimits): AuditPlanningStart {.raises.} =
  ## Only the actual full-state Services history feeds whole-batch proof qualification; a foreign exact lease remains untouched.
  if not services.started: return AuditPlanningStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable: return AuditPlanningStart(
      status: StateProofAdmissionError.Busy)
  if services.light.active: return AuditPlanningStart(status: StateProofAdmissionError.QueryFailure,
      captureReason: WorkJobError.InvalidInput)
  let staged = services.stageAuditAnnouncements(wire, limits)
  if staged != WorkJobError.None: return AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  let admitted = services.admitAssuranceWork()
  case admitted.error
  of StateProofAdmissionError.None: AuditPlanningStart(status: StateProofAdmissionError.None,
      ticket: admitted.value)
  of StateProofAdmissionError.WorkerFailure: AuditPlanningStart(
      status: StateProofAdmissionError.WorkerFailure, workerReason: admitted.workerError)
  of StateProofAdmissionError.Busy: AuditPlanningStart(status: StateProofAdmissionError.Busy)
  of StateProofAdmissionError.QueryFailure: AuditPlanningStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: admitted.captureError)
  of StateProofAdmissionError.Closed: AuditPlanningStart(status: StateProofAdmissionError.Closed)
  of StateProofAdmissionError.Uninitialized: AuditPlanningStart(
      status: StateProofAdmissionError.Uninitialized) # Every selected refusal preserves its actual branch; no future child may silently default.

proc auditContextCurrent*(services: Services, context: AuditContext): bool =
  ## Historical child/body and predecessor identities are compared only after every canonical lease retires.
  services.stateProofAvailable and context.matches(services.canonical.chainView)

proc stageAssurancePlanning(services: var Services, local: StateEdKey,
    limits: AssuranceFetchLimits): WorkJobError =
  ## The actual selected complete source is captured independently of peers and retired temporary view wrappers.
  let captured = captureAssurancePlanning(services.canonical.chainView.bestBlock, local, limits)
  if captured.error != WorkJobError.None: return captured.error
  services.assuranceWorkInput = captured.value
  WorkJobError.None

proc beginAssurancePlanning*(services: var Services, local: StateEdKey,
    limits: AssuranceFetchLimits): AssuranceWorkStart {.raises.} =
  ## Planning requires full-state exclusion but neither a namespace nor a private signing key.
  if not services.started: return AssuranceWorkStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable: return AssuranceWorkStart(
      status: StateProofAdmissionError.Busy)
  let staged = services.stageAssurancePlanning(local, limits)
  if staged != WorkJobError.None: return AssuranceWorkStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.admitAssuranceWork()

proc assurancePlanningCurrent*(services: Services, plan: AssuranceFetchPlan): bool =
  ## Host comparison touches the actual best source only after every foreign lease has retired.
  services.stateProofAvailable and plan.matches(services.canonical.chainView.bestBlock)

proc stageAssuranceSchedule(services: var Services, local: StateEdKey,
    window: AssuranceWindow, limits: AssuranceScheduleLimits): WorkJobError =
  ## The actual best complete source is captured while idle; temporary snapshot/wrapper aliases retire before native publication.
  let captured = captureAssuranceScheduleJob(services.canonical.chainView.bestBlock,
    local, window, limits)
  if captured.error != WorkJobError.None: return captured.error
  services.assuranceWorkInput = captured.value
  WorkJobError.None

proc beginAssuranceSchedule*(services: var Services, local: StateEdKey,
    window: AssuranceWindow, limits: AssuranceScheduleLimits): AssuranceWorkStart {.raises.} =
  ## Timed author planning uses the same exact canonical/RPC lease and requires no archive or private signer.
  if not services.started: return AssuranceWorkStart(status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable: return AssuranceWorkStart(
      status: StateProofAdmissionError.Busy)
  let staged = services.stageAssuranceSchedule(local, window, limits)
  if staged != WorkJobError.None: return AssuranceWorkStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.admitAssuranceWork()

proc assuranceScheduleCurrent*(services: Services, plan: AssuranceSchedule): bool =
  ## Compare the full selected source only after foreign and owned native leases have retired.
  services.stateProofAvailable and plan.matches(services.canonical.chainView.bestBlock)

proc beginAssuranceDistribution*(services: var Services, request: ReadRequest,
    peer: StateEdKey, limits: AssuranceDistributionLimits): AssuranceWorkStart {.raises.} =
  ## Receipt requires full-state canonical/RPC exclusion but neither local shard storage nor a private signer.
  if not services.started: return AssuranceWorkStart(
      status: StateProofAdmissionError.Closed)
  if not services.stateProofAvailable: return AssuranceWorkStart(
      status: StateProofAdmissionError.Busy)
  let staged = services.stageAssuranceDistribution(request, peer, limits)
  if staged != WorkJobError.None: return AssuranceWorkStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.admitAssuranceWork()

proc assuranceDistributionCurrent*(services: Services, checked: CheckedAssurance): bool =
  ## Fresh actual head and complete root are checked only while no foreign canonical lease exists.
  services.stateProofAvailable and checked.matches(services.canonical.chainView.bestBlock)

func error*(outcome: AssuranceSigningStart): AssuranceStorageStartError =
  ## Inspect native admission before extracting its exact ticket or capture/worker refusal.
  outcome.status

func value*(outcome: AssuranceSigningStart): ProofWorkerTicket {.requires: outcome.status ==
    AssuranceStorageStartError.None.} =
  ## Only full source/key/namespace admission grants signing collection or cancellation authority.
  outcome.ticket

func captureError*(outcome: AssuranceSigningStart): AssuranceSigningJobError {.requires: outcome.status ==
    AssuranceStorageStartError.CaptureFailure.} =
  ## Preserve actual source/key/storage/policy capture refusal.
  outcome.captureReason

func workerError*(outcome: AssuranceSigningStart): ProofWorkerError {.requires: outcome.status ==
    AssuranceStorageStartError.WorkerFailure.} =
  ## Failed native submission retains no secret/source aliases or canonical exclusion.
  outcome.workerReason

proc configureAssuranceSigner*(services: var Services, certificate, privateKey: string,
    transportIdentity: StateEdKey): WorkSigningSetupResult =
  ## Explicit full-state setup imports the private key only once and compares its certificate-derived identity with the actual bound TLS identity.
  if not services.started: return WorkSigningSetupResult(status: WorkSigningSetupError.Closed)
  if not services.stateProofAvailable or services.assuranceSignerReady:
    return WorkSigningSetupResult(status: WorkSigningSetupError.Busy)
  if not services.assuranceInfo.opened or services.assuranceInfo.faulted:
    return WorkSigningSetupResult(status: WorkSigningSetupError.InvalidStorage)
  let loaded = loadWorkSigner(certificate, privateKey)
  if loaded.error != WorkSignerError.None:
    return WorkSigningSetupResult(status: WorkSigningSetupError.SignerFailure, reason: loaded)
  let identity = loaded.value.signerIdentity.value
  if array[32, byte](identity) != array[32, byte](transportIdentity):
    return WorkSigningSetupResult(status: WorkSigningSetupError.InvalidIdentity)
  services.assuranceSigner = loaded.value
  services.assuranceSignerIdentity = identity
  services.assuranceSignerReady = true
  WorkSigningSetupResult(status: WorkSigningSetupError.None)

func assuranceSigningConfigured*(services: Services): bool =
  ## Cached scalar observation never touches a private-key ARC owner while a job holds its lease.
  services.started and services.assuranceSignerReady

func assuranceSigningMatches*(services: Services, identity: StateEdKey): bool =
  ## Cached scalar identity checks do not inspect a private signer while another job owns it.
  services.started and services.assuranceSignerReady and
    array[32, byte](services.assuranceSignerIdentity) == array[32, byte](identity)

proc stageAssuranceSigning(services: var Services, requested: AssuranceBits,
    now: AssuranceTime, limits: AssurancePossessionLimits): AssuranceSigningJobError =
  ## Retire every temporary canonical/signer/capture alias before native submission can access the private key.
  let captured = captureAssuranceSigning(services.assuranceStore,
    services.canonical.chainView.bestBlock,
    services.assuranceSigner, services.assuranceInfo.chain, requested, now, limits)
  if captured.error == AssuranceSigningJobError.None: services.assuranceSigningInput = captured.value
  captured.error

proc beginAssuranceSigning*(services: var Services, requested: AssuranceBits,
    now: AssuranceTime, limits: AssurancePossessionLimits): AssuranceSigningStart {.raises.} =
  ## One managed source/key/archive lease performs fresh all-local verification, actual durable renewal and the one private signature.
  if not services.started: return AssuranceSigningStart(status: AssuranceStorageStartError.Closed)
  if services.light.active or not services.assuranceSignerReady or
      not services.assuranceInfo.opened or services.assuranceInfo.faulted:
    return AssuranceSigningStart(status: AssuranceStorageStartError.Unavailable)
  if not services.stateProofAvailable: return AssuranceSigningStart(
      status: AssuranceStorageStartError.Busy)
  discard services.proofWorker.start()
  let reason = services.stageAssuranceSigning(requested, now, limits)
  if reason != AssuranceSigningJobError.None:
    return AssuranceSigningStart(status: AssuranceStorageStartError.CaptureFailure,
        captureReason: reason)
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.assuranceSigningInput = default(AssuranceSigningJob)
    return AssuranceSigningStart(status: AssuranceStorageStartError.Busy)
  services.lastAssurance = default(SignedAssurance)
  let admitted = services.proofWorker.submit(services.assuranceSigningInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true
    services.assuranceSigningActive = true
    return AssuranceSigningStart(status: AssuranceStorageStartError.None, ticket: admitted.value)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.assuranceSigningInput = default(AssuranceSigningJob)
  AssuranceSigningStart(status: AssuranceStorageStartError.WorkerFailure,
      workerReason: admitted.error)

proc currentAssuranceBytes*(services: Services, assurance: SignedAssurance,
    maximum: ByteLimit): AssuranceSigningResult[seq[byte]] =
  ## Only the latest signature collected by this live Services instance may publish against its still-current complete source and healthy installed namespace.
  if not services.stateProofAvailable or not services.assuranceSignerReady or
      not services.assuranceInfo.opened or services.assuranceInfo.faulted:
    return assuranceSigningFailure[seq[byte]](AssuranceSigningError.StaleSource)
  if not sameAssurance(services.lastAssurance, assurance):
    return assuranceSigningFailure[seq[byte]](AssuranceSigningError.StaleSource)
  assurance.assuranceBytes(services.canonical.chainView.bestBlock, maximum)

func error*(outcome: WorkSubmissionStart): StateProofAdmissionError =
  ## Failed starts never expose a session token.
  outcome.status

func value*(outcome: WorkSubmissionStart): WorkSessionToken {.requires: outcome.status ==
    StateProofAdmissionError.None.} =
  ## Session control remains distinct from raw CPU collection authority.
  outcome.token

func captureError*(outcome: WorkSubmissionStart): WorkJobError {.requires: outcome.status ==
    StateProofAdmissionError.QueryFailure.} =
  ## Only an actual failed staging operation carries its cause.
  outcome.captureReason

func workerError*(outcome: WorkSubmissionStart): ProofWorkerError {.requires: outcome.status ==
    StateProofAdmissionError.WorkerFailure.} =
  ## Preserve the actual bounded worker admission refusal.
  outcome.workerReason

func matchesWork(services: Services, token: WorkSessionToken): bool =
  ## Host-only namespace comparisons touch no canonical or job ARC owner.
  token.owner != nil and token.owner == services.workIdentity and token.generation != 0 and
    token.generation == services.workGeneration and services.workPhase != WorkSessionPhase.Empty

func workSessionPhase*(services: Services, token: WorkSessionToken): WorkSessionPhase =
  ## Foreign, stale and default controls observe no session; Busy/Done observations remain scalar.
  if services.matchesWork(token): services.workPhase else: WorkSessionPhase.Empty

func workSubmissionActive*(services: Services, token: WorkSessionToken): bool =
  ## Only this matching session can authorize joined teardown of its selected CPU turn.
  services.matchesWork(token) and services.workActive

proc reapWorkSubmission*(services: var Services): bool =
  ## Deferred graph retirement never collects, cancels or joins an unrelated CPU borrower.
  if services.workPhase != WorkSessionPhase.Retired: return false
  if not services.stateProofAvailable or services.workActive: return false
  services.workInput = default(WorkSubmissionJob)
  services.workContext = default(AuthorizedWorkContext)
  services.workRecovery = default(WorkRecovery)
  services.workRecoveryInfo = default(WorkRecoveryInfo)
  services.workRecoveryJobs = 0
  services.workRecoveryEnabled = false
  services.workFallbackAllowed = false
  services.workOutcome = default(WorkJobResult)
  services.clearWorkExchange()
  services.workTicket = default(ProofWorkerTicket)
  services.workInfo = default(WorkSubmissionInfo)
  services.workDuty = default(WorkDuty)
  services.workReportInfo = default(ComputedReportInfo)
  services.workContributionInfo = default(WorkEligibilityInfo)
  services.workHead = default(BlockHash)
  services.workPhase = WorkSessionPhase.Empty
  true

proc submitWork(services: var Services, phase: WorkSessionPhase): WorkSubmissionStart =
  ## All staging aliases are gone before this function takes the exact RPC/worker lease.
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.workInput = default(WorkSubmissionJob)
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  let admitted = if phase == WorkSessionPhase.Completing:
    # The proof lease excludes preparation until collection or join, so package refinement can use its compiler.
    services.proofWorker.submit(services.workInput, services.nativeRuntime)
  else:
    services.proofWorker.submit(services.workInput)
  if admitted.error == ProofWorkerError.None:
    services.proofing = true
    services.workActive = true
    services.workTicket = admitted.value
    services.workPhase = phase
    return WorkSubmissionStart(status: StateProofAdmissionError.None,
      token: WorkSessionToken(owner: services.workIdentity, generation: services.workGeneration))
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
  services.workInput = default(WorkSubmissionJob)
  WorkSubmissionStart(status: StateProofAdmissionError.WorkerFailure, workerReason: admitted.error)

proc configureWorkSigner*(services: var Services, certificate, privateKey: string,
    transportIdentity: StateEdKey, storage: GuarantorStorageLimits): WorkSigningSetupResult =
  ## Import privately before any work session; the actual transport's cached public identity must match the loaded TLS key.
  if not services.started: return WorkSigningSetupResult(status: WorkSigningSetupError.Closed)
  if not services.stateProofAvailable or services.workPhase != WorkSessionPhase.Empty or
      services.workSignerReady:
    return WorkSigningSetupResult(status: WorkSigningSetupError.Busy)
  if not storage.valid: return WorkSigningSetupResult(status: WorkSigningSetupError.InvalidStorage)
  let loaded = loadWorkSigner(certificate, privateKey)
  if loaded.error != WorkSignerError.None:
    return WorkSigningSetupResult(status: WorkSigningSetupError.SignerFailure, reason: loaded)
  let identity = loaded.value.signerIdentity.value
  if array[32, byte](identity) != array[32, byte](transportIdentity):
    return WorkSigningSetupResult(status: WorkSigningSetupError.InvalidIdentity)
  if not services.guarantorStore.configure(storage):
    return WorkSigningSetupResult(status: WorkSigningSetupError.InvalidStorage)
  services.workSigner = loaded.value
  services.workSignerIdentity = identity
  services.workSignerReady = true
  WorkSigningSetupResult(status: WorkSigningSetupError.None)

func workSigningConfigured*(services: Services): bool =
  ## This scalar is safe to observe while any canonical/signer alias belongs to the worker.
  services.started and services.workSignerReady

func workSignerMatches*(services: Services, identity: StateEdKey,
    storage: GuarantorStorageLimits): bool =
  ## Fixed cached public identity allows a reopened native host to reuse private setup without importing or inspecting the key again.
  if not services.started or not services.workSignerReady: return false
  let original = array[32, byte](services.workSignerIdentity)
  let requested = array[32, byte](identity)
  original == requested and services.guarantorStore.matches(storage)

func retainedWorkBundles*(services: Services): int =
  ## A scalar count is safe during foreign work and does not expose any serving or canonical alias.
  services.guarantorStore.len

func retainedWorkBytes*(services: Services): uint64 =
  ## Logical retained payload remains separate from transient worker/canonical memory.
  services.guarantorStore.byteLength

proc contributionRetention(services: Services, requested: AvailabilityMerkleLimits): AvailabilityMerkleLimits =
  ## The single Services lease keeps this remaining entry/byte budget stable until exact collection or joined cancellation.
  if not requested.validGuarantorLimits: return default(AvailabilityMerkleLimits)
  let available = services.guarantorStore.captureLimits
  if not available.validGuarantorLimits: return default(AvailabilityMerkleLimits)
  AvailabilityMerkleLimits(bytes: ByteLimit(min(uint64(requested.bytes), uint64(available.bytes))),
    hashes: ElementLimit(min(uint64(requested.hashes), uint64(available.hashes))),
    hashBytes: ByteLimit(min(uint64(requested.hashBytes), uint64(available.hashBytes))))

func sameWorkSession*(left, right: WorkSessionToken): bool =
  ## Host-only exact session comparison grants no graph access or cancellation authority.
  left.owner != nil and left.owner == right.owner and left.generation != 0 and left.generation ==
      right.generation

proc workDistributionCurrent*(services: Services, info: WorkDistributionInfo,
    now: StateTime): bool =
  ## Capture a fixed comparison only while canonical access is available; all temporary aliases retire before a caller submits work.
  if not services.stateProofAvailable or uint32(info.observed) != uint32(now): return false
  let head = services.canonical.chainView.bestBlock
  if head.error != GenesisError.None: return false
  let sameHead = array[32, byte](head.value.blockHash) == array[32, byte](info.head)
  let sameRoot = array[32, byte](head.value.stateRoot) == array[32, byte](info.root)
  sameHead and sameRoot

proc stageWorkDistribution(services: var Services, request: ReadRequest, now: StateTime,
    limits: WorkDistributionLimits): WorkJobError =
  ## The staging activation retires all temporary canonical/job aliases before the exact shared lease is granted.
  let captured = captureWorkDistribution(request, services.canonical.chainView, now, limits)
  if captured.error != WorkJobError.None: return captured.error
  services.distributionInput = captured.value
  WorkJobError.None

proc beginWorkDistribution*(services: var Services, request: ReadRequest, now: StateTime,
    limits: WorkDistributionLimits): WorkDistributionStart {.raises.} =
  ## Incoming verification can run while a primary guarantee waits; it neither signs nor replaces that primary source.
  if not services.started: return WorkDistributionStart(status: StateProofAdmissionError.Closed)
  if services.distributionActive or not services.stateProofAvailable:
    return WorkDistributionStart(status: StateProofAdmissionError.Busy)
  if services.distributionGeneration == high(uint64):
    return WorkDistributionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.LimitExceeded)
  let staged = services.stageWorkDistribution(request, now, limits)
  if staged != WorkJobError.None:
    return WorkDistributionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: staged)
  if services.distributionIdentity == nil: services.distributionIdentity = WorkSessionIdentity(marker: 3)
  discard services.proofWorker.start()
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.distributionInput = default(WorkSubmissionJob)
    return WorkDistributionStart(status: StateProofAdmissionError.Busy)
  let admitted = services.proofWorker.submit(services.distributionInput)
  if admitted.error != ProofWorkerError.None:
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    services.distributionInput = default(WorkSubmissionJob)
    return WorkDistributionStart(status: StateProofAdmissionError.WorkerFailure,
        workerReason: admitted.error)
  inc services.distributionGeneration
  services.proofing = true
  services.distributionActive = true
  services.distributionTicket = admitted.value
  WorkDistributionStart(status: StateProofAdmissionError.None, token: WorkDistributionToken(
      owner: services.distributionIdentity, generation: services.distributionGeneration))

func workDistributionActive*(services: Services, token: WorkDistributionToken): bool =
  ## Host-only identity/generation checks never inspect the leased canonical/job graph.
  services.distributionActive and token.owner != nil and token.owner ==
      services.distributionIdentity and token.generation != 0 and token.generation ==
      services.distributionGeneration

proc cancelWorkDistribution*(services: var Services, token: WorkDistributionToken): bool =
  ## Cancellation touches only this exact active proof ticket, leaving every alias frozen until collect or joined stop.
  if not services.workDistributionActive(token): return false
  let ticket = services.distributionTicket
  services.cancelStateProof(ticket)

proc collectWorkDistribution*(services: var Services,
    token: WorkDistributionToken): WorkDistributionCompletion =
  ## Cut source-free results only after matching collection; no caller receives the worker's canonical qualification owner.
  if not services.workDistributionActive(token): return default(WorkDistributionCompletion)
  let ticket = services.distributionTicket
  let completed = services.collectStateProof(ticket)
  if completed.kind == ProofWorkerCompletionKind.Uninitialized: return default(WorkDistributionCompletion)
  services.distributionActive = false
  services.distributionTicket = default(ProofWorkerTicket)
  services.distributionInput = default(WorkSubmissionJob)
  if completed.kind == ProofWorkerCompletionKind.Cancelled:
    return WorkDistributionCompletion(status: WorkDistributionCompletionKind.Cancelled)
  if completed.kind != ProofWorkerCompletionKind.WorkSubmitted:
    return WorkDistributionCompletion(status: WorkDistributionCompletionKind.InvalidResult)
  let outcome = completed.workSubmissionValue
  case outcome.kind
  of WorkJobResultKind.DistributionFailure:
    return WorkDistributionCompletion(status: WorkDistributionCompletionKind.Refused,
        reason: outcome.distributionError)
  of WorkJobResultKind.DistributionEncodingFailure:
    return WorkDistributionCompletion(status: WorkDistributionCompletionKind.EncodingFailure,
        encodingReason: outcome.distributionEncodingError)
  of WorkJobResultKind.DistributionCacheFailure:
    return WorkDistributionCompletion(status: WorkDistributionCompletionKind.CacheFailure,
        cacheReason: outcome.distributionCacheError)
  of WorkJobResultKind.DistributionOutputLimit:
    return WorkDistributionCompletion(status: WorkDistributionCompletionKind.LimitExceeded)
  of WorkJobResultKind.DistributionQualified: discard # This exact success alone permits graph-free extraction below.
  else: return WorkDistributionCompletion(status: WorkDistributionCompletionKind.InvalidResult)
  let checked = outcome.qualifiedDistribution
  let facts = checked.distributionInfo
  if facts.error != WorkDistributionError.None: return WorkDistributionCompletion(
      status: WorkDistributionCompletionKind.InvalidResult)
  if facts.value.targets < 0 or facts.value.targets > 2046: return WorkDistributionCompletion(
      status: WorkDistributionCompletionKind.InvalidResult)
  var targets = newSeq[StateValidator](facts.value.targets)
  for index in 0..<targets.len:
    # Every record is fixed copied data; no snapshot/roster pointer can escape into native routing.
    let selected = checked.distributionTarget(index)
    if selected.error != WorkDistributionError.None: return WorkDistributionCompletion(
        status: WorkDistributionCompletionKind.InvalidResult)
    targets[index] = selected.value
  let payload = checked.distributionPayload
  if payload.error != WorkDistributionError.None: return WorkDistributionCompletion(
      status: WorkDistributionCompletionKind.InvalidResult)
  WorkDistributionCompletion(status: WorkDistributionCompletionKind.Completed, info: facts.value,
    targets: targets, payload: payload.value, report: outcome.distributionReport)

proc stageWorkSharing(services: var Services, request: SharedWorkRequest, local, peer: StateEdKey,
    now: StateTime, limits: WorkSharingLimits): WorkJobError =
  ## Native task aliases remain independent from the detached job; view/key staging aliases retire before admission.
  var bounded = limits
  bounded.retention = services.contributionRetention(limits.retention)
  if not bounded.retention.validGuarantorLimits: return WorkJobError.LimitExceeded
  let captured = captureWorkSharing(request, services.canonical.chainView, local, peer,
    now, services.workSigner, bounded, services.guarantorStore.snapshot)
  if captured.error != WorkJobError.None: return captured.error
  services.sharingInput = captured.value
  WorkJobError.None

proc beginWorkSharing*(services: var Services, request: SharedWorkRequest, local, peer: StateEdKey,
    now: StateTime, limits: WorkSharingLimits): WorkSharingStart {.raises.} =
  ## A waiting primary builder does not monopolize idle CPU capacity or lose its original context.
  if not services.started: return WorkSharingStart(status: StateProofAdmissionError.Closed)
  if not services.workSignerReady or array[32, byte](local) != array[32, byte](
      services.workSignerIdentity):
    return WorkSharingStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  if services.sharingActive or not services.stateProofAvailable:
    return WorkSharingStart(status: StateProofAdmissionError.Busy)
  if services.sharingGeneration == high(uint64):
    return WorkSharingStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.LimitExceeded)
  let staged = services.stageWorkSharing(request, local, peer, now, limits)
  if staged != WorkJobError.None: return WorkSharingStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  if services.sharingIdentity == nil: services.sharingIdentity = WorkSessionIdentity(marker: 2)
  discard services.proofWorker.start()
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil:
    services.sharingInput = default(WorkSubmissionJob)
    return WorkSharingStart(status: StateProofAdmissionError.Busy)
  let admitted = services.proofWorker.submit(services.sharingInput)
  if admitted.error != ProofWorkerError.None:
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    services.sharingInput = default(WorkSubmissionJob)
    return WorkSharingStart(status: StateProofAdmissionError.WorkerFailure,
        workerReason: admitted.error)
  inc services.sharingGeneration
  services.proofing = true
  services.sharingActive = true
  services.sharingTicket = admitted.value
  WorkSharingStart(status: StateProofAdmissionError.None,
    token: WorkSharingToken(owner: services.sharingIdentity,
        generation: services.sharingGeneration))

func matchesSharing(services: Services, token: WorkSharingToken): bool =
  ## Sharing namespaces are host-only and independent from primary work sessions or native stream tickets.
  services.sharingActive and token.owner != nil and token.owner == services.sharingIdentity and
    token.generation != 0 and token.generation == services.sharingGeneration

func workSharingActive*(services: Services, token: WorkSharingToken): bool =
  ## Host-only namespace/generation observation never touches the worker's canonical or signer graph.
  services.matchesSharing(token)

proc cancelWorkSharing*(services: var Services, token: WorkSharingToken): bool =
  ## Cancellation marks only the exact sharing lease; signer/source aliases remain frozen until collect/join.
  if not services.matchesSharing(token): return false
  let ticket = services.sharingTicket
  services.cancelStateProof(ticket)

proc collectWorkSharing*(services: var Services, token: WorkSharingToken): WorkSharingCompletion =
  ## Only exact Done collection installs the most recent privately retained shared bundle and exposes fixed response bytes.
  if not services.matchesSharing(token): return default(WorkSharingCompletion)
  let ticket = services.sharingTicket
  let completed = services.collectStateProof(ticket)
  if completed.kind == ProofWorkerCompletionKind.Uninitialized: return default(WorkSharingCompletion)
  services.sharingActive = false
  services.sharingTicket = default(ProofWorkerTicket)
  services.sharingInput = default(WorkSubmissionJob)
  if completed.kind == ProofWorkerCompletionKind.Cancelled:
    return WorkSharingCompletion(status: WorkSharingCompletionKind.Cancelled)
  if completed.kind != ProofWorkerCompletionKind.WorkSubmitted:
    return WorkSharingCompletion(status: WorkSharingCompletionKind.InvalidResult)
  let outcome = completed.workSubmissionValue
  if outcome.kind == WorkJobResultKind.SharingFailure:
    return WorkSharingCompletion(status: WorkSharingCompletionKind.Refused,
        reason: outcome.sharingError)
  if outcome.kind != WorkJobResultKind.Contributed:
    return WorkSharingCompletion(status: WorkSharingCompletionKind.InvalidResult)
  let contribution = outcome.signedContribution
  let encoded = contribution.sharingResponse
  if encoded.error != WorkSharingError.None:
    return WorkSharingCompletion(status: WorkSharingCompletionKind.InvalidResult)
  let source = contribution.contributionAvailability
  if source.error != WorkSignerError.None:
    return WorkSharingCompletion(status: WorkSharingCompletionKind.InvalidResult)
  if services.guarantorStore.remember(source.value) != GuarantorStoreError.None:
    return WorkSharingCompletion(status: WorkSharingCompletionKind.InvalidResult)
  services.sharedContribution = contribution
  WorkSharingCompletion(status: WorkSharingCompletionKind.Completed, response: encoded.value,
    info: contribution.contributionInfo.value)

proc stageWorkAuthorization(services: var Services, header: WorkSubmissionHeader,
    limits: WorkSubmissionLimits, execution: InputRefinementLimits,
    recipient = default(WorkRecipient), dutyLimits = default(WorkDutyLimits),
    recovery = default(WorkRecoveryPolicy)): WorkJobError =
  ## Complete-state and successful capture aliases retire in this helper before CPU submission.
  let head = services.canonical.chainView.bestBlock
  if head.error != GenesisError.None: return WorkJobError.InvalidInput
  let captured = captureWorkAuthorization(header, head.value.stateSnapshot,
    head.value.chainParameters, limits, execution, recipient, dutyLimits,
    services.canonical.chainView, recovery)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  services.workInfo = header.submissionInfo.value
  services.workHead = head.value.blockHash
  WorkJobError.None

proc beginWorkSubmission*(services: var Services, header: WorkSubmissionHeader,
    limits: WorkSubmissionLimits, execution: InputRefinementLimits,
    recovery = default(WorkRecoveryPolicy)): WorkSubmissionStart {.raises.} =
  ## Optional explicit builder admission shares full-state capacity; partial light state never grants a work context.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if services.light.active: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  discard services.reapWorkSubmission()
  if services.workPhase != WorkSessionPhase.Empty: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if services.workGeneration == high(uint64): return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.LimitExceeded)
  let staged = services.stageWorkAuthorization(header, limits, execution, recovery = recovery)
  if staged != WorkJobError.None: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  if services.workIdentity == nil: services.workIdentity = WorkSessionIdentity(marker: 1)
  inc services.workGeneration
  discard services.proofWorker.start()
  services.submitWork(WorkSessionPhase.Authorizing)

proc stageWorkWire(services: var Services, header: UntrustedWorkHeader,
    limits: WorkSubmissionLimits, execution: InputRefinementLimits,
    recipient: WorkRecipient, dutyLimits: WorkDutyLimits,
        recovery: WorkRecoveryPolicy): WorkJobError =
  ## Raw transcript and decoded package aliases retire here; only private job ownership survives before CPU admission.
  if not header.valid or not recipient.valid: return WorkJobError.InvalidInput
  let first = header.firstMessage
  let package = header.packageMessage
  let head = services.canonical.chainView.bestBlock
  if head.error != GenesisError.None: return WorkJobError.InvalidInput
  let parameters = head.value.chainParameters
  let config = PackageConfig(refineGas: Gas(parameters.get(maxRefineGas)),
    accumulateGas: Gas(parameters.get(maxAccumulateGas)), maxBytes: ByteLimit(MaxBundleBytes))
  let decoded = decodeWorkSubmission(header.kind, first, package, config)
  if decoded.error != WorkSubmissionError.None: return WorkJobError.InvalidInput
  services.stageWorkAuthorization(decoded.value, limits, execution, recipient, dutyLimits, recovery)

proc beginWorkSubmission*(services: var Services, header: UntrustedWorkHeader,
    limits: WorkSubmissionLimits, execution: InputRefinementLimits,
    recipient: WorkRecipient, dutyLimits: WorkDutyLimits,
    recovery = default(WorkRecoveryPolicy)): WorkSubmissionStart {.raises.} =
  ## Native actors pass only detached raw bytes; every decoded header/canonical alias retires before the worker starts.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if services.light.active: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  discard services.reapWorkSubmission()
  if services.workPhase != WorkSessionPhase.Empty: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if services.workGeneration == high(uint64): return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.LimitExceeded)
  let staged = services.stageWorkWire(header, limits, execution, recipient, dutyLimits, recovery)
  if staged != WorkJobError.None: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  if services.workIdentity == nil: services.workIdentity = WorkSessionIdentity(marker: 1)
  inc services.workGeneration
  discard services.proofWorker.start()
  services.submitWork(WorkSessionPhase.Authorizing)

proc workSourceCurrent(services: Services): bool =
  ## Temporary head ownership retires before the caller can submit a completion job.
  let head = services.canonical.chainView.bestBlock
  head.error == GenesisError.None and array[32, byte](head.value.blockHash) == array[32, byte](
      services.workHead)

proc workSubmissionCurrent*(services: Services, token: WorkSessionToken): bool =
  ## A foreign lease prevents observation; otherwise compare original captured provenance with the actual canonical best head.
  if not services.stateProofAvailable or not services.matchesWork(token): return false
  services.workSourceCurrent

func workRecoveryEnabled*(services: Services, token: WorkSessionToken): bool =
  ## Cached scalar capability presence is safe even through a foreign uncollected Done lease.
  services.matchesWork(token) and services.workRecoveryEnabled

func workFallbackAllowed*(services: Services, token: WorkSessionToken): bool =
  ## Only a collected remote import refusal can resume the retained original authorization for fallback.
  services.matchesWork(token) and services.workFallbackAllowed

func workRecoveryInfo*(services: Services, token: WorkSessionToken): WorkRecoveryInfo {.requires: services.matchesWork(token).} =
  ## Scalar progress copies never touch private packet, catalog or grant aliases while another worker owns them.
  services.workRecoveryInfo

proc activateWorkRecovery*(services: var Services, token: WorkSessionToken): ReadError =
  ## A missing preferred reply or collected peer import refusal can activate only the exact original prepared recovery context.
  if not services.matchesWork(token) or not services.workRecoveryEnabled: return ReadError.Unavailable
  if not services.stateProofAvailable: return ReadError.Busy
  if services.workPhase != WorkSessionPhase.Authorized:
    if services.workPhase != WorkSessionPhase.Failed or
        not services.workFallbackAllowed: return ReadError.InvalidRequest
  if not services.workSourceCurrent: return ReadError.Unavailable
  services.workOutcome = default(WorkJobResult)
  services.clearWorkExchange()
  services.workFallbackAllowed = false
  services.workPhase = WorkSessionPhase.Recovering
  ReadError.None

proc workRecoveryRequest*(services: Services, token: WorkSessionToken,
    validator: StateValidatorIndex): WorkRecoveryResult[WorkRecoveryRequest] =
  ## Return detached request/key facts only while the private graph is idle and this exact session is ready for a packet.
  if not services.matchesWork(token) or not services.workRecoveryEnabled: return default(
      WorkRecoveryResult[WorkRecoveryRequest])
  if not services.stateProofAvailable or services.workPhase != WorkSessionPhase.Recovering:
    return default(WorkRecoveryResult[WorkRecoveryRequest])
  services.workRecovery.recoveryRequest(validator)

proc stageWorkRecoveryPacket(services: var Services, version: uint64,
    validator: StateValidatorIndex, wire: openArray[byte]): WorkJobError =
  ## Retire every context/progress capture alias before entering the exclusive worker.
  let captured = captureWorkRecoveryPacket(services.workContext, services.workRecovery, version,
      validator, wire)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc stageWorkRecoveryRetry(services: var Services): WorkJobError =
  ## Only the private matching progress is captured; host code cannot set its proven discriminator.
  let captured = captureWorkRecoveryRetry(services.workContext, services.workRecovery)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc stageRecoveredWorkPackage(services: var Services, extrinsics: openArray[byte]): WorkJobError =
  ## Original package/progress owners remain private until this staging activation has retired.
  let captured = captureRecoveredWorkPackage(services.workContext, services.workRecovery, extrinsics)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc beginWorkRecoveryPacket*(services: var Services, token: WorkSessionToken, version: uint64,
    validator: StateValidatorIndex, wire: openArray[byte]): WorkSubmissionStart =
  ## Admit at most the declared number of bounded proof-check turns, independent from native/peer cancellation.
  if not services.matchesWork(token) or not services.workRecoveryEnabled:
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable or services.workPhase != WorkSessionPhase.Recovering:
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  if not services.workSourceCurrent: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let limit = uint64(services.workRecovery.recoveryPolicy.limits.requests)
  if services.workRecoveryJobs >= limit: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.LimitExceeded)
  let staged = services.stageWorkRecoveryPacket(version, validator, wire)
  if staged != WorkJobError.None: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  inc services.workRecoveryJobs
  services.submitWork(WorkSessionPhase.CheckingRecovery)

proc beginWorkRecoveryRetry*(services: var Services, token: WorkSessionToken): WorkSubmissionStart =
  ## Exhaustion can only discard unproven bytes through a closed private CPU job.
  if not services.matchesWork(token) or not services.workRecoveryEnabled:
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable or services.workPhase != WorkSessionPhase.Recovering:
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  if not services.workSourceCurrent: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let staged = services.stageWorkRecoveryRetry()
  if staged != WorkJobError.None: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.CheckingRecovery)

proc beginRecoveredWorkPackage*(services: var Services, token: WorkSessionToken,
    extrinsics: openArray[byte]): WorkSubmissionStart =
  ## Complete recovered original input tables and refine only under this fresh source's next exclusive CPU turn.
  if not services.matchesWork(token) or not services.workRecoveryEnabled:
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable or services.workPhase != WorkSessionPhase.Recovering:
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  if not services.workSourceCurrent: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let staged = services.stageRecoveredWorkPackage(extrinsics)
  if staged != WorkJobError.None: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.Completing)

proc stageWorkBundle(services: var Services, extrinsics, segments,
    proofs: openArray[byte]): WorkJobError =
  ## Every context/capture alias retires in this helper activation before native CPU admission.
  let captured = captureWorkBundle(services.workContext, extrinsics, segments, proofs)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc stageWorkPackage(services: var Services, extrinsics: openArray[byte],
    imports: openArray[seq[VerifiedImport]], lookup: openArray[SegmentLookup]): WorkJobError =
  ## Original grant and independently verified availability aliases remain private until this staging activation retires.
  let captured = captureWorkPackage(services.workContext, extrinsics, imports, lookup)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc stageFetchedWorkPackage(services: var Services, extrinsics,
    reply: openArray[byte]): WorkJobError =
  ## Retire all plan/context staging aliases before the detached job is admitted to the managed CPU worker.
  let captured = captureFetchedWorkPackage(services.workContext, extrinsics, reply)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc workImportRequest*(services: Services, token: WorkSessionToken): WorkSubmissionResult[seq[byte]] =
  ## Detached raw request bytes may be retained during later graph leases; reading the private context itself requires idle ownership.
  if not services.started or not services.matchesWork(token):
    return default(WorkSubmissionResult[seq[byte]])
  if not services.stateProofAvailable or services.workPhase != WorkSessionPhase.Authorized:
    return default(WorkSubmissionResult[seq[byte]])
  services.workContext.importRequest

proc beginFetchedWorkPackage*(services: var Services, token: WorkSessionToken,
    extrinsics, reply: openArray[byte]): WorkSubmissionStart =
  ## Only the original live authorized session can admit fetched bytes, verification and refinement under its selected state.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if not services.matchesWork(token): return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable or services.workPhase != WorkSessionPhase.Authorized:
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  if not services.workSourceCurrent:
    services.workPhase = WorkSessionPhase.Retired
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  let staged = services.stageFetchedWorkPackage(extrinsics, reply)
  if staged != WorkJobError.None: return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.Completing)

proc beginWorkBundle*(services: var Services, token: WorkSessionToken,
    extrinsics, segments, proofs: openArray[byte]): WorkSubmissionStart =
  ## A body wait holds no CPU lease; only the original authorized session can capture the next bounded CPU turn.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if not services.matchesWork(token): return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if services.workPhase != WorkSessionPhase.Authorized: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if not services.workSourceCurrent:
    services.workPhase = WorkSessionPhase.Retired
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  let staged = services.stageWorkBundle(extrinsics, segments, proofs)
  if staged != WorkJobError.None: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.Completing)

proc beginWorkPackage*(services: var Services, token: WorkSessionToken,
    extrinsics: openArray[byte], imports: openArray[seq[VerifiedImport]],
    lookup: openArray[SegmentLookup]): WorkSubmissionStart =
  ## CE133 feeds separately acquired immutable availability witnesses into the same source-bound completion turn.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if not services.matchesWork(token): return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if services.workPhase != WorkSessionPhase.Authorized: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if not services.workSourceCurrent:
    services.workPhase = WorkSessionPhase.Retired
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  let staged = services.stageWorkPackage(extrinsics, imports, lookup)
  if staged != WorkJobError.None: return WorkSubmissionStart(
      status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.Completing)

proc stageWorkReport(services: var Services, limits: WorkReportLimits): WorkJobError =
  ## Retain only this session's original completed refinement; every temporary source alias retires before CPU submission.
  if services.workOutcome.kind != WorkJobResultKind.Refined: return WorkJobError.InvalidInput
  let captured = captureWorkReport(services.workContext, services.workOutcome.execution,
    services.workDuty.shardCount, limits)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc beginWorkReport*(services: var Services, token: WorkSessionToken,
    limits: WorkReportLimits, now: StateTime): WorkSubmissionStart =
  ## Only the fresh original network session chooses its actual source roster count; no caller report or shard-count replacement is accepted.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if not services.matchesWork(token): return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if services.workPhase != WorkSessionPhase.Complete: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if not services.workDuty.activeAt(now): return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.workSourceCurrent:
    services.workPhase = WorkSessionPhase.Retired
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  let staged = services.stageWorkReport(limits)
  if staged != WorkJobError.None: return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.Reporting)

proc stageWorkContribution(services: var Services, local: StateEdKey, now: StateTime,
    limits: WorkEligibilityLimits, retention: AvailabilityMerkleLimits): WorkJobError =
  ## Original execution and the actual fresh canonical view retire from staging before the exclusive CPU lease begins.
  let captured = captureWorkContribution(services.workContext,
    services.workOutcome.reportTranscript,
    services.canonical.chainView, local, now, services.workSigner, limits, retention,
    services.guarantorStore.snapshot)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc beginWorkContribution*(services: var Services, token: WorkSessionToken,
    transportIdentity: StateEdKey, now: StateTime,
        limits: WorkEligibilityLimits, retention: AvailabilityMerkleLimits): WorkSubmissionStart =
  ## Omission remains disabled; requalify original execution against fresh state and sign on the same managed turn.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if not services.matchesWork(token) or not services.workSignerReady:
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  if array[32, byte](services.workSignerIdentity) != array[32, byte](transportIdentity):
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable: return WorkSubmissionStart(
      status: StateProofAdmissionError.Busy)
  if services.workPhase != WorkSessionPhase.ReportReady:
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  let bounded = services.contributionRetention(retention)
  if not bounded.validGuarantorLimits:
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure,
        captureReason: WorkJobError.LimitExceeded)
  let staged = services.stageWorkContribution(transportIdentity, now, limits, bounded)
  if staged != WorkJobError.None:
    return WorkSubmissionStart(status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.Signing)

proc stageWorkExchange(services: var Services, maximum: ByteLimit): WorkJobError =
  ## Temporary contribution aliases retire before preparation takes its exclusive graph lease.
  if services.workOutcome.kind != WorkJobResultKind.Contributed: return WorkJobError.InvalidInput
  let captured = captureWorkExchange(services.workOutcome.signedContribution, maximum)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc beginWorkExchange*(services: var Services, token: WorkSessionToken,
    maximum: ByteLimit): WorkSubmissionStart =
  ## Prepare only this genuine signed session; signer setup and exact prior collection are prerequisites.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if not services.matchesWork(token): return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable or services.workPhase != WorkSessionPhase.Contributed:
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  let staged = services.stageWorkExchange(maximum)
  if staged != WorkJobError.None: return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.PreparingExchange)

proc stageWorkResponse(services: var Services, position: int, peer: StateEdKey,
    response: array[96, byte]): WorkJobError =
  ## Only the private round and fixed copies enter verification, never its native raw-request cache.
  let captured = captureWorkResponse(services.workRound, services.workShareTargets[position], peer, response)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc beginWorkPeerResponse*(services: var Services, token: WorkSessionToken,
    position: int, transportIdentity: StateEdKey, response: array[96, byte]): WorkSubmissionStart =
  ## The ordinal selects a privately prepared target; actual TLS identity is a host observation, never packet metadata.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if not services.matchesWork(token): return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable or services.workPhase !=
      WorkSessionPhase.AwaitingContributions:
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  if position < 0 or position >= services.workExchangeState.targets: return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let staged = services.stageWorkResponse(position, transportIdentity, response)
  if staged != WorkJobError.None: return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.CheckingContribution)

proc stageWorkGuarantee(services: var Services, maximum: ByteLimit): WorkJobError =
  ## Temporary round aliases retire before final canonical encoding borrows the shared graph.
  let captured = captureWorkGuarantee(services.workRound, maximum)
  if captured.error != WorkJobError.None: return captured.error
  services.workInput = captured.value
  WorkJobError.None

proc beginWorkGuaranteeCollection*(services: var Services, token: WorkSessionToken,
    maximum: ByteLimit): WorkSubmissionStart =
  ## Two actual collected credentials are necessary; resource policy never supplies missing credential authority.
  if not services.started: return WorkSubmissionStart(status: StateProofAdmissionError.Closed)
  if not services.matchesWork(token): return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  if not services.stateProofAvailable or services.workPhase !=
      WorkSessionPhase.AwaitingContributions:
    return WorkSubmissionStart(status: StateProofAdmissionError.Busy)
  if services.workExchangeState.credentials < 2: return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: WorkJobError.InvalidInput)
  let staged = services.stageWorkGuarantee(maximum)
  if staged != WorkJobError.None: return WorkSubmissionStart(
    status: StateProofAdmissionError.QueryFailure, captureReason: staged)
  services.submitWork(WorkSessionPhase.CollectingGuarantee)

func workExchangeInfo*(services: Services, token: WorkSessionToken): WorkExchangeInfo =
  ## Fixed committed counters/status retain no alias to worker-owned canonical state.
  if services.matchesWork(token): services.workExchangeState else: default(WorkExchangeInfo)

func workShareTarget*(services: Services, token: WorkSessionToken,
    position: int): WorkShareTarget {.requires:
    services.matchesWork(token) and exchangeWorkPhase(services.workPhase) and
    position >= 0 and position < services.workExchangeState.targets.} =
  ## Complete fixed target metadata can be copied through an active or unrelated CPU lease.
  services.workShareTargets[position]

proc workSharingRequest*(services: Services, token: WorkSessionToken): SharedWorkRequest {.requires:
    services.matchesWork(token) and exchangeWorkPhase(services.workPhase).} =
  ## Independent raw bytes carry no canonical/signer reference and remain safe for native sends during verification.
  services.workSharedRequest

proc workGuaranteePayload*(services: Services, token: WorkSessionToken): seq[byte] {.requires:
    services.matchesWork(token) and services.workPhase == WorkSessionPhase.Guaranteed.} =
  ## Copy the independent raw cache rather than the collected guarantee graph's private sequence.
  result = newSeq[byte](services.workGuaranteeBytes.len)
  for index in 0..<result.len: result[index] = services.workGuaranteeBytes[index]

proc workExchangeOutcome*(services: Services, token: WorkSessionToken): WorkJobResult {.requires:
    services.stateProofAvailable and services.matchesWork(token).} =
  ## Retire every extracted source-bearing alias before admitting another shared-graph borrower.
  services.workExchangeOutcome

proc collectWorkSubmission*(services: var Services, token: WorkSessionToken): WorkSessionPhase =
  ## Exact matching Done collection installs source-bearing artifacts privately and exposes only scalar phase.
  if not services.matchesWork(token): return WorkSessionPhase.Empty
  if not services.workActive: return services.workPhase
  block:
    # Collected owners retire before this host activation returns and another CPU job may be admitted.
    let ticket = services.workTicket
    let completed = services.collectStateProof(ticket)
    if completed.kind == ProofWorkerCompletionKind.Uninitialized: return services.workPhase
    services.workActive = false
    if services.workPhase == WorkSessionPhase.Retired or completed.kind ==
        ProofWorkerCompletionKind.Cancelled:
      services.workPhase = WorkSessionPhase.Retired
      return services.workPhase
    if completed.kind != ProofWorkerCompletionKind.WorkSubmitted:
      services.workPhase = WorkSessionPhase.Failed
      return services.workPhase
    let outcome = completed.workSubmissionValue
    case outcome.kind
    of WorkJobResultKind.Authorized:
      services.workContext = outcome.context
      services.workDuty = services.workContext.duty
      services.workRecovery = services.workContext.recovery
      let recovery = services.workRecovery.recoveryInfo
      services.workRecoveryEnabled = recovery.error == WorkRecoveryError.None
      if services.workRecoveryEnabled: services.workRecoveryInfo = recovery.value
      services.workPhase = WorkSessionPhase.Authorized
    of WorkJobResultKind.RecoveryUpdated:
      services.workRecovery = outcome.recovery
      services.workRecoveryInfo = services.workRecovery.recoveryInfo.value
      services.workOutcome = default(WorkJobResult)
      services.workPhase = WorkSessionPhase.Recovering
    of WorkJobResultKind.RecoveryFailure:
      services.workOutcome = outcome
      if services.workPhase == WorkSessionPhase.CheckingRecovery and
          outcome.recoveryError.peerRejected:
        services.workPhase = WorkSessionPhase.Recovering
      else:
        services.workPhase = WorkSessionPhase.Failed
    of WorkJobResultKind.BodyFailure:
      services.workOutcome = outcome
      services.workPhase = WorkSessionPhase.Failed
      if services.workRecoveryEnabled and services.workInfo.kind == WorkSubmissionKind.Package:
        let reason = outcome.bodyError
        if reason.error == WorkSubmissionError.InvalidMessage: services.workFallbackAllowed = true
        if reason.error == WorkSubmissionError.ImportFailure:
          services.workFallbackAllowed = reason.importError in [
            work_imports.ImportJustificationError.InvalidProof,
            work_imports.ImportJustificationError.InvalidIndex,
            work_imports.ImportJustificationError.RootMismatch]
    of WorkJobResultKind.Refined:
      services.workOutcome = outcome
      services.workPhase = WorkSessionPhase.Complete
    of WorkJobResultKind.Contributed:
      let source = outcome.signedContribution.contributionAvailability
      if source.error != WorkSignerError.None or services.guarantorStore.remember(source.value) !=
          GuarantorStoreError.None:
        services.workOutcome = default(WorkJobResult) # A failed local retention invariant must never expose a signature.
        services.workPhase = WorkSessionPhase.Failed
        return services.workPhase
      services.clearWorkExchange() # A new signature never inherits a prior round's targets or peer credentials.
      services.workOutcome = outcome
      services.workContributionInfo = outcome.signedContribution.contributionInfo.value
      services.workPhase = WorkSessionPhase.Contributed
    of WorkJobResultKind.ExchangePrepared:
      services.workRound = outcome.exchangeRound
      services.workSharedRequest = outcome.exchangeRequest
      services.workShareTargets = outcome.exchangeTargets
      services.workExchangeState.targets = outcome.exchangeTargetCount
      services.workExchangeState.credentials = services.workRound.credentialCount
      let sizes = services.workSharedRequest.sharingInfo.value
      services.workExchangeState.requestBytes = sizes.headerBytes+sizes.bundleBytes+9
      services.workExchangeState.status = outcome.kind
      services.workExchangeOutcome = outcome
      services.workPhase = WorkSessionPhase.AwaitingContributions
    of WorkJobResultKind.PeerAccepted:
      services.workRound = outcome.exchangeRound
      services.workExchangeState.credentials = services.workRound.credentialCount
      services.workExchangeState.status = outcome.kind
      services.workExchangeOutcome = outcome
      services.workPhase = WorkSessionPhase.AwaitingContributions
    of WorkJobResultKind.ExchangePreparationFailure:
      services.workExchangeOutcome = outcome
      services.workExchangeState.status = outcome.kind
      services.workPhase = WorkSessionPhase.Contributed # Genuine original signing can retry a larger byte budget.
    of WorkJobResultKind.PeerResponseFailure, WorkJobResultKind.GuaranteeCollectionFailure:
      services.workExchangeOutcome = outcome
      services.workExchangeState.status = outcome.kind
      services.workPhase = WorkSessionPhase.AwaitingContributions # Refusal preserves every previously accepted credential.
    of WorkJobResultKind.GuaranteeCollected:
      let guarantee = outcome.collectedGuarantee
      let payload = guarantee.guaranteePayload
      if payload.error != WorkGuaranteeError.None:
        services.workPhase = WorkSessionPhase.Failed
        return services.workPhase # An inconsistent/default owner cannot expose completed wire bytes.
      services.workGuarantee = guarantee
      services.workGuaranteeBytes = payload.value
      services.workExchangeState.guaranteeBytes = services.workGuaranteeBytes.len
      services.workExchangeState.status = outcome.kind
      services.workExchangeOutcome = outcome
      services.workPhase = WorkSessionPhase.Guaranteed
    of WorkJobResultKind.Reported:
      services.workOutcome = outcome
      services.workReportInfo = outcome.reportTranscript.computedGuaranteeReport.value.computedReportInfo.value
      services.workPhase = WorkSessionPhase.ReportReady
    else:
      services.workOutcome = outcome
      services.workPhase = WorkSessionPhase.Failed # Genuine failure details stay owned until explicit safe extraction or retirement.
  services.workPhase

proc retireWorkSubmission*(services: var Services, token: WorkSessionToken): bool =
  ## Mark scalar retirement immediately; foreign Queued/Running/Done capacity and canonical ARC owners remain untouched.
  if not services.matchesWork(token): return false
  services.workPhase = WorkSessionPhase.Retired
  if services.workActive:
    let ticket = services.workTicket
    discard services.cancelStateProof(ticket)
  discard services.reapWorkSubmission()
  true

proc workSubmissionInfo*(services: Services, token: WorkSessionToken): WorkSubmissionInfo {.requires: services.matchesWork(token).} =
  ## Detached copied reader geometry remains safe to observe while any worker owns the shared graph.
  services.workInfo

func workSubmissionDuty*(services: Services, token: WorkSessionToken): WorkDuty {.requires: services.matchesWork(token).} =
  ## Fixed assignment metadata stays safe to observe while another borrower owns the canonical graph; defaults have no duty claim.
  services.workDuty

func workSubmissionReportInfo*(services: Services,
    token: WorkSessionToken): ComputedReportInfo {.requires:
    services.matchesWork(token) and (services.workPhase == WorkSessionPhase.ReportReady or
      signedWorkPhase(services.workPhase)).} =
  ## Fixed copied report metadata is safe during foreign graph leases; source-bearing transcript access remains gated.
  services.workReportInfo

func workSignedInfo*(services: Services, token: WorkSessionToken): WorkEligibilityInfo {.requires: services.matchesWork(
    token) and signedWorkPhase(services.workPhase).} =
  ## Only fixed scalar facts escape while the genuine contribution remains private to the collected session.
  services.workContributionInfo

proc workSubmissionOutcome*(services: Services, token: WorkSessionToken): WorkJobResult {.requires:
    services.stateProofAvailable and services.matchesWork(token) and
    (services.workPhase in {WorkSessionPhase.Complete, WorkSessionPhase.ReportReady,
        WorkSessionPhase.Failed} or
      signedWorkPhase(services.workPhase)).} =
  ## The caller must retire every returned source-bearing alias before admitting any subsequent shared-graph CPU job.
  services.workOutcome

func preparationActive*(services: Services): bool =
  ## Done and cancelled work still retain the canonical exclusion gate until collection or joined close.
  services.preparing

proc preparationAvailable*(services: Services): bool =
  ## Preflight scalar exclusion before reading any canonical handle; no implicit legacy state is permitted.
  if services.light.active: return false # Partial evidence never authorizes complete execution.
  if not services.started or services.proofing or services.preparing or services.publishing:
    return false # Existing native work owns all shared graph aliases.
  if services.diskFaulted or services.rpc.chainPaused:
    return false # IO uncertainty or another RPC lease forbids new execution.
  if services.adoption.stage != AccumulationHandoffStage.Idle or
      services.currentAdoption.phase != CurrentHandoffPhase.Idle:
    return false # Pending and unacknowledged work retain bounded producer capacity.
  services.canonical.stateSnapshot.error == StateStoreError.None

proc beginPreparation*(services: var Services, input: var BlockInput,
    id: BlockInputId): PreparationAdmission {.raises, requires: services.preparationAvailable.} =
  ## Pause RPC before worker admission; all existing input/chain/context aliases and info queries remain untouched until exact collection/join.
  discard services.worker.start() # Reuse an existing idle thread without spawning per job.
  services.rpcLease = services.rpc.pauseChain()
  let admitted = services.worker.submit(input, id, services.canonical,
      residency = addr services.executionContext)
  if admitted.error == PreparationError.None:
    services.preparing = true # No fallible canonical/alias work follows successful worker submission.
  else:
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # A refused input grants no lease and restores ordinary RPC ticks.
  admitted

proc beginPreparation*(services: var Services, input: var CurrentBlockInput,
    id: CurrentBlockInputId): PreparationAdmission {.raises,
        requires: services.preparationAvailable.} =
  ## Pause chain RPC before handing stable input and canonical storage to the worker.
  ## Plain ARC requires all existing graph and context aliases to stay untouched.
  ## A refusal restores RPC immediately. Cancellation and Done still hold the gate:
  ## exact collection or joined close retires the borrow before resuming access.
  discard services.worker.start() # The existing fixed-address thread handles both payload alternatives.
  services.rpcLease = services.rpc.pauseChain()
  let admitted = services.worker.submit(input, id, services.canonical,
      residency = addr services.executionContext)
  if admitted.error == PreparationError.None:
    services.preparing = true # No host graph work follows successful native admission.
  else:
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # Refused submission grants no lease or current authority.
  admitted

proc stageAuditPreparation(services: var Services, parent: genesis.BlockHash): bool =
  ## Retire temporary wrappers before the native job borrows the stable Services field.
  let branch = services.auditBranchParent(parent)
  if branch.error != ApplicationChainError.None: return false
  services.auditPreparationChain = branch.value
  true

proc beginAuditBranchPreparation*(services: var Services, input: var CurrentBlockInput,
    id: CurrentBlockInputId, parent: genesis.BlockHash): PreparationAdmission {.raises.} =
  ## Use the ordinary current STF worker, retaining the original branch exclusively through exact collection.
  if not services.preparationAvailable or not services.stageAuditPreparation(parent):
    return default(PreparationAdmission)
  discard services.worker.start()
  services.rpcLease = services.rpc.pauseChain()
  let admitted = services.worker.submit(input, id, services.auditPreparationChain,
      residency = addr services.executionContext)
  if admitted.error == PreparationError.None:
    services.preparing = true
  else:
    services.auditPreparationChain = default(ApplicationChain)
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
  admitted

proc preparationPhase*(services: var Services): PreparationPhase =
  ## Poll only the worker's synchronized scalar lifecycle state.
  services.worker.phase

proc cancelPreparation*(services: var Services, ticket: PreparationTicket): bool =
  ## Cancellation never reopens canonical or RPC access before actual retirement.
  services.worker.cancel(ticket)

proc collectPreparation*(services: var Services, ticket: PreparationTicket): PreparationCompletion =
  ## Restore canonical and RPC access only after the exact completion retires.
  ## The returned certificate still needs explicit host adoption. A foreign, stale
  ## or unfinished ticket leaves exclusion in force.
  result = services.worker.collect(ticket)
  if result.kind != PreparationCompletionKind.Uninitialized:
    services.auditPreparationChain = default(ApplicationChain)
    services.preparing = false
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # Stale/early collection cannot release another active lease.
    if services.stateProofAvailable: services.audits.drainAbandonedDeclarations()

proc planCollectedSupplied*(services: Services, receipt: PreparationCompletion,
    limits: CollectedSuppliedLimits): CollectedSuppliedPlanResult[CollectedSuppliedPlan] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Freeze only the genuine collected target while the actual canonical host gate is open.
  collected_supplied_plan.planCollectedSupplied(services.canonical, receipt, limits)

proc executeCollectedSupplied*(services: Services, plan: CollectedSuppliedPlan,
    declarations: openArray[StateService]): CollectedSuppliedResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Recheck frozen prior provenance and complete borrowed successor declarations outside every managed native lease.
  collected_supplied_state.executeCollectedSupplied(services.canonical, plan, declarations)

proc captureLogicalCheckpoint*(services: Services, source: CurrentLogicalState,
    limit: ByteLimit): LogicalCheckpointResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Explicit retained logical sources may share canonical ARC graphs; checkpoint copying requires the managed host gate open.
  logical_checkpoint.captureLogicalCheckpoint(source, limit)

proc reviewLogicalState*(services: Services, source: CurrentLogicalState,
    limits: AccountReviewPlanLimits): LogicalReviewResult[ReviewedLogicalState] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Explicit immutable logical sources may alias canonical state; original-current review runs only outside all managed graph leases.
  logical_review.reviewLogicalState(source, limits)

proc planLogicalReview*(services: Services, source: CurrentLogicalState,
    limits: AccountReviewPlanLimits): LogicalReviewResult[LogicalReviewPlan] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Frozen admission may share canonical graphs, so every existing native exclusion remains checked.
  logical_review.planLogicalReview(source, limits)

proc executeLogicalReview*(services: Services,
    source: LogicalReviewPlan): LogicalReviewResult[ReviewedLogicalState] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Content retry touches retained original aliases only outside native graph leases; it grants no adoption authority.
  logical_review.executeLogicalReview(source)

proc captureLogicalSeed*(services: Services, declarations: openArray[StateService],
    limits: LogicalSeedLimits): LogicalSeedResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Select the actual physical canonical parent only while all managed native aliases are available.
  logical_seed.captureLogicalSeed(services.canonical, declarations, limits)

proc refreshCollectedLogical*(services: Services, completion: PreparationCompletion,
    source: SelectedLogicalParent, limits: CollectedLogicalLimits): CollectedLogicalResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Run bounded host qualification only after all managed native leases end; canonical installation remains separately owned.
  collected_logical.refreshCollectedLogical(services.canonical, completion, source, limits)

proc refreshCollectedLogical*(services: Services, completion: PreparationCompletion,
    source: CurrentLogicalState, limits: CollectedLogicalLimits): CollectedLogicalResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Run bounded host qualification only after all managed native leases end; canonical installation remains separately owned.
  collected_logical.refreshCollectedLogical(services.canonical, completion, source, limits)

proc takeAccumulation*(services: var Services): ApplicationChainResult[BlockSnapshot] {.requires:
    services.accumulationStage == AccumulationHandoffStage.Finished.} =
  ## Acknowledge the exact retained outcome before accepting another candidate.
  result = services.adoption.take()
  if result.error == ApplicationChainError.None:
    log(services.historyLog, LogTarget.Application, LogLevel.Info, "Imported block, " &
        services.describeHead)
  else:
    log(services.historyLog, LogTarget.Application, LogLevel.Warn, "Block import rejected: " & $result.error)

proc cancelAccumulation*(services: var Services): bool =
  ## Cancel only unattempted work; finished outcomes still require acknowledgement or explicit shutdown.
  if services.proofing or services.preparing or services.publishing: return false # Active preparation has no pending adoption to cancel.
  services.adoption.cancel()

proc stageDiskPublication(services: var Services): bool =
  ## This complete activation retires every local prepared/source alias BEFORE worker submission begins.
  if services.diskFaulted:
    services.adoption.completePublication(durabilityFailure())
    return false
  let prepared = services.adoption.preparePending(services.canonical)
  if prepared.error != ChainPreparationError.None:
    services.adoption.completePublication(preparationRefusal(prepared))
    return false
  services.rpcLease = services.rpc.pauseChain()
  if services.chainRpc and not services.canonical.canInstallPrepared(services.rpc, prepared.value,
      services.rpcLease):
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    services.adoption.completePublication(durabilityFailure())
    return false
  let staged = prepareDiskPublication(services.disk, services.canonical, prepared.value,
    services.diskId, services.diskLimits.contextBytes, replay = services.diskResume)
  if staged.error != DiskChainError.None:
    services.diskStageOutcome = staged
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    services.adoption.completePublication(durabilityFailure())
    return false
  services.diskStageOutcome = default(DiskChainResult[PreparedDiskPublication])
  services.diskCommitOutcome = default(DiskChainResult[RepositoryGeneration])
  services.diskPublication = staged.value
  services.adoption.markPublishing() # Drop pending source/limits before any native graph access is possible.
  true

proc stageCurrentDiskPublication(services: var Services): bool =
  ## Retire every local current/context alias before the caller grants the native disk borrow.
  services.currentDiskStageOutcome = default(DiskChainResult[PreparedCurrentDiskPublication])
  services.currentDiskAdmission = DiskWorkerError.Uninitialized
  services.diskCommitOutcome = default(DiskChainResult[
      RepositoryGeneration]) # No previous job's receipt can authorize this attempt.
  if services.diskFaulted:
    services.currentAdoption.refusePublication(CurrentHandoffError.DurabilityRefused)
    return false
  let prepared = services.currentAdoption.pendingUpdate
  if not services.canonical.canInstallPrepared(prepared):
    services.currentAdoption.refusePublication(CurrentHandoffError.StaleState)
    return false
  services.rpcLease = services.rpc.pauseChain()
  if services.rpcLease == nil or (services.chainRpc and not services.canonical.canInstallPrepared(
      services.rpc, prepared, services.rpcLease)):
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    services.currentAdoption.refusePublication(CurrentHandoffError.RpcRefused)
    return false # A foreign pause or refused enabled listener grants no disk operation or canonical fallback.
  let staged = prepareDiskPublication(services.disk, services.canonical, prepared,
    services.diskId, services.diskLimits.contextBytes, replay = services.diskResume)
  if staged.error != DiskChainError.None:
    services.currentDiskStageOutcome = staged
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    services.currentAdoption.refusePublication(CurrentHandoffError.DurabilityRefused)
    return false
  services.currentDiskPublication = staged.value
  services.currentAdoption.markPublishing() # Freeze the expected child before the native operation can begin.
  true

func startupDiskMaintenanceOutcome*(services: Services): DiskChainResult[
    ManagedCompaction] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Retain a real pre-listener startup compaction receipt; default means no startup maintenance was due.
  services.startupMaintenance

func diskMaintenanceFailed*(services: Services): bool {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Observe actual preparation/admission/IO/cleanup failure without treating joined nonexecution as rollback or failure.
  if services.maintenanceStage.error notin {DiskChainError.Uninitialized,
      DiskChainError.None}: return true
  if services.maintenanceAdmission notin {DiskWorkerError.Uninitialized,
      DiskWorkerError.None}: return true
  if services.maintenanceCompletion.kind != DiskCompletionKind.Maintained: return false
  let outcome = services.maintenanceCompletion.maintenanceValue
  if outcome.error != DiskChainError.None: return true
  outcome.value.cleanup != FileError.None

func diskMaintenanceCompletion*(services: Services): DiskPublicationCompletion {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Retain the exact completed or queued-not-executed maintenance receipt across joined shutdown.
  services.maintenanceCompletion

func diskMaintenancePreparation*(services: Services): DiskChainResult[
    PreparedDiskMaintenance] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Preserve a refused host context/root preparation without fabricating a worker result.
  services.maintenanceStage

func diskMaintenanceAdmissionError*(services: Services): DiskWorkerError =
  ## A scalar actual worker admission reason is observable without touching leased graphs.
  services.maintenanceAdmission

proc stageDiskMaintenance(services: var Services): bool =
  ## Retire all temporary canonical/context aliases in this activation before outer worker submission.
  services.rpcLease = services.rpc.pauseChain()
  if services.chainRpc and services.rpcLease == nil: return false
  let staged = prepareDiskMaintenance(services.disk, services.canonical, services.diskId,
    services.diskLimits.contextBytes)
  if staged.error != DiskChainError.None:
    services.maintenanceStage = staged
    services.diskFaulted = true
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    return false
  services.maintenanceStage = default(DiskChainResult[PreparedDiskMaintenance])
  services.maintenanceCompletion = default(DiskPublicationCompletion)
  services.diskMaintenance = staged.value
  true

proc beginDiskMaintenance*(services: var Services): bool =
  ## Explicit host maintenance shares publication exclusion, RPC pause and one fixed-address native slot.
  if not services.started or not services.diskEnabled or not services.diskManaged or
      services.diskFaulted:
    return false
  if services.proofing or services.preparing or services.publishing: return false
  if services.rpc.chainPaused: return false
  if not services.stageDiskMaintenance(): return false
  let admitted = services.diskWorker.submitMaintenance(services.disk, services.diskMaintenance)
  services.maintenanceAdmission = admitted.error
  if admitted.error != DiskWorkerError.None:
    services.diskMaintenance = default(PreparedDiskMaintenance)
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    services.diskFaulted = true
    return false
  services.diskTicket = admitted.value
  services.diskOperation = ServiceDiskOperation.Maintenance
  services.publishing = true # Every existing canonical/RPC/checkpoint gate now covers the maintenance lease too.
  true

func diskRetirementCompletion*(services: Services): DiskPublicationCompletion {.requires: not services.publishing.} =
  ## Preserve actual cleanup success, Busy or failure after collection or joined shutdown; core publication receipts remain separate.
  services.retirementCompletion

proc beginDiskRetirement*(services: var Services): bool =
  ## Borrow no graph until publication/preparation/proof exclusion and the RPC pause have all succeeded.
  if not services.started or not services.diskEnabled or not services.diskPaged or
      services.diskFaulted: return false
  if services.proofing or services.preparing or services.publishing or
      services.rpc.chainPaused: return false
  if not services.disk.pagedRetirementPending: return false
  services.rpcLease = services.rpc.pauseChain()
  if services.chainRpc and services.rpcLease == nil: return false
  let prepared = preparePagedRetirement(services.disk)
  if prepared.error != DiskStoreError.None:
    services.diskFaulted = true
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    return false
  services.diskRetirement = prepared.value
  services.retirementCompletion = default(DiskPublicationCompletion)
  let admitted = services.diskWorker.submitRetirement(services.disk, services.diskRetirement)
  if admitted.error != DiskWorkerError.None:
    services.diskRetirement = default(PreparedPagedRetirement)
    services.diskFaulted = true
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil
    return false
  services.diskTicket = admitted.value
  services.diskOperation = ServiceDiskOperation.Retirement
  services.publishing = true # Existing gates cover the same one-slot graph lease through collect or joined close.
  true

proc retirementDue(services: Services): bool =
  ## One retry per second bounds repeated foreign-reader pin checks; no wall-clock/protocol time enters state semantics.
  not services.retirementDelayed or (getMonoTime()-services.retirementAttempt).inMilliseconds >= 1000

proc rpcProofLimits(): ProofQueryLimits =
  ## Bound complete-map generation, proof verification and detached wire copies.
  ## These are independent local admission ceilings. The hash estimate limits
  ## admitted work and carries no wall-clock promise.
  ProofQueryLimits(map: StateTrieLimits(items: ElementLimit(65536), nodes: TrieNodeLimit(131071),
      perValue: ByteLimit(1048576), totalValueBytes: ByteLimit(8388608)),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(MaxRpcProofBytes)),
    aggregate: StateProofBatchLimits(items: ElementLimit(MaxRpcProofKeys), nodes: ElementLimit(
        3984), valueBytes: ByteLimit(MaxRpcProofBytes)),
    view: ProofViewLimits(items: ElementLimit(MaxRpcProofKeys), valueBytes: ByteLimit(
        MaxRpcProofBytes)),
    wireBytes: ByteLimit(MaxRpcProofBytes), hashes: ProofHashLimit(4000000))

proc beginRpcProof(services: var Services) =
  ## Claim detached RPC proof intent after RPC/UI request views retire.
  ## The admission stages the exact block and starts the bounded worker only
  ## after temporary graph aliases retire. Keep the routing ticket separate
  ## from that worker lease. Refusals become terminal errors, and disconnect
  ## can discard delivery while the worker still requires collection.
  let dispatch = services.rpc.takeStateProofRequest()
  if not dispatch.valid: return
  services.rpcProof = dispatch
  try:
    let admitted = services.beginStateProof(dispatch.proofRequest.blockHash,
      dispatch.proofRequest.plan, rpcProofLimits())
    if admitted.error == StateProofAdmissionError.None:
      services.rpcProofTicket = admitted.value # After native submission, touch only detached/host-only selectors.
    else:
      var reason = $admitted.error
      if admitted.error == StateProofAdmissionError.QueryFailure:
        reason.add(": " & $admitted.queryError) # Preserve selection/budget refusals without exposing payloads.
      elif admitted.error == StateProofAdmissionError.WorkerFailure:
        reason.add(": " & $admitted.workerError) # Native refusal remains distinct from unavailable selection.
      discard services.rpc.finishStateProof(dispatch, default(StateRoot), [],
        "State proof admission unavailable: " & reason)
      services.rpcProof = default(RpcProofDispatch)
  except:
    services.stopStateProofs() # Startup failure or unexpected raised refusal cannot abandon a borrower.
    discard services.rpc.finishStateProof(dispatch, default(StateRoot), [], "State proof worker unavailable")
    services.rpcProof = default(RpcProofDispatch)

proc finishRpcProof(services: var Services, completion: ProofWorkerCompletion) =
  ## Only detached collected output is read after the exact worker lease has reopened RPC.
  var failure = "State proof cancelled"
  if completion.kind == ProofWorkerCompletionKind.Completed:
    let outcome = completion.value
    failure = "State proof unavailable: " & $outcome.error
    if outcome.error == ProofQueryError.None:
      let response = outcome.value
      let wire = response.bytes(ByteLimit(MaxRpcProofBytes))
      let expected = services.rpcProof.proofRequest.blockHash
      let matching = array[32, byte](response.blockHash) == array[32, byte](expected)
      if matching and wire.error == ProofQueryError.None:
        discard services.rpc.finishStateProof(services.rpcProof, response.stateRoot, wire.value)
        failure = "" # Full detached success has already queued exactly one terminal result.
      else:
        failure = "State proof identity or output budget mismatch"
  if failure.len > 0:
    discard services.rpc.finishStateProof(services.rpcProof, default(StateRoot), [], failure)
  services.rpcProof = default(RpcProofDispatch)
  services.rpcProofTicket = default(ProofWorkerTicket)

proc tickMcp(services: var Services, peers: uint32) =
  ## No graph copy or retirement occurs while an existing canonical lease is held.
  if not services.mcp.enabled: return
  if services.proofing or services.preparing or services.publishing or services.rpc.chainPaused or
      services.light.busy:
    var context = default(mcp_protocol.QueryContext)
    context.busy = true
    services.mcp.tick(context)
    return # Busy replies retain only detached JSON and do not delay worker collection.
  var info = services.mcpInfo
  info.peers = peers
  if services.light.active:
    info.light = services.light.queryMetadata # Already detached headers never alias the partial proof graph.
  elif services.canonical.chainView.retainedCount > 0:
    info.chain = services.canonical.chainView # One synchronous selected view retires before any worker starts.
  services.mcp.tick(mcp_protocol.QueryContext(info: info))

proc tick*(services: var Services, peers: uint32) =
  ## Attempt one pending adoption between native callbacks; independent management remains available during leases.
  services.tickMcp(peers) # Context aliases retire on return, before publication or worker admission below.
  if services.light.active:
    services.management.tick() # Static management observations retain no canonical proof graph.
    services.light.tick(peers)
    services.ui.tick() # Independent asset/connection work never touches the light actor source.
    return
  services.management.tick() # Startup metadata and OS observations never borrow the canonical/database graph.
  if services.rpcProof.valid and services.proofing:
    if services.stateProofPhase != ProofWorkerPhase.Done:
      services.ui.tick()
      return # Poll synchronized scalars only while native generation owns the canonical graph.
    let ticket = services.rpcProofTicket # Retain the small host-only identity before mutable collection.
    let completion = services.collectStateProof(ticket)
    services.finishRpcProof(completion) # Exact collection releases the lease before response serialization.
  if services.proofing or services.preparing:
    services.ui.tick()
    return # Never create RPC contexts or canonical ARC aliases while the worker owns its lease.
  if services.publishing:
    if services.diskWorker.phase != DiskWorkerPhase.Done:
      services.ui.tick()
      return # Poll only scalar worker state while RPC/canonical graphs remain borrowed.
    services.finishDiskPublication(services.diskWorker.collect(services.diskTicket))
  if services.diskEnabled:
    if services.diskPaged and not services.diskResume and not services.diskFaulted and
        services.disk.pagedRetirementPending:
      # Retire the authenticated predecessor before staging the next candidate; pending handoffs retain their bounded slot.
      if services.retirementDue(): discard services.beginDiskRetirement()
      services.ui.tick()
      return
    if services.currentAdoption.phase == CurrentHandoffPhase.Pending and
        services.stageCurrentDiskPublication():
      let admitted = services.diskWorker.submit(services.disk, services.currentDiskPublication)
      services.currentDiskAdmission = admitted.error
      if admitted.error == DiskWorkerError.None:
        services.diskTicket = admitted.value
        services.diskOperation = ServiceDiskOperation.CurrentPublication
        services.publishing = true
        services.ui.tick()
        return # Only scalar polling/independent UI work may follow a successful native borrow.
      services.currentDiskPublication = default(PreparedCurrentDiskPublication)
      services.currentAdoption.refusePublication(CurrentHandoffError.DurabilityRefused)
      services.diskFaulted = true
      discard services.rpc.resumeChain(services.rpcLease)
      services.rpcLease = nil # A refused worker borrowed no graph and produced no IO receipt.
    if services.adoption.stage == AccumulationHandoffStage.Pending and
        services.stageDiskPublication():
      let admitted = services.diskWorker.submit(services.disk, services.diskPublication)
      assert admitted.error == DiskWorkerError.None, "private idle disk worker admission"
      services.diskTicket = admitted.value
      services.diskOperation = ServiceDiskOperation.Publication
      services.publishing = true
      services.ui.tick()
      return # No managed canonical/source alias may be touched or retired after successful admission.
    if (services.adoption.stage == AccumulationHandoffStage.Finished or
        services.currentAdoption.phase == CurrentHandoffPhase.Finished) and
        services.maintenanceDue() and services.beginDiskMaintenance():
      services.ui.tick()
      return # No canonical/RPC graph aliases are touched until scalar polling observes the maintenance completion.
  elif services.currentAdoption.phase == CurrentHandoffPhase.Pending:
    if services.chainRpc:
      services.currentAdoption.process(services.canonical,
          services.rpc) # Exact RPC history is mandatory; no canonical fallback.
    else:
      services.currentAdoption.process(services.canonical) # Installation consumes only the already captured current update.
  elif services.chainRpc:
    services.adoption.process(services.canonical, services.rpc) # Enabled listener failure remains a completed refusal.
  else:
    services.adoption.process(services.canonical) # No listener is needed for explicit independent adoption.
  services.rpc.tick(peers)
  services.ui.tick()
  services.beginRpcProof() # Native generation starts outside transport callbacks and after all host tick aliases retire.

func nodeProtocol*(services: Services): string =
  ## Detached configured-genesis identity is available independently of workers or later restored heads.
  if services.started and not services.light.active: services.networkBase else: ""

proc networkProtocol*(services: Services, options: Options): string =
  ## The captured configured genesis remains independent of mutable canonical/checkpoint progress.
  if not services.started or not options.valid: return ""
  selectChainAlpn(services.networkBase, options.networkAlpnOverride, options.chainPath.len > 0)

proc configureTelemetry*(services: var Services, options: Options, certificate: string,
    port: uint16, ipv6: bool): bool {.raises.} =
  ## Register the actual transport identity/address after binding, using the captured chain bytes.
  logCertificateIdentity(options.logWriter, certificate)
  let configured = setupTelemetry(services.telemetry, options, certificate, port, ipv6,
      services.chainText)
  if services.light.active and configured: services.chainText = "" # Telemetry registration owns only bounded metadata before the peer loop starts.
  if options.telemetryEnabled:
    log(options.logWriter, LogTarget.Telemetry, LogLevel.Info, "Telemetry configured=" & $configured)
  configured

proc stageCheckpointVerification*(services: var Services, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Independent fixed trust and explicit decode budgets require no canonical alias, so verification may run during preparation leases.
  services.checkpointExport.stageVerification(expected, limits, limit)

proc freezeCollectedSupplied*(services: Services, plan: CollectedSuppliedPlan,
    declarations: openArray[StateService], limits: SuppliedServicesLimits): FrozenSuppliedResult[
        FrozenSuppliedInput] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Capture source aliases only after every managed native graph lease has ended.
  frozen_supplied.freezeCollectedSupplied(services.canonical, plan, declarations, limits)

proc executeFrozenSupplied*(services: Services, source: FrozenSuppliedInput): FrozenSuppliedResult[
    CurrentLogicalState] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Frozen input does not bypass canonical staleness or native exclusion checks.
  frozen_supplied.executeFrozenSupplied(services.canonical, source)

proc planCollectedLogical*(services: Services, completion: PreparationCompletion,
    source: SelectedLogicalParent, limits: CollectedLogicalLimits): CollectedLogicalPlanResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Retaining prepared source graphs requires every existing native lease to have ended.
  collected_logical.planCollectedLogical(services.canonical, completion, source, limits)

proc planCollectedLogical*(services: Services, completion: PreparationCompletion,
    source: CurrentLogicalState, limits: CollectedLogicalLimits): CollectedLogicalPlanResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Retaining prepared source graphs requires every existing native lease to have ended.
  collected_logical.planCollectedLogical(services.canonical, completion, source, limits)

proc executeCollectedLogical*(services: Services, plan: CollectedLogicalPlan): CollectedLogicalResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Retry cannot bypass native exclusion or the frozen update's exact canonical-parent check.
  collected_logical.executeCollectedLogical(services.canonical, plan)

proc planLogicalServiceProof*(services: Services, source: CurrentLogicalState,
    service: ServiceIndex, limits: LogicalServiceProofLimits): LogicalServiceProofResult[
        LogicalServiceProof] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Namespace selection reads retained source aliases only outside the managed native graph lease.
  logical_service_proof.planLogicalServiceProof(source, service, limits)

proc planLogicalExport*(services: Services, source: CurrentLogicalState,
    limits: SuppliedServicesLimits): LogicalExportResult[LogicalExportPlan] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Complete export admission reads retained original source graphs only outside managed native leases.
  logical_export.planLogicalExport(source, limits)

proc executeLogicalExport*(services: Services, plan: LogicalExportPlan): LogicalExportResult[seq[
    StateService]] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Detached copying remains excluded through actual collection/join of every native graph borrower.
  logical_export.executeLogicalExport(plan)

proc importLogicalCheckpoint*(services: Services, source: CurrentLogicalState,
    wire: openArray[byte], limits: StateStoreLimits,
    wireLimit: ByteLimit): LogicalCheckpointImportResult[ImportedLogicalCheckpoint] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Original logical/root aliases remain outside every managed native lease until actual collection or join.
  logical_checkpoint_import.importLogicalCheckpoint(source, wire, limits, wireLimit)

proc auditLogicalCodeAvailability*(services: Services, source: CurrentLogicalState,
    limits: CodeAvailabilityLimits): LogicalCodeResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Original logical/current payload aliases remain excluded until actual matching collection or joined shutdown.
  logical_code.auditLogicalCodeAvailability(source, limits)

proc planFullLogicalProof*(services: Services, source: CurrentLogicalState,
    limits: FullLogicalProofLimits): FullLogicalProofResult[FullLogicalProofPlan] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Whole-map enumeration and selector ownership remain excluded until actual managed collection/join.
  full_logical_proof.planFullLogicalProof(source, limits)

proc planLogicalProofPages*(services: Services, source: CurrentLogicalState,
    fullLimits: FullLogicalProofLimits, pageLimits: LogicalProofPageLimits): LogicalProofPageResult[
        LogicalProofPages] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Complete original-source traversal and all retained page-plan aliases remain outside managed native graph leases until matching collection/join.
  paged_logical_proof.planLogicalProofPages(source, fullLimits, pageLimits)

proc planLogicalCodeProof*(services: Services, source: CurrentLogicalState, service: ServiceIndex,
    limits: LogicalCodeProofLimits): LogicalCodeProofResult[LogicalCodeProof] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Original current inventory/content and selector aliases remain excluded until actual matching native collection or joined close.
  logical_code_proof.planLogicalCodeProof(source, service, limits)

proc planLogicalSourceExport*(services: Services, source: CurrentLogicalState,
    limits: LogicalSourceExportLimits): LogicalSourceExportResult[
        LogicalSourceExportPlan] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Original raw-key graph traversal remains excluded until actual matching native collection or joined shutdown.
  logical_source_export.planLogicalSourceExport(source, limits)

proc executeLogicalSourceExport*(services: Services,
    plan: LogicalSourceExportPlan): LogicalSourceExportResult[string] {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Frozen declaration aliases and raw keys remain outside every active managed graph lease.
  logical_source_export.executeLogicalSourceExport(plan)

proc continueCurrentStorage*(services: Services, parent: SelectedLogicalParent,
    update: PreparedCurrentChainUpdate, limits: StorageContinuationLimits): StorageContinuationResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Keep original parent, producer history and copied declarations outside every managed graph lease until actual collection/join.
  logical_continuation.continueCurrentStorage(parent, update, limits)

proc continueCurrentStorage*(services: Services, prior: CurrentLogicalState,
    update: PreparedCurrentChainUpdate, limits: StorageContinuationLimits): StorageContinuationResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Continue only on the stable owner after matching collection or joined shutdown retires all native graph borrowing.
  logical_continuation.continueCurrentStorage(prior, update, limits)

proc continueCurrentNamespaces*(services: Services, parent: SelectedLogicalParent,
    update: PreparedCurrentChainUpdate, limits: LogicalContinuationLimits): LogicalContinuationResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Read original identities and producer storage/request history only on the stable host after all matching collection/join boundaries.
  logical_continuation.continueCurrentNamespaces(parent, update, limits)

proc continueCurrentNamespaces*(services: Services, prior: CurrentLogicalState,
    update: PreparedCurrentChainUpdate, limits: LogicalContinuationLimits): LogicalContinuationResult {.requires:
    not (services.proofing or services.preparing or services.publishing).} =
  ## Current provenance and detached reconstruction remain excluded from every native graph lease until actual retirement.
  logical_continuation.continueCurrentNamespaces(prior, update, limits)

func startupBlockAnchor*(services: Services): StartupBlockAnchor =
  ## Read fixed startup metadata without borrowing canonical graphs, including during worker leases.
  if services.started: services.startupAnchor else: default(StartupBlockAnchor)
