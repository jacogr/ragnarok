# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One reusable fixed-address worker owns proof queries, network reads, response verification or ingestion under an exclusive request ARC graph lease.
## Plain ARC requires all external selected-state aliases to remain untouched through cancellation and Done.
## One host thread serializes controls; the worker stays at its final address until joined close.

import std/[assertions, locks, rawthreads]
import ./query as proof_query
import ./network_read
import ./ticket_verification
import ./ticket_production
import ./work_submission
import ./assurance_storage
import ./assurance_acquisition
import ../../jamnp-s/assurance_store
import ../../jamnp-s/ticket_validation
import ./read_validation as verification_job
import ../../jamnp-s/read_validation as read_verification
import ../../jamnp-s/read_stream
import ../light/proof_import as light_proof_import

type
  ProofWorkerPhase* {.pure.} = enum ## Done still occupies capacity and retains the exclusive graph lease.
    Idle, Queued, Running, Done
  ProofWorkerError* {.pure.} = enum ## Admission failures retain no ticket or borrowed graph.
    Uninitialized, None, Closed, Busy, NotReady, Exhausted
  ProofWorkerOperation {.pure.} = enum ## One bounded CPU slot owns proof production, network reads, response verification or current-root ingestion.
    Query, Ingestion, NetworkRead, ReadVerification, TicketVerification, TicketProduction,
      WorkSubmission, AssuranceStorage, AssuranceAcquisition
  ProofWorkerIdentity = ref object ## Host-only namespace; the worker never accesses this ARC reference.
    marker: uint8
  ProofWorkerTicket* = object ## Retained namespace and nonwrapping generation prevent foreign or stale retirement.
    owner: nil ProofWorkerIdentity
    generation: uint64
  ProofWorkerAdmission* = object ## Successful admission alone exposes its lease ticket.
    case status: ProofWorkerError
    of None: ticket: ProofWorkerTicket
    else: discard                # Refusals retain no authority.
  ProofWorkerCompletionKind* {.pure.} = enum ## Cancellation never exposes a proof success prefix.
    Uninitialized, Completed, Cancelled, Imported, ReadCompleted, ReadVerified, TicketVerified,
      TicketProduced, WorkSubmitted, AssuranceCompleted, AssuranceAcquired
  ProofWorkerCompletion* = object ## Only a collected uncancelled completion exposes its typed query outcome.
    case status: ProofWorkerCompletionKind
    of Completed: response: ProofQueryResult[ProofResponse]
    of Imported: ingestion: LightImportResult[ImportedLightProofs]
    of ReadCompleted: readResponse: ReadResult[ReadReply]
    of ReadVerified: verifiedResponse: ReadVerificationResult[CheckedReadReply]
    of WorkSubmitted: workResponse: WorkJobResult
    of AssuranceCompleted: assuranceResponse: AssuranceStoreResult[bool]
    of AssuranceAcquired: acquisitionResponse: AssuranceAcquisitionResult[AssuranceAcquisitionInfo]
    of TicketVerified, TicketProduced: ticketResponse: NetworkTicketResult[CheckedNetworkTicket]
    else: discard # Defaults and cancellation have no response payload.
  StateProofWorker* = object ## Must remain at one address from start through explicit joined close.
    lock: Lock
    changed: Cond
    thread: RawThread
    started, stopping, cancelled: bool
    phase: ProofWorkerPhase
    next: uint64
    identity: nil ProofWorkerIdentity
    operation: ProofWorkerOperation
    importJob: LightProofImport
    importOutcome: LightImportResult[ImportedLightProofs]
    ticketJob: TicketVerificationJob
    productionJob: TicketProductionJob
    workJob: WorkSubmissionJob
    acquisitionJob: AssuranceAcquisitionJob
    acquisitionOutcome: AssuranceAcquisitionResult[AssuranceAcquisitionInfo]
    assuranceJob: AssuranceStorageJob
    assuranceOutcome: AssuranceStoreResult[bool]
    workOutcome: WorkJobResult
    ticketOutcome: NetworkTicketResult[CheckedNetworkTicket]
    verifyJob: ReadVerificationJob
    verifyOutcome: ReadVerificationResult[CheckedReadReply]
    readJob: NetworkReadJob
    readOutcome: ReadResult[ReadReply]
    query: ProofQuery
    outcome: ProofQueryResult[ProofResponse]

proc `=wasMoved`*(worker: var StateProofWorker) {.nodestroy, inline,
    requires: not worker.started.} =
  ## Moving a live worker would invalidate the address borrowed by its native thread.
  `=wasMoved`(worker.ticketJob)
  `=wasMoved`(worker.productionJob)
  `=wasMoved`(worker.workJob)
  `=wasMoved`(worker.workOutcome)
  `=wasMoved`(worker.acquisitionJob)
  `=wasMoved`(worker.acquisitionOutcome)
  `=wasMoved`(worker.assuranceJob)
  `=wasMoved`(worker.assuranceOutcome)
  `=wasMoved`(worker.ticketOutcome)
  `=wasMoved`(worker.verifyJob)
  `=wasMoved`(worker.verifyOutcome)
  `=wasMoved`(worker.readJob)
  `=wasMoved`(worker.readOutcome)
  `=wasMoved`(worker.importJob)
  `=wasMoved`(worker.importOutcome)
  `=wasMoved`(worker.query)
  `=wasMoved`(worker.outcome)
  `=wasMoved`(worker.identity)

proc `=copy`*(destination: var StateProofWorker, source: StateProofWorker) {.error.}
  ## A native thread and its borrowed stack addresses have exactly one owner.

proc `=dup`*(source: StateProofWorker): StateProofWorker {.error.}
  ## Composite owners must reject duplication explicitly.

proc requireClosed(worker: StateProofWorker) {.requires: not worker.started.} =
  ## Destruction cannot silently abandon a thread borrowing host memory.
  discard

proc `=destroy`*(worker: StateProofWorker) =
  ## Host cleanup joins explicitly while all borrowed inputs and aliases still exist.
  requireClosed(worker)
  `=destroy`(worker.ticketJob)
  `=destroy`(worker.productionJob)
  `=destroy`(worker.workJob)
  `=destroy`(worker.workOutcome)
  `=destroy`(worker.acquisitionJob)
  `=destroy`(worker.acquisitionOutcome)
  `=destroy`(worker.assuranceJob)
  `=destroy`(worker.assuranceOutcome)
  `=destroy`(worker.ticketOutcome)
  `=destroy`(worker.verifyJob)
  `=destroy`(worker.verifyOutcome)
  `=destroy`(worker.readJob)
  `=destroy`(worker.readOutcome)
  `=destroy`(worker.importJob)
  `=destroy`(worker.importOutcome)
  `=destroy`(worker.query)
  `=destroy`(worker.outcome)
  `=destroy`(worker.identity)

func error*(admission: ProofWorkerAdmission): ProofWorkerError =
  ## Observe admission without granting ticket authority.
  admission.status

func value*(admission: ProofWorkerAdmission): ProofWorkerTicket {.inline,
    requires: admission.status == ProofWorkerError.None.} =
  ## Only admitted work grants a ticket.
  admission.ticket

func kind*(completion: ProofWorkerCompletion): ProofWorkerCompletionKind =
  ## Observe default/cancelled results without extracting a response.
  completion.status

func value*(completion: ProofWorkerCompletion): ProofQueryResult[ProofResponse] {.inline,
    requires: completion.status == ProofWorkerCompletionKind.Completed.} =
  ## The query's own guarded result retains all typed failures and finalized success.
  completion.response

func importedValue*(completion: ProofWorkerCompletion): LightImportResult[
    ImportedLightProofs] {.inline, requires: completion.status ==
        ProofWorkerCompletionKind.Imported.} =
  ## Only complete uncancelled ingestion exposes its genuinely verified checkpoint-bound batch.
  completion.ingestion

func readValue*(completion: ProofWorkerCompletion): ReadResult[ReadReply] {.requires:
    completion.status == ProofWorkerCompletionKind.ReadCompleted.} =
  ## Network replies remain distinct from RPC proof responses and verified light ingestion.
  completion.readResponse

func verifiedReadValue*(completion: ProofWorkerCompletion): ReadVerificationResult[
    CheckedReadReply] {.requires: completion.status == ProofWorkerCompletionKind.ReadVerified.} =
  ## Complete verification is distinct from raw network replies and ordinary RPC proof production.
  completion.verifiedResponse

func verifiedTicketValue*(completion: ProofWorkerCompletion): NetworkTicketResult[
    CheckedNetworkTicket] {.requires: completion.status ==
    ProofWorkerCompletionKind.TicketVerified.} =
  ## Only exact uncancelled ticket-proof collection exposes the actual complete verifier outcome.
  completion.ticketResponse

func producedTicketValue*(completion: ProofWorkerCompletion): NetworkTicketResult[
    CheckedNetworkTicket] {.requires: completion.status ==
    ProofWorkerCompletionKind.TicketProduced.} =
  ## Exact uncancelled production exposes a whole genuine signing/verification outcome, never a key or partial proof.
  completion.ticketResponse

func workSubmissionValue*(completion: ProofWorkerCompletion): WorkJobResult {.requires:
    completion.status == ProofWorkerCompletionKind.WorkSubmitted.} =
  ## Only exact uncancelled collection transfers the complete work turn; source-bearing payloads remain behind the host graph gate.
  completion.workResponse

func assuranceStorageValue*(completion: ProofWorkerCompletion): AssuranceStoreResult[
    bool] {.requires: completion.status == ProofWorkerCompletionKind.AssuranceCompleted.} =
  ## Exact uncancelled collection alone exposes the completed namespace I/O outcome.
  completion.assuranceResponse
func assuranceAcquisitionValue*(completion: ProofWorkerCompletion): AssuranceAcquisitionResult[
    AssuranceAcquisitionInfo] {.requires: completion.status ==
    ProofWorkerCompletionKind.AssuranceAcquired.} =
  ## Only exact uncancelled collection exposes persisted progress; no completion grants a possession bit or signing capability.
  completion.acquisitionResponse
proc stopAssuranceScan(context: nil pointer): bool {.nimcall, raises: [].} =
  ## Execution holds no worker mutex; close/cancel release it before waiting so a scan can observe the stop without deadlocking.
  let worker = cast[ptr StateProofWorker](context)
  if worker == nil: return true
  acquire(worker.lock)
  result = worker.cancelled or worker.stopping
  release(worker.lock)
proc execute(worker: ptr StateProofWorker) =
  ## All selected-state aliases and generation scratch retire before run publishes Done.
  case worker.operation
  of ProofWorkerOperation.AssuranceAcquisition:
    # Canonical/frame/native-owner aliases remain exclusively borrowed until exact collection or joined close.
    worker.acquisitionOutcome = executeAssuranceAcquisition(worker.acquisitionJob,
      assuranceScanControl(stopAssuranceScan, cast[pointer](worker)))
  of ProofWorkerOperation.AssuranceStorage:
    # Store/path aliases stay private through Done; cancellation checks borrow this worker only during execution.
    worker.assuranceOutcome = executeAssuranceStorage(worker.assuranceJob,
      assuranceScanControl(stopAssuranceScan, cast[pointer](worker)))
  of ProofWorkerOperation.WorkSubmission:
    worker.workOutcome = executeWorkSubmission(worker.workJob) # Original state aliases retire before Done.
  of ProofWorkerOperation.TicketProduction:
    worker.ticketOutcome = executeTicketProduction(
        worker.productionJob) # Private signer/source aliases retire before Done.
  of ProofWorkerOperation.TicketVerification:
    worker.ticketOutcome = executeTicketVerification(
        worker.ticketJob) # Only detached immutable source/proof facts cross this CPU boundary.
  of ProofWorkerOperation.ReadVerification:
    worker.verifyOutcome = executeReadVerification(
        worker.verifyJob) # Fresh immutable input contains no selected-state aliases.
  of ProofWorkerOperation.NetworkRead:
    worker.readOutcome = executeNetworkRead(worker.readJob) # Only frozen wire survives the worker activation.
  of ProofWorkerOperation.Query:
    worker.outcome = executeProofQuery(worker.query) # Full/partial query sources retain the same bounded response contract.
  of ProofWorkerOperation.Ingestion:
    worker.importOutcome = executeLightProofImport(
        worker.importJob) # No native storage mutation or canonical adoption occurs on this CPU thread.

proc run(raw: pointer) =
  ## A single condition-driven thread performs no service, transport or canonical-publication work.
  let worker = cast[ptr StateProofWorker](raw)
  acquire(worker.lock)
  while true:
    while worker.phase != ProofWorkerPhase.Queued and not worker.stopping:
      wait(worker.changed, worker.lock) # Recheck after spurious wakeups; never poll for jobs.
    if worker.stopping:
      release(worker.lock)
      return # Shutdown ends all borrowing before the host clears retained owners.
    worker.phase = ProofWorkerPhase.Running
    let skip = worker.cancelled
    release(worker.lock)
    if not skip:
      execute(worker) # The host cannot touch any alias of the exclusively borrowed ARC graph.
    acquire(worker.lock)
    worker.phase = ProofWorkerPhase.Done # execute's entire activation has already retired.

proc start*(worker: var StateProofWorker): bool {.raises.} =
  ## Initialize one worker at its final address; preserve generations across close/restart.
  if worker.started: return false # Reinitialization cannot replace live locks or thread state.
  initLock(worker.lock)
  initCond(worker.changed)
  worker.stopping = false
  worker.phase = ProofWorkerPhase.Idle
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.operation = ProofWorkerOperation.Query
  worker.cancelled = false
  try:
    worker.thread.create(run, addr worker)
  except:
    deinitCond(worker.changed)
    deinitLock(worker.lock)
    raise # Failed creation leaves no running borrower or initialized synchronization owner.
  worker.identity = ProofWorkerIdentity(marker: 1) # Host-only ticket identity is fresh even when an address is reused.
  worker.started = true
  true

proc phase*(worker: var StateProofWorker): ProofWorkerPhase =
  ## Scalar-only polling never copies a leased ARC owner.
  if not worker.started: return ProofWorkerPhase.Idle # Defaults/closed workers own no slot.
  acquire(worker.lock)
  result = worker.phase
  release(worker.lock)

proc submit*(worker: var StateProofWorker, query: var ProofQuery): ProofWorkerAdmission =
  ## Transfer one query; every external selected-state alias remains untouched until collect/join.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle:
    return ProofWorkerAdmission(status: ProofWorkerError.Busy)
  if not query.valid:
    return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64):
    return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.operation = ProofWorkerOperation.Query
  worker.query = move(query)
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None,
    ticket: ProofWorkerTicket(owner: worker.identity, generation: worker.next))

proc submit*(worker: var StateProofWorker, request: var LightProofImport): ProofWorkerAdmission =
  ## Move privately copied wire into one bounded CPU slot; all request aliases remain frozen through cancellation and Done.
  if not worker.started: return ProofWorkerAdmission(
      status: ProofWorkerError.Closed) # No running borrower can own a request yet.
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle: return ProofWorkerAdmission(
      status: ProofWorkerError.Busy) # Do not inspect any already leased graph before capacity refusal.
  if not request.valid: return ProofWorkerAdmission(
      status: ProofWorkerError.NotReady) # Defaults never become an empty verified import.
  if worker.next == high(uint64): return ProofWorkerAdmission(
      status: ProofWorkerError.Exhausted) # Ticket generations never wrap.
  inc worker.next
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.importJob = move(request)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.operation = ProofWorkerOperation.Ingestion
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None,
    ticket: ProofWorkerTicket(owner: worker.identity, generation: worker.next))

proc submit*(worker: var StateProofWorker, request: var NetworkReadJob): ProofWorkerAdmission =
  ## Transfer one network read into the existing single CPU slot without adding any native thread.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle: return ProofWorkerAdmission(
      status: ProofWorkerError.Busy)
  if not request.valid: return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64): return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.readJob = move(request)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.operation = ProofWorkerOperation.NetworkRead
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None,
    ticket: ProofWorkerTicket(owner: worker.identity, generation: worker.next))

proc submit*(worker: var StateProofWorker, request: var ReadVerificationJob): ProofWorkerAdmission =
  ## Move a fresh bounded verification input into the same fixed-address CPU slot.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle: return ProofWorkerAdmission(
      status: ProofWorkerError.Busy)
  if not request.valid: return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64): return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = move(request)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.operation = ProofWorkerOperation.ReadVerification
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None,
    ticket: ProofWorkerTicket(owner: worker.identity, generation: worker.next))

proc submit*(worker: var StateProofWorker, request: var TicketVerificationJob): ProofWorkerAdmission =
  ## Move one detached ticket-verification capability into the same exact bounded CPU slot.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle: return ProofWorkerAdmission(
      status: ProofWorkerError.Busy)
  if not request.valid: return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64): return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketJob = move(request)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.operation = ProofWorkerOperation.TicketVerification
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None, ticket: ProofWorkerTicket(
      owner: worker.identity, generation: worker.next))

proc submit*(worker: var StateProofWorker, request: var TicketProductionJob): ProofWorkerAdmission =
  ## Move one detached private signing capability into the same exact bounded CPU slot.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle: return ProofWorkerAdmission(
      status: ProofWorkerError.Busy)
  if not request.valid: return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64): return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.productionJob = move(request)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.operation = ProofWorkerOperation.TicketProduction
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None, ticket: ProofWorkerTicket(
      owner: worker.identity, generation: worker.next))

proc submit*(worker: var StateProofWorker, request: var WorkSubmissionJob): ProofWorkerAdmission =
  ## Move one immutable work-submission capability into the same exact bounded CPU slot.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle: return ProofWorkerAdmission(
      status: ProofWorkerError.Busy)
  if not request.valid: return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64): return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.workJob = move(request)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.operation = ProofWorkerOperation.WorkSubmission
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None, ticket: ProofWorkerTicket(
      owner: worker.identity, generation: worker.next))

proc submit*(worker: var StateProofWorker, request: var AssuranceStorageJob): ProofWorkerAdmission =
  ## Move one closed assurance I/O capability into the same exact bounded lease; the store address remains frozen through collection/join.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle: return ProofWorkerAdmission(
      status: ProofWorkerError.Busy)
  if not request.valid: return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64): return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.assuranceJob = move(request)
  worker.operation = ProofWorkerOperation.AssuranceStorage
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None, ticket: ProofWorkerTicket(
      owner: worker.identity, generation: worker.next))

proc submit*(worker: var StateProofWorker, request: var AssuranceAcquisitionJob): ProofWorkerAdmission =
  ## Move one canonical acquired-shard retention job into the existing bounded lease; native namespace and source aliases stay frozen through collection/join.
  if not worker.started: return ProofWorkerAdmission(status: ProofWorkerError.Closed)
  acquire(worker.lock)
  defer: release(worker.lock)
  if worker.phase != ProofWorkerPhase.Idle: return ProofWorkerAdmission(
      status: ProofWorkerError.Busy)
  if not request.valid: return ProofWorkerAdmission(status: ProofWorkerError.NotReady)
  if worker.next == high(uint64): return ProofWorkerAdmission(status: ProofWorkerError.Exhausted)
  inc worker.next
  worker.query = default(ProofQuery)
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.acquisitionJob = move(request)
  worker.operation = ProofWorkerOperation.AssuranceAcquisition
  worker.cancelled = false
  worker.phase = ProofWorkerPhase.Queued
  signal(worker.changed)
  ProofWorkerAdmission(status: ProofWorkerError.None, ticket: ProofWorkerTicket(
      owner: worker.identity, generation: worker.next))

func matches(worker: var StateProofWorker, ticket: ProofWorkerTicket): bool =
  ## Called under the lock; generation zero and idle slots never authorize retirement.
  ticket.owner == worker.identity and ticket.generation != 0 and ticket.generation ==
      worker.next and
    worker.phase != ProofWorkerPhase.Idle


proc cancel*(worker: var StateProofWorker, ticket: ProofWorkerTicket): bool =
  ## Mark unwanted work without freeing capacity or ending its lease; archive scans poll cooperatively while proof/FFI execution finishes normally.
  if not worker.started: return false # A closed/default owner never accepts cancellation.
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket): return false # Foreign/stale tickets cannot affect another lease.
  worker.cancelled = true
  true

proc collect*(worker: var StateProofWorker, ticket: ProofWorkerTicket): ProofWorkerCompletion =
  ## Only Done collection ends the lease; defaults leave the slot and graph entirely untouched.
  if not worker.started: return default(ProofWorkerCompletion)
  acquire(worker.lock)
  defer: release(worker.lock)
  if not worker.matches(ticket) or worker.phase != ProofWorkerPhase.Done:
    return default(ProofWorkerCompletion) # Still-running work and foreign tickets retain all ownership.
  if worker.cancelled:
    worker.outcome = default(ProofQueryResult[ProofResponse])
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.Cancelled)
  elif worker.operation == ProofWorkerOperation.AssuranceAcquisition:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.AssuranceAcquired,
      acquisitionResponse: move(worker.acquisitionOutcome)) # Only fixed metadata survives the complete source/proof/retention turn.
  elif worker.operation == ProofWorkerOperation.AssuranceStorage:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.AssuranceCompleted,
      assuranceResponse: move(worker.assuranceOutcome)) # Collection ends every mutable namespace borrow before host observation or close.
  elif worker.operation == ProofWorkerOperation.WorkSubmission:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.WorkSubmitted,
      workResponse: move(worker.workOutcome)) # All worker inputs retire before Services installs source-bearing artifacts.
  elif worker.operation == ProofWorkerOperation.TicketProduction:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.TicketProduced,
        ticketResponse: move(worker.ticketOutcome)) # Collection ends the worker's secret/source borrowing before the host can rotate keys.
  elif worker.operation == ProofWorkerOperation.TicketVerification:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.TicketVerified,
        ticketResponse: move(worker.ticketOutcome)) # Complete detached proof facts leave no worker aliases after exact collection.
  elif worker.operation == ProofWorkerOperation.ReadVerification:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.ReadVerified,
      verifiedResponse: move(worker.verifyOutcome)) # No worker-owned aliases survive matching Done collection.
  elif worker.operation == ProofWorkerOperation.NetworkRead:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.ReadCompleted,
      readResponse: move(worker.readOutcome)) # Done collection ends every worker alias before host transport publication.
  elif worker.operation == ProofWorkerOperation.Ingestion:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.Imported,
      ingestion: move(worker.importOutcome)) # Transfer a verified whole batch only after every worker alias retires.
  else:
    result = ProofWorkerCompletion(status: ProofWorkerCompletionKind.Completed,
      response: move(worker.outcome)) # Transfer on the host only after all worker aliases have retired.
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.operation = ProofWorkerOperation.Query
  worker.query = default(ProofQuery)
  worker.phase = ProofWorkerPhase.Idle

proc close*(worker: var StateProofWorker) =
  ## Join before releasing results or ending the exclusive graph lease; archive scans observe stopping and proof/FFI execution finishes normally.
  if not worker.started: return # Defaults and repeated cleanup have no native lifetime.
  acquire(worker.lock)
  worker.stopping = true
  broadcast(worker.changed)
  release(worker.lock)
  worker.thread.join()
  worker.outcome = default(ProofQueryResult[ProofResponse])
  worker.readJob = default(NetworkReadJob)
  worker.readOutcome = default(ReadResult[ReadReply])
  worker.verifyJob = default(ReadVerificationJob)
  worker.verifyOutcome = default(ReadVerificationResult[CheckedReadReply])
  worker.ticketJob = default(TicketVerificationJob)
  worker.productionJob = default(TicketProductionJob)
  worker.workJob = default(WorkSubmissionJob)
  worker.workOutcome = default(WorkJobResult)
  worker.ticketOutcome = default(NetworkTicketResult[CheckedNetworkTicket])
  worker.assuranceJob = default(AssuranceStorageJob)
  worker.assuranceOutcome = default(AssuranceStoreResult[bool])
  worker.acquisitionJob = default(AssuranceAcquisitionJob)
  worker.acquisitionOutcome = default(AssuranceAcquisitionResult[AssuranceAcquisitionInfo])
  worker.importJob = default(LightProofImport)
  worker.importOutcome = default(LightImportResult[ImportedLightProofs])
  worker.operation = ProofWorkerOperation.Query
  worker.query = default(ProofQuery)
  worker.phase = ProofWorkerPhase.Idle
  worker.started = false
  deinitCond(worker.changed)
  deinitLock(worker.lock)
