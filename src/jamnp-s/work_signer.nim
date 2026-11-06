# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private immutable local signer ownership matches the configured TLS identity; no raw seed or arbitrary-message signing API escapes.
import ./identity
import ./availability_proof
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
