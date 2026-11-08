# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Certify standalone original-coordinate guarantee signatures under an actual guarantor plan. This nominal support capability excludes population, report-policy and inclusion admission; it cannot replace VerifiedGuaranteeCredentials in consensus consumers.

import ./guarantors
import ../codec/[bounded, guarantees, assurances, report_owned, owned, disputes]
import ../codec/work/report
import ../codec/state/safrole
import ../crypto/[primitives, guarantee]

type
  GuaranteeSupportLimits* = object ## Whole standalone wire, canonical copies, hash input and Ed25519 work have finite independent caps.
    wire*: GuaranteeConfig
    workspaceBytes*, hashBytes*: ByteLimit
    signatures*: ElementLimit
  GuaranteeSupportError* {.pure.} = enum ## No failed/default alternative contains a verified credential, partial signature prefix or inclusion certificate.
    Uninitialized, None, InvalidPolicy, LimitExceeded, StructureFailure, AssignmentFailure,
    WrongAssignment, InvalidSigner, InvalidSignature, OwnershipFailure, BackendFailure, InvalidIndex
  GuaranteeSupportInfo* = object ## Fixed copied facts describe only the exact canonical signed report and original credential count.
    report*: DisputeHash
    core*: CoreIndex
    slot*: GuaranteeSlot
    credentials*: int
    retainedBytes*: uint64
  SupportData = ref object ## Private immutable ownership retains detached canonical report bytes and fixed actual assigned routing records.
    info: GuaranteeSupportInfo
    guarantee: Guarantee
    validators: array[3, StateValidator]
  VerifiedGuaranteeSupport* = object ## A default grants neither credential support nor report/admission validity.
    data: nil SupportData
  GuaranteeSupportResult*[T] = object ## Genuine structural, assignment and ownership refusals preserve their exact selected cause.
    case status: GuaranteeSupportError
    of None: completed: T
    of StructureFailure: structureReason: GuaranteeError
    of AssignmentFailure: assignmentReason: GuarantorError
    of OwnershipFailure: ownerReason: OwnershipError
    of BackendFailure: cryptoReason: CryptoError
    else: discard # Ordinary/default failures expose no accepted source or partial output.

func error*[T](outcome: GuaranteeSupportResult[T]): GuaranteeSupportError =
  ## Inspect status before extracting complete ownership or its selected child reason.
  outcome.status

func value*[T](outcome: GuaranteeSupportResult[T]): T {.requires: outcome.status ==
    GuaranteeSupportError.None.} =
  ## Only complete report-bound signature support exposes an immutable owner or fixed facts.
  outcome.completed

func structureError*[T](outcome: GuaranteeSupportResult[
    T]): GuaranteeError {.requires: outcome.status == GuaranteeSupportError.StructureFailure.} =
  ## Preserve count/order/ordinal/report-shape refusals from the maintained canonical guarantee codec.
  outcome.structureReason

func assignmentError*[T](outcome: GuaranteeSupportResult[
    T]): GuarantorError {.requires: outcome.status == GuaranteeSupportError.AssignmentFailure.} =
  ## Missing, stale, future or out-of-roster original coordinates never become fabricated signer keys.
  outcome.assignmentReason

func ownerError*[T](outcome: GuaranteeSupportResult[
    T]): OwnershipError {.requires: outcome.status == GuaranteeSupportError.OwnershipFailure.} =
  ## Keep actual canonical encoding/detachment failure distinct from report invalidity.
  outcome.ownerReason

func cryptoError*[T](outcome: GuaranteeSupportResult[T]): CryptoError {.requires: outcome.status ==
    GuaranteeSupportError.BackendFailure.} =
  ## A failed message hash cannot expose a temporary zero transcript.
  outcome.cryptoReason

func valid*(limits: GuaranteeSupportLimits): bool =
  ## The codec validates detailed chain geometry; these local maxima independently bound every allocation and hash/signature operation.
  uint64(limits.wire.cores) in 2'u64..341'u64 and uint64(limits.wire.validators) in
      6'u64..1023'u64 and
    uint64(limits.wire.validators) mod 3 == 0 and
    uint64(limits.wire.maxBytes) > 0 and uint64(limits.wire.maxBytes) <= 8'u64*1024*1024 and
    uint64(limits.workspaceBytes) > 0 and uint64(limits.workspaceBytes) <= 32'u64*1024*1024 and
    uint64(limits.hashBytes) > 0 and uint64(limits.hashBytes) <= 8'u64*1024*1024 and
    uint64(limits.signatures) > 0 and uint64(limits.signatures) <= 3

func valid*(support: VerifiedGuaranteeSupport): bool =
  ## Plain copied guarantee metadata cannot initialize a signature-support owner.
  support.data != nil

proc supportInfo*(support: VerifiedGuaranteeSupport): GuaranteeSupportResult[GuaranteeSupportInfo] =
  ## Inspect detached fixed signed identity and accounting while retaining no mutable report storage.
  let data = support.data
  if data == nil: return GuaranteeSupportResult[GuaranteeSupportInfo](
      status: GuaranteeSupportError.Uninitialized)
  GuaranteeSupportResult[GuaranteeSupportInfo](status: GuaranteeSupportError.None,
      completed: data.info)

proc supportedGuarantee*(support: VerifiedGuaranteeSupport): GuaranteeSupportResult[Guarantee] =
  ## The immutable exact detached report and original slot/credentials remain distinct from full consensus admission.
  let data = support.data
  if data == nil: return GuaranteeSupportResult[Guarantee](
      status: GuaranteeSupportError.Uninitialized)
  GuaranteeSupportResult[Guarantee](status: GuaranteeSupportError.None, completed: data.guarantee)

proc supportValidator*(support: VerifiedGuaranteeSupport, ordinal: int): GuaranteeSupportResult[
    StateValidator] =
  ## Credential row ordinals return their original plan's full fixed public records, never shuffled or compressed replacement indices.
  let data = support.data
  if data == nil: return GuaranteeSupportResult[StateValidator](
      status: GuaranteeSupportError.Uninitialized)
  if ordinal < 0 or ordinal >= data.info.credentials:
    return GuaranteeSupportResult[StateValidator](status: GuaranteeSupportError.InvalidIndex)
  GuaranteeSupportResult[StateValidator](status: GuaranteeSupportError.None,
      completed: data.validators[ordinal])

proc verifyGuaranteeSupport*(value: Guarantee, plan: GuarantorPlan,
    limits: GuaranteeSupportLimits): GuaranteeSupportResult[VerifiedGuaranteeSupport] =
  ## The caller authenticates the actual plan/source. Whole shape/copy/hash/signature admission precedes key extraction, crypto and detached publication; this factory deliberately issues only the narrower support capability.
  if not limits.valid:
    return GuaranteeSupportResult[VerifiedGuaranteeSupport](
        status: GuaranteeSupportError.InvalidPolicy)
  let measured = measureGuarantee(value, limits.wire)
  if measured.error != GuaranteeError.None:
    return GuaranteeSupportResult[VerifiedGuaranteeSupport](
        status: GuaranteeSupportError.StructureFailure, structureReason: measured.error)
  let info = value.report.ownedReportInfo.value
  let length = uint64(info.consumed)
  # Wire<=8MiB and the measured complete canonical owner prove every multiplication/addition before allocation.
  if sizeof(StateValidator) > 512 or length > uint64(limits.hashBytes) or
      4*length+65536 > uint64(limits.workspaceBytes) or uint64(value.credentialCount) > uint64(
          limits.signatures):
    return GuaranteeSupportResult[VerifiedGuaranteeSupport](
        status: GuaranteeSupportError.LimitExceeded)
  var validators = default(array[3, StateValidator])
  for ordinal in 0..<value.credentialCount:
    # Slot selects the actual current/prior rotation and its independent roster population; all original coordinates survive nulls/repeated keys.
    let selected = plan.guarantorAt(value.slot, value.credentials[ordinal].validator)
    if selected.error != GuarantorError.None:
      return GuaranteeSupportResult[VerifiedGuaranteeSupport](
          status: GuaranteeSupportError.AssignmentFailure, assignmentReason: selected.error)
    if uint64(selected.value.core) != uint64(info.core):
      return GuaranteeSupportResult[VerifiedGuaranteeSupport](
          status: GuaranteeSupportError.WrongAssignment)
    let key = array[32, byte](selected.value.validator.ed25519)
    if key == default(array[32, byte]) or key == array[32, byte](nullValidator().ed25519):
      return GuaranteeSupportResult[VerifiedGuaranteeSupport](
          status: GuaranteeSupportError.InvalidSigner)
    validators[ordinal] = selected.value.validator
  var wire = newSeq[byte](info.consumed)
  let encoded = value.report.encodeOwnedReport(wire)
  if encoded.error != OwnershipError.None:
    return GuaranteeSupportResult[VerifiedGuaranteeSupport](
        status: GuaranteeSupportError.OwnershipFailure, ownerReason: encoded.error)
  let message = guaranteeMessage(wire)
  if message.error != CryptoError.None:
    return GuaranteeSupportResult[VerifiedGuaranteeSupport](
        status: GuaranteeSupportError.BackendFailure, cryptoReason: message.error)
  let bytes = array[45, byte](message.value)
  for ordinal in 0..<value.credentialCount:
    # Distinct canonical credential indices may legitimately hold the same key; the original plan, not key deduplication, defines the positions.
    let public = EdPublicKey(array[32, byte](validators[ordinal].ed25519))
    let signature = EdSignature(array[64, byte](value.credentials[ordinal].signature))
    if not verify(public, signature, bytes):
      return GuaranteeSupportResult[VerifiedGuaranteeSupport](
          status: GuaranteeSupportError.InvalidSignature)
  let detached = decodeOwnedReport(wire, uint64(limits.wire.cores))
  if detached.error != OwnershipError.None:
    return GuaranteeSupportResult[VerifiedGuaranteeSupport](
        status: GuaranteeSupportError.OwnershipFailure, ownerReason: detached.error)
  var guarantee = value
  guarantee.report = detached.value
  var hash = default(array[32, byte])
  for index in 0..<32: hash[index] = bytes[13+index]
  GuaranteeSupportResult[VerifiedGuaranteeSupport](status: GuaranteeSupportError.None,
    completed: VerifiedGuaranteeSupport(data: SupportData(guarantee: guarantee,
      validators: validators,
      info: GuaranteeSupportInfo(report: DisputeHash(hash), core: info.core, slot: value.slot,
        credentials: value.credentialCount, retainedBytes: length+65536))))
