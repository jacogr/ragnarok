# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole CE145 receipt preparation qualifies negative support and private execution sources before publishing any source-free judgment record. Private origins remain under the managed Services lease until atomic registry installation.

import ./[judgment_claim, judgment_support, audit_origin, assurance_store, audits, work_signer]
import ../chain/[genesis, provider]
import ../codec/[bounded, report_owned]
from ../codec/state/safrole import StateEdKey

type
  JudgmentSourceInput* = object ## Raw report bytes and an explicitly selected actual retained reporting context grant no guarantee or execution authority.
    source*, membership*: genesis.BlockHash
    report*: OwnedReport
  JudgmentReceiptLimits* = object ## Whole-message aggregate child work is reserved before the first support signature or state scan.
    support*: JudgmentSupportLimits
    origin*: AuditOriginLimits
    readBytes*, workspaceBytes*, hashBytes*, retainedBytes*: ByteLimit
    hashes*, signatures*: ElementLimit
  QualifiedJudgment* = object ## Fixed original signed claims become publishable only after required support and genuine private source qualification; this is not local report truth.
    ready: bool
    record: AuditJudgment
    auditor: StateEdKey
  PreparedData = ref object ## Acyclic source-bearing output never escapes Services' exact collector; source-free records do not alias its complete maps.
    records: seq[QualifiedJudgment]
    origins: seq[AuditDisputeOrigin]
  PreparedJudgmentBatch* = object ## Only complete success owns all negative origins and every qualified original record.
    data: nil PreparedData
  JudgmentReceiptError* {.pure.} = enum ## No failure contains an accepted judgment, origin or earlier record prefix.
    Uninitialized, None, InvalidPolicy, InvalidSource, InvalidIndex, LimitExceeded, Cancelled,
    SupportFailure, OriginFailure
  JudgmentReceiptResult*[T] = object ## Only genuine failed child operations carry their selected diagnostic branch.
    case status: JudgmentReceiptError
    of None: completed: T
    of SupportFailure:
      supportReason: JudgmentSupportResult[VerifiedJudgmentSupport]
      supportOrdinal: int
    of OriginFailure:
      originReason: AuditOriginResult[AuditDisputeOrigin]
      originOrdinal: int
    else: discard # Ordinary refusals expose no unrelated child or successful prefix.

func error*[T](outcome: JudgmentReceiptResult[T]): JudgmentReceiptError =
  ## Inspect the selected reason before extracting complete ownership.
  outcome.status

func value*[T](outcome: JudgmentReceiptResult[T]): T {.requires: outcome.status ==
    JudgmentReceiptError.None.} =
  ## Source-bearing output is accessed only under its original exclusive Services lease.
  outcome.completed

func supportError*[T](outcome: JudgmentReceiptResult[T]): JudgmentSupportResult[
    VerifiedJudgmentSupport] {.requires: outcome.status == JudgmentReceiptError.SupportFailure.} =
  ## Preserve actual original guarantor qualification failure without inventing a successful subset.
  outcome.supportReason

func failedOrdinal*[T](outcome: JudgmentReceiptResult[T]): int =
  ## Only context-dependent refusals permit retry with another retained source.
  case outcome.status
  of JudgmentReceiptError.SupportFailure: outcome.supportOrdinal
  of JudgmentReceiptError.OriginFailure:
    if outcome.originReason.error in [AuditOriginError.HistoryUnavailable,
        AuditOriginError.LimitExceeded]:
      outcome.originOrdinal
    else: -1
  else: -1

func originError*[T](outcome: JudgmentReceiptResult[T]): AuditOriginResult[
    AuditDisputeOrigin] {.requires: outcome.status == JudgmentReceiptError.OriginFailure.} =
  ## Missing historical execution and full-map retention remain typed unavailable-source failures.
  outcome.originReason

func valid*(limits: JudgmentReceiptLimits): bool =
  ## Missing aggregate bounds cannot activate receipt processing; at most sixteen negative records can perform these child operations.
  limits.support.valid and limits.origin.valid and
    uint64(limits.readBytes) in 1'u64..64'u64*1024*1024 and
    uint64(limits.workspaceBytes) in 1'u64..512'u64*1024*1024 and
    uint64(limits.hashBytes) in 1'u64..256'u64*1024*1024 and
    uint64(limits.retainedBytes) in 1'u64..64'u64*1024*1024 and
    uint64(limits.hashes) in 1'u64..1048576'u64 and uint64(limits.signatures) in 1'u64..48'u64

func valid*(record: QualifiedJudgment): bool =
  ## No raw boolean or signed-but-unsupported negative claim can initialize a publishable judgment.
  record.ready

func judgmentRecord*(record: QualifiedJudgment): AuditJudgment {.requires: record.ready.} =
  ## Original signer, epoch, validity and inline support remain fixed; forwarding does not re-sign them.
  record.record

func judgmentAuditor*(record: QualifiedJudgment): StateEdKey {.requires: record.ready.} =
  ## Identify the independently authenticated original signer across admitted branch rosters.
  record.auditor

func sameJudgmentKey*(left, right: AuditJudgment, leftAuditor, rightAuditor: StateEdKey): bool =
  uint32(left.epoch) == uint32(right.epoch) and uint16(left.validator) == uint16(
      right.validator) and
    array[32, byte](left.report) == array[32, byte](right.report) and
    array[32, byte](leftAuditor) == array[32, byte](rightAuditor)

func sameJudgmentKey*(left, right: QualifiedJudgment): bool =
  left.valid and right.valid and sameJudgmentKey(left.record, right.record, left.auditor, right.auditor)

proc qualifyLocalJudgment*(signed: SignedAuditJudgment): JudgmentReceiptResult[QualifiedJudgment] =
  ## Only an actual completed private evaluation and original-key signature constructs SignedAuditJudgment; no caller validity bit becomes a publishable local judgment.
  if not signed.valid: return JudgmentReceiptResult[QualifiedJudgment](
      status: JudgmentReceiptError.InvalidSource)
  JudgmentReceiptResult[QualifiedJudgment](status: JudgmentReceiptError.None,
    completed: QualifiedJudgment(ready: true, record: signed.judgmentRecord,
        auditor: signed.judgmentAuditor))

func valid*(batch: PreparedJudgmentBatch): bool =
  ## Default output is not an initialized empty successful receipt.
  batch.data != nil

proc len*(batch: PreparedJudgmentBatch): int =
  ## Fixed occupancy inspection does not export the private sequence.
  let data = batch.data
  if data == nil: return 0
  data.records.len

proc judgmentAt*(batch: PreparedJudgmentBatch, ordinal: int): JudgmentReceiptResult[
    QualifiedJudgment] =
  ## Return a fixed detached record, never an execution source alias.
  let data = batch.data
  if data == nil: return JudgmentReceiptResult[QualifiedJudgment](
      status: JudgmentReceiptError.Uninitialized)
  if ordinal < 0 or ordinal >= data.records.len:
    return JudgmentReceiptResult[QualifiedJudgment](status: JudgmentReceiptError.InvalidIndex)
  JudgmentReceiptResult[QualifiedJudgment](status: JudgmentReceiptError.None,
      completed: data.records[ordinal])

proc negativeCount*(batch: PreparedJudgmentBatch): int =
  ## Each negative record has exactly one fully qualified private origin in original relative order.
  let data = batch.data
  if data == nil: return 0
  data.origins.len

proc negativeOriginAt*(batch: PreparedJudgmentBatch, ordinal: int): JudgmentReceiptResult[
    AuditDisputeOrigin] =
  ## Services alone follows these source-bearing aliases after exact worker retirement and before RPC resumes.
  let data = batch.data
  if data == nil: return JudgmentReceiptResult[AuditDisputeOrigin](
      status: JudgmentReceiptError.Uninitialized)
  if ordinal < 0 or ordinal >= data.origins.len:
    return JudgmentReceiptResult[AuditDisputeOrigin](status: JudgmentReceiptError.InvalidIndex)
  JudgmentReceiptResult[AuditDisputeOrigin](status: JudgmentReceiptError.None,
      completed: data.origins[ordinal])

proc prepareJudgmentReceipt*(view: ChainView, claims: SignedJudgmentBatch,
    inputs: openArray[JudgmentSourceInput], limits: JudgmentReceiptLimits,
    control: AssuranceScanControl = default(AssuranceScanControl),
    alternatives: openArray[ChainView] = []): JudgmentReceiptResult[
        PreparedJudgmentBatch] =
  ## Every negative requires an actual full-hash-bound report and original support; no partial result survives a late signature, source, quota or cancellation refusal.
  if not limits.valid: return JudgmentReceiptResult[PreparedJudgmentBatch](
      status: JudgmentReceiptError.InvalidPolicy)
  if view.fuzzOnly or not claims.valid or claims.len > 16 or inputs.len != claims.len or
      alternatives.len > 64:
    return JudgmentReceiptResult[PreparedJudgmentBatch](status: JudgmentReceiptError.InvalidSource)
  if control.stopped: return JudgmentReceiptResult[PreparedJudgmentBatch](
      status: JudgmentReceiptError.Cancelled)
  var negatives = 0'u64
  for ordinal in 0..<claims.len:
    # Every original membership root must exist in this actual Services chain, including positive claims that have no report/support lookup.
    let claim = claims.claimAt(ordinal).value
    if judgmentAuthorityView(view, alternatives, claim).bestBlock.error != GenesisError.None:
      return JudgmentReceiptResult[PreparedJudgmentBatch](
          status: JudgmentReceiptError.InvalidSource)
    if not claim.judgmentRecord.valid: inc negatives
  # Child policies have finite validated maxima and negatives<=16. Division proves whole-message work capacity without overflowing products.
  if negatives > uint64(limits.readBytes) div uint64(limits.support.readBytes) or
      negatives > uint64(limits.workspaceBytes) div uint64(limits.support.workspaceBytes) or
      negatives > uint64(limits.hashBytes) div uint64(limits.support.hashBytes) or
      negatives > uint64(limits.hashes) div uint64(limits.support.hashes) or
      negatives > uint64(limits.signatures) div 3:
    return JudgmentReceiptResult[PreparedJudgmentBatch](status: JudgmentReceiptError.LimitExceeded)
  let fixed = 4096'u64+uint64(claims.len)*2048
  if fixed > uint64(limits.retainedBytes) or negatives > (uint64(
      limits.retainedBytes)-fixed) div uint64(limits.support.retainedBytes):
    return JudgmentReceiptResult[PreparedJudgmentBatch](status: JudgmentReceiptError.LimitExceeded)
  var records = newSeq[QualifiedJudgment](claims.len)
  var origins: seq[AuditDisputeOrigin] = @[]
  for ordinal in 0..<claims.len:
    # Whole reservations precede the first signature/hash/state scan. Only complete success transfers these private owners to the collector.
    if control.stopped: return JudgmentReceiptResult[PreparedJudgmentBatch](
        status: JudgmentReceiptError.Cancelled)
    let claim = claims.claimAt(ordinal).value
    if not claim.judgmentRecord.valid:
      let membership = inputs[ordinal].membership
      var authority = default(ChainView)
      if array[32, byte](membership) == default(array[32, byte]):
        authority = judgmentAuthorityView(view, alternatives, claim)
      elif view.bestBlock.error == GenesisError.None and
          array[32, byte](view.bestBlock.value.blockHash) == array[32, byte](membership):
        authority = view
      else:
        for branch in alternatives:
          let head = branch.bestBlock
          if head.error == GenesisError.None and
              array[32, byte](head.value.blockHash) == array[32, byte](membership):
            authority = branch
            break
      let support = qualifyJudgmentSupportAt(authority, inputs[ordinal].source, claim, inputs[
          ordinal].report, limits.support, control, membership)
      if support.error == JudgmentSupportError.Cancelled:
        return JudgmentReceiptResult[PreparedJudgmentBatch](status: JudgmentReceiptError.Cancelled)
      if support.error != JudgmentSupportError.None:
        return JudgmentReceiptResult[PreparedJudgmentBatch](
            status: JudgmentReceiptError.SupportFailure, supportReason: support,
            supportOrdinal: ordinal)
      let origin = captureAuditDisputeOrigin(authority, support.value, limits.origin, control)
      if origin.error == AuditOriginError.Cancelled:
        return JudgmentReceiptResult[PreparedJudgmentBatch](status: JudgmentReceiptError.Cancelled)
      if origin.error != AuditOriginError.None:
        return JudgmentReceiptResult[PreparedJudgmentBatch](
            status: JudgmentReceiptError.OriginFailure, originReason: origin,
            originOrdinal: ordinal)
      origins.add(origin.value)
    records[ordinal] = QualifiedJudgment(ready: true, record: claim.judgmentRecord,
        auditor: claim.claimInfo.auditor.ed25519)
  if control.stopped: return JudgmentReceiptResult[PreparedJudgmentBatch](
      status: JudgmentReceiptError.Cancelled)
  JudgmentReceiptResult[PreparedJudgmentBatch](status: JudgmentReceiptError.None,
    completed: PreparedJudgmentBatch(data: PreparedData(records: move(records), origins: move(origins))))
