# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Collect genuine CE134 responses under the managed CPU lease; private targets bind transport identities to the signed source assignment.
## Two/three unique verified credentials can produce a canonical CE135 payload; this module does not schedule its distribution.
import ./[work_signer, work_duty, work_eligibility]
import ../codec/[bounded, guarantees, assurances]
import ../codec/state/safrole
import ../state/computed/guarantee
import ../crypto/primitives

type
  WorkGuaranteeError* {.pure.} = enum ## Failed/default outcomes contain no partially accepted credential or guarantee owner.
    Uninitialized, None, InvalidSource, InvalidTarget, InvalidPeer, InvalidMessage,
    WrongReport, InvalidSignature, Duplicate, InsufficientCredentials, LimitExceeded, CodecFailure
  WorkShareTarget* = object ## All fields are private fixed copies minted only from an actual contribution's complete fresh-source cohort.
    ready: bool
    member: WorkParticipant
    message: array[45, byte]
    root: array[32, byte]
    info: WorkEligibilityInfo
  WorkGuaranteeData = ref object ## Immutable collection versions retain the original genuine local contribution and copied peer credentials.
    local: SignedWorkContribution
    message: array[45, byte]
    root: array[32, byte]
    info: WorkEligibilityInfo
    credentials: array[3, GuaranteeCredential]
    count: int
  WorkGuaranteeRound* = object ## Public callers cannot attach an arbitrary credential list or replace the locally signed source.
    data: nil WorkGuaranteeData
  CollectedGuaranteeData = ref object ## Canonical complete payload and computation provenance share one private acyclic lifetime.
    round: WorkGuaranteeData
    wire: seq[byte]
  CollectedWorkGuarantee* = object ## A raw structurally valid Guarantee cannot manufacture this verified collection capability.
    data: nil CollectedGuaranteeData
  WorkGuaranteeResult*[T] = object ## Only selected complete success exposes an owner; codec failures preserve their genuine cause.
    case status: WorkGuaranteeError
    of None: completed: T
    of CodecFailure: codecReason: GuaranteeError
    else: discard # No failed branch carries an accepted prefix.
func error*[T](outcome: WorkGuaranteeResult[T]): WorkGuaranteeError =
  ## Inspect a reason without writable result alternatives.
  outcome.status
func value*[T](outcome: WorkGuaranteeResult[T]): T {.requires: outcome.status ==
    WorkGuaranteeError.None.} =
  ## Extract only a successful target, immutable round, complete guarantee or detached byte payload.
  outcome.completed
func codecError*[T](outcome: WorkGuaranteeResult[T]): GuaranteeError {.requires: outcome.status ==
    WorkGuaranteeError.CodecFailure.} =
  ## Only an actual failed structural codec operation has this child.
  outcome.codecReason
func valid*(target: WorkShareTarget): bool =
  ## Defaults carry no request recipient or response-verification authority.
  target.ready
func participant*(target: WorkShareTarget): WorkParticipant {.requires: target.ready.} =
  ## Return an independently mutable full record, preserving its exact original nominal ordinal.
  target.member
proc sharingTarget*(contribution: SignedWorkContribution, position: int): WorkGuaranteeResult[
    WorkShareTarget] =
  ## Execute with exclusive graph ownership; neither a caller index nor packet key supplies assignment authority.
  let info = contribution.contributionInfo
  if info.error != WorkSignerError.None:
    return WorkGuaranteeResult[WorkShareTarget](status: WorkGuaranteeError.InvalidSource)
  let duty = contribution.contributionDuty.value
  let selected = duty.participantAt(position)
  if selected.error != WorkDutyError.None:
    return WorkGuaranteeResult[WorkShareTarget](status: WorkGuaranteeError.InvalidTarget)
  if uint16(selected.value.index) == uint16(info.value.validator):
    return WorkGuaranteeResult[WorkShareTarget](status: WorkGuaranteeError.InvalidTarget)
  if not workRecipient(selected.value.validator.ed25519, duty.observedTime).valid:
    return WorkGuaranteeResult[WorkShareTarget](status: WorkGuaranteeError.InvalidTarget)
  let message = array[45, byte](contribution.contributionTranscript.value.computedGuaranteeMessage.value)
  WorkGuaranteeResult[WorkShareTarget](status: WorkGuaranteeError.None,
    completed: WorkShareTarget(ready: true, member: selected.value, message: message,
      root: array[32, byte](duty.sourceRoot), info: info.value))
proc beginWorkGuarantee*(contribution: SignedWorkContribution): WorkGuaranteeResult[
    WorkGuaranteeRound] =
  ## Begin with exactly the original signer-produced credential; copying public facts cannot begin an accepted collection.
  let info = contribution.contributionInfo
  if info.error != WorkSignerError.None:
    return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.InvalidSource)
  let message = array[45, byte](contribution.contributionTranscript.value.computedGuaranteeMessage.value)
  var credentials = default(array[3, GuaranteeCredential])
  credentials[0] = contribution.contributionCredential.value
  let duty = contribution.contributionDuty.value
  WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.None,
    completed: WorkGuaranteeRound(data: WorkGuaranteeData(local: contribution, message: message,
        root: array[32, byte](duty.sourceRoot),
      info: info.value, credentials: credentials, count: 1)))
proc credentialCount*(round: WorkGuaranteeRound): int =
  ## Call only while owning the graph lease; a default collection has no implicit all-zero local signature.
  let data = round.data
  if data == nil: return 0
  data.count
func targetMatches(target: WorkShareTarget, data: WorkGuaranteeData): bool =
  ## Fixed report/slot/core/head/root bindings reject targets issued for a different report or complete qualification source.
  if not target.ready or target.message != data.message: return false
  if target.root != data.root: return false
  if uint32(target.info.slot) != uint32(data.info.slot): return false
  if uint64(target.info.core) != uint64(data.info.core): return false
  let originalHead = array[32, byte](data.info.head)
  let targetHead = array[32, byte](target.info.head)
  originalHead == targetHead
proc addWorkResponse*(round: WorkGuaranteeRound, target: WorkShareTarget,
    transportIdentity: StateEdKey,

reply: openArray[byte]): WorkGuaranteeResult[WorkGuaranteeRound] =
  ## Verify on one managed CPU lease after exact native response FIN; callbacks must never invoke cryptography here.
  let data = round.data
  if data == nil:
    return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.InvalidSource)
  if not targetMatches(target, data):
    return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.InvalidTarget)
  let actualIdentity = array[32, byte](transportIdentity)
  let assignedIdentity = array[32, byte](target.member.validator.ed25519)
  if actualIdentity != assignedIdentity:
    return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.InvalidPeer)
  if reply.len != 96:
    return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.InvalidMessage)
  for ordinal in 0..<data.count:
    # A repeated original validator position can never increase the credential threshold.
    if uint16(data.credentials[ordinal].validator) == uint16(target.member.index):
      return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.Duplicate)
  if data.count >= 3:
    return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.LimitExceeded)
  for octet in 0..<32:
    # The exact original report hash precedes the peer signature, without a second hash or timeslot in the signing domain.
    if reply[octet] != data.message[13+octet]:
      return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.WrongReport)
  var signature = default(array[64, byte])
  for octet in 0..<64: signature[octet] = reply[32+octet]
  if not verify(EdPublicKey(assignedIdentity), EdSignature(signature), data.message):
    return WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.InvalidSignature)
  var credentials = data.credentials
  credentials[data.count] = GuaranteeCredential(validator: target.member.index,
    signature: GuaranteeSignature(signature))
  WorkGuaranteeResult[WorkGuaranteeRound](status: WorkGuaranteeError.None,
    completed: WorkGuaranteeRound(data: WorkGuaranteeData(local: data.local, message: data.message,
      root: data.root,
      info: data.info, credentials: credentials, count: data.count+1)))
proc collectWorkGuarantee*(round: WorkGuaranteeRound, maximum: ByteLimit): WorkGuaranteeResult[
    CollectedWorkGuarantee] =
  ## Structural output budgets are independent of credential authority; this step does not promise next-block inclusion or assurance retention.
  let data = round.data
  if data == nil:
    return WorkGuaranteeResult[CollectedWorkGuarantee](status: WorkGuaranteeError.InvalidSource)
  if data.count < 2:
    return WorkGuaranteeResult[CollectedWorkGuarantee](
        status: WorkGuaranteeError.InsufficientCredentials)
  var credentials = data.credentials
  for current in 1..<data.count:
    # At most three values are insertion-sorted into the GP's strict ascending original-index order.
    var position = current
    while position > 0:
      if uint16(credentials[position-1].validator) < uint16(credentials[position].validator): break
      let saved = credentials[position]
      credentials[position] = credentials[position-1]
      credentials[position-1] = saved
      dec position
  let duty = data.local.contributionDuty.value
  let config = GuaranteeConfig(cores: duty.coreCapacity,
    validators: ValidatorCount(uint16(duty.shardCount)), maxBytes: maximum)
  let encoded = encodeGuaranteeValue(Guarantee(report: data.local.contributionReport.value,
    slot: data.info.slot, credentials: credentials, credentialCount: data.count), config)
  if encoded.error != GuaranteeError.None:
    return WorkGuaranteeResult[CollectedWorkGuarantee](status: WorkGuaranteeError.CodecFailure,
      codecReason: encoded.error)
  WorkGuaranteeResult[CollectedWorkGuarantee](status: WorkGuaranteeError.None,
    completed: CollectedWorkGuarantee(data: CollectedGuaranteeData(round: data,
        wire: encoded.value)))
proc guaranteePayload*(guarantee: CollectedWorkGuarantee): WorkGuaranteeResult[seq[byte]] =
  ## Copy the exact complete CE135 payload without a stream selector or E4 prefix; mutable returned bytes cannot alter the verified owner.
  let data = guarantee.data
  if data == nil: return default(WorkGuaranteeResult[seq[byte]])
  var bytes = newSeq[byte](data.wire.len)
  for index in 0..<bytes.len: bytes[index] = data.wire[index]
  WorkGuaranteeResult[seq[byte]](status: WorkGuaranteeError.None, completed: bytes)
