# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One non-copyable owner for telemetry, RPC, UI and optional explicitly configured canonical state.
## The peer dispatcher borrows individual fields only while this stack owner remains stable;
## transport callbacks must retire before close/destruction. A bounded chain snapshot is shared once.
## After starting preparation, explicitly close to join before any borrowed input or shared alias retires.

import std/[syncio, strutils, base64, assertions]
import ./options
import ./[checkpoint_recovery, checkpoint_trust]
import ./handoff
import ./candidate
import ./block_input
import ./preparation_worker
import ./[disk_chain, disk_worker]
import ./[checkpoint_identity, checkpoint_transfer, checkpoint_session, checkpoint_worker, checkpoint_file]
import ../codec/bounded
import ../crypto/primitives
import ../codec/[block_codec, header, state_trie]
import ./chain as application_chain
import ../state/[store, disk_store, accumulation_finalization, accumulation_completion, accumulation_publication]
import ../storage/[file_repository, node_repository, node_records, record_codec, database_identity]
import ../chain/provider
import ../telemetry/[wire, client, chain]
import ../quic/transport
import ../rpc/[server, protocol]
import ../chain/[parameters, genesis]
import ../ui/server

type Services* = object ## Owns listeners/exporter; fields are borrowed by synchronous peer callbacks.
  rpc*: Server
  ui*: UiServer
  telemetry*: Client
  chainText: string
  canonical: ApplicationChain
  adoption: AccumulationHandoff
  worker: PreparationWorker
  checkpointExport: ApplicationCheckpointSession
  rpcLease: nil RpcChainLease
  preparing: bool
  started, chainRpc: bool
  disk: DiskStateStore
  diskWorker: DiskPublicationWorker
  diskPublication: PreparedDiskPublication
  diskTicket: DiskPublicationTicket
  diskStageOutcome: DiskChainResult[PreparedDiskPublication]
  diskCommitOutcome: DiskChainResult[RepositoryGeneration]
  diskId: StorageChainId
  diskLimits: JournalLimits
  diskEnabled, publishing, diskFaulted: bool

proc `=wasMoved`*(services: var Services) {.nodestroy, inline, requires: not services.started.} =
  ## Only closed aggregates may relocate; native workers and callback borrows require the original stable parent address.
  `=wasMoved`(services.diskWorker)
  `=wasMoved`(services.disk)
  `=wasMoved`(services.diskPublication)
  `=wasMoved`(services.diskTicket)
  `=wasMoved`(services.diskStageOutcome)
  `=wasMoved`(services.diskCommitOutcome)
  `=wasMoved`(services.checkpointExport)
  `=wasMoved`(services.worker)
  `=wasMoved`(services.rpcLease)
  `=wasMoved`(services.ui)
  `=wasMoved`(services.rpc)
  `=wasMoved`(services.telemetry)
  `=wasMoved`(services.chainText)
  `=wasMoved`(services.canonical)
  `=wasMoved`(services.adoption)

proc `=copy`*(destination: var Services, source: Services) {.error: "Application Services owns descriptors".}
proc `=dup`*(source: Services): Services {.error.}
  ## Composite ownership includes the stable worker and all listener lifetimes.
proc `=destroy`*(services: Services) =
  ## Retire partially configured owners and the shared snapshot even without explicit shutdown.
  `=destroy`(services.diskWorker) # Join must precede every disk/canonical/publication alias retirement.
  `=destroy`(services.disk)
  `=destroy`(services.diskPublication)
  `=destroy`(services.diskTicket)
  `=destroy`(services.diskStageOutcome)
  `=destroy`(services.diskCommitOutcome)
  `=destroy`(services.checkpointExport) # Explicit close joins the detached I/O child before aggregate destruction.
  `=destroy`(services.worker) # Explicit close must join before any shared chain alias retires.
  `=destroy`(services.rpcLease)
  `=destroy`(services.ui)
  `=destroy`(services.rpc)
  `=destroy`(services.telemetry)
  `=destroy`(services.chainText)
  `=destroy`(services.canonical)
  `=destroy`(services.adoption)

proc finishDiskPublication(services: var Services, completion: DiskPublicationCompletion) =
  ## Called only after collect/join retires all native temporaries; install before reopening RPC access.
  if not services.publishing: return
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
  let completion = services.diskWorker.close()
  services.finishDiskPublication(completion)
  if services.diskEnabled: services.diskFaulted = true # Explicit backend shutdown requires a fresh startup before more writes.
func diskPublicationActive*(services: Services): bool =
  ## Scalar-only observation is permitted while canonical graphs remain exclusively borrowed.
  services.publishing
func diskPublicationOutcome*(services: Services): DiskChainResult[RepositoryGeneration] {.requires:
    not services.preparing and not services.publishing.} =
  ## Preserve the actual last IO receipt, including across close, until a later startup/job replaces it.
  services.diskCommitOutcome
func diskPreparationOutcome*(services: Services): DiskChainResult[
    PreparedDiskPublication] {.requires:
    not services.preparing and not services.publishing.} =
  ## Failed host staging keeps its own typed context refusal; default means no such failure was recorded.
  services.diskStageOutcome

proc stopPreparation*(services: var Services) =
  ## Join and discard private execution before reopening canonical/RPC access; listeners and canonical state remain owned.
  if services.publishing: return # A disk borrower owns the same RPC lease until its own joined retirement.
  services.worker.close()
  services.preparing = false
  discard services.rpc.resumeChain(services.rpcLease)
  services.rpcLease = nil

proc stopCheckpointExport*(services: var Services) =
  ## Join detached I/O outside callbacks and retain actual uncollected work/retirement uncertainty until explicit acknowledgement.
  services.checkpointExport.close()

proc close*(services: var Services) =
  ## Idempotent retirement happens after every dispatcher/native callback has ended its borrows.
  services.stopCheckpointExport() # Repeated close preserves the fixed joined-outcome journal.
  services.stopDiskPublication() # Commit receipts survive shutdown; joined IO ends all graph borrowing.
  services.stopPreparation() # Join before releasing any canonical or listener alias.
  services.ui.close()
  services.rpc.close()
  services.telemetry.close()
  services.rpc = default(Server) # Server.close retires sockets; replacement also releases its retained history/configuration.
  services.adoption = default(AccumulationHandoff) # Retire pending or unacknowledged immutable owners on shutdown.
  if services.disk.opened: discard services.disk.close
  services.diskEnabled = false
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
  rpc.start(options.rpcPort(), role, parameters, genesis, options.uiPort())

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
  if imported:
    if initializeDiskChain(services.disk, options.stateDatabase, services.diskId,
        services.canonical, services.diskLimits).error != DiskChainError.None: return false
  else:
    let opened = openDiskChain(services.disk, options.stateDatabase, services.diskId,
      seed.value.chainView.bestBlock.value.chainParameters, limits, services.diskLimits)
    if opened.error == DiskChainError.None:
      services.canonical = opened.value # Local restart preserves bounded history and explicit finality.
    else:
      if opened.error != DiskChainError.StoreFailure: return false
      if opened.storeFailure.error != DiskStoreError.FileFailure: return false
      if opened.storeFailure.fileError != FileError.IoFailure: return false
      let created = initializeDiskChain(services.disk, options.stateDatabase, services.diskId,
        services.canonical, services.diskLimits)
      if created.error != DiskChainError.None:
        return false # O_EXCL prevents a failed open from overwriting any existing or concurrently created file.
  services.diskEnabled = true
  services.diskStageOutcome = default(DiskChainResult[PreparedDiskPublication])
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
  if withState:
    if recovered.chainView.retainedCount > 0:
      let configured = configuredParameters(services.chainText)
      let head = recovered.chainView.bestBlock.value
      if not configured.ok or configured.value.encodeParameters !=
          head.chainParameters.encodeParameters:
        services.close() # A trusted anchor must still match the complete explicitly selected chain profile.
        return false
      services.canonical = recovered # Preserve the exact restored map, inherited policy and one-head/unfinalized view.
    else:
      let seeded = initApplicationChain(services.chainText, limits)
      if seeded.error != ApplicationChainError.None:
        services.close() # A missing/refused seed cannot become a partial listener-only startup.
        return false
      services.canonical = seeded.value
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
        options.uiPort())
  else:
    rpcReady = services.rpc.setupRpc(options, role,
        services.chainText) # Preserve legacy optional/unavailable genesis behavior.
  if not rpcReady:
    stderr.writeLine("Invalid RPC listener or --chain parameters")
    services.close() # RPC failures retire both the UI listener and the canonical owner.
    return false
  services.chainRpc = withState and options.rpcPort() != 0
  services.started = true
  true

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
  var limits = genesisStoreLimits()
  if options.stateEnabled:
    limits.writes = options.stateWrites # Fixed trie ceilings never imply a mutable budget.
    limits.writeValueBytes = options.stateWriteBytes
    return startConfigured(services, options, role, true, limits)
  startConfigured(services, options, role, false, limits)

proc start*(services: var Services, options: Options, role: string,
    limits: StateStoreLimits): bool {.raises.} =
  ## Explicitly enable canonical complete-state ownership, sharing the exact seed with optional RPC.
  startConfigured(services, options, role, true, limits)

proc startRecovered*(services: var Services, options: Options, role: string,
    recovered: ApplicationRecoveryResult): bool {.raises.} =
  ## Explicit component recovery preserves its caller-selected map policy, like the existing explicit-limits startup overload.
  ## CLI recovery must restore with its parsed policy before calling this entry point; no map policy is widened here.
  if services.started or not options.valid or not options.stateEnabled:
    return false # Failed/repeated admission must not read files or disturb active services.
  if recovered.error != ApplicationRecoveryError.None:
    return false # Refused/default recovery never falls back to configured genesis.
  startServices(services, options, role, true, genesisStoreLimits(), recovered.value)

func chainView*(services: Services): ChainView {.requires: not services.preparing and
    not services.publishing.} =
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

proc checkpointIdentity*(services: Services): ApplicationCheckpointIdentityResult {.requires: not services.preparing and
    not services.publishing.} =
  ## Capture fixed context only while canonical aliases are available; no file metadata supplies independent trust.
  captureApplicationCheckpointIdentity(services.canonical)
proc prepareCheckpoint*(services: Services, limit: ByteLimit): PreparedApplicationCheckpoint {.requires: not services.preparing and
    not services.publishing.} =
  ## Explicit host-side serialization runs outside callbacks and before any detached I/O admission or execution lease.
  prepareApplicationCheckpoint(services.canonical, limit)

proc stateSnapshot*(services: Services): StateStoreResult[StateStoreSnapshot] {.requires:
    not services.preparing and not services.publishing.} =
  ## Retain only immutable complete state independently of listener lifetime and future adoption.
  services.canonical.stateSnapshot

proc applyAccumulation*(services: var Services, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): ApplicationChainResult[BlockSnapshot] {.requires:
    not services.preparing and not services.publishing.} =
  ## Publish between dispatcher turns using the startup RPC choice; enabled-listener refusal never falls back.
  if services.diskEnabled: return durabilityRequired() # Explicit disk consumers enqueue and poll; dispatcher IO must stay nonblocking.
  if services.chainRpc:
    services.canonical.applyAccumulation(services.rpc, source,
        limits) # Join all three handles before notifications.
  else:
    services.canonical.applyAccumulation(source, limits) # Disabled/default canonical owners still use existing guarded adoption.

func accumulationStage*(services: Services): AccumulationHandoffStage =
  ## Observe producer backpressure independently of optional listener lifetime.
  services.adoption.stage

proc enqueueAccumulation*(services: var Services, source: PreparedFinalAccumulation,
    limits: AccumulationCompositionLimits): AccumulationEnqueueError {.requires:
    not services.preparing and not services.publishing.} =
  ## Hand one finalized candidate to the next dispatcher turn; canonical authority is rechecked at adoption.
  services.adoption.enqueue(services.canonical, source, limits)

proc enqueueCandidate*(services: var Services, candidate: OwnedBlock,
    ancestors: openArray[OwnedHeader], limits: ApplicationCandidateLimits,
    composition: AccumulationCompositionLimits): ApplicationCandidateResult {.requires:
    not services.preparing and not services.publishing.} =
  ## Prepare from this selected head and queue the genuine successor; publication waits for the next service tick.
  services.adoption.enqueueCandidate(services.canonical, candidate, ancestors, limits, composition)

proc beginBlockInput*(services: Services, input: var BlockInput, extent: ByteLimit,
    ancestors: openArray[OwnedHeader], resources: BlockInputLimits,
    policies: ApplicationCandidateLimits): BlockInputAdmission {.requires:
    not services.preparing and not services.publishing.} =
  ## Bind bounded reception to this exact canonical history without preparing or publishing a block.
  input.begin(services.canonical, extent, ancestors, resources, policies)

proc enqueueBlockInput*(services: var Services, input: var BlockInput, id: BlockInputId,
    composition: AccumulationCompositionLimits): BlockInputResult {.requires:
    not services.preparing and not services.publishing.} =
  ## Explicit producer work runs outside transport callbacks; finalized success waits for a later adoption tick.
  input.enqueue(id, services.canonical, services.adoption, composition)

func preparationActive*(services: Services): bool =
  ## Done and cancelled work still retain the canonical exclusion gate until collection or joined close.
  services.preparing

proc preparationAvailable*(services: Services): bool =
  ## Preflight scalar exclusion before reading any canonical handle; no implicit legacy state is permitted.
  if not services.started or services.preparing or services.publishing:
    return false # Existing native work owns all shared graph aliases.
  if services.diskFaulted or services.rpc.chainPaused:
    return false # IO uncertainty or another RPC lease forbids new execution.
  if services.adoption.stage != AccumulationHandoffStage.Idle:
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

proc takeAccumulation*(services: var Services): ApplicationChainResult[BlockSnapshot] {.requires:
    services.accumulationStage == AccumulationHandoffStage.Finished.} =
  ## Acknowledge the exact retained outcome before accepting another candidate.
  services.adoption.take()

proc cancelAccumulation*(services: var Services): bool =
  ## Cancel only unattempted work; finished outcomes still require acknowledgement or explicit shutdown.
  if services.preparing or services.publishing: return false # Active preparation has no pending adoption to cancel.
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
    services.diskId, services.diskLimits.contextBytes)
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

proc tick*(services: var Services, peers: uint32) =
  ## Attempt one pending adoption between native callbacks; exclusive preparation leaves independent UI work available.
  if services.preparing:
    services.ui.tick()
    return # Never create RPC contexts or canonical ARC aliases while the worker owns its lease.
  if services.publishing:
    if services.diskWorker.phase != DiskWorkerPhase.Done:
      services.ui.tick()
      return # Poll only scalar worker state while RPC/canonical graphs remain borrowed.
    services.finishDiskPublication(services.diskWorker.collect(services.diskTicket))
  if services.diskEnabled:
    if services.adoption.stage == AccumulationHandoffStage.Pending and
        services.stageDiskPublication():
      let admitted = services.diskWorker.submit(services.disk, services.diskPublication)
      assert admitted.error == DiskWorkerError.None, "private idle disk worker admission"
      services.diskTicket = admitted.value
      services.publishing = true
      services.ui.tick()
      return # No managed canonical/source alias may be touched or retired after successful admission.
  elif services.chainRpc:
    services.adoption.process(services.canonical, services.rpc) # Enabled listener failure remains a completed refusal.
  else:
    services.adoption.process(services.canonical) # No listener is needed for explicit independent adoption.
  services.rpc.tick(peers)
  services.ui.tick()

proc configureTelemetry*(services: var Services, options: Options, certificate: string,
    port: uint16, ipv6: bool): bool {.raises.} =
  ## Register the actual transport identity/address after binding, using the captured chain bytes.
  setupTelemetry(services.telemetry, options, certificate, port, ipv6, services.chainText)

proc stageCheckpointVerification*(services: var Services, expected: ApplicationCheckpointIdentity,
    limits: StateStoreLimits, limit: ByteLimit): ApplicationCheckpointAdmission =
  ## Independent fixed trust and explicit decode budgets require no canonical alias, so verification may run during preparation leases.
  services.checkpointExport.stageVerification(expected, limits, limit)
