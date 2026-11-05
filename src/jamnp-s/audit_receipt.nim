# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole bounded CE144 batches derive every source from the actual retained chain on the managed worker; no authenticated prefix escapes a late refusal or cancellation.
import ./[audits, audit_context, audit_validation, assurance_store]
import ../chain/[genesis, provider]
import ../codec/bounded

type
  AuditReceiptLimits* = object ## Context execution ceilings apply per record; aggregate proof, entropy-hash and retained-context ceilings cover the entire batch before work begins.
    message*: AuditLimits
    context*: AuditContextLimits
    proof*: AuditProofLimits
    retainedBytes*: ByteLimit
  AuditReceiptError* {.pure.} = enum ## Actual selected decoder/context/proof failures remain distinct from cancellation and local reservation refusal.
    Uninitialized, None, InvalidPolicy, InvalidSource, LimitExceeded, InvalidIndex, Cancelled,
    DecodeFailure, ContextFailure, ProofFailure
  AnnouncementData = ref object ## One immutable acyclic owner retains only wholly checked source-free records, never a canonical map or failed prefix.
    records: seq[CheckedAuditAnnouncement]
  CheckedAuditBatch* = object ## Only whole source/role/proof qualification can construct this batch.
    data: nil AnnouncementData
  AuditReceiptResult*[T] = object ## Failure alternatives retain diagnostics only, with no partial accepted collection.
    case status: AuditReceiptError
    of None: completed: T
    of DecodeFailure: decodeReason: AuditError
    of ContextFailure: contextReason: AuditContextResult[AuditContext]
    of ProofFailure: proofReason: AuditValidationResult[CheckedAuditAnnouncement]
    else: discard # Defaults and ordinary resource/cancellation refusals have no success payload.
func error*[T](outcome: AuditReceiptResult[T]): AuditReceiptError =
  ## Observe a selected reason before extracting its payload.
  outcome.status
func value*[T](outcome: AuditReceiptResult[T]): T {.requires: outcome.status ==
    AuditReceiptError.None.} =
  ## Only complete successful batches or record lookups expose retained ownership.
  outcome.completed
func decodeError*[T](outcome: AuditReceiptResult[T]): AuditError {.requires: outcome.status ==
    AuditReceiptError.DecodeFailure.} =
  ## Preserve the actual whole-message structural refusal.
  outcome.decodeReason
func contextError*[T](outcome: AuditReceiptResult[T]): AuditContextResult[
    AuditContext] {.requires: outcome.status == AuditReceiptError.ContextFailure.} =
  ## Unknown/pruned/header-only sources retain their exact cause without fabricated available work.
  outcome.contextReason
func proofError*[T](outcome: AuditReceiptResult[T]): AuditValidationResult[
    CheckedAuditAnnouncement] {.requires: outcome.status == AuditReceiptError.ProofFailure.} =
  ## Preserve the actual original-key proof refusal or unapproved later-tranche gate.
  outcome.proofReason
func valid*(limits: AuditReceiptLimits): bool =
  ## At most sixteen bounded private consensus-prefix executions occur per job; omission activates no receipt.
  limits.context.valid and limits.proof.valid and limits.message.valid and
    uint64(limits.message.cores) == uint64(limits.context.admission.frame.cores) and
    uint64(limits.message.validators) == uint64(limits.context.availability.rosters.validators) and
    uint64(limits.message.records) in
      1'u64..16'u64 and
    uint64(limits.message.bytes) > 0 and uint64(limits.message.bytes) <= 16'u64*133 and
    uint64(limits.retainedBytes) > 0 and uint64(limits.retainedBytes) <= 256'u64*1024*1024
proc len*(batch: CheckedAuditBatch): int =
  ## A default handle has no accepted records or initialized empty-batch authority.
  let data = batch.data
  if data == nil: return 0
  data.records.len
func valid*(batch: CheckedAuditBatch): bool =
  ## Successful empty input remains distinguishable from a default handle.
  batch.data != nil
proc announcementAt*(batch: CheckedAuditBatch, ordinal: int): AuditReceiptResult[
    CheckedAuditAnnouncement] =
  ## Return an immutable checked record without exporting the mutable backing sequence.
  let data = batch.data
  if data == nil: return AuditReceiptResult[CheckedAuditAnnouncement](
      status: AuditReceiptError.Uninitialized)
  if ordinal < 0 or ordinal >= data.records.len:
    return AuditReceiptResult[CheckedAuditAnnouncement](status: AuditReceiptError.InvalidIndex)
  AuditReceiptResult[CheckedAuditAnnouncement](status: AuditReceiptError.None,
      completed: data.records[ordinal])
proc qualifyAuditAnnouncements*(source: ChainView, wire: openArray[byte],
    limits: AuditReceiptLimits, control: AssuranceScanControl = default(
        AssuranceScanControl)): AuditReceiptResult[CheckedAuditBatch] =
  ## Decode the entire message and reserve all possible retained outputs and crypto before executing any record; cancellation discards the entire private batch.
  if not limits.valid: return AuditReceiptResult[CheckedAuditBatch](
      status: AuditReceiptError.InvalidPolicy)
  if source.fuzzOnly or source.bestBlock.error != GenesisError.None:
    return AuditReceiptResult[CheckedAuditBatch](status: AuditReceiptError.InvalidSource)
  if control.stopped: return AuditReceiptResult[CheckedAuditBatch](
      status: AuditReceiptError.Cancelled)
  let decoded = decodeAnnouncements(wire, limits.message)
  if decoded.error != AuditError.None:
    return AuditReceiptResult[CheckedAuditBatch](status: AuditReceiptError.DecodeFailure,
        decodeReason: decoded.error)
  let count = uint64(decoded.value.len)
  # The decoder proves count <=16; division avoids unchecked multiplication of caller-configured context byte ceilings.
  if count > uint64(limits.proof.proofs) or count*2 > uint64(limits.proof.hashes) or
      count*72 > uint64(limits.proof.hashBytes):
    return AuditReceiptResult[CheckedAuditBatch](status: AuditReceiptError.LimitExceeded)
  if count > 0 and (uint64(limits.retainedBytes) div count < 1024 or
      uint64(limits.context.outputBytes) > uint64(limits.retainedBytes) div count-1024):
    return AuditReceiptResult[CheckedAuditBatch](status: AuditReceiptError.LimitExceeded)
  var records = newSeq[CheckedAuditAnnouncement](decoded.value.len)
  for ordinal in 0..<records.len:
    # Every occurrence retains its own original source. Headers and original ordinals may differ within one protocol message.
    if control.stopped: return AuditReceiptResult[CheckedAuditBatch](
        status: AuditReceiptError.Cancelled)
    let claim = decoded.value.announcementAt(ordinal).value
    let context = captureAuditContext(source, genesis.BlockHash(array[32, byte](claim.header)),
        limits.context, control)
    if context.error == AuditContextError.Cancelled:
      return AuditReceiptResult[CheckedAuditBatch](status: AuditReceiptError.Cancelled)
    if context.error != AuditContextError.None:
      return AuditReceiptResult[CheckedAuditBatch](status: AuditReceiptError.ContextFailure,
          contextReason: context)
    let checked = qualifyInitialAudit(context.value, claim, limits.proof)
    if checked.error != AuditValidationError.None:
      return AuditReceiptResult[CheckedAuditBatch](status: AuditReceiptError.ProofFailure,
          proofReason: checked)
    records[ordinal] = checked.value
  if control.stopped: return AuditReceiptResult[CheckedAuditBatch](
      status: AuditReceiptError.Cancelled)
  AuditReceiptResult[CheckedAuditBatch](status: AuditReceiptError.None,
    completed: CheckedAuditBatch(data: AnnouncementData(records: records)))
