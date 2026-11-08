# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CE141 receipt binds exact detached wire to the selected complete parent, actual authenticated peer key and every matching original roster position; qualification is not block inclusion.

import ./assurance_duty
import ./read_stream
import ../chain/[genesis, parameters]
import ../codec/[assurances, bounded]
import ../codec/state/[safrole, availability]
import ../codec/work/report
import ../crypto/[assurance_context, primitives]

type
  AssuranceDistributionLimits* = object ## Whole canonical reads/request geometry and exact wire bounds are explicit independently of native buffering.
    duty*: AssuranceDutyLimits
    wireBytes*: ByteLimit
  AssuranceDistributionError* {.pure.} = enum ## Default and failure alternatives retain no accepted assurance prefix.
    Uninitialized, None, InvalidSource, InvalidPolicy, InvalidWire, WrongAnchor, InvalidBits,
      InvalidSignature, LimitExceeded, InvalidIndex, DutyFailure, ContextFailure
  AssuranceDistributionInfo* = object ## Fixed observations record the full source and TLS key used for verification, never a current-source or block-admission capability.
    duty*: AssuranceDutyInfo
    wireBytes*: int
  DistributionData = ref object ## Immutable source-free ownership retains only copied observations, records and original indices.
    info: AssuranceDistributionInfo
    bits: AssuranceBits
    signature: AssuranceSignature
    indices: seq[ValidatorIndex]
  CheckedAssurance* = object ## Construction is private to complete source-bound signature verification.
    data: nil DistributionData
  AssuranceDistributionResult*[T] = object ## Failed canonical/transcript children remain selected without any successful wire or record.
    case status: AssuranceDistributionError
    of None: completed: T
    of DutyFailure: dutyReason: AssuranceDutyResult[AssuranceDuty]
    of ContextFailure: contextReason: AssuranceContextError
    else: discard # Simple refusal contains no partial ownership or unrelated child cause.

func error*[T](outcome: AssuranceDistributionResult[T]): AssuranceDistributionError =
  ## Inspect the immutable discriminator before guarded extraction.
  outcome.status

func value*[T](outcome: AssuranceDistributionResult[T]): T {.requires: outcome.status ==
    AssuranceDistributionError.None.} =
  ## Only full canonical and cryptographic qualification exposes a capability or copied record.
  outcome.completed

func dutyError*[T](outcome: AssuranceDistributionResult[T]): AssuranceDutyResult[
    AssuranceDuty] {.requires: outcome.status == AssuranceDistributionError.DutyFailure.} =
  ## Preserve actual canonical chapter/roster/geometry refusal.
  outcome.dutyReason

func contextError*[T](outcome: AssuranceDistributionResult[
    T]): AssuranceContextError {.requires: outcome.status ==
    AssuranceDistributionError.ContextFailure.} =
  ## Preserve actual transcript backend/configuration refusal.
  outcome.contextReason

func refused[T](reason: AssuranceDistributionError): AssuranceDistributionResult[
    T] {.requires: reason notin {AssuranceDistributionError.None,
    AssuranceDistributionError.DutyFailure, AssuranceDistributionError.ContextFailure}.} =
  ## A simple failure cannot manufacture a successful child.
  AssuranceDistributionResult[T](status: reason)

func valid*(limits: AssuranceDistributionLimits): bool =
  ## Omission cannot activate receipt or guess canonical read budgets.
  uint64(limits.wireBytes) >= 97 and uint64(limits.wireBytes) <= 139 and
    uint64(limits.duty.chapterBytes) > 0 and uint64(limits.duty.readBytes) > 0 and
    uint64(limits.duty.reports) > 0 and uint64(limits.duty.requests) > 0

func valid*(checked: CheckedAssurance): bool =
  ## A default cannot grant even an empty candidate.
  checked.data != nil

proc distributionInfo*(checked: CheckedAssurance): AssuranceDistributionResult[
    AssuranceDistributionInfo] =
  ## Detached copied facts never expose the private index sequence.
  let data = checked.data
  if data == nil: return refused[AssuranceDistributionInfo](
      AssuranceDistributionError.Uninitialized)
  AssuranceDistributionResult[AssuranceDistributionInfo](status: AssuranceDistributionError.None,
      completed: data.info)

proc matches*(checked: CheckedAssurance, source: BlockSnapshotResult): bool =
  ## An identical header with a different complete posterior map still revokes qualification.
  let data = checked.data
  if data == nil or source.error != GenesisError.None: return false
  array[32, byte](data.info.duty.anchor) == array[32, byte](source.value.blockHash) and
    array[32, byte](data.info.duty.root) == array[32, byte](source.value.stateRoot)

proc assuranceAt*(checked: CheckedAssurance, ordinal: int): AssuranceDistributionResult[Assurance] =
  ## One signature represents every actual original position of the same authenticated roster key; callers sort and freshly requalify block candidates.
  let data = checked.data
  if data == nil: return refused[Assurance](AssuranceDistributionError.Uninitialized)
  if ordinal < 0 or ordinal >= data.indices.len: return refused[Assurance](
      AssuranceDistributionError.InvalidIndex)
  AssuranceDistributionResult[Assurance](status: AssuranceDistributionError.None,
    completed: Assurance(bits: data.bits, signature: data.signature, validator: data.indices[ordinal]))

proc qualifyAssuranceDistribution*(request: ReadRequest, source: BlockSnapshotResult,
    peer: StateEdKey, limits: AssuranceDistributionLimits): AssuranceDistributionResult[
        CheckedAssurance] =
  ## Exact whole wire, canonical anchor, original peer positions and pending-core semantics precede the single real signature verification.
  if not limits.valid: return refused[CheckedAssurance](AssuranceDistributionError.InvalidPolicy)
  if source.error != GenesisError.None: return refused[CheckedAssurance](
      AssuranceDistributionError.InvalidSource)
  if not request.valid or request.kind != ReadKind.Assurance:
    return refused[CheckedAssurance](AssuranceDistributionError.InvalidWire)
  let cores = source.value.chainParameters.get(coreCount)
  if cores < 2 or cores > 341: return refused[CheckedAssurance](
      AssuranceDistributionError.InvalidSource)
  let width = (int(cores)+7) div 8
  if uint64(request.payloadLength) > uint64(limits.wireBytes):
    return refused[CheckedAssurance](AssuranceDistributionError.LimitExceeded)
  if request.payloadLength != 96+width: return refused[CheckedAssurance](
      AssuranceDistributionError.InvalidWire)
  let wire = request.payload
  let anchor = array[32, byte](source.value.blockHash)
  for index in 0..<32:
    # A sender cannot choose a different selected parent through its own anchor bytes.
    if wire[index] != anchor[index]: return refused[CheckedAssurance](
        AssuranceDistributionError.WrongAnchor)
  var bits = default(AssuranceBits)
  for index in 0..<width: bits.bytes[index] = wire[32+index]
  for core in int(cores)..<width*8:
    # Unused tail bits must never disappear when the fixed wire is decoded.
    if (bits.bytes[core div 8] and byte(1 shl (core mod 8))) != 0:
      return refused[CheckedAssurance](AssuranceDistributionError.InvalidBits)
  let captured = captureAssuranceDuty(source, peer, limits.duty)
  if captured.error != AssuranceDutyError.None:
    return AssuranceDistributionResult[CheckedAssurance](
        status: AssuranceDistributionError.DutyFailure, dutyReason: captured)
  let duty = captured.value
  let facts = duty.dutyInfo.value
  for core in 0..<int(cores):
    # Current C10 can exclude impossible possession; eventual inclusion must separately apply post-judgment assignments.
    if (bits.bytes[core div 8] and byte(1 shl (core mod 8))) != 0:
      if not duty.assignment(CoreIndex(core)).value.present:
        return refused[CheckedAssurance](AssuranceDistributionError.InvalidBits)
  let message = assuranceMessage(AssuranceParent(anchor), bits, CoreCount(cores))
  if message.error != AssuranceContextError.None:
    return AssuranceDistributionResult[CheckedAssurance](
        status: AssuranceDistributionError.ContextFailure, contextReason: message.error)
  var signature = default(AssuranceSignature)
  for index in 0..<64: signature.bytes[index] = wire[32+width+index]
  let key = importPublicKey(array[32, byte](peer))
  let credential = importSignature(signature.bytes)
  if key.error != CryptoError.None or credential.error != CryptoError.None:
    return refused[CheckedAssurance](AssuranceDistributionError.InvalidSignature)
  if not verify(key.value, credential.value, array[45, byte](message.value)):
    return refused[CheckedAssurance](AssuranceDistributionError.InvalidSignature)
  var indices = newSeq[ValidatorIndex](facts.localIndices)
  for ordinal in 0..<indices.len:
    # Preserve null gaps and all repeated original validator positions without duplicating cryptographic work.
    indices[ordinal] = duty.localIndex(ordinal).value
  AssuranceDistributionResult[CheckedAssurance](status: AssuranceDistributionError.None,
    completed: CheckedAssurance(data: DistributionData(info: AssuranceDistributionInfo(duty: facts,
      wireBytes: wire.len), bits: bits, signature: signature, indices: indices)))
