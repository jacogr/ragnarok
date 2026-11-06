# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepare one genuine original-key audit judgment and independently owned CE136 serving bytes under a single private worker lease. No full execution, evaluation or key graph escapes the complete source-free output.
import ./[audit_origin, audit_evaluation, work_signer, read_stream, assurance_store]
import ../codec/[bounded, report_owned, owned]
from ../codec/state/safrole import StateValidatorIndex

type
  AuditPublicationLimits* = object ## Complete framed report output and all temporary encoding copies are reserved before signing.
    wireBytes*, workspaceBytes*: ByteLimit
  AuditPublication* = object ## Only completed private evaluation, exact original report encoding and actual signature construct an initialized publication.
    ready: bool
    signed: SignedAuditJudgment
    report: ReadReply
  AuditPublicationError* {.pure.} = enum ## No failure or cancelled operation exposes a signature, serving prefix or private source.
    Uninitialized, None, InvalidPolicy, InvalidEvaluation, LimitExceeded, Cancelled,
    SigningFailure, EncodingFailure, ReadFailure
  AuditPublicationResult*[T] = object ## Genuine failed selected child operations retain their exact reason without a successful prefix.
    case status: AuditPublicationError
    of None: completed: T
    of SigningFailure: signingReason: AuditSigningResult[SignedAuditJudgment]
    of EncodingFailure: encodingReason: OwnershipError
    of ReadFailure: readReason: ReadError
    else: discard # Defaults and ordinary refusals carry no completed publication or unrelated child.
func error*[T](outcome: AuditPublicationResult[T]): AuditPublicationError =
  ## Inspect the selected reason before extracting complete output.
  outcome.status
func value*[T](outcome: AuditPublicationResult[T]): T {.requires: outcome.status ==
    AuditPublicationError.None.} =
  ## Success transfers detached public wire facts only after source/key borrowers retire through exact collection.
  outcome.completed
func signingError*[T](outcome: AuditPublicationResult[T]): AuditSigningResult[
    SignedAuditJudgment] {.requires: outcome.status == AuditPublicationError.SigningFailure.} =
  ## Preserve actual original-key identity, cancellation or crypto failure without a signature prefix.
  outcome.signingReason
func encodingError*[T](outcome: AuditPublicationResult[
    T]): OwnershipError {.requires: outcome.status == AuditPublicationError.EncodingFailure.} =
  ## Preserve actual complete original report encoding refusal.
  outcome.encodingReason
func readError*[T](outcome: AuditPublicationResult[T]): ReadError {.requires: outcome.status ==
    AuditPublicationError.ReadFailure.} =
  ## Preserve actual exact report request/reply framing failure.
  outcome.readReason
func valid*(limits: AuditPublicationLimits): bool =
  ## Default local policy cannot allocate output or sign anything.
  uint64(limits.wireBytes) in 4'u64..uint64(MaxReadReplyBytes) and
    uint64(limits.workspaceBytes) in 1'u64..64'u64*1024*1024
func valid*(publication: AuditPublication): bool =
  ## A default object is not an initialized empty report or a completed signature.
  publication.ready
func signedJudgment*(publication: AuditPublication): SignedAuditJudgment {.requires: publication.ready.} =
  ## Fixed signed records do not alias the private evaluator, original state or signer.
  publication.signed
proc reportReply*(publication: AuditPublication): ReadReply {.requires: publication.ready.} =
  ## Independently frozen raw serving bytes share no OwnedReport or complete-state alias with the leased input graph.
  publication.report
proc prepareAuditPublication*(signer: WorkSigner, evaluation: AuditEvaluation,
    validator: StateValidatorIndex, limits: AuditPublicationLimits,
    control: AssuranceScanControl = default(AssuranceScanControl)): AuditPublicationResult[
        AuditPublication] =
  ## Whole output/workspace admission and exact original report encoding precede the actual private original-key signature; cancellation discards every intermediate owner.
  if not limits.valid: return AuditPublicationResult[AuditPublication](
      status: AuditPublicationError.InvalidPolicy)
  if not evaluation.valid: return AuditPublicationResult[AuditPublication](
      status: AuditPublicationError.InvalidEvaluation)
  if control.stopped: return AuditPublicationResult[AuditPublication](
      status: AuditPublicationError.Cancelled)
  let origin = evaluation.evaluationOrigin.value
  let report = origin.originReport.value
  let described = report.ownedReportInfo
  if described.error != OwnershipError.None:
    return AuditPublicationResult[AuditPublication](status: AuditPublicationError.EncodingFailure,
        encodingReason: described.error)
  let length = uint64(described.value.consumed)
  if length > uint64(limits.wireBytes)-4 or 3*(length+4)+65536 > uint64(limits.workspaceBytes):
    return AuditPublicationResult[AuditPublication](status: AuditPublicationError.LimitExceeded)
  var wire = newSeq[byte](int(length)+4)
  for index in 0..<4: wire[index] = byte((uint32(length) shr (8*index)) and 255)
  let encoded = report.encodeOwnedReport(wire.toOpenArray(4, wire.len-1))
  if encoded.error != OwnershipError.None:
    return AuditPublicationResult[AuditPublication](status: AuditPublicationError.EncodingFailure,
        encodingReason: encoded.error)
  var hash: seq[byte] = @[]
  for octet in array[32, byte](evaluation.evaluationInfo.value.reportHash): hash.add(octet)
  let request = decodeReadRequest(ReadKind.Report, hash)
  if request.error != ReadError.None:
    return AuditPublicationResult[AuditPublication](status: AuditPublicationError.ReadFailure,
        readReason: request.error)
  let reply = captureReadReply(request.value, wire)
  if reply.error != ReadError.None:
    return AuditPublicationResult[AuditPublication](status: AuditPublicationError.ReadFailure,
        readReason: reply.error)
  if control.stopped: return AuditPublicationResult[AuditPublication](
      status: AuditPublicationError.Cancelled)
  let signed = signAuditJudgment(signer, evaluation, validator, control)
  if signed.error == AuditSigningError.Cancelled:
    return AuditPublicationResult[AuditPublication](status: AuditPublicationError.Cancelled)
  if signed.error != AuditSigningError.None:
    return AuditPublicationResult[AuditPublication](status: AuditPublicationError.SigningFailure,
        signingReason: signed)
  if control.stopped: return AuditPublicationResult[AuditPublication](
      status: AuditPublicationError.Cancelled)
  AuditPublicationResult[AuditPublication](status: AuditPublicationError.None,
    completed: AuditPublication(ready: true, signed: signed.value, report: reply.value))
