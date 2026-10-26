# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One non-copyable owner for telemetry, RPC, UI and optional explicitly configured canonical state.
## The peer dispatcher borrows individual fields only while this stack owner remains stable;
## transport callbacks must retire before close/destruction. A bounded chain snapshot is shared once.
## After starting preparation, explicitly close to join before any borrowed input or shared alias retires.

import ../lib/logging

import std/[syncio, strutils, base64, assertions, monotimes, times]
import ../state/logical_continuation
import ./options
import ./light_runtime as light_actor
import ./[light_head, light_policy]
import ./[checkpoint_recovery, checkpoint_trust]
import ./[handoff, current_handoff, current_block_input]
import ./candidate
import ./block_input
import ./preparation_worker
import ./[collected_supplied_plan, collected_supplied_state]
import ./logical_review
import ./logical_proof
import ../state/account_review_plan
import ./logical_checkpoint
import ./frozen_supplied
import ../state/supplied_services
import ./logical_service_proof
import ./logical_export
import ./logical_source_export
import ./logical_checkpoint_import
import ./logical_code
import ./logical_code_proof
import ../state/code_availability
import ./full_logical_proof
import ./paged_logical_proof
import ./logical_seed
import ../codec/[state_composition, composite]
import ./current_logical as collected_logical
import ../state/[parent_logical, current_logical]
import ./[proof_query, proof_worker]
import ../state/[proof_service, proof_plan, proof_view, trie_proof]
import ./[disk_chain, disk_worker]
import ./[checkpoint_identity, checkpoint_transfer, checkpoint_session, checkpoint_worker, checkpoint_file]
import ../codec/bounded
import ../crypto/primitives
import ../codec/[block_codec, header, state_trie]
import ./chain as application_chain
import ../state/[store, disk_store, accumulation_finalization, accumulation_completion,
    accumulation_publication, accumulation_current_update]
import ../storage/[file_repository, node_repository, node_records, record_codec, database_identity,
    managed_repository, managed_manifest, full_paged_store]
import ../chain/provider
import ../telemetry/[wire, client, chain]
import ../quic/transport
import ../rpc/[server, protocol, proof_requests]
import ../chain/[parameters, genesis]
import ../ui/server
import ../management/[server, protocol]

type
  StateProofAdmissionError* {.pure.} = enum ## Admission grants a ticket only after capture and native submission succeed.
    Uninitialized, None, Closed, Busy, QueryFailure, WorkerFailure
  StateProofAdmission* = object ## Private guarded alternatives cannot forge a successful managed lease.
    case status: StateProofAdmissionError
    of None: ticket: ProofWorkerTicket
    of QueryFailure: queryReason: ProofQueryError
    of WorkerFailure: workerReason: ProofWorkerError
    else: discard # Closed/busy/default refusals expose no authority.

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

type Services* = object             ## Owns listeners/exporter; fields are borrowed by synchronous peer callbacks.
  light: light_actor.LightRuntime
  rpc*: Server
  ui*: UiServer
  management*: ManagementServer
  telemetry*: Client
  chainText: string
  canonical: ApplicationChain
  adoption: AccumulationHandoff
  currentAdoption: CurrentAccumulationHandoff
  worker: PreparationWorker
  proofWorker: StateProofWorker
  proofInput: ProofQuery
  rpcProof: RpcProofDispatch        # Detached connection intent never retains canonical state.
  rpcProofTicket: ProofWorkerTicket # Host-only exact collection authority for an RPC-origin job.
  proofing: bool
  checkpointExport: ApplicationCheckpointSession
  rpcLease: nil RpcChainLease
  preparing: bool
  started, chainRpc: bool
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
  `=wasMoved`(services.proofInput)
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
  `=wasMoved`(services.rpcLease)
  `=wasMoved`(services.management)
  `=wasMoved`(services.ui)
  `=wasMoved`(services.rpc)
  `=wasMoved`(services.telemetry)
  `=wasMoved`(services.chainText)
  `=wasMoved`(services.canonical)
  `=wasMoved`(services.adoption)
  `=wasMoved`(services.currentAdoption)

proc `=copy`*(destination: var Services, source: Services) {.error: "Application Services owns descriptors".}
proc `=dup`*(source: Services): Services {.error.}
  ## Composite ownership includes the stable worker and all listener lifetimes.
proc `=destroy`*(services: Services) =
  ## Retire partially configured owners and the shared snapshot even without explicit shutdown.
  `=destroy`(services.light)
  `=destroy`(services.proofWorker) # Explicit joined close precedes every selected-state alias retirement.
  `=destroy`(services.proofInput)
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
  `=destroy`(services.rpcLease)
  `=destroy`(services.management)
  `=destroy`(services.ui)
  `=destroy`(services.rpc)
  `=destroy`(services.telemetry)
  `=destroy`(services.chainText)
  `=destroy`(services.canonical)
  `=destroy`(services.adoption)
  `=destroy`(services.currentAdoption)

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
  services.publishing = false
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
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
  services.publishing = false
  services.diskMaintenance = default(PreparedDiskMaintenance)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
proc finishCurrentDiskPublication(services: var Services, completion: DiskPublicationCompletion) =
  ## Collection/join ends all borrows before exact receipt/context checks and canonical/RPC installation.
  if completion.kind == DiskCompletionKind.Completed:
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
  services.publishing = false
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil

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
  services.publishing = false
  services.diskPublication = default(PreparedDiskPublication)
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil
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

proc stopStateProofs*(services: var Services) =
  ## Join before dropping the captured selection or releasing this proof job's exact RPC token.
  if services.light.active:
    services.light.stopProofs()
    return # Full-state worker/lease fields remain unstarted in light mode.
  services.proofWorker.close()
  if services.proofing:
    services.proofInput = default(ProofQuery)
    services.proofing = false
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # Only this worker's joined lease can reopen canonical access.
  if services.rpcProof.valid:
    discard services.rpc.finishStateProof(services.rpcProof, default(StateRoot), [], "State proof stopped")
    services.rpcProof = default(RpcProofDispatch)
    services.rpcProofTicket = default(ProofWorkerTicket)

proc stopPreparation*(services: var Services) =
  ## Join and discard private execution before reopening canonical/RPC access; listeners and canonical state remain owned.
  if services.light.active: return # Distinct light actor owns its own CPU/IO lease and joins.
  if services.proofing or services.publishing: return # A proof/disk borrower owns the same RPC lease until its own joined retirement.
  services.worker.close()
  services.preparing = false
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil

proc stopCheckpointExport*(services: var Services) =
  ## Join detached I/O outside callbacks and retain actual uncollected work/retirement uncertainty until explicit acknowledgement.
  services.checkpointExport.close()

proc close*(services: var Services) =
  ## Idempotent retirement happens after every dispatcher/native callback has ended its borrows.
  services.light.close() # Distinct light workers join before the borrowed RPC owner or partial evidence retires.
  services.stopStateProofs() # Join selected-state access before any canonical/RPC owner retires.
  services.stopCheckpointExport() # Repeated close preserves the fixed joined-outcome journal.
  services.stopDiskPublication() # Commit receipts survive shutdown; joined IO ends all graph borrowing.
  services.stopPreparation() # Join before releasing any canonical or listener alias.
  services.management.close()
  services.ui.close()
  services.rpc.close()
  services.telemetry.close()
  services.rpc = default(Server) # Server.close retires sockets; replacement also releases its retained history/configuration.
  services.adoption = default(AccumulationHandoff) # Retire pending or unacknowledged immutable owners on shutdown.
  services.currentAdoption = default(CurrentAccumulationHandoff) # Native workers joined before current graph retirement.
  if services.disk.opened: discard services.disk.close
  services.diskEnabled = false
  services.diskManaged = false
  services.compactBytes = ByteLimit(0)
  services.diskOperation = ServiceDiskOperation.Publication
  services.diskFaulted = false
  services.diskTicket = default(DiskPublicationTicket)
  services.canonical = default(ApplicationChain)
  services.started = false
  services.chainRpc = false
  services.chainText = ""

# Read at most limit+1 bytes; empty output means missing, empty or oversized configuration.
proc boundedFile(path: string, limit: int): string {.raises.} =
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

proc setupRpc(rpc: var Server, options: Options, role: string, text: string): bool =
  ## An explicit RPC chain must validate before opening the listener; missing configuration remains unavailable.
  var parameters = default(ParameterResult)
  var genesis = unavailableGenesis()
  if options.rpcPort() != 0 and options.chainPath().len > 0:
    parameters = configuredParameters(text)
    if not parameters.ok: return false # Fail startup rather than advertise a partial/default parameter set.
    genesis = configuredGenesis(text, parameters.value)
    if genesis.error == GenesisError.Invalid: return false # Reject an incomplete or malformed explicit genesis.
  rpc.start(options.rpcPort(), role, parameters, genesis, options.uiPort(), chainIdentity(genesis))

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
  var address = default(array[16, byte])
  if ipv6:
    address[15] = 1 # The proof peer binds only ::1 in its IPv6 modes.
  else:
    # JIP-3 represents IPv4 endpoints as IPv4-mapped IPv6 addresses.
    address[10] = 255
    address[11] = 255
    address[12] = 127
    address[15] = 1
  var identity = default(array[32, byte])
  # Copy C array elements individually into native Nim storage before crossing the API boundary.
  for i in 0..<32: identity[i] = fields.key[i]
  let parsed = chainMetadata(text, identity, address, port)
  if not parsed.ok: return false # Failed chain metadata cannot produce a registration.
  configure(client, options.telemetryEndpoint(), parsed.value)

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
      if opened.error != DiskChainError.StoreFailure: return false
      if opened.storeFailure.error != DiskStoreError.FileFailure: return false
      if opened.storeFailure.fileError != FileError.IoFailure: return false
      let created = services.initializeSelectedDisk(options.stateDatabase)
      if created.error != DiskChainError.None:
        return false # O_EXCL prevents a failed open from overwriting any existing or concurrently created file.
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
      if options.rpcPort() != 0:
        identity = chainIdentity(configuredGenesis(services.chainText,
            configured.value)) # Imported head is never genesis identity.
      services.canonical = recovered # Preserve the exact restored map, inherited policy and one-head/unfinalized view.
    else:
      let seeded = initApplicationChain(services.chainText, limits)
      if seeded.error != ApplicationChainError.None:
        services.close() # A missing/refused seed cannot become a partial listener-only startup.
        return false
      services.canonical = seeded.value
      identity = chainIdentity(seeded.value.chainView.bestBlock) # Reuse capture without repeating map/header hashing.
  if options.diskStorage:
    if not withState or not services.setupDisk(options, limits, recovered.chainView.retainedCount > 0):
      services.close()
      return false # Backend failure never falls back to ephemeral memory or another chain.
  if not services.ui.start(options.uiPort(), options.devUiDirectory()):
    stderr.writeLine("Invalid UI listener or --dev-ui-dir")
    services.close() # Failed startup cannot retain a directory, seed or partially opened listener.
    return false
  var rpcReady = false
  if withState:
    let head = services.canonical.chainView.bestBlock
    let parameters = decodeParameters(head.value.chainParameters.encodeParameters)
    rpcReady = services.rpc.start(options.rpcPort(), role, parameters, services.canonical.chainView,
        options.uiPort(), identity)
  else:
    rpcReady = services.rpc.setupRpc(options, role,
        services.chainText) # Preserve legacy optional/unavailable genesis behavior.
  if not rpcReady:
    stderr.writeLine("Invalid RPC listener or --chain parameters")
    services.close() # RPC failures retire both the UI listener and the canonical owner.
    return false
  if options.rpcPort() != 0:
    log(options.logWriter, LogTarget.Rpc, LogLevel.Info, "RPC listener started port=" &
        $options.rpcPort())
  services.chainRpc = withState and options.rpcPort() != 0
  if services.chainRpc and options.argument(1) in ["server", "client", "mesh"]:
    discard services.rpc.enableStateProofs() # These dispatcher shapes retain no external canonical aliases across turns.
  let database = if options.diskStorage: options.stateDatabase else: ""
  let managementInfo = ManagementInfo(role: role, chainPath: options.chainPath,
    databasePath: database, stateEnabled: withState)
  if not services.management.start(options.managementSocket, managementInfo):
    stderr.writeLine("Invalid management socket; select an absent path in an owned private directory")
    services.close() # A refused management listener rolls back every previously started service.
    return false
  services.started = true
  true

type LightStartup = object ## Fixed configured/trusted metadata retains no complete genesis StateStore or ChainView.
  ready: bool
  trust: TrustedApplicationCheckpoint
  policy: LightRuntimePolicy
  parameters: ParameterResult
  identity: ChainIdentity
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
    identity: chainIdentity(genesis))
proc startLightServices(services: var Services, options: Options, role: string): bool {.raises.} =
  ## Light startup chooses distinct memory/paged ownership with independent current trust before any listener is exposed.
  if services.started or not options.valid or not options.lightMode: return false # Failed/repeated mode selection cannot disturb an existing lifetime.
  services.chainText = boundedFile(options.chainPath, MaxChainBytes)
  let startup = captureLightStartup(services.chainText, options)
  if not startup.ready:
    services.close()
    return false # No complete/partial startup prefix becomes an active service.
  var ready = false
  defer:
    if not ready: services.close() # Join every partial acquisition before rollback or exception propagation.
  if not services.ui.start(options.uiPort, options.devUiDirectory): return false
  let path = if options.diskStorage: options.stateDatabase else: ""
  if not services.light.start(services.rpc, role, options.rpcPort, options.uiPort,
      options.diskStorage, path, startup.trust, startup.policy, startup.parameters,
      startup.identity): return false
  let info = ManagementInfo(role: role, chainPath: options.chainPath, databasePath: path,
      stateEnabled: true)
  if not services.management.start(options.managementSocket,
      info): return false # Static management remains separate from complete-map execution controls.
  if not options.telemetryEnabled: services.chainText = "" # No raw configured genesis is retained during ordinary light runtime.
  services.chainRpc = options.rpcPort != 0
  services.started = true
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
  services.adoption.enqueueCandidate(services.canonical, candidate, ancestors, limits, composition)

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
  input.enqueue(id, services.canonical, services.adoption, composition)

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
  services.currentAdoption.take()

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

proc beginStateProof*(services: var Services, selected: BlockHash, plan: StateProofPlan,
    limits: ProofQueryLimits): StateProofAdmission {.raises.} =
  ## Global/mixed plans use the established exclusive lease and exact native ticket retirement.
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
proc cancelStateProof*(services: var Services, ticket: ProofWorkerTicket): bool =
  ## Cancellation requests discard without releasing graph access or bounded capacity.
  if services.light.active: services.light.cancelQuery(ticket) else: services.proofWorker.cancel(ticket)
proc collectStateProof*(services: var Services, ticket: ProofWorkerTicket): ProofWorkerCompletion =
  ## Only matching Done collection retires the query and reopens canonical/RPC access together.
  if services.light.active: return services.light.collectQuery(
      ticket) # Only actual matching Done collection ends its own request lease.
  result = services.proofWorker.collect(ticket)
  if result.kind != ProofWorkerCompletionKind.Uninitialized:
    services.proofing = false
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # A stale/foreign/early ticket never resumes another lease.

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
  ## Pause RPC before worker admission; all existing external graph aliases must also remain untouched until collection/join.
  discard services.worker.start() # Reuse an existing idle thread without spawning per job.
  services.rpcLease = services.rpc.pauseChain()
  let admitted = services.worker.submit(input, id, services.canonical)
  if admitted.error == PreparationError.None:
    services.preparing = true # No fallible canonical/alias work follows successful worker submission.
  else:
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # A refused input grants no lease and restores ordinary RPC ticks.
  admitted

proc beginPreparation*(services: var Services, input: var CurrentBlockInput,
    id: CurrentBlockInputId): PreparationAdmission {.raises,
        requires: services.preparationAvailable.} =
  ## Pause RPC before current submission; all external input/canonical aliases remain frozen until collect or join.
  discard services.worker.start() # The existing fixed-address thread handles both payload alternatives.
  services.rpcLease = services.rpc.pauseChain()
  let admitted = services.worker.submit(input, id, services.canonical)
  if admitted.error == PreparationError.None:
    services.preparing = true # No host graph work follows successful native admission.
  else:
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # Refused submission grants no lease or current authority.
  admitted

proc preparationPhase*(services: var Services): PreparationPhase =
  ## Poll only the worker's synchronized scalar lifecycle state.
  services.worker.phase

proc cancelPreparation*(services: var Services, ticket: PreparationTicket): bool =
  ## Cancellation never reopens canonical or RPC access before actual retirement.
  services.worker.cancel(ticket)

proc collectPreparation*(services: var Services, ticket: PreparationTicket): PreparationCompletion =
  ## Move/drop completion only after execution temporaries retire, then restore canonical and RPC access together.
  result = services.worker.collect(ticket)
  if result.kind != PreparationCompletionKind.Uninitialized:
    services.preparing = false
    discard services.rpc.resumeChain(services.rpcLease)
    services.rpcLease = nil # Stale/early collection cannot release another active lease.

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
  services.adoption.take()

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
  ## Explicit local resource ceilings bound complete-map generation, proof verification and detached wire copies.
  ProofQueryLimits(map: StateTrieLimits(items: ElementLimit(65536), nodes: TrieNodeLimit(131071),
      perValue: ByteLimit(1048576), totalValueBytes: ByteLimit(8388608)),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(MaxRpcProofBytes)),
    aggregate: StateProofBatchLimits(items: ElementLimit(MaxRpcProofKeys), nodes: ElementLimit(
        3984), valueBytes: ByteLimit(MaxRpcProofBytes)),
    view: ProofViewLimits(items: ElementLimit(MaxRpcProofKeys), valueBytes: ByteLimit(
        MaxRpcProofBytes)),
    wireBytes: ByteLimit(MaxRpcProofBytes), hashes: ProofHashLimit(4000000))

proc beginRpcProof(services: var Services) =
  ## Run only after RPC/UI tick activations retire; no selected-state alias can escape onto this stack.
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

proc tick*(services: var Services, peers: uint32) =
  ## Attempt one pending adoption between native callbacks; independent management remains available during leases.
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
    let completion = services.collectStateProof(services.rpcProofTicket)
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

proc configureTelemetry*(services: var Services, options: Options, certificate: string,
    port: uint16, ipv6: bool): bool {.raises.} =
  ## Register the actual transport identity/address after binding, using the captured chain bytes.
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
