# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Initial CE144 evidence binds verified Bandersnatch output to a complete canonical audit context; public shuffle metadata alone grants no audit or private signing authority.
import ./[audits, audit_context]
import ../bandersnatch/bandersnatch
import ../codec/[assurances, disputes]
import ../codec/work/report
import ../codec/state/safrole
import ../codec/bounded
import ../crypto/primitives
import ../chain/genesis

type
  AuditProofLimits* = object ## Explicit native proof, additional BLAKE2b and transient byte ceilings apply before cryptographic work.
    proofs*, hashes*: ElementLimit
    bytes*, hashBytes*: ByteLimit
  InitialAuditSelection* = object ## Detached deterministic metadata can be constructed or changed by a caller; it is never accepted as authenticated evidence.
    count*: int
    cores*: array[10, CoreIndex]
  AuditAnnouncementInfo* = object ## Fixed verified source/ordinal facts describe one whole announcement, not canonical judgment or audited status.
    blockHash*: genesis.BlockHash
    epoch*: uint64
    validator*: JudgeIndex
    tranche*: uint32
    selected*: int
  CheckedAuditAnnouncement* = object ## Only whole source/role/proof qualification creates this private immutable capability.
    ready: bool
    context: AuditContext
    claim: AuditAnnouncement
    info: AuditAnnouncementInfo
    selected: array[10, CoreIndex]
  AuditValidationError* {.pure.} = enum ## Unsupported source interpretations and real cryptographic failures contain no accepted selected-core prefix.
    Uninitialized, None, InvalidPolicy, InvalidSource, InvalidClaim, InvalidAuditor,
    UnsupportedTranche, InvalidIndex, LimitExceeded, ProofFailure, SigningFailure, HashFailure
  AuditValidationResult*[T] = object ## Genuine selected primitive failures remain distinct from local input and resource refusals.
    case status: AuditValidationError
    of None: completed: T
    of ProofFailure: proofReason: BsResult[BsOutput]
    of SigningFailure: signingReason: BsError
    of HashFailure: hashReason: CryptoError
    else: discard # No failed/default alternative contains an accepted context or selected obligations.
func error*[T](outcome: AuditValidationResult[T]): AuditValidationError =
  ## Inspect the selected result before extracting metadata or actual child failures.
  outcome.status
func value*[T](outcome: AuditValidationResult[T]): T {.requires: outcome.status ==
    AuditValidationError.None.} =
  ## Only whole success grants public deterministic metadata or a checked source-bound announcement.
  outcome.completed
func proofError*[T](outcome: AuditValidationResult[T]): BsResult[
    BsOutput] {.requires: outcome.status == AuditValidationError.ProofFailure.} =
  ## Preserve the actual malformed/invalid/backend proof result without a successful VRF prefix.
  outcome.proofReason
func signingError*[T](outcome: AuditValidationResult[T]): BsError {.requires: outcome.status ==
    AuditValidationError.SigningFailure.} =
  ## Return the original key or signing failure.
  outcome.signingReason
func hashError*[T](outcome: AuditValidationResult[T]): CryptoError {.requires: outcome.status ==
    AuditValidationError.HashFailure.} =
  ## A failed maintained hash remains its exact primitive reason.
  outcome.hashReason
func refused[T](reason: AuditValidationError): AuditValidationResult[T] {.requires: reason notin [
    AuditValidationError.None, AuditValidationError.ProofFailure,
    AuditValidationError.SigningFailure, AuditValidationError.HashFailure].} =
  ## Ordinary refusals cannot manufacture accepted or unrelated child payloads.
  AuditValidationResult[T](status: reason)
func valid*(limits: AuditProofLimits): bool =
  ## Defaults activate no crypto; zero remaining hash capacity is a valid finite budget and is checked against actual work.
  uint64(limits.proofs) > 0 and uint64(limits.proofs) <= 1000000 and
    uint64(limits.hashes) <= 1000000 and uint64(limits.hashBytes) <= 128'u64*1024*1024 and
    uint64(limits.bytes) > 0 and uint64(limits.bytes) <= 64'u64*1024*1024
func valid*(claim: CheckedAuditAnnouncement): bool =
  ## Neither default metadata nor a public shuffle selection can stand in for a completed proof.
  claim.ready and claim.context.valid
proc announcementInfo*(claim: CheckedAuditAnnouncement): AuditValidationResult[
    AuditAnnouncementInfo] =
  ## A fixed copied observation retains no canonical graph or private-key alias.
  if not claim.valid: return refused[AuditAnnouncementInfo](AuditValidationError.Uninitialized)
  AuditValidationResult[AuditAnnouncementInfo](status: AuditValidationError.None,
      completed: claim.info)
proc announcementContext*(claim: CheckedAuditAnnouncement): AuditValidationResult[AuditContext] =
  ## The immutable checked source remains tied to this exact proof and its original available report set.
  if not claim.valid: return refused[AuditContext](AuditValidationError.Uninitialized)
  AuditValidationResult[AuditContext](status: AuditValidationError.None, completed: claim.context)
proc announcementRecord*(claim: CheckedAuditAnnouncement): AuditValidationResult[
    AuditAnnouncement] =
  ## Forwarding copies the exact verified record; it cannot alter header, validator, intent or proof bytes.
  if not claim.valid: return refused[AuditAnnouncement](AuditValidationError.Uninitialized)
  AuditValidationResult[AuditAnnouncement](status: AuditValidationError.None,
      completed: claim.claim)
proc selectedCore*(claim: CheckedAuditAnnouncement, ordinal: int): AuditValidationResult[CoreIndex] =
  ## Dense bounded selection exposes only real newly available cores selected by the authenticated proof.
  if not claim.valid: return refused[CoreIndex](AuditValidationError.Uninitialized)
  if ordinal < 0 or ordinal >= claim.info.selected: return refused[CoreIndex](
      AuditValidationError.InvalidIndex)
  AuditValidationResult[CoreIndex](status: AuditValidationError.None, completed: claim.selected[ordinal])
func selectionWork(cores: uint64): uint64 =
  ## Ten initial draws need at most two complete eight-word entropy groups, independently of the validator population.
  if cores < 10: (cores+7) div 8 else: 2'u64
func selectionFits(cores: uint64, limits: AuditProofLimits): bool =
  ## Reserve complete hash groups, their input bytes and the transient shuffle buffer.
  let hashes = selectionWork(cores)
  hashes <= uint64(limits.hashes) and hashes*36 <= uint64(limits.hashBytes) and
    uint64(limits.bytes) >= 4096
func initialTranscript(entropy: array[32, byte]): array[41, byte] =
  ## Signing and verification use the same domain and the verified header VRF output.
  result = default(array[41, byte])
  const domain = "jam_audit"
  for index, octet in domain: result[index] = byte(octet)
  for index in 0..<32: result[domain.len+index] = entropy[index]
proc initialAuditSelection*(cores: CoreCount, entropy: BsOutput,
    limits: AuditProofLimits): AuditValidationResult[InitialAuditSelection] =
  ## GP Fisher-Yates uses BLAKE2b(output || E4(group)) and LE32 draws; returned public metadata grants no proof authenticity.
  if not limits.valid: return refused[InitialAuditSelection](AuditValidationError.InvalidPolicy)
  let count = uint64(cores)
  if count == 0 or count > 341: return refused[InitialAuditSelection](
      AuditValidationError.InvalidSource)
  if not selectionFits(count, limits):
    return refused[InitialAuditSelection](AuditValidationError.LimitExceeded)
  var remaining = default(array[341, uint16])
  for index in 0..<int(count):
    remaining[index] = uint16(index) # Original active-core positions are never compressed by whether a report became available.
  let draws = int(min(count, 10'u64))
  var selected = InitialAuditSelection(count: draws)
  var input = default(array[36, byte])
  let seed = array[32, byte](entropy)
  for index in 0..<32: input[index] = seed[index] # No dollar sign, domain, length or terminator is part of entropy expansion.
  var digest = default(array[32, byte])
  for ordinal in 0..<draws:
    # The selected prefix is identical to shuffling the entire q vector; unused draws need no extra hashing or storage.
    if ordinal mod 8 == 0:
      let group = uint32(ordinal div 8)
      for index in 0..<4: input[32+index] = byte((group shr (8*index)) and 255)
      let hashed = blake2b256(input)
      if hashed.error != CryptoError.None:
        return AuditValidationResult[InitialAuditSelection](
            status: AuditValidationError.HashFailure, hashReason: hashed.error)
      digest = array[32, byte](hashed.value)
    var draw = 0'u32
    for index in 0..<4: draw = draw or (uint32(digest[(ordinal mod 8)*4+index]) shl (8*index))
    let position = int(draw mod uint32(int(count)-ordinal))
    selected.cores[ordinal] = CoreIndex(remaining[position])
    remaining[position] = remaining[int(count)-ordinal-1]
  AuditValidationResult[InitialAuditSelection](status: AuditValidationError.None,
      completed: selected)
proc initialAuditor(context: AuditContext, ordinal: JudgeIndex): AuditValidationResult[BsPublicKey] =
  ## Resolve the active key at the claimed original prior-roster position.
  let source = context.contextInfo.value
  if uint64(uint16(ordinal)) >= uint64(source.auditors):
    return refused[BsPublicKey](AuditValidationError.InvalidAuditor)
  let member = context.auditorAt(int(uint16(ordinal))).value
  if array[32, byte](member.ed25519) == array[32, byte](nullValidator().ed25519) or
      array[32, byte](member.ed25519) == default(array[32, byte]):
    return refused[BsPublicKey](AuditValidationError.InvalidAuditor)
  AuditValidationResult[BsPublicKey](status: AuditValidationError.None,
    completed: BsPublicKey(array[32, byte](member.bandersnatch)))
proc qualifyInitialAudit*(context: AuditContext, claim: AuditAnnouncement,
    limits: AuditProofLimits): AuditValidationResult[CheckedAuditAnnouncement] =
  ## Canonical source, original prior C8 member and exact initial transcript are checked before any obligation is returned.
  if not limits.valid: return refused[CheckedAuditAnnouncement](AuditValidationError.InvalidPolicy)
  if not context.valid: return refused[CheckedAuditAnnouncement](AuditValidationError.InvalidSource)
  let source = context.contextInfo.value
  let cores = uint64(source.cores)
  if cores == 0 or cores > 341 or source.auditors < 3 or source.auditors > 1023:
    return refused[CheckedAuditAnnouncement](AuditValidationError.InvalidSource)
  if array[32, byte](claim.header) != array[32, byte](source.blockHash):
    return refused[CheckedAuditAnnouncement](AuditValidationError.InvalidClaim)
  if claim.intent != AuditIntent.Initial:
    return refused[CheckedAuditAnnouncement](AuditValidationError.UnsupportedTranche) # The later-tranche source discrepancy requires an explicit normative decision; no format guessing occurs.
  let auditor = initialAuditor(context, claim.validator)
  if auditor.error != AuditValidationError.None:
    return refused[CheckedAuditAnnouncement](auditor.error)
  if not selectionFits(cores, limits):
    return refused[CheckedAuditAnnouncement](AuditValidationError.LimitExceeded)
  let checked = verify(auditor.value, BsSignature(array[96, byte](claim.proof)),
      initialTranscript(source.entropy), [])
  if checked.error != BsError.None:
    return AuditValidationResult[CheckedAuditAnnouncement](
        status: AuditValidationError.ProofFailure, proofReason: checked)
  let shuffled = initialAuditSelection(source.cores, checked.value, limits)
  if shuffled.error == AuditValidationError.HashFailure:
    return AuditValidationResult[CheckedAuditAnnouncement](status: AuditValidationError.HashFailure,
        hashReason: shuffled.hashError)
  if shuffled.error != AuditValidationError.None: return refused[CheckedAuditAnnouncement](shuffled.error)
  var selected = default(array[10, CoreIndex])
  var count = 0
  for ordinal in 0..<source.reports:
    # The full q vector is shuffled before empty positions are filtered; source report order provides deterministic detached output.
    let core = context.availableCore(ordinal).value
    var required = false
    for chosen in 0..<shuffled.value.count:
      if uint64(core) == uint64(shuffled.value.cores[chosen]): required = true
    if required:
      if count == selected.len: return refused[CheckedAuditAnnouncement](
          AuditValidationError.InvalidSource)
      selected[count] = core
      inc count
  AuditValidationResult[CheckedAuditAnnouncement](status: AuditValidationError.None,
    completed: CheckedAuditAnnouncement(ready: true, context: context, claim: claim,
      info: AuditAnnouncementInfo(blockHash: source.blockHash, epoch: source.epoch,
        validator: claim.validator, tranche: 0, selected: count), selected: selected))
proc produceInitialAudit*(context: AuditContext, ordinal: JudgeIndex, key: BsKey,
    limits: AuditProofLimits): AuditValidationResult[CheckedAuditAnnouncement] =
  ## Bind the local Thin proof to a validated block and the matching original roster position.
  if not limits.valid: return refused[CheckedAuditAnnouncement](AuditValidationError.InvalidPolicy)
  if not context.valid: return refused[CheckedAuditAnnouncement](AuditValidationError.InvalidSource)
  let source = context.contextInfo.value
  let cores = uint64(source.cores)
  if cores == 0 or cores > 341 or source.auditors < 3 or source.auditors > 1023:
    return refused[CheckedAuditAnnouncement](AuditValidationError.InvalidSource)
  let auditor = initialAuditor(context, ordinal)
  if auditor.error != AuditValidationError.None:
    return refused[CheckedAuditAnnouncement](auditor.error)
  if uint64(limits.proofs) < 2 or not selectionFits(cores, limits):
    return refused[CheckedAuditAnnouncement](AuditValidationError.LimitExceeded)
  let local = key.publicKey
  if local.error != BsError.None:
    return AuditValidationResult[CheckedAuditAnnouncement](
        status: AuditValidationError.SigningFailure, signingReason: local.error)
  if array[32, byte](local.value) != array[32, byte](auditor.value):
    return refused[CheckedAuditAnnouncement](AuditValidationError.InvalidAuditor)
  let signed = sign(key, initialTranscript(source.entropy), [])
  if signed.error != BsError.None:
    return AuditValidationResult[CheckedAuditAnnouncement](
        status: AuditValidationError.SigningFailure, signingReason: signed.error)
  qualifyInitialAudit(context, AuditAnnouncement(header: AuditHeaderHash(
    array[32, byte](source.blockHash)), validator: ordinal, intent: AuditIntent.Initial,
    proof: AuditProof(array[96, byte](signed.value))), limits)
