# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable source-bound CE139/140 progress authenticates each proven packet before threshold reconstruction.
## Only detached request facts leave the shared graph; all packet/import owners remain under the managed worker lease.
import ./[work_submission, import_recovery, availability_proof, availability_merkle, read_stream]
import ./endpoints
import ../chain/[provider, genesis, import_catalog]
import ../state/store
import ../state/erasure/[layout, words]
import "../state/export/erasure" as export_erasure
import "../state/import/inputs" as import_inputs
import "../state/import/justification" as import_proof
import ../codec/bounded
from ../codec/work/package import ImportKind
from ../codec/work/report import BundleLength
from ../codec/state/safrole import StateValidatorIndex, StateEdKey

type
  WorkRecoveryLimits* = object ## Whole-session reservations cover both recovery attempts per import and every possible proven packet check.
    catalog*: ImportCatalogLimits
    pair*: ImportRecoveryLimits
    transfer*: AvailabilityMerkleLimits
    items*, requests*, dials*, hashes*, peersPerPoll*: ElementLimit
    bytes*, hashBytes*, replyBytes*: ByteLimit
    products*: FieldProductLimit
    timeoutMs*: int
  WorkRecoveryPolicy* = object ## Default policy cannot capture canonical catalogs or activate fallback network work.
    ready: bool
    limits: WorkRecoveryLimits
  WorkRecoveryError* {.pure.} = enum ## Failed/default steps carry no successfully reconstructed or accepted prefix.
    Uninitialized, None, InvalidSource, InvalidIndex, InvalidPacket, LimitExceeded,
      CatalogFailure, TransferFailure, ReconstructionFailure, BindingFailure, InvalidErasureRoot
  WorkRecoveryResult*[T] = object ## Preserve genuine selected child failures without exposing successful partial state.
    case status: WorkRecoveryError
    of None: completed: T
    of CatalogFailure: catalogReason: ImportCatalogError
    of TransferFailure: transferReason: AvailabilityTransferResult[VerifiedAvailabilityTransfer]
    of ReconstructionFailure, InvalidErasureRoot: recoveryReason: ImportRecoveryResult
    of BindingFailure: bindingReason: WorkSubmissionResult[VerifiedImportInputs]
    else: discard # Local refusals retain only their selected reason.
  RecoveryPacket = ref object ## One detached row pair is immutable; proven packets are created only after both original-coordinate verifications.
    shard: ErasureShardIndex
    bytes: seq[byte]
  RecoveryPlan = ref object ## Original grant plan, exact selected catalog and canonical source occurrences cannot be replaced between packets.
    original: WorkImportPlan
    entries: seq[WorkImportEntry]
    sources: seq[ReportedImport]
    policy: WorkRecoveryPolicy
  RecoveryData = ref object ## New steps copy only bounded descriptors, sharing immutable packet/import children without retaining a chain of old progress.
    plan: RecoveryPlan
    cursor: int
    version: uint64
    proven: bool
    packets: seq[RecoveryPacket]
    imports: seq[VerifiedImport]
  WorkRecovery* = object ## Only a complete source capture or genuine next step constructs usable progress.
    data: nil RecoveryData
  WorkRecoveryInfo* = object ## Fixed scalar state is safe to cache through a foreign graph lease.
    version*: uint64
    occurrence*, occurrences*, population*, threshold*, packets*: int
    proven*, complete*: bool
  WorkRecoveryRequest* = object ## Detached bytes and expected original identity grant no source or stream authority.
    version*: uint64
    validator*: StateValidatorIndex
    identity*: StateEdKey
    endpoint*: EndpointResult
    request*: ReadRequest
    maximum*: ByteLimit
func error*[T](outcome: WorkRecoveryResult[T]): WorkRecoveryError =
  ## Inspect a selected reason without a writable discriminator.
  outcome.status
func value*[T](outcome: WorkRecoveryResult[T]): T {.requires: outcome.status ==
    WorkRecoveryError.None.} =
  ## Extract only a completely selected source, progress or input table.
  outcome.completed
func catalogError*[T](outcome: WorkRecoveryResult[
    T]): ImportCatalogError {.requires: outcome.status == WorkRecoveryError.CatalogFailure.} =
  ## Preserve the exact original selected-chain catalog refusal.
  outcome.catalogReason
func transferError*[T](outcome: WorkRecoveryResult[T]): AvailabilityTransferResult[
    VerifiedAvailabilityTransfer] {.requires: outcome.status ==
    WorkRecoveryError.TransferFailure.} =
  ## Preserve the genuine failed independent-coordinate verifier, with its original backend/Merkle cause.
  outcome.transferReason
func reconstructionError*[T](outcome: WorkRecoveryResult[
    T]): ImportRecoveryResult {.requires: outcome.status in {
    WorkRecoveryError.ReconstructionFailure, WorkRecoveryError.InvalidErasureRoot}.} =
  ## Only a genuine reconstruction refusal can be extracted; invalid-root classification additionally requires proven packets.
  outcome.recoveryReason
func bindingError*[T](outcome: WorkRecoveryResult[T]): WorkSubmissionResult[
    VerifiedImportInputs] {.requires: outcome.status == WorkRecoveryError.BindingFailure.} =
  ## Complete package binding retains its real original verifier cause.
  outcome.bindingReason
func failure[T](reason: WorkRecoveryError): WorkRecoveryResult[T] {.requires: reason in {
    WorkRecoveryError.Uninitialized, WorkRecoveryError.InvalidSource,
        WorkRecoveryError.InvalidIndex,
    WorkRecoveryError.InvalidPacket, WorkRecoveryError.LimitExceeded}.} =
  ## A local refusal cannot fabricate a child result or progress owner.
  WorkRecoveryResult[T](status: reason)
func workRecoveryPolicy*(limits: WorkRecoveryLimits): WorkRecoveryPolicy =
  ## Activation requires explicit finite network and computation ceilings; no guessed defaults enable recovery.
  if uint64(limits.items) == 0 or uint64(limits.items) > 3072: return default(WorkRecoveryPolicy)
  if uint64(limits.requests) == 0 or uint64(limits.requests) > 6285312: return default(WorkRecoveryPolicy)
  if uint64(limits.dials) == 0 or uint64(limits.dials) > 6285312: return default(WorkRecoveryPolicy)
  if uint64(limits.peersPerPoll) == 0 or uint64(limits.peersPerPoll) > 1023: return default(WorkRecoveryPolicy)
  if uint64(limits.replyBytes) < 12 or uint64(limits.replyBytes) > 32'u64*1024*1024: return default(WorkRecoveryPolicy)
  if limits.timeoutMs < 1 or limits.timeoutMs > 120000: return default(WorkRecoveryPolicy)
  if uint64(limits.bytes) == 0 or uint64(limits.hashes) == 0 or uint64(limits.hashBytes) == 0:
    return default(WorkRecoveryPolicy)
  WorkRecoveryPolicy(ready: true, limits: limits)
func valid*(policy: WorkRecoveryPolicy): bool =
  ## A default value confers no recovery admission authority.
  policy.ready
func limits*(policy: WorkRecoveryPolicy): WorkRecoveryLimits {.requires: policy.ready.} =
  ## Copy fixed independent local caps while retaining no canonical or logging alias.
  policy.limits
func reserve(total: var uint64, count, each, maximum: uint64): bool =
  ## Check multiplication and aggregate addition before doing either operation.
  if total > maximum: return false
  if count != 0 and each > (maximum-total) div count: return false
  total += count*each
  true
proc beginWorkRecovery*(original: WorkImportPlan, view: ChainView,
    policy: WorkRecoveryPolicy): WorkRecoveryResult[WorkRecovery] =
  ## Bind the exact original authorization map before any catalog capture, allocation or source selection.
  if not policy.valid: return failure[WorkRecovery](WorkRecoveryError.InvalidSource)
  let head = view.bestBlock
  if head.error != GenesisError.None: return failure[WorkRecovery](WorkRecoveryError.InvalidSource)
  if not original.importPlanStateMatches(head.value.stateSnapshot): return failure[WorkRecovery](
      WorkRecoveryError.InvalidSource)
  let shape = original.importPlanShape
  if shape.error != WorkSubmissionError.None: return failure[WorkRecovery](
      WorkRecoveryError.InvalidSource)
  if uint64(shape.value.entries) > uint64(policy.limits.items): return failure[WorkRecovery](
      WorkRecoveryError.LimitExceeded)
  let entries = original.importPlanEntries
  if entries.error != WorkSubmissionError.None: return failure[WorkRecovery](
      WorkRecoveryError.InvalidSource)
  let limits = policy.limits
  if uint64(entries.value.len) > uint64(limits.items): return failure[WorkRecovery](
      WorkRecoveryError.LimitExceeded)
  var products = 0'u64
  var hashes = 0'u64
  var hashBytes = 0'u64
  if not reserve(products, uint64(entries.value.len)*2, uint64(limits.pair.products), uint64(
      limits.products)):
    return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
  if not reserve(hashes, uint64(entries.value.len)*2, uint64(limits.pair.hashes), uint64(
      limits.hashes)):
    return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
  if not reserve(hashes, uint64(limits.requests)*2, uint64(limits.transfer.hashes), uint64(
      limits.hashes)):
    return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
  if not reserve(hashBytes, uint64(entries.value.len)*2, uint64(limits.pair.hashBytes), uint64(
      limits.hashBytes)):
    return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
  if not reserve(hashBytes, uint64(limits.requests)*2, uint64(limits.transfer.hashBytes), uint64(
      limits.hashBytes)):
    return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
  let catalog = captureImportCatalog(view, limits.catalog)
  if catalog.error != ImportCatalogError.None:
    return WorkRecoveryResult[WorkRecovery](status: WorkRecoveryError.CatalogFailure,
        catalogReason: catalog.error)
  var sources = newSeq[ReportedImport](entries.value.len)
  var attempts = 0'u64
  for index in 0..<sources.len:
    # The original nominal reference determines whether package identity must also match the independently known export root.
    let entry = entries.value[index]
    let selected = if entry.reference.kind == ImportKind.Package:
      catalog.value.catalogPackageImport(entry.reference.package, entry.root)
    else: catalog.value.catalogImport(entry.root)
    if selected.error != ImportCatalogError.None:
      return WorkRecoveryResult[WorkRecovery](status: WorkRecoveryError.CatalogFailure,
          catalogReason: selected.error)
    let info = selected.value.reportedImportInfo.value
    if uint16(entry.reference.index) >= uint16(info.specifier.segmentCount):
      return failure[WorkRecovery](WorkRecoveryError.InvalidIndex)
    let geometry = erasureGeometry(BundleLength(4104), info.specifier.erasureShards).value
    if not reserve(attempts, uint64(uint16(info.specifier.erasureShards))*2, 1, uint64(
        limits.requests)):
      return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
    if uint64(limits.replyBytes) < 12+geometry.segmentChunkBytes*2:
      return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
    var bytes = 0'u64
    if not reserve(bytes, uint64(sources.len), 4488, uint64(limits.bytes)):
      return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
    if not reserve(bytes, geometry.originalShards+1, uint64(limits.replyBytes), uint64(limits.bytes)):
      return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
    if not reserve(bytes, 1, uint64(limits.pair.bytes), uint64(limits.bytes)):
      return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
    if not reserve(bytes, 2, uint64(limits.transfer.bytes), uint64(limits.bytes)):
      return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
    if not reserve(bytes, 1, 8208, uint64(limits.bytes)):
      return failure[WorkRecovery](WorkRecoveryError.LimitExceeded)
    sources[index] = selected.value
  WorkRecoveryResult[WorkRecovery](status: WorkRecoveryError.None, completed: WorkRecovery(
    data: RecoveryData(
    plan: RecoveryPlan(original: original, entries: entries.value, sources: sources,
        policy: policy),
    cursor: 0, version: 1, packets: @[], imports: @[])))
proc recoveryMatches*(recovery: WorkRecovery, grant: AuthorizedWorkSubmission): bool =
  ## An exact grant, not a replacement source with identical bytes, owns every later packet and completion job.
  let data = recovery.data
  if data == nil: return false
  data.plan.original.importPlanMatches(grant)
proc recoveryPolicy*(recovery: WorkRecovery): WorkRecoveryPolicy =
  ## Copy only immutable numeric policies while the caller owns canonical graph access.
  let data = recovery.data
  if data == nil: return default(WorkRecoveryPolicy)
  data.plan.policy
func peerRejected*(outcome: WorkRecoveryResult[WorkRecovery]): bool =
  ## Only malformed or cryptographically incorrect remote data is retryable; local budget/backend/source failures are fatal.
  if outcome.status == WorkRecoveryError.InvalidPacket: return true
  if outcome.status != WorkRecoveryError.TransferFailure: return false
  if outcome.transferReason.error == AvailabilityTransferError.MerkleFailure:
    return outcome.transferReason.merkleError in [AvailabilityMerkleError.InvalidProof,
        AvailabilityMerkleError.RootMismatch]
  outcome.transferReason.error in [AvailabilityTransferError.InvalidPayload,
    AvailabilityTransferError.InvalidProof, AvailabilityTransferError.RootMismatch]
proc recoveryInfo*(recovery: WorkRecovery): WorkRecoveryResult[WorkRecoveryInfo] =
  ## Fixed copied geometry does not expose packet bytes, original grants or source-bearing handles.
  let data = recovery.data
  if data == nil: return failure[WorkRecoveryInfo](WorkRecoveryError.Uninitialized)
  var info = WorkRecoveryInfo(version: data.version, occurrence: data.cursor,
    occurrences: data.plan.entries.len, packets: data.packets.len, proven: data.proven,
    complete: data.cursor == data.plan.entries.len)
  if not info.complete:
    let source = data.plan.sources[data.cursor].reportedImportInfo.value.specifier
    info.population = int(uint16(source.erasureShards))
    info.threshold = int(erasureGeometry(BundleLength(4104),
        source.erasureShards).value.originalShards)
  WorkRecoveryResult[WorkRecoveryInfo](status: WorkRecoveryError.None, completed: info)
proc recoveryRequest*(recovery: WorkRecovery, validator: StateValidatorIndex): WorkRecoveryResult[
    WorkRecoveryRequest] =
  ## Select one original assurer and its exact two-row coordinates; callbacks receive only copied raw selector bytes.
  let data = recovery.data
  if data == nil: return failure[WorkRecoveryRequest](WorkRecoveryError.Uninitialized)
  if data.cursor >= data.plan.entries.len: return failure[WorkRecoveryRequest](
      WorkRecoveryError.InvalidIndex)
  let source = data.plan.sources[data.cursor]
  let assigned = source.importAssurer(validator)
  if assigned.error != ImportCatalogError.None: return failure[WorkRecoveryRequest](
      WorkRecoveryError.InvalidIndex)
  for index in 0..<data.packets.len:
    if uint64(data.packets[index].shard) == uint64(assigned.value.shard):
      return failure[WorkRecoveryRequest](WorkRecoveryError.InvalidIndex)
  let facts = source.reportedImportInfo.value.specifier
  let ordinal = uint16(data.plan.entries[data.cursor].reference.index)
  let page = uint16(facts.segmentCount)+ordinal div 64
  var wire = newSeq[byte](39)
  for index in 0..<32: wire[index] = facts.erasureRoot.bytes[index]
  let shard = uint16(uint64(assigned.value.shard))
  wire[32] = byte(shard and 255)
  wire[33] = byte(shard shr 8)
  wire[34] = 2
  wire[35] = byte(ordinal and 255)
  wire[36] = byte(ordinal shr 8)
  wire[37] = byte(page and 255)
  wire[38] = byte(page shr 8)
  let kind = if data.proven: ReadKind.ProvenSegmentShards else: ReadKind.SegmentShards
  let request = decodeReadRequest(kind, wire)
  if request.error != ReadError.None: return failure[WorkRecoveryRequest](
      WorkRecoveryError.InvalidPacket)
  WorkRecoveryResult[WorkRecoveryRequest](status: WorkRecoveryError.None,
    completed: WorkRecoveryRequest(
    version: data.version, validator: validator, identity: assigned.value.identity,
    endpoint: validatorEndpoint(array[128, byte](assigned.value.metadata)),
    request: request.value, maximum: data.plan.policy.limits.replyBytes))
proc messageLength(wire: openArray[byte], offset: int): uint64 {.requires: offset >= 0 and offset <= wire.len-4.} =
  ## Read E4 only after the complete prefix extent has been proved.
  uint64(wire[offset]) or (uint64(wire[offset+1]) shl 8) or (uint64(wire[offset+2]) shl 16) or (
      uint64(wire[offset+3]) shl 24)
proc acceptRecoveryPacket*(recovery: WorkRecovery, version: uint64, validator: StateValidatorIndex,
    wire: openArray[byte]): WorkRecoveryResult[WorkRecovery] =
  ## Validate one complete response against the original private source and append immutable chunks only after full success.
  let data = recovery.data
  if data == nil: return failure[WorkRecovery](WorkRecoveryError.Uninitialized)
  if version != data.version or data.version == high(uint64): return failure[WorkRecovery](
      WorkRecoveryError.InvalidSource)
  let requested = recovery.recoveryRequest(validator)
  if requested.error != WorkRecoveryError.None: return failure[WorkRecovery](requested.error)
  let limits = data.plan.policy.limits
  if uint64(wire.len) > uint64(limits.replyBytes): return failure[WorkRecovery](
      WorkRecoveryError.LimitExceeded)
  let source = data.plan.sources[data.cursor]
  let facts = source.reportedImportInfo.value.specifier
  let width = int(erasureGeometry(BundleLength(4104), facts.erasureShards).value.segmentChunkBytes)
  if wire.len < 4 or messageLength(wire, 0) != uint64(width*2): return failure[WorkRecovery](
      WorkRecoveryError.InvalidPacket)
  if wire.len-4 < width*2: return failure[WorkRecovery](WorkRecoveryError.InvalidPacket)
  var cursor = 4+width*2
  let assigned = source.importAssurer(validator).value
  var starts = default(array[2, int])
  var sizes = default(array[2, int])
  if data.proven:
    for row in 0..<2:
      # Validate every E4 extent and the complete suffix before any proof hash or retained packet allocation.
      if wire.len-cursor < 4: return failure[WorkRecovery](WorkRecoveryError.InvalidPacket)
      let size = messageLength(wire, cursor)
      cursor += 4
      if size > uint64(wire.len-cursor): return failure[WorkRecovery](
          WorkRecoveryError.InvalidPacket)
      starts[row] = cursor
      sizes[row] = int(size)
      cursor += int(size)
  if cursor != wire.len: return failure[WorkRecovery](WorkRecoveryError.InvalidPacket)
  if data.proven:
    for row in 0..<2:
      # Each independent source-coordinate proof must verify before either piece contributes to retained proven progress.
      let ordinal = uint64(uint16(data.plan.entries[data.cursor].reference.index))
      let selectedRow = if row == 0: ordinal else: uint64(uint16(facts.segmentCount))+ordinal div 64
      let request = AvailabilityRequest(kind: AvailabilityTransferKind.Segment,
        root: facts.erasureRoot,
        shard: assigned.shard, row: ExportErasureIndex(selectedRow))
      let checked = verifyAvailabilityTransfer(facts, request, [], wire.toOpenArray(4+row*width, 4+(
          row+1)*width-1),
        wire.toOpenArray(starts[row], starts[row]+sizes[row]-1), limits.transfer)
      if checked.error != AvailabilityTransferError.None:
        return WorkRecoveryResult[WorkRecovery](status: WorkRecoveryError.TransferFailure,
            transferReason: checked)
  var bytes = newSeq[byte](width*2)
  for index in 0..<bytes.len: bytes[index] = wire[4+index]
  var packets: seq[RecoveryPacket] = @[]
  for index in 0..<data.packets.len: packets.add(data.packets[index])
  packets.add(RecoveryPacket(shard: assigned.shard, bytes: bytes))
  var imports = newSeq[VerifiedImport](data.imports.len)
  for index in 0..<imports.len: imports[index] = data.imports[index]
  var cursorImport = data.cursor
  var proven = data.proven
  let threshold = int(erasureGeometry(BundleLength(4104), facts.erasureShards).value.originalShards)
  if packets.len == threshold:
    var segments = newSeq[byte](4104)
    var pages = newSeq[byte](4104)
    var indices = newSeq[ErasureShardIndex](threshold)
    for index in 0..<threshold:
      # Complete equal-width threshold matrices preserve shard coordinates independently of response arrival order.
      indices[index] = packets[index].shard
      for position in 0..<width:
        segments[index*width+position] = packets[index].bytes[position]
        pages[index*width+position] = packets[index].bytes[width+position]
    let recovered = recoverImport(source, data.plan.entries[data.cursor].reference.index,
      segments, pages, indices, limits.pair)
    if recovered.error == ImportRecoveryError.None:
      imports.add(recovered.value)
      inc cursorImport
      proven = false
    elif recovered.error == ImportRecoveryError.ReconstructionMismatch or
        (recovered.error == ImportRecoveryError.ProofFailure and recovered.proofError ==
            ImportJustificationError.RootMismatch):
      if data.proven:
        return WorkRecoveryResult[WorkRecovery](status: WorkRecoveryError.InvalidErasureRoot,
            recoveryReason: recovered)
      proven = true # Drop every unproven packet and reconstruct the same original occurrence again with CE140.
    else:
      return WorkRecoveryResult[WorkRecovery](status: WorkRecoveryError.ReconstructionFailure,
          recoveryReason: recovered)
    packets = @[]
  WorkRecoveryResult[WorkRecovery](status: WorkRecoveryError.None, completed: WorkRecovery(
    data: RecoveryData(
    plan: data.plan, cursor: cursorImport, version: data.version+1, proven: proven,
    packets: packets, imports: imports)))
proc retryRecoveryProven*(recovery: WorkRecovery): WorkRecoveryResult[WorkRecovery] =
  ## Exhausted unproven responders can retry the same original occurrence with proofs; no unproven packet crosses this boundary.
  let data = recovery.data
  if data == nil: return failure[WorkRecovery](WorkRecoveryError.Uninitialized)
  if data.proven or data.cursor >= data.plan.entries.len or data.version == high(uint64):
    return failure[WorkRecovery](WorkRecoveryError.InvalidSource)
  var imports = newSeq[VerifiedImport](data.imports.len)
  for index in 0..<imports.len: imports[index] = data.imports[index]
  WorkRecoveryResult[WorkRecovery](status: WorkRecoveryError.None, completed: WorkRecovery(
    data: RecoveryData(
    plan: data.plan, cursor: data.cursor, version: data.version+1, proven: true, packets: @[],
        imports: imports)))
proc completeRecoveredWork*(recovery: WorkRecovery, grant: AuthorizedWorkSubmission,
    extrinsics: openArray[byte], limits: WorkSubmissionLimits): WorkRecoveryResult[
        VerifiedImportInputs] =
  ## Only complete original-plan recovery can bind all original rows and feed actual refinement.
  let data = recovery.data
  if data == nil: return failure[VerifiedImportInputs](WorkRecoveryError.Uninitialized)
  if not data.plan.original.importPlanMatches(grant): return failure[VerifiedImportInputs](
      WorkRecoveryError.InvalidSource)
  if data.cursor != data.plan.entries.len: return failure[VerifiedImportInputs](
      WorkRecoveryError.InvalidSource)
  let shape = data.plan.original.importPlanShape.value
  var rows = newSeq[seq[VerifiedImport]](shape.items)
  for index in 0..<data.plan.entries.len:
    # Manifest occurrence order binds complete rows, including original trailing/empty work-item rows.
    let entry = data.plan.entries[index]
    rows[entry.item].add(data.imports[index])
  let completed = completePackageSubmission(grant, extrinsics, rows,
    data.plan.original.importPlanLookup.value, limits)
  if completed.error != WorkSubmissionError.None:
    return WorkRecoveryResult[VerifiedImportInputs](status: WorkRecoveryError.BindingFailure,
        bindingReason: completed)
  WorkRecoveryResult[VerifiedImportInputs](status: WorkRecoveryError.None,
      completed: completed.value)
