# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private immutable local signer ownership matches the configured TLS identity; no raw seed or arbitrary-message signing API escapes.
import ./identity
import ./[audit_evaluation, audit_origin, audit_context, audits]
import ../codec/disputes
import ./availability_proof
import ./[assurance_possession, assurance_store, assurance_record, assurance_duty]
import ../chain/genesis
import ../crypto/assurance_context
import ../codec/assurances
import ./[work_eligibility, work_duty]
import ../codec/[guarantees, report_owned]
import ../state/computed/guarantee
import ../state/computed/report
import ../crypto/primitives
import ../quic/transport
import ../codec/bounded
import ../codec/state/safrole
import ../lib/atomic/file

type
  WorkSignerError* {.pure.} = enum ## Failed/default imports expose no signer or identity.
    Uninitialized, None, InvalidPath, CertificateFailure, ReadFailure, KeyFailure,
      KeyAllocationFailure, CryptoFailure, IdentityMismatch, InvalidEligibility, RetentionFailure
  WorkSignerData = ref object ## Only private seed ownership survives startup; the final EdSeed release wipes its own storage.
    seed: EdSeed
    identity: StateEdKey
  WorkSigner* = object ## Caller cannot obtain a mutable clearable seed alias; managed jobs must freeze this private owner until exact collection/join.
    data: nil WorkSignerData
  WorkContributionData = ref object ## A single real signature remains bound to the private eligible report, never a fully guaranteed report.
    eligible: EligibleWorkGuarantee
    credential: GuaranteeCredential
    available: GuarantorAvailability
  SignedWorkContribution* = object ## No caller-issued signature or copied eligibility facts can construct this owner.
    data: nil WorkContributionData
  WorkSignerResult*[T] = object ## Only complete success carries an owner or copied public identity; genuine children retain selected reasons.
    case status: WorkSignerError
    of None: completed: T
    of CertificateFailure: certificateReason: CertificateIdentityError
    of ReadFailure: readReason: AtomicFileError
    of CryptoFailure: cryptoReason: CryptoError
    of RetentionFailure: retentionReason: AvailabilityTransferResult[GuarantorAvailability]
    else: discard # No partial private key survives a local refusal.
type
  AssuranceSigningError* {.pure.} = enum ## Failed signing exposes no reusable possession result, signature prefix or private-key alias.
    Uninitialized, None, InvalidSigner, PossessionFailure, ContextFailure, CryptoFailure,
      Cancelled, StaleSource, LimitExceeded
  SignedAssuranceData = ref object ## Source-free immutable ownership retains only exact fresh-check facts and the one real Ed25519 signature.
    info: AssurancePossessionInfo
    signature: AssuranceSignature
  SignedAssurance* = object ## Only fresh stored verification and private signing in this module constructs a complete assurance.
    data: nil SignedAssuranceData
  AssuranceSigningResult*[T] = object ## Every actual failed proof, transcript or signing primitive preserves its selected reason alone.
    case status: AssuranceSigningError
    of None: completed: T
    of PossessionFailure: possessionReason: AssurancePossessionResult[AssurancePossessionInfo]
    of ContextFailure: contextReason: AssuranceContextError
    of CryptoFailure: cryptoReason: CryptoError
    else: discard # Default/simple failure cannot expose an accepted signature or unrelated successful child.
func error*[T](outcome: AssuranceSigningResult[T]): AssuranceSigningError =
  ## Inspect the selected signing/refusal branch before any guarded extraction.
  outcome.status
func value*[T](outcome: AssuranceSigningResult[T]): T {.requires: outcome.status ==
    AssuranceSigningError.None.} =
  ## Only a fully completed signature or detached wire payload is accessible.
  outcome.completed
func possessionError*[T](outcome: AssuranceSigningResult[T]): AssurancePossessionResult[
    AssurancePossessionInfo] {.requires: outcome.status ==
    AssuranceSigningError.PossessionFailure.} =
  ## Preserve complete source, aggregate-work and durability failures without a signed prefix.
  outcome.possessionReason
func contextError*[T](outcome: AssuranceSigningResult[
    T]): AssuranceContextError {.requires: outcome.status ==
    AssuranceSigningError.ContextFailure.} =
  ## Retain the actual canonical fixed-bitfield transcript refusal.
  outcome.contextReason
func cryptoError*[T](outcome: AssuranceSigningResult[T]): CryptoError {.requires: outcome.status ==
    AssuranceSigningError.CryptoFailure.} =
  ## A failed maintained Ed25519 provider cannot become a default successful signature.
  outcome.cryptoReason
func assuranceSigningFailure*[T](reason: AssuranceSigningError): AssuranceSigningResult[
    T] {.requires: reason notin {AssuranceSigningError.None,
    AssuranceSigningError.PossessionFailure, AssuranceSigningError.ContextFailure,
    AssuranceSigningError.CryptoFailure}.} =
  ## Host publication gates may create only payload-free simple refusals, never a successful signature or fabricated child.
  AssuranceSigningResult[T](status: reason)
func valid*(assurance: SignedAssurance): bool =
  ## A default handle grants no signature, source tag or wire prefix.
  assurance.data != nil
func sameAssurance*(left, right: SignedAssurance): bool =
  ## Compare only actual private signature-owner identity; a retained old signature cannot become the newly authorized Services publication after restart.
  left.data != nil and left.data == right.data
proc assuranceInfo*(assurance: SignedAssurance): AssuranceSigningResult[AssurancePossessionInfo] =
  ## Copy fixed source/bitfield facts without sharing any private signer or stored record graph.
  let data = assurance.data
  if data == nil: return default(AssuranceSigningResult[AssurancePossessionInfo])
  AssuranceSigningResult[AssurancePossessionInfo](status: AssuranceSigningError.None,
      completed: data.info)
proc matches*(assurance: SignedAssurance, source: BlockSnapshotResult): bool =
  ## A different complete posterior root revokes publication even when the sealed anchor header is unchanged.
  let data = assurance.data
  if data == nil or source.error != GenesisError.None: return false
  array[32, byte](data.info.duty.anchor) == array[32, byte](source.value.blockHash) and
    array[32, byte](data.info.duty.root) == array[32, byte](source.value.stateRoot)
proc assuranceBytes*(assurance: SignedAssurance, source: BlockSnapshotResult,
    maximum: ByteLimit): AssuranceSigningResult[seq[byte]] =
  ## CE141 contains exactly anchor, fixed LSB-first bitfield and signature, with no validator ordinal; fresh source and whole extent precede copying.
  let data = assurance.data
  if data == nil: return default(AssuranceSigningResult[seq[byte]])
  if not assurance.matches(source): return AssuranceSigningResult[seq[byte]](
      status: AssuranceSigningError.StaleSource)
  let width = int((uint64(data.info.duty.cores)+7) div 8)
  let length = 32+width+64
  if uint64(length) > uint64(maximum): return AssuranceSigningResult[seq[byte]](
      status: AssuranceSigningError.LimitExceeded)
  var wire = newSeq[byte](length)
  let anchor = array[32, byte](data.info.duty.anchor)
  for index in 0..<32: wire[index] = anchor[index] # Anchor precedes precisely the configured bitfield width.
  for index in 0..<width: wire[32+index] = data.info.bits.bytes[index]
  for index in 0..<64: wire[32+width+index] = data.signature.bytes[index]
  AssuranceSigningResult[seq[byte]](status: AssuranceSigningError.None, completed: wire)

func error*[T](outcome: WorkSignerResult[T]): WorkSignerError =
  ## Inspect a reason without permitting writable discriminator access.
  outcome.status
func value*[T](outcome: WorkSignerResult[T]): T {.requires: outcome.status ==
    WorkSignerError.None.} =
  ## Extract only completely imported private ownership or public copied facts.
  outcome.completed
func certificateError*[T](outcome: WorkSignerResult[
    T]): CertificateIdentityError {.requires: outcome.status ==
    WorkSignerError.CertificateFailure.} =
  ## Retain the exact bounded leaf-certificate refusal.
  outcome.certificateReason
func readError*[T](outcome: WorkSignerResult[T]): AtomicFileError {.requires: outcome.status ==
    WorkSignerError.ReadFailure.} =
  ## Retain the exact bounded private-file read refusal.
  outcome.readReason
func cryptoError*[T](outcome: WorkSignerResult[T]): CryptoError {.requires: outcome.status ==
    WorkSignerError.CryptoFailure.} =
  ## Preserve the actual private seed/public-key backend refusal.
  outcome.cryptoReason
func retentionError*[T](outcome: WorkSignerResult[T]): AvailabilityTransferResult[
    GuarantorAvailability] {.requires: outcome.status == WorkSignerError.RetentionFailure.} =
  ## Expose only the actual failed pre-sign serving capture, without a signature or retained prefix.
  outcome.retentionReason
proc contributionAvailability*(contribution: SignedWorkContribution): WorkSignerResult[
    GuarantorAvailability] =
  ## Only a genuine signed contribution exposes the independent serving owner captured before its private signature.
  let data = contribution.data
  if data == nil: return WorkSignerResult[GuarantorAvailability](
      status: WorkSignerError.Uninitialized)
  WorkSignerResult[GuarantorAvailability](status: WorkSignerError.None, completed: data.available)
proc signerIdentity*(signer: WorkSigner): WorkSignerResult[StateEdKey] =
  ## Copy only public bytes; a default or refused signer carries no fabricated all-zero identity.
  let data = signer.data
  if data == nil: return WorkSignerResult[StateEdKey](status: WorkSignerError.Uninitialized)
  WorkSignerResult[StateEdKey](status: WorkSignerError.None, completed: data.identity)
func validSignerPath(path: string): bool =
  ## Bound path conversion independently from caller CLI policy and reject NUL truncation before any file operation.
  if path.len == 0 or path.len > 4096: return false
  for character in path:
    if character == char(0): return false
  true
proc loadWorkSigner*(certificate, privateKey: string): WorkSignerResult[WorkSigner] =
  ## Bounded startup reads and maintained PEM parsing never prompt or log secrets; all caller scratch is explicitly wiped.
  if not validSignerPath(certificate) or not validSignerPath(privateKey):
    return WorkSignerResult[WorkSigner](status: WorkSignerError.InvalidPath)
  let expected = certificateIdentity(certificate)
  if expected.error != CertificateIdentityError.None:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.CertificateFailure,
        certificateReason: expected.error)
  var pem = default(array[65537, byte])
  defer: clearSecret(pem)
  let loaded = readFileInto(privateKey, pem)
  if loaded.error != AtomicFileError.None:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.ReadFailure,
        readReason: loaded.error)
  if loaded.value == 0: return WorkSignerResult[WorkSigner](status: WorkSignerError.KeyFailure)
  var raw = default(array[32, byte])
  defer: clearSecret(raw)
  let parsed = parseIdentitySeed(addr pem[0], csize_t(loaded.value), addr raw[0])
  if parsed < 0: return WorkSignerResult[WorkSigner](status: WorkSignerError.KeyAllocationFailure)
  if parsed != 1:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.KeyFailure)
  let imported = importSeed(raw)
  if imported.error != CryptoError.None:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.CryptoFailure,
        cryptoReason: imported.error)
  let derived = imported.value.publicKey
  if derived.error != CryptoError.None:
    return WorkSignerResult[WorkSigner](status: WorkSignerError.CryptoFailure,
        cryptoReason: derived.error)
  if array[32, byte](derived.value) != array[32, byte](expected.value):
    return WorkSignerResult[WorkSigner](status: WorkSignerError.IdentityMismatch)
  WorkSignerResult[WorkSigner](status: WorkSignerError.None, completed: WorkSigner(data:
    WorkSignerData(seed: imported.value, identity: expected.value)))

proc contributionInfo*(contribution: SignedWorkContribution): WorkSignerResult[
    WorkEligibilityInfo] =
  ## Copy only facts belonging to an actual signer-produced contribution.
  let data = contribution.data
  if data == nil: return WorkSignerResult[WorkEligibilityInfo](
      status: WorkSignerError.Uninitialized)
  WorkSignerResult[WorkEligibilityInfo](status: WorkSignerError.None,
    completed: data.eligible.eligibilityInfo.value)
proc contributionDuty*(contribution: SignedWorkContribution): WorkSignerResult[WorkDuty] =
  ## Only an actual signed owner exposes its original fresh-source cohort; copied public facts cannot replace it.
  let data = contribution.data
  if data == nil: return default(WorkSignerResult[WorkDuty])
  let selected = data.eligible.eligibleDuty
  if selected.error != WorkEligibilityError.None:
    return WorkSignerResult[WorkDuty](status: WorkSignerError.InvalidEligibility)
  WorkSignerResult[WorkDuty](status: WorkSignerError.None, completed: selected.value)
proc contributionCredential*(contribution: SignedWorkContribution): WorkSignerResult[
    GuaranteeCredential] =
  ## Return the original nominal roster index and ordinary Ed25519 signature together.
  let data = contribution.data
  if data == nil: return WorkSignerResult[GuaranteeCredential](
      status: WorkSignerError.Uninitialized)
  WorkSignerResult[GuaranteeCredential](status: WorkSignerError.None, completed: data.credential)
proc contributionReport*(contribution: SignedWorkContribution): WorkSignerResult[OwnedReport] =
  ## Share the exact immutable eligible report for later multi-guarantor assembly.
  let data = contribution.data
  if data == nil: return WorkSignerResult[OwnedReport](status: WorkSignerError.Uninitialized)
  WorkSignerResult[OwnedReport](status: WorkSignerError.None,
      completed: data.eligible.eligibleReport.value)
proc contributionTranscript*(contribution: SignedWorkContribution): WorkSignerResult[
    ComputedGuaranteeTranscript] =
  ## Retain the exact computation and bundle provenance, never a caller replacement.
  let data = contribution.data
  if data == nil: return WorkSignerResult[ComputedGuaranteeTranscript](
      status: WorkSignerError.Uninitialized)
  WorkSignerResult[ComputedGuaranteeTranscript](status: WorkSignerError.None,
    completed: data.eligible.eligibleTranscript.value)
proc signWorkContribution*(signer: WorkSigner,
    eligible: EligibleWorkGuarantee, retention: AvailabilityMerkleLimits,
    existing: openArray[GuarantorAvailability] = []): WorkSignerResult[
        SignedWorkContribution] =
  ## Sign only a complete source-qualified report matching this actual TLS key; execute under the managed graph lease.
  ## The runtime must freeze every signer/capability alias through exact worker collection or joined shutdown.
  let data = signer.data
  if data == nil: return WorkSignerResult[SignedWorkContribution](
      status: WorkSignerError.Uninitialized)
  let info = eligible.eligibilityInfo
  if info.error != WorkEligibilityError.None:
    return WorkSignerResult[SignedWorkContribution](status: WorkSignerError.InvalidEligibility)
  if array[32, byte](data.identity) != array[32, byte](info.value.identity):
    return WorkSignerResult[SignedWorkContribution](status: WorkSignerError.IdentityMismatch)
  let source = eligible.eligibleTranscript.value.computedGuaranteeReport.value.computedReportSource.value
  let retained = retainGuarantorAvailability(source, retention, existing)
  if retained.error != AvailabilityTransferError.None:
    return WorkSignerResult[SignedWorkContribution](status: WorkSignerError.RetentionFailure,
      retentionReason: retained)
  let message = array[45, byte](eligible.eligibleMessage.value)
  let signature = data.seed.sign(message)
  if signature.error != CryptoError.None:
    return WorkSignerResult[SignedWorkContribution](status: WorkSignerError.CryptoFailure,
      cryptoReason: signature.error)
  WorkSignerResult[SignedWorkContribution](status: WorkSignerError.None,
    completed: SignedWorkContribution(data: WorkContributionData(eligible: eligible,
      available: retained.value,
      credential: GuaranteeCredential(validator: info.value.validator,
        signature: GuaranteeSignature(array[64, byte](signature.value))))))

proc signStoredAssurance*(signer: WorkSigner, owner: var AssuranceStore,
    source: BlockSnapshotResult, chain: AssuranceChainId, requested: AssuranceBits,
    now: AssuranceTime, limits: AssurancePossessionLimits,
    control = default(AssuranceScanControl)): AssuranceSigningResult[SignedAssurance] =
  ## Execute within one fixed-owner/source/key lease: reverify and durably renew every selected local coordinate before the only private signature attempt.
  let data = signer.data
  if data == nil: return AssuranceSigningResult[SignedAssurance](
      status: AssuranceSigningError.InvalidSigner)
  let possessed = qualifyStoredAssurance(owner, source, chain, data.identity, requested, now,
      limits, control)
  if possessed.error != AssurancePossessionError.None:
    return AssuranceSigningResult[SignedAssurance](status: AssuranceSigningError.PossessionFailure,
        possessionReason: possessed)
  if control.stopped: return AssuranceSigningResult[SignedAssurance](
      status: AssuranceSigningError.Cancelled)
  let info = possessed.value
  let message = assuranceMessage(AssuranceParent(array[32, byte](info.duty.anchor)), info.bits,
      info.duty.cores)
  if message.error != AssuranceContextError.None:
    return AssuranceSigningResult[SignedAssurance](status: AssuranceSigningError.ContextFailure,
        contextReason: message.error)
  if control.stopped: return AssuranceSigningResult[SignedAssurance](
      status: AssuranceSigningError.Cancelled)
  let signed = data.seed.sign(array[45, byte](message.value))
  if signed.error != CryptoError.None:
    return AssuranceSigningResult[SignedAssurance](status: AssuranceSigningError.CryptoFailure,
        cryptoReason: signed.error)
  AssuranceSigningResult[SignedAssurance](status: AssuranceSigningError.None,
    completed: SignedAssurance(data: SignedAssuranceData(info: info,
      signature: AssuranceSignature(bytes: array[64, byte](signed.value)))))


type
  SignedAuditJudgment* = object ## Source-free private construction records a real signature and fixed original facts; no full state, evaluation or key alias leaves the worker.
    ready: bool
    record: AuditJudgment
    info: AuditEvaluationInfo
  AuditSigningError* {.pure.} = enum ## No failure or cancellation exposes a signed prefix or an evaluation/key alias.
    Uninitialized, None, InvalidSigner, InvalidEvaluation, InvalidValidator, IdentityMismatch,
    Cancelled, CryptoFailure
  AuditSigningResult*[T] = object ## Genuine primitive failure retains only its selected cause.
    case status: AuditSigningError
    of None: completed: T
    of CryptoFailure: cryptoReason: CryptoError
    else: discard                 # A reason alone cannot publish a judgment.
func error*[T](outcome: AuditSigningResult[T]): AuditSigningError =
  ## Select the actual reason before extracting completed public output.
  outcome.status
func value*[T](outcome: AuditSigningResult[T]): T {.requires: outcome.status ==
    AuditSigningError.None.} =
  ## Return source-free signed ownership only after complete private signing.
  outcome.completed
func cryptoError*[T](outcome: AuditSigningResult[T]): CryptoError {.requires: outcome.status ==
    AuditSigningError.CryptoFailure.} =
  ## A failed maintained signing call has no signature or secret payload.
  outcome.cryptoReason
func valid*(judgment: SignedAuditJudgment): bool =
  ## Default records never represent an actual signed judgment.
  judgment.ready
func signedAuditInfo*(judgment: SignedAuditJudgment): AuditEvaluationInfo {.requires: judgment.ready.} =
  ## Detached facts identify the actual completed original evaluation without granting execution or raw signing authority.
  judgment.info
func judgmentRecord*(judgment: SignedAuditJudgment): AuditJudgment {.requires: judgment.ready.} =
  ## Copy one fixed complete CE145 record; caller edits cannot change this private signed owner.
  judgment.record
proc signAuditJudgment*(signer: WorkSigner, evaluation: AuditEvaluation,
    validator: StateValidatorIndex, control: AssuranceScanControl = default(
        AssuranceScanControl)): AuditSigningResult[SignedAuditJudgment] =
  ## Services selects its retained private evaluation before lending the key. Original prior-C8 ordinal/key and pinned GP domain bind the actual validity and whole report hash; no arbitrary message or caller boolean is accepted.
  let data = signer.data
  if data == nil: return AuditSigningResult[SignedAuditJudgment](
      status: AuditSigningError.InvalidSigner)
  if not evaluation.valid: return AuditSigningResult[SignedAuditJudgment](
      status: AuditSigningError.InvalidEvaluation)
  if control.stopped: return AuditSigningResult[SignedAuditJudgment](
      status: AuditSigningError.Cancelled)
  let origin = evaluation.evaluationOrigin.value
  let context = origin.originContext.value
  let facts = context.contextInfo.value
  if uint64(validator) >= uint64(facts.auditors):
    return AuditSigningResult[SignedAuditJudgment](status: AuditSigningError.InvalidValidator)
  let member = context.auditorAt(int(uint64(validator))).value
  if array[32, byte](member.ed25519) != array[32, byte](data.identity):
    return AuditSigningResult[SignedAuditJudgment](status: AuditSigningError.IdentityMismatch)
  let info = evaluation.evaluationInfo.value
  let domain = if info.positive: "jam_valid" else: "jam_invalid"
  var message = default(array[43, byte])
  for ordinal in 0..<domain.len: message[ordinal] = byte(domain[ordinal])
  for ordinal in 0..<32: message[domain.len+ordinal] = array[32, byte](info.reportHash)[ordinal]
  if control.stopped: return AuditSigningResult[SignedAuditJudgment](
      status: AuditSigningError.Cancelled)
  let signed = data.seed.sign(message.toOpenArray(0, domain.len+31))
  if signed.error != CryptoError.None: return AuditSigningResult[SignedAuditJudgment](
      status: AuditSigningError.CryptoFailure, cryptoReason: signed.error)
  if control.stopped: return AuditSigningResult[SignedAuditJudgment](
      status: AuditSigningError.Cancelled)
  var record = AuditJudgment(epoch: DisputeEpoch(info.epoch), validator: JudgeIndex(uint16(uint64(
      validator))),
    valid: info.positive, report: DisputeHash(array[32, byte](info.reportHash)),
    signature: DisputeSignature(array[64, byte](signed.value)), slot: GuaranteeSlot(0),
    credentialCount: 0, credentials: default(array[3, GuaranteeCredential]))
  if not info.positive:
    let guarantee = origin.originGuarantee.value
    record.slot = guarantee.slot
    record.credentialCount = guarantee.credentialCount
    record.credentials = guarantee.credentials
  AuditSigningResult[SignedAuditJudgment](status: AuditSigningError.None,
    completed: SignedAuditJudgment(ready: true, record: record, info: info))
