# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One distinct light actor serializes bounded proof CPU work and paged publication/retirement without complete-state ownership.
## All staging activations retire before worker admission; the borrowed RPC owner and this actor remain at stable addresses until joined close.
import std/[assertions, monotimes, times]
import ./[light_head, light_store, light_policy, light_proof_import, light_rpc,
  checkpoint_identity, checkpoint_trust, proof_query, proof_worker, disk_worker]
import ../rpc/[server, protocol, proof_requests, light_source]
import ../state/[proof_view, trie_proof, proof_service]
import ../codec/[bounded, state_trie]
import ../chain/[genesis, parameters]
import ../storage/[paged_store, file_errors]

type
  LightRuntimeError* {.pure.} = enum ## Admission/default failures grant no worker or state authority.
    Uninitialized, None, Closed, Busy, InvalidSelection, QueryFailure, ImportFailure,
    WorkerFailure, RpcMismatch, StorageFailure
  LightRuntimeResult*[T] = object ## Success alone exposes its exact passive head or admitted ticket.
    case status: LightRuntimeError
    of None: completed: T
    of QueryFailure: queryCause: ProofQueryError
    of ImportFailure: importCause: LightImportError
    of WorkerFailure: workerCause: ProofWorkerError
    else: discard                 # Plain refusals contain only their reason.
  CpuOperation {.pure.} = enum ## Typed CPU completion dispatch is independent of the shared slot lifecycle.
    Query, Import
  IoOperation {.pure.} = enum ## Cleanup never grants a core publication receipt.
    Publication, Retirement
  LightRuntime* = object ## Move-only actor owns one selected light backend and at most one active request graph lease.
    started, diskMode, faulted, cpuBusy, ioBusy, publicationReady: bool
    rpc: nil ptr Server
    rpcBound: bool
    rpcSource: RpcLightHead
    lease: nil RpcChainLease
    current: LightApplicationHead
    policy: LightRuntimePolicy
    disk: LightPagedStore
    cpu: StateProofWorker
    io: DiskPublicationWorker
    cpuOperation: CpuOperation
    ioOperation: IoOperation
    query: ProofQuery
    importInput: LightProofImport
    publication: PreparedLightPublication
    retirement: PreparedLightRetirement
    cpuTicket: ProofWorkerTicket
    ioTicket: DiskPublicationTicket
    request: RpcProofDispatch
    lastDisk: DiskPublicationCompletion
    retirementDelayed: bool
    retirementAttempt: MonoTime
func error*[T](outcome: LightRuntimeResult[T]): LightRuntimeError =
  ## Observe admission without authorizing payload access.
  outcome.status
func value*[T](outcome: LightRuntimeResult[T]): T {.requires: outcome.status ==
    LightRuntimeError.None.} =
  ## Only complete success exposes an immutable head or live ticket.
  outcome.completed
func queryError*[T](outcome: LightRuntimeResult[T]): ProofQueryError {.requires: outcome.status ==
    LightRuntimeError.QueryFailure.} =
  ## Preserve precise query selection/plan/policy refusal.
  outcome.queryCause
func workerError*[T](outcome: LightRuntimeResult[T]): ProofWorkerError {.requires: outcome.status ==
    LightRuntimeError.WorkerFailure.} =
  ## Failed admission grants no graph lease or ticket.
  outcome.workerCause
func active*(runtime: LightRuntime): bool =
  ## Passive mode observation touches no canonical graph or native owner.
  runtime.started
func busy*(runtime: LightRuntime): bool =
  ## Done retains exclusion until actual collection or joined close.
  runtime.cpuBusy or runtime.ioBusy
func storageFaulted*(runtime: LightRuntime): bool =
  ## Uncertainty disables future mutations while independently retained evidence remains readable.
  runtime.faulted
proc `=copy`*(destination: var LightRuntime, source: LightRuntime) {.error.}
  ## Native thread and writer ownership has one stable actor address.
proc `=dup`*(source: LightRuntime): LightRuntime {.error.}
  ## Composite implicit duplication cannot copy native lifetimes.
proc `=wasMoved`*(runtime: var LightRuntime) {.nodestroy, inline, requires: not runtime.started.} =
  ## Only explicitly closed actors may relocate after every borrower has joined.
  `=wasMoved`(runtime.rpcSource)
  `=wasMoved`(runtime.lease)
  `=wasMoved`(runtime.current)
  `=wasMoved`(runtime.disk)
  `=wasMoved`(runtime.cpu)
  `=wasMoved`(runtime.io)
  `=wasMoved`(runtime.query)
  `=wasMoved`(runtime.importInput)
  `=wasMoved`(runtime.publication)
  `=wasMoved`(runtime.retirement)
  `=wasMoved`(runtime.cpuTicket)
  `=wasMoved`(runtime.ioTicket)
  `=wasMoved`(runtime.request)
  `=wasMoved`(runtime.lastDisk)
proc `=destroy`*(runtime: LightRuntime) =
  ## Explicit joined close precedes every canonical, request, cache and native owner destruction.
  assert not runtime.started
  `=destroy`(runtime.cpu)
  `=destroy`(runtime.io)
  `=destroy`(runtime.disk)
  `=destroy`(runtime.query)
  `=destroy`(runtime.importInput)
  `=destroy`(runtime.publication)
  `=destroy`(runtime.retirement)
  `=destroy`(runtime.cpuTicket)
  `=destroy`(runtime.ioTicket)
  `=destroy`(runtime.request)
  `=destroy`(runtime.lastDisk)
  `=destroy`(runtime.current)
  `=destroy`(runtime.rpcSource)
  `=destroy`(runtime.lease)
proc releaseLease(runtime: var LightRuntime) =
  ## Only collection/join of the actual owning operation resumes its exact host RPC pause token.
  let rpc = runtime.rpc
  if rpc != nil and runtime.lease != nil:
    assert rpc[].resumeChain(runtime.lease) # Foreign/default pause authority can never be silently released.
  runtime.lease = nil
proc head*(runtime: LightRuntime): LightRuntimeResult[LightApplicationHead] =
  ## Scalar exclusion is checked before copying any shared canonical ARC handle.
  if not runtime.started: return LightRuntimeResult[LightApplicationHead](
      status: LightRuntimeError.Closed) # No startup prefix grants state authority.
  if runtime.busy: return LightRuntimeResult[LightApplicationHead](
      status: LightRuntimeError.Busy) # Running/Done worker aliases remain untouched.
  LightRuntimeResult[LightApplicationHead](status: LightRuntimeError.None,
      completed: runtime.current)
proc queryMetadata*(runtime: LightRuntime): RpcLightHead {.requires: not runtime.busy.} =
  ## Detached read-only transport metadata owns no partial proof graph or application trust authority.
  runtime.rpcSource

proc proofPhase*(runtime: var LightRuntime): ProofWorkerPhase =
  ## Synchronized scalar polling never reads a request or canonical graph.
  runtime.cpu.phase
proc diskPhase*(runtime: var LightRuntime): DiskWorkerPhase =
  ## Native publication/retirement phase remains independent of CPU proof work.
  runtime.io.phase
proc sourceReady(runtime: LightRuntime): bool =
  ## Dispatcher preflight runs only outside every worker lease and grants no physical storage authority.
  if not runtime.started or runtime.busy: return false # Capacity/exclusion precedes all graph access.
  let rpc = runtime.rpc
  rpc != nil and (not runtime.rpcBound or rpc[].canInstallLightHead(runtime.rpcSource))
proc adopt(runtime: var LightRuntime, target: LightApplicationHead): bool =
  ## All worker aliases have retired before bounded metadata copying and canonical/RPC source installation.
  if not target.valid: return false # An invalid source can never replace current trust.
  let rpc = runtime.rpc
  if rpc == nil: return false # The borrowed listener owner outlives this actor's active lifetime.
  let captured = captureLightRpcHead(target)
  if captured.error != RpcLightSourceError.None: return false # No transport prefix is installed.
  if runtime.rpcBound and not rpc[].installLightHead(runtime.rpcSource,
      captured.value): return false # Exact old source includes local coverage, not just equal root/header.
  runtime.current = target
  runtime.rpcSource = captured.value
  true
proc finishImportReply(runtime: var LightRuntime, failure: string) =
  ## Exact connection namespace suppresses cancelled/reset acknowledgements after actual adoption or refusal.
  let rpc = runtime.rpc
  if rpc != nil and runtime.request.valid:
    discard rpc[].finishStateProofImport(runtime.request, runtime.current.stateRoot,
      runtime.current.proofView.len, failure)
  runtime.request = default(RpcProofDispatch)
proc finishDisk(runtime: var LightRuntime, completion: DiskPublicationCompletion) =
  ## Entered native IO retains its exact typed outcome; only NotExecuted promises no publication/cleanup activation.
  runtime.ioBusy = false
  runtime.lastDisk = completion
  runtime.releaseLease() # Join/collection already retired every native temporary before any source access below.
  case runtime.ioOperation
  of IoOperation.Publication:
    if completion.kind == DiskCompletionKind.LightCompleted:
      let outcome = completion.lightValue
      if outcome.error == LightStoreError.None:
        if not runtime.adopt(outcome.value.head):
          runtime.faulted = true # A confirmed durable target cannot authorize a mismatched RPC binding.
          runtime.finishImportReply("Light RPC source changed")
        else:
          runtime.finishImportReply("") # Actual usable publication precedes successful import acknowledgement.
      else:
        runtime.faulted = true # Fresh independent reopen resolves native publication uncertainty.
        runtime.finishImportReply("Light storage publication failed")
    else:
      assert completion.kind == DiskCompletionKind.NotExecuted # Never fabricate success for genuinely unexecuted queued work.
      runtime.finishImportReply("Light publication did not execute")
    runtime.publication = default(PreparedLightPublication)
    runtime.publicationReady = false
  of IoOperation.Retirement:
    if completion.kind == DiskCompletionKind.LightRetired:
      let outcome = completion.lightRetirementValue
      if outcome.error == LightStoreError.None:
        runtime.retirementDelayed = false # Confirmed absence unblocks the next physical publication.
      elif outcome.error == LightStoreError.NativeFailure and outcome.nativeFailure.error ==
          PagedNativeError.FileFailure and outcome.nativeFailure.fileError == FileError.Busy:
        runtime.retirementDelayed = true # A foreign old pin retains bounded retryable backpressure.
        runtime.retirementAttempt = getMonoTime()
      else:
        runtime.faulted = true # Cleanup uncertainty never rolls back the already adopted trusted head.
    else:
      assert completion.kind == DiskCompletionKind.NotExecuted # No IO entry cannot claim durable absence.
    runtime.retirement = default(PreparedLightRetirement)
proc close*(runtime: var LightRuntime) =
  ## Join CPU and IO before releasing the borrowed RPC lease, native writer, jobs or any shared proof/header alias.
  runtime.cpu.close()
  if runtime.cpuBusy:
    runtime.cpuBusy = false
    runtime.releaseLease() # CPU-only work has no durable side effect; joined shutdown may discard its result.
  let completion = runtime.io.close
  if runtime.ioBusy: runtime.finishDisk(completion) # Preserve every operation that entered native IO.
  runtime.releaseLease()
  let rpc = runtime.rpc
  if rpc != nil: rpc[].close() # This actor acquired the initially closed borrowed listener; joins precede transport alias retirement.
  if runtime.disk.opened: discard runtime.disk.close
  runtime.query = default(ProofQuery)
  runtime.importInput = default(LightProofImport)
  runtime.publication = default(PreparedLightPublication)
  runtime.retirement = default(PreparedLightRetirement)
  runtime.request = default(RpcProofDispatch)
  runtime.current = default(LightApplicationHead)
  runtime.rpcSource = default(RpcLightHead)
  runtime.rpc = nil
  runtime.started = false
  runtime.cpuBusy = false
  runtime.ioBusy = false
  runtime.publicationReady = false
  runtime.retirementDelayed = false
proc start*(runtime: var LightRuntime, rpc: var Server, role: string,
    port, uiPort: uint16, disk: bool, path: string, trust: TrustedApplicationCheckpoint,
    policy: LightRuntimePolicy, parameters: ParameterResult,
        identity: ChainIdentity): bool {.raises.} =
  ## Startup owns all native work before callbacks become observable; independent current trust and explicit backend policy never come from disk.
  if runtime.started or not rpc.availableForStart or (disk and path.len == 0) or (not disk and
      path.len > 0): return false # Repeated/default physical activation cannot replace a live owner.
  if not parameters.ok or not trust.ready: return false # Independently configured parameters must match current trusted metadata.
  if parameters.value.encodeParameters != trust.identity.parameters.encodeParameters: return false # No cross-network/profile fallback.
  runtime.lastDisk = default(DiskPublicationCompletion)
  runtime.rpc = addr rpc
  runtime.policy = policy
  runtime.diskMode = disk
  runtime.rpcBound = port != 0
  runtime.faulted = false
  var ready = false
  defer:
    if not ready: runtime.close() # Every partial file/thread/listener acquisition retires before returning or raising.
  let captured = captureLightHead(trust, policy.head)
  if captured.error != LightHeadError.None: return false # Independent header/root/profile checks precede native mutation.
  runtime.current = captured.value
  if disk:
    # Exclusive initialization never overwrites; only an already-existing target permits strict independent-trust reopen.
    let created = initializeLightPagedStore(runtime.disk, path, captured.value, policy.store)
    if created.error == LightStoreError.None:
      runtime.current = created.value.head
    else:
      if created.error != LightStoreError.NativeFailure: return false
      let cause = created.nativeFailure
      if cause.error != PagedNativeError.FileFailure or cause.fileError !=
          FileError.AlreadyExists: return false
      let opened = openLightPagedStore(runtime.disk, path, trust, policy.store)
      if opened.error != LightStoreError.None: return false # No schema/root/backend fallback or forensic candidate repair.
      runtime.current = opened.value.head
  let transport = captureLightRpcHead(runtime.current)
  if transport.error != RpcLightSourceError.None: return false # Complete detached metadata capture precedes listener visibility.
  runtime.rpcSource = transport.value
  if not rpc.startLight(port, role, parameters, transport.value, disk, uiPort,
      identity): return false
  if port != 0: discard rpc.enableStateProofs() # The light actor itself owns bounded query/import dispatch and all canonical exclusion.
  if not runtime.cpu.start(): return false # One reusable existing CPU worker; full-state preparation stays unstarted.
  if disk and not runtime.io.start(): return false # At most one existing disk worker belongs to this selected backend.
  runtime.started = true
  ready = true
  true
proc stageQuery(runtime: var LightRuntime, selected: BlockHash, plan: StateProofPlan,
    limits: ProofQueryLimits): ProofQueryError =
  ## This activation retires every temporary canonical/query alias before admission can start a native borrower.
  if array[32, byte](selected) != array[32, byte](
      runtime.current.current.value.identity.blockHash): return ProofQueryError.InvalidSelection # Retained historical headers do not imply retained historical proof views.
  let captured = captureProofQuery(runtime.current, plan, limits)
  if captured.error == ProofQueryError.None: runtime.query = captured.value # One stable staged owner survives activation retirement.
  captured.error
proc stageQuery(runtime: var LightRuntime, selected: BlockHash, plan: ServiceProofPlan,
    limits: ProofQueryLimits): ProofQueryError =
  ## Preserve service MissingWitness spelling while retaining a distinct partial source.
  if array[32, byte](selected) != array[32, byte](
      runtime.current.current.value.identity.blockHash): return ProofQueryError.InvalidSelection # No implicit current/historical retargeting.
  let captured = captureProofQuery(runtime.current, plan, limits)
  if captured.error == ProofQueryError.None: runtime.query = captured.value # All local captured-result aliases retire before the caller submits.
  captured.error
proc ensureCpu(runtime: var LightRuntime): bool =
  ## Explicit proof shutdown may restart the one bounded worker; ordinary requests reuse its existing thread.
  try:
    discard runtime.cpu.start() # A running worker returns false without creating another thread.
    true
  except:
    false # Failed creation grants no borrower, request or graph lease.
proc admitQuery(runtime: var LightRuntime, reason: ProofQueryError): LightRuntimeResult[
    ProofWorkerTicket] =
  ## Staging has retired; only scalar/ticket work follows successful native ownership transfer.
  if reason != ProofQueryError.None: return LightRuntimeResult[ProofWorkerTicket](
      status: LightRuntimeError.QueryFailure, queryCause: reason) # Failed capture owns no worker slot.
  if not runtime.ensureCpu:
    runtime.query = default(ProofQuery) # No native borrower exists after failed thread creation.
    return LightRuntimeResult[ProofWorkerTicket](status: LightRuntimeError.WorkerFailure,
        workerCause: ProofWorkerError.Closed)
  let rpc = runtime.rpc
  assert rpc != nil
  runtime.lease = rpc[].pauseChain()
  if runtime.lease == nil:
    runtime.query = default(ProofQuery) # No native borrower exists after failed pause admission.
    return LightRuntimeResult[ProofWorkerTicket](status: LightRuntimeError.RpcMismatch)
  let admitted = runtime.cpu.submit(runtime.query)
  if admitted.error != ProofWorkerError.None:
    runtime.query = default(ProofQuery) # Failed worker admission grants no graph lease.
    runtime.releaseLease()
    return LightRuntimeResult[ProofWorkerTicket](status: LightRuntimeError.WorkerFailure,
        workerCause: admitted.error)
  runtime.cpuTicket = admitted.value
  runtime.cpuOperation = CpuOperation.Query
  runtime.cpuBusy = true
  LightRuntimeResult[ProofWorkerTicket](status: LightRuntimeError.None, completed: admitted.value)
proc beginQuery*(runtime: var LightRuntime, selected: BlockHash, plan: StateProofPlan,
    limits: ProofQueryLimits): LightRuntimeResult[ProofWorkerTicket] =
  ## The caller retains every source alias untouched through exact collection/join; scalar selection must be prepared before this call.
  if not runtime.started: return LightRuntimeResult[ProofWorkerTicket](
      status: LightRuntimeError.Closed)
  if not runtime.sourceReady or runtime.publicationReady: return LightRuntimeResult[
      ProofWorkerTicket](status: LightRuntimeError.Busy) # Exclusion precedes any source handle copy.
  let reason = runtime.stageQuery(selected, plan, limits)
  runtime.admitQuery(reason)
proc beginQuery*(runtime: var LightRuntime, selected: BlockHash, plan: ServiceProofPlan,
    limits: ProofQueryLimits): LightRuntimeResult[ProofWorkerTicket] =
  ## Existing service callers use the same capacity and exact partial-evidence source contract.
  if not runtime.started: return LightRuntimeResult[ProofWorkerTicket](
      status: LightRuntimeError.Closed)
  if not runtime.sourceReady or runtime.publicationReady: return LightRuntimeResult[
      ProofWorkerTicket](status: LightRuntimeError.Busy) # No leased graph is inspected.
  let reason = runtime.stageQuery(selected, plan, limits)
  runtime.admitQuery(reason)
proc cancelQuery*(runtime: var LightRuntime, ticket: ProofWorkerTicket): bool =
  ## Logical cancellation never ends capacity or source exclusion before collection/join.
  runtime.cpu.cancel(ticket)
proc collectQuery*(runtime: var LightRuntime, ticket: ProofWorkerTicket): ProofWorkerCompletion =
  ## SDK collection retires only the actual matching Done query, without touching a foreign/in-flight lease.
  if not runtime.cpuBusy or runtime.cpuOperation != CpuOperation.Query: return default(
      ProofWorkerCompletion) # Imported results have a separate actor-owned adoption path.
  result = runtime.cpu.collect(ticket)
  if result.kind != ProofWorkerCompletionKind.Uninitialized:
    runtime.cpuBusy = false
    runtime.releaseLease() # Every native temporary and selected-state alias has retired.
proc stageImport(runtime: var LightRuntime, selected: BlockHash,
    wire: openArray[byte]): LightImportError =
  ## Fixed independent identity and private wire capture retire their temporary aliases before CPU admission.
  if array[32, byte](selected) != array[32, byte](
      runtime.current.current.value.identity.blockHash): return LightImportError.InvalidSelection # Untrusted selectors cannot change the current head/root.
  let captured = captureLightProofImport(runtime.current, wire, runtime.policy.ingestion)
  if captured.error == LightImportError.None: runtime.importInput = captured.value # Preserve one stable detached request owner only.
  captured.error
proc admitImport(runtime: var LightRuntime, reason: LightImportError): bool =
  ## No request/metadata capture activation remains live when the CPU worker begins borrowing.
  if reason != LightImportError.None:
    runtime.finishImportReply("Invalid or over-budget light proof import") # No authenticated prefix or worker ticket exists.
    return false
  if not runtime.ensureCpu:
    runtime.importInput = default(LightProofImport)
    runtime.finishImportReply("Light proof worker unavailable") # Thread creation failure grants no graph lease.
    return false
  let rpc = runtime.rpc
  assert rpc != nil
  runtime.lease = rpc[].pauseChain()
  if runtime.lease == nil:
    runtime.importInput = default(LightProofImport)
    runtime.finishImportReply("Light RPC source unavailable") # No borrower owns the staged wire.
    return false
  let admitted = runtime.cpu.submit(runtime.importInput)
  if admitted.error != ProofWorkerError.None:
    runtime.importInput = default(LightProofImport)
    runtime.releaseLease()
    runtime.finishImportReply("Light proof worker unavailable") # Refused admission grants no graph lease.
    return false
  runtime.cpuTicket = admitted.value
  runtime.cpuOperation = CpuOperation.Import
  runtime.cpuBusy = true
  true
proc stageImportedPublication(runtime: var LightRuntime, batch: VerifiedStateProofBatch): bool =
  ## All verified-batch/cache/prepared-target temporary aliases retire before the caller may submit native IO.
  let source = runtime.disk.snapshot
  if source.error != LightStoreError.None or not sameLightHead(source.value.head,
      runtime.current): return false # Passive facade/canonical incarnations must agree.
  let prepared = prepareLightProofMerge(source.value, batch)
  if prepared.error != LightStoreError.None: return false # No partially prepared target can reach disk.
  runtime.publication = prepared.value
  runtime.publicationReady = true
  true
proc collectImport(runtime: var LightRuntime) =
  ## This entire completion/verification/merge activation retires before tick can admit the prepared native publication.
  let completion = runtime.cpu.collect(runtime.cpuTicket)
  assert completion.kind != ProofWorkerCompletionKind.Uninitialized
  runtime.cpuBusy = false
  runtime.releaseLease()
  if completion.kind == ProofWorkerCompletionKind.Cancelled:
    runtime.finishImportReply("Light proof import cancelled") # Cancelled CPU work grants no imported facts.
    return
  assert completion.kind == ProofWorkerCompletionKind.Imported
  let outcome = completion.importedValue
  if outcome.error != LightImportError.None:
    runtime.finishImportReply("Light proof authentication failed") # A failed whole batch never changes retained knowledge.
    return
  let imported = outcome.value
  if not sameApplicationCheckpoint(imported.identity, runtime.current.current.value.identity):
    runtime.finishImportReply("Light proof import selected a stale head") # Equal roots cannot hide a different current checkpoint.
    return
  let merged = mergeLightProofs(runtime.current, imported.batch, runtime.policy.head)
  if merged.error != LightHeadError.None:
    runtime.finishImportReply("Light proof retention limit exceeded") # Independent retained-state ceilings never widen after verification.
    return
  if merged.value.proofView.len == runtime.current.proofView.len:
    runtime.finishImportReply("") # Already known genuine facts need no physical no-op publication.
    return
  if not runtime.diskMode:
    if runtime.adopt(merged.value): runtime.finishImportReply(
        "") # Memory adoption follows whole-batch authentication and exact RPC preflight.
    else: runtime.finishImportReply("Light RPC source changed") # No native state is involved in refused memory adoption.
  elif runtime.faulted or runtime.disk.retirementPending:
    runtime.finishImportReply("Light storage unavailable or retirement pending") # One old artifact bounds physical backpressure.
  elif not runtime.stageImportedPublication(imported.batch):
    runtime.finishImportReply("Light storage preparation failed") # Staging may refuse pure quotas without fabricating publication.
proc admitPublication(runtime: var LightRuntime): bool =
  ## Prepared staging activations and completion/batch aliases have retired before any native IO starts.
  if not runtime.publicationReady or runtime.busy: return false # No slot or target authority exists yet.
  let rpc = runtime.rpc
  assert rpc != nil
  if runtime.faulted or (runtime.rpcBound and not rpc[].canInstallLightHead(runtime.rpcSource)):
    runtime.finishImportReply("Light storage or RPC source unavailable")
    runtime.publication = default(PreparedLightPublication)
    runtime.publicationReady = false
    return false
  runtime.lastDisk = default(DiskPublicationCompletion) # Release previous snapshot outcomes before native graph borrowing begins.
  runtime.lease = rpc[].pauseChain()
  if runtime.lease == nil: return false # A foreign pause retains its own resume authority.
  let admitted = runtime.io.submit(runtime.disk, runtime.publication)
  if admitted.error != DiskWorkerError.None:
    runtime.releaseLease()
    runtime.finishImportReply("Light disk worker unavailable") # Refused admission entered no native activation.
    runtime.publication = default(PreparedLightPublication)
    runtime.publicationReady = false
    return false
  runtime.ioTicket = admitted.value
  runtime.ioOperation = IoOperation.Publication
  runtime.ioBusy = true
  true
proc stageRetirement(runtime: var LightRuntime): bool =
  ## A private passive job captures no native pin; all temporary cache aliases retire before admission.
  let prepared = runtime.disk.prepareLightRetirement
  if prepared.error != LightStoreError.None: return false # Default/quarantined state grants no cleanup authority.
  runtime.retirement = prepared.value
  true
proc admitRetirement(runtime: var LightRuntime): bool =
  ## Borrow stable store/job addresses only after staging activation retirement and exact RPC source preflight.
  let rpc = runtime.rpc
  assert rpc != nil
  if runtime.busy or runtime.faulted or (runtime.rpcBound and not rpc[].canInstallLightHead(
      runtime.rpcSource)): return false # No borrowed graph is touched after a failed scalar/source gate.
  runtime.lastDisk = default(DiskPublicationCompletion)
  runtime.lease = rpc[].pauseChain()
  if runtime.lease == nil: return false # Another host owner retains this pause.
  let admitted = runtime.io.submitRetirement(runtime.disk, runtime.retirement)
  if admitted.error != DiskWorkerError.None:
    runtime.releaseLease() # No native activation exists after failed admission.
    runtime.retirement = default(PreparedLightRetirement)
    return false
  runtime.ioTicket = admitted.value
  runtime.ioOperation = IoOperation.Retirement
  runtime.ioBusy = true
  true
proc retirementDue(runtime: LightRuntime): bool =
  ## A foreign physical pin receives bounded monotonic retry spacing while ordinary metadata/proof reads remain available.
  not runtime.retirementDelayed or (getMonoTime()-runtime.retirementAttempt).inMilliseconds >= 1000
proc collectDisk(runtime: var LightRuntime) =
  ## The complete returned-outcome activation retires before tick can enqueue another borrower of shared snapshot graphs.
  let completion = runtime.io.collect(runtime.ioTicket)
  assert completion.kind != DiskCompletionKind.Uninitialized
  runtime.finishDisk(completion)
proc collectRpcQuery(runtime: var LightRuntime) =
  ## Exact CPU collection ends exclusion before response serialization and connection-local completion.
  let ticket = runtime.cpuTicket # Retain the small host-only ticket before mutable actor collection.
  let completion = runtime.collectQuery(ticket)
  assert completion.kind != ProofWorkerCompletionKind.Uninitialized
  let rpc = runtime.rpc
  assert rpc != nil
  if completion.kind == ProofWorkerCompletionKind.Completed:
    let outcome = completion.value
    if outcome.error == ProofQueryError.None:
      let response = outcome.value
      let wire = response.bytes(runtime.policy.query.wireBytes)
      if wire.error == ProofQueryError.None: discard rpc[].finishStateProof(runtime.request,
          response.stateRoot, wire.value) # Detached bounded wire contains no canonical graph.
      else: discard rpc[].finishStateProof(runtime.request, runtime.current.stateRoot, newSeq[byte](
          0), "Light proof output limit exceeded")
    else:
      discard rpc[].finishStateProof(runtime.request, runtime.current.stateRoot, newSeq[byte](0),
          "Light proof witness unavailable") # Missing evidence is never converted to absence.
  else:
    assert completion.kind == ProofWorkerCompletionKind.Cancelled
    discard rpc[].finishStateProof(runtime.request, runtime.current.stateRoot, newSeq[byte](0), "Light proof request cancelled")
  runtime.request = default(RpcProofDispatch)
proc beginRpcRequest(runtime: var LightRuntime) =
  ## RPC tick and all metadata contexts have retired before this bounded actor claims one detached request intent.
  if not runtime.sourceReady or runtime.publicationReady: return # No canonical/request alias is touched while a worker owns exclusion.
  let rpc = runtime.rpc
  assert rpc != nil
  let dispatch = rpc[].takeStateProofRequest()
  if not dispatch.valid: return # No request owns no capacity or graph lease.
  runtime.request = dispatch
  let selected = dispatch.proofRequest
  if selected.isImport:
    if runtime.faulted or (runtime.diskMode and runtime.disk.retirementPending):
      runtime.finishImportReply("Light storage unavailable or retirement pending") # Mutation backpressure never prevents ordinary known-head reads between cleanup attempts.
      return
    let reason = runtime.stageImport(selected.blockHash, selected.importBytes)
    discard runtime.admitImport(reason) # Staging returns only a scalar reason; no captured request alias remains live here.
  else:
    let limits = runtime.policy.query # Capture fixed policy values before mutably staging the actor.
    let reason = runtime.stageQuery(selected.blockHash, selected.plan, limits)
    let admitted = runtime.admitQuery(reason)
    if admitted.error != LightRuntimeError.None:
      assert rpc != nil # Refused admission retained the same stable borrowed listener.
      discard rpc[].finishStateProof(dispatch, runtime.current.stateRoot, newSeq[byte](0),
          "Light block or proof request unavailable") # No worker borrowed any canonical graph.
      runtime.request = default(RpcProofDispatch)
proc tick*(runtime: var LightRuntime, peers: uint32) =
  ## One bounded actor turn performs no native storage IO or cryptographic proof verification on the dispatcher.
  if not runtime.started: return # Closed/default actors own no listener work.
  if runtime.cpuBusy:
    if runtime.cpu.phase != ProofWorkerPhase.Done: return # Only synchronized scalar state may be observed during native CPU borrowing.
    if runtime.cpuOperation == CpuOperation.Import:
      runtime.collectImport() # Its batch/completion activation retires before possible disk admission below.
    elif runtime.request.valid:
      runtime.collectRpcQuery() # SDK-owned query tickets retain their lease until explicit caller collection.
    else:
      return # External caller still owns exact collection authority.
  if runtime.ioBusy:
    if runtime.io.phase != DiskWorkerPhase.Done: return # No shared snapshot/cache/RPC aliases may retire yet.
    runtime.collectDisk() # This entire outcome activation retires before another native admission.
  if runtime.publicationReady:
    discard runtime.admitPublication()
    return # Only scalar/ticket work follows a successful native borrow.
  if runtime.diskMode and not runtime.faulted and runtime.disk.retirementPending and
      runtime.retirementDue():
    if runtime.stageRetirement() and runtime.admitRetirement(): return # Prepared-job activation retired before submission; Busy retries are spaced separately.
  let rpc = runtime.rpc
  assert rpc != nil
  rpc[].tick(peers) # Detached transport metadata owns no partial application proof graph.
  runtime.beginRpcRequest() # Transport callbacks and contexts have retired before CPU admission.
proc diskCompletion*(runtime: LightRuntime): DiskPublicationCompletion {.requires: not runtime.busy.} =
  ## Last actual worker outcome survives joined close; staging without worker admission never fabricates a new IO receipt.
  runtime.lastDisk

func proofActive*(runtime: LightRuntime): bool =
  ## Both imported and ordinary query outcomes retain the same CPU exclusion through Done.
  runtime.cpuBusy
func diskActive*(runtime: LightRuntime): bool =
  ## Scalar native IO observation grants no snapshot or completion payload.
  runtime.ioBusy
proc stopProofs*(runtime: var LightRuntime) =
  ## Joined CPU shutdown may discard CPU-only results without releasing an active disk lease.
  runtime.cpu.close()
  if runtime.cpuBusy:
    runtime.cpuBusy = false
    runtime.releaseLease() # Only the CPU operation owned this lease; IO cannot run concurrently.
    let rpc = runtime.rpc
    if rpc != nil and runtime.request.valid:
      if runtime.request.proofRequest.isImport: runtime.finishImportReply(
          "Light proof import stopped") # No imported facts were adopted.
      else:
        discard rpc[].finishStateProof(runtime.request, runtime.current.stateRoot, newSeq[byte](0), "Light proof request stopped")
        runtime.request = default(RpcProofDispatch)
proc stopDisk*(runtime: var LightRuntime) =
  ## Entered native IO keeps its actual outcome; explicit backend shutdown disables future writes until fresh startup.
  let completion = runtime.io.close
  if runtime.ioBusy: runtime.finishDisk(completion) # Join precedes all current/source/cache access.
  if runtime.diskMode: runtime.faulted = true # Read-only immutable evidence remains independently usable.
